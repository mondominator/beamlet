import SwiftUI
import UserNotifications

@main
struct BeamletApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository: AuthRepository
    @State private var api: BeamletAPI
    @State private var nearbyService: NearbyService?
    @State private var receiveRouter: IncomingFileRouter

    init() {
        let repo = AuthRepository()
        let apiInstance = BeamletAPI(authRepository: repo)
        _authRepository = State(initialValue: repo)
        _api = State(initialValue: apiInstance)
        _receiveRouter = State(initialValue: IncomingFileRouter(api: apiInstance))
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
                .environment(receiveRouter)
                .preferredColorScheme(colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .didTapNotification)) { notification in
                    // APNs payload key — see server/internal/push/apns.go.
                    // The router downloads the file and routes it to the
                    // share sheet / clipboard / browser without any inbox UI.
                    guard let fileID = notification.object as? String else { return }
                    receiveRouter.receive(fileID: fileID)
                }
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
                        await syncDiscoverabilityFromServer()
                    }
                }
                .onChange(of: authRepository.isAuthenticated) { _, isAuth in
                    if isAuth {
                        Task {
                            await requestNotificationPermission()
                            await registerExistingDeviceToken()
                            await startNearbyService()
                            await syncDiscoverabilityFromServer()
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

    private func syncDiscoverabilityFromServer() async {
        if let me = try? await api.getMe(),
           let serverMode = me.discoverability,
           let mode = DiscoverabilityMode(rawValue: serverMode) {
            mode.save()
            nearbyService?.mode = mode
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
        var serverURL: String?
        var inviteToken: String?

        if url.scheme == "beamlet" {
            // beamlet://invite?payload={"u":"...","i":"..."}
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let payloadString = components.queryItems?.first(where: { $0.name == "payload" })?.value,
               let data = payloadString.data(using: .utf8),
               let payload = try? JSONDecoder().decode(QRPayload.self, from: data) {
                serverURL = payload.url
                inviteToken = payload.invite
            }
        } else if url.scheme == "https" || url.scheme == "http" {
            // Universal Link: https://beam.bitstorm.ca/invite/TOKEN
            let path = url.path  // "/invite/TOKEN"
            if path.hasPrefix("/invite/") {
                inviteToken = String(path.dropFirst("/invite/".count))
                // Server URL is the base of this URL
                guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
                components.path = ""
                components.query = nil
                serverURL = components.url?.absoluteString
            }
        }

        guard let serverURL, let inviteToken, !inviteToken.isEmpty else { return }

        if authRepository.isAuthenticated {
            Task {
                let response = try? await api.redeemInviteAsExistingUser(inviteToken: inviteToken)
                if response?.contact != nil {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        } else {
            // Store for setup flow
            UserDefaults.standard.set(serverURL, forKey: "pendingInviteURL")
            UserDefaults.standard.set(inviteToken, forKey: "pendingInviteToken")
        }
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
        #if DEBUG
        print("Failed to register for push: \(error)")
        #endif
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let fileID = userInfo["file_id"] as? String {
            NotificationCenter.default.post(name: .didTapNotification, object: fileID)
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let didReceiveAPNsToken = Notification.Name("didReceiveAPNsToken")
    static let didTapNotification = Notification.Name("didTapNotification")
}
