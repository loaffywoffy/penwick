#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Penwick.app"
SDK="$(xcrun --show-sdk-path)"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$BIN" "$RES"
touch "build/.metadata_never_index"   # keep the build copy out of Spotlight

# --- Icon ---------------------------------------------------------------
echo "Rendering app icon..."
swift makeicon.swift build/icon_1024.png >/dev/null

ICONSET="build/Penwick.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" build/icon_1024.png --out "$ICONSET/icon_$2.png" >/dev/null; }
gen 16   16x16
gen 32   16x16@2x
gen 32   32x32
gen 64   32x32@2x
gen 128  128x128
gen 256  128x128@2x
gen 256  256x256
gen 512  256x256@2x
gen 512  512x512
cp build/icon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES/Penwick.icns"

# --- Name databases (bundled into the app) ------------------------------
cp names/*.txt "$RES/"

# --- Compile ------------------------------------------------------------
echo "Compiling Swift -> native binary..."
swiftc Sources/Quill.swift \
  -o "$BIN/Penwick" \
  -sdk "$SDK" \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit \
  -parse-as-library \
  -O

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Penwick</string>
  <key>CFBundleDisplayName</key><string>Penwick</string>
  <key>CFBundleExecutable</key><string>Penwick</string>
  <key>CFBundleIdentifier</key><string>com.penwick.app</string>
  <key>CFBundleIconFile</key><string>Penwick</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP/Contents/PkgInfo"

# No version numbers — stamp an opaque build code (md5 of the compiled binary).
# The in-app updater compares this against the code published on GitHub.
CODE=$(md5 -q "$BIN/Penwick")
/usr/libexec/PlistBuddy -c "Add :PenwickBuildCode string $CODE" "$APP/Contents/Info.plist" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :PenwickBuildCode $CODE" "$APP/Contents/Info.plist" >/dev/null 2>&1
echo "Build code: $CODE"

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(codesign skipped)"

# Install into /Applications — the single canonical copy. (No iCloud copy: the
# other Mac auto-updates from GitHub, so we don't keep a duplicate around.)
rm -rf /Applications/Penwick.app
cp -R "$APP" /Applications/Penwick.app && echo "Installed: /Applications/Penwick.app"

echo "Built: $APP"
