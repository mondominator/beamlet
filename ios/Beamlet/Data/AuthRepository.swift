import Foundation
import Security

@Observable
class AuthRepository {
    private let keychain = KeychainService()
    private let suiteName = "group.com.beamlet.shared"

    private(set) var serverURL: URL?
    private(set) var token: String?
    private(set) var deviceToken: String?
    private(set) var userID: String?

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

        // Try Keychain first, fall back to UserDefaults for migration
        if let keychainToken = keychain.get("authToken") {
            token = keychainToken
        } else if let defaultsToken = defaults?.string(forKey: "authToken") {
            // Migrate token from UserDefaults to Keychain
            token = defaultsToken
            keychain.set(defaultsToken, forKey: "authToken")
            defaults?.removeObject(forKey: "authToken")
        }

        userID = defaults?.string(forKey: "userID")
    }

    func store(serverURL: URL, token: String) {
        self.serverURL = serverURL
        self.token = token

        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(serverURL.absoluteString, forKey: "serverURL")

        // Store token in Keychain and remove from UserDefaults
        keychain.set(token, forKey: "authToken")
        defaults?.removeObject(forKey: "authToken")
    }

    func storeDeviceToken(_ token: String) {
        self.deviceToken = token
    }

    func storeUserID(_ id: String) {
        self.userID = id
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(id, forKey: "userID")
    }

    func clear() {
        serverURL = nil
        token = nil
        deviceToken = nil
        userID = nil

        // Clear Keychain
        keychain.delete("authToken")

        // Clear UserDefaults
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removeObject(forKey: "serverURL")
        defaults?.removeObject(forKey: "authToken")
        defaults?.removeObject(forKey: "userID")
    }
}

// MARK: - Keychain Service
class KeychainService {
    private let service = "com.beamlet.app"
    private let accessGroup = "group.com.beamlet.shared"

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
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
            kSecAttrAccessGroup as String: accessGroup,
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
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
    }
}
