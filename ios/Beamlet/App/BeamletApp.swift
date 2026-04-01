import SwiftUI
import UserNotifications

@main
struct BeamletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository: AuthRepository
    @State private var api: BeamletAPI
    @State private var nearbyService: NearbyService?

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
                .environment(nearbyService)
                .preferredColorScheme(.dark)
                .task {
                    if authRepository.isAuthenticated {
                        await requestNotificationPermission()
                        await registerExistingDeviceToken()
                        await startNearbyService()
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

    private func startNearbyService() async {
        // Fetch userID if not stored yet
        if authRepository.userID == nil {
            if let me = try? await api.getMe() {
                authRepository.storeUserID(me.id)
            }
        }

        guard let userID = authRepository.userID else { return }
        if nearbyService == nil {
            let service = NearbyService(userID: userID, api: api)
            nearbyService = service
        }

        // Load contacts so BLE can match hashes
        if let contacts = try? await api.listUsers() {
            nearbyService?.updateContacts(contacts)
        }

        nearbyService?.start()
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
