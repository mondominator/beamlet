import SwiftUI
import UserNotifications

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var scannedPayload: QRPayload?

    // Check for pending invite from URL scheme
    private var pendingInvite: QRPayload? {
        guard let urlStr = UserDefaults.standard.string(forKey: "pendingInviteURL"),
              let inviteToken = UserDefaults.standard.string(forKey: "pendingInviteToken") else {
            return nil
        }
        return QRPayload(url: urlStr, invite: inviteToken)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        Text("Beamlet")
                            .font(.largeTitle.bold())

                        Text("Scan a QR code or enter your server details")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // QR Scan button
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)

                    // Divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                        Text("or enter manually")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                    }
                    .padding(.horizontal)

                    // Manual form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.headline)
                            TextField("https://beamlet.example.com", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Token")
                                .font(.headline)
                            SecureField("Paste your token here", text: $token)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal)

                    if let error = error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.horizontal)
                    }

                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                    .padding(.horizontal)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { value in
                        handleScan(value)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showScanner = false }
                        }
                    }
                }
            }
            .sheet(item: $scannedPayload) { payload in
                NavigationStack {
                    Group {
                        if let serverURL = URL(string: payload.url) {
                            NameEntryView(
                                serverURL: serverURL,
                                inviteToken: payload.invite,
                                onComplete: {
                                    scannedPayload = nil
                                    // Clear pending invite
                                    UserDefaults.standard.removeObject(forKey: "pendingInviteURL")
                                    UserDefaults.standard.removeObject(forKey: "pendingInviteToken")
                                }
                            )
                            .environment(authRepository)
                            .environment(api)
                        } else {
                            Text("Invalid server URL")
                                .foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Setup")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .onAppear {
                // Auto-open name entry if we have a pending invite from URL
                if scannedPayload == nil, let pending = pendingInvite {
                    scannedPayload = pending
                }
            }
        }
    }

    private func handleScan(_ value: String) {
        showScanner = false
        guard let data = value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code"
            return
        }
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
            // Validate credentials before storing
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

            // Only store after validation succeeds
            authRepository.store(serverURL: url, token: trimmedToken)

            do {
                // Fetch and store user ID
                if let me = try? await api.getMe() {
                    authRepository.storeUserID(me.id)
                }

                let center = UNUserNotificationCenter.current()
                let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted == true {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }

                if let deviceToken = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "apnsDeviceToken") {
                    authRepository.storeDeviceToken(deviceToken)
                    try? await api.registerDevice(apnsToken: deviceToken)
                }
            } catch {
                authRepository.clear()
                self.error = error.localizedDescription
            }

            isConnecting = false
        }
    }
}
