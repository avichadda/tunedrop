#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
version="0.2.0"
volume_name="TuneDrop Installer"
app="$root/dist/TuneDrop.app"
dmg="$root/dist/TuneDrop-$version.dmg"
staging="$root/.build/dmg-staging"
read_write_dmg="$root/.build/TuneDrop-$version-rw.dmg"
background="$staging/.background/background.png"
device=""

cleanup() {
  if [ -n "$device" ]; then
    hdiutil detach "$device" -quiet || true
  fi
}
trap cleanup EXIT INT TERM

"$root/scripts/build-macos-app.sh"

rm -rf "$staging"
rm -f "$read_write_dmg" "$dmg"
mkdir -p "$staging/.background"
cp -R "$app" "$staging/TuneDrop.app"
ln -s /Applications "$staging/Applications"
swift "$root/assets/generate-dmg-background.swift" "$background"

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$read_write_dmg" >/dev/null

attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$read_write_dmg")"
device="$(printf '%s\n' "$attach_output" | awk '/Apple_HFS/ {print $1; exit}')"
mount_point="$(printf '%s\n' "$attach_output" | awk '
  /Apple_HFS/ {
    sub(/^.*Apple_HFS[[:space:]]+/, "")
    print
    exit
  }
')"

if [ -z "$device" ] || [ -z "$mount_point" ]; then
  echo "Error: Could not mount the writable DMG." >&2
  exit 1
fi

SetFile -a V "$mount_point/.background"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set bounds of container window to {200, 120, 860, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "TuneDrop.app" of container window to {170, 220}
    set position of item "Applications" of container window to {490, 220}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$device" -quiet
device=""

hdiutil convert \
  "$read_write_dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$dmg" >/dev/null

printf 'Built %s\n' "$dmg"
