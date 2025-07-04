import SwiftUI
import Combine

class ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let content: String
    let timestamp: Date
    let contentType: ClipboardContentType
    
    init(content: String, timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.contentType = ClipboardContentType.detectType(for: content)
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    var preview: String {
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isURL: Bool {
        return contentType == .url
    }
    
    var isEmail: Bool {
        return contentType == .email
    }
}

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case url
    case email
    case number
    case code
    case json
    
    static func detectType(for content: String) -> ClipboardContentType {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for URL
        if let url = URL(string: trimmed), url.scheme != nil {
            return .url
        }
        
        // Check for email
        if trimmed.contains("@") && trimmed.contains(".") {
            let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
            if trimmed.range(of: emailRegex, options: .regularExpression) != nil {
                return .email
            }
        }
        
        // Check for number
        if Double(trimmed) != nil {
            return .number
        }
        
        // Check for JSON
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || 
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            do {
                _ = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
                return .json
            } catch {
                // Not valid JSON
            }
        }
        
        // Check for code (simple heuristic)
        let codeKeywords = ["func", "class", "struct", "import", "return", "if", "else", "for", "while", "var", "let", "const", "function", "def", "public", "private"]
        if codeKeywords.contains(where: trimmed.lowercased().contains) {
            return .code
        }
        
        return .text
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
    
    var color: Color {
        switch self {
        case .text: return .primary
        case .url: return .blue
        case .email: return .green
        case .number: return .orange
        case .code: return .purple
        case .json: return .pink
        }
    }
}

class ClipboardManager: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = [] {
        didSet {
            saveItems()
        }
    }
    
    @Published var isMonitoring: Bool = false
    @Published var lastError: String?
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let maxItems = 100
    private let userDefaultsKey = "ClipboardManagerItems"
    private let minClipboardLength = 1
    private let maxClipboardLength = 10000
    
    init() {
        loadItems()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(clipboardItems)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            lastError = "Failed to save clipboard items: \(error.localizedDescription)"
            print("Failed to save clipboard items: \(error)")
        }
    }
    
    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        
        do {
            let items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            clipboardItems = items
        } catch {
            lastError = "Failed to load clipboard items: \(error.localizedDescription)"
            print("Failed to load clipboard items: \(error)")
        }
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        // Initialize the change count
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Check clipboard every 0.5 seconds for better responsiveness
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        isMonitoring = true
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        
        // Only process if the pasteboard has changed
        guard changeCount != lastChangeCount else { return }
        
        lastChangeCount = changeCount
        
        guard let string = pasteboard.string(forType: .string),
              !string.isEmpty,
              string.count >= minClipboardLength,
              string.count <= maxClipboardLength else { return }
        
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        // Don't add duplicates of the most recent item
        if let firstItem = clipboardItems.first, firstItem.content == trimmedString {
            return
        }
        
        // Add new item at the beginning of the array
        DispatchQueue.main.async {
            let newItem = ClipboardItem(content: trimmedString)
            self.clipboardItems.insert(newItem, at: 0)
            
            // Limit the number of items
            if self.clipboardItems.count > self.maxItems {
                self.clipboardItems = Array(self.clipboardItems.prefix(self.maxItems))
            }
        }
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Temporarily stop monitoring to avoid circular updates
        let wasMonitoring = isMonitoring
        if wasMonitoring {
            stopMonitoring()
        }
        
        let success = pasteboard.setString(item.content, forType: .string)
        
        // Restart monitoring after a brief delay
        if wasMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startMonitoring()
            }
        }
        
        if success {
            // Move the item to the top of the list
            if let index = clipboardItems.firstIndex(of: item), index != 0 {
                DispatchQueue.main.async {
                    self.clipboardItems.remove(at: index)
                    self.clipboardItems.insert(item, at: 0)
                }
            }
        } else {
            lastError = "Failed to copy item to clipboard"
        }
    }
    
    func clearHistory() {
        clipboardItems.removeAll()
        lastError = nil
    }
    
    func removeItem(at indexSet: IndexSet) {
        clipboardItems.remove(atOffsets: indexSet)
    }
    
    func removeItem(_ item: ClipboardItem) {
        if let index = clipboardItems.firstIndex(of: item) {
            clipboardItems.remove(at: index)
        }
    }
    
    func searchItems(query: String) -> [ClipboardItem] {
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
