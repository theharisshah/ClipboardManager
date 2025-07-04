import XCTest
@testable import ClipboardManager

final class ClipboardManagerTests: XCTestCase {
    
    var clipboardManager: ClipboardManager!
    
    override func setUp() {
        super.setUp()
        clipboardManager = ClipboardManager()
        clipboardManager.clearHistory()
    }
    
    override func tearDown() {
        clipboardManager.clearHistory()
        super.tearDown()
    }
    
    func testClipboardItemEquality() {
        let id = UUID()
        let content = "Test content"
        let timestamp = Date()
        
        let item1 = ClipboardItem(content: content, timestamp: timestamp, id: id)
        let item2 = ClipboardItem(content: content, timestamp: timestamp, id: id)
        
        XCTAssertEqual(item1, item2)
        
        let item3 = ClipboardItem(content: content, timestamp: timestamp, id: UUID())
        XCTAssertNotEqual(item1, item3)
    }
    
    func testClipboardItemInitialization() {
        let content = "Test content"
        let item = ClipboardItem(content: content)
        
        XCTAssertEqual(item.content, content)
        XCTAssertNotNil(item.id)
        XCTAssertNotNil(item.timestamp)
    }
    
    func testClipboardItemEncoding() {
        let content = "Test content"
        let item = ClipboardItem(content: content)
        
        XCTAssertNoThrow(try JSONEncoder().encode(item))
        
        let encoder = JSONEncoder()
        let data = try! encoder.encode(item)
        let decoder = JSONDecoder()
        let decodedItem = try! decoder.decode(ClipboardItem.self, from: data)
        
        XCTAssertEqual(item, decodedItem)
        XCTAssertEqual(item.content, decodedItem.content)
    }
    
    func testClearHistory() {
        // Add some test items
        let item1 = ClipboardItem(content: "Item 1")
        let item2 = ClipboardItem(content: "Item 2")
        
        clipboardManager.clipboardItems = [item1, item2]
        XCTAssertEqual(clipboardManager.clipboardItems.count, 2)
        
        clipboardManager.clearHistory()
        XCTAssertEqual(clipboardManager.clipboardItems.count, 0)
    }
    
    func testRemoveItem() {
        let item1 = ClipboardItem(content: "Item 1")
        let item2 = ClipboardItem(content: "Item 2")
        let item3 = ClipboardItem(content: "Item 3")
        
        clipboardManager.clipboardItems = [item1, item2, item3]
        
        let indexSet = IndexSet(integer: 1)
        clipboardManager.removeItem(at: indexSet)
        
        XCTAssertEqual(clipboardManager.clipboardItems.count, 2)
        XCTAssertTrue(clipboardManager.clipboardItems.contains(item1))
        XCTAssertFalse(clipboardManager.clipboardItems.contains(item2))
        XCTAssertTrue(clipboardManager.clipboardItems.contains(item3))
    }
    
    func testMaxItemsLimit() {
        let maxItems = 50
        
        // Add more than the maximum number of items
        for i in 0..<60 {
            let item = ClipboardItem(content: "Item \(i)")
            clipboardManager.clipboardItems.insert(item, at: 0)
        }
        
        // The manager should trim to max items when saving
        XCTAssertLessThanOrEqual(clipboardManager.clipboardItems.count, maxItems)
    }
    
    func testCopyToClipboard() {
        let item1 = ClipboardItem(content: "Item 1")
        let item2 = ClipboardItem(content: "Item 2")
        let item3 = ClipboardItem(content: "Item 3")
        
        clipboardManager.clipboardItems = [item1, item2, item3]
        
        // Copy item3 (at index 2) to clipboard
        clipboardManager.copyToClipboard(item: item3)
        
        // item3 should now be at the top of the list
        XCTAssertEqual(clipboardManager.clipboardItems.first, item3)
        XCTAssertEqual(clipboardManager.clipboardItems.count, 3)
    }
    
    func testPersistence() {
        let item1 = ClipboardItem(content: "Persistent Item 1")
        let item2 = ClipboardItem(content: "Persistent Item 2")
        
        clipboardManager.clipboardItems = [item1, item2]
        
        // Create a new manager to test loading
        let newManager = ClipboardManager()
        
        // Wait a bit for async loading
        let expectation = XCTestExpectation(description: "Wait for loading")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(newManager.clipboardItems.count, 2)
        XCTAssertTrue(newManager.clipboardItems.contains(item1))
        XCTAssertTrue(newManager.clipboardItems.contains(item2))
    }
    
    func testDuplicateContent() {
        let content = "Same content"
        let item1 = ClipboardItem(content: content)
        let item2 = ClipboardItem(content: content)
        
        clipboardManager.clipboardItems = [item1]
        
        // Simulate adding a duplicate - this should be handled in the monitoring logic
        // For now, just test that we can detect duplicates
        XCTAssertEqual(item1.content, item2.content)
        XCTAssertNotEqual(item1, item2) // Different IDs
    }
    
    func testTimestampOrdering() {
        let now = Date()
        let pastTime = now.addingTimeInterval(-3600) // 1 hour ago
        let futureTime = now.addingTimeInterval(3600) // 1 hour from now
        
        let item1 = ClipboardItem(content: "Past", timestamp: pastTime)
        let item2 = ClipboardItem(content: "Present", timestamp: now)
        let item3 = ClipboardItem(content: "Future", timestamp: futureTime)
        
        clipboardManager.clipboardItems = [item1, item2, item3]
        
        XCTAssertTrue(item1.timestamp < item2.timestamp)
        XCTAssertTrue(item2.timestamp < item3.timestamp)
    }
} 