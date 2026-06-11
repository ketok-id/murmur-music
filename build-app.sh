#!/usr/bin/env bash
# Build Murmur.app, then package it as a .zip and a drag-to-install .dmg.
# Run this on macOS. Requires Xcode Command Line Tools (Swift 5.9+).
#
#   ./build-app.sh             # builds .app + .zip + .dmg in ./dist (ad-hoc signed)
#   ./build-app.sh --no-sign    # skip ad-hoc codesign (not recommended — Apple Silicon will refuse unsigned binaries as "damaged")
#   ./build-app.sh --no-dmg     # skip the .dmg (just .app + .zip)
#   ./build-app.sh --open       # also open the dist folder in Finder when done

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Murmur"
BUNDLE_ID="local.murmur.app"
VERSION="2026.06.11.8"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

SIGN=1
OPEN_DIST=0
MAKE_DMG=1
for arg in "$@"; do
  case "$arg" in
    --sign) SIGN=1 ;;
    --no-sign) SIGN=0 ;;
    --dmg) MAKE_DMG=1 ;;
    --no-dmg) MAKE_DMG=0 ;;
    --open) OPEN_DIST=1 ;;
    *) echo "Unknown flag: $arg"; exit 2 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "❌ swift not found. Install Xcode Command Line Tools:  xcode-select --install"
  exit 1
fi

echo "▶︎ Building release binary..."
swift build -c release

BIN=".build/release/Murmur"
if [ ! -f "$BIN" ]; then
  echo "❌ build failed; expected binary at $BIN"
  exit 1
fi

echo "▶︎ Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Murmur</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- LSUIElement=true makes the app launch directly into .accessory
       activation policy with no Dock icon, ever. The main window is
       AppKit-hosted (MainWindowController) and shown explicitly by
       AppDelegate, so SwiftUI's main-scene auto-presentation (which
       would require .regular) is not relied on. See the READ BEFORE
       TOUCHING block in AppDelegate.swift. -->
  <key>LSUIElement</key><true/>
  <key>NSQuitAlwaysKeepsWindows</key><false/>
  <key>NSHighResolutionCapable</key><true/>
  <!-- ATS stays strict for ordinary requests (every API URL in the
       codebase is HTTPS). The single, scoped exception is MEDIA loads:
       many radio-browser.info station streams are plain http://, and
       NSAllowsArbitraryLoadsForMedia lets AVFoundation (RadioPlayer)
       play them without opening http for URLSession traffic. -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsForMedia</key><true/>
  </dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$BUNDLE_ID.deeplink</string>
      <key>CFBundleURLSchemes</key>
      <array><string>murmur</string></array>
    </dict>
  </array>
</dict></plist>
PLIST

# Build .icns from PNG if present
if [ -f "icon.png" ]; then
  echo "▶︎ Generating AppIcon.icns from icon.png..."
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  done
  # also @2x variants
  cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
  cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

if [ "$SIGN" = "1" ]; then
  echo "▶︎ Ad-hoc codesigning..."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "▶︎ Zipping for sharing..."
( cd "$DIST_DIR" && rm -f "$APP_NAME.zip" && /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip" )
ZIP_SIZE=$(du -sh "$DIST_DIR/$APP_NAME.zip" | awk '{print $1}')

DMG_SIZE=""
if [ "$MAKE_DMG" = "1" ]; then
  if command -v hdiutil >/dev/null 2>&1; then
    echo "▶︎ Building DMG installer..."
    # Stage the .app next to an /Applications symlink so the mounted volume
    # shows the familiar "drag Murmur into Applications" layout.
    STAGING="$(mktemp -d)/dmg"
    mkdir -p "$STAGING"
    cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
    ln -s /Applications "$STAGING/Applications"
    rm -f "$DMG_PATH"
    # UDZO = zlib-compressed read-only image (smallest, standard for downloads).
    hdiutil create \
      -volname "$APP_NAME" \
      -srcfolder "$STAGING" \
      -fs HFS+ \
      -format UDZO \
      -ov \
      "$DMG_PATH" >/dev/null
    rm -rf "$STAGING"
    if [ "$SIGN" = "1" ]; then
      codesign --force --sign - "$DMG_PATH"
    fi
    DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
  else
    echo "⚠︎ hdiutil not found — skipping DMG."
    MAKE_DMG=0
  fi
fi

echo ""
echo "✅ Done."
echo "   App:  $(pwd)/$APP_BUNDLE"
echo "   Zip:  $(pwd)/$DIST_DIR/$APP_NAME.zip   ($ZIP_SIZE)"
if [ "$MAKE_DMG" = "1" ]; then
  echo "   DMG:  $(pwd)/$DMG_PATH   ($DMG_SIZE)"
fi
echo ""
echo "For the website, upload the .dmg. On first launch the recipient hits"
echo "Gatekeeper (unsigned/un-notarized app):"
echo "  • Open the .dmg, drag Murmur to Applications, then right-click → Open"
echo "  • Or run:  xattr -dr com.apple.quarantine /Applications/Murmur.app"

if [ "$OPEN_DIST" = "1" ]; then
  open "$DIST_DIR"
fi
