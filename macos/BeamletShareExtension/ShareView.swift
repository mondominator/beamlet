import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let api: BeamletAPI
    let extensionContext: NSExtensionContext?

    @State private var contacts: [BeamletUser] = []
    @State private var isLoading = true
    @State private var sendingTo: String?
    @State private var sent = false
    @State private var errorMessage: String?
    @State private var sharedItems: [SharedItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
                Spacer()
                Text("Beamlet")
                    .font(.headline)
                Spacer()
                // Invisible balance button
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
                    .controlSize(.large)
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
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 88), spacing: 8)
                    ], spacing: 16) {
                        ForEach(contacts) { contact in
                            contactButton(contact: contact)
                        }
                    }
                    .padding(24)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 300)
        .task {
            await loadData()
        }
    }

    // MARK: - Contact Button

    @ViewBuilder
    private func contactButton(contact: BeamletUser) -> some View {
        Button {
            sendTo(contact)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if sendingTo == contact.id {
                        avatarView(name: contact.name, size: 56)
                            .opacity(0.4)
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        avatarView(name: contact.name, size: 56)
                    }
                }

                Text(contact.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 88)
        }
        .buttonStyle(.plain)
        .disabled(sendingTo != nil)
    }

    // MARK: - Avatar

    private func avatarView(name: String, size: CGFloat) -> some View {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()

        let hue = Double(abs(name.hashValue) % 360) / 360.0

        return ZStack {
            Circle()
                .fill(Color(hue: hue, saturation: 0.5, brightness: 0.85))
                .frame(width: size, height: size)
            Text(initials.uppercased())
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Load Data

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

    // MARK: - Extract Shared Items

    private static let maxShareFileSize = 100_000_000 // 100 MB

    private func loadFileData(from url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let size = fileSize, size > Self.maxShareFileSize {
            errorMessage = "File too large (max 100 MB)"
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func extractItem(from provider: NSItemProvider) async -> SharedItem? {
        // URLs (web links)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                // If it's a file URL, treat as file; otherwise as link
                if url.isFileURL {
                    if let data = loadFileData(from: url) {
                        let mimeType = mimeTypeForExtension(url.pathExtension)
                        if mimeType.hasPrefix("image/") {
                            return SharedItem(type: .image, data: data, filename: url.lastPathComponent)
                        } else if mimeType.hasPrefix("video/") {
                            return SharedItem(type: .video, data: data, filename: url.lastPathComponent)
                        } else {
                            return SharedItem(type: .file, data: data, filename: url.lastPathComponent)
                        }
                    }
                } else {
                    return SharedItem(type: .link, text: url.absoluteString)
                }
            }
        }

        // Plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return SharedItem(type: .text, text: text)
            }
        }

        // Images
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = loadFileData(from: url) {
                return SharedItem(type: .image, data: data, filename: url.lastPathComponent)
            }
        }

        // Movies
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.movie.identifier) as? URL,
               let data = loadFileData(from: url) {
                return SharedItem(type: .video, data: data, filename: url.lastPathComponent)
            }
        }

        // Generic data/files
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? URL,
               let data = loadFileData(from: url) {
                return SharedItem(type: .file, data: data, filename: url.lastPathComponent)
            }
        }

        return nil
    }

    // MARK: - Send

    private func sendTo(_ contact: BeamletUser) {
        sendingTo = contact.id
        errorMessage = nil

        Task {
            do {
                for item in sharedItems {
                    switch item.type {
                    case .text:
                        _ = try await api.uploadText(
                            recipientID: contact.id,
                            text: item.text ?? ""
                        )
                    case .link:
                        _ = try await api.uploadText(
                            recipientID: contact.id,
                            text: item.text ?? "",
                            contentType: "link"
                        )
                    case .image:
                        if let data = item.data {
                            let filename = item.filename ?? "image.jpg"
                            let mime = mimeTypeForExtension(
                                (filename as NSString).pathExtension
                            )
                            _ = try await api.uploadFile(
                                recipientID: contact.id,
                                fileData: data,
                                filename: filename,
                                mimeType: mime
                            )
                        }
                    case .video:
                        if let data = item.data {
                            let filename = item.filename ?? "video.mp4"
                            let mime = mimeTypeForExtension(
                                (filename as NSString).pathExtension
                            )
                            _ = try await api.uploadFile(
                                recipientID: contact.id,
                                fileData: data,
                                filename: filename,
                                mimeType: mime
                            )
                        }
                    case .file:
                        if let data = item.data {
                            let filename = item.filename ?? "file"
                            let mime = mimeTypeForExtension(
                                (filename as NSString).pathExtension
                            )
                            _ = try await api.uploadFile(
                                recipientID: contact.id,
                                fileData: data,
                                filename: filename,
                                mimeType: mime
                            )
                        }
                    }
                }

                sent = true
                try? await Task.sleep(for: .seconds(1))
                extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            } catch {
                errorMessage = error.localizedDescription
                sendingTo = nil
            }
        }
    }

    // MARK: - MIME Type Helper

    private func mimeTypeForExtension(_ ext: String) -> String {
        if let utType = UTType(filenameExtension: ext) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
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
