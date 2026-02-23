require "cgi"
require "digest/md5"
require "json"

module CmsV6
  class Client
    class Error < StandardError; end
    class UnauthorizedError < Error
      attr_reader :debug

      def initialize(message = nil, debug: nil)
        @debug = debug
        super(message)
      end
    end
    class PermissionDeniedError < Error; end
    class InvalidCredentialsError < Error; end
    class TimeoutError < Error; end
    class ServerError < Error; end

    LOGIN_PATH = "StandardApiAction_login.action".freeze
    SESSION_TTL = 25.minutes

    def initialize(connection: nil, logger: Rails.logger)
      @connection = connection || build_connection
      @logger = logger
    end

    def login(force: false, token_preference: :payload_first)
      Rails.cache.delete(session_cache_key) if force
      return session_token if !force && session_token.present?

      response, payload, token = login_with_documented_payloads(token_preference: token_preference)
      handle_login_result!(response: response, payload: payload)
      raise InvalidCredentialsError, login_error_message(payload) if token.blank?

      Rails.cache.write(session_cache_key, token, expires_in: SESSION_TTL)
      raise Error, "CMSV6 session token could not be cached" if session_token.blank?
      token
    end

    def get(path, params: {})
      request_with_refresh(path:, method: :get, params: params)
    end

    def post(path, body: {})
      request_with_refresh(path:, method: :post, body: body)
    end

    def login_diagnostic
      attempts = []
      response = nil
      payload = {}
      token = nil

      login_payloads.each do |mode, candidate|
        response = request_raw(path: LOGIN_PATH, method: :post, body: candidate, token: nil)
        payload = decode_response(response)
        token = token_from(response: response, payload: payload)
        candidates = token_candidates(response: response, payload: payload)
        attempts << {
          mode: mode,
          result: payload["result"],
          result_tip: payload["resultTip"],
          message: payload["message"],
          token_present: token.present?,
          payload_token_len: candidates[:payload_token].to_s.length,
          cookie_token_len: candidates[:cookie_token].to_s.length
        }
        break if token.present? && payload.fetch("result", 0).to_i.zero?
      end

      {
        http_status: response.status.to_i,
        result: payload["result"],
        result_tip: payload["resultTip"],
        message: payload["message"],
        key: payload["key"],
        encry: payload["encry"],
        session_token_present: token.present?,
        attempts: attempts,
        mode: {
          encrypted_requests: encrypted_requests?,
          encrypted_login_password: encrypted_login_password?
        },
        env: {
          cmsv6_account: cms_account,
          cmsv6_password_length: cms_password.to_s.length,
          cmsv6_base_url: cms_base_url
        }
      }
    rescue StandardError => error
      {
        error: error.class.name,
        message: error.message,
        mode: {
          encrypted_requests: encrypted_requests?,
          encrypted_login_password: encrypted_login_password?
        },
        env: {
          cmsv6_account: cms_account,
          cmsv6_password_length: cms_password.to_s.length,
          cmsv6_base_url: cms_base_url
        }
      }
    end

    private

    def request_with_refresh(path:, method:, params: nil, body: nil)
      response = request_raw(path:, method:, params:, body:, token: login)
      payload = decode_response(response)

      # result=5 means the account lacks permission for this endpoint entirely.
      # Re-logging in will not help — fail fast so callers can try a fallback endpoint.
      raise_permission_denied!(path: path, response: response, payload: payload) if permission_denied_payload?(payload)

      if unauthorized_payload?(payload) || unauthorized_response?(response)
        refreshed_token = login(force: true, token_preference: :payload_first)
        response = request_raw(path:, method:, params:, body:, token: refreshed_token)
        payload = decode_response(response)
      end

      if unauthorized_payload?(payload) || unauthorized_response?(response)
        fallback_token = login(force: true, token_preference: :cookie_first)
        response = request_raw(path:, method:, params:, body:, token: fallback_token)
        payload = decode_response(response)
      end

      handle_payload_errors(path: path, response: response, payload: payload)
      payload
    end

    def request_raw(path:, method:, params: nil, body: nil, token:, encrypt: encrypted_requests?)
      params, body = attach_session_token(method: method, params: params, body: body, token: token)
      encrypt = false if standard_api_path?(path)

      with_network_errors("#{method.to_s.upcase} #{path}") do
        @connection.public_send(method, build_url(path, params, encrypt: encrypt)) do |request|
          set_common_headers(request, token: token, encrypt: encrypt)
          request.body = build_request_body(body, encrypt: encrypt) if method == :post
        end
      end
    end

    def set_common_headers(request, token:, encrypt:)
      request.headers["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8"
      request.headers["Accept"] = "application/json"
      request.headers["Newv"] = "1" if encrypt
      return if token.blank?

      request.headers["Cookie"] = "JSESSIONID=#{token}"
      request.headers["jsessionId"] = token
      request.headers["X-CMS-Session"] = token
    end

    def build_url(path, params, encrypt:)
      filtered_params = params&.compact
      return path if filtered_params.blank?
      return "#{path}?#{filtered_params.to_query}" unless encrypt

      encrypted_query = CmsV6::Cipher.encrypt(filtered_params.to_json)
      "#{path}?#{encrypted_query}"
    end

    def build_request_body(body, encrypt:)
      filtered_body = body&.compact || {}
      return filtered_body.to_query unless encrypt

      CmsV6::Cipher.encrypt(filtered_body.to_json)
    end

    def decode_response(response)
      payload = parse_json(response.body)
      return payload unless payload["encry"].to_i == 1 && payload["data"].present?

      decrypted = CmsV6::Cipher.decrypt(payload["data"])
      parse_json(decrypted)
    rescue OpenSSL::Cipher::CipherError, ArgumentError => error
      log_failure(path: "decode_response", status: response.status, message: error.message)
      {}
    end

    def handle_payload_errors(path:, response:, payload:)
      if response.status.to_i >= 500
        log_failure(path: path, status: response.status, message: "CMS server error")
        raise ServerError, "CMSV6 server error"
      end

      if unauthorized_payload?(payload) || unauthorized_response?(response)
        log_failure(path: path, status: response.status, message: "CMS unauthorized result=#{payload["result"]}")
        raise UnauthorizedError.new(
          payload["message"].presence || "CMSV6 session expired",
          debug: {
            path: path,
            http_status: response.status.to_i,
            result: payload["result"],
            result_tip: payload["resultTip"],
            message: payload["message"]
          }
        )
      end

      if payload["result"].to_i == 111008
        raise Error, "CMSV6 requires encrypted transport"
      end
    end

    def unauthorized_payload?(payload)
      [ 2, 111002 ].include?(payload["result"].to_i)
    end

    def permission_denied_payload?(payload)
      payload["result"].to_i == 5
    end

    def unauthorized_response?(response)
      [ 401, 403 ].include?(response.status.to_i)
    end

    def raise_permission_denied!(path:, response:, payload:)
      log_failure(path: path, status: response.status, message: "CMS permission denied result=5 (endpoint not available for this account)")
      raise PermissionDeniedError, payload["message"].presence || "CMSV6 account lacks permission for this endpoint"
    end

    def session_token
      Rails.cache.read(session_cache_key)
    end

    public

    def cache_state
      token = session_token
      {
        cache_key: session_cache_key,
        token_present: token.present?,
        token_length: token.to_s.length
      }
    end

    def current_session_token
      session_token.presence || login
    end

    private

    def token_from(response:, payload:, token_preference: :payload_first)
      payload_token = payload["jsession"] || payload["JSESSIONID"] || payload["session"] || payload["token"]
      cookie_header = Array(response.headers["set-cookie"]).join(";")
      cookie_match = cookie_header.match(/JSESSIONID=([^;]+)/i)
      cookie_token = cookie_match ? CGI.unescape(cookie_match[1]) : nil

      case token_preference
      when :cookie_first
        cookie_token.presence || payload_token
      else
        payload_token.presence || cookie_token
      end
    end

    def token_candidates(response:, payload:)
      cookie_header = Array(response.headers["set-cookie"]).join(";")
      cookie_match = cookie_header.match(/JSESSIONID=([^;]+)/i)
      {
        payload_token: (payload["jsession"] || payload["JSESSIONID"] || payload["session"] || payload["token"]),
        cookie_token: (cookie_match ? CGI.unescape(cookie_match[1]) : nil)
      }
    end

    def parse_json(raw_body)
      return {} if raw_body.blank?

      JSON.parse(raw_body)
    rescue JSON::ParserError
      {}
    end

    def with_network_errors(action)
      yield
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
      log_failure(path: action, status: nil, message: error.message)
      raise TimeoutError, "CMSV6 request timed out"
    end

    def log_failure(path:, status:, message:)
      @logger.error("[CMSV6] #{message} path=#{path} status=#{status}")
    end

    def build_connection
      Faraday.new(url: cms_base_url) do |faraday|
        faraday.options.open_timeout = 5   # TCP connect
        faraday.options.timeout      = 12  # response read
        faraday.request :retry, max: 1, interval: 0.2, backoff_factor: 2
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
      end
    end

    def encrypted_requests?
      ENV.fetch("CMSV6_ENCRYPTED", "true") == "true"
    end

    # Kept for diagnostics visibility. StandardApiAction_login uses `password` field.
    def encrypted_login_password?
      ENV.fetch("CMSV6_LOGIN_PASSWORD_ENCRYPTED", "false") == "true"
    end

    def cms_base_url
      ENV.fetch("CMSV6_BASE_URL")
    end

    def cms_account
      ENV.fetch("CMSV6_ACCOUNT")
    end

    def cms_password
      ENV.fetch("CMSV6_PASSWORD")
    end

    def attach_session_token(method:, params:, body:, token:)
      return [ params, body ] if token.blank?

      session_fields = {
        jsession: token,
        JSESSIONID: token,
        session: token
      }

      merged_params = (params || {}).merge(session_fields)
      return [ merged_params, body ] if method == :get

      merged_body = (body || {}).merge(session_fields)
      [ merged_params, merged_body ]
    end

    def standard_api_path?(path)
      path.to_s.include?("StandardApiAction_")
    end

    def login_with_documented_payloads(token_preference: :payload_first)
      response = nil
      payload = {}
      token = nil

      login_payloads.each_value do |candidate|
        response = request_raw(path: LOGIN_PATH, method: :post, body: candidate, token: nil)
        payload = decode_response(response)
        token = token_from(response: response, payload: payload, token_preference: token_preference)
        break if token.present? && payload.fetch("result", 0).to_i.zero?
      end

      [ response, payload, token ]
    end

    def login_payloads
      {
        plain_password: { account: cms_account, password: cms_password },
        md5_password: { account: cms_account, password: Digest::MD5.hexdigest(cms_password) }
      }
    end

    def handle_login_result!(response:, payload:)
      if response.status.to_i >= 500
        raise ServerError, "CMSV6 server error"
      end

      result = payload.fetch("result", 0).to_i
      return if result.zero?

      message = login_error_message(payload)
      case result
      when 1, 2, 3, 4, 13, 29, 34
        raise InvalidCredentialsError, message
      else
        raise Error, message
      end
    end

    def login_error_message(payload)
      payload["message"].presence || payload["resultTip"].presence || "CMSV6 login failed"
    end

    def session_cache_key
      "cms_v6/session_token/#{Digest::MD5.hexdigest(cms_account)}"
    end
  end
end
