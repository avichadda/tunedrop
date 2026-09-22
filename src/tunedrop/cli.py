from pathlib import Path
from typing import Annotated

import typer

from tunedrop import __version__
from tunedrop.downloader import AudioFormat, MediaDownloader, MediaDownloadError
from tunedrop.spotify import SpotifyApiError, SpotifyClient, SpotifyUrlError, parse_spotify_url
from tunedrop.tags import TaggingError, write_tags

app = typer.Typer(
    add_completion=False,
    no_args_is_help=True,
    help="Resolve Spotify metadata and archive matching public audio.",
)


def version_callback(value: bool) -> None:
    if value:
        typer.echo(__version__)
        raise typer.Exit()


@app.command()
def download(
    url: Annotated[str, typer.Argument(help="Spotify track, album, or playlist URL")],
    output: Annotated[
        Path, typer.Option("--output", "-o", help="Directory for completed audio")
    ] = Path("Music"),
    audio_format: Annotated[
        AudioFormat, typer.Option("--format", "-f", help="Output audio format")
    ] = "mp3",
    bitrate: Annotated[
        int, typer.Option("--bitrate", min=64, max=320, help="Lossy audio bitrate in kbps")
    ] = 320,
    overwrite: Annotated[bool, typer.Option(help="Replace files already present")] = False,
    version: Annotated[
        bool | None,
        typer.Option("--version", callback=version_callback, is_eager=True, help="Show version"),
    ] = None,
) -> None:
    """Download one track, album, or playlist."""
    del version
    try:
        reference = parse_spotify_url(url)
        tracks = SpotifyClient.from_environment().resolve(reference)
        downloader = MediaDownloader(audio_format, bitrate)
        typer.echo(f"Resolved {len(tracks)} track(s)")
        failures = 0
        for index, track in enumerate(tracks, start=1):
            typer.echo(f"[{index}/{len(tracks)}] {track.artists[0]} - {track.title}")
            try:
                path = downloader.download(track, output, overwrite)
                write_tags(path, track)
            except (MediaDownloadError, TaggingError) as error:
                failures += 1
                typer.echo(f"  failed: {error}", err=True)
        if failures:
            raise typer.Exit(code=1)
    except (SpotifyUrlError, SpotifyApiError) as error:
        typer.echo(f"Error: {error}", err=True)
        raise typer.Exit(code=1) from error