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

    @AppStorage("appTheme") private var appTheme: String = "system"

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(api)
                .environment(nearbyService)
                .preferredColorScheme(colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Clear badge when app becomes active
                    UNUserNotificationCenter.current().setBadgeCount(0)
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                }
                .task {
                    if authRepository.isAuthenticated {
                        await requestNotificationPermission()
                        await registerExistingDeviceToken()
                        await startNearbyService()
                    }
                }
                .onChange(of: authRepository.isAuthenticated) { _, isAuth in
                    if isAuth {
                        Task {
                            await requestNotificationPermission()
                            await registerExistingDeviceToken()
                            await startNearbyService()
                        }
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
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

    private func handleIncomingURL(_ url: URL) {
        // Handle beamlet://invite?payload={"url":"...","invite":"..."}
        guard url.scheme == "beamlet",
              url.host == "invite",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payloadString = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = payloadString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            return
        }

        if authRepository.isAuthenticated {
            // Already set up — redeem as existing user (add contact)
            Task {
                let response = try? await api.redeemInviteAsExistingUser(inviteToken: payload.invite)
                if response?.contact != nil {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }
        // If not authenticated, the user needs to set up first
        // Store the invite for the setup flow to pick up
        UserDefaults.standard.set(payload.url, forKey: "pendingInviteURL")
        UserDefaults.standard.set(payload.invite, forKey: "pendingInviteToken")
    }
}

// MARK: - App Delegate (Push Notifications)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults(suiteName: "group.com.beamlet.shared")?.set(token, forKey: "apnsDeviceToken")
        NotificationCenter.default.post(name: .didReceiveAPNsToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for push: \(error)")
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

extension Notification.Name {
    static let didReceiveAPNsToken = Notification.Name("didReceiveAPNsToken")
}
