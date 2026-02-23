require "rails_helper"

RSpec.describe "API V1 Vehicles", type: :request do
  let!(:user) { User.create!(email: "fleet.user@example.com", password: "password123", password_confirmation: "password123") }
  let(:jwt) { JwtToken.issue(user: user) }
  let(:headers) { { "Authorization" => "Bearer #{jwt}" } }

  before { Rails.cache.clear }

  describe "GET /api/v1/vehicles" do
    it "returns normalized vehicle data from CMSV6" do
      connection = instance_double(Faraday::Connection)
      login_response = instance_double(Faraday::Response, status: 200, headers: {}, body: { jsession: "cms-session-token" }.to_json)
      vehicles_response = instance_double(
        Faraday::Response,
        status: 200,
        headers: {},
        body: { list: [ { devIdno: "V001", vehiName: "Truck 1", vehiNum: "ABC123", online: 1 } ] }.to_json
      )

      allow(Faraday).to receive(:new).and_return(connection)
      allow(connection).to receive(:post).and_return(login_response, vehicles_response)
      allow(connection).to receive(:get).and_return(vehicles_response)

      get "/api/v1/vehicles", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["vehicles"]).to eq(
        [
          {
            "id" => "V001",
            "name" => "Truck 1",
            "plate_number" => "ABC123",
            "online" => true
          }
        ]
      )
    end
  end

  describe "GET /api/v1/map_feed" do
    it "returns bundled vehicles + status + live_stream in one response" do
      connection = instance_double(Faraday::Connection)
      login_response = instance_double(Faraday::Response, status: 200, headers: {}, body: { jsession: "cms-session-token" }.to_json)
      vehicles_response = instance_double(
        Faraday::Response,
        status: 200,
        headers: {},
        body: { list: [ { devIdno: "V001", vehiName: "Truck 1", vehiNum: "ABC123", online: 1 } ] }.to_json
      )
      status_response = instance_double(
        Faraday::Response,
        status: 200,
        headers: {},
        body: { list: [ { vehiIdno: "V001", lat: 1.23, lng: 4.56, online: 1 } ] }.to_json
      )
      stream_response = instance_double(
        Faraday::Response,
        status: 200,
        headers: {},
        body: { url: "http://video.test/live.m3u8?jsession=" }.to_json
      )

      allow(Faraday).to receive(:new).and_return(connection)
      allow(connection).to receive(:post).and_return(login_response, vehicles_response)
      allow(connection).to receive(:get).and_return(status_response, stream_response)

      get "/api/v1/map_feed", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["vehicles"]).to be_an(Array)
      expect(body["vehicles"][0]["id"]).to eq("V001")
      expect(body["vehicles"][0].dig("status", "online")).to eq(true)
      expect(body["vehicles"][0].dig("live_stream", "stream_url")).to include("/api/v1/stream_proxy")
      expect(body["vehicles"][0].dig("live_stream", "raw_stream_url")).to include("live.m3u8")
    end
  end
end
