import SwiftUI
import CoreImage.CIFilterBuiltins

struct AddContactView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(AuthRepository.self) private var authRepository

    @State private var inviteToken: String?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Creating invite...")
            } else if let error = error {
                ErrorView(message: error) {
                    Task { await createInvite() }
                }
            } else if let token = inviteToken, let url = authRepository.serverURL {
                let payload = QRPayload(url: url.absoluteString, invite: token)

                VStack(spacing: 16) {
                    Text("Have them scan this with Beamlet")
                        .font(.headline)

                    if let qrImage = generateQRCode(from: payload) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text("This code expires in 24 hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Share link button
                    if let shareURL = URL(string: "\(url.absoluteString)/invite/\(token)") {
                        ShareLink(item: shareURL, message: Text("Join me on Beamlet!")) {
                            Label("Share Invite Link", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Add Contact")
        .task {
            await createInvite()
        }
    }

    private func createInvite() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.createInvite()
            inviteToken = response.inviteToken
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func generateQRCode(from payload: QRPayload) -> UIImage? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
