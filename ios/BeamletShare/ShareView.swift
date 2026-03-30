import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let api: BeamletAPI
    let extensionContext: NSExtensionContext?

    @State private var contacts: [BeamletUser] = []
    @State private var isLoading = true
    @State private var sendingTo: String?
    @State private var sent = false
    @State private var error: String?
    @State private var sharedItems: [SharedItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button("Cancel") {
                    extensionContext?.completeRequest(returningItems: nil)
                }
                Spacer()
                Text("Beamlet")
                    .font(.headline)
                Spacer()
                // Balance the cancel button
                Button("Cancel") {}.hidden()
            }
            .padding()

            Divider()

            if sent {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Sent!")
                        .font(.title3.bold())
                }
                Spacer()
            } else if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if contacts.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No contacts yet")
                        .font(.headline)
                    Text("Add contacts in the Beamlet app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                // Contact grid — AirDrop style
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80), spacing: 16)
                    ], spacing: 20) {
                        ForEach(contacts) { contact in
                            Button {
                                sendTo(contact)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(width: 60, height: 60)

                                        if sendingTo == contact.id {
                                            ProgressView()
                                        } else {
                                            Text(contact.name.prefix(1).uppercased())
                                                .font(.title2.bold())
                                                .foregroundStyle(.blue)
                                        }
                                    }

                                    Text(contact.name)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .disabled(sendingTo != nil)
                        }
                    }
                    .padding(24)
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        contacts = (try? await api.listUsers()) ?? []

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
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return SharedItem(type: .link, text: url.absoluteString)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return SharedItem(type: .text, text: text)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .image, data: data, filename: url.lastPathComponent)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .video, data: data, filename: url.lastPathComponent)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return SharedItem(type: .file, data: data, filename: url.lastPathComponent)
            }
        }
        return nil
    }

    private func sendTo(_ contact: BeamletUser) {
        sendingTo = contact.id
        error = nil

        Task {
            do {
                for item in sharedItems {
                    switch item.type {
                    case .text:
                        let _ = try await api.uploadText(recipientID: contact.id, text: item.text ?? "")
                    case .link:
                        let _ = try await api.uploadText(recipientID: contact.id, text: item.text ?? "", contentType: "link")
                    case .image:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: contact.id, fileData: data,
                                filename: item.filename ?? "image.jpg", mimeType: "image/jpeg"
                            )
                        }
                    case .video:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: contact.id, fileData: data,
                                filename: item.filename ?? "video.mp4", mimeType: "video/mp4"
                            )
                        }
                    case .file:
                        if let data = item.data {
                            let _ = try await api.uploadFile(
                                recipientID: contact.id, fileData: data,
                                filename: item.filename ?? "file", mimeType: "application/octet-stream"
                            )
                        }
                    }
                }

                sent = true
                try? await Task.sleep(for: .seconds(1))
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                self.error = error.localizedDescription
                sendingTo = nil
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
}

enum SharedItemType {
    case text, link, image, video, file
}
