import Foundation
import PhotosUI
import SwiftUI

@Observable
@MainActor
class SendViewModel {
    private let api: BeamletAPI

    var users: [BeamletUser] = []
    var selectedUser: BeamletUser?
    var message = ""
    var selectedPhoto: PhotosPickerItem?
    var selectedPhotoData: Data?
    var isSending = false
    var error: String?
    var showSuccess = false

    var canSend: Bool {
        selectedUser != nil && (selectedPhotoData != nil || !message.isEmpty) && !isSending
    }

    init(api: BeamletAPI) {
        self.api = api
    }

    func loadUsers() async {
        users = (try? await api.listUsers()) ?? []
    }

    func loadPhotoData() async {
        guard let item = selectedPhoto else { return }
        selectedPhotoData = try? await item.loadTransferable(type: Data.self)
    }

    func send() async {
        guard let user = selectedUser else { return }
        isSending = true
        error = nil

        do {
            if let photoData = selectedPhotoData {
                let _ = try await api.uploadFile(
                    recipientID: user.id,
                    fileData: photoData,
                    filename: "photo.jpg",
                    mimeType: "image/jpeg",
                    message: message.isEmpty ? nil : message
                )
            } else if !message.isEmpty {
                let _ = try await api.uploadText(
                    recipientID: user.id,
                    text: message
                )
            }
            showSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    func reset() {
        selectedUser = nil
        selectedPhoto = nil
        selectedPhotoData = nil
        message = ""
    }
}
