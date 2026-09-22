import os
from dataclasses import dataclass
from typing import Literal
from urllib.parse import urlparse

import requests

from tunedrop.models import Track


class SpotifyUrlError(ValueError):
    """Raised when a URL is not a supported Spotify media URL."""


class SpotifyApiError(RuntimeError):
    """Raised when Spotify metadata cannot be resolved."""


@dataclass(frozen=True, slots=True)
class SpotifyReference:
    kind: Literal["track", "album", "playlist"]
    spotify_id: str


def parse_spotify_url(value: str) -> SpotifyReference:
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or parsed.hostname not in {
        "open.spotify.com",
        "www.open.spotify.com",
    }:
        raise SpotifyUrlError("Expected an open.spotify.com URL")

    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) != 2 or parts[0] not in {"track", "album", "playlist"}:
        raise SpotifyUrlError("Supported Spotify URL types: track, album, playlist")

    spotify_id = parts[1]
    if not spotify_id.isalnum() or len(spotify_id) != 22:
        raise SpotifyUrlError("Spotify URL contains an invalid media ID")

    return SpotifyReference(kind=parts[0], spotify_id=spotify_id)  # type: ignore[arg-type]


class SpotifyClient:
    api_base = "https://api.spotify.com/v1"
    token_url = "https://accounts.spotify.com/api/token"

    def __init__(self, client_id: str, client_secret: str) -> None:
        if not client_id or not client_secret:
            raise SpotifyApiError(
                "Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET before downloading"
            )
        self._client_id = client_id
        self._client_secret = client_secret
        self._session = requests.Session()
        self._access_token: str | None = None

    @classmethod
    def from_environment(cls) -> "SpotifyClient":
        return cls(
            os.environ.get("SPOTIFY_CLIENT_ID", ""),
            os.environ.get("SPOTIFY_CLIENT_SECRET", ""),
        )

    def resolve(self, reference: SpotifyReference) -> list[Track]:
        if reference.kind == "track":
            return [self._track_from_payload(self._get(f"tracks/{reference.spotify_id}"))]
        if reference.kind == "album":
            return self._resolve_album(reference.spotify_id)
        return self._resolve_playlist(reference.spotify_id)

    def _token(self) -> str:
        if self._access_token is not None:
            return self._access_token
        try:
            response = self._session.post(
                self.token_url,
                auth=(self._client_id, self._client_secret),
                data={"grant_type": "client_credentials"},
                timeout=20,
            )
            response.raise_for_status()
            self._access_token = response.json()["access_token"]
        except (requests.RequestException, KeyError, ValueError) as error:
            raise SpotifyApiError(f"Spotify authentication failed: {error}") from error
        return self._access_token

    def _get(self, path_or_url: str) -> dict:
        url = (
            path_or_url
            if path_or_url.startswith("https://")
            else f"{self.api_base}/{path_or_url}"
        )
        try:
            response = self._session.get(
                url,
                headers={"Authorization": f"Bearer {self._token()}"},
                timeout=20,
            )
            response.raise_for_status()
            payload = response.json()
        except (requests.RequestException, ValueError) as error:
            raise SpotifyApiError(f"Spotify metadata request failed: {error}") from error
        if not isinstance(payload, dict):
            raise SpotifyApiError("Spotify returned an unexpected response")
        return payload

    def _resolve_album(self, spotify_id: str) -> list[Track]:
        album = self._get(f"albums/{spotify_id}")
        tracks_page = album.get("tracks")
        if not isinstance(tracks_page, dict):
            raise SpotifyApiError("Spotify album metadata has no track list")
        tracks = self._page_items(tracks_page)
        return [self._track_from_payload(item, album=album) for item in tracks]

    def _resolve_playlist(self, spotify_id: str) -> list[Track]:
        playlist = self._get(f"playlists/{spotify_id}")
        tracks_page = playlist.get("tracks")
        if not isinstance(tracks_page, dict):
            raise SpotifyApiError("Spotify playlist metadata has no track list")
        items = self._page_items(tracks_page)
        return [
            self._track_from_payload(item["track"])
            for item in items
            if isinstance(item.get("track"), dict) and item["track"].get("type") == "track"
        ]

    def _page_items(self, first_page: dict) -> list[dict]:
        items = list(first_page.get("items", []))
        next_url = first_page.get("next")
        while next_url:
            page = self._get(next_url)
            items.extend(page.get("items", []))
            next_url = page.get("next")
        return items

    @staticmethod
    def _track_from_payload(payload: dict, album: dict | None = None) -> Track:
        album_payload = album or payload.get("album", {})
        artists = tuple(artist["name"] for artist in payload.get("artists", []))
        album_artists = album_payload.get("artists", [])
        images = album_payload.get("images", [])
        if not artists:
            raise SpotifyApiError("Spotify track metadata has no artist")
        if not payload.get("id") or not payload.get("name"):
            raise SpotifyApiError("Spotify track metadata is incomplete")
        return Track(
            spotify_id=payload["id"],
            title=payload["name"],
            artists=artists,
            album=album_payload.get("name", ""),
            album_artist=album_artists[0]["name"] if album_artists else artists[0],
            track_number=payload.get("track_number", 0),
            disc_number=payload.get("disc_number", 0),
            release_date=album_payload.get("release_date"),
            cover_url=images[0]["url"] if images else None,
            duration_ms=payload.get("duration_ms", 0),
        )