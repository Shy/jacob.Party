# jacob.party

Real-time party tracking demonstrating Temporal workflows with Swift, SwiftUI, and Vapor.

## Structure

```
├── Sources/App/              # Vapor server + Temporal worker
│   ├── Workflows/            # Temporal workflows
│   └── Activities/           # Temporal activities
├── app/JacobParty/           # iOS app (SwiftUI)
└── Resources/Views/          # Web interface
```

## What This Demonstrates

**Temporal with Swift**
- Four workflow types: start party, stop party, update location, query state
- Activities for storage operations
- Non-blocking workflow execution
- Temporal worker integrated with Vapor server

**Swift Temporal SDK Usage**
- Client and worker initialization with mTLS support
- Workflow and activity definitions using Swift macros
- Environment-based configuration (local vs cloud)
- HTTP API triggering workflows

**iOS Integration**
- Real-time location tracking with automatic updates
- Device-based authentication with Keychain UUID storage
- Background location updates while party is active
- Secure communication with server via authenticated API requests

**Security**
- Device authentication middleware
- UUID-based device whitelist
- Secure keychain storage for persistent device identity

**Storage**
- JSON file-based persistence (no database required)

## Prerequisites

- Swift 6.0+
- Xcode 16+ (for iOS app)
- Temporal Server (local) or Temporal Cloud account

## Quick Start

### 1. Start Temporal Server

```bash
# Install Temporal CLI
brew install temporal

# Start local server
temporal server start-dev
```

Leave this running in a terminal.

### 2. Get Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable **Maps JavaScript API**
4. Create credentials → API Key
5. Copy the API key

### 3. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and add your Google Maps API key:
```env
GOOGLE_MAPS_API_KEY=your_actual_api_key_here
```

All available environment variables:
```env
# Application Name
APP_NAME=jacob

# Google Maps API Key (REQUIRED for map display)
GOOGLE_MAPS_API_KEY=YOUR_API_KEY_HERE

# Temporal Configuration (defaults for local development)
TEMPORAL_HOST=127.0.0.1
TEMPORAL_PORT=7233
TEMPORAL_NAMESPACE=default
TEMPORAL_TASK_QUEUE=party-queue

# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=8080

# Device Authentication (leave empty to allow all devices)
ALLOWED_DEVICE_IDS=
```

### 4. Run Server

```bash
swift build
.build/debug/App
```

Server starts on `http://127.0.0.1:8080` and connects to local Temporal.

### 5. Run iOS App (Optional)

```bash
open app/JacobParty/JacobParty.xcodeproj
```

Build and run in Xcode. Or use the web interface at `http://127.0.0.1:8080`.

**For production deployment:** Update the base URL in `PartyViewModel.swift`:
```swift
private let baseURL = "https://yourserver.com"  // Change from localhost
```

## Device Authentication

The iOS app uses device-based authentication with persistent UUIDs stored in the Keychain.

### How It Works

1. **iOS App**: Generates a unique UUID on first launch and stores it securely in the Keychain
2. **All API Requests**: Include `X-Device-ID` header with the device UUID
3. **Server**: Validates device IDs against an optional whitelist

### Getting Your Device UUID

Run the iOS app once and check the server logs:
```bash
tail -f /tmp/server.log | grep "Device ID"
```

You'll see: `📱 Device ID: 779D6E13-14A4-4130-A82B-7D858AE4C34B (whitelist disabled)`

### Enabling the Whitelist

Add allowed device UUIDs to `.env`:
```env
# Single device
ALLOWED_DEVICE_IDS=779D6E13-14A4-4130-A82B-7D858AE4C34B

# Multiple devices (comma-separated)
ALLOWED_DEVICE_IDS=779D6E13-14A4-4130-A82B-7D858AE4C34B,ANOTHER-UUID-HERE
```

**Empty = All devices allowed (development mode)**

With whitelist enabled:
- ✅ Requests with allowed device IDs: Accepted
- ❌ Requests with unknown device IDs: `403 Forbidden`
- ❌ Requests without device ID header: `401 Unauthorized`

### Public vs Protected Endpoints

**Public (no authentication):**
- `GET /` - Website
- `GET /api/state` - View party state (read-only)

**Protected (requires device authentication):**
- `POST /api/party/start` - Start party
- `POST /api/party/stop` - Stop party
- `POST /api/party/location` - Update location

Anyone can view the website and see where the party is, but only authorized devices can control it.

## Using Temporal Cloud

See [certs/README.md](certs/README.md) for certificate setup.

Update `.env`:
```env
TEMPORAL_HOST=your-namespace.tmprl.cloud
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_TLS_ENABLED=true
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
```

## How It Works

### Temporal Workflows

**PartyWorkflow** - Start party with location
```
POST /api/party/start → PartyWorkflow → recordPartyStart activity → Write JSON
```

**UpdateLocationWorkflow** - Update location while partying
```
POST /api/party/location → UpdateLocationWorkflow → updateLocation activity → Update JSON
```
*iOS app automatically sends location updates when you move >50 meters*

**GetPartyStateWorkflow** - Query current state
```
GET /api/state → GetPartyStateWorkflow → getPartyState activity → Read JSON
```

**StopPartyWorkflow** - Stop party and clear data
```
POST /api/party/stop → StopPartyWorkflow → recordPartyEnd activity → Delete JSON
```

All workflows complete immediately. Activities handle JSON file storage.

## Key Files

**Swift Temporal SDK Integration:**
- [Sources/App/configure.swift](Sources/App/configure.swift) - Client and worker setup
- [Sources/App/Workflows/](Sources/App/Workflows/) - Workflow definitions
- [Sources/App/Activities/PartyActivities.swift](Sources/App/Activities/PartyActivities.swift) - Activity definitions

**HTTP API:**
- [Sources/App/routes.swift](Sources/App/routes.swift) - Vapor routes triggering workflows

## Debugging

**Temporal UI:** `http://localhost:8233`

**CLI Commands:**
```bash
# List workflows
temporal workflow list

# View specific workflow
temporal workflow describe --workflow-id jacob-party

# View workflow history
temporal workflow show --workflow-id jacob-party
```

**Troubleshooting:**

*Map not showing?*
- Check `GOOGLE_MAPS_API_KEY` is set in `.env`
- Verify Maps JavaScript API is enabled in Google Cloud Console
- Check browser console for errors

*Server won't start?*
- Ensure Temporal server is running: `temporal server start-dev`
- Check port 8080 is not in use: `lsof -i :8080`
- Verify `.env` file exists with correct syntax

*iOS location not updating?*
- Check location permissions in Settings → Privacy
- Verify "Always Allow" location permission is granted
- Check that party mode is active (location only updates while partying)

## Architecture Notes

- JSON file storage (no database required)
- Non-blocking workflows (complete immediately)
- Activities handle all I/O operations
- Worker and HTTP server in same process
- Supports both local Temporal and Temporal Cloud
