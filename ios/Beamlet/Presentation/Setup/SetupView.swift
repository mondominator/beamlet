import SwiftUI

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?

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

                        Text("Enter your server details to get started")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.headline)
                            TextField("https://beamlet.example.com", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
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

                    // Connect button
                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func connect() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        Task {
            // Temporarily store credentials to test the connection
            authRepository.store(serverURL: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))

            do {
                // Verify by fetching user list
                let _ = try await api.listUsers()

                // Register for push notifications
                let center = UNUserNotificationCenter.current()
                let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted == true {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }

                // Register device token if we already have one
                if let deviceToken = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "apnsDeviceToken") {
                    authRepository.storeDeviceToken(deviceToken)
                    try? await api.registerDevice(apnsToken: deviceToken)
                }
            } catch {
                // Connection failed — clear credentials
                authRepository.clear()
                self.error = error.localizedDescription
            }

            isConnecting = false
        }
    }
}
