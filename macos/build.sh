#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/macos/build"
APP="$BUILD/dmg/Aside Clean Logo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "${ARCH}-apple-macosx12.0" \
    -framework AppKit "$ROOT/macos/AsideCleanLogo.swift" -o "$BUILD/AsideCleanLogo-$ARCH"
done
lipo -create "$BUILD/AsideCleanLogo-arm64" "$BUILD/AsideCleanLogo-x86_64" -output "$APP/Contents/MacOS/AsideCleanLogo"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/black.png" "$ROOT/assets/white.png" "$APP/Contents/Resources/"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/assets/black.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/assets/black.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/macos/README.txt" "$BUILD/dmg/READ ME.txt"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
bash "$ROOT/macos/test.sh" "$APP"
DMG="$ROOT/dist/Aside-Clean-Logo-macOS.dmg"
if [[ -f "$DMG" ]]; then rm "$DMG"; fi
hdiutil create -volname "Aside Clean Logo" -srcfolder "$BUILD/dmg" -format UDZO "$DMG"
hdiutil verify "$DMG"
lipo -info "$APP/Contents/MacOS/AsideCleanLogo"
shasum -a 256 "$DMG"
