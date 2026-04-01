import Foundation
import UIKit
import AudioToolbox
import WidgetKit

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
                AudioServicesPlaySystemSound(1003) // "received" ding
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

    private func updateWidgetData(_ files: [BeamletFile]) {
        struct WidgetFile: Codable {
            let senderName: String
            let type: String
            let timeAgo: String
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        let widgetFiles = files.prefix(4).map { file in
            WidgetFile(
                senderName: file.senderName ?? "Unknown",
                type: file.displayType,
                timeAgo: file.createdAt.map { formatter.localizedString(for: $0, relativeTo: Date()) } ?? ""
            )
        }

        if let data = try? JSONEncoder().encode(widgetFiles) {
            UserDefaults(suiteName: "group.com.beamlet.shared")?.set(data, forKey: "widgetRecentFiles")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
