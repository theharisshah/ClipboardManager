import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var selectedItems = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var hoveredItem: UUID?
    
    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.clipboardItems
        } else {
            return clipboardManager.clipboardItems.filter { 
                $0.content.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section
            headerView
            
            // Search section
            searchSection
            
            // Content section
            contentSection
            
            // Footer section
            footerView
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 450, minHeight: 550)
        .confirmationDialog(
            "Are you sure?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    clipboardManager.clearHistory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all clipboard items.")
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clipboard Manager")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("\(clipboardManager.clipboardItems.count) items")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Label("Clear All", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .disabled(clipboardManager.clipboardItems.isEmpty)
                
                Button(action: {
                    NSApplication.shared.keyWindow?.close()
                }) {
                    Label("Close", systemImage: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var searchSection: some View {
        VStack(spacing: 12) {
            ModernSearchBar(text: $searchText)
                .padding(.horizontal, 20)
            
            if !filteredItems.isEmpty {
                HStack {
                    Text("\(filteredItems.count) \(filteredItems.count == 1 ? "item" : "items")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var contentSection: some View {
        ScrollView {
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(filteredItems) { item in
                        ModernClipboardItemRow(
                            item: item,
                            isHovered: hoveredItem == item.id,
                            onCopy: {
                                clipboardManager.copyToClipboard(item: item)
                                // Show brief feedback
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    // Could add a toast notification here
                                }
                            },
                            onDelete: {
                                if let index = clipboardManager.clipboardItems.firstIndex(of: item) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        clipboardManager.removeItem(at: IndexSet(integer: index))
                                    }
                                }
                            }
                        )
                        .onHover { hovering in
                            hoveredItem = hovering ? item.id : nil
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No clipboard items yet" : "No matching items")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                
                if searchText.isEmpty {
                    Text("Copy something to get started!")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } else {
                    Text("Try a different search term")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var footerView: some View {
        HStack {
            Text("Press ⌘+Shift+V to show/hide • Click any item to copy")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if clipboardManager.clipboardItems.isEmpty {
                Text("No items yet")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

struct ModernSearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("Search clipboard items...", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 14))
                .onSubmit {
                    isFocused = false
                }
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.blue : Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

struct ModernClipboardItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Content type indicator
            VStack {
                Image(systemName: item.contentType.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(item.contentType.color)
                    .frame(width: 24, height: 24)
                    .background(item.contentType.color.opacity(0.1))
                    .cornerRadius(6)
                Spacer()
            }
            
            // Content area
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 8) {
                    Label(formattedDate(item.timestamp), systemImage: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text(item.contentType.rawValue.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(item.contentType.color)
                    
                    Spacer()
                    
                    Text("\(item.content.count) chars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete item")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(isPressed ? Color.blue.opacity(0.1) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onCopy()
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: 10) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .contextMenu {
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true {
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ClipboardManager())
    }
}
