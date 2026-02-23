require "faraday"
require "uri"

module Api
  module V1
    class StreamsController < BaseController
      skip_before_action :authenticate_user!, only: :show
      before_action :authenticate_stream_proxy!, only: :show

      def show
        expires_now
        target_url = params[:url].to_s
        if target_url.blank?
          return render_error(code: "invalid_stream_url", message: "url is required", status: :unprocessable_entity)
        end

        uri = parse_and_validate!(target_url)
        return if performed?

        upstream_url = append_session_token(uri.to_s)
        upstream_uri = URI.parse(upstream_url)
        response = stream_http_client.get(upstream_uri.to_s)
        if response.status.to_i >= 400
          return render_error(
            code: "stream_unavailable",
            message: "CMS stream endpoint returned #{response.status}",
            status: :bad_gateway
          )
        end

        body = response.body.to_s
        content_type = response.headers["content-type"].to_s

        if hls_manifest?(upstream_uri, content_type)
          manifest = rewrite_manifest(body, upstream_uri)
          return render plain: manifest, content_type: "application/vnd.apple.mpegurl"
        end

        send_data body, type: (content_type.presence || "application/octet-stream"), disposition: "inline"
      rescue URI::InvalidURIError
        render_error(code: "invalid_stream_url", message: "url is invalid", status: :unprocessable_entity)
      rescue Faraday::Error => error
        Rails.logger.error("[CMSV6] stream proxy failed #{error.class}: #{error.message}")
        render_error(code: "stream_proxy_failed", message: "Could not load stream", status: :bad_gateway)
      end

      private

      def authenticate_stream_proxy!
        token = params[:st].to_s
        if token.blank?
          return render_error(code: "unauthorized", message: "Missing stream token", status: :unauthorized)
        end

        StreamProxyToken.decode!(token, url: params[:url].to_s)
      rescue StreamProxyToken::DecodeError
        render_error(code: "unauthorized", message: "Invalid stream token", status: :unauthorized)
      end

      def parse_and_validate!(target_url)
        uri = URI.parse(target_url)
        unless %w[http https].include?(uri.scheme)
          render_error(code: "invalid_stream_url", message: "only http/https urls are supported", status: :unprocessable_entity)
          return nil
        end
        unless allowed_stream_hosts.include?(uri.host)
          render_error(code: "invalid_stream_url", message: "stream host is not allowed", status: :unprocessable_entity)
          return nil
        end
        uri
      end

      def allowed_stream_hosts
        @allowed_stream_hosts ||= begin
          hosts = []
          cms_host = URI.parse(ENV.fetch("CMSV6_BASE_URL")).host
          hosts << cms_host if cms_host.present?
          explicit = ENV["CMSV6_STREAM_BASE_URL"].to_s.strip
          if explicit.present?
            stream_host = URI.parse(explicit).host
            hosts << stream_host if stream_host.present?
          end
          hosts.compact.uniq
        rescue URI::InvalidURIError, KeyError
          []
        end
      end

      def append_session_token(url)
        uri = URI.parse(url)
        params = Rack::Utils.parse_nested_query(uri.query)
        return url if params["jsession"].present? || params["JSESSIONID"].present?

        token = cms_client.current_session_token.to_s
        return url if token.blank?

        params["jsession"] = token
        uri.query = params.to_query
        uri.to_s
      end

      def hls_manifest?(uri, content_type)
        uri.path.to_s.end_with?(".m3u8") || content_type.include?("mpegurl")
      end

      def rewrite_manifest(manifest, base_uri)
        manifest.lines.map do |line|
          stripped = line.strip
          if stripped.blank? || stripped.start_with?("#")
            line
          else
            absolute = append_session_token(URI.join(base_uri.to_s, stripped).to_s)
            proxied = api_v1_stream_proxy_url(url: absolute, st: StreamProxyToken.issue(url: absolute))
            "#{proxied}\n"
          end
        end.join
      end

      def stream_http_client
        @stream_http_client ||= Faraday.new do |faraday|
          faraday.options.timeout = 20
          faraday.options.open_timeout = 8
          faraday.adapter Faraday.default_adapter
        end
      end
    end
  end
end
