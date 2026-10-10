import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipboardManager

// MARK: - Test support

/// A private defaults suite and a private named pasteboard for a single test, so tests never read or overwrite the
/// developer's real clipboard (`NSPasteboard.general`) or saved history (`UserDefaults.standard`).
///
/// Create one per test and release it with `defer { env.cleanUp() }`.
struct TestEnvironment {
    let suiteName: String
    let defaults: UserDefaults
    let pasteboard: NSPasteboard

    init() {
        // An absolute path keeps the suite's plist in the temporary directory. With a plain name, cfprefsd leaves
        // an empty plist per test in ~/Library/Preferences even after removePersistentDomain.
        suiteName = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardManagerTests.\(UUID().uuidString)").path
        defaults = UserDefaults(suiteName: suiteName)!
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardManagerTests.\(UUID().uuidString)"))
    }

    /// A manager that never polls on its own: tests call `checkClipboard()` explicitly.
    func makeManager(maxItems: Int = ClipboardManager.defaultMaxItems) -> ClipboardManager {
        ClipboardManager(defaults: defaults, pasteboard: pasteboard, maxItems: maxItems, startsMonitoring: false)
    }

    /// A manager reading the same suite through a separate `UserDefaults` instance, like a relaunched app.
    func makeRelaunchedManager(maxItems: Int = ClipboardManager.defaultMaxItems) -> ClipboardManager {
        ClipboardManager(defaults: UserDefaults(suiteName: suiteName)!, pasteboard: pasteboard,
                         maxItems: maxItems, startsMonitoring: false)
    }

    /// Simulates another app copying plain text.
    func copyExternally(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Simulates an app (such as a password manager) copying text together with a marker type.
    func copyExternally(_ string: String, markedAs marker: String) {
        let markerType = NSPasteboard.PasteboardType(marker)
        pasteboard.declareTypes([.string, markerType], owner: nil)
        pasteboard.setString(string, forType: .string)
        pasteboard.setData(Data(), forType: markerType)
    }

    var pasteboardString: String? {
        pasteboard.string(forType: .string)
    }

    /// The raw saved history.
    var storedHistory: Data? {
        get { defaults.data(forKey: ClipboardManager.storageKey) }
        nonmutating set { defaults.set(newValue, forKey: ClipboardManager.storageKey) }
    }

    var backup: Data? {
        defaults.data(forKey: ClipboardManager.storageKey + ".backup")
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard.releaseGlobally()
    }
}

/// History items, newest first, with fixed timestamps one minute apart.
func makeItems(_ contents: [String]) -> [ClipboardItem] {
    let newest = Date(timeIntervalSinceReferenceDate: 700_000_000)
    return contents.enumerated().map { index, content in
        ClipboardItem(content: content, timestamp: newest.addingTimeInterval(Double(-60 * index)))
    }
}

func encodedJSON<Value: Encodable>(_ value: Value) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

func decodeItem(_ json: String) throws -> ClipboardItem {
    try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))
}

extension ClipboardManager {
    var contents: [String] {
        clipboardItems.map(\.content)
    }
}

// MARK: - Content type detection

@Suite("Content type detection")
struct ContentTypeDetectionTests {
    @Test("Prose, labels, file names, paths and number-like words are text", arguments: [
        "Note: buy milk",
        "Warning: disk full",
        "TODO: fix login",
        "Re: meeting",
        "localhost",
        "Thanks for the update",
        "Let me know if you need anything",
        "Life is good",
        "Various default settings",
        "Here is the information you requested.",
        "Can you return it by Friday?",
        "The information in this letter is different from what we discussed.",
        "cat.gif",
        "notes.txt",
        "/Users/x/Documents/Information.pdf",
        "Paris -> London",
        "make sure you call me",
        "import the data into excel",
        "4111 1111",
        "nan",
        "inf",
        "infinity",
        "1.",
        "C:\\Users\\haris",
        "class notes: bring a pen",
    ])
    func text(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .text)
    }

    @Test("Links with a scheme, bare domains and local addresses are links", arguments: [
        "https://developer.apple.com/documentation/swiftui",
        "http://localhost:3000/api",
        "localhost:8080",
        "www.apple.com",
        "apple.com",
        "github.com/apple/swift",
        "ssh://git@github.com/x.git",
        "file:///Users/x/a.txt",
        "192.168.1.10:8080",
    ])
    func url(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .url)
    }

    @Test("Email addresses and mailto links are emails", arguments: [
        "jane.appleseed@example.com",
        "mailto:foo@bar.com",
        "user+tag@sub.example.co.uk",
    ])
    func email(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .email)
    }

    @Test("Integers, decimals, grouped and scientific numbers are numbers", arguments: [
        "42",
        "-3.14",
        "1,234,567.89",
        "1e10",
        ".5",
        "007",
    ])
    func number(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .number)
    }

    @Test("Valid JSON objects and arrays are JSON", arguments: [
        "{\"name\": \"Clipboard\", \"version\": 2}",
        "[1, 2, 3]",
        "{\n  \"a\": [true, null]\n}",
    ])
    func json(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .json)
    }

    @Test("Source code, SQL, shell commands, CSS and markup are code", arguments: [
        "func greet(_ name: String) -> String {\n    return name\n}",
        "let x = 5",
        "const a = 1;",
        "print(\"hi\")",
        "console.log(x);",
        "SELECT * FROM users WHERE id = 1;",
        "#include <stdio.h>",
        "fn main() {}",
        "def foo(x):\n    return x",
        "import Foundation",
        "from os import path",
        "git commit -m \"fix\"",
        "cd ~/projects",
        "if (a) {\n  b();\n}",
        ".btn {\n  color: red;\n}",
        "<div class=\"x\">Hi</div>",
        "#!/bin/bash\necho hi",
        "class Foo:\n    pass",
    ])
    func code(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .code)
    }

    @Test("Surrounding whitespace doesn't change the type", arguments: [
        ("https://apple.com", ClipboardContentType.url),
        ("jane.appleseed@example.com", .email),
        ("42", .number),
        ("[1, 2, 3]", .json),
        ("let x = 5", .code),
        ("Note: buy milk", .text),
    ])
    func surroundingWhitespace(_ input: String, expected: ClipboardContentType) {
        #expect(ClipboardContentType.detectType(for: "  \n\t" + input + " \n\n") == expected)
    }

    @Test("Empty and whitespace-only content is text", arguments: ["", " ", "\n\n", " \t\n "])
    func blank(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .text)
    }
}

// MARK: - Content type metadata

@Suite("Content type metadata")
struct ContentTypeMetadataTests {
    static let displayNames: [(ClipboardContentType, String)] = [
        (.text, "Text"), (.url, "Link"), (.email, "Email"), (.number, "Number"), (.code, "Code"), (.json, "JSON"),
    ]

    /// Raw values are persisted in saved history, so they must never change.
    static let rawValues: [(ClipboardContentType, String)] = [
        (.text, "text"), (.url, "url"), (.email, "email"), (.number, "number"), (.code, "code"), (.json, "json"),
    ]

    @Test("Display names", arguments: displayNames)
    func displayName(_ type: ClipboardContentType, expected: String) {
        #expect(type.displayName == expected)
    }

    @Test("Raw values are stable", arguments: rawValues)
    func rawValue(_ type: ClipboardContentType, expected: String) {
        #expect(type.rawValue == expected)
        #expect(ClipboardContentType(rawValue: expected) == type)
    }

    @Test("The tables above cover every case")
    func tablesCoverAllCases() {
        let allCases = Set(ClipboardContentType.allCases)
        #expect(Set(Self.displayNames.map { $0.0 }) == allCases)
        #expect(Set(Self.rawValues.map { $0.0 }) == allCases)
    }
}

// MARK: - ClipboardItem model

@Suite("ClipboardItem model and coding")
struct ClipboardItemTests {
    @Test("Items with the same id, content and timestamp are equal; a different id is not")
    func equality() {
        let id = UUID()
        let timestamp = Date()
        let item = ClipboardItem(content: "Test content", timestamp: timestamp, id: id)

        #expect(item == ClipboardItem(content: "Test content", timestamp: timestamp, id: id))
        #expect(Set([item, ClipboardItem(content: "Test content", timestamp: timestamp, id: id)]).count == 1)
        #expect(item != ClipboardItem(content: "Test content", timestamp: timestamp, id: UUID()))
    }

    @Test("Encoding and decoding round-trips every field")
    func codableRoundTrip() throws {
        let items = [
            ClipboardItem(content: "Test content"),
            ClipboardItem(content: "  https://apple.com\n", timestamp: Date(timeIntervalSince1970: 1_234.5678)),
            ClipboardItem(content: "{\"a\": 1}"),
        ]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)

        #expect(decoded == items)
        #expect(decoded.map(\.contentType) == [.text, .url, .json])
    }

    @Test("A stale, unknown or missing stored contentType is ignored and re-detected", arguments: [
        #""contentType": "code","#,
        #""contentType": "image","#,
        #""contentType": 7,"#,
        "",
    ])
    func storedContentTypeIsRedetected(_ contentTypeField: String) throws {
        let id = UUID()
        let item = try decodeItem("""
            {\(contentTypeField) "id": "\(id.uuidString)", "content": "Thanks for the update", "timestamp": 0}
            """)

        #expect(item.contentType == .text)
        #expect(item.id == id)
        #expect(item.content == "Thanks for the update")
        #expect(item.timestamp == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("An item stored as an unknown type gets its detected type")
    func unknownTypeGetsDetectedType() throws {
        let item = try decodeItem(#"{"content": "https://apple.com", "contentType": "image"}"#)
        #expect(item.contentType == .url)
    }

    @Test("Missing id and timestamp decode with fresh values")
    func missingIDAndTimestamp() throws {
        let json = #"{"content": "hello"}"#
        let first = try decodeItem(json)
        let second = try decodeItem(json)

        #expect(first.content == "hello")
        #expect(first.id != second.id)
        #expect(abs(first.timestamp.timeIntervalSinceNow) < 60)
    }

    @Test("Content is required")
    func missingContentFails() {
        #expect(throws: (any Error).self) {
            try decodeItem(#"{"id": "\#(UUID().uuidString)", "timestamp": 0, "contentType": "text"}"#)
        }
    }

    @Test("Encoding still writes contentType for older builds")
    func encodingWritesContentType() throws {
        let item = ClipboardItem(content: "https://apple.com")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]

        #expect(object?["contentType"] as? String == "url")
        #expect(object?["content"] as? String == "https://apple.com")
        #expect(object?["id"] as? String == item.id.uuidString)
    }
}

// MARK: - Display helpers

@Suite("Item display helpers")
struct ItemDisplayTests {
    @Test("preview is trimmed")
    func previewIsTrimmed() {
        #expect(ClipboardItem(content: "  \n hello world \n\t").preview == "hello world")
    }

    @Test("preview and previewLines are capped at 600 characters")
    func previewIsCapped() {
        let long = "   \n" + String(repeating: "x", count: 1_000)
        #expect(ClipboardItem(content: long).preview == String(repeating: "x", count: 600))

        let prose = ClipboardItem(content: String(repeating: "word ", count: 500))
        #expect(prose.preview.count <= 600)
        #expect(prose.previewLines.count == 1)
        #expect(prose.previewLines.allSatisfy { $0.count <= 600 })
    }

    @Test("Prose collapses runs of whitespace and newlines into a single line")
    func proseCollapsesWhitespace() throws {
        let item = ClipboardItem(content: "  Hello,\n\n   world!\tSee you\r\nsoon.  ")
        try #require(item.contentType == .text)
        #expect(item.previewLines == ["Hello, world! See you soon."])
    }

    @Test("Code and JSON keep their first two non-blank lines without common indentation", arguments: [
        ("    func greet() {\n\n        return 1\n    }\n", ["func greet() {", "    return 1"]),
        ("\tif (a) {\n\t\tb();\n\t}", ["if (a) {", "    b();"]),
        ("\n\n  let x = 5\n   \n  let y = 6\n  let z = 7\n", ["let x = 5", "let y = 6"]),
        ("{\n  \"a\": 1,\n  \"b\": 2\n}", ["{", "  \"a\": 1,"]),
        ("let x = 5", ["let x = 5"]),
    ])
    func monospacedPreviewLines(_ content: String, expected: [String]) throws {
        let item = ClipboardItem(content: content)
        try #require(item.contentType.isMonospaced)
        #expect(item.previewLines == expected)
    }

    @Test("lineCount ignores leading and trailing blank lines", arguments: [
        ("one", 1),
        ("one\ntwo", 2),
        ("\n\none\ntwo\n\n", 2),
        ("  \n one\n\n three \n \n", 3),
    ])
    func lineCount(_ content: String, expected: Int) {
        #expect(ClipboardItem(content: content).lineCount == expected)
    }

    @Test("detail is the host for links and the line count for multi-line text", arguments: [
        ("https://www.apple.com/mac", "apple.com"),
        ("https://developer.apple.com/documentation/swiftui", "developer.apple.com"),
        ("www.apple.com", "apple.com"),
        ("github.com/apple/swift", "github.com"),
        ("localhost:8080", "localhost"),
        ("first line\nsecond line", "2 lines"),
        ("func greet(_ name: String) -> String {\n    return name\n}", "3 lines"),
        ("{\n  \"a\": 1\n}", "3 lines"),
    ] as [(String, String?)])
    func detail(_ content: String, expected: String?) {
        #expect(ClipboardItem(content: content).detail == expected)
    }

    @Test("detail is nil for single-line text, code, emails and numbers", arguments: [
        "Just one line of text",
        "  padded single line\n\n",
        "let x = 5",
        "jane.appleseed@example.com",
        "42",
    ])
    func noDetail(_ content: String) {
        #expect(ClipboardItem(content: content).detail == nil)
    }
}

// MARK: - Recording copies

@MainActor
@Suite("Recording copies", .serialized)
struct RecordingTests {
    @Test("A copy on the pasteboard is recorded at the top")
    func recordsCopies() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("first")
        manager.checkClipboard()
        env.copyExternally("second")
        manager.checkClipboard()

        #expect(manager.contents == ["second", "first"])
        #expect(manager.clipboardItems.first?.contentType == .text)
    }

    @Test("Content is stored exactly as copied, including surrounding whitespace")
    func storesContentUntrimmed() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("  indented\n")
        manager.checkClipboard()

        #expect(manager.contents == ["  indented\n"])
        #expect(env.makeRelaunchedManager().contents == ["  indented\n"])
    }

    @Test("Empty and whitespace-only copies are ignored", arguments: ["", " ", "\n\n", " \t\n "])
    func ignoresBlankCopies(_ input: String) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally(input)
        manager.checkClipboard()
        manager.record(input)

        #expect(manager.clipboardItems.isEmpty)
    }

    @Test("A copy of exactly 10,000 UTF-16 units is recorded")
    func acceptsMaximumLength() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally(String(repeating: "a", count: 10_000))
        manager.checkClipboard()
        env.copyExternally(String(repeating: "😀", count: 5_000))
        manager.checkClipboard()

        #expect(manager.clipboardItems.map { $0.content.utf16.count } == [10_000, 10_000])
    }

    @Test("A copy longer than 10,000 UTF-16 units is ignored")
    func ignoresOverlongCopies() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally(String(repeating: "a", count: 10_001))
        manager.checkClipboard()
        // 5,001 characters, but 10,002 UTF-16 units.
        env.copyExternally(String(repeating: "😀", count: 5_001))
        manager.checkClipboard()

        #expect(manager.clipboardItems.isEmpty)
    }

    @Test("Copying older text again moves it to the top without a duplicate and keeps its id")
    func recopyMovesToTop() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("one")
        manager.checkClipboard()
        let originalID = try #require(manager.clipboardItems.first?.id)
        env.copyExternally("two")
        manager.checkClipboard()
        env.copyExternally("one")
        manager.checkClipboard()

        #expect(manager.contents == ["one", "two"])
        #expect(manager.clipboardItems.first?.id == originalID)
    }

    @Test("Checking again without a new copy doesn't add a duplicate")
    func repeatedCheckDoesNotDuplicate() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("only once")
        manager.checkClipboard()
        manager.checkClipboard()

        #expect(manager.contents == ["only once"])
    }

    @Test("Recording beyond maxItems drops the oldest entries")
    func trimsToMaxItems() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager(maxItems: 3)

        for text in ["1", "2", "3", "4", "5"] {
            env.copyExternally(text)
            manager.checkClipboard()
        }

        #expect(manager.contents == ["5", "4", "3"])
    }
}

// MARK: - Concealed and transient copies

@MainActor
@Suite("Concealed and transient copies", .serialized)
struct ConcealedCopyTests {
    @Test("Copies marked concealed, transient or auto-generated are not recorded", arguments: [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ])
    func ignoresMarkedCopies(_ marker: String) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("hunter2", markedAs: marker)
        manager.checkClipboard()
        #expect(manager.clipboardItems.isEmpty)

        // Monitoring carries on with the next ordinary copy.
        env.copyExternally("visible")
        manager.checkClipboard()
        #expect(manager.contents == ["visible"])
    }

    @Test("An unrelated extra pasteboard type doesn't prevent recording")
    func recordsCopiesWithOtherTypes() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()

        env.copyExternally("plain text", markedAs: "com.example.custom-type")
        manager.checkClipboard()

        #expect(manager.contents == ["plain text"])
    }
}

// MARK: - Copying back to the clipboard

@MainActor
@Suite("Copying an item back to the clipboard", .serialized)
struct CopyToClipboardTests {
    @Test("Copying moves the item to the top immediately and puts its text on the pasteboard")
    func movesToTopAndWritesPasteboard() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["a", "b", "c"])
        let item = manager.clipboardItems[2]

        #expect(manager.copyToClipboard(item: item))

        #expect(manager.contents == ["c", "a", "b"])
        #expect(manager.clipboardItems.first?.id == item.id)
        #expect(env.pasteboardString == "c")
    }

    @Test("The app's own write doesn't come back as a new entry", arguments: [true, false])
    func noSelfCapture(movesToTop: Bool) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["a", "b", "c"])

        manager.copyToClipboard(item: manager.clipboardItems[1], movesToTop: movesToTop)
        let afterCopy = manager.clipboardItems
        manager.checkClipboard()

        #expect(manager.clipboardItems == afterCopy)
    }

    @Test("movesToTop: false writes the pasteboard but leaves the history alone")
    func withoutMovingToTop() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let items = makeItems(["a", "b", "c"])
        manager.clipboardItems = items

        #expect(manager.copyToClipboard(item: items[2], movesToTop: false))

        #expect(manager.clipboardItems == items)
        #expect(env.pasteboardString == "c")
    }

    @Test("Copying refreshes the item's timestamp but keeps its id")
    func refreshesTimestamp() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let old = ClipboardItem(content: "old", timestamp: Date(timeIntervalSinceNow: -3_600))
        manager.clipboardItems = [ClipboardItem(content: "newer"), old]

        manager.copyToClipboard(item: old)

        let top = try #require(manager.clipboardItems.first)
        #expect(top.id == old.id)
        #expect(top.content == "old")
        #expect(top.timestamp > old.timestamp)
    }

    @Test("A copy made in another app but not yet polled is recorded, not lost")
    func recordsPendingExternalCopy() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["a", "b"])

        env.copyExternally("external")
        manager.copyToClipboard(item: manager.clipboardItems[1])

        #expect(manager.contents == ["b", "external", "a"])
        #expect(env.pasteboardString == "b")
    }
}

// MARK: - Editing the history

@MainActor
@Suite("Editing the history", .serialized)
struct HistoryEditingTests {
    @Test("clearHistory removes every item and clears the last error")
    func clearHistory() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        env.storedHistory = Data("not json".utf8)
        let manager = env.makeManager()
        #expect(manager.lastError != nil)
        manager.clipboardItems = makeItems(["Item 1", "Item 2"])

        manager.clearHistory()

        #expect(manager.clipboardItems.isEmpty)
        #expect(manager.lastError == nil)
    }

    @Test("removeItem(at:) removes the items at the given offsets", arguments: [
        ([1], ["a", "c", "d"]),
        ([0, 3], ["b", "c"]),
        ([], ["a", "b", "c", "d"]),
    ] as [([Int], [String])])
    func removeAtOffsets(_ offsets: [Int], expected: [String]) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["a", "b", "c", "d"])

        manager.removeItem(at: IndexSet(offsets))

        #expect(manager.contents == expected)
    }

    @Test("removeItem(_:) removes the item with the same id")
    func removeItem() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let items = makeItems(["a", "b", "c"])
        manager.clipboardItems = items

        manager.removeItem(items[1])
        #expect(manager.clipboardItems == [items[0], items[2]])

        manager.removeItem(ClipboardItem(content: "a"))
        #expect(manager.clipboardItems == [items[0], items[2]])
    }

    @Test("moveToTop moves the matching item with a fresh timestamp; unknown items are ignored")
    func moveToTop() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let items = makeItems(["a", "b", "c"])
        manager.clipboardItems = items

        manager.moveToTop(items[2])
        let top = try #require(manager.clipboardItems.first)
        #expect(manager.contents == ["c", "a", "b"])
        #expect(top.id == items[2].id)
        #expect(top.timestamp > items[2].timestamp)

        let before = manager.clipboardItems
        manager.moveToTop(ClipboardItem(content: "not in history"))
        #expect(manager.clipboardItems == before)
    }

    @Test("By default the history keeps the first 100 items")
    func defaultMaxItems() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let items = makeItems((0..<150).map { "Item \($0)" })

        manager.clipboardItems = items

        #expect(manager.maxItems == 100)
        #expect(manager.clipboardItems == Array(items.prefix(100)))
    }

    @Test("Assigning more than maxItems keeps the first ones")
    func smallMaxItems() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager(maxItems: 5)
        let items = makeItems((0..<8).map { "Item \($0)" })

        manager.clipboardItems = items

        #expect(manager.clipboardItems == Array(items.prefix(5)))
    }

    @Test("maxItems is at least 1", arguments: [(0, 1), (-5, 1), (1, 1), (5, 5)])
    func maxItemsIsClamped(_ requested: Int, expected: Int) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        #expect(env.makeManager(maxItems: requested).maxItems == expected)
    }
}

// MARK: - Searching and filtering

@MainActor
@Suite("Searching and filtering", .serialized)
struct SearchTests {
    static let contents = [
        "Hello World",
        "https://apple.com",
        "hello there",
        "let x = 5",
        "Goodbye",
        "https://swift.org",
    ]

    @Test("searchItems is case-insensitive, trims the query and keeps history order", arguments: [
        ("HELLO", ["Hello World", "hello there"]),
        ("  world \n", ["Hello World"]),
        ("https://", ["https://apple.com", "https://swift.org"]),
        ("x = 5", ["let x = 5"]),
        ("no match", []),
    ])
    func search(_ query: String, expected: [String]) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(Self.contents)

        #expect(manager.searchItems(query: query).map(\.content) == expected)
    }

    @Test("An empty or blank query returns the whole history", arguments: ["", "   ", "\n\t"])
    func emptyQuery(_ query: String) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(Self.contents)

        #expect(manager.searchItems(query: query) == manager.clipboardItems)
    }

    @Test("getItemsByType returns only items of that type, in order", arguments: [
        (ClipboardContentType.url, ["https://apple.com", "https://swift.org"]),
        (.text, ["Hello World", "hello there", "Goodbye"]),
        (.code, ["let x = 5"]),
        (.json, []),
    ])
    func filterByType(_ type: ClipboardContentType, expected: [String]) {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(Self.contents)

        #expect(manager.getItemsByType(type).map(\.content) == expected)
    }

    @Test("exportItems lists every item in history order, separated by blank lines")
    func export() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        #expect(manager.exportItems() == "")

        manager.clipboardItems = makeItems(["first", "second\nline"])
        let entries = manager.exportItems().components(separatedBy: "\n\n")

        #expect(entries.count == 2)
        #expect(entries.first?.hasSuffix(": first") == true)
        #expect(entries.last?.hasSuffix(": second\nline") == true)
    }
}

// MARK: - Persistence

@MainActor
@Suite("Saving and loading history", .serialized)
struct PersistenceTests {
    @Test("A new manager loads the saved history with order, ids, content and timestamps intact")
    func roundTrip() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["Persistent Item 1", "  https://apple.com\n", "let x = 5"])
        env.copyExternally("recorded copy")
        manager.checkClipboard()

        let reloaded = env.makeRelaunchedManager()

        #expect(reloaded.clipboardItems == manager.clipboardItems)
        #expect(reloaded.lastError == nil)
        #expect(env.backup == nil)
    }

    @Test("Edits are saved immediately")
    func editsArePersisted() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        let items = makeItems(["a", "b", "c"])
        manager.clipboardItems = items

        manager.removeItem(items[1])

        #expect(env.makeRelaunchedManager().clipboardItems == [items[0], items[2]])
    }

    @Test("Clearing the history is saved")
    func clearHistoryIsPersisted() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(["a", "b"])

        manager.clearHistory()

        #expect(env.makeRelaunchedManager().clipboardItems.isEmpty)
    }

    @Test("Loading more items than maxItems keeps the newest ones")
    func loadingTrimsToMaxItems() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let items = makeItems((0..<10).map { "Item \($0)" })
        env.makeManager(maxItems: 10).clipboardItems = items

        let manager = env.makeRelaunchedManager(maxItems: 5)

        #expect(manager.clipboardItems == Array(items.prefix(5)))
    }

    @Test("Unreadable entries are skipped, reported and backed up; readable ones load")
    func lossyLoading() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let first = ClipboardItem(content: "first", timestamp: Date(timeIntervalSinceReferenceDate: 200))
        let second = ClipboardItem(content: "https://apple.com", timestamp: Date(timeIntervalSinceReferenceDate: 100))
        let stored = Data("""
            [
              \(try encodedJSON(first)),
              42,
              {"id": "\(UUID().uuidString)", "timestamp": 5, "contentType": "text"},
              "a loose string",
              null,
              \(try encodedJSON(second))
            ]
            """.utf8)
        env.storedHistory = stored

        let manager = env.makeManager()

        #expect(manager.clipboardItems == [first, second])
        #expect(manager.lastError != nil)
        #expect(env.backup == stored)
    }

    @Test("Corrupt history loads as empty, is reported, and is kept until something new is recorded", arguments: [
        "definitely not json",
        #"{"content": "an object, not an array"}"#,
        "",
    ])
    func corruptHistory(_ corrupt: String) throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let stored = Data(corrupt.utf8)
        env.storedHistory = stored

        let manager = env.makeManager()

        #expect(manager.clipboardItems.isEmpty)
        #expect(manager.lastError != nil)
        #expect(env.backup == stored)
        #expect(env.storedHistory == stored)

        manager.record("new item")

        let saved = try #require(env.storedHistory)
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: saved).map(\.content) == ["new item"])
        #expect(env.backup == stored)
    }

    @Test("Migrating legacy history never overwrites existing history")
    func migrationKeepsExistingHistory() throws {
        let env = TestEnvironment()
        let legacy = TestEnvironment()
        defer { env.cleanUp(); legacy.cleanUp() }
        let stored = try JSONEncoder().encode(makeItems(["existing"]))
        env.storedHistory = stored
        legacy.storedHistory = try JSONEncoder().encode(makeItems(["legacy"]))

        ClipboardManager.migrateLegacyHistory(from: legacy.defaults, to: env.defaults)

        #expect(env.storedHistory == stored)
    }

    @Test("Legacy history is copied when there is no history yet")
    func migrationCopiesLegacyHistory() throws {
        let env = TestEnvironment()
        let legacy = TestEnvironment()
        defer { env.cleanUp(); legacy.cleanUp() }
        let legacyData = try JSONEncoder().encode(makeItems(["legacy"]))
        legacy.storedHistory = legacyData

        ClipboardManager.migrateLegacyHistory(from: legacy.defaults, to: env.defaults)

        #expect(env.storedHistory == legacyData)
        #expect(env.makeManager().contents == ["legacy"])
    }

    @Test("Clearing the history also removes the backup and the legacy copy")
    func clearRemovesLeftoverCopies() throws {
        let env = TestEnvironment()
        let legacy = TestEnvironment()
        defer { env.cleanUp(); legacy.cleanUp() }
        env.storedHistory = Data("not json".utf8)
        legacy.storedHistory = try JSONEncoder().encode(makeItems(["secret"]))
        let manager = ClipboardManager(defaults: env.defaults, legacyDefaults: legacy.defaults,
                                       pasteboard: env.pasteboard, startsMonitoring: false)
        #expect(env.backup != nil)

        manager.clearHistory()

        #expect(env.backup == nil)
        #expect(legacy.storedHistory == nil)
    }
}

// MARK: - Keyboard commands

struct KeyCase: CustomTestStringConvertible, Sendable {
    let name: String
    let keyCode: Int
    let modifiers: UInt
    let expected: KeyCommand?

    init(_ name: String, _ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], _ expected: KeyCommand?) {
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.expected = expected
    }

    var testDescription: String { name }
}

@Suite("Keyboard commands")
struct KeyCommandTests {
    @Test("Popover keys map to commands", arguments: [
        KeyCase("↑", kVK_UpArrow, [.function, .numericPad], .moveUp),
        KeyCase("↓", kVK_DownArrow, [.function, .numericPad], .moveDown),
        KeyCase("⌃P", kVK_ANSI_P, .control, .moveUp),
        KeyCase("⌃N", kVK_ANSI_N, .control, .moveDown),
        KeyCase("Page Up", kVK_PageUp, .function, .pageUp),
        KeyCase("Page Down", kVK_PageDown, .function, .pageDown),
        KeyCase("⌘↑", kVK_UpArrow, [.command, .function, .numericPad], .first),
        KeyCase("⌘↓", kVK_DownArrow, [.command, .function, .numericPad], .last),
        KeyCase("Home", kVK_Home, .function, .first),
        KeyCase("End", kVK_End, .function, .last),
        KeyCase("Return", kVK_Return, [], .activate),
        KeyCase("Enter", kVK_ANSI_KeypadEnter, .numericPad, .activate),
        KeyCase("⌘⌫", kVK_Delete, .command, .delete),
        KeyCase("⌘⌦", kVK_ForwardDelete, [.command, .function], .delete),
        KeyCase("Esc", kVK_Escape, [], .escape),
        KeyCase("⌘1", kVK_ANSI_1, .command, .quickPick(0)),
        KeyCase("⌘5", kVK_ANSI_5, .command, .quickPick(4)),
        KeyCase("⌘9", kVK_ANSI_9, .command, .quickPick(8)),
    ])
    func mapsPopoverKeys(_ key: KeyCase) {
        #expect(KeyCommand(keyCode: UInt16(key.keyCode), modifierFlags: NSEvent.ModifierFlags(rawValue: key.modifiers)) == key.expected)
    }

    @Test("Text editing keys go to the search field", arguments: [
        KeyCase("a", kVK_ANSI_A, [], nil),
        KeyCase("⇧A", kVK_ANSI_A, .shift, nil),
        KeyCase("⌫", kVK_Delete, [], nil),
        KeyCase("⌥⌫", kVK_Delete, .option, nil),
        KeyCase("⌘A", kVK_ANSI_A, .command, nil),
        KeyCase("⌘V", kVK_ANSI_V, .command, nil),
        KeyCase("⌘Z", kVK_ANSI_Z, .command, nil),
        KeyCase("⌃K", kVK_ANSI_K, .control, nil),
        KeyCase("←", kVK_LeftArrow, [.function, .numericPad], nil),
        KeyCase("⇧↓", kVK_DownArrow, [.shift, .function, .numericPad], nil),
        KeyCase("⇧Return", kVK_Return, .shift, nil),
        KeyCase("Tab", kVK_Tab, [], nil),
        KeyCase("⌘0", kVK_ANSI_0, .command, nil),
        KeyCase("⌘⇧1", kVK_ANSI_1, [.command, .shift], nil),
    ])
    func leavesEditingKeysAlone(_ key: KeyCase) {
        #expect(KeyCommand(keyCode: UInt16(key.keyCode), modifierFlags: NSEvent.ModifierFlags(rawValue: key.modifiers)) == nil)
    }
}

// MARK: - Popover model

/// Records how the model asked AppDelegate to close the popover.
final class CloseRecorder {
    var reasons: [PopoverCloseReason] = []
}

@MainActor
@Suite("Popover model", .serialized)
struct PopoverModelTests {
    /// A model over a manager with the given history (newest first), opened like AppDelegate does.
    func makeModel(_ env: TestEnvironment, _ contents: [String], recorder: CloseRecorder) -> PopoverModel {
        let manager = env.makeManager()
        manager.clipboardItems = makeItems(contents)
        let model = PopoverModel(manager: manager)
        model.closePopover = { recorder.reasons.append($0) }
        model.prepareForShow()
        return model
    }

    func highlightedContent(_ model: PopoverModel) -> String? {
        let items = model.visibleItems
        let id = model.currentID(in: items)
        return items.first(where: { $0.id == id })?.content
    }

    @Test("The first item is highlighted on open, and arrows move the highlight within bounds")
    func movesHighlight() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"], recorder: CloseRecorder())

        #expect(highlightedContent(model) == "a")
        #expect(model.handle(.moveUp))
        #expect(highlightedContent(model) == "a")
        #expect(model.handle(.moveDown))
        #expect(model.handle(.moveDown))
        #expect(model.handle(.moveDown))
        #expect(highlightedContent(model) == "c")
        #expect(model.handle(.first))
        #expect(highlightedContent(model) == "a")
        #expect(model.handle(.pageDown))
        #expect(highlightedContent(model) == "c")
        #expect(model.handle(.pageUp))
        #expect(highlightedContent(model) == "a")
        #expect(model.handle(.last))
        #expect(highlightedContent(model) == "c")
    }

    @Test("Navigation follows the search results")
    func navigatesSearchResults() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["apple", "banana", "apricot"], recorder: CloseRecorder())

        model.query = "ap"
        #expect(model.visibleItems.map(\.content) == ["apple", "apricot"])
        #expect(highlightedContent(model) == "apple")
        model.handle(.moveDown)
        #expect(highlightedContent(model) == "apricot")
    }

    @Test("Return copies the highlighted item, closes, and moves it to the top only after closing")
    func returnCopiesAndCloses() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let recorder = CloseRecorder()
        let model = makeModel(env, ["a", "b", "c"], recorder: recorder)

        model.handle(.moveDown)
        #expect(model.handle(.activate))

        #expect(env.pasteboardString == "b")
        #expect(model.copiedID == model.manager.clipboardItems[1].id)
        // The list doesn't reorder under the pointer while the popover is still visible.
        #expect(model.manager.contents == ["a", "b", "c"])

        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(recorder.reasons == [.copied])

        model.didClose()
        #expect(model.manager.contents == ["b", "a", "c"])
        #expect(model.copiedID == nil)
    }

    @Test("A second Return while the popover is closing doesn't copy again")
    func ignoresRepeatedCopy() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b"], recorder: CloseRecorder())

        model.handle(.activate)
        model.handle(.moveDown)
        model.handle(.activate)

        #expect(env.pasteboardString == "a")
    }

    @Test("⌘1…⌘9 copy the visible item at that position; out-of-range picks do nothing")
    func quickPick() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"], recorder: CloseRecorder())

        #expect(model.handle(.quickPick(8)))
        #expect(env.pasteboardString == nil)
        #expect(model.copiedID == nil)

        #expect(model.handle(.quickPick(1)))
        #expect(env.pasteboardString == "b")
    }

    @Test("⌘⌫ deletes the highlighted item and highlights the next one")
    func deletesHighlighted() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"], recorder: CloseRecorder())

        model.handle(.moveDown)
        #expect(model.handle(.delete))
        #expect(model.manager.contents == ["a", "c"])
        #expect(highlightedContent(model) == "c")

        // Deleting the last row highlights the one above it.
        #expect(model.handle(.delete))
        #expect(model.manager.contents == ["a"])
        #expect(highlightedContent(model) == "a")
    }

    @Test("While searching, ⌘⌫ is left to the search field")
    func deleteKeepsTextEditingMeaning() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b"], recorder: CloseRecorder())

        model.query = "a"
        #expect(!model.handle(.delete))
        #expect(model.manager.contents == ["a", "b"])
    }

    @Test("Deleting a row that isn't highlighted keeps the highlight")
    func deleteOtherRowKeepsHighlight() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"], recorder: CloseRecorder())

        model.handle(.moveDown)
        model.delete(model.manager.clipboardItems[2])

        #expect(highlightedContent(model) == "b")
    }

    @Test("Esc clears the search first, then closes")
    func escapeClearsThenCloses() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let recorder = CloseRecorder()
        let model = makeModel(env, ["a"], recorder: recorder)

        model.query = "zzz"
        #expect(model.handle(.escape))
        #expect(model.query.isEmpty)
        #expect(recorder.reasons.isEmpty)

        #expect(model.handle(.escape))
        #expect(recorder.reasons == [.dismissed])
    }

    @Test("While the clear confirmation is shown, Return does nothing and Esc dismisses it")
    func confirmationSwallowsKeys() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let recorder = CloseRecorder()
        let model = makeModel(env, ["a", "b"], recorder: recorder)

        model.isConfirmingClear = true
        #expect(model.handle(.activate))
        #expect(model.handle(.delete))
        #expect(env.pasteboardString == nil)
        #expect(model.manager.contents == ["a", "b"])

        #expect(model.handle(.escape))
        #expect(!model.isConfirmingClear)
        #expect(recorder.reasons.isEmpty)
    }

    @Test("Clearing from the popover empties the history and ends the confirmation")
    func clearsHistory() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b"], recorder: CloseRecorder())

        model.isConfirmingClear = true
        model.clearHistory()

        #expect(model.manager.clipboardItems.isEmpty)
        #expect(!model.isConfirmingClear)
    }

    @Test("Opening the popover resets the search, highlight and confirmation")
    func resetsOnOpen() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b"], recorder: CloseRecorder())

        model.query = "b"
        model.handle(.moveDown)
        model.isConfirmingClear = true
        let focusRequest = model.focusRequest

        model.didClose()
        model.prepareForShow()
        model.didShow()

        #expect(model.query.isEmpty)
        #expect(model.highlightedID == nil)
        #expect(!model.isConfirmingClear)
        #expect(highlightedContent(model) == "a")
        #expect(model.focusRequest != focusRequest)
    }
}

// MARK: - Review regressions

@Suite("Detection edge cases")
struct DetectionEdgeCaseTests {
    @Test("Chat messages, lists and UI paths are text", arguments: [
        "git is confusing",
        "docker is eating all my RAM",
        "ssh keys are set up now",
        "swift is fun",
        "ls output looks weird on my machine",
        "cd player is broken",
        "python3 is installed but pip isn't",
        "cp the file to the shared drive when you get a chance",
        "Groceries\nbrew coffee\nbuy milk",
        "Shopping list:\n- milk\n- eggs\n  - free range\n- return library books",
        "Hi team,\n\n  Please return the signed forms by Friday.\n\nThanks",
        "Open Settings (gear icon) -> Privacy & Security",
        "Revenue (Q3) -> up 12%",
        "main.rs",
        "lib.rs",
        "main.cc",
    ])
    func prose(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .text)
    }

    @Test("Common commands and closures are code", arguments: [
        "swift build",
        "npm run build",
        "brew install wget",
        "pip install requests",
        "docker compose up",
        "cd ClipboardManager",
        "ssh myserver",
        "ls -la",
        "rm -rf build/",
        "$ make install",
        "arr.map((x) => x * 2)",
        "const double = (x) => x * 2",
    ])
    func code(_ input: String) {
        #expect(ClipboardContentType.detectType(for: input) == .code)
    }

    @Test("Links longer than 2,048 characters are still links")
    func longLink() {
        let link = "https://example.com/saml?SAMLRequest=" + String(repeating: "a", count: 3000)
        #expect(ClipboardContentType.detectType(for: link) == .url)
        #expect(ClipboardItem(content: link).detail == "example.com")
    }

    @Test("Long runs of blank lines are classified quickly")
    func blankLinePerformance() {
        let inputs = [
            "a" + String(repeating: "\n", count: 4000) + "b",
            "Name\tAge\n" + String(repeating: "\t\t\n", count: 1500) + "Bob\t30",
            String(repeating: "    \n", count: 1000) + "x",
        ]
        let start = Date()
        for input in inputs {
            _ = ClipboardContentType.detectType(for: input)
        }
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test("Link details show the host as written", arguments: [
        ("file:///Users/x/a.txt", nil),
        ("münchen.de/karte", "münchen.de"),
        ("ssh://git@github.com/x.git", "github.com"),
        ("https://www.apple.com:443/mac?x=1", "apple.com"),
    ] as [(String, String?)])
    func linkDetail(_ input: String, _ expected: String?) {
        let item = ClipboardItem(content: input)
        #expect(item.contentType == .url)
        #expect(item.detail == expected)
    }

    @Test("Every kind of line break counts", arguments: ["a\rb\rc", "a\u{2028}b\u{2028}c", "a\r\nb\r\nc"])
    func lineBreaks(_ input: String) {
        #expect(ClipboardItem(content: input).lineCount == 3)
    }
}

@MainActor
@Suite("History limits", .serialized)
struct HistoryLimitTests {
    @Test("Recording into a full history never publishes more than maxItems")
    func noOverLimitEmission() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let manager = env.makeManager(maxItems: 3)
        manager.clipboardItems = makeItems(["3", "2", "1"])
        var counts: [Int] = []
        let subscription = manager.$clipboardItems.sink { counts.append($0.count) }

        manager.record("4")

        subscription.cancel()
        #expect(counts.allSatisfy { $0 <= 3 })
        #expect(manager.contents == ["4", "3", "2"])
    }
}

@MainActor
@Suite("Popover model after review", .serialized)
struct PopoverModelReviewTests {
    func makeModel(_ env: TestEnvironment, _ contents: [String], maxItems: Int = ClipboardManager.defaultMaxItems) -> PopoverModel {
        let manager = env.makeManager(maxItems: maxItems)
        manager.clipboardItems = makeItems(contents)
        let model = PopoverModel(manager: manager)
        model.prepareForShow()
        return model
    }

    @Test("Typing a query makes the top match current again")
    func queryResetsHighlight() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["apple one", "banana", "apple two"])

        model.handle(.last)
        model.query = "apple"

        #expect(model.highlightedID == nil)
        #expect(model.currentID(in: model.visibleItems) == model.manager.clipboardItems[0].id)
    }

    @Test("Only keyboard moves request scrolling")
    func keyboardScrollOnly() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"])
        let before = model.keyboardScrollRequest

        model.hover(model.manager.clipboardItems[2])
        #expect(model.keyboardScrollRequest == before)

        model.handle(.moveDown)
        #expect(model.keyboardScrollRequest != before)
    }

    @Test("Deleting the last item ends the clear confirmation")
    func deleteLastEndsConfirmation() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a"])

        model.isConfirmingClear = true
        model.delete(model.manager.clipboardItems[0])

        #expect(!model.isConfirmingClear)
    }

    @Test("A copied item pushed out of a full history comes back when the popover closes")
    func evictedCopyIsRestored() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let model = makeModel(env, ["a", "b", "c"], maxItems: 3)

        model.handle(.last)
        model.handle(.activate)
        // Another app copies before the popover closes; the full history drops "c".
        env.copyExternally("external")
        model.manager.checkClipboard()
        #expect(!model.manager.contents.contains("c"))

        model.didClose()

        #expect(model.manager.contents.first == "c")
        #expect(model.manager.contents.contains("external"))
    }
}
