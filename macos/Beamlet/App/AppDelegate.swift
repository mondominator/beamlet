import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private let authRepository = AuthRepository()
    private lazy var api = BeamletAPI(authRepository: authRepository)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Create the status bar controller with shared dependencies
        statusBarController = StatusBarController(authRepository: authRepository, api: api)

        // Request notification permissions and register for remote notifications
        requestNotificationPermissions()

        // Periodically check if we need to register the device token
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.authRepository.isAuthenticated, let token = self.authRepository.deviceToken {
                self.registerTokenWithServer(token)
                timer.invalidate()
            }
        }
    }

    // MARK: - Push Notifications

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
                return
            }
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        authRepository.storeDeviceToken(tokenString)
        registerTokenWithServer(tokenString)
    }

    private func registerTokenWithServer(_ tokenString: String) {
        guard authRepository.isAuthenticated else { return }
        Task {
            try? await api.registerDevice(apnsToken: tokenString, platform: "macos")
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // User tapped the notification -- show the popover
        statusBarController?.showPopover()
        completionHandler()
    }
}
