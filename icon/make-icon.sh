#!/usr/bin/env bash
#
# Generates Resources/AppIcon.icns from the SF Symbol renderer.
# Re-run whenever you want to regenerate the icon.
#
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
PNG="$DIR/icon_1024.png"
ICONSET="$DIR/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

echo "==> rendering 1024px master"
swift "$DIR/make-icon.swift" "$PNG"

echo "==> building iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
sips -z 16 16     "$PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$PNG"         "$ICONSET/icon_512x512@2x.png"

echo "==> packing .icns"
mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "==> wrote $OUT"
