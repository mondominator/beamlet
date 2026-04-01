import SwiftUI

struct AuthenticatedImage: View {
    let url: URL
    let authHeaders: [String: String]

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if isLoading {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.7))
            } else {
                RoundedRectangle(cornerRadius: 10)
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
            if let uiImage = UIImage(data: data) {
                image = uiImage
            }
        } catch {
            // Failed to load
        }
        isLoading = false
    }
}
