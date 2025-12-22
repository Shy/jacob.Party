# jacob.party

A demonstration project using [Apple's Swift SDK for Temporal](https://github.com/apple/swift-temporal-sdk) showing how to build a real-world application with Temporal workflows, activities, and workers in Swift.

**The App**: Let your friends know when you're out partying so they can come join you. Start the party on your iPhone, and your friends can see your location on the web in real-time.

Three components communicate through Temporal:
- **Vapor Server** - HTTP API that triggers Temporal workflows
- **iOS App** - SwiftUI app with background location tracking
- **Web Interface** - Real-time party status display with Google Maps integration

## Monorepo Structure

```
├── server/                   # Vapor server + Temporal worker
│   ├── Sources/App/          # Server application code
│   │   ├── Workflows/        # Temporal workflow definitions
│   │   ├── Activities/       # Temporal activity implementations
│   │   └── Middleware/       # Auth & rate limiting
│   ├── Resources/Views/      # Web interface (HTML)
│   ├── Dockerfile            # Docker image for server
│   └── docker-compose.yml    # Server orchestration
├── app/                      # iOS app (SwiftUI)
│   └── JacobParty/           # Xcode project
├── certs/                    # Temporal Cloud mTLS certificates (gitignored)
├── .env                      # Environment configuration (gitignored)
└── .env.example              # Environment template
```

## What This Demonstrates

**Temporal with Swift**
- Four workflow types (start/stop party, update location, query state)
- Workflow and activity definitions using Swift macros
- Client and worker initialization with flexible authentication (API key or mTLS)
- Worker integrated with Vapor server in same process

**iOS Integration**
- Battery-efficient location tracking (10m accuracy, 50m distance filter)
- Updates only when moved >50m AND 60+ seconds elapsed
- Device-based authentication with Keychain UUID storage
- Background location updates while party is active

**Performance & Security**
- Web polling with exponential backoff (10s → 120s), pauses when tab hidden
- Rate limiting (30 requests/minute per IP)
- Device authentication middleware with optional UUID whitelist
- JSON file storage (no database required)

## Prerequisites

- Swift 6.2+ with [Apple's Swift SDK for Temporal](https://github.com/apple/swift-temporal-sdk)
- Xcode 16+ (for iOS app)
- Temporal Server (local dev) or Temporal Cloud account

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
# Edit .env to add your Google Maps API key
cp .env server/.env
```

### 2. Start Temporal Server

```bash
temporal server start-dev
```

### 3. Run Server

```bash
cd server
swift build
.build/debug/App serve
```

Server starts on `http://127.0.0.1:8080` and loads config from `.env`.

### 4. Run iOS App (Optional)

```bash
open app/JacobParty/JacobParty.xcodeproj
```

Build and run in Xcode (⌘R). App loads `SERVER_URL` from `app/JacobParty/Config.xcconfig`.

## Device Authentication

The iOS app generates a unique UUID on first launch (stored in Keychain) and sends it in the `X-Device-ID` header with all requests.

### Getting Your Device UUID

Run the iOS app and check server logs:
```bash
tail -f /tmp/server.log | grep "Device ID"
# Output: 📱 Device ID: 779D6E13-14A4-4130-A82B-7D858AE4C34B (whitelist disabled)
```

### Optional Whitelist

Add allowed device UUIDs to `.env` (empty = all devices allowed):
```env
ALLOWED_DEVICE_IDS=779D6E13-14A4-4130-A82B-7D858AE4C34B,ANOTHER-UUID-HERE
```

**Endpoints:**
- Public: `GET /` (website), `GET /api/state` (party status)
- Protected: `POST /api/party/*` (requires device authentication)

## Container Deployment

```bash
cd server
docker build -t jacob-party .
docker run -p 8080:8080 --env-file ../.env jacob-party

# Or use Docker Compose
docker-compose up -d
```

For mTLS, mount certificates: `-v $(pwd)/../certs:/app/certs:ro`

## Temporal Cloud Authentication

**API Key (Recommended)**:
```env
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=us-east-1.aws.api.temporal.io
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_API_KEY=your-api-key
```

**mTLS Certificates**:
```env
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=your-namespace.tmprl.cloud
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
```
See [certs/README.md](certs/README.md) for setup. Can combine both methods for maximum security.

## How It Works

Four Temporal workflows handle all party operations:

1. **PartyWorkflow** - Start party: `POST /api/party/start` → `recordPartyStart` activity → Write JSON
2. **UpdateLocationWorkflow** - Update location: `POST /api/party/location` → `updateLocation` activity → Update JSON
3. **GetPartyStateWorkflow** - Query state: `GET /api/state` → `getPartyState` activity → Read JSON
4. **StopPartyWorkflow** - Stop party: `POST /api/party/stop` → `recordPartyEnd` activity → Delete JSON

All workflows complete immediately. Activities handle JSON file storage.

## API Testing

Test the party lifecycle with [HTTPie](https://httpie.io):

```bash
# Check current state
http GET localhost:8080/api/state

# Start a party
http --ignore-stdin POST localhost:8080/api/party/start \
  location:='{"lat":37.7749,"lng":-122.4194}' \
  reason=testing

# Update location
http --ignore-stdin POST localhost:8080/api/party/location \
  location:='{"lat":37.7849,"lng":-122.4094}' \
  reason=testing

# Stop party
http POST localhost:8080/api/party/stop
```

**Note:** Device authentication is disabled by default (see `ALLOWED_DEVICE_IDS` in `.env`).

## Key Files

- [server/Sources/App/configure.swift](server/Sources/App/configure.swift) - Temporal client and worker setup
- [server/Sources/App/Workflows/](server/Sources/App/Workflows/) - Workflow definitions
- [server/Sources/App/Activities/PartyActivities.swift](server/Sources/App/Activities/PartyActivities.swift) - Activity implementations
- [server/Sources/App/routes.swift](server/Sources/App/routes.swift) - HTTP API routes
- [server/Sources/App/Middleware/](server/Sources/App/Middleware/) - Auth and rate limiting

## Debugging

**Temporal UI:** `http://localhost:8233`

**CLI:**
```bash
temporal workflow list
temporal workflow describe --workflow-id jacob-party
```

**Common Issues:**
- Map not showing? Check `GOOGLE_MAPS_API_KEY` in `.env` and Maps JavaScript API enabled
- Server won't start? Verify Temporal is running (`temporal server start-dev`) and port 8080 is free
- iOS location not updating? Check "Always Allow" location permission and party mode is active
