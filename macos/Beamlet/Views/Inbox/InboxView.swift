import SwiftUI
import Quartz

enum InboxTab: String, CaseIterable {
    case received = "Received"
    case sent = "Sent"
}

struct InboxView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: InboxViewModel?
    @State private var selectedTab: InboxTab = .received
    @State private var sentFiles: [BeamletFile] = []
    @State private var isLoadingSent = false
    @State private var quickLookURL: URL?
    @State private var showQuickLook = false
    @State private var selectedFileID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("", selection: $selectedTab) {
                ForEach(InboxTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            Group {
                if selectedTab == .sent {
                    sentFilesView
                } else if let vm = viewModel {
                    receivedFilesView(vm: vm)
                } else {
                    loadingView("Loading inbox...")
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = InboxViewModel(api: api)
            }
            await viewModel?.loadFiles()
        }
        .onAppear {
            viewModel?.startPolling()
        }
        .onDisappear {
            viewModel?.stopPolling()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .sent && sentFiles.isEmpty {
                Task { await loadSentFiles() }
            }
        }
        .sheet(isPresented: $showQuickLook) {
            if let url = quickLookURL {
                QuickLookPreview(url: url)
                    .frame(width: 500, height: 400)
            }
        }
    }

    // MARK: - Received

    @ViewBuilder
    private func receivedFilesView(vm: InboxViewModel) -> some View {
        if vm.isLoading && vm.files.isEmpty {
            loadingView("Loading inbox...")
        } else if let error = vm.error, vm.files.isEmpty {
            errorView(error) { Task { await vm.loadFiles() } }
        } else if vm.files.isEmpty {
            emptyStateView(icon: "tray", title: "No Files", message: "Files sent to you will appear here")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.files) { file in
                        InboxItemRow(
                            file: file,
                            thumbnailURL: vm.thumbnailURL(for: file.id),
                            authHeaders: vm.authHeaders,
                            onTap: {
                                selectedFileID = file.id
                                handleTap(file: file, vm: vm)
                            },
                            onPin: { Task { await vm.togglePin(file.id) } },
                            onDelete: { vm.deleteFile(file) }
                        )
                        .background(selectedFileID == file.id ? Color.accentColor.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            // Feature 5: Quick Look on spacebar
            .onKeyPress(.space) {
                if let selectedID = selectedFileID,
                   let file = vm.files.first(where: { $0.id == selectedID }) {
                    quickLookFile(file)
                    return .handled
                }
                return .ignored
            }
        }
    }

    // MARK: - Sent

    @ViewBuilder
    private var sentFilesView: some View {
        if isLoadingSent && sentFiles.isEmpty {
            loadingView("Loading sent files...")
        } else if sentFiles.isEmpty {
            emptyStateView(icon: "paperplane", title: "No Sent Files", message: "Files you send will appear here")
        } else {
            List {
                ForEach(sentFiles) { file in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.12))
                            Image(systemName: file.isImage ? "photo.fill" : file.isVideo ? "video.fill" : file.isText ? "text.bubble.fill" : "doc.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("To: \(file.recipientName ?? file.senderName ?? "Unknown")")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                if file.read {
                                    HStack(spacing: 2) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 9))
                                        Text("Read")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundStyle(.green)
                                } else {
                                    HStack(spacing: 2) {
                                        Image(systemName: "circle")
                                            .font(.system(size: 9))
                                        Text("Delivered")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }

                            if let date = file.createdAt {
                                Text(date, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Tap Handler

    private func handleTap(file: BeamletFile, vm: InboxViewModel) {
        vm.markRead(file.id)

        if file.isImage {
            Task {
                if let data = try? await api.downloadFile(file.id) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
                    try? data.write(to: tempURL)
                    quickLookURL = tempURL
                    showQuickLook = true
                }
            }
        } else if file.isLink, let text = file.textContent, let url = URL(string: text) {
            NSWorkspace.shared.open(url)
        } else if file.isText {
            if let text = file.textContent {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        } else {
            Task {
                if let data = try? await api.downloadFile(file.id) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
                    try? data.write(to: tempURL)
                    quickLookURL = tempURL
                    showQuickLook = true
                }
            }
        }
    }

    // MARK: - Quick Look (spacebar)

    private func quickLookFile(_ file: BeamletFile) {
        if file.isText || file.isLink { return }
        // Check if already saved in ~/Downloads/Beamlet/
        let downloadDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Beamlet")
            .appendingPathComponent(file.filename)
        if FileManager.default.fileExists(atPath: downloadDir.path) {
            quickLookURL = downloadDir
            showQuickLook = true
            return
        }
        // Otherwise download to temp
        Task {
            if let data = try? await api.downloadFile(file.id) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
                try? data.write(to: tempURL)
                quickLookURL = tempURL
                showQuickLook = true
            }
        }
    }

    // MARK: - Sent Loading

    private func loadSentFiles() async {
        isLoadingSent = true
        sentFiles = (try? await api.listSentFiles()) ?? []
        isLoadingSent = false
    }

    // MARK: - Shared Views

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Quick Look Preview (macOS)

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        if let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.previewItem = url as QLPreviewItem
            return preview
        }
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let preview = nsView as? QLPreviewView {
            preview.previewItem = url as QLPreviewItem
        }
    }
}
