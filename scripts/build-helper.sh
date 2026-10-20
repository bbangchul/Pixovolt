#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?output directory required}"
mkdir -p "$DEST" "$ROOT/work/ClangModules"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fmodules -fmodules-cache-path="$ROOT/work/ClangModules" -Wall -Wextra -Werror \
  -I "$ROOT/Vendor/m1ddc/headers" \
  "$ROOT/Vendor/m1ddc/sources/i2c.m" "$ROOT/Vendor/m1ddc/sources/ioregistry.m" "$ROOT/Vendor/m1ddc/sources/m1ddc.m" \
  -framework Foundation -framework IOKit -framework CoreGraphics -framework ApplicationServices -framework CoreDisplay \
  -o "$DEST/m1ddc"
chmod 755 "$DEST/m1ddc"
/usr/bin/codesign --force --sign - "$DEST/m1ddc"
