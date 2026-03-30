# BLE Proximity Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add BLE-based proximity detection so nearby Beamlet users appear automatically in the share sheet and Send tab, with AirDrop-style discoverability settings.

**Architecture:** CoreBluetooth peripheral/central on each device. Peripheral advertises a custom service; central scans and connects to read a discovery characteristic. Contacts Only mode uses a daily-rotating SHA256 hash; Everyone mode broadcasts the plain user ID. A new `NearbyService` class manages all BLE logic and exposes observable `nearbyUsers`.

**Tech Stack:** CoreBluetooth, CryptoKit (SHA256), SwiftUI

**Prerequisites:** The QR invites branch must be merged. The server must have the contacts system in place.

---

## File Structure

### Server (new/modified)
```
server/
├── internal/api/
│   ├── me_handler.go              # GET /api/me — return current user
│   ├── me_handler_test.go
│   └── router.go                  # Add /api/me and /api/users/{id}/profile routes
```

### iOS (new files)
```
ios/Beamlet/
├── Model/
│   └── NearbyUser.swift           # NearbyUser struct + DiscoverabilityMode enum
├── Data/
│   └── NearbyService.swift        # CoreBluetooth BLE discovery manager
```

### iOS (modified files)
```
ios/Beamlet/
├── Data/
│   ├── AuthRepository.swift       # Add userID storage
│   └── BeamletAPI.swift           # Add getMe(), getProfile() methods
├── App/
│   └── BeamletApp.swift           # Initialize and inject NearbyService
├── Presentation/
│   ├── Setup/
│   │   └── SetupView.swift        # Store userID on connect
│   ├── Setup/
│   │   └── NameEntryView.swift    # Store userID on redeem
│   ├── Send/
│   │   ├── SendView.swift         # Add Nearby section
│   │   └── SendViewModel.swift    # Load nearby users
│   ├── Settings/
│   │   └── SettingsView.swift     # Add discoverability picker
│   └── Components/
│       └── MainTabView.swift      # Pass NearbyService to tabs
├── Resources/
│   └── Info.plist                 # Add Bluetooth usage description
└── project.yml                    # (if background mode needed)
ios/BeamletShare/
└── ShareView.swift                # Show nearby users first in grid
```

---

### Task 1: Server — /api/me and /api/users/{id}/profile Endpoints

**Files:**
- Create: `server/internal/api/me_handler.go`
- Create: `server/internal/api/me_handler_test.go`
- Modify: `server/internal/api/router.go`

- [ ] **Step 1: Write me handler test**

Create `server/internal/api/me_handler_test.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestGetMe(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	contactStore := store.NewContactStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, aliceToken, _ := userStore.Create("Alice")

	srv := &Server{
		UserStore:    userStore,
		ContactStore: contactStore,
		InviteStore:  inviteStore,
	}
	router := NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/me", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var user model.User
	json.NewDecoder(w.Body).Decode(&user)
	if user.ID != alice.ID || user.Name != "Alice" {
		t.Fatalf("expected Alice, got %+v", user)
	}
}

func TestGetUserProfile(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	contactStore := store.NewContactStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	srv := &Server{
		UserStore:    userStore,
		ContactStore: contactStore,
		InviteStore:  inviteStore,
	}
	router := NewRouter(srv)

	// No auth needed for profile
	req := httptest.NewRequest("GET", "/api/users/"+alice.ID+"/profile", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.ID != alice.ID || resp.Name != "Alice" {
		t.Fatalf("expected Alice, got %+v", resp)
	}
}

func TestGetUserProfile_NotFound(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	contactStore := store.NewContactStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	srv := &Server{
		UserStore:    userStore,
		ContactStore: contactStore,
		InviteStore:  inviteStore,
	}
	router := NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/users/nonexistent/profile", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}
```

- [ ] **Step 2: Implement me handler**

Create `server/internal/api/me_handler.go`:

```go
package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
)

func (s *Server) GetMe(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"id":   user.ID,
		"name": user.Name,
	})
}

func (s *Server) GetUserProfile(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")

	user, err := s.UserStore.GetByID(userID)
	if err != nil {
		http.Error(w, "user not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"id":   user.ID,
		"name": user.Name,
	})
}
```

- [ ] **Step 3: Add routes**

In `server/internal/api/router.go`, add to the public routes section (alongside `/invites/redeem`):

```go
		r.Get("/users/{id}/profile", s.GetUserProfile)
```

And add to the authenticated routes section:

```go
			r.Get("/me", s.GetMe)
```

- [ ] **Step 4: Run tests**

```bash
cd server
go test ./internal/api/ -run "TestGetMe|TestGetUserProfile" -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/internal/api/me_handler.go server/internal/api/me_handler_test.go server/internal/api/router.go
git commit -m "feat: add /api/me and /api/users/{id}/profile endpoints"
```

---

### Task 2: iOS Models — NearbyUser and DiscoverabilityMode

**Files:**
- Create: `ios/Beamlet/Model/NearbyUser.swift`

- [ ] **Step 1: Create model file**

Create `ios/Beamlet/Model/NearbyUser.swift`:

```swift
import Foundation

struct NearbyUser: Identifiable, Hashable {
    let id: String
    let name: String
    let isContact: Bool
}

enum DiscoverabilityMode: String, CaseIterable {
    case off
    case contactsOnly
    case everyone

    var displayName: String {
        switch self {
        case .off: return "Receiving Off"
        case .contactsOnly: return "Contacts Only"
        case .everyone: return "Everyone"
        }
    }

    var description: String {
        switch self {
        case .off: return "You won't be visible to nearby users"
        case .contactsOnly: return "Only your contacts can see you nearby"
        case .everyone: return "Anyone with Beamlet nearby can see you"
        }
    }

    static func load() -> DiscoverabilityMode {
        let raw = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "discoverabilityMode") ?? "contactsOnly"
        return DiscoverabilityMode(rawValue: raw) ?? .contactsOnly
    }

    func save() {
        UserDefaults(suiteName: "group.com.beamlet.shared")?.set(rawValue, forKey: "discoverabilityMode")
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add Beamlet/Model/NearbyUser.swift
git commit -m "feat(ios): add NearbyUser model and DiscoverabilityMode enum"
```

---

### Task 3: iOS AuthRepository — Store User ID, API Methods

**Files:**
- Modify: `ios/Beamlet/Data/AuthRepository.swift`
- Modify: `ios/Beamlet/Data/BeamletAPI.swift`
- Modify: `ios/Beamlet/Presentation/Setup/SetupView.swift`
- Modify: `ios/Beamlet/Presentation/Setup/NameEntryView.swift`

- [ ] **Step 1: Add userID to AuthRepository**

In `ios/Beamlet/Data/AuthRepository.swift`, add a `userID` property alongside the existing `token` and `serverURL`:

Add to the properties:
```swift
    private(set) var userID: String?
```

In `loadStoredCredentials()`, add:
```swift
        userID = defaults?.string(forKey: "userID")
```

In `store(serverURL:token:)`, add a new method that also stores the user ID. Add this method:
```swift
    func storeUserID(_ id: String) {
        self.userID = id
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(id, forKey: "userID")
    }
```

In `clear()`, add:
```swift
        userID = nil
```
and:
```swift
        defaults?.removeObject(forKey: "userID")
```

- [ ] **Step 2: Add API methods**

In `ios/Beamlet/Data/BeamletAPI.swift`, add these methods inside the class:

```swift
    // MARK: - Profile

    struct MeResponse: Codable {
        let id: String
        let name: String
    }

    func getMe() async throws -> MeResponse {
        try await request("/api/me")
    }

    func getProfile(userID: String) async throws -> MeResponse {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("/api/users/\(userID)/profile")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }

        return try decoder.decode(MeResponse.self, from: data)
    }
```

- [ ] **Step 3: Store userID during manual connect**

In `ios/Beamlet/Presentation/Setup/SetupView.swift`, in the `connect()` method, after `let _ = try await api.listUsers()` succeeds, add:

```swift
                // Fetch and store user ID
                if let me = try? await api.getMe() {
                    authRepository.storeUserID(me.id)
                }
```

- [ ] **Step 4: Store userID during QR redeem**

In `ios/Beamlet/Presentation/Setup/NameEntryView.swift`, in the `submit()` method, after `authRepository.store(serverURL: serverURL, token: token)`, add:

```swift
                if let userID = response.userID {
                    authRepository.storeUserID(userID)
                }
```

- [ ] **Step 5: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): store userID in AuthRepository, add getMe/getProfile API methods"
```

---

### Task 4: iOS Info.plist — Bluetooth Permission

**Files:**
- Modify: `ios/Beamlet/Resources/Info.plist`

- [ ] **Step 1: Add Bluetooth usage description**

Add inside the top-level `<dict>` in `ios/Beamlet/Resources/Info.plist`:

```xml
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Beamlet uses Bluetooth to discover nearby users for sharing.</string>
    <key>UIBackgroundModes</key>
    <array>
        <string>bluetooth-peripheral</string>
        <string>bluetooth-central</string>
    </array>
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add Beamlet/Resources/Info.plist
git commit -m "feat(ios): add Bluetooth usage description and background modes"
```

---

### Task 5: iOS NearbyService — Core BLE Logic

**Files:**
- Create: `ios/Beamlet/Data/NearbyService.swift`

- [ ] **Step 1: Create NearbyService**

Create `ios/Beamlet/Data/NearbyService.swift`:

```swift
import Foundation
import CoreBluetooth
import CryptoKit

@Observable
class NearbyService: NSObject {
    private(set) var nearbyUsers: [NearbyUser] = []

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var discoveryCharacteristic: CBMutableCharacteristic?

    private let userID: String
    private let api: BeamletAPI
    private var contactIDs: Set<String> = []
    private var contactNames: [String: String] = [:]
    private var discoveredPeers: [String: NearbyUser] = [:]
    private var resolvedProfiles: [String: String] = [:]

    var mode: DiscoverabilityMode {
        didSet {
            mode.save()
            restartAdvertising()
        }
    }

    static let serviceUUID = CBUUID(string: "B3AE0001-1E70-4000-8000-00805F9B34FB")
    static let characteristicUUID = CBUUID(string: "B3AE0002-1E70-4000-8000-00805F9B34FB")

    init(userID: String, api: BeamletAPI) {
        self.userID = userID
        self.api = api
        self.mode = DiscoverabilityMode.load()
        super.init()
    }

    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        nearbyUsers = []
        discoveredPeers = [:]
    }

    func updateContacts(_ contacts: [BeamletUser]) {
        contactIDs = Set(contacts.map(\.id))
        contactNames = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0.name) })
    }

    // MARK: - Discovery Hash

    private func discoveryHash(for id: String) -> Data {
        let dateString = Self.todayString()
        let input = Data("\(id)\(dateString)".utf8)
        let hash = SHA256.hash(data: input)
        return Data(hash.prefix(8))
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    // MARK: - Advertising

    private func restartAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()

        guard mode != .off, peripheralManager?.state == .poweredOn else { return }

        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: .read,
            value: advertisingPayload(),
            permissions: .readable
        )
        discoveryCharacteristic = characteristic

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager?.add(service)
    }

    private func advertisingPayload() -> Data {
        switch mode {
        case .off:
            return Data()
        case .contactsOnly:
            return Data([0x01]) + discoveryHash(for: userID)
        case .everyone:
            return Data([0x02]) + Data(userID.utf8)
        }
    }

    // MARK: - Scanning / Resolving

    private func handleDiscoveredPayload(_ data: Data, rssi: NSNumber) {
        guard rssi.intValue > -70 else { return } // Too far away

        guard let modeByte = data.first else { return }

        if modeByte == 0x01 {
            // Contacts Only — try to match hash against known contacts
            let hash = data.dropFirst()
            for contactID in contactIDs {
                if discoveryHash(for: contactID) == hash {
                    let name = contactNames[contactID] ?? "Unknown"
                    addNearbyUser(NearbyUser(id: contactID, name: name, isContact: true))
                    return
                }
            }
        } else if modeByte == 0x02 {
            // Everyone — extract user ID, resolve name
            let peerID = String(data: data.dropFirst(), encoding: .utf8) ?? ""
            guard !peerID.isEmpty, peerID != userID else { return }

            if let name = contactNames[peerID] {
                addNearbyUser(NearbyUser(id: peerID, name: name, isContact: true))
            } else if let cached = resolvedProfiles[peerID] {
                addNearbyUser(NearbyUser(id: peerID, name: cached, isContact: false))
            } else {
                Task {
                    if let profile = try? await api.getProfile(userID: peerID) {
                        resolvedProfiles[peerID] = profile.name
                        await MainActor.run {
                            addNearbyUser(NearbyUser(id: peerID, name: profile.name, isContact: false))
                        }
                    }
                }
            }
        }
    }

    private func addNearbyUser(_ user: NearbyUser) {
        discoveredPeers[user.id] = user
        nearbyUsers = Array(discoveredPeers.values).sorted { a, b in
            if a.isContact != b.isContact { return a.isContact }
            return a.name < b.name
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension NearbyService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Ignore connection failures silently
    }
}

// MARK: - CBPeripheralDelegate

extension NearbyService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else { return }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        // Get RSSI for distance filtering
        peripheral.readRSSI()

        // Store data temporarily, process when RSSI arrives
        objc_setAssociatedObject(peripheral, "discoveryData", data, .OBJC_ASSOCIATION_RETAIN)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let data = objc_getAssociatedObject(peripheral, "discoveryData") as? Data {
            handleDiscoveredPayload(data, rssi: RSSI)
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension NearbyService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            restartAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error == nil {
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
            ])
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add Beamlet/Data/NearbyService.swift
git commit -m "feat(ios): add NearbyService with BLE advertising and scanning"
```

---

### Task 6: iOS BeamletApp — Wire Up NearbyService

**Files:**
- Modify: `ios/Beamlet/App/BeamletApp.swift`

- [ ] **Step 1: Add NearbyService to app**

In `ios/Beamlet/App/BeamletApp.swift`:

Add a new `@State` property alongside the existing ones:
```swift
    @State private var nearbyService: NearbyService?
```

In the `body` computed property, add `.environment(nearbyService)` after `.environment(api)` (using optional environment). Actually, since NearbyService is optional (no userID until authenticated), inject it conditionally. Replace the `.task` modifier with:

```swift
                .task {
                    if authRepository.isAuthenticated {
                        await requestNotificationPermission()
                        await registerExistingDeviceToken()
                        startNearbyService()
                    }
                }
```

Add the environment injection (after `.environment(api)`):
```swift
                .environment(nearbyService)
```

Add the helper method:
```swift
    private func startNearbyService() {
        guard let userID = authRepository.userID else { return }
        if nearbyService == nil {
            let service = NearbyService(userID: userID, api: api)
            nearbyService = service
        }
        nearbyService?.start()
    }
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add Beamlet/App/BeamletApp.swift
git commit -m "feat(ios): wire up NearbyService in app entry point"
```

---

### Task 7: iOS SettingsView — Discoverability Picker

**Files:**
- Modify: `ios/Beamlet/Presentation/Settings/SettingsView.swift`

- [ ] **Step 1: Add discoverability section**

In `ios/Beamlet/Presentation/Settings/SettingsView.swift`:

Add an environment property:
```swift
    @Environment(NearbyService.self) private var nearbyService: NearbyService?
```

Add a state property:
```swift
    @State private var discoverability: DiscoverabilityMode = .load()
```

Add a new section at the top of the List (before the "Contacts" section):

```swift
                Section {
                    Picker("Discoverability", selection: $discoverability) {
                        ForEach(DiscoverabilityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: discoverability) {
                        nearbyService?.mode = discoverability
                    }
                } header: {
                    Text("Discoverability")
                } footer: {
                    Text(discoverability.description)
                }
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add Beamlet/Presentation/Settings/SettingsView.swift
git commit -m "feat(ios): add discoverability picker to settings"
```

---

### Task 8: iOS SendView — Nearby Section

**Files:**
- Modify: `ios/Beamlet/Presentation/Send/SendViewModel.swift`
- Modify: `ios/Beamlet/Presentation/Send/SendView.swift`

- [ ] **Step 1: Update SendViewModel to accept nearby users**

In `ios/Beamlet/Presentation/Send/SendViewModel.swift`, add a property:

```swift
    var nearbyUserIDs: Set<String> = []
```

- [ ] **Step 2: Update SendView**

In `ios/Beamlet/Presentation/Send/SendView.swift`:

Add environment property:
```swift
    @Environment(NearbyService.self) private var nearbyService: NearbyService?
```

In the Form, before the existing "Recipient" section, add a "Nearby" section:

```swift
                    if let nearby = nearbyService?.nearbyUsers, !nearby.isEmpty {
                        Section("Nearby") {
                            ForEach(nearby) { user in
                                Button {
                                    vm.selectedUser = vm.users.first(where: { $0.id == user.id })
                                        ?? BeamletUser(id: user.id, name: user.name, createdAt: nil)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(user.isContact ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                                .frame(width: 40, height: 40)
                                            Text(user.name.prefix(1).uppercased())
                                                .font(.headline)
                                                .foregroundStyle(user.isContact ? .blue : .secondary)
                                        }
                                        VStack(alignment: .leading) {
                                            Text(user.name)
                                                .foregroundStyle(.primary)
                                            Text(user.isContact ? "Contact" : "Nearby")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
```

Also add a `.task` to update nearby service contacts when users load. After the existing `.task { await vm.loadUsers() }`, add:

```swift
                .onChange(of: vm.users) {
                    nearbyService?.updateContacts(vm.users)
                }
```

- [ ] **Step 3: Commit**

```bash
cd ios
git add Beamlet/Presentation/Send/SendView.swift Beamlet/Presentation/Send/SendViewModel.swift
git commit -m "feat(ios): add Nearby section to Send tab"
```

---

### Task 9: iOS ShareView — Nearby Users in Grid

**Files:**
- Modify: `ios/BeamletShare/ShareView.swift`

- [ ] **Step 1: Add NearbyService to share extension**

In `ios/BeamletShare/ShareView.swift`:

Add imports at top:
```swift
import CoreBluetooth
import CryptoKit
```

Add properties:
```swift
    @State private var nearbyService: NearbyService?
    @State private var nearbyUsers: [NearbyUser] = []
```

In `loadData()`, after `contacts = (try? await api.listUsers()) ?? []`, add:

```swift
        // Start BLE scanning
        if let userID = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "userID") {
            let service = NearbyService(userID: userID, api: api)
            service.updateContacts(contacts)
            service.start()
            nearbyService = service
        }
```

Add a timer to poll nearby users. After the `isLoading = false` at the end of `loadData()`, add:

```swift
        // Poll for nearby users
        Task {
            for _ in 0..<10 { // Poll for ~5 seconds
                try? await Task.sleep(for: .milliseconds(500))
                if let service = nearbyService {
                    nearbyUsers = service.nearbyUsers
                }
            }
        }
```

In the contact grid, modify the `ForEach(contacts)` to show nearby contacts first. Replace the grid content with:

```swift
                        // Nearby non-contacts first
                        ForEach(nearbyUsers.filter { !$0.isContact }) { user in
                            contactButton(
                                id: user.id,
                                name: user.name,
                                isNearby: true,
                                isContact: false
                            )
                        }

                        // Then all contacts (nearby ones marked)
                        ForEach(contacts) { contact in
                            contactButton(
                                id: contact.id,
                                name: contact.name,
                                isNearby: nearbyUsers.contains(where: { $0.id == contact.id }),
                                isContact: true
                            )
                        }
```

Extract the button into a helper function (add as a method on ShareView):

```swift
    @ViewBuilder
    private func contactButton(id: String, name: String, isNearby: Bool, isContact: Bool) -> some View {
        Button {
            sendTo(BeamletUser(id: id, name: name, createdAt: nil))
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isContact ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 60, height: 60)
                        .overlay {
                            if isNearby {
                                Circle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .frame(width: 66, height: 66)
                            }
                        }

                    if sendingTo == id {
                        ProgressView()
                    } else {
                        Text(name.prefix(1).uppercased())
                            .font(.title2.bold())
                            .foregroundStyle(isContact ? .blue : .secondary)
                    }
                }

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .disabled(sendingTo != nil)
    }
```

Update `sendTo` to accept `BeamletUser` instead of using the contacts array (it already does).

- [ ] **Step 2: Commit**

```bash
cd ios
git add BeamletShare/ShareView.swift
git commit -m "feat(ios): show nearby users in share extension grid"
```

---

### Task 10: Build Verification

- [ ] **Step 1: Run server tests**

```bash
cd server
go test ./... -v
```

Expected: All pass

- [ ] **Step 2: Build and run iOS**

```bash
cd ios
xcodegen generate
xcodebuild -scheme Beamlet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Install on devices**

```bash
xcodebuild -scheme Beamlet -destination 'platform=iOS,id=00008110-000C48680C9A201E' build
xcrun devicectl device install app --device 00008110-000C48680C9A201E <path-to-app>
xcrun devicectl device install app --device 00008101-000955A61A8B001E <path-to-app>
```

- [ ] **Step 4: Commit any generated changes**

```bash
git add .
git commit -m "chore: regenerate Xcode project with Bluetooth support"
```

---

## Manual Testing

1. Open Beamlet on iPhone, go to Settings → verify "Discoverability" picker shows (default: Contacts Only)
2. Open Beamlet on iPad, same check
3. On iPhone Send tab, verify "Nearby" section appears when iPad is nearby
4. Share a photo via share sheet, verify nearby contacts have a blue ring
5. Set discoverability to "Receiving Off" on iPad, verify it disappears from iPhone's nearby list
6. Set to "Everyone" on iPad, create a non-contact user on a third device, verify it appears as a gray nearby user
