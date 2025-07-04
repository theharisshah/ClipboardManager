import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var clipboardManager = ClipboardManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(clipboardManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    private var hotkeyManager: HotkeyManager?
    private var clipboardManager: ClipboardManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon and main window initially
        NSApp.setActivationPolicy(.accessory)
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Setup the popover for the main interface
        setupPopover()
        
        // Setup global hotkey
        setupHotkey()
        
        // Setup menu
        setupMenu()
        
        // Close the default main window
        NSApp.windows.forEach { window in
            if window.title.isEmpty {
                window.close()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager = nil
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 450, height: 550)
        popover?.behavior = .transient
        popover?.delegate = self
        
        // Create the clipboard manager instance
        clipboardManager = ClipboardManager()
        
        // Create the content view
        let contentView = ContentView()
            .environmentObject(clipboardManager!)
        
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }
    
    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePopover()
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Open Clipboard Manager", action: #selector(showPopover), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear All History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func togglePopover() {
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                showPopover()
            }
        }
    }
    
    @objc private func showPopover() {
        if let button = statusItem?.button, let popover = popover {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc private func clearHistory() {
        clipboardManager?.clearHistory()
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Clipboard Manager"
        alert.informativeText = "A powerful clipboard history manager for macOS.\n\nPress ⌘+Shift+V to show/hide anywhere.\nClick the menu bar icon to access.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        // Optionally perform actions when popover is about to show
    }
    
    func popoverDidClose(_ notification: Notification) {
        // Optionally perform actions when popover closes
    }
}
