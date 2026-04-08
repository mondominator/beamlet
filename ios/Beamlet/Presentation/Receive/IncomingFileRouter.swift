import Foundation
import SwiftUI
import UIKit

/// Receives a notification tap (or any other "incoming file" trigger),
/// downloads the file from the server, and routes it to the right place:
///
///   - URLs   → open in Safari + brief toast
///   - Text   → copy to clipboard + brief toast
///   - Files  → write to a temp directory and present `UIActivityViewController`
///              (the system share sheet) so the user can save to Photos /
///              Files / Books / wherever.
///
/// Beamlet itself never persists incoming files. The temp file is deleted
/// once the share sheet dismisses (success or cancel — `completionWithItemsHandler`
/// fires either way).
@MainActor
@Observable
final class IncomingFileRouter {

    /// A media file ready to hand off to the share sheet. Driven by
    /// `MainView`'s `.sheet(item:)` modifier.
    struct SharePresentation: Identifiable {
        let id = UUID()
        let fileURL: URL
        let filename: String
    }

    /// Lightweight banner shown at the top of the screen for status messages
    /// (link opened, text copied, error). Auto-dismisses after a few seconds.
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var sharePresentation: SharePresentation?
    var toast: Toast?

    private let api: BeamletAPI
    private var inFlight: Set<String> = []

    init(api: BeamletAPI) {
        self.api = api
    }

    /// Entry point invoked by `BeamletApp` when the user taps a Beamlet
    /// notification. The file ID comes from the APNs payload's `file_id`
    /// custom key (see server/internal/push/apns.go).
    func receive(fileID: String) {
        guard !inFlight.contains(fileID) else { return }
        inFlight.insert(fileID)

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight.remove(fileID) } }
            await self.handle(fileID: fileID)
        }
    }

    /// Dismiss any pending share sheet and clean up its temp file.
    func clearShare() {
        if let url = sharePresentation?.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        sharePresentation = nil
    }

    func clearToast() {
        toast = nil
    }

    // MARK: - Private

    private func handle(fileID: String) async {
        let item: BeamletAPI.DownloadedItem
        do {
            item = try await api.downloadItem(fileID)
        } catch {
            toast = Toast(
                message: "Couldn't download: \(error.localizedDescription)",
                isError: true
            )
            return
        }

        switch item {
        case .link(let file):
            await openLink(file: file)
        case .text(let file):
            copyText(file: file)
        case .media(let data, _, let filename):
            saveAndShare(data: data, filename: filename)
        }

        // Best-effort read receipt — failure here is non-fatal because
        // the recipient already has (or rejected) the content.
        _ = try? await api.markRead(fileID)
    }

    private func openLink(file: BeamletFile) async {
        guard let raw = file.textContent, let url = URL(string: raw) else {
            toast = Toast(message: "This link is empty.", isError: true)
            return
        }
        let opened = await UIApplication.shared.open(url)
        toast = Toast(
            message: opened ? "Opened in browser" : "Couldn't open link",
            isError: !opened
        )
    }

    private func copyText(file: BeamletFile) {
        let body = file.textContent ?? ""
        UIPasteboard.general.string = body
        toast = Toast(
            message: body.isEmpty ? "Empty message" : "Copied to clipboard",
            isError: body.isEmpty
        )
    }

    /// Write the downloaded bytes to a fresh per-call subfolder under the
    /// system temp directory and surface a share-sheet presentation. Each
    /// call gets its own subfolder so concurrent receives can't collide on
    /// filenames, and so cleanup can blow away the whole subfolder later
    /// without having to track individual file paths.
    private func saveAndShare(data: Data, filename: String) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("beamlet-incoming")
            .appendingPathComponent(UUID().uuidString)
        let target = folder.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
            sharePresentation = SharePresentation(fileURL: target, filename: filename)
        } catch {
            toast = Toast(
                message: "Couldn't save file: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
