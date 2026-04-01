import Foundation
import UIKit

@Observable
@MainActor
class InboxViewModel {
    private let api: BeamletAPI
    private var previousUnreadCount = 0

    var files: [BeamletFile] = []
    var isLoading = true
    var error: String?
    var hasNewFiles = false

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadFiles() async {
        do {
            let newFiles = try await api.listFiles()
            let newUnreadCount = newFiles.filter { !$0.read }.count

            // Haptic on new unread files
            if newUnreadCount > previousUnreadCount && previousUnreadCount > 0 {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                hasNewFiles = true
                // Reset after brief flash
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.hasNewFiles = false
                }
            }
            previousUnreadCount = newUnreadCount

            files = newFiles
            isLoading = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            isLoading = false
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

    func thumbnailURL(for fileID: String) -> URL? {
        api.thumbnailURL(for: fileID)
    }

    var authHeaders: [String: String] {
        api.authHeaders
    }
}
