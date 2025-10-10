# Temporal Cloud Authentication Options

This project supports **two authentication methods** for connecting to Temporal Cloud:

## 1. API Key Authentication (Recommended) ✅

**Simplest option** - just set one environment variable!

### Environment Variables
```bash
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=us-east-1.aws.api.temporal.io  # Regional endpoint
TEMPORAL_PORT=7233
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_API_KEY=your-api-key-here
```

### Benefits
- ✅ No certificate file management
- ✅ Works perfectly in Docker multi-stage builds
- ✅ Easy to rotate (just update env var)
- ✅ Simpler deployment on cloud platforms (DO, Heroku, etc.)
- ✅ Smaller Docker images (~2GB vs 12.7GB)

### Transport Security
Uses `.tls` (TLS encryption without client certificates)

---

## 2. mTLS Certificate Authentication (Legacy)

**Traditional method** - uses client certificates for authentication.

### Environment Variables

**Option A: File Paths (Local Development)**
```bash
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=namespace.tmprl.cloud  # Namespace-specific endpoint
TEMPORAL_PORT=7233
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
```

**Option B: Certificate Content (Cloud Deployment)**
```bash
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=namespace.tmprl.cloud
TEMPORAL_PORT=7233
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_CLIENT_CERT_CONTENT=<paste full PEM certificate content>
TEMPORAL_CLIENT_KEY_CONTENT=<paste full PEM key content>
```

### Transport Security
Uses `.mTLS` (mutual TLS with client certificate authentication)

---

## 3. Hybrid: mTLS + API Key (Maximum Security)

You can use **both** methods simultaneously for defense-in-depth:

```bash
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=namespace.tmprl.cloud
TEMPORAL_PORT=7233
TEMPORAL_NAMESPACE=your-namespace
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
TEMPORAL_API_KEY=your-api-key-here
```

This provides:
- mTLS for transport-level authentication
- API key for application-level authentication

---

## How It Works

The `configure.swift` automatically detects which authentication method(s) to use:

```swift
if let certPath = clientCertPath, let keyPath = clientKeyPath {
    // Use mTLS (with optional API key)
    transportSecurity = .mTLS(...)
} else {
    // Use TLS with API key only
    transportSecurity = .tls
}
```

Both `TemporalClient` and `TemporalWorker` receive the `apiKey` parameter:
```swift
configuration: .init(
    instrumentation: .init(serverHostname: temporalHost),
    namespace: temporalNamespace,
    apiKey: temporalApiKey  // Can be nil
)
```

---

## DigitalOcean Deployment

### Current Setup (API Key)
1. Set environment variables in DO App Platform
2. Push code to GitHub
3. DO builds using multi-stage Dockerfile
4. Result: ~2GB image, no certificate issues

### If You Need mTLS in Future
1. Add certificate content to DO environment variables:
   - `TEMPORAL_CLIENT_CERT_CONTENT`
   - `TEMPORAL_CLIENT_KEY_CONTENT`
2. Optionally keep `TEMPORAL_API_KEY` for hybrid auth
3. Code automatically uses mTLS when certificates are present

---

## Docker Multi-Stage Build

The Dockerfile now includes Swift runtime libraries:

```dockerfile
# Copy Swift runtime libraries from builder
COPY --from=builder /usr/lib/swift /usr/lib/swift
```

This enables:
- Multi-stage builds to work correctly
- ~2GB images instead of 12.7GB
- No SSL certificate loading errors

---

## Package Dependencies

Using the API key fix branch:

```swift
.package(url: "https://github.com/Shy/swift-temporal-sdk.git", branch: "apiKeyFix")
```

This branch includes:
- `apiKey` parameter in `TemporalClient.Configuration`
- `apiKey` parameter in `TemporalWorker.Configuration`
- Authorization header automatically added: `Bearer <api-key>`

---

## Migration Guide

### From mTLS to API Key

1. Get API key from Temporal Cloud
2. Update `.env`:
   ```bash
   # Add this
   TEMPORAL_API_KEY=your-key
   TEMPORAL_HOST=us-east-1.aws.api.temporal.io  # Use regional endpoint

   # Comment out or remove these
   # TEMPORAL_CLIENT_CERT=certs/client.pem
   # TEMPORAL_CLIENT_KEY=certs/client.key
   ```
3. Deploy - no code changes needed!

### From API Key to mTLS

1. Generate certificates from Temporal Cloud
2. Add certificate environment variables
3. Change host to namespace-specific endpoint
4. Keep or remove `TEMPORAL_API_KEY` (optional)
5. Deploy - automatically uses mTLS

---

## Testing Locally

```bash
cd server
.build/debug/App serve
```

Expected logs:
```
[ INFO ] ✅ TLS configuration validated (using API key authentication)
[ INFO ] 🔐 Connecting to Temporal Cloud [auth_method: API Key, ...]
[ INFO ] 🔌 Starting Temporal client... [attempt: 1]
[ INFO ] ✅ Temporal client connected successfully
[ INFO ] 👷 Starting Temporal worker... [attempt: 1]
[ INFO ] ✅ Temporal worker running successfully
```

---

## Troubleshooting

### "TLS enabled but authentication configuration incomplete"
- Need either `TEMPORAL_API_KEY` OR certificates
- Check environment variables are set correctly

### "Couldn't create SSL context" (Docker)
- Make sure Swift runtime libraries are copied: `COPY --from=builder /usr/lib/swift /usr/lib/swift`
- This issue should not occur with API key auth

### Worker crashes after 12 seconds
- Old issue with SDK 0.1.0 on Linux
- Fixed in the `apiKeyFix` branch
- Use the branch from GitHub: `https://github.com/Shy/swift-temporal-sdk.git`
