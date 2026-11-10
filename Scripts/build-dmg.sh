#!/bin/zsh
# Builds CallerLite.app and packs it into a drag-to-install .dmg.
# Usage: ./Scripts/build-dmg.sh
# Output: dist/CallerLite-<version>.dmg

set -euo pipefail

APP_NAME="CallerLite"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./Scripts/build-app.sh release

APP="dist/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/$APP_NAME-$VERSION.dmg"

# Stage the app next to an Applications shortcut so users can drag it over.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "Built $ROOT/$DMG"
shasum -a 256 "$DMG"
