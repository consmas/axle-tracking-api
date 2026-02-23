class JwtToken
  class DecodeError < StandardError; end

  ALGORITHM = "HS256"

  class << self
    def issue(user:, expires_in: 24.hours)
      payload = {
        user_id: user.id,
        role: user.role,
        exp: expires_in.from_now.to_i
      }

      JWT.encode(payload, secret, ALGORITHM)
    end

    def decode!(token)
      decoded, = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
      decoded
    rescue JWT::DecodeError, JWT::ExpiredSignature => error
      raise DecodeError, error.message
    end

    private

    def secret
      ENV.fetch("JWT_SECRET")
    end
  end
end
