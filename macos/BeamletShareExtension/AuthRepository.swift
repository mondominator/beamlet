import Foundation
import Security

/// Lightweight auth reader for the share extension.
/// Reads credentials stored by the main Beamlet app via the shared app group.
class AuthRepository {
    private let keychain = KeychainService()
    private let suiteName = "group.com.beamlet.shared"

    private(set) var serverURL: URL?
    private(set) var token: String?
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
            token = defaultsToken
        }

        userID = defaults?.string(forKey: "userID")
    }
}

// MARK: - Keychain Service

class KeychainService {
    private let service = "com.beamlet.mac"
    private let accessGroup = "group.com.beamlet.shared"

    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
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
}
