require "rails_helper"

RSpec.describe "API V1 Vehicle Streams", type: :request do
  let!(:user) { User.create!(email: "stream.user@example.com", password: "password123", password_confirmation: "password123") }
  let(:jwt) { JwtToken.issue(user: user) }
  let(:headers) { { "Authorization" => "Bearer #{jwt}" } }
  let(:client) { instance_double(CmsV6::Client) }

  before do
    allow(CmsV6::Client).to receive(:new).and_return(client)
  end

  describe "GET /api/v1/vehicles/:id/live_stream" do
    it "returns normalized stream URL" do
      allow(client).to receive(:get).and_return(
        {
          "url" => "http://example.test/hls/1_827930_0_1.m3u8?jsession=",
          "result" => 0
        }
      )
      allow(client).to receive(:current_session_token).and_return("abc123")

      get "/api/v1/vehicles/827930/live_stream", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["protocol"]).to eq("hls")
      expect(body["stream_url"]).to include("/api/v1/stream_proxy")
      expect(body["raw_stream_url"]).to include("jsession=abc123")
    end
  end

  describe "GET /api/v1/vehicles/:id/playback_files" do
    it "returns normalized playback file list" do
      allow(client).to receive(:get).and_return(
        {
          "infos" => [
            {
              "name" => "clip01",
              "fbtm" => "2026-02-22 10:00:00",
              "fetm" => "2026-02-22 10:10:00",
              "len" => 120,
              "playbackUrl" => "http://example.test/3/5?DownType=5&jsession=",
              "downUrl" => "http://example.test/3/5?DownType=3&jsession="
            }
          ]
        }
      )
      allow(client).to receive(:current_session_token).and_return("abc123")

      get "/api/v1/vehicles/827930/playback_files",
          params: { from: "2026-02-22 00:00:00", to: "2026-02-22 23:59:59" },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["files"]).not_to be_empty
      expect(body["files"][0]["playback_url"]).to include("DownType=5")
      expect(body["files"][0]["playback_url"]).to include("jsession=abc123")
    end
  end
end
