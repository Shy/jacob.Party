# jacob.party

A demonstration project for [Apple's Swift SDK for Temporal](https://github.com/apple/swift-temporal-sdk) (1.0).

**The app**: let your friends know when you're out partying so they can come join you. Start the party on your phone; your friends watch your live location on the web.

The 1.0 version is shaped around three parts:
- **iOS app** (SwiftUI) — can run a `TemporalClient` and `TemporalWorker` on-device, or fall back to the original HTTP API path
- **Vapor server** — serves the public web map, queries Temporal for party state, and still exposes compatibility HTTP endpoints
- **Web UI** — Google Maps view of the live party state

## What this demonstrates

The whole party — start, location updates, reason changes, auto-stop, and shutdown — is one durable Temporal workflow. With the Temporal Swift SDK 1.0, the phone itself can be more than an HTTP client: it can connect to Temporal directly, start/signal/query workflows, and run a worker for iOS-compatible workflow/activity code.

| Temporal feature | Where to look |
|---|---|
| **Long-running `@Workflow` struct** | [`PartyWorkflow`](server/Sources/App/Workflows/PartyWorkflow.swift) lives for the duration of the party. State (`isPartying`, `currentLocation`, `reason`, `autoStopAt`) is plain `var` properties on the struct. |
| **Temporal on iOS** | [`TemporalPartyService`](app/JacobParty/JacobParty/TemporalPartyService.swift) starts a `TemporalClient` and `TemporalWorker` from the app when `TEMPORAL_DIRECT_ENABLED=YES`. |
| **Signals** (`@WorkflowSignal mutating func`) | `updateLocation(input: Location)` and `stopParty()` in `PartyWorkflow`. Each `POST /api/party/location` translates to one signal — no new workflow execution per request. |
| **Queries** (`@WorkflowQuery func`) | `getPartyState()` returns a `PartyStateOutput`. `GET /api/state` calls this — read-only, no event written, no activity scheduled. |
| **Updates** (`@WorkflowUpdate mutating func`) | `setReason` and `extendAutoStop` validate input then mutate state, returning a value. Validation throws `ApplicationError(isNonRetryable: true)` so the client gets a clean rejection. |
| **`signalWithStartWorkflow`** | `POST /api/party/start` ([routes.swift](server/Sources/App/routes.swift)). Starts the workflow if it isn't running, signals `updateLocation` if it is — idempotent in either case. |
| **Workflow timers** | `context.sleep(for:)` inside a `TaskGroup` arms an auto-stop timer. The race between the timer task and the stop-signal-driven `context.condition` is the workflow's main loop. |
| **`context.condition`** | The workflow blocks on `context.condition { $0.shouldExit }`. The closure receives the workflow struct, so any signal/update that flips `shouldExit` releases the wait. |
| **Child workflows** | `SendPartyNotificationsWorkflow` is spawned from the parent via `context.executeChildWorkflow(...)`. Isolates push-notification fan-out with its own retry/timeout policy. |
| **Async activity with heartbeats** | `sendPushNotification` in [`PartyActivities`](server/Sources/App/Activities/PartyActivities.swift) calls `ActivityExecutionContext.current?.heartbeat(details: index)` after each subscription. Retries resume from the last heartbeat detail via `info.heartbeatDetails(as: Int.self)`. |
| **Activity retry policies** | Every `executeActivity` call passes a `RetryPolicy` — see `RecordPartyStart` and `SendPushNotification`. |
| **Multiple auth modes** | [`configure.swift`](server/Sources/App/configure.swift) supports plaintext (local dev), TLS + API key, and mTLS — all via env vars. |
| **Worker + client in the same process** | The Vapor server hosts both a `TemporalClient` and a `TemporalWorker`, started in background tasks with retry. |

## Architecture

```
iOS button / HTTP request        Temporal action                  Effect
───────────────────              ──────────────────               ─────────────────
start party                   →  signalWithStartWorkflow       →  Workflow starts (or refreshes)
location update               →  handle.signal(UpdateLocation) →  Mutates state, no new workflow
reason change                 →  handle.executeUpdate(SetReason)  Validates + mutates, returns msg
extend party                  →  handle.executeUpdate(ExtendAutoStop)  Pushes timer further out
stop party                    →  handle.signal(StopParty)      →  shouldExit=true, run() returns
web map poll                  →  handle.query(GetPartyState)   →  Read-only snapshot
```

Inside `PartyWorkflow.run`:
1. Record start (activity).
2. Spawn `SendPartyNotificationsWorkflow` as a child (TaskGroup task).
3. Arm an auto-stop timer (TaskGroup task).
4. Wait on `context.condition { $0.shouldExit }`.
5. Whichever fires first — stop signal or auto-stop timer — falls through to record-end (activity) and return a `PartyResult`.

## Quick start

```bash
# 1. Start a local Temporal dev server
temporal server start-dev    # UI at http://localhost:8233

# 2. Configure env (uses plaintext + no auth by default)
cp .env.example .env
cp .env server/.env

# 3. Run the server
cd server && swift build && .build/debug/App serve

# 4. Drive it
http POST localhost:8080/api/party/start \
  location:='{"lat":37.7749,"lng":-122.4194}' \
  reason=demo \
  autoStopHours:=2

http GET  localhost:8080/api/state

http POST localhost:8080/api/party/location \
  location:='{"lat":37.7849,"lng":-122.4094}'

http POST localhost:8080/api/party/reason reason="celebrating-1.0"

http POST localhost:8080/api/party/extend additionalHours:=2

http POST localhost:8080/api/party/stop
```

Open http://localhost:8233 to see the workflow, signals, child workflow, and timer events in the UI.

## Prerequisites

- Swift 6.2+
- macOS 15+ / iOS 18+
- Temporal Server (local dev) or Temporal Cloud
- Xcode 16+ (only for the iOS app)

## iOS app

```bash
open app/JacobParty/JacobParty.xcodeproj
```

The visible UI is still the single party button. Under the hood, the app now has two transport modes:

- `TEMPORAL_DIRECT_ENABLED=NO` (default): original HTTP mode. The app calls Vapor, and Vapor drives Temporal.
- `TEMPORAL_DIRECT_ENABLED=YES`: iOS Temporal mode. The app starts a `TemporalClient` and `TemporalWorker`, then starts/signals `PartyWorkflow` directly through the Temporal Swift SDK.

For real-device local testing, set `TEMPORAL_HOST` to your Mac's LAN IP address, not `127.0.0.1`. For the video path, use Temporal Cloud with TLS and an API key in an uncommitted local config.

The app still generates a UUID at first launch (stored in Keychain) and sends it as `X-Device-ID` on the HTTP path. Add allowed UUIDs to `ALLOWED_DEVICE_IDS` in `.env` (empty = all devices allowed).

## Temporal Cloud

```env
TEMPORAL_TLS_ENABLED=true
TEMPORAL_HOST=your-namespace.tmprl.cloud
TEMPORAL_NAMESPACE=your-namespace
# Choose one (or both for max security):
TEMPORAL_API_KEY=your-api-key
TEMPORAL_CLIENT_CERT=certs/client.pem
TEMPORAL_CLIENT_KEY=certs/client.key
```

See [certs/README.md](certs/README.md) for mTLS certificate setup.

## Container deployment

```bash
cd server
docker build -t jacob-party .
docker run -p 8080:8080 --env-file ../.env jacob-party
# Or:
docker-compose up -d
```

For mTLS, mount the cert directory: `-v $(pwd)/../certs:/app/certs:ro`.

## Key files

- [server/Sources/App/Workflows/PartyWorkflow.swift](server/Sources/App/Workflows/PartyWorkflow.swift) — `PartyWorkflow` + `SendPartyNotificationsWorkflow`
- [server/Sources/App/Activities/PartyActivities.swift](server/Sources/App/Activities/PartyActivities.swift) — including the heartbeating push-notification activity
- [server/Sources/App/routes.swift](server/Sources/App/routes.swift) — HTTP → signals/queries/updates
- [server/Sources/App/configure.swift](server/Sources/App/configure.swift) — client/worker setup, auth modes
- [server/Sources/App/Models/PartyModels.swift](server/Sources/App/Models/PartyModels.swift) — workflow input/output and update/query payloads
- [app/JacobParty/JacobParty/TemporalPartyService.swift](app/JacobParty/JacobParty/TemporalPartyService.swift) — on-device Temporal client/worker lifecycle
- [app/JacobParty/JacobParty/TemporalPartyWorkflow.swift](app/JacobParty/JacobParty/TemporalPartyWorkflow.swift) — iOS-compatible workflow used by direct mode

## Debugging

**Temporal UI**: http://localhost:8233 — drill into a `PartyWorkflow` execution to see signals, the child `SendPartyNotificationsWorkflow`, and the auto-stop `TIMER_STARTED`/`TIMER_CANCELED` events.

**CLI**:
```bash
temporal workflow list
temporal workflow describe --workflow-id jacob-party
temporal workflow show --workflow-id jacob-party --output json | jq '.events[] | .eventType'
```

**Common issues**:
- Map blank? `GOOGLE_MAPS_API_KEY` missing or Maps JavaScript API not enabled.
- Server won't start? Verify `temporal server start-dev` is running and port 8080 is free.
- iOS not updating? Check "Always Allow" location permission and that a party is active.
