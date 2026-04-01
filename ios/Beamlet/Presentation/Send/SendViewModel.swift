import Foundation
import PhotosUI
import SwiftUI

@Observable
@MainActor
class SendViewModel {
    private let api: BeamletAPI

    var users: [BeamletUser] = []
    var selectedUsers: Set<String> = []  // Set of user IDs
    var message = ""
    var selectedPhoto: PhotosPickerItem?
    var selectedPhotoData: Data?
    var isSending = false
    var error: String?
    var showSuccess = false

    var canSend: Bool {
        !selectedUsers.isEmpty && (selectedPhotoData != nil || !message.isEmpty) && !isSending
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
        guard !selectedUsers.isEmpty else { return }
        isSending = true
        error = nil

        do {
            for userID in selectedUsers {
                if let photoData = selectedPhotoData {
                    let _ = try await api.uploadFile(
                        recipientID: userID,
                        fileData: photoData,
                        filename: "photo.jpg",
                        mimeType: "image/jpeg",
                        message: message.isEmpty ? nil : message
                    )
                } else if !message.isEmpty {
                    let _ = try await api.uploadText(
                        recipientID: userID,
                        text: message
                    )
                }
            }
            showSuccess = true
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    func reset() {
        selectedUsers.removeAll()
        selectedPhoto = nil
        selectedPhotoData = nil
        message = ""
    }
}
