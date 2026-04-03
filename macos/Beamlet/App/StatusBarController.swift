import AppKit
import SwiftUI

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var eventMonitor: Any?

    private let authRepository: AuthRepository
    private let api: BeamletAPI
    private var nearbyService: NearbyService?

    private var badgeCount: Int = 0 {
        didSet { updateIcon() }
    }

    init(authRepository: AuthRepository, api: BeamletAPI, nearbyService: NearbyService?) {
        self.authRepository = authRepository
        self.api = api
        self.nearbyService = nearbyService

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
    }

    func updateNearbyService(_ service: NearbyService) {
        self.nearbyService = service
        setupPopover()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Beamlet")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.action = #selector(togglePopover(_:))
        button.target = self

        // Register the button as a drag destination
        button.window?.registerForDraggedTypes([.fileURL, .string, .URL])
        let draggingView = StatusBarDraggingView(frame: button.bounds, controller: self)
        draggingView.autoresizingMask = [.width, .height]
        button.addSubview(draggingView)
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.animates = true

        // Use the existing PopoverContentView, injecting dependencies via environment.
        // Always provide a NearbyService (placeholder if not yet authenticated)
        // so child views can safely read the environment object.
        let service = nearbyService ?? NearbyService(userID: "", api: api)
        let contentView = PopoverContentView()
            .environment(authRepository)
            .environment(api)
            .environment(service)
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupEventMonitor() {
        // Close the popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Badge

    func updateBadgeCount(_ count: Int) {
        badgeCount = count
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        if badgeCount > 0 {
            let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Beamlet")
            image?.isTemplate = true
            button.image = image

            // Show the count as a title next to the icon
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.controlAccentColor
            ]
            button.attributedTitle = NSAttributedString(
                string: " \(badgeCount > 99 ? "99+" : "\(badgeCount)")",
                attributes: attributes
            )
        } else {
            let image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Beamlet")
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    // MARK: - Drag & Drop

    func handleDrop(urls: [URL]) {
        guard authRepository.isAuthenticated else {
            showPopover()
            return
        }

        // Show popover and let the UI handle the file upload flow
        showPopover()

        // Post a notification that files were dropped so the UI can pick them up
        NotificationCenter.default.post(
            name: .beamletFilesDropped,
            object: nil,
            userInfo: ["urls": urls]
        )
    }

    func handleDrop(string: String) {
        guard authRepository.isAuthenticated else {
            showPopover()
            return
        }

        showPopover()

        NotificationCenter.default.post(
            name: .beamletTextDropped,
            object: nil,
            userInfo: ["text": string]
        )
    }

    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let beamletFilesDropped = Notification.Name("beamletFilesDropped")
    static let beamletTextDropped = Notification.Name("beamletTextDropped")
}

// MARK: - Dragging View (overlay on status bar button)

class StatusBarDraggingView: NSView {
    private weak var controller: StatusBarController?

    init(frame: NSRect, controller: StatusBarController) {
        self.controller = controller
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string, .URL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Handle file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            controller?.handleDrop(urls: urls)
            return true
        }

        // Handle strings / text
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let text = strings.first, !text.isEmpty {
            controller?.handleDrop(string: text)
            return true
        }

        // Handle web URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            controller?.handleDrop(string: url.absoluteString)
            return true
        }

        return false
    }
}
