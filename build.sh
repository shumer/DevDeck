#!/bin/bash
# Build DevDeck.app (ad-hoc signed) from the SwiftPM package.
#
# The suite runs first: shipping a build with broken core logic is worse than not building.
# Pass --skip-tests to bypass that (CI should not).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/DevDeck.app"
MACOS="$APP/Contents/MacOS"

if [ "${1:-}" != "--skip-tests" ]; then
  echo "Running tests…"
  swift run --package-path "$HERE" DevDeckTests | tail -3
fi

# Version: the marketing number lives in VERSION and is bumped by hand; the build number is
# the commit count, so it always advances and cannot be forgotten.
SHORT_VERSION="$(tr -d '[:space:]' < "$HERE/VERSION" 2>/dev/null || echo 0.0)"
BUILD_NUMBER="$(git -C "$HERE" rev-list --count HEAD 2>/dev/null || echo 1)"
echo "Building v$SHORT_VERSION ($BUILD_NUMBER)…"
swift build --package-path "$HERE" -c release --product DevDeck

rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DevDeck</string>
  <key>CFBundleDisplayName</key><string>DevDeck</string>
  <key>CFBundleIdentifier</key><string>com.shumer.devdeck</string>
  <key>CFBundleExecutable</key><string>DevDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>DevDeck</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Agent app: no Dock icon, no application menu. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# The icon is drawn in code, so it is rendered here rather than checked in: every size comes
# from the drawing instead of being resampled from the largest one, and it cannot go stale
# against the source the way an exported PNG does.
swift build --package-path "$HERE" -c release --product AppIconExport >/dev/null
ICONSET="$(mktemp -d)/DevDeck.iconset"
"$(swift build --package-path "$HERE" -c release --show-bin-path)/AppIconExport" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/DevDeck.icns"
rm -rf "$(dirname "$ICONSET")"

cp "$(swift build --package-path "$HERE" -c release --show-bin-path)/DevDeck" "$MACOS/DevDeck"
chmod +x "$MACOS/DevDeck"
codesign --force --sign - "$APP" 2>/dev/null || echo "(ad-hoc signing skipped)"

echo "Built: $APP"

# Installing is the default. macOS registers the login item by path, and this directory's
# bundle is deleted and recreated on every build, so the copy that actually runs must live
# in /Applications - otherwise a rebuild leaves the old version running.
if [ "${1:-}" = "--no-install" ] || [ "${2:-}" = "--no-install" ]; then
  echo "Run:   open '$APP'    Quit: pkill -f DevDeck"
  exit 0
fi

DEST="/Applications/DevDeck.app"
WAS_RUNNING=""
pgrep -f "DevDeck.app/Contents/MacOS/DevDeck" >/dev/null && WAS_RUNNING=1
pkill -f "DevDeck.app/Contents/MacOS/DevDeck" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
open "$DEST"
echo "Installed and launched: $DEST  (v$SHORT_VERSION build $BUILD_NUMBER)"
[ -n "$WAS_RUNNING" ] && echo "Replaced the running instance."
exit 0
