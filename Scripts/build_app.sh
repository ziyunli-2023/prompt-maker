#!/usr/bin/env bash
# Build PromptMaker and wrap the binary into a proper macOS .app bundle.
#
# Why this exists: macOS Sequoia ignores Carbon RegisterEventHotKey events for
# raw binaries that aren't part of a real .app bundle with an Info.plist.
# After wrapping, global hotkeys start working.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="PromptMaker"
BUNDLE_ID="com.local.promptmaker"
VERSION="0.1.0"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR=".build/$CONFIG"
[ -f "$BIN_DIR/$APP_NAME" ] || BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "binary not found at $BIN"; exit 1; }

APP_DIR="build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

# Ad-hoc code sign so macOS treats the bundle as a proper signed app for
# hotkey / accessibility purposes.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> built: $APP_DIR"
echo "    run:    open $APP_DIR"
echo "    autorun: see README.md (LaunchAgent)"
