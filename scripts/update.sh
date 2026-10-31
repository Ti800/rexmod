#!/bin/sh
# Updates Rex from the official appcast and re-applies the panel patch.
# Sparkle can't update the patched app (its ad hoc signature no longer matches
# the official one), so run this when Rex says an update is available.
#
# Checks before installing: valid signature, Team ID AG92C3PT77, and that
# Gatekeeper accepts the app (notarized).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/Library/Application Support/rexmod"
APP="${REX_APP:-/Applications/Rex Beta.app}"
TEAM="AG92C3PT77"
FEED=$(defaults read "$APP/Contents/Info.plist" SUFeedURL 2>/dev/null || echo "https://blob.superlogical.com/public/rex-app/snapshot-arm64/appcast.xml")
WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

curl -fsSL --max-time 60 "$FEED" -o "$WORK/appcast.xml"
URL=$(grep -o 'enclosure url="[^"]*"' "$WORK/appcast.xml" | head -1 | sed 's/^enclosure url="//; s/"$//')
LATEST=$(grep -o '<sparkle:version>[0-9]*' "$WORK/appcast.xml" | head -1 | sed 's/.*>//')
CURRENT=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 0)
echo "installed $CURRENT, latest $LATEST"
if [ "$LATEST" = "$CURRENT" ] && [ "${1:-}" != "--force" ]; then
  echo "up to date"
  "$HERE/patch.sh"
  exit 0
fi

echo "downloading $URL"
curl -fsSL --max-time 600 "$URL" -o "$WORK/rex.dmg"
mkdir -p "$WORK/mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$WORK/mnt" "$WORK/rex.dmg" >/dev/null
NEW=$(find "$WORK/mnt" -maxdepth 1 -name '*.app' | head -1)
[ -n "$NEW" ] || { echo "no app in the disk image"; exit 1; }
codesign --verify --deep --strict "$NEW"
codesign -dv "$NEW" 2>&1 | grep -q "TeamIdentifier=$TEAM" || { echo "unexpected signer"; exit 1; }
spctl -a -t exec "$NEW" || { echo "Gatekeeper rejected the update"; exit 1; }
ditto "$NEW" "$WORK/Rex Beta.app"
hdiutil detach "$WORK/mnt" >/dev/null

# Keep the replaced bundle until the next run: a running Rex still uses it.
rm -rf "$PREFIX/replaced"
mkdir -p "$PREFIX/replaced"
[ -d "$APP" ] && mv "$APP" "$PREFIX/replaced/"
ditto "$WORK/Rex Beta.app" "$APP"
echo "installed official Rex $LATEST"
"$HERE/patch.sh"
