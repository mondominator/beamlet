import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // Set up the directory URLs that the Finder Sync extension monitors
        if let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            FIFinderSyncController.default().directoryURLs = [home]
        }
    }

    // MARK: - Menu and Toolbar Item

    override var toolbarItemName: String {
        return "Beamlet"
    }

    override var toolbarItemToolTip: String {
        return "Send with Beamlet"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Beamlet")!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Beamlet")
        let sendItem = NSMenuItem(title: "Send with Beamlet", action: #selector(sendWithBeamlet(_:)), keyEquivalent: "")
        sendItem.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)
        menu.addItem(sendItem)
        return menu
    }

    @objc func sendWithBeamlet(_ sender: Any?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
            return
        }

        // Open the main app with the selected files
        let urls = items.map { $0.absoluteString }
        let encodedURLs = urls.joined(separator: ",")

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.beamlet.mac") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--send", encodedURLs]
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }
}
