# Beamlet — Design Spec

**Date:** 2026-03-30
**Status:** Approved

## Overview

Beamlet is a self-hosted file sharing app for iOS — a personal AirDrop replacement that works reliably. Users share photos, videos, documents, links, and text via the iOS share sheet. Files route through a self-hosted server, so sharing works from anywhere (not just the same WiFi network).

## Target Users

Small group of known users (starting with two, expandable). Not intended for public distribution.

## Components

### 1. Beamlet Server (Go)

A single Go binary that handles file uploads/downloads, user management, and push notifications. Runs in a Docker container on Unraid behind an nginx reverse proxy.

**Stack:**
- Go (standard library + minimal dependencies)
- SQLite for metadata
- Local disk for file storage (Docker volume)
- APNs for push notifications
- Database migrations from day one (using golang-migrate)

**File Storage:**
- Files stored on disk at `/data/files/{year}/{month}/{uuid}.ext`
- Thumbnails generated on upload for images and videos
- Text and links stored as metadata-only entries (no file on disk)
- Auto-cleanup: files expire after 30 days (configurable)
- Max file size: 500MB (configurable)
- Background goroutine runs daily for purging expired files

**User Management:**
- Users created via CLI: `beamlet add-user "Sarah"` — prints an API token
- Token stored in iOS Keychain on the device
- Device setup via QR code scan or manual token paste
- One user can have multiple devices
- No sign-up flow initially; designed so one can bolt on later

**CLI Commands:**
- `beamlet add-user <name>` — create user, print token
- `beamlet list-users` — show all users
- `beamlet revoke-token <user>` — regenerate a user's token
- `beamlet serve` — start the server

**API Endpoints:**

All endpoints require `Authorization: Bearer <token>` header. Server speaks plain HTTP; nginx handles TLS.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/api/auth/register-device` | Register APNs device token |
| `GET` | `/api/users` | List all users (for recipient picker) |
| `POST` | `/api/files` | Upload a file (multipart) |
| `GET` | `/api/files` | List received files (paginated) |
| `GET` | `/api/files/{id}` | Download a file |
| `GET` | `/api/files/{id}/thumbnail` | Get thumbnail |
| `DELETE` | `/api/files/{id}` | Delete a received file |
| `PUT` | `/api/files/{id}/read` | Mark as read |

**Push Notifications:**
- APNs directly (no Firebase)
- Requires Apple Developer Program membership (already have one)
- Rich notifications with image previews in the banner
- Server sends push on file receipt containing: sender name, file type, thumbnail for images
- Each device registers its APNs device token on app launch
- Failed push delivery marks device as inactive

**Deployment:**
- Dockerfile producing a single-stage Go binary
- Docker Compose for easy deployment on Unraid
- Persistent volume for `/data` (database + files)
- Sits behind existing nginx reverse proxy (plain HTTP internally)
- Environment variables for configuration (APNs key path, file size limit, expiry days, etc.)

### 2. Beamlet iOS App (Swift)

Native iOS app with a share extension. Requires Apple Developer Program for distribution via TestFlight or direct install.

**Main App Views:**

- **Inbox** — List of received files, newest first. Shows thumbnails/previews, sender name, timestamp. Unread indicator for new items.
- **File viewer** — Images display inline, videos play, documents open in preview controller, links open in Safari.
- **Send** — Pick recipient, pick file from photos/files, send. Secondary to share extension but useful for browsing.
- **Settings** — Server URL, token entry (QR scan or manual paste), notification preferences.

**Share Extension:**
- Appears in iOS share sheet as "Beamlet"
- Compact UI: recipient picker, optional message, send button
- Handles photos, videos, files, links, text
- Uploads to server in background

**Notification Handling:**
- Tapping notification opens app directly to the received file
- Rich notifications show image preview in banner
- Registers APNs device token with server on each launch

## Database Schema (SQLite)

**users:**
- `id` (TEXT, UUID primary key)
- `name` (TEXT)
- `token_hash` (TEXT) — bcrypt hash of the API token
- `created_at` (TIMESTAMP)

**devices:**
- `id` (TEXT, UUID primary key)
- `user_id` (TEXT, FK → users)
- `apns_token` (TEXT)
- `platform` (TEXT) — "ios" or "macos"
- `active` (BOOLEAN)
- `created_at` (TIMESTAMP)
- `updated_at` (TIMESTAMP)

**files:**
- `id` (TEXT, UUID primary key)
- `sender_id` (TEXT, FK → users)
- `recipient_id` (TEXT, FK → users)
- `filename` (TEXT) — original filename
- `file_path` (TEXT) — path on disk
- `thumbnail_path` (TEXT, nullable)
- `file_type` (TEXT) — MIME type
- `file_size` (INTEGER) — bytes
- `content_type` (TEXT) — "file", "text", "link"
- `text_content` (TEXT, nullable) — for text/link entries
- `message` (TEXT, nullable) — optional message from sender
- `read` (BOOLEAN, default false)
- `expires_at` (TIMESTAMP)
- `created_at` (TIMESTAMP)

## Future Features (Out of Scope)

- **User sign-up flow** — web or in-app registration with invite/approval mechanism
- **Nearby detection via Bluetooth LE** — detect nearby Beamlet users and surface them as default recipients (GitHub issue to be created)
- **Mac app** — native macOS client
- **S3/object storage backend** — swap local disk for cloud storage if needed
- **Postgres backend** — swap SQLite if concurrent usage demands it

## Design Decisions

- **Go over Node.js:** Single binary, minimal dependencies, trivially deployable, scales well if needed later.
- **SQLite over Postgres:** Sufficient for small group usage, zero additional infrastructure. Schema designed for easy migration to Postgres later.
- **APNs direct over Firebase:** No Google dependency, more reliable for iOS-only use case, full control.
- **Token auth over OAuth/passwords:** Simplest secure approach for a known small group. Sign-up flow can layer on top later.
- **Server-routed over peer-to-peer:** Reliable from anywhere, no "same WiFi" requirement that makes AirDrop flaky.
- **Docker on Unraid:** Matches existing infrastructure, easy to manage alongside other services.
