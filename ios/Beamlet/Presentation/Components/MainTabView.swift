import SwiftUI

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab = 1  // Default to Send tab

    var body: some View {
        if sizeClass == .regular {
            // iPad: use sidebar navigation
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
                case 0: InboxView()
                case 1: SendView()
                case 2: SettingsView()
                default: SendView()
                }
            }
        } else {
            // iPhone: use tab bar
            TabView(selection: $selectedTab) {
                InboxView()
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
}
