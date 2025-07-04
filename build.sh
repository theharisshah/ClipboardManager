#!/bin/bash

# Build script for Clipboard Manager
echo "Building Clipboard Manager..."

# Clean previous builds
rm -rf .build

# Build the app
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Run the app with: .build/release/ClipboardManager"
    echo "Or run directly with: swift run"
else
    echo "❌ Build failed!"
    exit 1
fi 