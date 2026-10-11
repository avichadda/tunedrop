# TuneDrop

TuneDrop is a command-line music archiver. Give it a Spotify track, album, or
playlist URL and it resolves the metadata, searches public media sources for a
matching recording, converts the audio with FFmpeg, and writes tags and cover
art.

Spotify is used for metadata only. TuneDrop does not download or decrypt audio
from Spotify.

## Install with Homebrew

The formula tracks the current `main` branch until the first release is tagged:

```console
curl -fsSL https://raw.githubusercontent.com/avichadda/tunedrop/main/install.sh | sh
```

The installer taps this repository and installs TuneDrop from `main`. To run
the same steps manually:

```console
brew tap avichadda/tunedrop https://github.com/avichadda/tunedrop
brew install --HEAD avichadda/tunedrop/tunedrop
```

Homebrew installs FFmpeg and the required Python runtime automatically. Upgrade
the head build with:

```console
brew upgrade --fetch-HEAD avichadda/tunedrop/tunedrop
```

## macOS app

TuneDrop includes a native SwiftUI app for macOS 13 or newer. Install the
TuneDrop CLI first, then build the app:

```console
./scripts/build-macos-app.sh
open dist/TuneDrop.app
```

To build the distributable DMG with its branded drag-to-Applications window:

```console
./scripts/build-dmg.sh
open dist/TuneDrop-0.2.0.dmg
```

The app provides destination, format, bitrate, overwrite, progress, and
cancellation controls. It uses the installed TuneDrop CLI as its download
engine. On first launch, onboarding walks through creating a Spotify app and
adding the required callback URL. The client ID is saved in app preferences and
the client secret is stored securely in macOS Keychain. Use **Credentials...**
in the main window to update them later.

The app uses Sparkle to check the signed GitHub release feed when it launches.
When a newer version is available, Sparkle asks the user before installing it.
Users can also choose **TuneDrop > Check for Updates...**.

### Publishing an app update

Sparkle's private EdDSA key is stored in the release maintainer's macOS
Keychain; only its public key is committed. After creating a GitHub release and
uploading its matching DMG, sign the exact release asset and update the feed.
The app bundle in the DMG must pass Apple code-signing verification; local
builds use ad hoc signing, while public production releases should use a
Developer ID Application certificate and notarization:

```console
./scripts/generate-appcast.sh 0.3.0
git add appcast.xml
git commit -m "Update appcast for TuneDrop 0.3.0"
git push
```

Keep an encrypted backup of the private Sparkle key outside the repository.
Never commit the exported private key.

## Install for development

TuneDrop requires Python 3.11 or newer and FFmpeg:

```console
brew install ffmpeg
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e '.[dev]'
pytest
```

## Spotify credentials

Create an app in the [Spotify developer dashboard](https://developer.spotify.com/dashboard),
call it Tunedrop, enable the Web API, and add `http://127.0.0.1:8888/callback`
as a redirect URI. Then export its client credentials:

```console
export tunedrop_client_id="your-client-id"
export tunedrop_client_secret="your-client-secret"
```

TuneDrop never stores these values.

Playlist downloads open Spotify in your browser for authorization. Spotify only
allows access to playlists you own or collaborate on.

## Usage

```console
tunedrop "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
tunedrop -o ~/Music/Archive --format m4a "https://open.spotify.com/album/..."
tunedrop --format flac "https://open.spotify.com/playlist/..."
```

Run `tunedrop --help` for all options. Existing files are skipped unless
`--overwrite` is provided.

Only download media you are authorized to access. You are responsible for
following the source platform's terms and applicable copyright law.