import os
import secrets
import webbrowser
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Literal
from urllib.parse import parse_qs, urlencode, urlparse

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
    authorize_url = "https://accounts.spotify.com/authorize"
    token_url = "https://accounts.spotify.com/api/token"
    redirect_uri = "http://127.0.0.1:8888/callback"

    def __init__(self, client_id: str, client_secret: str) -> None:
        if not client_id or not client_secret:
            raise SpotifyApiError(
                "Set tunedrop_client_id and tunedrop_client_secret before downloading"
            )
        self._client_id = client_id
        self._client_secret = client_secret
        self._session = requests.Session()
        self._app_access_token: str | None = None
        self._user_access_token: str | None = None

    @classmethod
    def from_environment(cls) -> "SpotifyClient":
        return cls(
            os.environ.get(
                "tunedrop_client_id",  # noqa: SIM112
                os.environ.get("SPOTIFY_CLIENT_ID", ""),
            ),
            os.environ.get(
                "tunedrop_client_secret",  # noqa: SIM112
                os.environ.get("SPOTIFY_CLIENT_SECRET", ""),
            ),
        )

    def resolve(self, reference: SpotifyReference) -> list[Track]:
        if reference.kind == "track":
            return [self._track_from_payload(self._get(f"tracks/{reference.spotify_id}"))]
        if reference.kind == "album":
            return self._resolve_album(reference.spotify_id)
        return self._resolve_playlist(reference.spotify_id)

    def _app_token(self) -> str:
        if self._app_access_token is not None:
            return self._app_access_token
        try:
            response = self._session.post(
                self.token_url,
                auth=(self._client_id, self._client_secret),
                data={"grant_type": "client_credentials"},
                timeout=20,
            )
            response.raise_for_status()
            self._app_access_token = response.json()["access_token"]
        except (requests.RequestException, KeyError, ValueError) as error:
            raise SpotifyApiError(f"Spotify authentication failed: {error}") from error
        return self._app_access_token

    def _user_token(self) -> str:
        if self._user_access_token is not None:
            return self._user_access_token

        state = secrets.token_urlsafe(24)
        result: dict[str, str] = {}

        class CallbackHandler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                query = parse_qs(urlparse(self.path).query)
                result.update({key: values[0] for key, values in query.items() if values})
                body = b"Spotify authorization complete. You can close this window."
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                pass

        parameters = urlencode(
            {
                "client_id": self._client_id,
                "response_type": "code",
                "redirect_uri": self.redirect_uri,
                "scope": "playlist-read-private",
                "state": state,
            }
        )
        authorization_url = f"{self.authorize_url}?{parameters}"
        try:
            server = HTTPServer(("127.0.0.1", 8888), CallbackHandler)
        except OSError as error:
            raise SpotifyApiError(f"Could not start Spotify callback server: {error}") from error
        server.timeout = 180
        print("Opening Spotify authorization in your browser...")
        if not webbrowser.open(authorization_url):
            print(f"Open this URL to continue: {authorization_url}")
        server.handle_request()
        server.server_close()

        if result.get("state") != state:
            raise SpotifyApiError("Spotify authorization timed out or returned invalid state")
        if "error" in result:
            raise SpotifyApiError(f"Spotify authorization failed: {result['error']}")
        code = result.get("code")
        if not code:
            raise SpotifyApiError("Spotify authorization did not return a code")

        try:
            response = self._session.post(
                self.token_url,
                auth=(self._client_id, self._client_secret),
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": self.redirect_uri,
                },
                timeout=20,
            )
            response.raise_for_status()
            self._user_access_token = response.json()["access_token"]
        except (requests.RequestException, KeyError, ValueError) as error:
            raise SpotifyApiError(f"Spotify user authentication failed: {error}") from error
        return self._user_access_token

    def _get(self, path_or_url: str, *, user_token: bool = False) -> dict:
        url = (
            path_or_url
            if path_or_url.startswith("https://")
            else f"{self.api_base}/{path_or_url}"
        )
        access_token = self._user_token() if user_token else self._app_token()
        try:
            response = self._session.get(
                url,
                headers={"Authorization": f"Bearer {access_token}"},
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
        first_page = self._get(f"playlists/{spotify_id}/items", user_token=True)
        entries = self._page_items(first_page, user_token=True)
        tracks = []
        for entry in entries:
            item = entry.get("item", entry.get("track"))
            if isinstance(item, dict) and item.get("type") == "track":
                tracks.append(self._track_from_payload(item))
        return tracks

    def _page_items(self, first_page: dict, *, user_token: bool = False) -> list[dict]:
        items = list(first_page.get("items", []))
        next_url = first_page.get("next")
        while next_url:
            page = self._get(next_url, user_token=user_token)
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