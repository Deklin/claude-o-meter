#!/usr/bin/env bash
# One-line installer for Claude-o-Meter.
# Usage: curl -fsSL https://raw.githubusercontent.com/Deklin/claude-o-meter/master/scripts/install.sh | bash
set -euo pipefail

REPO="Deklin/claude-o-meter"
APP_NAME="ClaudeOMeter"
INSTALL_DIR="$HOME/Applications"

echo "==> Fetching latest release..."
API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_JSON=$(curl -fsSL "$API_URL")

TAG=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
assets = json.load(sys.stdin)['assets']
match = next((a['browser_download_url'] for a in assets if a['name'].endswith('.zip')), None)
if not match:
    raise SystemExit('No .zip asset found in latest release')
print(match)
")

echo "==> Downloading $APP_NAME $TAG..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.zip"

echo "==> Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
unzip -q "$TMP_DIR/$APP_NAME.zip" -d "$TMP_DIR"

# Remove any previous install
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"

echo "==> Clearing Gatekeeper quarantine..."
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

echo "==> Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "    Claude-o-Meter $TAG installed to $INSTALL_DIR/$APP_NAME.app"
echo "    The menu-bar icon will appear within a few seconds."
