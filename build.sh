#!/bin/bash
#
# Build script for Clipboard Manager.
# Builds a release binary and packages it as dist/ClipboardManager.app.
#
# Usage: ./build.sh [--clean]
#   --clean   run `swift package clean` before building

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipboardManager"
APP_DIR="dist/${APP_NAME}.app"
INFO_PLIST="ClipboardManager/Info.plist"

CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        -h|--help)
            echo "Usage: ./build.sh [--clean]"
            echo "  --clean   run 'swift package clean' before building"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

fail() {
    echo "❌ $1"
    exit 1
}

if [ "$CLEAN" -eq 1 ]; then
    echo "🧹 Cleaning previous build..."
    swift package clean || fail "Clean failed!"
fi

echo "🔨 Building Clipboard Manager (release)..."
swift build -c release || fail "Build failed!"

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="${BIN_DIR}/${APP_NAME}"
[ -f "$BINARY" ] || fail "Built binary not found at $BINARY"

echo "📦 Packaging ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint -s "$APP_DIR/Contents/Info.plist" || fail "Info.plist is invalid!"
fi

if command -v codesign >/dev/null 2>&1; then
    echo "🔏 Signing (ad-hoc)..."
    if ! codesign --force --sign - "$APP_DIR"; then
        echo "⚠️  Ad-hoc signing failed; the app may not launch until it is signed."
    fi
else
    echo "⚠️  codesign not found; skipping ad-hoc signing."
fi

echo ""
echo "✅ Build successful! → ${APP_DIR}"
echo ""
echo "Next steps:"
echo "  • Run it:      open ${APP_DIR}"
echo "  • Install it:  drag ${APP_DIR} into /Applications"
echo "                 (or: cp -R ${APP_DIR} /Applications/)"
echo "  • Develop:     swift run"
