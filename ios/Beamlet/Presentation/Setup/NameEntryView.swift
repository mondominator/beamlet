import SwiftUI

struct NameEntryView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    let serverURL: URL
    let inviteToken: String
    let onComplete: () -> Void

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("What's your name?")
                    .font(.title2.bold())
                Text("This is how others will see you in Beamlet.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            .padding(.horizontal)
        }
        .padding()
    }

    private func submit() {
        isSubmitting = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInvite(
                    serverURL: serverURL,
                    inviteToken: inviteToken,
                    name: name.trimmingCharacters(in: .whitespaces)
                )

                guard let token = response.token else {
                    self.error = "Invalid response from server"
                    isSubmitting = false
                    return
                }

                authRepository.store(serverURL: serverURL, token: token)
                onComplete()
            } catch {
                self.error = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
