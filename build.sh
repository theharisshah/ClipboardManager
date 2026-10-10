#!/bin/bash
#
# Build script for Clipboard Manager.
# Builds a release binary and packages it as dist/ClipboardManager.app.
#
# Usage: ./build.sh [--clean] [--dmg]
#   --clean   run `swift package clean` before building
#   --dmg     build a universal app (Apple Silicon + Intel) and package it as
#             dist/ClipboardManager-<version>.dmg

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipboardManager"
DISPLAY_NAME="Clipboard Manager"
APP_DIR="dist/${APP_NAME}.app"
INFO_PLIST="ClipboardManager/Info.plist"
ICON="assets/AppIcon.icns"

CLEAN=0
DMG=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        --dmg) DMG=1 ;;
        -h|--help)
            echo "Usage: ./build.sh [--clean] [--dmg]"
            echo "  --clean   run 'swift package clean' before building"
            echo "  --dmg     build a universal app (Apple Silicon + Intel) and package it"
            echo "            as dist/${APP_NAME}-<version>.dmg"
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

WORK_DIR="$(mktemp -d)"
cleanup() {
    if [ -d "$WORK_DIR/mnt" ]; then
        hdiutil detach -quiet "$WORK_DIR/mnt" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")"

if [ "$CLEAN" -eq 1 ]; then
    echo "🧹 Cleaning previous build..."
    swift package clean || fail "Clean failed!"
fi

if [ "$DMG" -eq 1 ]; then
    echo "🔨 Building Clipboard Manager ${VERSION} (release, Apple Silicon + Intel)..."
    SLICES=()
    for ARCH in arm64 x86_64; do
        TRIPLE="${ARCH}-apple-macosx${MIN_MACOS}"
        swift build -c release --triple "$TRIPLE" || fail "Build for ${ARCH} failed!"
        SLICES+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/${APP_NAME}")
    done
    BINARY="${WORK_DIR}/${APP_NAME}"
    lipo -create "${SLICES[@]}" -output "$BINARY" || fail "Couldn't combine the Apple Silicon and Intel builds!"
else
    echo "🔨 Building Clipboard Manager (release)..."
    swift build -c release || fail "Build failed!"
    BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi
[ -f "$BINARY" ] || fail "Built binary not found at $BINARY"

echo "📦 Packaging ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
if [ -f "$ICON" ]; then
    cp "$ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "⚠️  ${ICON} not found; the app will use the generic icon."
fi

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

if [ "$DMG" -eq 1 ]; then
    DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
    echo "💿 Creating ${DMG_PATH}..."

    # The window shows the app next to an Applications shortcut, so installing is a drag.
    STAGE="${WORK_DIR}/stage"
    mkdir -p "$STAGE"
    cp -R "$APP_DIR" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    if [ -f "$ICON" ]; then
        cp "$ICON" "$STAGE/.VolumeIcon.icns"
    fi

    # Build a writable image first so the volume icon can be switched on, then compress it.
    hdiutil create -quiet -volname "${DISPLAY_NAME} ${VERSION}" -srcfolder "$STAGE" \
        -fs HFS+ -format UDRW -ov "${WORK_DIR}/rw.dmg" || fail "Couldn't create the disk image!"
    if [ -f "$ICON" ]; then
        mkdir -p "${WORK_DIR}/mnt"
        hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "${WORK_DIR}/mnt" "${WORK_DIR}/rw.dmg" \
            || fail "Couldn't mount the disk image!"
        # Mark the volume as having a custom icon (Finder's kHasCustomIcon flag).
        if command -v SetFile >/dev/null 2>&1; then
            SetFile -a C "${WORK_DIR}/mnt"
        else
            xattr -wx com.apple.FinderInfo \
                "0000000000000000040000000000000000000000000000000000000000000000" "${WORK_DIR}/mnt"
        fi
        hdiutil detach -quiet "${WORK_DIR}/mnt" || fail "Couldn't unmount the disk image!"
        rmdir "${WORK_DIR}/mnt"
    fi
    rm -f "$DMG_PATH"
    hdiutil convert -quiet "${WORK_DIR}/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" \
        || fail "Couldn't compress the disk image!"
    hdiutil verify -quiet "$DMG_PATH" || fail "The disk image failed verification!"
    DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
fi

echo ""
echo "✅ Build successful! → ${APP_DIR}"
if [ "$DMG" -eq 1 ]; then
    echo "💿 Disk image:  ${DMG_PATH}"
    echo "   SHA-256:     ${DMG_SHA256}"
fi
echo ""
echo "Next steps:"
echo "  • Run it:      open ${APP_DIR}"
echo "  • Install it:  drag ${APP_DIR} into /Applications"
echo "                 (or: cp -R ${APP_DIR} /Applications/)"
if [ "$DMG" -eq 1 ]; then
    echo "  • Release it:  gh release create v${VERSION} ${DMG_PATH}"
fi
echo "  • Develop:     swift run"
