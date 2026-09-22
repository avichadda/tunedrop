from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Track:
    spotify_id: str
    title: str
    artists: tuple[str, ...]
    album: str
    album_artist: str
    track_number: int
    disc_number: int
    release_date: str | None
    cover_url: str | None
    duration_ms: int

    @property
    def search_query(self) -> str:
        return f"{self.artists[0]} - {self.title} audio"