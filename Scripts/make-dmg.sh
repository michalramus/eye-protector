#!/usr/bin/env bash
# Packages an already-built EyeProtector.app into a compressed DMG.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
APP="EyeProtector.app"

if [[ ! -d "$APP" ]]; then
  echo "no $APP — run ./build.sh release first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
# The usual drag-to-install target.
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
DMG="dist/EyeProtector-${VERSION}.dmg"
rm -f "$DMG"

hdiutil create \
  -volname "Eye Protector" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "built $DMG"
