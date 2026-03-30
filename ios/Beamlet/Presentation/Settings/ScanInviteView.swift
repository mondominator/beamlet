import SwiftUI

struct ScanInviteView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var connectedName: String?
    @State private var error: String?
    @State private var isRedeeming = false

    var body: some View {
        Group {
            if let name = connectedName {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Connected with \(name)!")
                        .font(.title2.bold())
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else if isRedeeming {
                ProgressView("Connecting...")
            } else {
                QRScannerView { value in
                    handleScan(value)
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    if let error = error {
                        Text(error)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("Scan Invite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleScan(_ value: String) {
        guard let data = value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code"
            return
        }

        isRedeeming = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInviteAsExistingUser(inviteToken: payload.invite)
                connectedName = response.contact?.name ?? "New contact"
            } catch {
                self.error = error.localizedDescription
                isRedeeming = false
            }
        }
    }
}
