require "rails_helper"

RSpec.describe "API V1 Streams", type: :request do
  let!(:user) { User.create!(email: "proxy.user@example.com", password: "password123", password_confirmation: "password123") }
  let(:jwt) { JwtToken.issue(user: user) }
  let(:headers) { { "Authorization" => "Bearer #{jwt}" } }
  let(:cms_client) { instance_double(CmsV6::Client, current_session_token: "abc123") }

  before do
    allow(CmsV6::Client).to receive(:new).and_return(cms_client)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CMSV6_BASE_URL").and_return("http://20.81.130.10/808gps")
  end

  it "rewrites manifest entries into same-origin proxy links" do
    conn = instance_double(Faraday::Connection)
    resp = instance_double(
      Faraday::Response,
      status: 200,
      headers: { "content-type" => "application/vnd.apple.mpegurl" },
      body: "#EXTM3U\n#EXTINF:2,\nsegment-1.ts\n"
    )
    allow(Faraday).to receive(:new).and_return(conn)
    allow(conn).to receive(:get).and_return(resp)

    source = "http://20.81.130.10:6604/hls/live.m3u8"
    st = StreamProxyToken.issue(url: source)
    get "/api/v1/stream_proxy", params: { url: source, st: st }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("#EXTM3U")
    expect(response.body).to include("/api/v1/stream_proxy?")
  end

  it "rejects requests without stream token" do
    get "/api/v1/stream_proxy", params: { url: "http://20.81.130.10:6604/hls/live.m3u8" }

    expect(response).to have_http_status(:unauthorized)
  end
end
