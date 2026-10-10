#!/bin/bash
#
# Runs the unit tests (Swift Testing) without launching the app or touching
# your clipboard or saved history.
#
# With full Xcode 16+ installed, plain `swift test` works. With only the
# Command Line Tools, SwiftPM needs to be pointed at the CLT's Testing.framework
# (and the CLT's broken _Testing_Foundation cross-import overlay disabled),
# which this script does automatically.
#
# Usage: ./test.sh [extra swift test arguments, e.g. --filter SomeTest]

set -euo pipefail
cd "$(dirname "$0")"

CLT_DIR="/Library/Developer/CommandLineTools"
FW="${CLT_DIR}/Library/Developer/Frameworks"

echo "🧪 Testing Clipboard Manager..."

status=0
if [ "$(xcode-select -p 2>/dev/null || true)" = "$CLT_DIR" ] && [ -d "${FW}/Testing.framework" ]; then
    echo "   (Command Line Tools detected: using the CLT's Testing.framework)"
    swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        "$@" || status=$?
else
    swift test "$@" || status=$?
fi

if [ "$status" -eq 0 ]; then
    echo "✅ All tests passed!"
else
    echo "❌ Tests failed (exit code $status)"
fi
exit "$status"
