from dataclasses import replace
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


def test_download_uses_fallback_search_when_primary_has_no_result(
    monkeypatch, tmp_path: Path
) -> None:
    track = make_track()
    destination = MediaDownloader().destination(track, tmp_path)
    searches: list[str] = []

    class FakeYoutubeDL:
        def __init__(self, options: dict) -> None:
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args) -> None:
            pass

        def download(self, urls: list[str]) -> None:
            searches.extend(urls)
            if len(searches) == 2:
                destination.write_bytes(b"audio")

    monkeypatch.setattr("tunedrop.downloader.shutil.which", lambda name: "/usr/bin/ffmpeg")
    monkeypatch.setattr("tunedrop.downloader.YoutubeDL", FakeYoutubeDL)

    result = MediaDownloader().download(track, tmp_path)

    assert result == destination
    assert searches == [
        'ytsearch5:Artist/Guest - Song: "Live"? audio',
        'ytsearch5:Song: "Live"? official audio',
    ]


def test_download_uses_base_title_as_final_fallback(monkeypatch, tmp_path: Path) -> None:
    track = replace(make_track(), title="Song (feat. Guest)")
    destination = MediaDownloader().destination(track, tmp_path)
    searches: list[str] = []

    class FakeYoutubeDL:
        def __init__(self, options: dict) -> None:
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args) -> None:
            pass

        def download(self, urls: list[str]) -> None:
            searches.extend(urls)
            if len(searches) == 6:
                destination.write_bytes(b"audio")

    monkeypatch.setattr("tunedrop.downloader.shutil.which", lambda name: "/usr/bin/ffmpeg")
    monkeypatch.setattr("tunedrop.downloader.YoutubeDL", FakeYoutubeDL)

    MediaDownloader().download(track, tmp_path)

    assert searches[-2:] == [
        "ytsearch5:Artist/Guest Song",
        "ytsearch5:Song",
    ]