#!/usr/bin/env bash
#
# Builds XcodeMini with SwiftPM and assembles a launchable, TCC-eligible
# .app bundle (Info.plist + LSUIElement + NSAppleEventsUsageDescription),
# then ad-hoc code-signs it.
#
#   ./build-app.sh           # build + assemble into ./dist/XcodeMini.app
#   ./build-app.sh install   # also copy into /Applications
#
set -euo pipefail

APP_NAME="XcodeMini"
BUNDLE_ID="co.ascendlogi.XcodeMini"
CONFIG="release"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$(swift build -c "$CONFIG" --product "$APP_NAME" --show-bin-path)/$APP_NAME"
APP_DIR="$ROOT/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"

echo "==> assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"

ICON_SRC="$ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$RES_DIR/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>XcodeMiniはXcodeを操作して、ビルド・実行・停止やscheme／実行先の選択を行います。</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> ad-hoc codesign"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "==> built: $APP_DIR"

if [[ "${1:-}" == "install" ]]; then
    DEST="/Applications/$APP_NAME.app"
    echo "==> installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    echo "==> installed: $DEST"
fi
