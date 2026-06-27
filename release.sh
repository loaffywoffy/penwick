#!/bin/bash
# Usage: ./release.sh <version> ["release notes"]
set -euo pipefail
cd "$(dirname "$0")"
NEW="${1:-}"; [ -z "$NEW" ] && { echo "usage: ./release.sh <version> [notes]"; exit 1; }
NOTES="${2:-Penwick $NEW}"
echo "$NEW" > VERSION
./build.sh
REL="$HOME/Quill/release"
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
  "version": "$NEW",
  "url": "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/Penwick.app.zip",
  "dmg": "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/Penwick.dmg",
  "notes": "$NOTES"
}
JSON
cd "$REL"
git add -A
git -c user.email="loaffywoffy@users.noreply.github.com" -c user.name="loaffywoffy" commit -q -m "Penwick $NEW"
git push -q
echo "Released $NEW — installed apps will now offer the update."
