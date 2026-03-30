import SwiftUI

struct SettingsView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    if let url = authRepository.serverURL {
                        LabeledContent("URL", value: url.absoluteString)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                        }
                    }
                }

                Section("Notifications") {
                    LabeledContent("Push") {
                        if authRepository.deviceToken != nil {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Enabled")
                            }
                        } else {
                            Text("Not registered")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Disconnect?", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    authRepository.clear()
                }
            } message: {
                Text("You'll need to re-enter your server details to reconnect.")
            }
        }
    }
}
