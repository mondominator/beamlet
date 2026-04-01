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

struct InboxView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: InboxViewModel?
    @State private var selectedFilter: InboxFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
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
                                            FileRowView(
                                                file: file,
                                                thumbnailURL: vm.thumbnailURL(for: file.id),
                                                authHeaders: vm.authHeaders
                                            )
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
            .navigationDestination(for: BeamletFile.self) { file in
                FileDetailView(file: file)
            }
            .refreshable {
                await viewModel?.loadFiles()
            }
            .task {
                if viewModel == nil {
                    viewModel = InboxViewModel(api: api)
                }
                await viewModel?.loadFiles()
            }
        }
    }
}
