import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api
    @Environment(NearbyService.self) private var nearbyService

    @State private var showLogoutConfirmation = false
    @State private var filesSent: Int?
    @State private var filesReceived: Int?
    @State private var storageUsed: Int64?
    @State private var launchAtLogin = false
    @AppStorage("fileExpiryDays") private var fileExpiryDays: Int = 7
    @AppStorage("inboxCleanupDays") private var inboxCleanupDays: Int = 1

    var body: some View {
        @Bindable var nearby = nearbyService
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Discoverability
                sectionHeader("Discoverability")
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Nearby Visibility", selection: $nearby.mode) {
                        ForEach(DiscoverabilityMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 11))
                    .onChange(of: nearbyService.mode) {
                        Task { try? await api.updateDiscoverability(nearbyService.mode.rawValue) }
                    }

                    Text(nearbyService.mode.description)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Server
                sectionHeader("Server")
                VStack(alignment: .leading, spacing: 6) {
                    if let url = authRepository.serverURL {
                        labeledRow("URL", value: url.absoluteString)
                    }
                    labeledRow("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Notifications
                sectionHeader("Notifications")
                VStack(alignment: .leading, spacing: 6) {
                    labeledRow("Push") {
                        if authRepository.deviceToken != nil {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                                Text("Enabled")
                                    .font(.system(size: 11))
                            }
                        } else {
                            Text("Not registered")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Usage
                sectionHeader("Usage")
                VStack(alignment: .leading, spacing: 6) {
                    labeledRow("Files Sent", value: filesSent.map { "\($0)" } ?? "--")
                    labeledRow("Files Received", value: filesReceived.map { "\($0)" } ?? "--")
                    labeledRow("Storage Used", value: storageUsed.map { formatBytes($0) } ?? "--")
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Storage settings
                sectionHeader("Storage")
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Sent File Expiry", selection: $fileExpiryDays) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .font(.system(size: 11))

                    Picker("Inbox Cleanup", selection: $inboxCleanupDays) {
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("Never").tag(0)
                    }
                    .font(.system(size: 11))

                    Text("Sent File Expiry: how long files you send stay on the server.\nInbox Cleanup: auto-delete received files older than this. Pinned files are kept.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Launch at login
                sectionHeader("General")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // About
                sectionHeader("About")
                VStack(alignment: .leading, spacing: 6) {
                    labeledRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    labeledRow("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Disconnect
                Button("Disconnect", role: .destructive) {
                    showLogoutConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .task {
            if let me = try? await api.getMe() {
                filesSent = me.filesSent
                filesReceived = me.filesReceived
                storageUsed = me.storageUsed
            }
            loadLaunchAtLoginState()
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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
    }

    // MARK: - Launch at Login

    private func loadLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert toggle on failure
                launchAtLogin = !enabled
            }
        }
    }
}
