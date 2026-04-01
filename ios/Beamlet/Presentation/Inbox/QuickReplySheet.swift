import SwiftUI
import PhotosUI
import AudioToolbox

struct QuickReplySheet: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(\.dismiss) private var dismiss

    let recipientID: String
    let recipientName: String
    let replyToMessage: String?

    @State private var message = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isSending = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Reply context
                if let original = replyToMessage, !original.isEmpty {
                    HStack {
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 3)
                        Text(original)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }

                // Reply input
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        AvatarView(name: recipientName, size: 32)
                        Text("Reply to \(recipientName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)

                    TextField("Type a message...", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(
                                selectedPhotoData != nil ? "Photo attached" : "Add photo",
                                systemImage: selectedPhotoData != nil ? "checkmark.circle.fill" : "photo"
                            )
                            .font(.subheadline)
                        }
                        .onChange(of: selectedPhoto) {
                            Task {
                                selectedPhotoData = try? await selectedPhoto?.loadTransferable(type: Data.self)
                            }
                        }

                        Spacer()

                        Button {
                            Task { await send() }
                        } label: {
                            if isSending {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.title3)
                            }
                        }
                        .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty && selectedPhotoData == nil)
                        .disabled(isSending)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func send() async {
        isSending = true
        do {
            if let photoData = selectedPhotoData {
                let _ = try await api.uploadFile(
                    recipientID: recipientID,
                    fileData: photoData,
                    filename: "reply.jpg",
                    mimeType: "image/jpeg",
                    message: message.isEmpty ? nil : message
                )
            } else {
                let _ = try await api.uploadText(
                    recipientID: recipientID,
                    text: message
                )
            }
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1001)
            dismiss()
        } catch {
            isSending = false
        }
    }
}
