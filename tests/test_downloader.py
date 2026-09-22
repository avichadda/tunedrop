from pathlib import Path

from tunedrop.downloader import MediaDownloader, safe_filename
from tunedrop.models import Track


def make_track() -> Track:
    return Track(
        spotify_id="4uLU6hMCjMI75M1A2tKUQC",
        title='Song: "Live"?',
        artists=("Artist/Guest",),
        album="Album",
        album_artist="Artist",
        track_number=1,
        disc_number=1,
        release_date="2025-01-01",
        cover_url=None,
        duration_ms=180_000,
    )


def test_safe_filename_removes_filesystem_characters() -> None:
    assert safe_filename('A/B: C*D? "E"') == "A_B_ C_D_ _E_"


def test_destination_is_stable_and_includes_spotify_id(tmp_path: Path) -> None:
    destination = MediaDownloader("flac").destination(make_track(), tmp_path)

    assert destination == tmp_path / "Artist_Guest - Song_ _Live__ [4uLU6hMCjMI75M1A2tKUQC].flac"