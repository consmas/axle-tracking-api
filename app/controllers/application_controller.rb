class ApplicationController < ActionController::API
  wrap_parameters false

  rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from JwtToken::DecodeError, with: :handle_unauthorized
  rescue_from CmsV6::Client::Error, with: :handle_cms_generic_error
  rescue_from CmsV6::Client::UnauthorizedError, with: :handle_cms_unauthorized
  rescue_from CmsV6::Client::PermissionDeniedError, with: :handle_cms_permission_denied
  rescue_from CmsV6::Client::InvalidCredentialsError, with: :handle_cms_credentials
  rescue_from CmsV6::Client::TimeoutError, with: :handle_cms_timeout
  rescue_from CmsV6::Client::ServerError, with: :handle_cms_server_error

  private

  def authenticate_user!
    handle_unauthorized and return if bearer_token.blank?

    payload = JwtToken.decode!(bearer_token)
    @current_user = User.find(payload.fetch("user_id"))
  rescue KeyError, JwtToken::DecodeError, ActiveRecord::RecordNotFound
    handle_unauthorized
  end

  def current_user
    @current_user
  end

  def require_admin!
    return if current_user&.admin?

    render_error(code: "forbidden", message: "Admin access required", status: :forbidden)
  end

  def render_error(code:, message:, status:, details: {})
    payload = { code: code, message: message }.merge(details)
    render json: { error: payload }, status: status
  end

  def bearer_token
    auth_header = request.headers["Authorization"].to_s
    return nil unless auth_header.start_with?("Bearer ")

    auth_header.split(" ", 2).last
  end

  def handle_record_invalid(error)
    render_error(code: "validation_error", message: error.record.errors.full_messages.join(", "), status: :unprocessable_entity)
  end

  def handle_not_found(_error)
    render_error(code: "not_found", message: "Resource not found", status: :not_found)
  end

  def handle_unauthorized(_error = nil)
    render_error(code: "unauthorized", message: "Invalid or missing access token", status: :unauthorized)
  end

  def handle_cms_unauthorized(error)
    render_error(
      code: "cms_unauthorized",
      message: error.message,
      status: :bad_gateway,
      details: cms_debug_details(error)
    )
  end

  def handle_cms_permission_denied(error)
    render_error(code: "cms_permission_denied", message: error.message, status: :bad_gateway)
  end

  def handle_cms_credentials(error)
    render_error(code: "cms_invalid_credentials", message: error.message, status: :bad_gateway)
  end

  def handle_cms_timeout(error)
    render_error(code: "cms_timeout", message: error.message, status: :gateway_timeout)
  end

  def handle_cms_server_error(error)
    render_error(code: "cms_server_error", message: error.message, status: :bad_gateway)
  end

  def handle_cms_generic_error(error)
    render_error(code: "cms_error", message: error.message, status: :bad_gateway)
  end

  def cms_debug_details(error)
    return {} unless error.respond_to?(:debug)
    return {} if error.debug.blank?

    { debug: error.debug }
  end
end
