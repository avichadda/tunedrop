import base64
from pathlib import Path

import requests
from mutagen import File
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, ID3
from mutagen.mp4 import MP4, MP4Cover
from mutagen.oggopus import OggOpus

from tunedrop.models import Track


class TaggingError(RuntimeError):
    """Raised when audio metadata cannot be written."""


def write_tags(path: Path, track: Track) -> None:
    audio = File(path, easy=True)
    if audio is None:
        raise TaggingError(f"Unsupported audio file: {path.name}")
    audio["title"] = [track.title]
    audio["artist"] = list(track.artists)
    audio["album"] = [track.album]
    audio["albumartist"] = [track.album_artist]
    audio["tracknumber"] = [str(track.track_number)]
    audio["discnumber"] = [str(track.disc_number)]
    if track.release_date:
        audio["date"] = [track.release_date]
    audio.save()

    if track.cover_url:
        image_data, mime = _download_cover(track.cover_url)
        _write_cover(path, image_data, mime)


def _download_cover(url: str) -> tuple[bytes, str]:
    try:
        response = requests.get(url, timeout=20)
        response.raise_for_status()
    except requests.RequestException as error:
        raise TaggingError(f"Cover art download failed: {error}") from error
    mime = response.headers.get("Content-Type", "image/jpeg").split(";", 1)[0]
    return response.content, mime


def _write_cover(path: Path, image_data: bytes, mime: str) -> None:
    if path.suffix.lower() == ".mp3":
        tags = ID3(path)
        tags.delall("APIC")
        tags.add(APIC(mime=mime, type=3, desc="Cover", data=image_data))
        tags.save(path)
    elif path.suffix.lower() == ".m4a":
        audio = MP4(path)
        image_format = MP4Cover.FORMAT_PNG if mime == "image/png" else MP4Cover.FORMAT_JPEG
        audio["covr"] = [MP4Cover(image_data, imageformat=image_format)]
        audio.save()
    elif path.suffix.lower() == ".flac":
        audio = FLAC(path)
        picture = Picture()
        picture.type = 3
        picture.mime = mime
        picture.desc = "Cover"
        picture.data = image_data
        audio.clear_pictures()
        audio.add_picture(picture)
        audio.save()
    elif path.suffix.lower() == ".opus":
        audio = OggOpus(path)
        picture = Picture()
        picture.type = 3
        picture.mime = mime
        picture.desc = "Cover"
        picture.data = image_data
        audio["metadata_block_picture"] = [
            base64.b64encode(picture.write()).decode("ascii")
        ]
        audio.save()