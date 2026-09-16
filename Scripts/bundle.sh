#!/usr/bin/env bash
# Assembles PRRadar.app.
#
# This is not cosmetic: an unbundled SwiftPM binary has no bundle identifier,
# and UNUserNotificationCenter traps when asked for the current center in that
# state. Notifications only work from a real bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/PRRadar.app"
BUNDLE_ID="com.rogelioacosta.prradar"
VERSION="1.7.0"

echo "==> building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BINARY="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/PRRadar"
[ -f "$BINARY" ] || { echo "binary not found at $BINARY" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/PRRadar"

echo "==> generating icon"
if swift "$ROOT/Scripts/make-icon.swift" "$ROOT/.build" >/dev/null 2>&1 \
   && iconutil -c icns "$ROOT/.build/AppIcon.iconset" \
        -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  ICON_KEY='<key>CFBundleIconFile</key><string>AppIcon</string>'
else
  # Worth shouting about: the bundle then declares no icon at all, and what a
  # notification banner shows in that case is whatever the icon cache still
  # holds — which looks exactly like the icon simply not having changed.
  echo "    !! icon generation FAILED - app will ship with no icon of its own" >&2
  ICON_KEY=''
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PRRadar</string>
  <key>CFBundleDisplayName</key><string>PR Radar</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>PRRadar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Agent app: no Dock icon, no menu bar. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  $ICON_KEY
</dict>
</plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  || echo "    (codesign failed; app will still run locally)"

echo "==> done: $APP"
