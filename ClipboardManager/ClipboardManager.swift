import AppKit
import Combine
import SwiftUI

struct ClipboardItem: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    /// The exact text that was copied, including leading/trailing whitespace.
    let content: String
    let timestamp: Date
    let contentType: ClipboardContentType

    init(content: String, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.contentType = ClipboardContentType.detectType(for: content)
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp, contentType
    }

    /// Only `content` is required. The stored `contentType` is ignored and re-detected, so improvements to
    /// detection apply to existing history and unknown values written by other versions can't break loading.
    /// `encode(to:)` is synthesized and still writes `contentType` so older builds can read new data.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let content = try container.decode(String.self, forKey: .content)
        let timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.init(content: content, timestamp: timestamp, id: id)
    }

    /// Trimmed, length-capped text for display. Never lay out the full content (up to 10,000 characters) in a row.
    var preview: String {
        String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.previewLength))
    }

    var isURL: Bool {
        return contentType == .url
    }

    var isEmail: Bool {
        return contentType == .email
    }

    private static let previewLength = 600
}

// MARK: - Display helpers

extension ClipboardItem {
    /// Lines to show in a list row. Code and JSON keep their first two non-blank lines with the common
    /// indentation removed; everything else is collapsed into a single line.
    var previewLines: [String] {
        let head = content.prefix(Self.previewLength)
        guard contentType.isMonospaced else {
            return [head.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")]
        }
        let lines = head
            .split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: "\t", with: "    ") }
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .prefix(2)
        let indent = lines.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        return lines.map { String($0.dropFirst(indent)) }
    }

    /// Number of lines, ignoring leading and trailing blank lines. Counts every kind of line break (\n, \r\n, \r, U+2028).
    var lineCount: Int {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    /// Short secondary detail for the row's metadata line: the host for links, the line count for multi-line text.
    var detail: String? {
        switch contentType {
        case .url:
            return Self.displayHost(of: content.trimmingCharacters(in: .whitespacesAndNewlines))
        case .text, .code, .json:
            let lines = lineCount
            return lines > 1 ? "\(lines) lines" : nil
        case .email, .number:
            return nil
        }
    }

    /// The host as written in the link (so internationalized domains aren't shown as Punycode), without "www.".
    /// Nil for file URLs.
    private static func displayHost(of link: String) -> String? {
        var rest = Substring(link)
        if let separator = rest.range(of: "://") {
            if rest[..<separator.lowerBound].lowercased() == "file" {
                return nil
            }
            rest = rest[separator.upperBound...]
        }
        rest = rest.prefix(while: { !"/?#".contains($0) })
        if let at = rest.lastIndex(of: "@") {
            rest = rest[rest.index(after: at)...]
        }
        rest = rest.prefix(while: { $0 != ":" })
        if rest.lowercased().hasPrefix("www.") {
            rest = rest.dropFirst(4)
        }
        return rest.isEmpty ? nil : String(rest)
    }
}

// MARK: - Content type

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case url
    case email
    case number
    case code
    case json

    static func detectType(for content: String) -> ClipboardContentType {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        // Links, emails and numbers are single tokens: prose such as "Note: buy milk" must not become a link.
        if !trimmed.contains(where: { $0.isWhitespace }) {
            // Cheap and exact, so it also covers long signed URLs.
            if let schemeType = schemeType(of: trimmed) {
                return schemeType
            }
            if trimmed.utf16.count <= 2048 {
                if Patterns.email.matches(trimmed) {
                    return .email
                }
                if isBareLink(trimmed) {
                    return .url
                }
                if Patterns.number.matches(trimmed) {
                    return .number
                }
            }
        }

        if isJSON(trimmed) {
            return .json
        }

        if looksLikeCode(trimmed) {
            return .code
        }

        return .text
    }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "Link"
        case .email: return "Email"
        case .number: return "Number"
        case .code: return "Code"
        case .json: return "JSON"
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .email: return "envelope"
        case .number: return "number"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .json: return "curlybraces"
        }
    }

    /// Tint for the type badge. Not used for text: these colors are too light for small text in light mode.
    var color: Color {
        switch self {
        case .text: return .secondary
        case .url: return .blue
        case .email: return .green
        case .number: return .orange
        case .code: return .purple
        case .json: return .pink
        }
    }

    var isMonospaced: Bool {
        return self == .code || self == .json
    }

    // MARK: Detection

    private static let linkSchemes: Set<String> = ["http", "https", "ftp", "ftps", "sftp", "ssh", "ws", "wss", "file"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Source-file extensions that are also country-code TLDs, so "main.rs" isn't mistaken for a domain.
    private static let fileExtensionTLDs: Set<String> = ["rs", "cc", "so"]

    /// Links with an explicit scheme: "https://…", "ssh://…", "file:///…", and "mailto:" (an email).
    private static func schemeType(of token: String) -> ClipboardContentType? {
        guard let url = URL(string: token), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "mailto" {
            return .email
        }
        if linkSchemes.contains(scheme), url.host != nil || scheme == "file" {
            return .url
        }
        return nil
    }

    /// Bare domains such as "apple.com" or "github.com/apple/swift", and local addresses like "localhost:8080".
    private static func isBareLink(_ token: String) -> Bool {
        if Patterns.localAddress.matches(token) {
            return true
        }
        let labels = token.split(separator: ".")
        if !token.contains("/"), labels.count == 2, let last = labels.last,
           fileExtensionTLDs.contains(last.lowercased()) {
            return false
        }
        // Only a match covering the whole token counts, so file names like "notes.txt" stay text.
        let range = NSRange(token.startIndex..., in: token)
        guard let match = linkDetector?.firstMatch(in: token, range: range), match.range == range else { return false }
        return match.url?.scheme?.lowercased() != "mailto"
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last,
              (first == "{" && last == "}") || (first == "[" && last == "]") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    /// Code needs one unambiguous construct (a declaration, an import, a call statement…) or at least two
    /// weaker hints. Keywords only count together with syntax, so prose like "Let me know if…" stays text.
    private static func looksLikeCode(_ text: String) -> Bool {
        let sample = text.utf16.count > 4000 ? String(text.prefix(4000)) : text
        if Patterns.strongCode.contains(where: { $0.matches(sample) }) {
            return true
        }
        return Patterns.weakCode.filter { $0.matches(sample) }.count >= 2
    }

    private enum Patterns {
        static let email = regex(#"^[\p{L}\p{N}._%+-]+@(?:[\p{L}\p{N}-]+\.)+[\p{L}\p{N}-]{2,}$"#)
        static let number = regex(#"^[+-]?(?=\.?\d)(?:\d{1,3}(?:,\d{3})+|\d+)?(?:\.\d+)?(?:[eE][+-]?\d+)?$"#)
        static let localAddress = regex(#"^(?:localhost|\d{1,3}(?:\.\d{1,3}){3})(?::\d{1,5}(?:/\S*)?|/\S*)$"#)

        // Line anchors use [ \t]* rather than \s*: \s also matches newlines, and with anchorsMatchLines a
        // "^\s*" would rescan long runs of blank lines from every line start (quadratic backtracking).
        static let strongCode: [NSRegularExpression] = [
            // Function declarations: func f(, def f(, fn f<, function f(
            #"^[ \t]*(?:(?:public|private|internal|fileprivate|open|static|final|export|default|async|override|mutating)[ \t]+)*(?:func|def|fn|function)[ \t]+[A-Za-z_$][\w$]*[ \t]*[(<]"#,
            // Variable declarations with a value: let x = 1, const y: T = …
            #"^[ \t]*(?:(?:export|public|private|static|final)[ \t]+)*(?:let|var|const|val)[ \t]+[A-Za-z_$][\w$]*[ \t]*(?::[^=\n]+)?=[^=]"#,
            // Type declarations opening a body
            #"^[ \t]*(?:(?:public|private|internal|fileprivate|open|final|export|abstract|sealed|data)[ \t]+)*(?:class|struct|enum|interface|protocol|extension|impl|trait)[ \t]+[A-Za-z_][\w<>, .:]*\{"#,
            // Python classes
            #"^[ \t]*class[ \t]+[A-Z]\w*[ \t]*(?:\([^)\n]*\))?[ \t]*:[ \t]*$"#,
            // Imports and preprocessor directives
            #"^[ \t]*#[ \t]*(?:include|import)[ \t]*[<"]|^[ \t]*#define[ \t]+\w+"#,
            #"^[ \t]*import[ \t]+[\w.]+[ \t]*;?[ \t]*$"#,
            #"^[ \t]*from[ \t]+[\w.]+[ \t]+import[ \t]+[\w*(]"#,
            #"^[ \t]*import[ \t]+[^\n]+[ \t]+from[ \t]+['"]"#,
            #"^[ \t]*(?:using|package)[ \t]+[\w.]+[ \t]*;[ \t]*$"#,
            // Control flow opening a block
            #"^[ \t]*(?:\}[ \t]*)?(?:if|else if|for|while|switch|guard|catch)\b[^\n]*\{[ \t]*$"#,
            // Shebang
            #"^#!/"#,
            // SQL statements (uppercase keywords)
            #"^[ \t]*(?:SELECT[ \t][^\n]*[ \t]FROM[ \t]|INSERT[ \t]+INTO[ \t]|UPDATE[ \t]+\S+[ \t]+SET[ \t]|DELETE[ \t]+FROM[ \t]|CREATE[ \t]+(?:TABLE|INDEX|VIEW|DATABASE)[ \t]|ALTER[ \t]+TABLE[ \t]|DROP[ \t]+(?:TABLE|INDEX|VIEW|DATABASE)[ \t])"#,
            // A line that is just a call: print("hi"), console.log(x);
            #"^[ \t]*[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\([^()\n]*\)[ \t]*;?[ \t]*$"#,
            // Closures and arrow functions: the parameter list must follow a name, "=", "(", ",", "{" or the line
            // start, so "Settings (gear icon) -> Privacy" stays prose.
            #"(?:[\w$]|[(,={][ \t]*|^[ \t]*)\([^()\n]*\)[ \t]*(?:=>|->)[ \t]*\S"#,
            // HTML/XML closing or self-closing tags
            #"</[A-Za-z][\w:-]*[ \t]*>|<[A-Za-z][\w:-]*[^<>\n]*/>"#,
            // Shell commands. Tools whose names are also English words ("swift", "cd", "docker"…) only count with
            // a known subcommand, a single argument, or a flag, path or file name, so chat messages stay prose.
            #"^[ \t]*\$[ \t]+\S"#,
            #"^[ \t]*(?:sudo|npm|npx|yarn|pnpm|kubectl|xcodebuild|xcrun|mkdir|chmod|chown|wget)[ \t]+[a-z][^\n]*[^.!?\s][ \t]*$"#,
            #"^[ \t]*git[ \t]+(?:add|bisect|blame|branch|checkout|cherry-pick|clone|commit|config|diff|fetch|grep|init|log|merge|mv|pull|push|rebase|remote|reset|restore|revert|rm|show|stash|status|submodule|switch|tag|worktree)\b(?:[^\n]*[^.!?\s])?[ \t]*$"#,
            #"^[ \t]*(?:brew|pip3?|cargo|swift|docker)[ \t]+(?:install|uninstall|reinstall|update|upgrade|build|run|test|ps|exec|compose|pull|push|package|init|add|list|search|info|logs|images|services|tap)\b(?:[^\n]*[^.!?\s])?[ \t]*$"#,
            #"^[ \t]*(?:cd|rm|cp|mv|curl|python3?|grep|ssh|ls|tar)[ \t]+\S+[ \t]*$"#,
            #"^[ \t]*(?:brew|cd|rm|cp|mv|curl|docker|swift|python3?|pip3?|grep|cargo|ssh|ls|tar)[ \t]+(?=(?:[^\n]*[ \t])?-{1,2}[A-Za-z]|[^\n]*[/~|>$=]|[^\n]*\.\w)[^\n]*[^.!?\s][ \t]*$"#,
        ].map(regex)

        static let weakCode: [NSRegularExpression] = [
            #";[ \t]*$"#,
            #"[{}][ \t]*;?[ \t]*$"#,
            #"==|!=|&&|\|\||<=|>=|\+=|-=|\*=|/=|::"#,
            #"\b[A-Za-z_$][\w$]*\.[A-Za-z_$][\w$]*\("#,
            #"^[ \t]*(?://|/\*|\*/)"#,
            #"^[ \t]*[A-Za-z_$][\w$.\[\]]*[ \t]*[+\-*/%]?=[ \t]*[^=\s]"#,
            // Keywords only in code positions, so "Please return the forms" doesn't count
            #"(?:^[ \t]*|[{;][ \t]*)(?:return|await|elif)\b|[=(,:\[!][ \t]*(?:null|nil|undefined|None)\b|\b(?:null|nil|undefined)[ \t]*[),;\]]|\blambda\b[^\n]*:"#,
            #"\{[^{}\n]*;[^{}\n]*\}"#,
            // Indented lines, except list items
            #"^(?:\t| {2,})(?![-*+•][ \t]|\d+[.)][ \t])\S"#,
        ].map(regex)

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // Patterns are compile-time constants; a failure here is a programming error.
            return try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }
}

private extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        return firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}

/// Decodes an element if possible and yields nil otherwise, so one bad entry can't discard the whole history.
private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Clipboard manager

/// Monitors the pasteboard and keeps the clipboard history. Use from the main thread.
class ClipboardManager: ObservableObject {
    static let defaultMaxItems = 100
    static let storageKey = "ClipboardManagerItems"

    /// Markers that password managers and other apps put on the pasteboard for content that must not be
    /// recorded (see nspasteboard.org).
    static let ignoredPasteboardTypes: Set<NSPasteboard.PasteboardType> = Set([
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
    ].map { NSPasteboard.PasteboardType($0) })

    @Published var clipboardItems: [ClipboardItem] = [] {
        didSet {
            // A safety net for direct assignments; record() trims before assigning so it saves only once.
            if clipboardItems.count > maxItems {
                clipboardItems.removeLast(clipboardItems.count - maxItems)
            }
            if !isRestoring {
                saveItems()
            }
        }
    }

    @Published var isMonitoring: Bool = false
    @Published var lastError: String?
    /// True when macOS (15.4 or later) is set to deny this app access to the clipboard.
    @Published private(set) var isPasteboardAccessDenied = false

    let maxItems: Int
    /// Longer copies are skipped. Measured in UTF-16 units, which is cheap for pasteboard strings.
    let maxClipboardLength = 10_000

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var isRestoring = false

    /// - Parameter legacyDefaults: Where older builds kept history (see `legacyDefaults`). Its copy is removed
    ///   when the history is cleared.
    init(defaults: UserDefaults = .standard,
         legacyDefaults: UserDefaults? = nil,
         pasteboard: NSPasteboard = .general,
         maxItems: Int = ClipboardManager.defaultMaxItems,
         startsMonitoring: Bool = true) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        self.pasteboard = pasteboard
        self.maxItems = max(1, maxItems)
        loadItems()
        if startsMonitoring {
            startMonitoring()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Builds that ran as a bare executable (`swift run`) keep history in the "ClipboardManager" defaults domain.
    /// Nil when this process is such a build, because then that domain is `UserDefaults.standard`.
    static var legacyDefaults: UserDefaults? {
        let legacyDomain = "ClipboardManager"
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != legacyDomain else { return nil }
        return UserDefaults(suiteName: legacyDomain)
    }

    /// When running from an app bundle, copies history from the legacy domain once.
    static func migrateLegacyHistory(from legacy: UserDefaults? = ClipboardManager.legacyDefaults,
                                     to defaults: UserDefaults = .standard) {
        guard defaults.data(forKey: storageKey) == nil,
              let data = legacy?.data(forKey: storageKey) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: Persistence

    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(clipboardItems)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            lastError = "Couldn’t save clipboard history: \(error.localizedDescription)"
        }
    }

    private func loadItems() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }

        isRestoring = true
        defer { isRestoring = false }

        do {
            let entries = try JSONDecoder().decode([FailableDecodable<ClipboardItem>].self, from: data)
            let items = entries.compactMap(\.value)
            if items.count < entries.count {
                backUp(data)
                let skipped = entries.count - items.count
                lastError = "\(skipped) saved \(skipped == 1 ? "item" : "items") couldn’t be read and \(skipped == 1 ? "was" : "were") skipped."
            }
            clipboardItems = items
        } catch {
            // Keep the unreadable data so the next save can't destroy it.
            backUp(data)
            lastError = "Couldn’t read saved clipboard history: \(error.localizedDescription)"
        }
    }

    private func backUp(_ data: Data) {
        defaults.set(data, forKey: Self.backupKey)
    }

    private static let backupKey = storageKey + ".backup"

    // MARK: Monitoring

    func startMonitoring() {
        guard timer == nil else { return }

        // Start from the current pasteboard state; only later copies are recorded.
        lastChangeCount = pasteboard.changeCount
        refreshPasteboardAccess()

        // Common modes keep polling while menus, alerts or scroll tracking run the run loop.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        isMonitoring = true
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func checkClipboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Reading the types doesn't read the contents, so concealed items are never touched.
        let types = pasteboard.types ?? []
        guard Self.ignoredPasteboardTypes.isDisjoint(with: types) else { return }

        guard let string = pasteboard.string(forType: .string) else {
            if types.contains(.string) {
                refreshPasteboardAccess()
            }
            return
        }
        if isPasteboardAccessDenied {
            isPasteboardAccessDenied = false
        }
        record(string)
    }

    /// Adds `string` to the top of the history. Copying text that is already in the history moves that entry
    /// to the top instead of adding a duplicate.
    func record(_ string: String) {
        let length = string.utf16.count
        guard length > 0, length <= maxClipboardLength,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        var items = clipboardItems
        let existingID = items.first(where: { $0.content == string })?.id
        items.removeAll { $0.content == string }
        items.insert(ClipboardItem(content: string, id: existingID ?? UUID()), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        clipboardItems = items
    }

    func refreshPasteboardAccess() {
        // accessBehavior is in the macOS 15.4 SDK (Swift 6.1 toolchains); older toolchains can still build the app.
        #if compiler(>=6.1)
        guard #available(macOS 15.4, *) else { return }
        let denied = pasteboard.accessBehavior == .alwaysDeny
        if denied != isPasteboardAccessDenied {
            isPasteboardAccessDenied = denied
        }
        #endif
    }

    // MARK: Actions

    /// Puts the item's text on the pasteboard. Unless `movesToTop` is false, the item also moves to the top
    /// of the history with a fresh timestamp.
    @discardableResult
    func copyToClipboard(item: ClipboardItem, movesToTop: Bool = true) -> Bool {
        // Record any copy made since the last poll so it isn't lost when we overwrite the pasteboard.
        checkClipboard()

        let ownChangeCount = pasteboard.clearContents()
        guard pasteboard.setString(item.content, forType: .string) else {
            lastError = "Couldn’t copy the item to the clipboard."
            return false
        }
        // Our own write must not come back as a new history entry. Using the count from clearContents() means a
        // copy another app makes right after this one is still recorded.
        lastChangeCount = ownChangeCount

        if movesToTop {
            moveToTop(item)
        }
        return true
    }

    func moveToTop(_ item: ClipboardItem) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        var items = clipboardItems
        let existing = items.remove(at: index)
        items.insert(ClipboardItem(content: existing.content, id: existing.id), at: 0)
        clipboardItems = items
    }

    func clearHistory() {
        clipboardItems.removeAll()
        // Don't leave copies behind: the backup of unreadable data and history migrated from older builds.
        defaults.removeObject(forKey: Self.backupKey)
        legacyDefaults?.removeObject(forKey: Self.storageKey)
        lastError = nil
    }

    func removeItem(at indexSet: IndexSet) {
        clipboardItems.remove(atOffsets: indexSet)
    }

    func removeItem(_ item: ClipboardItem) {
        if let index = clipboardItems.firstIndex(where: { $0.id == item.id }) {
            clipboardItems.remove(at: index)
        }
    }

    func searchItems(query: String) -> [ClipboardItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return clipboardItems }

        return clipboardItems.filter { item in
            item.content.localizedCaseInsensitiveContains(query)
        }
    }

    func getItemsByType(_ type: ClipboardContentType) -> [ClipboardItem] {
        return clipboardItems.filter { $0.contentType == type }
    }

    func exportItems() -> String {
        let items = clipboardItems.map { item in
            "\(item.timestamp): \(item.content)"
        }
        return items.joined(separator: "\n\n")
    }
}
