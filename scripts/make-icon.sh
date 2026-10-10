#!/bin/bash
#
# Regenerates the app icon from scripts/generate-icon.swift:
#   assets/AppIcon.icns          used by build.sh for the app and the DMG volume
#   assets/AppIcon.png           1024 px master (README)
#   dist/AppIcon-preview.png     every size on light and dark backgrounds, for review
#
# Usage: scripts/make-icon.sh

set -euo pipefail
cd "$(dirname "$0")/.."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "🎨 Rendering the app icon..."
swiftc -O scripts/generate-icon.swift -o "$WORK_DIR/generate-icon"
"$WORK_DIR/generate-icon" "$WORK_DIR/out"
[ -f "$WORK_DIR/out/AppIcon.icns" ] || { echo "❌ iconutil didn't produce AppIcon.icns"; exit 1; }

mkdir -p assets dist
cp "$WORK_DIR/out/AppIcon.icns" assets/AppIcon.icns
cp "$WORK_DIR/out/AppIcon-1024.png" assets/AppIcon.png
cp "$WORK_DIR/out/preview.png" dist/AppIcon-preview.png

echo "✅ Updated assets/AppIcon.icns and assets/AppIcon.png"
echo "   Preview: dist/AppIcon-preview.png"
