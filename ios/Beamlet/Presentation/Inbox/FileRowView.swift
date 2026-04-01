import SwiftUI

struct FileRowView: View {
    let file: BeamletFile
    let thumbnailURL: URL?
    let authHeaders: [String: String]

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail or icon
            Group {
                if file.isImage || file.isVideo, let url = thumbnailURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.15))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconBackground)
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundStyle(iconColor)
                    }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.senderName ?? "Unknown")
                        .font(.headline)
                    if !file.read {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                    if let date = file.createdAt {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if file.isText, let text = file.textContent {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let message = file.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundStyle(iconColor)
                        Text(file.displayType)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        if file.isImage { return "photo.fill" }
        if file.isVideo { return "video.fill" }
        if file.isText { return "text.bubble.fill" }
        if file.isLink { return "link" }
        return "doc.fill"
    }

    private var iconColor: Color {
        if file.isImage { return .blue }
        if file.isVideo { return .purple }
        if file.isText { return .green }
        if file.isLink { return .orange }
        return .gray
    }

    private var iconBackground: Color {
        iconColor.opacity(0.12)
    }
}
