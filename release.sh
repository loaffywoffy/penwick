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

# DMG — the human download (drag-to-Applications window).
echo "Building DMG..."
STAGE="$(mktemp -d)"
cp -R build/Penwick.app "$STAGE/Penwick.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$REL/Penwick.dmg"
hdiutil create -volname "Penwick" -srcfolder "$STAGE" -ov -format UDZO "$REL/Penwick.dmg" >/dev/null
rm -rf "$STAGE"
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
