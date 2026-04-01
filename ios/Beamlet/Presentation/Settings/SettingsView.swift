import SwiftUI

struct SettingsView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api
    @Environment(NearbyService.self) private var nearbyService: NearbyService?

    @State private var showLogoutConfirmation = false
    @State private var discoverability: DiscoverabilityMode = .load()
    @State private var filesSent: Int?
    @State private var filesReceived: Int?
    @State private var storageUsed: Int64?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Discoverability", selection: $discoverability) {
                        ForEach(DiscoverabilityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: discoverability) {
                        nearbyService?.mode = discoverability
                    }
                } header: {
                    Text("Discoverability")
                } footer: {
                    Text(discoverability.description)
                }

                Section("Contacts") {
                    NavigationLink {
                        AddContactView()
                    } label: {
                        Label("Add Contact", systemImage: "person.badge.plus")
                    }

                    NavigationLink {
                        ScanInviteView()
                    } label: {
                        Label("Scan Invite", systemImage: "qrcode.viewfinder")
                    }
                }

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

                Section("Usage") {
                    LabeledContent("Files Sent", value: filesSent.map { "\($0)" } ?? "—")
                    LabeledContent("Files Received", value: filesReceived.map { "\($0)" } ?? "—")
                    LabeledContent("Storage Used", value: storageUsed.map { formatBytes($0) } ?? "—")
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
            .task {
                if let me = try? await api.getMe() {
                    filesSent = me.filesSent
                    filesReceived = me.filesReceived
                    storageUsed = me.storageUsed
                }
            }
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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
