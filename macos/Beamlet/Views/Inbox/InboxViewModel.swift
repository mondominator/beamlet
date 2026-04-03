import Foundation

@Observable
@MainActor
class InboxViewModel {
    private let api: BeamletAPI

    var files: [BeamletFile] = []
    var isLoading = true
    var error: String?

    private var refreshTimer: Timer?

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

            files = newFiles
            isLoading = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            isLoading = false
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
