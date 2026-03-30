# Beamlet iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS app with share extension that lets users send and receive files through the Beamlet server, with push notifications for incoming files.

**Architecture:** SwiftUI app using `@Observable` pattern (iOS 17+). Lightweight ViewModels (`@Observable` classes) for views with async work (Inbox, Send). API and AuthRepository injected as direct `@Environment` objects (not custom EnvironmentKeys). XcodeGen for project generation. Share extension uses App Groups to share auth credentials with the main app.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, XcodeGen, UserNotifications, App Groups

**Prerequisites:** This plan must be executed on a macOS machine with Xcode 15+ and XcodeGen installed (`brew install xcodegen`). The Beamlet server should be running and accessible.

---

## File Structure

```
ios/
├── project.yml                          # XcodeGen project definition
├── Beamlet/
│   ├── App/
│   │   ├── BeamletApp.swift             # App entry point, DI setup
│   │   └── RootView.swift               # Auth routing (setup vs main)
│   ├── Data/
│   │   ├── BeamletAPI.swift             # API client (all server communication)
│   │   └── AuthRepository.swift         # Keychain storage, auth state
│   ├── Model/
│   │   └── Models.swift                 # User, File, Device models
│   ├── Presentation/
│   │   ├── Setup/
│   │   │   └── SetupView.swift          # Server URL + token entry / QR scan
│   │   ├── Inbox/
│   │   │   ├── InboxView.swift          # List of received files
│   │   │   ├── InboxViewModel.swift     # Async loading, pagination, state
│   │   │   └── FileRowView.swift        # Single file row in inbox
│   │   ├── Detail/
│   │   │   └── FileDetailView.swift     # View/download a received file
│   │   ├── Send/
│   │   │   ├── SendView.swift           # Pick recipient + file, send
│   │   │   └── SendViewModel.swift      # Upload logic, user loading, state
│   │   ├── Settings/
│   │   │   └── SettingsView.swift       # Server info, logout
│   │   └── Components/
│   │       ├── MainTabView.swift        # Tab bar (Inbox, Send, Settings)
│   │       └── StateViews.swift         # Loading, Error, Empty states
│   └── Resources/
│       ├── Info.plist
│       ├── Beamlet.entitlements
│       └── Assets.xcassets/
│           └── AppIcon.appiconset/
│               └── Contents.json
├── BeamletShare/
│   ├── ShareViewController.swift        # Share extension entry point
│   ├── ShareView.swift                  # SwiftUI share UI (recipient picker)
│   ├── Info.plist
│   └── BeamletShare.entitlements
└── BeamletTests/
    └── BeamletTests.swift               # API + model tests
```

---

### Task 1: XcodeGen Project Configuration

**Files:**
- Create: `ios/project.yml`
- Create: `ios/Beamlet/Resources/Info.plist`
- Create: `ios/Beamlet/Resources/Beamlet.entitlements`
- Create: `ios/Beamlet/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `ios/BeamletShare/Info.plist`
- Create: `ios/BeamletShare/BeamletShare.entitlements`

- [ ] **Step 1: Create project.yml**

Create `ios/project.yml`:

```yaml
name: Beamlet
options:
  bundleIdPrefix: com.beamlet
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: S6WU9SVVDW

targets:
  Beamlet:
    type: application
    platform: iOS
    sources:
      - Beamlet
    resources:
      - Beamlet/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.beamlet.app
        INFOPLIST_FILE: Beamlet/Resources/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "Apple Development"
        DEVELOPMENT_TEAM: S6WU9SVVDW
        ENABLE_PREVIEWS: YES
      configs:
        Debug:
          CODE_SIGN_IDENTITY: "Apple Development"
          DEVELOPMENT_TEAM: S6WU9SVVDW
        Release:
          CODE_SIGN_IDENTITY: "Apple Development"
          DEVELOPMENT_TEAM: S6WU9SVVDW
    entitlements:
      path: Beamlet/Resources/Beamlet.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.beamlet.shared
        aps-environment: development
    dependencies:
      - target: BeamletShare
        embed: true

  BeamletShare:
    type: app-extension
    platform: iOS
    sources:
      - BeamletShare
      - path: Beamlet/Data
        group: Shared
      - path: Beamlet/Model
        group: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.beamlet.app.share
        INFOPLIST_FILE: BeamletShare/Info.plist
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "Apple Development"
        DEVELOPMENT_TEAM: S6WU9SVVDW
        SKIP_INSTALL: YES
      configs:
        Debug:
          CODE_SIGN_IDENTITY: "Apple Development"
          DEVELOPMENT_TEAM: S6WU9SVVDW
        Release:
          CODE_SIGN_IDENTITY: "Apple Development"
          DEVELOPMENT_TEAM: S6WU9SVVDW
    entitlements:
      path: BeamletShare/BeamletShare.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.beamlet.shared

  BeamletTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - BeamletTests
    settings:
      base:
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: S6WU9SVVDW
    dependencies:
      - target: Beamlet

schemes:
  Beamlet:
    build:
      targets:
        Beamlet: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - BeamletTests
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 2: Create main app Info.plist**

Create `ios/Beamlet/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Beamlet</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.beamlet.app.cleanup</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create entitlements files**

Create `ios/Beamlet/Resources/Beamlet.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.beamlet.shared</string>
    </array>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

Create `ios/BeamletShare/BeamletShare.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.beamlet.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Create asset catalog**

Create `ios/Beamlet/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Create share extension Info.plist**

Create `ios/BeamletShare/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Beamlet</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsFileWithMaxCount</key>
                <integer>10</integer>
                <key>NSExtensionActivationSupportsImageWithMaxCount</key>
                <integer>10</integer>
                <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
                <integer>5</integer>
                <key>NSExtensionActivationSupportsText</key>
                <true/>
                <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
                <integer>1</integer>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
```

- [ ] **Step 6: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add XcodeGen project configuration and resources"
```

---

### Task 2: Models and Auth Repository

**Files:**
- Create: `ios/Beamlet/Model/Models.swift`
- Create: `ios/Beamlet/Data/AuthRepository.swift`

- [ ] **Step 1: Create data models**

Create `ios/Beamlet/Model/Models.swift`:

```swift
import Foundation

struct BeamletUser: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct BeamletFile: Codable, Identifiable, Hashable {
    let id: String
    let senderID: String
    let recipientID: String
    let filename: String
    let fileType: String
    let fileSize: Int64
    let contentType: String
    let textContent: String?
    let message: String?
    let read: Bool
    let expiresAt: Date?
    let createdAt: Date?
    let senderName: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, message, read
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case fileType = "file_type"
        case fileSize = "file_size"
        case contentType = "content_type"
        case textContent = "text_content"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case senderName = "sender_name"
    }

    var isImage: Bool { fileType.hasPrefix("image/") }
    var isVideo: Bool { fileType.hasPrefix("video/") }
    var isText: Bool { contentType == "text" }
    var isLink: Bool { contentType == "link" }

    var displayType: String {
        if isImage { return "Photo" }
        if isVideo { return "Video" }
        if isText { return "Message" }
        if isLink { return "Link" }
        return "File"
    }
}
```

- [ ] **Step 2: Create auth repository with keychain**

Create `ios/Beamlet/Data/AuthRepository.swift`:

```swift
import Foundation
import Security

@Observable
class AuthRepository {
    private let keychain = KeychainService()
    private let suiteName = "group.com.beamlet.shared"

    private(set) var serverURL: URL?
    private(set) var token: String?
    private(set) var deviceToken: String?

    var isAuthenticated: Bool {
        token != nil && serverURL != nil
    }

    init() {
        loadStoredCredentials()
    }

    private func loadStoredCredentials() {
        let defaults = UserDefaults(suiteName: suiteName)
        if let urlString = defaults?.string(forKey: "serverURL"),
           let url = URL(string: urlString) {
            serverURL = url
        }
        token = keychain.get("authToken")
    }

    func store(serverURL: URL, token: String) {
        self.serverURL = serverURL
        self.token = token

        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(serverURL.absoluteString, forKey: "serverURL")
        keychain.set(token, forKey: "authToken")
    }

    func storeDeviceToken(_ token: String) {
        self.deviceToken = token
    }

    func clear() {
        serverURL = nil
        token = nil
        deviceToken = nil

        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removeObject(forKey: "serverURL")
        keychain.delete("authToken")
    }
}

// MARK: - Keychain Service
class KeychainService {
    private let service = "com.beamlet.app"

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add data models and auth repository with keychain"
```

---

### Task 3: API Client

**Files:**
- Create: `ios/Beamlet/Data/BeamletAPI.swift`

- [ ] **Step 1: Create API client**

Create `ios/Beamlet/Data/BeamletAPI.swift`:

```swift
import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .notAuthenticated: return "Not authenticated"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code, let message): return message ?? "HTTP error \(code)"
        case .decodingError(let error): return "Decode error: \(error.localizedDescription)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

@Observable
class BeamletAPI {
    private let authRepository: AuthRepository
    private let session: URLSession
    private let decoder: JSONDecoder

    init(authRepository: AuthRepository, session: URLSession = .shared) {
        self.authRepository = authRepository
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO 8601 with fractional seconds first, then without
            let formatters = [
                ISO8601DateFormatter(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
            ]
            for formatter in formatters {
                if let date = formatter.date(from: string) { return date }
            }
            // Try Go's default time format
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ"
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: string) { return date }
            df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSSSS Z"
            if let date = df.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
    }

    // MARK: - Base Request

    private func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }
        guard let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            if let json = String(data: data, encoding: .utf8) {
                print("Decode error for \(T.self): \(error)")
                print("Response: \(json.prefix(500))")
            }
            #endif
            throw APIError.decodingError(error)
        }
    }

    private func requestVoid(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws {
        guard let baseURL = authRepository.serverURL else {
            throw APIError.notAuthenticated
        }
        guard let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: baseURL.absoluteString + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await MainActor.run { authRepository.clear() }
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Session expired")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    // MARK: - Users

    func listUsers() async throws -> [BeamletUser] {
        try await request("/api/users")
    }

    // MARK: - Device Registration

    func registerDevice(apnsToken: String, platform: String = "ios") async throws {
        let body = try JSONEncoder().encode(["apns_token": apnsToken, "platform": platform])
        try await requestVoid("/api/auth/register-device", method: "POST", body: body)
    }

    // MARK: - Files

    func listFiles(limit: Int = 20, offset: Int = 0) async throws -> [BeamletFile] {
        try await request("/api/files", queryItems: [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
    }

    func markRead(_ fileID: String) async throws {
        try await requestVoid("/api/files/\(fileID)/read", method: "PUT")
    }

    func deleteFile(_ fileID: String) async throws {
        try await requestVoid("/api/files/\(fileID)", method: "DELETE")
    }

    func downloadFile(_ fileID: String) async throws -> Data {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("/api/files/\(fileID)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.invalidResponse
        }
        return data
    }

    func thumbnailURL(for fileID: String) -> URL? {
        guard let baseURL = authRepository.serverURL else { return nil }
        return baseURL.appendingPathComponent("/api/files/\(fileID)/thumbnail")
    }

    var authHeaders: [String: String] {
        guard let token = authRepository.token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: - Upload

    func uploadFile(
        recipientID: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        message: String? = nil
    ) async throws -> BeamletFile {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("/api/files")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        if let message = message, !message.isEmpty {
            body.appendMultipart(boundary: boundary, name: "message", value: message)
        }
        body.appendMultipartFile(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: fileData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }

    func uploadText(
        recipientID: String,
        text: String,
        contentType: String = "text"
    ) async throws -> BeamletFile {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("/api/files")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let deviceToken = authRepository.deviceToken {
            request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        }

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "recipient_id", value: recipientID)
        body.appendMultipart(boundary: boundary, name: "content_type", value: contentType)
        body.appendMultipart(boundary: boundary, name: "text_content", value: text)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: http.statusCode, message: msg)
        }

        return try decoder.decode(BeamletFile.self, from: data)
    }
}

// MARK: - Multipart Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add API client with upload, download, and multipart support"
```

---

### Task 4: App Entry Point and Root View

**Files:**
- Create: `ios/Beamlet/App/BeamletApp.swift`
- Create: `ios/Beamlet/App/RootView.swift`
- Create: `ios/Beamlet/Presentation/Components/MainTabView.swift`
- Create: `ios/Beamlet/Presentation/Components/StateViews.swift`

- [ ] **Step 1: Create app entry point**

Create `ios/Beamlet/App/BeamletApp.swift`:

```swift
import SwiftUI
import UserNotifications

@main
struct BeamletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository: AuthRepository
    @State private var api: BeamletAPI

    init() {
        let repo = AuthRepository()
        let apiInstance = BeamletAPI(authRepository: repo)
        _authRepository = State(initialValue: repo)
        _api = State(initialValue: apiInstance)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(api)
                .preferredColorScheme(.dark)
                .task {
                    if authRepository.isAuthenticated {
                        await requestNotificationPermission()
                    }
                }
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        if granted == true {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}

// MARK: - App Delegate (Push Notifications)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults(suiteName: "group.com.beamlet.shared")?.set(token, forKey: "apnsDeviceToken")
        NotificationCenter.default.post(name: .didReceiveAPNsToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for push: \(error)")
    }
}

extension Notification.Name {
    static let didReceiveAPNsToken = Notification.Name("didReceiveAPNsToken")
}
```

- [ ] **Step 2: Create root view**

Create `ios/Beamlet/App/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @Environment(AuthRepository.self) private var authRepository

    var body: some View {
        Group {
            if authRepository.isAuthenticated {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .animation(.easeInOut, value: authRepository.isAuthenticated)
    }
}
```

- [ ] **Step 3: Create main tab view**

Create `ios/Beamlet/Presentation/Components/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }

            SendView()
                .tabItem {
                    Label("Send", systemImage: "paperplane.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
```

- [ ] **Step 4: Create shared state views**

Create `ios/Beamlet/Presentation/Components/StateViews.swift`:

```swift
import SwiftUI

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add app entry point, root view, tab navigation, and state views"
```

---

### Task 5: Setup View

**Files:**
- Create: `ios/Beamlet/Presentation/Setup/SetupView.swift`

- [ ] **Step 1: Create setup view**

Create `ios/Beamlet/Presentation/Setup/SetupView.swift`:

```swift
import SwiftUI

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        Text("Beamlet")
                            .font(.largeTitle.bold())

                        Text("Enter your server details to get started")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.headline)
                            TextField("https://beamlet.example.com", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Token")
                                .font(.headline)
                            SecureField("Paste your token here", text: $token)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal)

                    if let error = error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.horizontal)
                    }

                    // Connect button
                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func connect() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        Task {
            // Temporarily store credentials to test the connection
            authRepository.store(serverURL: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))

            do {
                // Verify by fetching user list
                let _ = try await api.listUsers()

                // Register for push notifications
                let center = UNUserNotificationCenter.current()
                let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted == true {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }

                // Register device token if we already have one
                if let deviceToken = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "apnsDeviceToken") {
                    authRepository.storeDeviceToken(deviceToken)
                    try? await api.registerDevice(apnsToken: deviceToken)
                }
            } catch {
                // Connection failed — clear credentials
                authRepository.clear()
                self.error = error.localizedDescription
            }

            isConnecting = false
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add setup view for server connection"
```

---

### Task 6: Inbox ViewModel, Views, and File Detail

**Files:**
- Create: `ios/Beamlet/Presentation/Inbox/InboxViewModel.swift`
- Create: `ios/Beamlet/Presentation/Inbox/InboxView.swift`
- Create: `ios/Beamlet/Presentation/Inbox/FileRowView.swift`
- Create: `ios/Beamlet/Presentation/Detail/FileDetailView.swift`

- [ ] **Step 1: Create file row view**

Create `ios/Beamlet/Presentation/Inbox/FileRowView.swift`:

```swift
import SwiftUI

struct FileRowView: View {
    let file: BeamletFile
    let thumbnailURL: URL?
    let authHeaders: [String: String]

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            Group {
                if file.isImage, let url = thumbnailURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                } else {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.senderName ?? "Unknown")
                        .font(.headline)
                    if !file.read {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                if file.isText, let text = file.textContent {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let message = file.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(file.displayType)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let date = file.createdAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if file.isImage { return "photo" }
        if file.isVideo { return "video" }
        if file.isText { return "text.bubble" }
        if file.isLink { return "link" }
        return "doc"
    }
}
```

- [ ] **Step 2: Create inbox view model**

Create `ios/Beamlet/Presentation/Inbox/InboxViewModel.swift`:

```swift
import Foundation

@Observable
@MainActor
class InboxViewModel {
    private let api: BeamletAPI

    var files: [BeamletFile] = []
    var isLoading = true
    var error: String?

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadFiles() async {
        do {
            files = try await api.listFiles()
            isLoading = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func deleteFiles(at offsets: IndexSet) {
        let toDelete = offsets.map { files[$0] }
        files.remove(atOffsets: offsets)
        Task {
            for file in toDelete {
                try? await api.deleteFile(file.id)
            }
        }
    }

    func thumbnailURL(for fileID: String) -> URL? {
        api.thumbnailURL(for: fileID)
    }

    var authHeaders: [String: String] {
        api.authHeaders
    }
}
```

- [ ] **Step 3: Create inbox view**

Create `ios/Beamlet/Presentation/Inbox/InboxView.swift`:

```swift
import SwiftUI

struct InboxView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: InboxViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isLoading && vm.files.isEmpty {
                        LoadingView(message: "Loading inbox...")
                    } else if let error = vm.error, vm.files.isEmpty {
                        ErrorView(message: error) { Task { await vm.loadFiles() } }
                    } else if vm.files.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "No Files",
                            message: "Files sent to you will appear here"
                        )
                    } else {
                        List {
                            ForEach(vm.files) { file in
                                NavigationLink(value: file) {
                                    FileRowView(
                                        file: file,
                                        thumbnailURL: vm.thumbnailURL(for: file.id),
                                        authHeaders: vm.authHeaders
                                    )
                                }
                            }
                            .onDelete(perform: vm.deleteFiles)
                        }
                        .listStyle(.plain)
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Inbox")
            .navigationDestination(for: BeamletFile.self) { file in
                FileDetailView(file: file)
            }
            .refreshable {
                await viewModel?.loadFiles()
            }
            .task {
                if viewModel == nil {
                    viewModel = InboxViewModel(api: api)
                }
                await viewModel?.loadFiles()
            }
        }
    }
}
```

- [ ] **Step 4: Create file detail view**

Create `ios/Beamlet/Presentation/Detail/FileDetailView.swift`:

```swift
import SwiftUI
import QuickLook

struct FileDetailView: View {
    @Environment(BeamletAPI.self) private var api
    let file: BeamletFile

    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var error: String?
    @State private var savedToPhotos = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("From \(file.senderName ?? "Unknown")")
                        .font(.headline)
                    if let date = file.createdAt {
                        Text(date, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let message = file.message, !message.isEmpty {
                        Text(message)
                            .font(.body)
                            .padding(.top, 4)
                    }
                }
                .padding()

                // Content
                if file.isText, let text = file.textContent {
                    Text(text)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = text
                            }
                        }
                } else if file.isLink, let text = file.textContent, let url = URL(string: text) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "link")
                            Text(text)
                                .lineLimit(2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                } else if file.isImage {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .contextMenu {
                                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                                    savedToPhotos = true
                                }
                                ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(file.filename, image: Image(uiImage: uiImage)))
                            }
                    } else if isLoading {
                        ProgressView("Downloading...")
                            .frame(height: 200)
                    }
                } else {
                    // Generic file
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text(file.filename)
                            .font(.headline)
                        Text(formattedSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                }

                if savedToPhotos {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(file.displayType)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Mark as read
            try? await api.markRead(file.id)

            // Download content for images
            if file.isImage {
                isLoading = true
                do {
                    imageData = try await api.downloadFile(file.id)
                } catch {
                    self.error = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: file.fileSize)
    }
}
```

- [ ] **Step 5: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add inbox view model, inbox, file row, and file detail views"
```

---

### Task 7: Send ViewModel, Send View, and Settings View

**Files:**
- Create: `ios/Beamlet/Presentation/Send/SendViewModel.swift`
- Create: `ios/Beamlet/Presentation/Send/SendView.swift`
- Create: `ios/Beamlet/Presentation/Settings/SettingsView.swift`

- [ ] **Step 1: Create send view model**

Create `ios/Beamlet/Presentation/Send/SendViewModel.swift`:

```swift
import Foundation
import PhotosUI
import SwiftUI

@Observable
@MainActor
class SendViewModel {
    private let api: BeamletAPI

    var users: [BeamletUser] = []
    var selectedUser: BeamletUser?
    var message = ""
    var selectedPhoto: PhotosPickerItem?
    var selectedPhotoData: Data?
    var isSending = false
    var error: String?
    var showSuccess = false

    var canSend: Bool {
        selectedUser != nil && (selectedPhotoData != nil || !message.isEmpty) && !isSending
    }

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadUsers() async {
        users = (try? await api.listUsers()) ?? []
    }

    func loadPhotoData() async {
        guard let item = selectedPhoto else { return }
        selectedPhotoData = try? await item.loadTransferable(type: Data.self)
    }

    func send() async {
        guard let user = selectedUser else { return }
        isSending = true
        error = nil

        do {
            if let photoData = selectedPhotoData {
                let _ = try await api.uploadFile(
                    recipientID: user.id,
                    fileData: photoData,
                    filename: "photo.jpg",
                    mimeType: "image/jpeg",
                    message: message.isEmpty ? nil : message
                )
            } else if !message.isEmpty {
                let _ = try await api.uploadText(
                    recipientID: user.id,
                    text: message
                )
            }
            showSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    func reset() {
        selectedUser = nil
        selectedPhoto = nil
        selectedPhotoData = nil
        message = ""
    }
}
```

- [ ] **Step 2: Create send view**

Create `ios/Beamlet/Presentation/Send/SendView.swift`:

```swift
import SwiftUI
import PhotosUI

struct SendView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: SendViewModel?

    var body: some View {
        NavigationStack {
            if let vm = viewModel {
                Form {
                    Section("Recipient") {
                        if vm.users.isEmpty {
                            ProgressView("Loading users...")
                        } else {
                            Picker("Send to", selection: Bindable(vm).selectedUser) {
                                Text("Select recipient").tag(nil as BeamletUser?)
                                ForEach(vm.users) { user in
                                    Text(user.name).tag(user as BeamletUser?)
                                }
                            }
                        }
                    }

                    Section("Content") {
                        PhotosPicker(selection: Bindable(vm).selectedPhoto, matching: .any(of: [.images, .videos])) {
                            HStack {
                                Image(systemName: vm.selectedPhotoData != nil ? "checkmark.circle.fill" : "photo")
                                    .foregroundStyle(vm.selectedPhotoData != nil ? .green : .secondary)
                                Text(vm.selectedPhotoData != nil ? "Photo selected" : "Choose photo or video")
                            }
                        }
                        .onChange(of: vm.selectedPhoto) {
                            Task { await vm.loadPhotoData() }
                        }

                        TextField("Message (optional)", text: Bindable(vm).message, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if let error = vm.error {
                        Section {
                            Text(error).foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await vm.send() }
                        } label: {
                            if vm.isSending {
                                HStack { ProgressView(); Text("Sending...") }
                            } else {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                        }
                        .disabled(!vm.canSend)
                    }
                }
                .navigationTitle("Send")
                .alert("Sent!", isPresented: Bindable(vm).showSuccess) {
                    Button("OK") { vm.reset() }
                } message: {
                    Text("File sent successfully")
                }
                .task { await vm.loadUsers() }
            } else {
                LoadingView()
                    .task { viewModel = SendViewModel(api: api) }
            }
        }
    }
}
```

- [ ] **Step 3: Create settings view**

Create `ios/Beamlet/Presentation/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    if let url = authRepository.serverURL {
                        LabeledContent("URL", value: url.absoluteString)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                        }
                    }
                }

                Section("Notifications") {
                    LabeledContent("Push") {
                        if authRepository.deviceToken != nil {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Enabled")
                            }
                        } else {
                            Text("Not registered")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Disconnect?", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    authRepository.clear()
                }
            } message: {
                Text("You'll need to re-enter your server details to reconnect.")
            }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add send view model, send view, and settings view"
```

---

### Task 8: Share Extension

**Files:**
- Create: `ios/BeamletShare/ShareViewController.swift`
- Create: `ios/BeamletShare/ShareView.swift`

- [ ] **Step 1: Create share view controller**

Create `ios/BeamletShare/ShareViewController.swift`:

```swift
import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let authRepository = AuthRepository()

        guard authRepository.isAuthenticated else {
            showError("Please open Beamlet and connect to your server first.")
            return
        }

        let api = BeamletAPI(authRepository: authRepository)
        let shareView = ShareView(
            api: api,
            extensionContext: extensionContext
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Beamlet", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}
```

- [ ] **Step 2: Create share SwiftUI view**

Create `ios/BeamletShare/ShareView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let api: BeamletAPI
    let extensionContext: NSExtensionContext?

    @State private var users: [BeamletUser] = []
    @State private var selectedUser: BeamletUser?
    @State private var message = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var sharedItems: [SharedItem] = []

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section("Send to") {
                            Picker("Recipient", selection: $selectedUser) {
                                Text("Select").tag(nil as BeamletUser?)
                                ForEach(users) { user in
                                    Text(user.name).tag(user as BeamletUser?)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if !sharedItems.isEmpty {
                            Section("Sharing") {
                                ForEach(sharedItems) { item in
                                    Label(item.description, systemImage: item.icon)
                                }
                            }
                        }

                        Section {
                            TextField("Message (optional)", text: $message)
                        }

                        if let error = error {
                            Section {
                                Text(error).foregroundStyle(.red).font(.callout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Beamlet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        extensionContext?.completeRequest(returningItems: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(selectedUser == nil || isSending)
                        .bold()
                }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        // Load users
        users = (try? await api.listUsers()) ?? []

        // Extract shared items from extension context
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            isLoading = false
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let shared = await extractItem(from: provider) {
                    sharedItems.append(shared)
                }
            }
        }

        isLoading = false
    }

    private func extractItem(from provider: NSItemProvider) async -> SharedItem? {
        // Try URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return SharedItem(type: .link, text: url.absoluteString)
            }
        }

        // Try text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return SharedItem(type: .text, text: text)
            }
        }

        // Try image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .image, data: data, filename: url.lastPathComponent)
            }
        }

        // Try video
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .video, data: data, filename: url.lastPathComponent)
            }
        }

        // Try any file
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .file, data: data, filename: url.lastPathComponent)
            }
        }

        return nil
    }

    private func send() {
        guard let user = selectedUser else { return }
        isSending = true
        error = nil

        Task {
            do {
                for item in sharedItems {
                    switch item.type {
                    case .text:
                        let _ = try await api.uploadText(recipientID: user.id, text: item.text ?? "")
                    case .link:
                        let _ = try await api.uploadText(recipientID: user.id, text: item.text ?? "", contentType: "link")
                    case .image:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "image.jpg",
                                mimeType: "image/jpeg",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    case .video:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "video.mp4",
                                mimeType: "video/mp4",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    case .file:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "file",
                                mimeType: "application/octet-stream",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    }
                }

                // If only a text message (no shared items)
                if sharedItems.isEmpty && !message.isEmpty {
                    let _ = try await api.uploadText(recipientID: user.id, text: message)
                }

                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                self.error = error.localizedDescription
                isSending = false
            }
        }
    }
}

// MARK: - Shared Item Model

struct SharedItem: Identifiable {
    let id = UUID()
    let type: SharedItemType
    var text: String?
    var data: Data?
    var filename: String?

    var description: String {
        switch type {
        case .text: return text?.prefix(50).description ?? "Text"
        case .link: return text ?? "Link"
        case .image: return filename ?? "Photo"
        case .video: return filename ?? "Video"
        case .file: return filename ?? "File"
        }
    }

    var icon: String {
        switch type {
        case .text: return "text.bubble"
        case .link: return "link"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        }
    }
}

enum SharedItemType {
    case text, link, image, video, file
}
```

- [ ] **Step 3: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add share extension with multi-type support"
```

---

### Task 9: Push Notification Handling

**Files:**
- Modify: `ios/Beamlet/App/BeamletApp.swift` (add notification observer for device token registration)

- [ ] **Step 1: Update BeamletApp to handle push token registration**

Add notification observer to `BeamletApp.swift`. Replace the existing `body` computed property:

```swift
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(api)
                .preferredColorScheme(.dark)
                .task {
                    if authRepository.isAuthenticated {
                        await requestNotificationPermission()
                        await registerExistingDeviceToken()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveAPNsToken)) { notification in
                    guard let token = notification.object as? String else { return }
                    authRepository.storeDeviceToken(token)
                    Task {
                        try? await api.registerDevice(apnsToken: token)
                    }
                }
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        if granted == true {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func registerExistingDeviceToken() async {
        if let token = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "apnsDeviceToken") {
            authRepository.storeDeviceToken(token)
            try? await api.registerDevice(apnsToken: token)
        }
    }
```

- [ ] **Step 2: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add push notification device token registration"
```

---

### Task 10: Unit Tests and Build Verification

**Files:**
- Create: `ios/BeamletTests/BeamletTests.swift`

- [ ] **Step 1: Create unit tests**

Create `ios/BeamletTests/BeamletTests.swift`:

```swift
import XCTest
@testable import Beamlet

final class BeamletTests: XCTestCase {

    // MARK: - Model Decoding

    func testBeamletFileDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "sender_id": "user-1",
            "recipient_id": "user-2",
            "filename": "photo.jpg",
            "file_type": "image/jpeg",
            "file_size": 12345,
            "content_type": "file",
            "read": false,
            "sender_name": "Alice"
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(BeamletFile.self, from: json)
        XCTAssertEqual(file.id, "abc-123")
        XCTAssertEqual(file.filename, "photo.jpg")
        XCTAssertTrue(file.isImage)
        XCTAssertFalse(file.isVideo)
        XCTAssertEqual(file.displayType, "Photo")
        XCTAssertEqual(file.senderName, "Alice")
    }

    func testBeamletFileTextType() throws {
        let json = """
        {
            "id": "def-456",
            "sender_id": "user-1",
            "recipient_id": "user-2",
            "filename": "text",
            "file_type": "text/plain",
            "file_size": 0,
            "content_type": "text",
            "text_content": "Hello!",
            "read": true
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(BeamletFile.self, from: json)
        XCTAssertTrue(file.isText)
        XCTAssertEqual(file.textContent, "Hello!")
        XCTAssertEqual(file.displayType, "Message")
    }

    func testBeamletUserDecoding() throws {
        let json = """
        {
            "id": "user-1",
            "name": "Alice"
        }
        """.data(using: .utf8)!

        let user = try JSONDecoder().decode(BeamletUser.self, from: json)
        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(user.name, "Alice")
    }

    // MARK: - Auth Repository

    func testAuthRepositoryInitialState() {
        let repo = AuthRepository()
        // Fresh repo with no stored credentials should not be authenticated
        // (may be authenticated if run on device with existing credentials)
        XCTAssertNotNil(repo)
    }

    // MARK: - Multipart Encoding

    func testMultipartEncoding() {
        var data = Data()
        let boundary = "test-boundary"
        data.appendMultipart(boundary: boundary, name: "field", value: "value")
        let string = String(data: data, encoding: .utf8)!
        XCTAssertTrue(string.contains("--test-boundary"))
        XCTAssertTrue(string.contains("name=\"field\""))
        XCTAssertTrue(string.contains("value"))
    }

    func testMultipartFileEncoding() {
        var data = Data()
        let boundary = "test-boundary"
        let fileData = "hello".data(using: .utf8)!
        data.appendMultipartFile(boundary: boundary, name: "file", filename: "test.txt", mimeType: "text/plain", data: fileData)
        let string = String(data: data, encoding: .utf8)!
        XCTAssertTrue(string.contains("filename=\"test.txt\""))
        XCTAssertTrue(string.contains("Content-Type: text/plain"))
        XCTAssertTrue(string.contains("hello"))
    }
}
```

- [ ] **Step 2: Generate Xcode project and build**

```bash
cd ios
xcodegen generate
xcodebuild -scheme Beamlet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run tests**

```bash
cd ios
xcodebuild -scheme Beamlet -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -10
```

Expected: Tests pass

- [ ] **Step 4: Commit and push**

```bash
cd ios
git add .
git commit -m "feat(ios): add unit tests and verify build"
git push
```

---

## Post-Implementation Notes

**To deploy to a device:**
1. Open `Beamlet.xcodeproj` in Xcode (generated by `xcodegen`)
2. Select your team in Signing & Capabilities for both targets
3. Create App Group `group.com.beamlet.shared` in the Apple Developer portal
4. Create App IDs for `com.beamlet.app` and `com.beamlet.app.share`
5. Enable Push Notifications capability for the main app
6. Build and run on your device

**To configure push notifications:**
1. Create an APNs key in Apple Developer portal
2. Download the `.p8` file
3. Place it in the server's docker volume
4. Update `docker-compose.yml` with your Key ID, Team ID, and Bundle ID
