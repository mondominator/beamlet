import SwiftUI

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showQRPasteSheet = false
    @State private var qrJSONText = ""
    @State private var scannedPayload: QRPayload?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    Text("Beamlet")
                        .font(.title.bold())

                    Text("Connect to your Beamlet server")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // QR / Invite paste button
                Button {
                    showQRPasteSheet = true
                } label: {
                    Label("Paste Invite QR Code", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                    Text("or enter manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                }
                .padding(.horizontal, 24)

                // Manual form
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL")
                            .font(.headline)
                        TextField("https://beamlet.example.com", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Token")
                            .font(.headline)
                        SecureField("Paste your token here", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 24)

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal, 24)
                }

                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showQRPasteSheet) {
            qrPasteSheet
        }
        .sheet(item: $scannedPayload) { payload in
            NameEntrySheet(
                serverURL: payload.url,
                inviteToken: payload.invite,
                onComplete: { scannedPayload = nil }
            )
            .environment(authRepository)
            .environment(api)
        }
    }

    // MARK: - QR Paste Sheet

    private var qrPasteSheet: some View {
        VStack(spacing: 16) {
            Text("Paste QR Code JSON")
                .font(.headline)
                .padding(.top, 16)

            Text("Copy the QR code content from another device and paste it below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextEditor(text: $qrJSONText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .border(Color.secondary.opacity(0.3))
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") {
                    qrJSONText = ""
                    showQRPasteSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    handleQRPaste()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(qrJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 360, height: 280)
    }

    // MARK: - Actions

    private func handleQRPaste() {
        let trimmed = qrJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code JSON. Expected format: {\"u\":\"...\",\"i\":\"...\"}"
            showQRPasteSheet = false
            return
        }
        showQRPasteSheet = false
        qrJSONText = ""
        scannedPayload = payload
    }

    private func connect() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            var validationRequest = URLRequest(url: url.appendingPathComponent("api/contacts"))
            validationRequest.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")

            do {
                let (_, response) = try await URLSession.shared.data(for: validationRequest)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    error = "Invalid token or server URL"
                    isConnecting = false
                    return
                }
            } catch {
                self.error = "Could not connect to server"
                isConnecting = false
                return
            }

            authRepository.store(serverURL: url, token: trimmedToken)

            if let me = try? await api.getMe() {
                authRepository.storeUserID(me.id)
            }

            isConnecting = false
        }
    }
}

// MARK: - Name Entry Sheet (for invite flow)

private struct NameEntrySheet: View {
    let serverURL: String
    let inviteToken: String
    let onComplete: () -> Void

    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Your Name")
                .font(.headline)
                .padding(.top, 16)

            Text("Choose a display name for your Beamlet account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                    onComplete()
                }
                .keyboardShortcut(.cancelAction)

                Button("Join") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 320, height: 220)
    }

    private func submit() {
        guard let url = URL(string: serverURL) else {
            error = "Invalid server URL"
            return
        }

        isSubmitting = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInvite(
                    serverURL: url,
                    inviteToken: inviteToken,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                if let token = response.token {
                    authRepository.store(serverURL: url, token: token)
                    if let userID = response.userID {
                        authRepository.storeUserID(userID)
                    }
                }

                dismiss()
                onComplete()
            } catch {
                self.error = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
