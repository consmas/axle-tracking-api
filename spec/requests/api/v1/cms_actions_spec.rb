require "rails_helper"

RSpec.describe "API V1 CMS Actions", type: :request do
  let!(:user) { User.create!(email: "user@example.com", password: "password123", password_confirmation: "password123") }
  let!(:admin) { User.create!(email: "admin@example.com", password: "password123", password_confirmation: "password123", role: :admin) }
  let(:user_jwt) { JwtToken.issue(user: user) }
  let(:admin_jwt) { JwtToken.issue(user: admin) }
  let(:user_headers) { { "Authorization" => "Bearer #{user_jwt}" } }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_jwt}" } }
  let(:client) { instance_double(CmsV6::Client) }

  before do
    allow(CmsV6::Client).to receive(:new).and_return(client)
  end

  describe "GET /api/v1/cms/actions" do
    it "returns supported CMS action catalog" do
      get "/api/v1/cms/actions", headers: user_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      names = body.fetch("actions").map { |row| row.fetch("name") }
      expect(names).to include("queryUserVehicle", "getDeviceStatus", "queryTrackDetail")
    end
  end

  describe "GET /api/v1/cms/actions/:action_name" do
    it "proxies whitelisted read action" do
      allow(client).to receive(:get).and_return({ "result" => 0, "list" => [] })

      get "/api/v1/cms/actions/queryUserVehicle", params: { language: "en" }, headers: user_headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:get).with(
        "StandardApiAction_queryUserVehicle.action",
        params: hash_including("language" => "en")
      )
      body = JSON.parse(response.body)
      expect(body["action"]).to eq("queryUserVehicle")
      expect(body.dig("data", "result")).to eq(0)
    end
  end

  describe "POST /api/v1/cms/actions/:action_name" do
    it "blocks non-admin users for admin actions" do
      post "/api/v1/cms/actions/addVehicle", params: { vehiIdno: "X100" }, headers: user_headers

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("forbidden")
    end

    it "allows admin users for admin actions" do
      allow(client).to receive(:post).and_return({ "result" => 0 })

      post "/api/v1/cms/actions/addVehicle", params: { payload: { vehiIdno: "X100", devIdno: "D100" } }, headers: admin_headers

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:post).with(
        "StandardApiAction_addVehicle.action",
        body: hash_including("vehiIdno" => "X100", "devIdno" => "D100")
      )
    end
  end
end
