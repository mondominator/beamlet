import SwiftUI

struct InboxItemView: View {
    let file: BeamletFile
    let thumbnailURL: URL?
    let authHeaders: [String: String]
    let onTap: () -> Void
    let onSavePhoto: (UIImage) -> Void
    let onReply: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onShare: (Data) -> Void

    @State private var fullImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender header
            HStack(spacing: 8) {
                AvatarView(name: file.senderName ?? "?", size: 28)

                Text(file.senderName ?? "Unknown")
                    .font(.subheadline.weight(.semibold))

                if !file.read {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 7, height: 7)
                }

                if file.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let date = file.createdAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Content — varies by type
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
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu { contextMenuItems }
        .background(Color(.systemBackground))
    }

    // MARK: - Image

    @ViewBuilder
    private var imageContent: some View {
        if let url = thumbnailURL {
            AuthenticatedImage(url: url, authHeaders: authHeaders)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Video

    @ViewBuilder
    private var videoContent: some View {
        if let url = thumbnailURL {
            ZStack {
                AuthenticatedImage(url: url, authHeaders: authHeaders)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 8)
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .foregroundStyle(.purple)
                Text(file.filename)
                    .foregroundStyle(.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Text

    private func textContent(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Link

    private func linkContent(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "safari.fill")
                .font(.title3)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .lineLimit(2)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Generic File

    private var genericFileContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if file.isImage {
            Button {
                onTap() // Opens full-screen viewer which has save
            } label: {
                Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }

        if file.isText, let text = file.textContent {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }

        Button { onReply() } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
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

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: file.fileSize)
    }
}
