#!/bin/sh
# Builds the Changes panel dylib and installs it where the patched Rex loads it.
set -eu
cd "$(dirname "$0")/.."
OUT=build/RexModPanel.dylib
DEST="$HOME/Library/Application Support/rexmod/RexModPanel.dylib"
TARGET=arm64-apple-macos15.0
mkdir -p build "$(dirname "$DEST")"
xcrun clang -c -fobjc-arc -target $TARGET -O2 panel/Boot.m -o build/Boot.o
xcrun swiftc -emit-library -module-name RexModPanel -target $TARGET -O -swift-version 5 -import-objc-header panel/Bridge.h \
  -framework AppKit -framework SwiftUI -framework CoreServices \
  -Xlinker -install_name -Xlinker "$DEST" \
  panel/Support.swift panel/Theme.swift panel/FlowIcons.swift panel/Model.swift panel/Views.swift panel/Panel.swift build/Boot.o -o "$OUT"
codesign -f -s - "$OUT" >/dev/null 2>&1
# Replace atomically so a running Rex keeps its mapped copy.
cp "$OUT" "$DEST.tmp" && mv -f "$DEST.tmp" "$DEST"
echo "built $OUT -> $DEST"
