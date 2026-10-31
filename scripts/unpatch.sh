#!/bin/sh
# Restores the official Rex build that patch.sh backed up. If that copy is
# older than you want, run update.sh instead (it installs the latest official
# build, then patches it) or download Rex again.
set -eu
PREFIX="$HOME/Library/Application Support/rexmod"
APP="${REX_APP:-/Applications/Rex Beta.app}"
B="$PREFIX/backup/Rex Beta.app"
[ -d "$B" ] || { echo "no backup in $PREFIX/backup; download Rex again from https://rex.superlogical.com"; exit 1; }
codesign --verify --strict "$B"
rm -rf "$PREFIX/replaced"
mkdir -p "$PREFIX/replaced"
[ -d "$APP" ] && mv "$APP" "$PREFIX/replaced/"
ditto "$B" "$APP"
echo "restored the official Rex $(cat "$PREFIX/backup/VERSION" 2>/dev/null). Quit Rex and open it again."
