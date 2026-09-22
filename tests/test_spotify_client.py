from tunedrop.spotify import SpotifyClient


def test_maps_track_payload_to_model() -> None:
    track = SpotifyClient._track_from_payload(
        {
            "id": "4uLU6hMCjMI75M1A2tKUQC",
            "name": "Never Gonna Give You Up",
            "artists": [{"name": "Rick Astley"}],
            "track_number": 1,
            "disc_number": 1,
            "duration_ms": 213_573,
            "album": {
                "name": "Whenever You Need Somebody",
                "artists": [{"name": "Rick Astley"}],
                "release_date": "1987-11-12",
                "images": [{"url": "https://i.scdn.co/image/example"}],
            },
        }
    )

    assert track.title == "Never Gonna Give You Up"
    assert track.artists == ("Rick Astley",)
    assert track.album == "Whenever You Need Somebody"
    assert track.cover_url == "https://i.scdn.co/image/example"
    assert track.search_query == "Rick Astley - Never Gonna Give You Up audio"


def test_page_items_follows_next_links(monkeypatch) -> None:
    client = SpotifyClient("client", "secret")
    monkeypatch.setattr(
        client,
        "_get",
        lambda url: {"items": [{"id": "second"}], "next": None},
    )

    items = client._page_items(
        {"items": [{"id": "first"}], "next": "https://api.spotify.com/v1/next"}
    )

    assert items == [{"id": "first"}, {"id": "second"}]