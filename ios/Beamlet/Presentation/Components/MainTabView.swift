import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }

            SendView()
                .tabItem {
                    Label("Send", systemImage: "paperplane.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
