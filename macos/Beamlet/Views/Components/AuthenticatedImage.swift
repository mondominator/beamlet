import SwiftUI
import AppKit

struct AuthenticatedImage: View {
    let url: URL
    let authHeaders: [String: String]

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.6))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        var request = URLRequest(url: url)
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let nsImage = NSImage(data: data) {
                image = nsImage
            }
        } catch {
            // Failed to load
        }
        isLoading = false
    }
}
