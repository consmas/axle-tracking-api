module Api
  class AuthController < ApplicationController
    def register
      user = User.create!(register_params)
      token = JwtToken.issue(user: user)

      render json: {
        user: serialized_user(user),
        token: token
      }, status: :created
    end

    def login
      user = User.find_by(email: login_params[:email].to_s.downcase)
      unless user&.authenticate(login_params[:password])
        return render_error(code: "invalid_credentials", message: "Invalid email or password", status: :unauthorized)
      end

      render json: {
        user: serialized_user(user),
        token: JwtToken.issue(user: user)
      }
    end

    private

    def register_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end

    def login_params
      params.require(:user).permit(:email, :password)
    end

    def serialized_user(user)
      {
        id: user.id,
        email: user.email,
        role: user.role
      }
    end
  end
end
