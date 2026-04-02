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
    @State private var nearbyService: NearbyService?
    @State private var nearbyUsers: [NearbyUser] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button("Cancel") {
                    nearbyService?.stop()
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
            } else if contacts.isEmpty && nearbyUsers.isEmpty {
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
                let nearbyIDs = Set(nearbyUsers.map(\.id))
                let nearbyContacts = contacts.filter { nearbyIDs.contains($0.id) }
                let nearbyNonContacts = nearbyUsers.filter { !$0.isContact }
                let otherContacts = contacts.filter { !nearbyIDs.contains($0.id) }

                ScrollView {
                    VStack(spacing: 24) {
                        // Nearby section (pulsing)
                        if !nearbyContacts.isEmpty || !nearbyNonContacts.isEmpty {
                            VStack(spacing: 12) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.teal)
                                        .font(.caption)
                                    Text("Nearby")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }

                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 88), spacing: 8)
                                ], spacing: 16) {
                                    ForEach(nearbyNonContacts) { user in
                                        contactButton(id: user.id, name: user.name, isNearby: true, isContact: false)
                                    }
                                    ForEach(nearbyContacts) { contact in
                                        contactButton(id: contact.id, name: contact.name, isNearby: true, isContact: true)
                                    }
                                }
                            }

                            if !otherContacts.isEmpty {
                                Divider().padding(.horizontal)
                            }
                        }

                        // Other contacts section
                        if !otherContacts.isEmpty {
                            VStack(spacing: 12) {
                                if !nearbyContacts.isEmpty || !nearbyNonContacts.isEmpty {
                                    HStack {
                                        Image(systemName: "person.2")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Text("Contacts")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 88), spacing: 8)
                                ], spacing: 16) {
                                    ForEach(otherContacts) { contact in
                                        contactButton(id: contact.id, name: contact.name, isNearby: false, isContact: true)
                                    }
                                }
                            }
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

        // Start BLE scanning
        if let userID = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "userID") {
            let service = NearbyService(userID: userID, api: api)
            service.updateContacts(contacts)
            service.start()
            nearbyService = service
        }

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

        // Continuously poll nearby users (updates every 3s)
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if let service = nearbyService {
                    nearbyUsers = service.nearbyUsers
                }
            }
        }
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

    @ViewBuilder
    private func contactButton(id: String, name: String, isNearby: Bool, isContact: Bool) -> some View {
        Button {
            sendTo(BeamletUser(id: id, name: name, createdAt: nil))
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if isNearby {
                        PulsingAvatarView(
                            name: name,
                            isContact: isContact,
                            isSelected: sendingTo == id,
                            size: 56
                        )
                    } else if sendingTo == id {
                        ZStack {
                            AvatarView(name: name, size: 56)
                                .opacity(0.4)
                            ProgressView()
                        }
                    } else {
                        AvatarView(name: name, size: 56)
                    }
                }

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 88)
        }
        .disabled(sendingTo != nil)
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
                nearbyService?.stop()
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
