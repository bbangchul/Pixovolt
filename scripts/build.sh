#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p outputs work
xcodebuild -project Pixovolt.xcodeproj -scheme Pixovolt -configuration Release \
  -derivedDataPath "$ROOT/work/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
APP="$ROOT/work/DerivedData/Build/Products/Release/Pixovolt.app"
# Install a complete product into the deliverables directory.
if [[ -e "$ROOT/outputs/Pixovolt.app" ]]; then
  mv "$ROOT/outputs/Pixovolt.app" "$ROOT/work/Previous-Pixovolt-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$APP" "$ROOT/outputs/Pixovolt.app"
codesign --verify --deep --strict --verbose=2 "$ROOT/outputs/Pixovolt.app"
file "$ROOT/outputs/Pixovolt.app/Contents/MacOS/Pixovolt" "$ROOT/outputs/Pixovolt.app/Contents/MacOS/m1ddc"
if [[ "${1:-}" == "--dmg" ]]; then
  "$ROOT/scripts/package-dmg.sh"
fi
