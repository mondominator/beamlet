import SwiftUI
import UserNotifications
import QuickLook

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
    @State private var replyFile: BeamletFile?
    @State private var refreshTimer: Timer?
    @State private var fullScreenImage: FullScreenImage?
    @State private var quickLookURL: URL?

    struct FullScreenImage: Identifiable {
        let id = UUID()
        let image: UIImage
        let file: BeamletFile
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedTab == .sent {
                    sentFilesView
                } else if let vm = viewModel {
                    if vm.isLoading && vm.files.isEmpty {
                        LoadingView(message: "Loading inbox...")
                    } else if let error = vm.error, vm.files.isEmpty {
                        ErrorView(message: error) { Task { await vm.loadFiles() } }
                    } else if vm.files.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "No Files",
                            message: "Files sent to you will appear here"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(vm.files) { file in
                                    InboxItemView(
                                        file: file,
                                        thumbnailURL: vm.thumbnailURL(for: file.id),
                                        authHeaders: vm.authHeaders,
                                        onTap: { handleTap(file: file, vm: vm) },
                                        onSavePhoto: { image in saveToPhotos(image) },
                                        onReply: { replyFile = file },
                                        onPin: {
                                            Task {
                                                let _ = try? await api.togglePin(file.id)
                                                await vm.loadFiles()
                                            }
                                        },
                                        onDelete: {
                                            if let idx = vm.files.firstIndex(of: file) {
                                                vm.deleteFiles(at: IndexSet(integer: idx))
                                            }
                                        },
                                        onShare: { data in shareFile(data: data, filename: file.filename) }
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } else {
                    LoadingView()
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $selectedTab) {
                        ForEach(InboxTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .refreshable {
                if selectedTab == .received {
                    await viewModel?.loadFiles()
                } else {
                    await loadSentFiles()
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = InboxViewModel(api: api)
                }
                await viewModel?.loadFiles()
            }
            .onAppear {
                UNUserNotificationCenter.current().setBadgeCount(0)
                refreshTimer?.invalidate()
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                    Task {
                        await viewModel?.loadFiles()
                        await loadSentFiles()
                    }
                }
            }
            .onDisappear {
                refreshTimer?.invalidate()
                refreshTimer = nil
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .sent && sentFiles.isEmpty {
                    Task { await loadSentFiles() }
                }
            }
            .sheet(item: $replyFile) { file in
                QuickReplySheet(
                    recipientID: file.senderID,
                    recipientName: file.senderName ?? "Unknown",
                    replyToMessage: file.isText ? file.textContent : file.message
                )
            }
            .fullScreenCover(item: $fullScreenImage) { item in
                ImageViewerView(image: item.image, file: item.file) {
                    fullScreenImage = nil
                }
            }
            .quickLookPreview($quickLookURL)
        }
    }

    private func handleTap(file: BeamletFile, vm: InboxViewModel) {
        // Mark as read
        Task { try? await api.markRead(file.id) }

        if file.isImage {
            // Download full image and show full-screen
            Task {
                if let data = try? await api.downloadFile(file.id),
                   let image = UIImage(data: data) {
                    fullScreenImage = FullScreenImage(image: image, file: file)
                }
            }
        } else if file.isLink, let text = file.textContent, let url = URL(string: text) {
            UIApplication.shared.open(url)
        } else if file.isText {
            // Text is shown inline, copy on tap
            if let text = file.textContent {
                UIPasteboard.general.string = text
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            // Generic file — download and Quick Look
            Task {
                if let data = try? await api.downloadFile(file.id) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
                    try? data.write(to: tempURL)
                    quickLookURL = tempURL
                }
            }
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func shareFile(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(ac, animated: true)
        }
    }

    // MARK: - Sent Tab

    @ViewBuilder
    private var sentFilesView: some View {
        if isLoadingSent && sentFiles.isEmpty {
            LoadingView(message: "Loading sent files...")
        } else if sentFiles.isEmpty {
            EmptyStateView(
                icon: "paperplane",
                title: "No Sent Files",
                message: "Files you send will appear here"
            )
        } else {
            List {
                ForEach(sentFiles) { file in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.12))
                            Image(systemName: file.isImage ? "photo.fill" : file.isVideo ? "video.fill" : file.isText ? "text.bubble.fill" : "doc.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("To: \(file.senderName ?? "Unknown")")
                                    .font(.headline)
                                Spacer()
                                if file.read {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                        Text("Read")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.green)
                                } else {
                                    HStack(spacing: 3) {
                                        Image(systemName: "circle")
                                            .font(.caption2)
                                        Text("Delivered")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }

                            if let date = file.createdAt {
                                Text(date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadSentFiles() async {
        isLoadingSent = true
        sentFiles = (try? await api.listSentFiles()) ?? []
        isLoadingSent = false
    }
}
