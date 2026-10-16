#!/usr/bin/env bash
# Assembles EyeProtector.app from the SwiftPM build product. See ADR 0001 for
# why this exists instead of an Xcode project.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="EyeProtector.app"
BINARY="EyeProtectorApp"

# The icon is generated, not committed, so the drawing script stays the only
# source of truth for it.
if [[ ! -f Resources/EyeProtector.icns ]]; then
  ./Scripts/make-icon.sh
fi

swift build -c "$CONFIG"
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$BINARY" "$APP/Contents/MacOS/$BINARY"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/EyeProtector.icns "$APP/Contents/Resources/EyeProtector.icns"

# Ad-hoc signature: enough to run locally. SMAppService may reject it, in which
# case launch-at-login falls back to a LaunchAgent plist.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "built $APP ($CONFIG)"
