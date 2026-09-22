import re
import shutil
from pathlib import Path
from typing import Literal

from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError

from tunedrop.models import Track

AudioFormat = Literal["mp3", "m4a", "flac", "opus"]


class MediaDownloadError(RuntimeError):
    """Raised when a matching media source cannot be downloaded."""


def safe_filename(value: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", value)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return cleaned[:180] or "untitled"


class MediaDownloader:
    def __init__(self, audio_format: AudioFormat = "mp3", bitrate: int = 320) -> None:
        self.audio_format = audio_format
        self.bitrate = bitrate

    def destination(self, track: Track, output_dir: Path) -> Path:
        stem = safe_filename(f"{track.artists[0]} - {track.title} [{track.spotify_id}]")
        return output_dir / f"{stem}.{self.audio_format}"

    def download(self, track: Track, output_dir: Path, overwrite: bool = False) -> Path:
        if shutil.which("ffmpeg") is None:
            raise MediaDownloadError("FFmpeg is required but was not found on PATH")

        output_dir.mkdir(parents=True, exist_ok=True)
        destination = self.destination(track, output_dir)
        if destination.exists() and not overwrite:
            return destination

        template = str(destination.with_suffix(".%(ext)s"))

        def match_duration(info: dict, *, incomplete: bool) -> str | None:
            if incomplete:
                return None
            if info.get("is_live"):
                return "live streams are not supported"
            duration = info.get("duration")
            expected = track.duration_ms / 1000
            tolerance = max(20, expected * 0.15)
            if duration and expected and abs(duration - expected) > tolerance:
                return "duration differs from the Spotify metadata"
            return None

        options = {
            "format": "bestaudio/best",
            "match_filter": match_duration,
            "noplaylist": True,
            "outtmpl": template,
            "postprocessors": [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": self.audio_format,
                    "preferredquality": str(self.bitrate),
                }
            ],
            "quiet": True,
            "no_warnings": True,
            "overwrites": overwrite,
        }
        try:
            with YoutubeDL(options) as downloader:
                downloader.download([f"ytsearch5:{track.search_query}"])
        except DownloadError as error:
            raise MediaDownloadError(
                f"No suitable media found for {track.title}: {error}"
            ) from error

        if not destination.exists():
            raise MediaDownloadError(f"Conversion did not produce {destination.name}")
        return destination