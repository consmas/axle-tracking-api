require "rails_helper"

RSpec.describe "API Auth", type: :request do
  describe "POST /api/auth/register" do
    it "creates a user and returns jwt" do
      post "/api/auth/register", params: {
        user: {
          email: "new.user@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include("token")
      expect(User.find_by(email: "new.user@example.com")).to be_present
    end
  end

  describe "POST /api/auth/login" do
    let!(:user) { User.create!(email: "login.user@example.com", password: "password123", password_confirmation: "password123") }

    it "returns jwt for valid credentials" do
      post "/api/auth/login", params: { user: { email: user.email, password: "password123" } }

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      expect(payload["token"]).to be_present
      expect(payload.dig("user", "email")).to eq(user.email)
    end

    it "returns unauthorized for invalid credentials" do
      post "/api/auth/login", params: { user: { email: user.email, password: "wrong-password" } }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("invalid_credentials")
    end
  end
end
