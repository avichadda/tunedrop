#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
app="$root/dist/TuneDrop.app"
contents="$app/Contents"
iconset="$root/.build/TuneDrop.iconset"
icon_source="$root/.build/TuneDrop-AppIcon.png"
sparkle_framework="$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

cd "$root"
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$contents/Frameworks" "$contents/MacOS" "$contents/Resources"
cp "$bin_path/TuneDrop" "$contents/MacOS/TuneDrop"
ditto "$sparkle_framework" "$contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$contents/MacOS/TuneDrop"

rm -rf "$iconset"
mkdir -p "$iconset"
swift "$root/assets/generate-app-icon.swift" "$icon_source"
for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  set -- $spec
  sips -z "$1" "$1" "$icon_source" --out "$iconset/$2" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"

cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>TuneDrop</string>
  <key>CFBundleIdentifier</key>
  <string>com.avichadda.tunedrop</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TuneDrop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/avichadda/tunedrop/main/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>Bn4ihfx99kBFK0KtTMD6dGAuSWerQVSwYPGkAtLMuMQ=</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

printf 'Built %s\n' "$app"
