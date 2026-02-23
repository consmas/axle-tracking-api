# cms_gateway_api

Rails 7+ API-only gateway that authenticates Flutter clients with JWT and proxies CMSV6 (808gps) data through normalized JSON endpoints.

## Stack

- Rails API-only app
- Faraday + `faraday-retry`
- Redis-backed `Rails.cache` for CMS session/token caching
- JWT app authentication
- RSpec request specs

## Required Environment Variables

- `CMSV6_BASE_URL` (example: `http://cmsv6.example.com`)
- `CMSV6_ACCOUNT`
- `CMSV6_PASSWORD`
- `JWT_SECRET`
- `REDIS_URL` (example: `redis://127.0.0.1:6379/0`)
- `CMSV6_ENCRYPTED` (`true` by default, for Newv encrypted transport mode)
- `CMSV6_LOGIN_PASSWORD_ENCRYPTED` (optional diagnostic flag; default `false`)
- `CMSV6_MAP_TYPE` (optional, default `2`)

## Setup

```bash
bundle install
bin/rails db:create db:migrate
bin/rails server
```

Local `.env` is supported via `dotenv-rails` (development/test). Create a `.env` file in project root with the required variables before starting the server.

## API Endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/v1/vehicles`
- `GET /api/v1/map_feed?channel=0&stream=1`
- `GET /api/v1/vehicles/:id/status`
- `GET /api/v1/vehicles/:id/track?from=...&to=...`
- `GET /api/v1/vehicles/:id/live_stream?channel=0&stream=1`
- `GET /api/v1/stream_proxy?url=<encoded_stream_url>` (same-origin HLS proxy for Flutter Web)
- `GET /api/v1/vehicles/:id/playback_files?from=...&to=...&channel=0`
- `GET /api/v1/alarms?from=...&to=...` (admin only)
- `POST /api/v1/cms/login` (refresh CMS `jsession` via `StandardApiAction_login.action`)
- `POST /api/v1/cms/login_diagnostic` (returns sanitized raw CMS login result fields)
- `GET /api/v1/cms/actions` (list supported CMS actions from doc catalog)
- `GET /api/v1/cms/actions/:action_name` (proxy read/action call through gateway)
- `POST /api/v1/cms/actions/:action_name` (proxy write/action call through gateway; admin for mutating actions)

All errors return:

```json
{
  "error": {
    "code": "some_code",
    "message": "Human readable message"
  }
}
```

## Example curl

Register:

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "admin@example.com",
      "password": "password123",
      "password_confirmation": "password123"
    }
  }'
```

Login:

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "admin@example.com",
      "password": "password123"
    }
  }'
```

Vehicles:

```bash
curl http://localhost:3000/api/v1/vehicles \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Unified map feed (vehicles + live status + stream URL):

```bash
curl "http://localhost:3000/api/v1/map_feed?channel=0&stream=1" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Live stream URL for a vehicle:

```bash
curl "http://localhost:3000/api/v1/vehicles/827930/live_stream?channel=0&stream=1" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Proxy an HLS URL through gateway (recommended for Flutter Web):

```bash
curl "http://localhost:3000/api/v1/vehicles/827930/live_stream?channel=0&stream=1" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

`live_stream.stream_url` already contains a signed short-lived `st` token and is safe to use directly in a browser video element.

Playback files for a vehicle:

```bash
curl "http://localhost:3000/api/v1/vehicles/827930/playback_files?from=2026-02-22%2000:00:00&to=2026-02-22%2023:59:59&channel=0" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Refresh CMS session:

```bash
curl -X POST http://localhost:3000/api/v1/cms/login \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

CMS login diagnostic (debug only):

```bash
curl -X POST http://localhost:3000/api/v1/cms/login_diagnostic \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

List full CMS action catalog:

```bash
curl http://localhost:3000/api/v1/cms/actions \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Execute a read action through gateway:

```bash
curl "http://localhost:3000/api/v1/cms/actions/queryUserVehicle?language=en" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

Execute a write action through gateway (admin JWT):

```bash
curl -X POST http://localhost:3000/api/v1/cms/actions/addVehicle \
  -H "Authorization: Bearer <ADMIN_JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "payload": {
      "vehiIdno": "X100",
      "devIdno": "D100"
    }
  }'
```

Diagnostic response intentionally excludes secrets and includes:
- `http_status`, `result`, `result_tip`, `message`, `key`
- `session_token_present`
- `attempts` (plain-password and MD5-password trial outcomes)
- mode flags (`encrypted_requests`, `encrypted_login_password`)
- env hints (`cmsv6_account`, `cmsv6_password_length`, `cmsv6_base_url`)

Flutter flow:
1. Call `POST /api/v1/cms/login` once after app login (or lazy on first CMS-backed request).
2. Call normal gateway endpoints (`/vehicles`, `/status`, `/track`, `/alarms`).
3. If a CMS-backed endpoint returns `cms_unauthorized`, call `POST /api/v1/cms/login` and retry.
4. For broad CMS feature coverage, call `GET/POST /api/v1/cms/actions/:action_name` with action params.

No captcha flow is required in this Standard API mode.

## Test

```bash
bundle exec rspec
```
