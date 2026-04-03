import SwiftUI
import UniformTypeIdentifiers

struct InboxItemRow: View {
    let file: BeamletFile
    let thumbnailURL: URL?
    let authHeaders: [String: String]
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    /// Returns the auto-saved file URL in ~/Downloads/Beamlet/ if it exists
    private var autoSavedURL: URL? {
        let downloadDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Beamlet")
            .appendingPathComponent(file.filename)
        return FileManager.default.fileExists(atPath: downloadDir.path) ? downloadDir : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender header
            HStack(spacing: 6) {
                AvatarView(name: file.senderName ?? "?", size: 22)

                Text(file.senderName ?? "Unknown")
                    .font(.system(size: 12, weight: .semibold))

                if !file.read {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 6, height: 6)
                }

                if file.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let date = file.createdAt {
                    Text(date, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Content
            Group {
                if file.isImage {
                    imageContent
                } else if file.isVideo {
                    videoContent
                } else if file.isText, let text = file.textContent {
                    textContent(text)
                } else if file.isLink, let text = file.textContent {
                    linkContent(text)
                } else {
                    genericFileContent
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu { contextMenuItems }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Feature 2: Drag files out of inbox
        .onDrag {
            let provider = NSItemProvider()
            if let savedURL = autoSavedURL {
                // File already saved locally, provide it directly
                provider.registerFileRepresentation(
                    forTypeIdentifier: UTType.data.identifier,
                    visibility: .all
                ) { completion in
                    completion(savedURL, true, nil)
                    return nil
                }
            } else if file.isText, let text = file.textContent {
                // For text items, provide as string
                provider.registerObject(ofClass: NSString.self, visibility: .all) { completion in
                    completion(text as NSString, nil)
                    return nil
                }
            }
            return provider
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var imageContent: some View {
        if let url = thumbnailURL {
            AuthenticatedImage(url: url, authHeaders: authHeaders)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Video

    @ViewBuilder
    private var videoContent: some View {
        if let url = thumbnailURL {
            ZStack {
                AuthenticatedImage(url: url, authHeaders: authHeaders)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .foregroundStyle(.purple)
                    .font(.system(size: 12))
                Text(file.filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Text

    private func textContent(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Link

    private func linkContent(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "safari.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .lineLimit(2)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Generic File

    private var genericFileContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.filename)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(file.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Context Menu (native macOS right-click)

    @ViewBuilder
    private var contextMenuItems: some View {
        if file.isImage {
            Button {
                onTap()
            } label: {
                Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }

        if file.isText, let text = file.textContent {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }

        if file.isLink, let text = file.textContent, let url = URL(string: text) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open Link", systemImage: "safari")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
        }

        Button {
            onPin()
        } label: {
            Label(
                file.pinned == true ? "Unpin" : "Pin",
                systemImage: file.pinned == true ? "pin.slash" : "pin"
            )
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
