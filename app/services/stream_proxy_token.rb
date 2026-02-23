class StreamProxyToken
  class DecodeError < StandardError; end

  ALGORITHM = "HS256"

  class << self
    def issue(url:, expires_in: 10.minutes)
      payload = {
        url: url,
        exp: expires_in.from_now.to_i
      }
      JWT.encode(payload, secret, ALGORITHM)
    end

    def decode!(token, url:)
      decoded, = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
      raise DecodeError, "token/url mismatch" unless decoded["url"].to_s == url.to_s

      decoded
    rescue JWT::DecodeError, JWT::ExpiredSignature, DecodeError => error
      raise DecodeError, error.message
    end

    private

    def secret
      ENV.fetch("JWT_SECRET")
    end
  end
end
