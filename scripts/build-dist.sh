#!/bin/sh
# Builds the prebuilt files install.sh ships (arm64, macOS 15+) into dist/.
# Needs Go and the Xcode command line tools; target machines need neither.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p dist build
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/rexmod ./cmd/rexmod
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/insertdylib ./cmd/insertdylib
TARGET=arm64-apple-macos15.0
xcrun clang -c -fobjc-arc -target $TARGET -O2 panel/Boot.m -o build/Boot.o
xcrun swiftc -emit-library -module-name RexModPanel -target $TARGET -O -swift-version 5 \
  -import-objc-header panel/Bridge.h -framework AppKit -framework SwiftUI -framework CoreServices \
  -Xlinker -install_name -Xlinker @rpath/RexModPanel.dylib \
  panel/Support.swift panel/FlowIcons.swift panel/Model.swift panel/Views.swift panel/Panel.swift build/Boot.o \
  -o dist/RexModPanel.dylib
for f in dist/rexmod dist/insertdylib dist/RexModPanel.dylib; do codesign -f -s - "$f" >/dev/null 2>&1; done
ls -la dist
