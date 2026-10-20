#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work" "$ROOT/outputs"
TMP="$(mktemp -d "$ROOT/work/package.XXXXXX")"
STAGE="$TMP/stage"
MOUNT="$TMP/mounted"
cleanup() {
  if mount | /usr/bin/grep -Fq "on $MOUNT "; then hdiutil detach "$MOUNT" -quiet || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$STAGE/.background" "$MOUNT"
ditto "$ROOT/outputs/Pixovolt.app" "$STAGE/Pixovolt.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/assets/dmg-background.png" "$STAGE/.background/background.png"
cp "$ROOT/docs/INSTALL.txt" "$STAGE/.background/INSTALL.txt"
cp "$ROOT/assets/Pixovolt.icns" "$STAGE/.VolumeIcon.icns"
xcrun swiftc -module-cache-path "$ROOT/work/ArtModules" "$ROOT/scripts/artwork.swift" -o "$TMP/artwork"
hdiutil create -size 32m -fs HFS+ -volname 'Pixovolt 1.1' -srcfolder "$STAGE" -format UDRW "$TMP/editable.dmg" -quiet
hdiutil attach "$TMP/editable.dmg" -mountpoint "$MOUNT" -nobrowse -noautoopen -quiet
python3 "$ROOT/scripts/dmg-layout.py" "$MOUNT"
SetFile -a C "$MOUNT"
# Mark invisible support resources explicitly as well as using dot names.
SetFile -a V "$MOUNT/.VolumeIcon.icns" "$MOUNT/.background"
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$TMP/editable.dmg" -format UDZO -o "$TMP/Pixovolt-1.1-arm64.dmg" -quiet
hdiutil verify "$TMP/Pixovolt-1.1-arm64.dmg"
"$TMP/artwork" file-icon "$ROOT/assets/Pixovolt.icns" "$TMP/Pixovolt-1.1-arm64.dmg"
# Replace the final deliverable only after image creation and validation pass.
mv -f "$TMP/Pixovolt-1.1-arm64.dmg" "$ROOT/outputs/Pixovolt-1.1-arm64.dmg"
printf 'Created %s\n' "$ROOT/outputs/Pixovolt-1.1-arm64.dmg"
