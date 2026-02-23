module Api
  module V1
    class CmsActionsController < BaseController
      before_action :validate_action!
      before_action :enforce_action_role!

      def index
        render json: { actions: CmsV6::ActionCatalog.summary }
      end

      def execute
        payload = if request.get?
                    cms_client.get(cms_path, params: passthrough_query_params)
                  else
                    cms_client.post(cms_path, body: passthrough_body_params)
                  end

        render json: {
          action: cms_action_name,
          endpoint: cms_path,
          method: request.request_method,
          data: payload
        }
      end

      private

      def cms_action_name
        @cms_action_name ||= params[:action_name].to_s
      end

      def cms_path
        CmsV6::ActionCatalog.endpoint(cms_action_name)
      end

      def validate_action!
        return if cms_action_name.blank? || CmsV6::ActionCatalog.include?(cms_action_name)

        render_error(code: "cms_action_not_supported", message: "Unsupported CMS action", status: :not_found)
      end

      def enforce_action_role!
        return unless cms_action_name.present?
        return unless CmsV6::ActionCatalog.admin_required?(cms_action_name)

        require_admin!
      end

      def passthrough_query_params
        params.to_unsafe_h.except(
          "controller", "action", "format", "action_name", "debug"
        )
      end

      def passthrough_body_params
        request_payload = params.to_unsafe_h.except(
          "controller", "action", "format", "action_name"
        )

        if request_payload.key?("payload") && request_payload["payload"].is_a?(Hash)
          request_payload["payload"]
        else
          request_payload
        end
      end
    end
  end
end
