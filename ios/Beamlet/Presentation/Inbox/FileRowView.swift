import SwiftUI

struct FileRowView: View {
    let file: BeamletFile
    let thumbnailURL: URL?
    let authHeaders: [String: String]

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            Group {
                if file.isImage, let url = thumbnailURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                } else {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.senderName ?? "Unknown")
                        .font(.headline)
                    if !file.read {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                if file.isText, let text = file.textContent {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let message = file.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(file.displayType)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let date = file.createdAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if file.isImage { return "photo" }
        if file.isVideo { return "video" }
        if file.isText { return "text.bubble" }
        if file.isLink { return "link" }
        return "doc"
    }
}
