import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AppKit

@Observable
@MainActor
class SendViewModel {
    private let api: BeamletAPI

    var users: [BeamletUser] = []
    var selectedUsers: Set<String> = []
    var selectedPhoto: PhotosPickerItem?
    var selectedPhotoData: Data?
    var selectedFileURL: URL?
    var selectedFileName: String?
    var selectedFileMimeType: String?
    var isSending = false
    var isLoadingUsers = true
    var error: String?
    var showSuccess = false
    var uploadProgress: Double = 0

    var canSend: Bool {
        !selectedUsers.isEmpty && (selectedPhotoData != nil || selectedFileURL != nil) && !isSending
    }

    var attachmentDisplayName: String? {
        if selectedPhotoData != nil { return "Photo selected" }
        if let name = selectedFileName { return name }
        return nil
    }

    init(api: BeamletAPI) {
        self.api = api
    }

    // MARK: - Contacts

    func loadUsers() async {
        isLoadingUsers = true
        users = (try? await api.listUsers()) ?? []
        isLoadingUsers = false
    }

    func toggleUser(_ user: BeamletUser) {
        if selectedUsers.contains(user.id) {
            selectedUsers.remove(user.id)
        } else {
            selectedUsers.insert(user.id)
        }
    }

    func isSelected(_ user: BeamletUser) -> Bool {
        selectedUsers.contains(user.id)
    }

    // MARK: - Attachment

    func clearAttachment() {
        selectedFileURL?.stopAccessingSecurityScopedResource()
        selectedPhoto = nil
        selectedPhotoData = nil
        selectedFileURL = nil
        selectedFileName = nil
        selectedFileMimeType = nil
    }

    func clearFileAttachment() {
        selectedFileURL?.stopAccessingSecurityScopedResource()
        selectedFileURL = nil
        selectedFileName = nil
        selectedFileMimeType = nil
    }

    /// Handle file URLs from drag-and-drop or NSOpenPanel
    func handleFileURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        _ = url.startAccessingSecurityScopedResource()
        selectedFileURL = url
        selectedFileName = url.lastPathComponent
        selectedFileMimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        selectedPhoto = nil
        selectedPhotoData = nil
    }

    /// Open NSOpenPanel to pick files (macOS native)
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        panel.title = "Choose a file to send"

        if panel.runModal() == .OK, let url = panel.url {
            handleFileURLs([url])
        }
    }

    /// Load photo data from PhotosPickerItem
    func loadPhotoData() async {
        guard let item = selectedPhoto else { return }
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let nsImage = NSImage(data: rawData),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            selectedPhotoData = nil
            return
        }
        selectedPhotoData = jpegData
    }

    // MARK: - Send

    func send() async {
        guard !selectedUsers.isEmpty else { return }
        isSending = true
        error = nil
        uploadProgress = 0

        let expiry = UserDefaults.standard.integer(forKey: "fileExpiryDays")
        let expiryDays = expiry > 0 ? expiry : 1

        var fileData: Data?
        var fileName: String?
        var fileMimeType: String?

        if let photoData = selectedPhotoData {
            fileData = photoData
            fileName = "photo.jpg"
            fileMimeType = "image/jpeg"
        } else if let fileURL = selectedFileURL {
            do {
                fileData = try Data(contentsOf: fileURL)
            } catch {
                self.error = error.localizedDescription
                isSending = false
                return
            }
            fileURL.stopAccessingSecurityScopedResource()
            selectedFileURL = nil
            fileName = selectedFileName ?? fileURL.lastPathComponent
            fileMimeType = selectedFileMimeType ?? "application/octet-stream"
        }

        guard let data = fileData, let name = fileName else {
            isSending = false
            return
        }

        let totalUsers = selectedUsers.count
        var completedUsers = 0

        do {
            for userID in selectedUsers {
                let _ = try await api.uploadFile(
                    recipientID: userID,
                    fileData: data,
                    filename: name,
                    mimeType: fileMimeType ?? "application/octet-stream",
                    message: nil,
                    expiryDays: expiryDays
                )
                completedUsers += 1
                uploadProgress = Double(completedUsers) / Double(totalUsers)
            }
            showSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    func reset() {
        selectedUsers.removeAll()
        selectedFileURL?.stopAccessingSecurityScopedResource()
        selectedPhoto = nil
        selectedPhotoData = nil
        selectedFileURL = nil
        selectedFileName = nil
        selectedFileMimeType = nil
        uploadProgress = 0
    }
}
