# ClipboardManager

A macOS application that helps you keep track of your clipboard history, similar to PastPal. ClipboardManager runs in the menu bar and allows you to access your previously copied items for later use.

## Features

- Monitors clipboard changes automatically
- Stores clipboard history with timestamps
- Allows searching through clipboard history
- Copy any previous item back to the clipboard with a single click
- Delete individual items or clear entire history
- Persists clipboard history between app launches
- Menu bar application for easy access

## Requirements

- macOS 11.0 (Big Sur) or later
- Xcode 13.0 or later (for building from source)
- Swift 5.5 or later

## Building from Source

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/ClipboardManager.git
   cd ClipboardManager
   ```

2. Build using Swift Package Manager:
   ```
   swift build
   ```

3. Run the application:
   ```
   swift run
   ```

4. For a release build:
   ```
   swift build -c release
   ```

5. The built application will be in `.build/release/ClipboardManager`

## Usage

1. Launch the application. It will appear as a clipboard icon in the menu bar.

2. Click on the menu bar icon to:
   - Open the clipboard history window
   - Quit the application

3. In the clipboard history window:
   - Click on any item to copy it to the clipboard
   - Use the search bar to filter items
   - Right-click on an item for additional options (copy, delete)
   - Click "Clear All" to remove all items from history

4. The application automatically monitors your clipboard and adds new items to the history.

## How It Works

ClipboardManager uses a timer to check the system clipboard for changes every second. When a change is detected, the new content is added to the history. The history is stored using UserDefaults for persistence between app launches.

## Customization

You can modify the following aspects of the application:

- Maximum number of items to store: Edit the `maxItems` property in `ClipboardManager.swift`
- Clipboard check frequency: Modify the timer interval in `startMonitoring()` method
- UI appearance: Customize the SwiftUI views in `ContentView.swift`

## License

This project is available under the MIT License. See the LICENSE file for more information.
