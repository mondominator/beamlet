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
