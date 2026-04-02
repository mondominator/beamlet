# Beamlet

Self-hosted file sharing with push notifications. A personal AirDrop replacement that works anywhere.

## Features

- **Share anything** — photos, videos, documents, links, and text messages
- **Push notifications** — instant alerts via Apple Push Notification service
- **BLE proximity discovery** — find nearby users via Bluetooth
- **QR code invites** — easy onboarding for new users
- **Shareable invite links** — invite via iMessage, email, or any messenger
- **iOS share extension** — send directly from any app's share sheet
- **Multi-recipient** — send to multiple contacts at once
- **Read receipts** — see when files are viewed
- **Pin files** — prevent important files from expiring
- **Inbox filters** — filter by photos, videos, messages, links, files
- **Quick reply** — swipe to reply from inbox
- **Dark/light theme** — system, light, or dark mode
- **iPad layout** — sidebar navigation on larger screens

## Architecture

```
iOS App + Share Extension
    ↓
Beamlet Server (Go + SQLite)
    ↓
Apple Push Notifications
```

## Server Setup

### Docker

```bash
docker run -d \
  --name beamlet \
  -p 8080:8080 \
  -v /path/to/data:/data \
  ghcr.io/mondominator/beamlet:latest serve
```

### With Push Notifications

```bash
docker run -d \
  --name beamlet \
  -p 8080:8080 \
  -v /path/to/data:/data \
  -v /path/to/AuthKey.p8:/app/apns_key.p8:ro \
  -e BEAMLET_APNS_KEY_PATH=/app/apns_key.p8 \
  -e BEAMLET_APNS_KEY_ID=YOUR_KEY_ID \
  -e BEAMLET_APNS_TEAM_ID=YOUR_TEAM_ID \
  -e BEAMLET_APNS_BUNDLE_ID=com.beamlet.app \
  -e BEAMLET_EXTERNAL_URL=https://your-domain.com \
  ghcr.io/mondominator/beamlet:latest serve
```

### Create First User

```bash
docker exec beamlet /app/beamlet add-user "YourName"
```

This prints a QR code — scan it with the Beamlet iOS app.

### Unraid

An Unraid template is included. Copy `unraid-template.xml` to your Unraid templates directory.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BEAMLET_PORT` | `8080` | Server port |
| `BEAMLET_DB_PATH` | `/data/beamlet.db` | SQLite database path |
| `BEAMLET_DATA_DIR` | `/data/files` | File storage directory |
| `BEAMLET_MAX_FILE_SIZE` | `524288000` | Max upload size (500MB) |
| `BEAMLET_EXPIRY_DAYS` | `30` | Days before auto-cleanup |
| `BEAMLET_APNS_KEY_PATH` | | Path to .p8 key file |
| `BEAMLET_APNS_KEY_ID` | | APNs Key ID |
| `BEAMLET_APNS_TEAM_ID` | | Apple Team ID |
| `BEAMLET_APNS_BUNDLE_ID` | | iOS bundle identifier |
| `BEAMLET_EXTERNAL_URL` | | Public URL when behind reverse proxy |

## iOS App

Requires iOS 17.0+. Build with Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

```bash
cd ios
xcodegen generate
open Beamlet.xcodeproj
```

## Development

### Server

```bash
cd server
go test ./...
go build -o beamlet .
./beamlet serve
```

### CLI Commands

```bash
beamlet serve          # Start the server
beamlet add-user NAME  # Create a user with QR code
beamlet list-users     # List all users
```

## License

MIT License. See [LICENSE](LICENSE).
