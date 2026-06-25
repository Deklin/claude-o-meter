#!/usr/bin/env bash
# Build ClaudeCostBar.app (a menu-bar agent, no Dock icon) from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeCostBar"
BUNDLE_ID="com.claudecostbar.app"
DIST="dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN_PATH/$APP_NAME" "$MACOS/$APP_NAME"

# Copy the SwiftPM resource bundle (contains pricing.json) next to the binary.
if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$MACOS/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Claude Cost</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local cost tracker for Claude Code.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so notifications/launch behave on a local machine.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "    (codesign skipped)"

echo "==> done: $APP"
echo "    Run:    open $APP"
echo "    Install: cp -R $APP /Applications/"
