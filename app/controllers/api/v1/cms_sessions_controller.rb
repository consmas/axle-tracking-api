module Api
  module V1
    class CmsSessionsController < BaseController
      def login
        token = cms_client.login(force: true)
        cache = cms_client.cache_state

        render json: {
          status: "ok",
          message: "CMS session refreshed",
          cache: cache.merge(token_preview: token.to_s[0, 8])
        }
      end

      def login_diagnostic
        diagnostic = cms_client.login_diagnostic

        render json: { diagnostic: diagnostic }
      end
    end
  end
end
