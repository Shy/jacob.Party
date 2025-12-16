# Jacob Party iOS App

Real-time party location tracker for iOS.

## Quick Start

**Requirements:**
- macOS with Xcode installed
- iPhone with iOS 17+ (or use simulator)
- Free Apple ID for code signing

**Build & Install:**

1. Clone the repo:
   ```bash
   git clone https://github.com/Shy/jacob.Party.git
   cd jacob.Party/app/JacobParty
   ```

2. Open in Xcode:
   ```bash
   open JacobParty.xcodeproj
   ```

3. Configure code signing:
   - Select project in left sidebar
   - Select "JacobParty" target
   - Go to "Signing & Capabilities" tab
   - Check "Automatically manage signing"
   - Select your Apple ID in "Team" dropdown
     - If you don't see your Apple ID, add it via Xcode > Settings > Accounts

4. Connect your iPhone and run:
   - Plug in iPhone via USB
   - Select your device from the dropdown (top toolbar)
   - Click Run button (▶︎) or press ⌘R
   - First time: Go to Settings > General > VPN & Device Management > Trust developer

5. Get your Device ID:
   - Once running, tap the Device ID text at the bottom of the app
   - It copies to clipboard
   - Send it to the admin to whitelist your device

## Configuration

Server URL is pre-configured in [Config.xcconfig](JacobParty/Config.xcconfig):
```
SERVER_URL = https://jacob.party
```

For local development, comment out the production URL and uncomment localhost.

## Troubleshooting

**"Failed to create provisioning profile"**
- Change the Bundle Identifier in project settings to something unique
- Example: `com.yourname.JacobParty`

**App expires after 7 days**
- This is normal with free Apple ID signing
- Just rebuild and reinstall from Xcode

**Location permission issues**
- Ensure you granted "Always Allow" for location in Settings
- App needs background location to track while in background

## How It Works

When you press the party button:
- App starts tracking your location
- Updates sent to server every 60 seconds (or 50+ meters moved)
- Background notifications keep you updated
- Server coordinates with other party-goers via Temporal workflows
