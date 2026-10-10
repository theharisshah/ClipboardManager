import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The UI lives in the status item's popover (see AppDelegate). An empty Settings scene keeps SwiftUI
        // from opening a window at launch while keeping the standard Edit menu shortcuts for the search field.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let statusMenu = NSMenu()
    private var hotkeyManager: HotkeyManager?
    private let keyMonitor = PopoverKeyMonitor()

    /// The one ClipboardManager in the app.
    private(set) lazy var clipboardManager: ClipboardManager = {
        let legacyDefaults = ClipboardManager.legacyDefaults
        ClipboardManager.migrateLegacyHistory(from: legacyDefaults)
        return ClipboardManager(legacyDefaults: legacyDefaults)
    }()

    private lazy var popoverModel = PopoverModel(manager: clipboardManager)

    /// The app that was active before the popover opened; it gets focus back after a copy.
    private var previousApp: NSRunningApplication?
    private var closeReason: PopoverCloseReason?
    private var lastTransientClose = Date.distantPast
    private var aboutPanelObserver: NSObjectProtocol?

    private static let statusImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run as a bare executable without the Info.plist's LSUIElement.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupMenu()
        setupHotkey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager = nil
        clipboardManager.stopMonitoring()
    }

    // MARK: Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.statusImage
            button.toolTip = "Clipboard Manager (⇧⌘V)"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Don't assign statusItem.menu permanently: while it's set, clicks open the menu and the button
            // action never fires. Left click opens the popover, right or Control-click shows the menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func setupPopover() {
        popover.behavior = .transient
        // Appear and disappear instantly, like a launcher. It also keeps the delegate callbacks in step with
        // what's on screen; with the animation, didShow/didClose arrive about half a second late.
        popover.animates = false
        popover.contentSize = PopoverMetrics.size
        popover.delegate = self

        popoverModel.closePopover = { [weak self] reason in
            self?.closePopover(reason)
        }

        let contentView = ContentView()
            .environmentObject(clipboardManager)
            .environmentObject(popoverModel)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupMenu() {
        let open = NSMenuItem(title: "Open Clipboard History", action: #selector(openFromMenu), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.target = self
        statusMenu.addItem(open)

        statusMenu.addItem(NSMenuItem.separator())

        let clear = NSMenuItem(title: "Clear All History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        statusMenu.addItem(clear)

        statusMenu.addItem(NSMenuItem.separator())

        let about = NSMenuItem(title: "About Clipboard Manager", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        statusMenu.addItem(about)

        let quit = NSMenuItem(title: "Quit Clipboard Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusMenu.addItem(quit)
    }

    private func setupHotkey() {
        let manager = HotkeyManager { [weak self] in
            self?.togglePopover()
        }
        popoverModel.isHotkeyAvailable = manager.isRegistered
        if !manager.isRegistered {
            clipboardManager.lastError = "The ⇧⌘V shortcut is in use by another app. Click the menu bar icon to open Clipboard Manager."
        }
        hotkeyManager = manager
    }

    // MARK: Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            closePopover(.dismissed)
            statusItem?.menu = statusMenu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else if popover.isShown {
            closePopover(.dismissed)
        } else if Date().timeIntervalSince(lastTransientClose) > 0.3 {
            // A transient popover closes on mouse-down outside it, so the mouse-up of that same click on the
            // icon must not reopen it.
            showPopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover(.dismissed)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }

        previousApp = Self.frontmostOtherApp()
        closeReason = nil

        popoverModel.prepareForShow()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Handle keys from the first moment, so a fast ⇧⌘V ↓ ↩ works.
        keyMonitor.start(window: { [weak self] in
            self?.popover.contentViewController?.view.window
        }, handler: { [weak self] command in
            self?.popoverModel.handle(command) ?? false
        })
        popoverModel.didShow()
    }

    private func closePopover(_ reason: PopoverCloseReason) {
        guard popover.isShown else { return }
        closeReason = reason
        popover.performClose(nil)
        // Hand focus back right away so ⌘V pastes into the previous app immediately.
        restoreFocus(to: previousApp)
        if reason == .copied {
            flashCopiedIcon()
        }
    }

    /// The frontmost app, unless that's Clipboard Manager itself.
    private static func frontmostOtherApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
    }

    /// Gives focus back to the app the user was in, so ⌘V pastes there. Does nothing if the user has already
    /// moved on to another app or is using one of our windows (an alert or the About panel).
    private func restoreFocus(to app: NSRunningApplication?) {
        guard NSApp.isActive, NSApp.modalWindow == nil else { return }
        guard let app = app, !app.isTerminated else {
            NSApp.hide(nil)
            return
        }
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            app.activate()
            return
        }
        #endif
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func flashCopiedIcon() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.statusItem?.button?.image = Self.statusImage
        }
    }

    // MARK: Menu actions

    @objc private func openFromMenu() {
        showPopover()
    }

    @objc private func clearHistory() {
        let count = clipboardManager.clipboardItems.count
        guard count > 0 else { return }

        // Capture before closing: closing the popover starts handing focus back asynchronously.
        let returnTo = popover.isShown ? previousApp : Self.frontmostOtherApp()
        closePopover(.dismissed)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = count == 1
            ? "This permanently deletes 1 item."
            : "This permanently deletes all \(count) items."
        let clearButton = alert.addButton(withTitle: "Clear All")
        clearButton.hasDestructiveAction = true
        // Return must not trigger the destructive action. Cancel keeps Esc and ⌘-period.
        clearButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            clipboardManager.clearHistory()
        }
        restoreFocus(to: returnTo)
    }

    @objc private func showAbout() {
        // Capture before closing: closing the popover starts handing focus back asynchronously.
        let returnTo = popover.isShown ? previousApp : Self.frontmostOtherApp()
        closePopover(.dismissed)
        NSApp.activate(ignoringOtherApps: true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "A clipboard history manager for macOS.\nClick the menu bar icon or press ⇧⌘V to open it.\nRight-click the icon for more options.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clipboard Manager",
            .applicationVersion: version,
            .credits: credits,
        ])

        // When the panel closes, return to the app the user was in.
        if let observer = aboutPanelObserver {
            NotificationCenter.default.removeObserver(observer)
            aboutPanelObserver = nil
        }
        guard let panel = NSApp.keyWindow, panel !== popover.contentViewController?.view.window else { return }
        aboutPanelObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let observer = self.aboutPanelObserver {
                NotificationCenter.default.removeObserver(observer)
                self.aboutPanelObserver = nil
            }
            DispatchQueue.main.async {
                if NSApp.keyWindow == nil {
                    self.restoreFocus(to: returnTo)
                }
            }
        }
    }
}

// MARK: - NSMenuItemValidation
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(clearHistory) {
            return !clipboardManager.clipboardItems.isEmpty
        }
        return true
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        if closeReason == nil {
            // Closed by a click outside the popover (on mouse-down).
            lastTransientClose = Date()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        keyMonitor.stop()
        popoverModel.didClose()

        if closeReason == nil {
            // A click into another app already gave that app focus. A click that activated nothing else, such as
            // one on our own menu bar icon, leaves this windowless app active, so hand focus back then.
            let returnTo = previousApp
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.popover.isShown, NSApp.keyWindow == nil else { return }
                self.restoreFocus(to: returnTo)
            }
        }
        previousApp = nil
        closeReason = nil
    }
}
