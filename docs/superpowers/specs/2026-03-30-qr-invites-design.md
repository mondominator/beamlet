# QR Code Setup & Contact Invites

## Goal

Replace manual token entry with QR code scanning for app setup, and add a contacts system so users only see people they've explicitly connected with. Any user can invite others.

## Current State

- Users created only via CLI `add-user`, which prints a long hex token
- iOS app requires manual entry of server URL + token
- `GET /api/users` returns all users — no contact/friendship model
- No invite or self-registration flow

## Design

### Contacts Model

Users can only see and send files to people they've connected with. A connection is always mutual — when an invite is redeemed, both parties become contacts.

**Database table: `contacts`**
```sql
CREATE TABLE contacts (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, contact_id)
);
```

Two rows per connection (A→B and B→A) for simple query: `SELECT contact_id FROM contacts WHERE user_id = ?`.

### Invite Tokens

Short-lived, single-use tokens that encode everything needed to onboard a new user or connect an existing one.

**Database table: `invites`**
```sql
CREATE TABLE invites (
    id TEXT PRIMARY KEY,
    token_hash TEXT NOT NULL,
    creator_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_user_id TEXT REFERENCES users(id),
    redeemed_by TEXT REFERENCES users(id),
    expires_at TIMESTAMP NOT NULL,
    redeemed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

- `creator_id` — the user who generated the invite
- `created_user_id` — set when CLI `add-user` creates both a user and an invite (the invite is pre-associated with the new user)
- `redeemed_by` — set when someone redeems the invite
- `token_hash` — bcrypt hash of the invite token (same pattern as auth tokens)
- Tokens expire after 24 hours and are single-use

### QR Code Payload

```json
{"url": "http://192.168.86.250:8080", "invite": "abc123def456"}
```

Encoded as a standard QR code. The iOS app's scanner reads this, extracts the server URL and invite token.

### API Changes

**New public endpoint (no auth required):**

`POST /api/invites/redeem`

Two modes:

1. **New user** (no Authorization header):
   ```json
   // Request
   {"invite_token": "abc123", "name": "Sarah"}

   // Response
   {
     "user_id": "uuid",
     "name": "Sarah",
     "token": "hex-auth-token",
     "contact": {"id": "creator-uuid", "name": "Creator Name"}
   }
   ```
   Server creates the user, creates mutual contact rows, marks invite redeemed.

2. **Existing user** (with Authorization header):
   ```json
   // Request
   {"invite_token": "abc123"}

   // Response
   {
     "contact": {"id": "creator-uuid", "name": "Creator Name"}
   }
   ```
   Server creates mutual contact rows, marks invite redeemed. No new user created.

3. **CLI setup invite** (no Authorization header, invite has `created_user_id` set):
   ```json
   // Request
   {"invite_token": "abc123", "name": "mondo"}

   // Response
   {
     "user_id": "uuid",
     "name": "mondo",
     "token": "hex-auth-token"
   }
   ```
   Server returns the pre-created user's auth token. The `name` field is optional — if provided, it updates the user's name; if omitted, the CLI-assigned name is kept. No contact created (CLI invites are for self-setup, not connecting two users).

**New authenticated endpoints:**

- `POST /api/invites` — create an invite token. Returns `{"invite_token": "abc123", "expires_at": "..."}`.
- `GET /api/contacts` — list the authenticated user's contacts. Returns array of `{"id": "...", "name": "...", "created_at": "..."}`.
- `DELETE /api/contacts/{id}` — remove a contact (deletes both rows in the contacts table).

**Modified endpoints:**

- `GET /api/users` — change to return only the authenticated user's contacts (same behavior as `GET /api/contacts`). This avoids breaking the iOS app immediately while we migrate.

### CLI Changes

`beamlet add-user [name]`:
- Creates the user (as before)
- Also creates an invite token associated with that user (`created_user_id` set)
- Prints the auth token (as before)
- Prints a QR code to the terminal containing `{"url": "http://<detected-ip>:8080", "invite": "token"}`
- Uses a Go QR library (e.g., `github.com/mdp/qrterminal`) for terminal rendering
- Server URL detection: check `BEAMLET_URL` env var, fall back to `http://localhost:$BEAMLET_PORT`

### iOS Changes

**SetupView (modified):**
- Add "Scan QR Code" button above the manual entry form
- Tapping opens the camera scanner
- On scan: parse JSON payload, extract URL + invite token
- Show "Enter your name" screen
- Call `POST /api/invites/redeem` with invite token + name
- Store returned credentials, user is logged in

**SettingsView (modified):**
- Add "Add Contact" row
- Tapping calls `POST /api/invites` to generate an invite token
- Displays a QR code on screen (using `CoreImage` CIFilter `CIQRCodeGenerator`)
- Shows "Have them scan this with Beamlet" instruction
- QR contains `{"url": "server-url", "invite": "token"}`

**QRScannerView (new):**
- Shared camera-based QR scanner using `AVCaptureSession`
- Used by SetupView (new users) and a "Scan Invite" option for existing users
- Parses the JSON payload and returns the URL + invite token

**SendView (no changes needed):**
- Already loads users via API; once `GET /api/users` returns contacts only, it just works

**InboxView (no changes needed):**
- Already shows sender names from file data

**New "Scan Invite" flow for existing users:**
- In Settings, add "Scan Invite" option alongside "Add Contact"
- Opens QR scanner, calls `POST /api/invites/redeem` with auth header
- Shows confirmation: "Connected with [name]!"

## Migration Path

1. Add `contacts` and `invites` tables (new migration)
2. Migrate existing users: create contact rows between all existing users so current behavior is preserved
3. Change `GET /api/users` to return contacts only
4. Update iOS app with QR scanner and invite flows

## Out of Scope

- Contact blocking/muting
- Invite link sharing (text/iMessage) — QR only for now
- Admin role or permissions — any user can invite
- Contact request approval — connections are instant and mutual
