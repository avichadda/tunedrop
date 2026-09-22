import pytest

from tunedrop.spotify import SpotifyReference, SpotifyUrlError, parse_spotify_url


def test_parse_track_url_ignores_query_string() -> None:
    reference = parse_spotify_url(
        "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=example"
    )

    assert reference == SpotifyReference("track", "4uLU6hMCjMI75M1A2tKUQC")


@pytest.mark.parametrize(
    "value",
    [
        "https://example.com/track/4uLU6hMCjMI75M1A2tKUQC",
        "spotify:track:4uLU6hMCjMI75M1A2tKUQC",
        "https://open.spotify.com/artist/4uLU6hMCjMI75M1A2tKUQC",
        "https://open.spotify.com/track/not-an-id",
    ],
)
def test_rejects_unsupported_urls(value: str) -> None:
    with pytest.raises(SpotifyUrlError):
        parse_spotify_url(value)