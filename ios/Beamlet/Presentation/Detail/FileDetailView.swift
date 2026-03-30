import SwiftUI
import QuickLook

struct FileDetailView: View {
    @Environment(BeamletAPI.self) private var api
    let file: BeamletFile

    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var error: String?
    @State private var savedToPhotos = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("From \(file.senderName ?? "Unknown")")
                        .font(.headline)
                    if let date = file.createdAt {
                        Text(date, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let message = file.message, !message.isEmpty {
                        Text(message)
                            .font(.body)
                            .padding(.top, 4)
                    }
                }
                .padding()

                // Content
                if file.isText, let text = file.textContent {
                    Text(text)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = text
                            }
                        }
                } else if file.isLink, let text = file.textContent, let url = URL(string: text) {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "link")
                            Text(text)
                                .lineLimit(2)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                } else if file.isImage {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .contextMenu {
                                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                                    savedToPhotos = true
                                }
                                ShareLink(item: Image(uiImage: uiImage), preview: SharePreview(file.filename, image: Image(uiImage: uiImage)))
                            }
                    } else if isLoading {
                        ProgressView("Downloading...")
                            .frame(height: 200)
                    }
                } else {
                    // Generic file
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text(file.filename)
                            .font(.headline)
                        Text(formattedSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                }

                if savedToPhotos {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(file.displayType)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Mark as read
            try? await api.markRead(file.id)

            // Download content for images
            if file.isImage {
                isLoading = true
                do {
                    imageData = try await api.downloadFile(file.id)
                } catch {
                    self.error = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: file.fileSize)
    }
}
