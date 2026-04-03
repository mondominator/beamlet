import AppKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private let authRepository = AuthRepository()
    private lazy var api = BeamletAPI(authRepository: authRepository)
    private var nearbyService: NearbyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = self

        // Feature 3: Define notification category with Save and Open actions
        let saveAction = UNNotificationAction(identifier: "SAVE", title: "Save", options: [])
        let openAction = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: "FILE_RECEIVED",
            actions: [saveAction, openAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Start nearby service if authenticated
        startNearbyServiceIfNeeded()

        // Create the status bar controller with shared dependencies
        statusBarController = StatusBarController(
            authRepository: authRepository,
            api: api,
            nearbyService: nearbyService
        )

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

        // Watch for authentication changes to start/stop nearby service and background polling
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.startNearbyServiceIfNeeded()
            self?.startBackgroundPollingIfNeeded()
        }
    }

    // MARK: - Background Polling

    private var backgroundPoller: Timer?
    private var knownFileIDs: Set<String> = []
    private var previousUnreadCount = 0

    private func startBackgroundPollingIfNeeded() {
        guard authRepository.isAuthenticated, backgroundPoller == nil else { return }

        // Poll every 10 seconds for new files
        backgroundPoller = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForNewFiles()
            }
        }
        // Initial poll
        Task { @MainActor in pollForNewFiles() }
    }

    @MainActor
    private func pollForNewFiles() {
        guard authRepository.isAuthenticated else { return }

        Task {
            guard let files = try? await api.listFiles() else { return }

            let unreadCount = files.filter { !$0.read }.count

            // Sound on new files
            if unreadCount > previousUnreadCount && previousUnreadCount > 0 {
                NSSound(named: "Tink")?.play()
            }
            previousUnreadCount = unreadCount

            // Badge update
            NotificationCenter.default.post(
                name: .beamletUnreadCountChanged,
                object: nil,
                userInfo: ["count": unreadCount]
            )

            // Auto-save new files
            let savedIDs = Set(UserDefaults.standard.stringArray(forKey: "autoSavedFileIDs") ?? [])
            let downloadDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/Beamlet")

            for file in files where !file.read && !savedIDs.contains(file.id) && !file.isText && !file.isLink {
                try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
                if let data = try? await api.downloadFile(file.id) {
                    let dest = downloadDir.appendingPathComponent(file.filename)
                    try? data.write(to: dest)

                    var ids = UserDefaults.standard.stringArray(forKey: "autoSavedFileIDs") ?? []
                    ids.append(file.id)
                    UserDefaults.standard.set(ids, forKey: "autoSavedFileIDs")

                    // Auto-open if enabled
                    if UserDefaults.standard.bool(forKey: "autoOpenFiles") {
                        NSWorkspace.shared.open(dest)
                    }

                    // Post local notification
                    let content = UNMutableNotificationContent()
                    content.title = file.senderName ?? "Someone"
                    content.body = "Sent you \(file.displayType.lowercased())"
                    content.sound = .default
                    content.categoryIdentifier = "FILE_RECEIVED"
                    content.userInfo = ["fileID": file.id, "filename": file.filename]

                    let request = UNNotificationRequest(
                        identifier: file.id,
                        content: content,
                        trigger: nil
                    )
                    try? await UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    // MARK: - Nearby Service

    private func startNearbyServiceIfNeeded() {
        guard authRepository.isAuthenticated,
              let userID = authRepository.userID,
              nearbyService == nil else { return }

        let service = NearbyService(userID: userID, api: api)
        nearbyService = service
        service.start()

        // Load contacts for hash-based discovery, and sync discoverability from server
        Task {
            if let contacts = try? await api.listUsers() {
                await MainActor.run {
                    service.updateContacts(contacts)
                }
            }
            if let me = try? await api.getMe(),
               let serverMode = me.discoverability,
               let mode = DiscoverabilityMode(rawValue: serverMode) {
                await MainActor.run {
                    mode.save()
                    service.mode = mode
                }
            }
        }

        // Update the status bar controller with the new nearby service
        statusBarController?.updateNearbyService(service)
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

    func applicationWillTerminate(_ notification: Notification) {
        nearbyService?.stop()
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
        let userInfo = response.notification.request.content.userInfo
        let fileID = userInfo["fileID"] as? String
        let filename = userInfo["filename"] as? String ?? "file"

        switch response.actionIdentifier {
        case "SAVE":
            // Feature 3: Download and save to ~/Downloads/Beamlet/
            if let fileID = fileID {
                Task {
                    let downloadDir = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Downloads/Beamlet")
                    try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
                    if let data = try? await api.downloadFile(fileID) {
                        let dest = downloadDir.appendingPathComponent(filename)
                        try? data.write(to: dest)
                    }
                }
            }
        case "OPEN":
            // Feature 3: Download and open with default app
            if let fileID = fileID {
                Task {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    if let data = try? await api.downloadFile(fileID) {
                        try? data.write(to: tempURL)
                        await MainActor.run {
                            NSWorkspace.shared.open(tempURL)
                        }
                    }
                }
            }
        default:
            // Default tap -- show the popover
            statusBarController?.showPopover()
        }

        completionHandler()
    }
}
