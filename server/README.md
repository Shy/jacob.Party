# jacob.party Server

Vapor HTTP server with integrated Temporal worker for managing party workflows.

## Structure

```
server/
├── Sources/App/              # Server application code
│   ├── Workflows/            # Temporal workflow definitions
│   ├── Activities/           # Temporal activity implementations
│   ├── Middleware/           # HTTP middleware (auth, rate limiting)
│   ├── Models/               # Data models
│   ├── configure.swift       # Server & Temporal configuration
│   ├── routes.swift          # HTTP API routes
│   └── entrypoint.swift      # Application entry point
├── Resources/Views/          # Web interface (HTML)
├── Package.swift             # Swift package manifest
├── Dockerfile                # Production Docker image
├── docker-compose.yml        # Docker orchestration
└── .dockerignore             # Docker build exclusions
```

## Running Locally

```bash
cd server
swift build
.build/debug/App
```

Server starts on `http://127.0.0.1:8080`

## Docker Deployment

```bash
cd server
docker-compose up -d
```

See main [README.md](../README.md) for full setup instructions.

## API Endpoints

**Public:**
- `GET /` - Web interface
- `GET /api/state` - Query party state (rate limited: 30/min per IP)

**Protected** (requires `X-Device-ID` header):
- `POST /api/party/start` - Start party with location
- `POST /api/party/location` - Update location
- `POST /api/party/stop` - Stop party

## Configuration

Environment variables (via `../.env`):
- `TEMPORAL_HOST` - Temporal server host
- `TEMPORAL_NAMESPACE` - Temporal namespace
- `APP_NAME` - Application name
- `GOOGLE_MAPS_API_KEY` - Google Maps API key
- `DEVICE_WHITELIST` - Comma-separated device UUIDs (optional)

## Features

- **Temporal Integration**: Workflows and activities for party management
- **Rate Limiting**: 30 requests/minute per IP on state endpoint
- **Device Authentication**: UUID-based device whitelist
- **Battery-Aware**: Web interface uses exponential backoff polling
- **Production Ready**: Docker support with health checks and logging
