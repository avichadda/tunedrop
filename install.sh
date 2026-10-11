#!/bin/sh

set -eu

tap="avichadda/tunedrop"
formula="$tap/tunedrop"
tap_url="https://github.com/avichadda/tunedrop"

if ! command -v brew >/dev/null 2>&1; then
  echo "Error: Homebrew is required to install TuneDrop." >&2
  echo "Install Homebrew from https://brew.sh and run this script again." >&2
  exit 1
fi

echo "Tapping $tap..."
brew tap "$tap" "$tap_url"

if brew list --formula tunedrop >/dev/null 2>&1; then
  echo "Updating TuneDrop..."
  brew upgrade --fetch-HEAD "$formula"
else
  echo "Installing TuneDrop..."
  brew install --HEAD "$formula"
fi

"$(brew --prefix tunedrop)/bin/tunedrop" --version
