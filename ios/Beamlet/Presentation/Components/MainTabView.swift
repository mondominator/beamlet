import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab = 1  // Default to Send tab
    @State private var pendingFileID: String?

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List {
                        Button { selectedTab = 1 } label: {
                            Label("Send", systemImage: "paperplane.fill")
                                .foregroundStyle(selectedTab == 1 ? .blue : .primary)
                        }
                        Button { selectedTab = 0 } label: {
                            Label("Inbox", systemImage: "tray.fill")
                                .foregroundStyle(selectedTab == 0 ? .blue : .primary)
                        }
                        Button { selectedTab = 2 } label: {
                            Label("Settings", systemImage: "gearshape.fill")
                                .foregroundStyle(selectedTab == 2 ? .blue : .primary)
                        }
                    }
                    .navigationTitle("Beamlet")
                } detail: {
                    switch selectedTab {
                    case 0: InboxView(openFileID: $pendingFileID)
                    case 1: SendView()
                    case 2: SettingsView()
                    default: SendView()
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    InboxView(openFileID: $pendingFileID)
                        .tabItem {
                            Label("Inbox", systemImage: "tray.fill")
                        }
                        .tag(0)

                    SendView()
                        .tabItem {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                        .tag(1)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .tag(2)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapNotification)) { notification in
            guard let fileID = notification.object as? String else { return }
            pendingFileID = fileID
            selectedTab = 0 // Switch to inbox
        }
    }
}
