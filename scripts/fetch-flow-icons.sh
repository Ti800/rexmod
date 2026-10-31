#!/bin/sh
# Downloads the free Flow Icons pack (thang-nm.flow-icons) from Open VSX and
# installs the "Flow Deep" theme (dark + light variants) for the panel.
# The icons stay outside the repo: ~/Library/Application Support/rexmod/flow-icons
set -eu
VERSION="${1:-2.0.10}"
DEST="$HOME/Library/Application Support/rexmod/flow-icons"
URL="https://open-vsx.org/api/thang-nm/flow-icons/$VERSION/file/thang-nm.flow-icons-$VERSION.vsix"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/x"
curl -fsSL --max-time 120 -o "$WORK/flow.vsix" "$URL"
unzip -q "$WORK/flow.vsix" 'extension/deep.json' 'extension/deep/*' 'extension/deep-light/*' 'extension/LICENSE.txt' -d "$WORK/x"
rm -rf "$DEST.new"
mkdir -p "$DEST.new"
cp -R "$WORK/x/extension/deep" "$WORK/x/extension/deep-light" "$WORK/x/extension/deep.json" "$WORK/x/extension/LICENSE.txt" "$DEST.new/"
echo "$VERSION" > "$DEST.new/VERSION"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
echo "Flow Icons $VERSION -> $DEST ($(find "$DEST/deep" -type f | wc -l | tr -d ' ') icons)"
