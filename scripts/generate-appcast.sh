#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 VERSION" >&2
  echo "Example: $0 0.3.0" >&2
  exit 2
fi

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
version="$1"
tag="v$version"
release_dir="$root/.build/appcast-releases"
generate_appcast="$root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
repository_url="https://github.com/avichadda/tunedrop"

cd "$root"
swift package resolve

if [ ! -x "$generate_appcast" ]; then
  echo "Error: Sparkle's generate_appcast tool was not resolved." >&2
  exit 1
fi

rm -rf "$release_dir"
mkdir -p "$release_dir"

gh release download "$tag" \
  --pattern "TuneDrop-$version.dmg" \
  --dir "$release_dir"
gh release view "$tag" --json body --jq .body > "$release_dir/TuneDrop-$version.md"

if [ -f "$root/appcast.xml" ]; then
  cp "$root/appcast.xml" "$release_dir/appcast.xml"
fi

"$generate_appcast" \
  --download-url-prefix "$repository_url/releases/download/$tag/" \
  --link "$repository_url/releases/tag/$tag" \
  --embed-release-notes \
  "$release_dir"

cp "$release_dir/appcast.xml" "$root/appcast.xml"
printf 'Updated %s for %s\n' "$root/appcast.xml" "$tag"
