import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @EnvironmentObject var model: PopoverModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Filter once per render; the list, footer and keyboard handling all use the same items.
        let items = model.visibleItems
        let currentID = model.currentID(in: items)

        VStack(spacing: 0) {
            SearchField(text: $model.query, placeholder: "Search", focusRequest: model.focusRequest)
                .padding(.horizontal, PopoverMetrics.gutter)
                .padding(.top, PopoverMetrics.gutter)
                .padding(.bottom, 10)

            notices

            Divider()

            if items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(items, currentID: currentID)
            }

            Divider()

            footer(items)
        }
        .frame(width: PopoverMetrics.size.width, height: PopoverMetrics.size.height)
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        if clipboardManager.isPasteboardAccessDenied {
            NoticeView(
                symbol: "hand.raised.fill",
                message: "Clipboard access is turned off. Allow Clipboard Manager in System Settings › Privacy & Security › Paste from Other Apps.",
                actionTitle: "Open Settings",
                action: openPrivacySettings
            )
        }
        if let error = clipboardManager.lastError {
            NoticeView(
                symbol: "exclamationmark.triangle.fill",
                message: error,
                actionTitle: "Dismiss",
                action: { clipboardManager.lastError = nil }
            )
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: List

    private func list(_ items: [ClipboardItem], currentID: UUID?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HistoryRow(
                            item: item,
                            shortcut: index < 9 ? index + 1 : nil,
                            isHighlighted: item.id == currentID,
                            isCopied: item.id == model.copiedID,
                            now: model.openedAt,
                            onCopy: { model.copy(item) },
                            onDelete: { delete(item) }
                        )
                        .id(item.id)
                        // Hover moves the highlight; leaving a row doesn't clear it.
                        .onHover { inside in
                            if inside {
                                model.hover(item)
                            }
                        }
                    }
                }
                .padding(PopoverMetrics.listInset)
                .id(Self.listTopID)
            }
            .onChange(of: model.keyboardScrollRequest) { _ in
                // No anchor: scroll only as far as needed to reveal the row. Hover never scrolls.
                if let id = model.highlightedID {
                    proxy.scrollTo(id)
                }
            }
            .onChange(of: model.scrollToTopRequest) { _ in
                scrollToTop(proxy)
            }
            .onChange(of: model.query) { _ in
                scrollToTop(proxy)
            }
        }
    }

    /// The padded stack, so scrolling to the top keeps the list's top inset visible.
    private static let listTopID = "list-top"

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.listTopID, anchor: .top)
    }

    private func delete(_ item: ClipboardItem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            model.delete(item)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        let isSearching = !model.trimmedQuery.isEmpty
        return VStack(spacing: 6) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            Text(isSearching ? "No Results for “\(model.trimmedQuery)”" : "No Clipboard History")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(isSearching
                 ? "Check the spelling or try a different search."
                 : model.isHotkeyAvailable
                 ? "Text you copy will appear here.\nPress ⇧⌘V to open this list from anywhere."
                 : "Text you copy will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private func footer(_ items: [ClipboardItem]) -> some View {
        Group {
            if model.isConfirmingClear {
                clearConfirmation
            } else {
                HStack(spacing: 8) {
                    if !clipboardManager.clipboardItems.isEmpty {
                        Text(countLabel(visibleCount: items.count))
                            .monospacedDigit()
                    }

                    Spacer()

                    if !items.isEmpty {
                        Text("↩ Copy")
                            .accessibilityHidden(true)
                    }

                    Menu {
                        Button("Clear History…") {
                            model.isConfirmingClear = true
                        }
                        .disabled(clipboardManager.clipboardItems.isEmpty)

                        Divider()

                        Button("Quit Clipboard Manager") {
                            NSApp.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                    .accessibilityLabel("More")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, PopoverMetrics.gutter)
        .frame(height: PopoverMetrics.footerHeight)
    }

    private var clearConfirmation: some View {
        HStack(spacing: 8) {
            Text(clipboardManager.clipboardItems.count == 1
                 ? "Clear 1 item?"
                 : "Clear all \(clipboardManager.clipboardItems.count) items?")
                .font(.subheadline.weight(.semibold))
            Text("This can’t be undone.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer(minLength: 4)

            Button("Cancel") {
                model.isConfirmingClear = false
            }
            .keyboardShortcut(.cancelAction)

            Button("Clear", role: .destructive) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    model.clearHistory()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .controlSize(.small)
    }

    private func countLabel(visibleCount: Int) -> String {
        let total = clipboardManager.clipboardItems.count
        if !model.trimmedQuery.isEmpty {
            return "\(visibleCount) of \(total)"
        }
        return total == 1 ? "1 item" : "\(total) items"
    }
}

// MARK: - Row

struct HistoryRow: View {
    let item: ClipboardItem
    let shortcut: Int?
    let isHighlighted: Bool
    let isCopied: Bool
    let now: Date
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var primaryColor: Color {
        isHighlighted ? Color(nsColor: .alternateSelectedControlTextColor) : .primary
    }

    private var secondaryColor: Color {
        isHighlighted ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.85) : .secondary
    }

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 10) {
                TypeBadge(type: item.contentType, isInverted: isHighlighted)

                VStack(alignment: .leading, spacing: 2) {
                    preview
                    meta
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Fixed room for the accessory, so the text never re-wraps when the row is highlighted.
            .padding(.trailing, PopoverMetrics.accessoryWidth + 6)
            .padding(.horizontal, PopoverMetrics.rowHorizontalPadding)
            .padding(.vertical, PopoverMetrics.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: PopoverMetrics.rowCornerRadius, style: .continuous)
                    .fill(isHighlighted ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        // The delete button sits beside the row button rather than inside it, so clicking it never copies.
        .overlay(alignment: .topTrailing) {
            accessory
                .frame(width: PopoverMetrics.accessoryWidth, height: PopoverMetrics.badgeSize, alignment: .trailing)
                .padding(.trailing, PopoverMetrics.rowHorizontalPadding)
                .padding(.top, PopoverMetrics.rowVerticalPadding)
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.contentType.displayName): \(String(item.previewLines.joined(separator: " ").prefix(140)))"))
        .accessibilityValue(Text(RelativeTime.short(item.timestamp, now: now)))
        .accessibilityHint(Text("Copies to the clipboard"))
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onCopy)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    @ViewBuilder
    private var preview: some View {
        let lines = item.previewLines
        if item.contentType.isMonospaced {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundColor(primaryColor)
        } else {
            Text(lines.first ?? "")
                .font(.body)
                .lineLimit(item.contentType == .text ? 2 : 1)
                .truncationMode(item.contentType == .url ? .middle : .tail)
                .foregroundColor(primaryColor)
        }
    }

    private var meta: some View {
        let prefix = [
            item.contentType == .text ? nil : item.contentType.displayName,
            item.detail,
        ].compactMap { $0 }.joined(separator: " · ")

        // A long host truncates in the middle; the time always stays visible.
        return HStack(spacing: 0) {
            if !prefix.isEmpty {
                Text(prefix + " · ")
                    .truncationMode(.middle)
            }
            Text(RelativeTime.short(item.timestamp, now: now))
                .fixedSize()
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundColor(secondaryColor)
        .help(RelativeTime.full(item.timestamp))
    }

    @ViewBuilder
    private var accessory: some View {
        if isCopied {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(primaryColor)
                .allowsHitTesting(false)
        } else if isHighlighted {
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(primaryColor.opacity(0.22)))
                    // Fill the whole accessory slot so the click target matches the drawn button and a near miss
                    // doesn't copy the row instead.
                    .frame(width: PopoverMetrics.accessoryWidth, height: PopoverMetrics.badgeSize, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(primaryColor)
            .help("Delete from History")
        } else if let shortcut = shortcut {
            Text("⌘\(shortcut)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .allowsHitTesting(false)
        }
    }
}

/// Plain row button with subtle press feedback instead of the default bezel.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct TypeBadge: View {
    let type: ClipboardContentType
    let isInverted: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: type.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isInverted ? Color(nsColor: .alternateSelectedControlTextColor) : type.color)
            .frame(width: PopoverMetrics.badgeSize, height: PopoverMetrics.badgeSize)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isInverted
                          ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.2)
                          : type.color.opacity(contrast == .increased ? 0.28 : 0.14))
            )
            .accessibilityHidden(true)
    }
}

struct NoticeView: View {
    let symbol: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.link)
                .font(.subheadline)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .padding(.horizontal, PopoverMetrics.gutter)
        .padding(.bottom, 10)
    }
}

// MARK: - Search field

/// NSSearchField for the native look, focus ring and cancel button. Keys like arrows, Return and Esc are
/// handled by AppDelegate's key monitor before they reach the field.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Changing this value makes the field first responder.
    var focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldChanged(_:))
        field.sendsSearchStringImmediately = true
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.setAccessibilityLabel("Search clipboard history")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            // The popover window isn't ready to change first responder within the same update.
            DispatchQueue.main.async {
                guard field.currentEditor() == nil else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var focusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                searchFieldChanged(field)
            }
        }

        /// Also called by the field's cancel (ⓧ) button, which doesn't send controlTextDidChange.
        @objc func searchFieldChanged(_ sender: NSSearchField) {
            if text.wrappedValue != sender.stringValue {
                text.wrappedValue = sender.stringValue
            }
        }
    }
}

// MARK: - Time formatting

enum RelativeTime {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// "Just now", "5 min. ago", "Yesterday", "Wed", "Oct 3".
    static func short(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        let calendar = Calendar.current
        if elapsed < 60 {
            return "Just now"
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if elapsed < 6 * 86_400 {
            return weekdayFormatter.string(from: date)
        }
        return monthDayFormatter.string(from: date)
    }

    static func full(_ date: Date) -> String {
        fullFormatter.string(from: date)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ClipboardManager(
            defaults: UserDefaults(suiteName: "ClipboardManagerPreview") ?? .standard,
            pasteboard: NSPasteboard(name: NSPasteboard.Name("ClipboardManagerPreview")),
            startsMonitoring: false
        )
        ContentView()
            .environmentObject(manager)
            .environmentObject(PopoverModel(manager: manager))
    }
}
