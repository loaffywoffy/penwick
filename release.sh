#!/bin/bash
# Usage: ./release.sh <version> ["release notes"]
set -euo pipefail
cd "$(dirname "$0")"
NEW="${1:-}"; [ -z "$NEW" ] && { echo "usage: ./release.sh <version> [notes]"; exit 1; }
NOTES="${2:-Penwick $NEW}"
echo "$NEW" > VERSION
./build.sh
REL="$HOME/Quill/release"
ditto -c -k --keepParent build/Penwick.app "$REL/Penwick.app.zip"
cat > "$REL/version.json" <<JSON
{
  "version": "$NEW",
  "url": "https://raw.githubusercontent.com/loaffywoffy/penwick-releases/main/Penwick.app.zip",
  "notes": "$NOTES"
}
JSON
cd "$REL"
git add -A
git -c user.email="loaffywoffy@users.noreply.github.com" -c user.name="loaffywoffy" commit -q -m "Penwick $NEW"
git push -q
echo "Released $NEW — installed apps will now offer the update."
