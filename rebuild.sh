#!/bin/bash
# Build Glean, wrap it in a signed .app bundle (agent app), and launch.
# A bundle is required for drag-out. Pass "release" for an optimized build.
set -e
cd "$(dirname "$0")"

pkill -f "Glean.app/Contents/MacOS/Glean" 2>/dev/null || true
sleep 0.5

CONFIG="${1:-debug}"
swift build -c "$CONFIG" >/dev/null
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Glean"

APP="build/Glean.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glean"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
[ -f Packaging/AppIcon.icns ] && cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1

open "$APP"
sleep 2
pgrep -f "Glean.app/Contents/MacOS/Glean" >/dev/null && echo "RUNNING ($APP)" || echo "NOT RUNNING — check for a crash"
