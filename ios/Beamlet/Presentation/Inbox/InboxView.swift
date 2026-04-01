import SwiftUI

enum InboxFilter: String, CaseIterable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    case messages = "Messages"
    case links = "Links"
    case files = "Files"

    func matches(_ file: BeamletFile) -> Bool {
        switch self {
        case .all: return true
        case .photos: return file.isImage
        case .videos: return file.isVideo
        case .messages: return file.isText
        case .links: return file.isLink
        case .files: return !file.isImage && !file.isVideo && !file.isText && !file.isLink
        }
    }
}

enum InboxTab: String, CaseIterable {
    case received = "Received"
    case sent = "Sent"
}

struct InboxView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: InboxViewModel?
    @State private var selectedFilter: InboxFilter = .all
    @State private var selectedTab: InboxTab = .received
    @State private var sentFiles: [BeamletFile] = []
    @State private var isLoadingSent = false
    @State private var replyFile: BeamletFile?
    @State private var refreshTimer: Timer?

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
                        let filtered = vm.files.filter { selectedFilter.matches($0) }

                        VStack(spacing: 0) {
                            // Filter chips
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(InboxFilter.allCases, id: \.self) { filter in
                                        let count = vm.files.filter { filter.matches($0) }.count
                                        if filter == .all || count > 0 {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    selectedFilter = filter
                                                }
                                            } label: {
                                                Text(filter == .all ? filter.rawValue : "\(filter.rawValue) (\(count))")
                                                    .font(.subheadline)
                                                    .fontWeight(selectedFilter == filter ? .semibold : .regular)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 7)
                                                    .background(selectedFilter == filter ? Color.blue : Color.gray.opacity(0.15))
                                                    .foregroundStyle(selectedFilter == filter ? .white : .primary)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }

                            if filtered.isEmpty {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text("No \(selectedFilter.rawValue.lowercased())")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            } else {
                                List {
                                    ForEach(filtered) { file in
                                        NavigationLink(value: file) {
                                            HStack {
                                                if file.pinned == true {
                                                    Image(systemName: "pin.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.orange)
                                                }
                                                FileRowView(
                                                    file: file,
                                                    thumbnailURL: vm.thumbnailURL(for: file.id),
                                                    authHeaders: vm.authHeaders
                                                )
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                Task {
                                                    let _ = try? await api.togglePin(file.id)
                                                    await vm.loadFiles()
                                                }
                                            } label: {
                                                Label(
                                                    file.pinned == true ? "Unpin" : "Pin",
                                                    systemImage: file.pinned == true ? "pin.slash" : "pin"
                                                )
                                            }
                                            .tint(.orange)

                                            Button {
                                                replyFile = file
                                            } label: {
                                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                    .onDelete { offsets in
                                        let filesToDelete = offsets.map { filtered[$0] }
                                        for file in filesToDelete {
                                            if let idx = vm.files.firstIndex(of: file) {
                                                vm.deleteFiles(at: IndexSet(integer: idx))
                                            }
                                        }
                                    }
                                }
                                .listStyle(.plain)
                            }
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
            .navigationDestination(for: BeamletFile.self) { file in
                FileDetailView(file: file)
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
                refreshTimer?.invalidate()
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                    Task { await viewModel?.loadFiles() }
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
        }
    }

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
                    NavigationLink(value: file) {
                        HStack(spacing: 14) {
                            // Type icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.12))
                                Image(systemName: file.isImage ? "photo.fill" : file.isVideo ? "video.fill" : file.isText ? "text.bubble.fill" : "doc.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 60, height: 60)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("To: \(file.senderName ?? "Unknown")")
                                        .font(.headline)
                                    Spacer()
                                    // Read receipt
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

                                Text(file.displayType)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

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
