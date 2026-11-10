#!/bin/zsh
# Builds CallerLite and wraps it into a proper macOS .app bundle.
# Usage: ./Scripts/build-app.sh [debug|release]

set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="CallerLite"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT"
echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

case "$CONFIG" in
  debug)   BUILD_DIR=".build/debug" ;;
  release) BUILD_DIR=".build/release" ;;
  *)       BUILD_DIR=".build/$CONFIG" ;;
esac

BIN="$BUILD_DIR/$APP_NAME"
APP="dist/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON_PKG="$ROOT/Resources/CallerLite.icon"
if [[ -d "$ICON_PKG" ]]; then
  xcrun actool "$ICON_PKG" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.0 \
    --app-icon CallerLite --output-partial-info-plist "$ROOT/.build/icon-partial.plist" >/dev/null
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CallerLite</string>
    <key>CFBundleDisplayName</key>
    <string>CallerLite</string>
    <key>CFBundleIconFile</key>
    <string>CallerLite</string>
    <key>CFBundleIconName</key>
    <string>CallerLite</string>
    <key>CFBundleIdentifier</key>
    <string>de.sipphone.mac</string>
    <key>CFBundleExecutable</key>
    <string>CallerLite</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.business</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 – Adam Moczydlowski
Alle Rechte vorbehalten.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>CallerLite benötigt Zugriff auf das Mikrofon, um Telefonate zu führen.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $ROOT/$APP"
echo "Start with: open $ROOT/$APP"
