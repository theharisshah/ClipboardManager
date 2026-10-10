import AppKit
import Carbon.HIToolbox
import SwiftUI

enum PopoverMetrics {
    static let size = CGSize(width: 420, height: 520)
    static let gutter: CGFloat = 12
    static let listInset: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 6
    static let rowCornerRadius: CGFloat = 6
    static let badgeSize: CGFloat = 22
    static let accessoryWidth: CGFloat = 26
    static let footerHeight: CGFloat = 32
}

/// Why the app closes the popover itself, as opposed to the user clicking somewhere else.
enum PopoverCloseReason {
    case copied
    case dismissed
}

/// UI state of the history popover, shared by the SwiftUI views and the key monitor in AppDelegate.
final class PopoverModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            // The top match becomes current again, matching the list scrolling back to the top. Rows reflowing
            // under a resting pointer must not take the highlight either.
            highlightedID = nil
            mouseLocationAtKeyboardNavigation = NSEvent.mouseLocation
        }
    }
    @Published var highlightedID: UUID?
    @Published var copiedID: UUID?
    @Published var isConfirmingClear = false
    /// Reference time for relative timestamps, so they are fresh every time the popover opens.
    @Published private(set) var openedAt = Date()
    @Published private(set) var focusRequest = 0
    @Published private(set) var scrollToTopRequest = 0
    /// Bumped when the keyboard moves the highlight, so the list scrolls to it (hovering never scrolls).
    @Published private(set) var keyboardScrollRequest = 0
    /// False when ⇧⌘V couldn't be registered.
    @Published var isHotkeyAvailable = true

    let manager: ClipboardManager

    /// Set by AppDelegate.
    var closePopover: (PopoverCloseReason) -> Void = { _ in }

    /// A copied item moves to the top only after the popover closes, so the list doesn't jump under the pointer.
    private var pendingMoveToTop: ClipboardItem?
    /// Mouse position at the last keyboard navigation. Rows scrolling under a resting pointer must not steal
    /// the highlight, so hover is ignored until the mouse actually moves.
    private var mouseLocationAtKeyboardNavigation: NSPoint?

    init(manager: ClipboardManager) {
        self.manager = manager
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var visibleItems: [ClipboardItem] {
        manager.searchItems(query: query)
    }

    /// The highlighted item, falling back to the first visible item.
    func currentID(in items: [ClipboardItem]) -> UUID? {
        if let id = highlightedID, items.contains(where: { $0.id == id }) {
            return id
        }
        return items.first?.id
    }

    // MARK: Popover lifecycle

    func prepareForShow() {
        query = ""
        highlightedID = nil
        copiedID = nil
        isConfirmingClear = false
        mouseLocationAtKeyboardNavigation = nil
        openedAt = Date()
        scrollToTopRequest &+= 1
        manager.refreshPasteboardAccess()
    }

    func didShow() {
        focusRequest &+= 1
    }

    func didClose() {
        if let item = pendingMoveToTop {
            pendingMoveToTop = nil
            if manager.clipboardItems.contains(where: { $0.id == item.id }) {
                manager.moveToTop(item)
            } else {
                // A copy made elsewhere just before pushed it out of a full history; it's on the clipboard now.
                manager.record(item.content)
            }
        }
        copiedID = nil
        isConfirmingClear = false
    }

    // MARK: Actions

    func copy(_ item: ClipboardItem) {
        // Ignore repeated clicks or Returns while the popover is closing.
        guard copiedID == nil else { return }
        guard manager.copyToClipboard(item: item, movesToTop: false) else { return }

        pendingMoveToTop = item
        highlightedID = item.id
        copiedID = item.id
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: "Copied",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])

        // Show the checkmark briefly, then close and hand focus back so ⌘V pastes right away.
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.05 : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.closePopover(.copied)
        }
    }

    func delete(_ item: ClipboardItem) {
        let items = visibleItems
        if currentID(in: items) == item.id, let index = items.firstIndex(where: { $0.id == item.id }) {
            // Keep a highlight in place: the next row, or the previous one at the end of the list.
            let neighbor = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            highlightedID = neighbor?.id
            keyboardScrollRequest &+= 1
        }
        manager.removeItem(item)
        if manager.clipboardItems.isEmpty {
            isConfirmingClear = false
        }
    }

    func clearHistory() {
        isConfirmingClear = false
        highlightedID = nil
        manager.clearHistory()
    }

    func hover(_ item: ClipboardItem) {
        if let location = mouseLocationAtKeyboardNavigation {
            guard NSEvent.mouseLocation != location else { return }
            mouseLocationAtKeyboardNavigation = nil
        }
        if highlightedID != item.id {
            highlightedID = item.id
        }
    }

    /// Esc: dismiss the clear confirmation, then clear the search, then close.
    func cancel() {
        if isConfirmingClear {
            isConfirmingClear = false
        } else if !query.isEmpty {
            query = ""
        } else {
            closePopover(.dismissed)
        }
    }

    /// Handles a key from the popover's key monitor. Returns false to let the search field handle the key.
    @discardableResult
    func handle(_ command: KeyCommand) -> Bool {
        if isConfirmingClear {
            if command == .escape {
                isConfirmingClear = false
            }
            // Swallow everything else so Return can't trigger anything while the confirmation is up.
            return true
        }

        let items = visibleItems
        switch command {
        case .moveUp:
            move(by: -1, in: items)
        case .moveDown:
            move(by: 1, in: items)
        case .pageUp:
            move(by: -8, in: items)
        case .pageDown:
            move(by: 8, in: items)
        case .first:
            move(by: -items.count, in: items)
        case .last:
            move(by: items.count, in: items)
        case .activate:
            if let id = currentID(in: items), let item = items.first(where: { $0.id == id }) {
                copy(item)
            }
        case .quickPick(let index):
            if items.indices.contains(index) {
                copy(items[index])
            }
        case .delete:
            // With a search query, ⌘⌫ keeps its text-editing meaning.
            guard trimmedQuery.isEmpty else { return false }
            if let id = currentID(in: items), let item = items.first(where: { $0.id == id }) {
                delete(item)
            }
        case .escape:
            cancel()
        }
        return true
    }

    private func move(by delta: Int, in items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == currentID(in: items) }) ?? 0
        let target = min(max(current + delta, 0), items.count - 1)
        let item = items[target]
        highlightedID = item.id
        keyboardScrollRequest &+= 1
        mouseLocationAtKeyboardNavigation = NSEvent.mouseLocation

        // Focus stays in the search field, so VoiceOver wouldn't otherwise say which item is highlighted.
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
                .announcement: "\(item.contentType.displayName): \(item.previewLines.joined(separator: " ").prefix(140))",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
    }
}

// MARK: - Keyboard

/// Keys the popover handles itself. Everything else goes to the focused search field.
enum KeyCommand: Equatable {
    case moveUp, moveDown, pageUp, pageDown, first, last
    /// Return / Enter: copy the highlighted item and close.
    case activate
    /// ⌘1 … ⌘9: copy the visible item at this index and close.
    case quickPick(Int)
    /// ⌘⌫ / ⌘⌦: delete the highlighted item.
    case delete
    /// Esc: dismiss the confirmation, clear the search, or close.
    case escape

    /// Virtual key codes keep ⌘1…⌘9 working on non-US layouts.
    private static let digitKeyCodes: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                               kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        // Arrow keys also carry .function and .numericPad; compare only the real modifiers.
        let modifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(keyCode), modifiers) {
        case (kVK_UpArrow, []), (kVK_ANSI_P, [.control]):
            self = .moveUp
        case (kVK_DownArrow, []), (kVK_ANSI_N, [.control]):
            self = .moveDown
        case (kVK_PageUp, []):
            self = .pageUp
        case (kVK_PageDown, []):
            self = .pageDown
        case (kVK_UpArrow, [.command]), (kVK_Home, []):
            self = .first
        case (kVK_DownArrow, [.command]), (kVK_End, []):
            self = .last
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []):
            self = .activate
        case (kVK_Delete, [.command]), (kVK_ForwardDelete, [.command]):
            self = .delete
        case (kVK_Escape, []):
            self = .escape
        case (let code, [.command]):
            guard let index = Self.digitKeyCodes.firstIndex(of: code) else { return nil }
            self = .quickPick(index)
        default:
            return nil
        }
    }
}

/// Routes keys to the popover while its search field has focus. `.onKeyPress` needs macOS 14, and the field
/// editor swallows arrows, Return and Esc before SwiftUI's move/exit commands see them.
final class PopoverKeyMonitor {
    private var token: Any?

    func start(window: @escaping () -> NSWindow?, handler: @escaping (KeyCommand) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only the popover's own window, never alerts or other windows.
            guard let popoverWindow = window(), event.window === popoverWindow else { return event }
            // Input methods (e.g. Japanese or Chinese) use Return, arrows and Esc while composing.
            if let editor = popoverWindow.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            guard let command = KeyCommand(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else { return event }
            return handler(command) ? nil : event
        }
    }

    func stop() {
        if let token = token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }

    deinit {
        stop()
    }
}
