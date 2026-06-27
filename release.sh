#!/bin/bash
# Usage: ./release.sh ["release notes"]   — no version numbers; uses a build code.
set -euo pipefail
cd "$(dirname "$0")"
NOTES="${1:-Penwick update}"
./build.sh
REL="$HOME/Quill/release"
CODE=$(/usr/libexec/PlistBuddy -c "Print PenwickBuildCode" build/Penwick.app/Contents/Info.plist)
# Zip — used by the in-app auto-updater.
ditto -c -k --keepParent build/Penwick.app "$REL/Penwick.app.zip"

# DMG — a branded drag-to-Applications installer window.
echo "Building DMG..."
swift dmgbg.swift build/dmgbg.png >/dev/null
STAGE="$(mktemp -d)"
cp -R build/Penwick.app "$STAGE/Penwick.app"
mkdir "$STAGE/.background"
cp build/dmgbg.png "$STAGE/.background/bg.png"
ln -s /Applications "$STAGE/Applications"

RWDIR="$(mktemp -d)"; RW="$RWDIR/rw.dmg"
hdiutil create -volname "Penwick" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil detach "/Volumes/Penwick" >/dev/null 2>&1 || true
hdiutil attach "$RW" -nobrowse -noautoopen >/dev/null
sleep 2
osascript <<'OSA' || echo "(DMG window styling skipped — needs Finder automation permission)"
tell application "Finder"
  tell disk "Penwick"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 110
    set text size of opts to 13
    set background picture of opts to file ".background:bg.png"
    set position of item "Penwick.app" of container window to {165, 215}
    set position of item "Applications" of container window to {495, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync; sleep 1
hdiutil detach "/Volumes/Penwick" >/dev/null 2>&1 || hdiutil detach "/Volumes/Penwick" -force >/dev/null 2>&1 || true
rm -f "$REL/Penwick.dmg"
hdiutil convert "$RW" -format UDZO -o "$REL/Penwick.dmg" >/dev/null
rm -rf "$STAGE" "$RWDIR"
echo "Built: $REL/Penwick.dmg"

cat > "$REL/version.json" <<JSON
{
  "code": "$CODE",
  "url": "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/Penwick.app.zip",
  "dmg": "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/Penwick.dmg",
  "notes": "$NOTES"
}
JSON
cd "$REL"
git add -A
git -c user.email="loaffywoffy@users.noreply.github.com" -c user.name="loaffywoffy" commit -q -m "Penwick ${CODE:0:8}"
git push -q
echo "Released ${CODE:0:8} — installed apps will now offer the update."
