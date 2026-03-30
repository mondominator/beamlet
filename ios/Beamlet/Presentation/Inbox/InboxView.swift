import SwiftUI

struct InboxView: View {
    @Environment(BeamletAPI.self) private var api
    @State private var viewModel: InboxViewModel?

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
                        List {
                            ForEach(vm.files) { file in
                                NavigationLink(value: file) {
                                    FileRowView(
                                        file: file,
                                        thumbnailURL: vm.thumbnailURL(for: file.id),
                                        authHeaders: vm.authHeaders
                                    )
                                }
                            }
                            .onDelete(perform: vm.deleteFiles)
                        }
                        .listStyle(.plain)
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
