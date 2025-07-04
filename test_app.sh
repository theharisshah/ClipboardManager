#!/bin/bash

echo "🧪 Testing ClipboardManager..."
echo "=============================="

# Check if build exists
if [ ! -f ".build/release/ClipboardManager" ]; then
    echo "❌ App not built. Run './build.sh' first."
    exit 1
fi

echo "✅ Build exists"

# Test basic functionality
echo "📋 Testing basic functionality..."
echo "1. Run the app in the background for 5 seconds"
echo "2. Copy some test text"
echo "3. Check if the app is running"

# Start the app in background
.build/release/ClipboardManager &
APP_PID=$!

# Give it time to start
sleep 2

# Copy some test text
echo "Test clipboard content $(date)" | pbcopy
echo "   → Copied test text to clipboard"

# Check if app is still running
if kill -0 $APP_PID 2>/dev/null; then
    echo "✅ App is running (PID: $APP_PID)"
else
    echo "❌ App crashed or failed to start"
    exit 1
fi

# Let it run for a bit more
sleep 3

# Kill the app
kill $APP_PID 2>/dev/null

echo ""
echo "🎉 Basic test completed successfully!"
echo ""
echo "To test the full functionality:"
echo "1. Run: swift run"
echo "2. Copy some text"
echo "3. Press ⌘+Shift+V to open the clipboard manager"
echo "4. Click the menu bar icon to access options"
echo ""
echo "Happy clipboard managing! 📋✨" 