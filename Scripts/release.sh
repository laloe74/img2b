#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="img2b"
VERSION="${1:-}"

cd "$PROJECT_DIR"

if [ -z "$VERSION" ]; then
    # Auto-increment patch version from latest tag
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    LATEST_NUM=$(echo "$LATEST_TAG" | sed 's/v//')
    IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_NUM"
    PATCH=$((PATCH + 1))
    VERSION="v${MAJOR}.${MINOR}.${PATCH}"
    echo "Auto version: $VERSION (previous: $LATEST_TAG)"
fi

# Get recent commits since last tag for changelog
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
    CHANGES=$(git log "$LAST_TAG"..HEAD --oneline --no-merges | sed 's/^/  - /')
else
    CHANGES=$(git log --oneline --no-merges | sed 's/^/  - /')
fi

DATE=$(date +%Y-%m-%d)

echo
echo "=== Building $APP_NAME $VERSION ==="

# Update version before building
VERSION_NUM="${VERSION#v}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION_NUM" "$PROJECT_DIR/Resources/Info.plist"
echo "Updated Info.plist version to $VERSION_NUM"

# Build release
source "$PROJECT_DIR/Scripts/build-app.sh"

# Create DMG with Applications symlink
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TMP="/tmp/${APP_NAME}-dmg"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TMP" -ov -format UDZO "/tmp/$DMG_NAME" 2>&1
rm -rf "$DMG_TMP"
echo "Package: /tmp/$DMG_NAME"

# Update cask SHA256
SHA256=$(shasum -a 256 "/tmp/$DMG_NAME" | cut -d' ' -f1)
echo "SHA256: $SHA256"
sed -i '' "s/sha256.*/sha256 \"$SHA256\"/" "$PROJECT_DIR/Casks/img2b.rb"
sed -i '' "s/^  version.*/  version \"${VERSION#v}\"/" "$PROJECT_DIR/Casks/img2b.rb"
echo "Updated Casks/img2b.rb"

# Generate Sparkle appcast (with EdDSA signing)
DMG_SIZE=$(stat -f%z "/tmp/$DMG_NAME")
ED_SIG=$(python3 -c "
import struct, base64, subprocess
size = $DMG_SIZE
size_bytes = struct.pack('<Q', size)
with open('/tmp/$DMG_NAME', 'rb') as f:
    data = f.read()
with open('/tmp/sparkle_sign_input', 'wb') as f:
    f.write(size_bytes + data)
result = subprocess.run(['openssl', 'pkeyutl', '-sign', '-inkey', '/tmp/sparkle_private.pem',
    '-in', '/tmp/sparkle_sign_input'], capture_output=True)
print(base64.b64encode(result.stdout).decode())
")
DMG_URL="https://github.com/laloe74/img2b/releases/download/${VERSION}/${DMG_NAME}"
BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PROJECT_DIR/Resources/Info.plist")

cat > "$PROJECT_DIR/appcast.xml" << APPCASTEOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
  <title>img2b</title>
  <item>
    <title>Version ${VERSION#v}</title>
    <sparkle:version>${BUILD_NUM}</sparkle:version>
    <sparkle:shortVersionString>${VERSION#v}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
    <enclosure url="${DMG_URL}"
               sparkle:edSignature="${ED_SIG}"
               sparkle:length="${DMG_SIZE}"
               type="application/octet-stream"/>
  </item>
</channel>
</rss>
APPCASTEOF
echo "Generated appcast.xml"

# Update CHANGELOG
CHANGELOG="$PROJECT_DIR/CHANGELOG.md"
TEMP=$(mktemp)
cat > "$TEMP" << EOF
# Changelog

## $VERSION — $DATE

$CHANGES

EOF
tail -n +2 "$CHANGELOG" >> "$TEMP"
mv "$TEMP" "$CHANGELOG"

# Commit, tag, push
cd "$PROJECT_DIR"
git add -A appcast.xml
git commit -m "$VERSION" || echo "No changes to commit"
git tag -a "$VERSION" -m "$VERSION — $DATE"
git push origin main --tags

# GitHub release
if command -v gh &>/dev/null; then
    gh release create "$VERSION" \
        "/tmp/$DMG_NAME" \
        --title "$VERSION" \
        --notes "$CHANGES"
    echo
    echo "=== GitHub release created: $VERSION ==="
else
    echo
    echo "=== Tag $VERSION pushed. Install gh CLI for auto-release: brew install gh ==="
fi

# Clean up temp files
rm -f "/tmp/$DMG_NAME"

echo
echo "=== Done: $VERSION ==="
