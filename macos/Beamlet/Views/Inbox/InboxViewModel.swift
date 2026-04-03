import Foundation
import AppKit

@Observable
@MainActor
class InboxViewModel {
    private let api: BeamletAPI

    var files: [BeamletFile] = []
    var isLoading = true
    var error: String?

    private var refreshTimer: Timer?
    private var previousUnreadCount: Int = 0

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadFiles() async {
        do {
            var newFiles = try await api.listFiles()

            // Auto-delete received files older than user's inbox cleanup preference
            let cleanupDays = UserDefaults.standard.integer(forKey: "inboxCleanupDays")
            if cleanupDays > 0 {
                let cutoff = Date().addingTimeInterval(-Double(cleanupDays) * 86400)
                var expiredIDs: [String] = []
                for file in newFiles {
                    if file.pinned == true { continue }
                    if let created = file.createdAt, created < cutoff {
                        expiredIDs.append(file.id)
                    }
                }
                if !expiredIDs.isEmpty {
                    let api = self.api
                    Task.detached {
                        for id in expiredIDs {
                            try? await api.deleteFile(id)
                        }
                    }
                    newFiles = newFiles.filter { !expiredIDs.contains($0.id) }
                }
            }

            // Feature 4: Play sound when new unread files arrive
            let newUnreadCount = newFiles.filter { !$0.read }.count
            if newUnreadCount > previousUnreadCount && previousUnreadCount >= 0 && !isLoading {
                NSSound(named: "Tink")?.play()
            }
            previousUnreadCount = newUnreadCount

            files = newFiles
            isLoading = false
            error = nil

            // Feature 1: Auto-save new files to ~/Downloads/Beamlet/
            autoSaveNewFiles(newFiles)

            // Feature 7: Notify StatusBarController of unread count
            NotificationCenter.default.post(
                name: .beamletUnreadCountChanged,
                object: nil,
                userInfo: ["count": newUnreadCount]
            )
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Auto-save received files to ~/Downloads/Beamlet/

    private func autoSaveNewFiles(_ files: [BeamletFile]) {
        let savedIDs = Set(UserDefaults.standard.stringArray(forKey: "autoSavedFileIDs") ?? [])
        let downloadDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Beamlet")
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let autoOpen = UserDefaults.standard.bool(forKey: "autoOpenFiles")

        for file in files where !file.read && !savedIDs.contains(file.id) && !file.isText && !file.isLink {
            Task {
                if let data = try? await api.downloadFile(file.id) {
                    let dest = downloadDir.appendingPathComponent(file.filename)
                    try? data.write(to: dest)
                    var ids = UserDefaults.standard.stringArray(forKey: "autoSavedFileIDs") ?? []
                    ids.append(file.id)
                    UserDefaults.standard.set(ids, forKey: "autoSavedFileIDs")

                    // Feature 6: Auto-open if enabled
                    if autoOpen {
                        NSWorkspace.shared.open(dest)
                    }
                }
            }
        }
    }

    func deleteFile(_ file: BeamletFile) {
        files.removeAll { $0.id == file.id }
        Task {
            try? await api.deleteFile(file.id)
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

    func togglePin(_ fileID: String) async {
        let _ = try? await api.togglePin(fileID)
        await loadFiles()
    }

    func markRead(_ fileID: String) {
        Task {
            try? await api.markRead(fileID)
        }
    }

    func thumbnailURL(for fileID: String) -> URL? {
        api.thumbnailURL(for: fileID)
    }

    var authHeaders: [String: String] {
        api.authHeaders
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.loadFiles()
            }
        }
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
