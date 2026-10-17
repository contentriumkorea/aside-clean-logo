#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/macos/build/dmg/Aside Clean Logo.app}"
TEST="$(mktemp -d "${TMPDIR:-/tmp}/aside-clean-logo-test.XXXXXX")"
trap 'rm -rf "$TEST"' EXIT
FIXTURE="$TEST/Aside.app"
mkdir -p "$FIXTURE/Contents/MacOS"
cat > "$TEST/fixture.c" <<'EOF'
int main(void) { return 0; }
EOF
clang "$TEST/fixture.c" -o "$FIXTURE/Contents/MacOS/fixture"
cat > "$FIXTURE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.contentrium.aside-clean-logo.fixture</string>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
codesign --force --sign - "$FIXTURE"
codesign --verify --deep --strict "$FIXTURE"
BEFORE="$(shasum -a 256 "$FIXTURE/Contents/MacOS/fixture")"
"$APP/Contents/MacOS/AsideCleanLogo" --self-test "$FIXTURE" "$TEST/state"
AFTER="$(shasum -a 256 "$FIXTURE/Contents/MacOS/fixture")"
[[ "$BEFORE" == "$AFTER" ]]
codesign --verify --deep --strict "$FIXTURE"
codesign --verify --deep --strict "$APP"
echo "PASS: executable bytes unchanged, app signatures valid"
