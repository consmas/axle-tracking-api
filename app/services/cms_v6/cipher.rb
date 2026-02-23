require "base64"
require "openssl"

module CmsV6
  class Cipher
    KEY = "ttx123456Aes1234".freeze

    class << self
      def encrypt(plain_text)
        return "" if plain_text.blank?

        aes = OpenSSL::Cipher.new("AES-128-ECB")
        aes.encrypt
        aes.key = KEY
        Base64.strict_encode64(aes.update(plain_text.to_s) + aes.final)
      end

      def decrypt(cipher_text)
        return "" if cipher_text.blank?

        aes = OpenSSL::Cipher.new("AES-128-ECB")
        aes.decrypt
        aes.key = KEY
        aes.padding = 1
        raw = Base64.decode64(cipher_text.to_s.gsub(/\s+/, ""))
        aes.update(raw) + aes.final
      end
    end
  end
end
