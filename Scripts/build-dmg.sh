#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="img2b"
VERSION="${1:-0.2.10}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DESKTOP_DMG="$HOME/Desktop/$DMG_NAME"

echo "=== Building $APP_NAME v$VERSION ==="

cd "$PROJECT_DIR"

# Update Info.plist version
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PROJECT_DIR/Resources/Info.plist"

# Build release
swift build -c release

echo
echo "=== Creating app bundle ==="

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_DIR/release/$APP_NAME" "$MACOS_DIR/"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/"

if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

cp "$PROJECT_DIR/Resources/img2b.entitlements" "$RESOURCES_DIR/"

echo
echo "=== Signing ==="
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/Resources/img2b.entitlements" \
    "$APP_BUNDLE" 2>&1

echo
echo "=== Creating DMG ==="
DMG_TMP="/tmp/${APP_NAME}-dmg"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TMP" -ov -format UDZO "$DESKTOP_DMG" 2>&1
rm -rf "$DMG_TMP"

echo
echo "=== Done ==="
echo "DMG: $DESKTOP_DMG"
