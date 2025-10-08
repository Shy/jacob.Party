# jacob.party iOS App

SwiftUI iPhone app with 3D party button, background location tracking, and 6-hour timeout notifications.

## Features

- ✅ **3D Party Button** - SceneKit-powered interactive button with press animation
- ✅ **Location Tracking** - Background GPS tracking while partying
- ✅ **6-Hour Timeout** - Automatic notification after 6 hours with option to continue
- ✅ **Haptic Feedback** - Satisfying tactile response on button press
- ✅ **Network Integration** - Full HTTP API integration with Vapor server
- ✅ **State Synchronization** - Fetches initial state from server on launch

## Project Structure

```
app/JacobParty/
├── JacobParty.xcodeproj/          # Xcode project file
└── JacobParty/                    # Source files
    ├── Assets.xcassets/           # App assets
    ├── Info.plist                 # Permissions and capabilities
    ├── JacobPartyApp.swift        # App entry point
    ├── ContentView.swift          # Main view with layout
    ├── PartyButton3DView.swift    # 3D button with SceneKit
    ├── PartyViewModel.swift       # State management + network calls
    ├── LocationManager.swift      # Background GPS tracking
    └── NotificationManager.swift  # 6-hour timeout notifications
```

## Building & Running

1. Open the Xcode project:
   ```bash
   open app/JacobParty/JacobParty.xcodeproj
   ```

2. Select iPhone simulator or device

3. Run (⌘R)

4. Grant permissions:
   - **Location**: "Allow While Using App" → then "Change to Always Allow"
   - **Notifications**: "Allow" for timeout alerts

## API Integration

The app communicates with the Vapor server at `http://127.0.0.1:8080`:

**Endpoints Used:**
- `GET /api/state` - Fetch current party state on launch
- `POST /api/party/start` - Start party with location
- `POST /api/party/stop` - Stop party

**To Change Server URL:**
Edit [PartyViewModel.swift](JacobParty/PartyViewModel.swift#L13):
```swift
private let baseURL = "https://yourserver.com"  // Change from localhost
```

## Permissions

Configured in [Info.plist](JacobParty/Info.plist):

- **NSLocationWhenInUseUsageDescription** - Initial location permission
- **NSLocationAlwaysAndWhenInUseUsageDescription** - Background location
- **UIBackgroundModes** - `location` for background GPS updates

## How It Works

1. **Launch**: App fetches initial state from server
2. **Start Party**: Tap button → sends location to server via Temporal workflow
3. **Background Tracking**: GPS continues updating even when app is backgrounded
4. **6-Hour Timer**: Notification appears after 6 hours
5. **Notification Actions**:
   - "Keep Partying" → Reschedules for 6 more hours
   - "Stop Party" → Ends party immediately
   - Tap notification → Auto-stops party

## Development Notes

- **State Management**: Uses `@Published` properties with Combine
- **Network**: Async/await with URLSession
- **Location**: CoreLocation with background updates enabled
- **Notifications**: UserNotifications framework with interactive actions
- **UI**: SwiftUI + SceneKit for 3D button

## Requirements

- iOS 15.0+
- Xcode 16.0+
- Swift 6.0+

Built for jacob.party! 🎉
