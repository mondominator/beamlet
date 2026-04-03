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
            }
            previousUnreadCount = newUnreadCount

            // Auto-delete received files older than user's cleanup preference
            let expiryDays = UserDefaults.standard.integer(forKey: "fileExpiryDays")
            let maxAge = expiryDays > 0 ? expiryDays : 1
            let cutoff = Date().addingTimeInterval(-Double(maxAge) * 86400)

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
            }

            files = newFiles.filter { !expiredIDs.contains($0.id) }
            updateWidgetData(files)
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

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func updateWidgetData(_ files: [BeamletFile]) {
        struct WidgetFile: Codable {
            let senderName: String
            let type: String
            let timeAgo: String
        }

        let formatter = Self.relativeDateFormatter

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
