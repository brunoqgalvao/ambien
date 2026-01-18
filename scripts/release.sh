#!/bin/bash
#
# MeetingRecorder Release Script
# Usage: ./scripts/release.sh 1.0.1 2
#   - First arg: marketing version (e.g., 1.0.1)
#   - Second arg: build number (must increment each release)
#

set -e

VERSION=$1
BUILD=$2

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "Usage: ./scripts/release.sh <version> <build>"
    echo "Example: ./scripts/release.sh 1.0.1 2"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_DIR="$PROJECT_DIR/docs"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

# GitHub Pages URL (update this if you use a custom domain)
GITHUB_USER="brunogalvao"
REPO_NAME="ami-like"
BASE_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}"

echo "🚀 Building MeetingRecorder v$VERSION (build $BUILD)..."

# Find Sparkle tools in DerivedData
SPARKLE_BIN=$(find "$DERIVED_DATA" -path "*/MeetingRecorder*/SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle tools not found. Build the project in Xcode first."
    exit 1
fi

SIGN_TOOL="$SPARKLE_BIN/sign_update"

# Update version in Info.plist
echo "📝 Updating Info.plist..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PROJECT_DIR/MeetingRecorder/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PROJECT_DIR/MeetingRecorder/Info.plist"

# Clean and build
echo "🔨 Building Release..."
cd "$PROJECT_DIR"
xcodebuild -project MeetingRecorder.xcodeproj \
    -scheme MeetingRecorder \
    -configuration Release \
    clean build \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    2>&1 | tail -5

# Find the built app
APP_PATH=$(find "$DERIVED_DATA" -path "*/MeetingRecorder*/Build/Products/Release/MeetingRecorder.app" -type d 2>/dev/null | head -1)

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed - app not found"
    exit 1
fi

echo "✅ Build succeeded: $APP_PATH"

# Create docs/releases directory
mkdir -p "$DOCS_DIR/releases"

# Create zip
ZIP_NAME="MeetingRecorder-$VERSION.zip"
ZIP_PATH="$DOCS_DIR/releases/$ZIP_NAME"

echo "📦 Creating $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Get file size
FILE_SIZE=$(stat -f%z "$ZIP_PATH")

# Sign the update
echo "🔏 Signing update..."
SIGNATURE=$("$SIGN_TOOL" "$ZIP_PATH" 2>&1)

# Extract just the signature value
ED_SIGNATURE=$(echo "$SIGNATURE" | grep -o 'edSignature="[^"]*"' | sed 's/edSignature="//;s/"//')

# Update appcast.xml
APPCAST_PATH="$DOCS_DIR/appcast.xml"
PUB_DATE=$(date -R)

echo "📝 Updating appcast.xml..."

cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MeetingRecorder Updates</title>
    <link>${BASE_URL}/appcast.xml</link>
    <description>Most recent updates to MeetingRecorder</description>
    <language>en</language>

    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New in $VERSION</h2>
        <ul>
          <li>Bug fixes and improvements</li>
        </ul>
      ]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="${BASE_URL}/releases/$ZIP_NAME"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$FILE_SIZE"
        type="application/octet-stream"/>
    </item>

  </channel>
</rss>
EOF

# Update index.html download link
sed -i '' "s/MeetingRecorder-[0-9.]*\.zip/MeetingRecorder-$VERSION.zip/g" "$DOCS_DIR/index.html"
sed -i '' "s/Version [0-9.]*\( \|&\)/Version $VERSION\1/g" "$DOCS_DIR/index.html"

# Also update /Applications
echo "📲 Updating /Applications..."
pkill -f "MeetingRecorder" 2>/dev/null || true
sleep 1
rm -rf /Applications/MeetingRecorder.app
cp -R "$APP_PATH" /Applications/

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ RELEASE READY: MeetingRecorder v$VERSION"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📁 Files updated:"
echo "   $ZIP_PATH"
echo "   $APPCAST_PATH"
echo "   /Applications/MeetingRecorder.app"
echo ""
echo "📤 To publish:"
echo "   git add docs/"
echo "   git commit -m \"Release v$VERSION\""
echo "   git push origin main"
echo ""
echo "🌐 After push, available at:"
echo "   Download: ${BASE_URL}/releases/$ZIP_NAME"
echo "   Appcast:  ${BASE_URL}/appcast.xml"
echo ""
echo "═══════════════════════════════════════════════════════════════"
