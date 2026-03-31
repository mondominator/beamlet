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
