require "rails_helper"

RSpec.describe "API V1 CMS Sessions", type: :request do
  let!(:user) { User.create!(email: "cms.user@example.com", password: "password123", password_confirmation: "password123") }
  let(:jwt) { JwtToken.issue(user: user) }
  let(:headers) { { "Authorization" => "Bearer #{jwt}" } }
  let(:client) { instance_double(CmsV6::Client) }

  before do
    allow(CmsV6::Client).to receive(:new).and_return(client)
  end

  describe "POST /api/v1/cms/login" do
    it "refreshes CMS session via Standard API login" do
      allow(client).to receive(:login).and_return("cms-token")
      allow(client).to receive(:cache_state).and_return(
        {
          cache_key: "cms_v6/session_token/test",
          token_present: true,
          token_length: 9
        }
      )

      post "/api/v1/cms/login", headers: headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:login).with(force: true)
    end
  end

  describe "POST /api/v1/cms/login_diagnostic" do
    it "returns sanitized diagnostic fields for cms login response" do
      allow(client).to receive(:login_diagnostic).and_return(
        {
          http_status: 200,
          result: 1,
          result_tip: "incorrect_login_information",
          message: "Username or password incorrect!",
          session_token_present: false,
          mode: {
            encrypted_requests: true,
            encrypted_login_password: true
          },
          env: {
            cmsv6_account: "admin",
            cmsv6_password_length: 11,
            cmsv6_base_url: "http://20.81.130.10/808gps"
          }
        }
      )

      post "/api/v1/cms/login_diagnostic", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("diagnostic", "result")).to eq(1)
      expect(body.dig("diagnostic", "session_token_present")).to eq(false)
      expect(body.dig("diagnostic", "env", "cmsv6_password_length")).to eq(11)
      expect(client).to have_received(:login_diagnostic)
    end
  end
end
