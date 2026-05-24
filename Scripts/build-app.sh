#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="img2b"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
DESKTOP="$HOME/Desktop/$APP_NAME.app"

echo "=== Building $APP_NAME ==="

cd "$PROJECT_DIR"
swift build -c release

echo
echo "=== Creating app bundle ==="

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/release/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/"

# Copy icon if exists
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/"
fi

# Copy entitlements
cp "$PROJECT_DIR/Resources/img2b.entitlements" "$RESOURCES_DIR/"

# Ad-hoc code sign
echo
echo "=== Signing ==="
codesign --force --deep --sign - \
    --entitlements "$PROJECT_DIR/Resources/img2b.entitlements" \
    "$APP_BUNDLE" 2>&1

# Copy to desktop
rm -rf "$DESKTOP"
cp -R "$APP_BUNDLE" "$DESKTOP"

echo
echo "=== Done ==="
echo "App built: $APP_BUNDLE"
echo "Desktop: $DESKTOP"
