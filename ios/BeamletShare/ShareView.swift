import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let api: BeamletAPI
    let extensionContext: NSExtensionContext?

    @State private var users: [BeamletUser] = []
    @State private var selectedUser: BeamletUser?
    @State private var message = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var sharedItems: [SharedItem] = []

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section("Send to") {
                            Picker("Recipient", selection: $selectedUser) {
                                Text("Select").tag(nil as BeamletUser?)
                                ForEach(users) { user in
                                    Text(user.name).tag(user as BeamletUser?)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if !sharedItems.isEmpty {
                            Section("Sharing") {
                                ForEach(sharedItems) { item in
                                    Label(item.description, systemImage: item.icon)
                                }
                            }
                        }

                        Section {
                            TextField("Message (optional)", text: $message)
                        }

                        if let error = error {
                            Section {
                                Text(error).foregroundStyle(.red).font(.callout)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Beamlet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        extensionContext?.completeRequest(returningItems: nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(selectedUser == nil || isSending)
                        .bold()
                }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        // Load users
        users = (try? await api.listUsers()) ?? []

        // Extract shared items from extension context
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            isLoading = false
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let shared = await extractItem(from: provider) {
                    sharedItems.append(shared)
                }
            }
        }

        isLoading = false
    }

    private func extractItem(from provider: NSItemProvider) async -> SharedItem? {
        // Try URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return SharedItem(type: .link, text: url.absoluteString)
            }
        }

        // Try text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return SharedItem(type: .text, text: text)
            }
        }

        // Try image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .image, data: data, filename: url.lastPathComponent)
            }
        }

        // Try video
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .video, data: data, filename: url.lastPathComponent)
            }
        }

        // Try any file
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .file, data: data, filename: url.lastPathComponent)
            }
        }

        return nil
    }

    private func send() {
        guard let user = selectedUser else { return }
        isSending = true
        error = nil

        Task {
            do {
                for item in sharedItems {
                    switch item.type {
                    case .text:
                        let _ = try await api.uploadText(recipientID: user.id, text: item.text ?? "")
                    case .link:
                        let _ = try await api.uploadText(recipientID: user.id, text: item.text ?? "", contentType: "link")
                    case .image:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "image.jpg",
                                mimeType: "image/jpeg",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    case .video:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "video.mp4",
                                mimeType: "video/mp4",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    case .file:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: user.id,
                                fileData: data,
                                filename: item.filename ?? "file",
                                mimeType: "application/octet-stream",
                                message: message.isEmpty ? nil : message
                            )
                        }
                    }
                }

                // If only a text message (no shared items)
                if sharedItems.isEmpty && !message.isEmpty {
                    let _ = try await api.uploadText(recipientID: user.id, text: message)
                }

                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                self.error = error.localizedDescription
                isSending = false
            }
        }
    }
}

// MARK: - Shared Item Model

struct SharedItem: Identifiable {
    let id = UUID()
    let type: SharedItemType
    var text: String?
    var data: Data?
    var filename: String?

    var description: String {
        switch type {
        case .text: return text?.prefix(50).description ?? "Text"
        case .link: return text ?? "Link"
        case .image: return filename ?? "Photo"
        case .video: return filename ?? "Video"
        case .file: return filename ?? "File"
        }
    }

    var icon: String {
        switch type {
        case .text: return "text.bubble"
        case .link: return "link"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        }
    }
}

enum SharedItemType {
    case text, link, image, video, file
}
