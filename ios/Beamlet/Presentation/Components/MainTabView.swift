import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1  // Default to Send tab

    var body: some View {
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
