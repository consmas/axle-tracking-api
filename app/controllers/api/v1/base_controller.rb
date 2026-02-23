module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!

      private

      def cms_client
        @cms_client ||= CmsV6::Client.new
      end
    end
  end
end
