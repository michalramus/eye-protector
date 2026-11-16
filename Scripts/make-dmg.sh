#!/usr/bin/env bash
# Packages an already-built app into a compressed DMG. Usage:
#   make-dmg.sh [version] [eyeprotector|curfew]
# Both default to what they always were: "dev" and Eye Protector.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
WHICH="${2:-eyeprotector}"

case "$WHICH" in
  eyeprotector)
    APP="Eye Protector.app"
    VOLUME="Eye Protector"
    NAME="EyeProtector"
    BUILD="./build.sh release"
    ;;
  curfew)
    APP="Curfew.app"
    VOLUME="Curfew"
    NAME="Curfew"
    BUILD="./build-curfew.sh release"
    ;;
  *)
    echo "unknown app \"$WHICH\" — expected eyeprotector or curfew" >&2
    exit 1
    ;;
esac

if [[ ! -d "$APP" ]]; then
  echo "no \"$APP\" — run $BUILD first" >&2
  exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
# The usual drag-to-install target.
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
DMG="dist/${NAME}-${VERSION}.dmg"
rm -f "$DMG"

hdiutil create \
  -volname "$VOLUME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "built $DMG"
