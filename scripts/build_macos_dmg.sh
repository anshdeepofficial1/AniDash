#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AniDash macOS DMG Packager
# Builds and packages a native, production-grade macOS DMG for AniDash
# ==============================================================================

echo "🚀 Starting AniDash macOS DMG Build Process..."

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Extract version from pubspec.yaml
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml | tr -d '\r\n')
if [ -z "$VERSION" ]; then
  VERSION="1.0.0"
fi
APP_NAME="AniDash"
DMG_NAME="${APP_NAME}-v${VERSION}-macOS.dmg"
OUTPUT_DIR="build/macos/installer"
mkdir -p "$OUTPUT_DIR"

echo "📦 Project Version: $VERSION"
echo "🖥️  Target Artifact: $OUTPUT_DIR/$DMG_NAME"

# 1. Flutter dependencies
echo "📥 Fetching Flutter dependencies..."
flutter pub get

# 2. Build macOS Release
echo "🔨 Building macOS Release binary..."
flutter build macos --release --no-tree-shake-icons

# Locate built .app bundle
APP_BUNDLE=$(find build/macos/Build/Products/Release -name "*.app" -maxdepth 1 | head -n 1)

if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
  echo "❌ Error: Could not find built .app bundle in build/macos/Build/Products/Release!" >&2
  exit 1
fi

echo "✅ Located app bundle at: $APP_BUNDLE"

# 3. Create DMG
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
  echo "✨ Using 'create-dmg' for Apple-styled layout..."
  create-dmg \
    --volname "${APP_NAME}" \
    --volicon "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 120 \
    --icon "${APP_NAME}.app" 180 180 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 480 180 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${APP_BUNDLE}" || true
fi

# Fallback to native hdiutil if create-dmg didn't run or output the DMG
if [ ! -f "$DMG_PATH" ]; then
  echo "ℹ️  Packaging via native macOS hdiutil..."
  STAGING_DIR=$(mktemp -d /tmp/anidash_dmg_staging.XXXXXX)
  cp -R "$APP_BUNDLE" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"
  
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  
  rm -rf "$STAGING_DIR"
fi

if [ -f "$DMG_PATH" ]; then
  FILE_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
  echo "🎉 SUCCESS: macOS DMG created successfully!"
  echo "📍 Location: $DMG_PATH ($FILE_SIZE)"
else
  echo "❌ Error: Failed to generate DMG." >&2
  exit 1
fi
