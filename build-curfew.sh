#!/usr/bin/env bash
# Assembles Curfew.app from the SwiftPM build product. Same shape as build.sh;
# the one difference is that the executable is renamed on the way in.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="Curfew.app"
BINARY="CurfewApp"
# Not the product name: the launchd plists --install writes point at
# /Applications/Curfew.app/Contents/MacOS/Curfew (see Paths.swift).
EXECUTABLE="Curfew"

# The icon is generated, not committed, so the drawing script stays the only
# source of truth for it.
if [[ ! -f Resources/Curfew.icns ]]; then
  ./Scripts/make-curfew-icon.sh
fi

swift build -c "$CONFIG"
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Curfew-Info.plist "$APP/Contents/Info.plist"
cp Resources/Curfew.icns "$APP/Contents/Resources/Curfew.icns"

# Ad-hoc signature: enough to run locally. It is not a Developer ID, so a
# downloaded copy still needs the quarantine flag cleared by hand.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "built $APP ($CONFIG)"
