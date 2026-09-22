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
brew tap avichadda/tunedrop https://github.com/avichadda/spotipy
brew install --HEAD avichadda/tunedrop/tunedrop
```

Homebrew installs FFmpeg and the required Python runtime automatically. Upgrade
the head build with:

```console
brew upgrade --fetch-HEAD avichadda/tunedrop/tunedrop
```

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
then export its client credentials:

```console
export SPOTIFY_CLIENT_ID="your-client-id"
export SPOTIFY_CLIENT_SECRET="your-client-secret"
```

TuneDrop never stores these values.

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