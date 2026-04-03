import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case send = "Send"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inbox: return "tray.fill"
        case .send: return "paperplane.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct PopoverContentView: View {
    @Environment(AuthRepository.self) private var authRepository
    @State private var selectedTab: PopoverTab = .inbox

    var body: some View {
        Group {
            if authRepository.isAuthenticated {
                authenticatedView
            } else {
                SetupView()
            }
        }
        .frame(width: 400, height: 600)
    }

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(Array(PopoverTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.rawValue)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color.blue.opacity(0.08)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Feature 8: Cmd+1/2/3 to switch tabs
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .inbox:
                    InboxView()
                case .send:
                    SendView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Feature 8: Cmd+N to jump to Send, Cmd+, for Settings, Escape to close popover
        .onKeyPress(keys: [.escape]) { _ in
            NSApp.keyWindow?.close()
            return .handled
        }
        .background {
            // Hidden buttons for additional keyboard shortcuts
            Group {
                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = .send
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()

                Button("") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = .settings
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
            }
            .frame(width: 0, height: 0)
        }
    }
}
