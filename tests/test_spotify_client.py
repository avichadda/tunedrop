from tunedrop.spotify import SpotifyClient


def test_from_environment_uses_tunedrop_credentials(monkeypatch) -> None:
    monkeypatch.setenv("tunedrop_client_id", "client")
    monkeypatch.setenv("tunedrop_client_secret", "secret")

    client = SpotifyClient.from_environment()

    assert client._client_id == "client"
    assert client._client_secret == "secret"


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
        lambda url, **kwargs: {"items": [{"id": "second"}], "next": None},
    )

    items = client._page_items(
        {"items": [{"id": "first"}], "next": "https://api.spotify.com/v1/next"}
    )

    assert items == [{"id": "first"}, {"id": "second"}]


def test_resolve_playlist_uses_user_authorized_items(monkeypatch) -> None:
    client = SpotifyClient("client", "secret")
    requested: list[tuple[str, bool]] = []

    def get(path: str, *, user_token: bool = False) -> dict:
        requested.append((path, user_token))
        return {
            "items": [
                {
                    "item": {
                        "id": "4uLU6hMCjMI75M1A2tKUQC",
                        "name": "Never Gonna Give You Up",
                        "type": "track",
                        "artists": [{"name": "Rick Astley"}],
                        "album": {"name": "Whenever You Need Somebody"},
                    }
                }
            ],
            "next": None,
        }

    monkeypatch.setattr(client, "_get", get)

    tracks = client._resolve_playlist("7bO7mIn2NcCzujsBUCfzl8")

    assert requested == [("playlists/7bO7mIn2NcCzujsBUCfzl8/items", True)]
    assert [track.title for track in tracks] == ["Never Gonna Give You Up"]