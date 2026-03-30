# BLE Proximity Discovery

## Goal

Add AirDrop-style proximity detection so nearby Beamlet users are automatically highlighted in the share sheet and Send tab. Devices discover each other over BLE; file transfer still goes through the server.

## Current State

- Share extension shows a grid of contacts, user taps one to send
- Send tab loads contacts from API
- No proximity awareness
- No discoverability settings

## Design

### Discoverability Modes

Three user-selectable modes, matching AirDrop's model:

1. **Receiving Off** — device does not advertise over BLE. Invisible to all nearby users. Can still scan and see others.
2. **Contacts Only** — device advertises a hashed identifier. Only existing contacts can recognize you. Strangers see the BLE signal but can't resolve your identity.
3. **Everyone** — device advertises its plain user ID. Any nearby Beamlet user can see your name and send to you.

Default: Contacts Only. Persisted in shared UserDefaults (so share extension can read it).

### BLE Protocol

**Service UUID:** A custom UUID for Beamlet discovery (e.g., `B3AM-0001-...`).

**Advertising payload:** A single characteristic containing the discovery data:
- Contacts Only: `SHA256(userID + "2026-03-30")` truncated to 8 bytes. The daily date string acts as a rotating salt so the hash changes every day, preventing long-term tracking. Contacts can match this because they know the user's ID — they hash each contact ID with today's date and compare.
- Everyone: the raw user ID (UUID string, 36 bytes). Any device can read it and resolve the name via the server.
- Receiving Off: device does not start the peripheral manager / does not advertise.

**Scanning:** All devices scan for the Beamlet BLE service regardless of their own discoverability mode. When a peripheral is discovered:
1. Read the discovery characteristic.
2. If 8 bytes: hashed mode. Compare against `SHA256(contactID + todayDateString)` for each known contact. If match, mark that contact as nearby.
3. If UUID string: Everyone mode. Call `GET /api/users/{id}/profile` to resolve the name. Display as a nearby non-contact.

**RSSI filtering:** Only show devices with RSSI > -70 dBm (roughly within a few meters). This prevents showing users across the building.

### Server Changes

**New endpoint:**

`GET /api/users/{id}/profile` — no auth required. Returns:
```json
{"id": "uuid", "name": "Display Name"}
```

Used by "Everyone" mode to resolve nearby user IDs to display names. Returns 404 if user doesn't exist. Only exposes name — no sensitive data.

**No other server changes.** The existing `POST /api/files` upload endpoint works for non-contacts (it doesn't enforce a contact relationship).

### iOS Architecture

**NearbyService** (`@Observable` class):
- Owns `CBCentralManager` (scanning) and `CBPeripheralManager` (advertising)
- Reads discoverability mode from shared UserDefaults
- Manages advertising based on mode: off, hashed, or plain UUID
- Scans for Beamlet BLE service, reads characteristics
- Resolves discovered devices against contact list (hashed match) or server (Everyone mode)
- Exposes `nearbyUsers: [NearbyUser]` — each has `id`, `name`, `isContact` flag
- Injected via `@Environment` from the app entry point

**NearbyUser model:**
```
struct NearbyUser: Identifiable {
    let id: String
    let name: String
    let isContact: Bool
}
```

**DiscoverabilityMode enum:**
```
enum DiscoverabilityMode: String, CaseIterable {
    case off
    case contactsOnly
    case everyone
}
```

Persisted in `UserDefaults(suiteName: "group.com.beamlet.shared")` under key `discoverabilityMode`.

### UI Changes

**SettingsView:** Add a "Discoverability" picker with three options (Receiving Off / Contacts Only / Everyone) in the existing Settings tab, in a new section above "Server".

**SendView:** Add a "Nearby" section at the top showing nearby users (both contacts and Everyone-mode strangers). Nearby contacts also remain in the main contacts list but are visually marked.

**ShareView (share extension):** Nearby users appear first in the grid. Contacts that are nearby get a subtle ring/glow around their avatar circle. Non-contact nearby users (Everyone mode) appear in the grid with a different color (e.g., gray circle instead of blue) and a "Nearby" label.

**Info.plist additions:**
- `NSBluetoothAlwaysUsageDescription`: "Beamlet uses Bluetooth to discover nearby users for sharing."
- Background mode: `bluetooth-peripheral` (required for BLE peripheral role even in foreground)

### Share Extension BLE

The share extension has limited background execution, but it can:
1. Start scanning when the extension launches
2. Discover nearby devices within the first few seconds
3. Update the UI as devices are found

The extension creates its own `NearbyService` instance (same as the main app creates one). Since the extension is short-lived, BLE scanning starts immediately and results appear within 1-2 seconds.

### Privacy

- Contacts Only mode: strangers cannot identify you from BLE. The hash rotates daily.
- Everyone mode: your user ID is visible to any BLE scanner, but only other Beamlet users can resolve it to a name (via the server endpoint).
- Receiving Off: no BLE advertising at all.
- BLE scanning is passive and doesn't reveal the scanner's identity.

## Out of Scope

- Background BLE (always-on discovery when app is closed)
- Peer-to-peer file transfer over BLE/WiFi Direct
- Profile photos or avatars in nearby user display
- Blocking specific nearby users
