#!/bin/sh
# Packs a release: the prebuilt dist/ files plus everything install.sh needs,
# as build/release/rexmod-<version>-darwin-arm64.tar.gz.
#   scripts/package-release.sh [version]   (default: git describe)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
"$ROOT/scripts/build-dist.sh" >/dev/null
NAME="rexmod-$VERSION-darwin-arm64"
OUT="$ROOT/build/release"
rm -rf "${OUT:?}/$NAME" "${OUT:?}/$NAME.tar.gz"
mkdir -p "$OUT/$NAME"
cp -R install.sh uninstall.sh README.md LICENSE dist nvim agents skills scripts editor "$OUT/$NAME/"
tar -czf "$OUT/$NAME.tar.gz" -C "$OUT" "$NAME"
echo "$OUT/$NAME.tar.gz"
