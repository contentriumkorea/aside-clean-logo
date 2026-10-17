#!/bin/bash
# Ephemeral GitHub macOS runner diagnostic. No installer/release code is changed.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "This diagnostic changes temporary Dock preferences and runs a clean browser profile. Run only on an ephemeral GitHub macOS runner." >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT/dist/dock-probe}"
DMG_URL="${ASIDE_PROBE_DMG_URL:-https://releases.aside.com/dev-updater/Aside-1.0.813.1.dmg}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aside-dock-probe.XXXXXX")"
MOUNT="$WORK/mounted"
DOCK_BACKUP="$WORK/dock-before.plist"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then hdiutil detach "$MOUNT" >/dev/null || true; fi
  if [[ -f "$DOCK_BACKUP" ]]; then
    /usr/bin/defaults import com.apple.dock "$DOCK_BACKUP" >/dev/null
    /usr/bin/killall Dock >/dev/null 2>&1 || true
  fi
  # WORK is always the direct output of mktemp under the runner's temp directory.
  rm -rf "$WORK"
}
trap cleanup EXIT

xcrun swiftc -swift-version 5 -O -framework AppKit "$ROOT/macos/dock-probe.swift" -o "$WORK/dock-probe"
FIXTURE="$WORK/Dock Probe Fixture.app"
mkdir -p "$FIXTURE/Contents/MacOS" "$FIXTURE/Contents/Resources" "$WORK/AppIcon.iconset"
cp "$WORK/dock-probe" "$FIXTURE/Contents/MacOS/dock-probe"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/assets/black.png" --out "$WORK/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/assets/black.png" --out "$WORK/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$FIXTURE/Contents/Resources/AppIcon.icns"
python3 - "$FIXTURE/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='dock-probe', CFBundleIdentifier='com.contentrium.aside-dock-probe-fixture',
                      CFBundleName='Dock Probe Fixture', CFBundlePackageType='APPL', CFBundleIconFile='AppIcon',
                      NSHighResolutionCapable=True), f)
PY
codesign --force --sign - "$FIXTURE"
codesign --verify --deep --strict "$FIXTURE"

curl --fail --location --retry 3 --retry-delay 3 "$DMG_URL" --output "$WORK/Aside.dmg"
shasum -a 256 "$WORK/Aside.dmg" > "$OUTPUT/download-sha256.txt"
printf '%s\n' "$DMG_URL" > "$OUTPUT/download-url.txt"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$WORK/Aside.dmg" > "$OUTPUT/mount.txt"
MOUNTED=1
ASIDE_SOURCE="$(find "$MOUNT" -maxdepth 3 -type d -name 'Aside.app' -print -quit)"
if [[ -z "$ASIDE_SOURCE" ]]; then echo 'Official disk image contains no Aside.app' >&2; exit 2; fi
ASIDE="$WORK/Aside.app"
ditto "$ASIDE_SOURCE" "$ASIDE"
hdiutil detach "$MOUNT" > "$OUTPUT/unmount.txt"
MOUNTED=0
codesign --display --verbose=4 "$ASIDE" > "$OUTPUT/aside-baseline-signature.txt" 2>&1

# This is test-only Dock fixture setup, not a production/customization API.
# The complete previous preference domain is restored by cleanup, even on error.
/usr/bin/defaults export com.apple.dock "$DOCK_BACKUP"
pin_app() {
  local ENTRY
  ENTRY="$(python3 - "$1" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
with open(app / 'Contents/Info.plist', 'rb') as f: info = plistlib.load(f)
entry = {'tile-data': {'file-data': {'_CFURLString': app.as_uri()+'/', '_CFURLStringType':15},
                       'file-label': app.stem, 'bundle-identifier':info['CFBundleIdentifier']},
         'tile-type':'file-tile'}
print(plistlib.dumps(entry).decode())
PY
)"
  /usr/bin/defaults write com.apple.dock persistent-apps -array-add "$ENTRY"
}
pin_app "$FIXTURE"
pin_app "$ASIDE"
/usr/bin/defaults write com.apple.dock autohide -bool false
/usr/bin/defaults write com.apple.dock orientation -string bottom
/usr/bin/defaults write com.apple.dock tilesize -int 64
/usr/bin/killall Dock

RESULT=0
if ASIDE_DOCK_PROBE_REFRESH=1 "$WORK/dock-probe" "$FIXTURE" "$ROOT/assets" "$OUTPUT/fixture" fixture; then
  echo 'Fixture diagnostic commands completed. Review screenshots to decide actual Dock behavior.'
else
  echo 'Fixture diagnostic failed; keep the report and continue to the independent Aside probe.' >&2
  RESULT=1
fi
if ASIDE_DOCK_PROBE_REFRESH=1 "$WORK/dock-probe" "$ASIDE" "$ROOT/assets" "$OUTPUT/aside" aside; then
  echo 'Aside diagnostic commands completed. Review screenshots; this is not a Dock-support acceptance claim.'
else
  echo 'Aside diagnostic failed; see phases.json/errors.json. No release conclusion is permitted.' >&2
  RESULT=1
fi

# The clean diagnostic profile is intentionally excluded from uploaded artifacts.
# It is newly created here and contains no user's browser data.
if [[ -d "$OUTPUT/aside/isolated-profile" ]]; then rm -rf "$OUTPUT/aside/isolated-profile"; fi
sw_vers > "$OUTPUT/runner-version.txt"
echo "Probe exit status: $RESULT. Default, strict, and Gatekeeper results are separate facts."
exit "$RESULT"
