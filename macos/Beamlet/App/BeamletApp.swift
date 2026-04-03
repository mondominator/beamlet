import SwiftUI

@main
struct BeamletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // No settings window, everything in popover
        }
    }
}
