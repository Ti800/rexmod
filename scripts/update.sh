#!/bin/sh
# Updates Rex from the official appcast and re-applies the panel patch.
# Sparkle can't update the patched app (its installer only accepts an app
# signed by Superlogical), so this does it instead: the re-patch agent runs it
# every hour, and you can run it any time.
#
# Checks before installing: valid signature, Team ID AG92C3PT77, and that
# Gatekeeper accepts the app (notarized).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/Library/Application Support/rexmod"
APP="${REX_APP:-/Applications/Rex Beta.app}"
TEAM="AG92C3PT77"
FEED=$(defaults read "$APP/Contents/Info.plist" SUFeedURL 2>/dev/null || echo "https://blob.superlogical.com/public/rex-app/snapshot-arm64/appcast.xml")
# Only Superlogical's own servers, over HTTPS (redirects included).
official() { printf '%s' "$1" | grep -Eq '^https://([a-z0-9-]+\.)*superlogical\.com/'; }
official "$FEED" || { echo "refusing the update feed $FEED"; exit 1; }
CURL="curl -fsSL --proto =https --proto-redir =https"
# One update at a time (the hourly agent and a manual run can meet).
LOCK="$PREFIX/.update.lock"
mkdir -p "$PREFIX"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    rm -rf "$LOCK" && mkdir "$LOCK"
  else
    echo "another update is running"
    exit 0
  fi
fi
WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" >/dev/null 2>&1 || true; rm -rf "$WORK" "$LOCK"' EXIT

$CURL --max-time 60 "$FEED" -o "$WORK/appcast.xml"
URL=$(grep -o 'enclosure url="[^"]*"' "$WORK/appcast.xml" | head -1 | sed 's/^enclosure url="//; s/"$//')
LATEST=$(grep -o '<sparkle:version>[0-9]*' "$WORK/appcast.xml" | head -1 | sed 's/.*>//')
CURRENT=$(defaults read "$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo 0)
echo "installed $CURRENT, latest $LATEST"
if [ "$LATEST" = "$CURRENT" ] && [ "${1:-}" != "--force" ]; then
  echo "up to date"
  "$HERE/patch.sh"
  exit 0
fi

official "$URL" || { echo "refusing the download $URL"; exit 1; }
echo "downloading $URL"
$CURL --max-time 600 "$URL" -o "$WORK/rex.dmg"
mkdir -p "$WORK/mnt"
hdiutil attach -nobrowse -readonly -mountpoint "$WORK/mnt" "$WORK/rex.dmg" >/dev/null
NEW=$(find "$WORK/mnt" -maxdepth 1 -name '*.app' | head -1)
[ -n "$NEW" ] || { echo "no app in the disk image"; exit 1; }
codesign --verify --deep --strict "$NEW"
# Signed by Superlogical's Developer ID, checked exactly and as a requirement.
TID=$(codesign -dv "$NEW" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$TID" = "$TEAM" ] || { echo "unexpected signer: $TID"; exit 1; }
codesign --verify -R="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\"" "$NEW" ||
  { echo "unexpected signer"; exit 1; }
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
