#!/usr/bin/env python3
"""Normalize FLAC ALBUM tags to match Lidarr/MusicBrainz names.

Spotify metadata uses straight quotes ('), Lidarr/MusicBrainz uses curly quotes (').
This script queries Lidarr's lookup API for the correct album title and updates
FLAC tags when they differ.
"""

import os
import json
import subprocess
import sys
import urllib.request
import urllib.parse
from pathlib import Path


def get_lidarr_album_title(api_url, api_key, artist_name, album_name):
    """Query Lidarr album lookup for the MusicBrainz-correct album title."""
    url = f"{api_url}/api/v1/album/lookup?term={urllib.parse.quote(album_name)}"
    req = urllib.request.Request(url, headers={"X-Api-Key": api_key})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            results = json.loads(resp.read())
        for r in results:
            r_artist = r.get("artist", {}).get("artistName", "").lower()
            if artist_name.lower() in r_artist or r_artist in artist_name.lower():
                mb_title = r.get("title", "")
                if mb_title and mb_title != album_name:
                    return mb_title
    except Exception:
        pass
    return None


def get_flac_tags(path):
    """Extract common tags from a FLAC file."""
    r = subprocess.run(
        ["metaflac", "--show-tag=ALBUM", "--show-tag=ALBUMARTIST", "--show-tag=ARTIST", path],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return {}
    tags = {}
    for line in r.stdout.strip().split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            tags[k] = v
    return tags


def main():
    download_dir = os.environ.get("DOWNLOAD_DIR", "/home/ubuntu/lidarr-data/_spotiflac")
    lidarr_url = os.environ.get("LIDARR_URL", "http://navidrome:8888")
    api_key = os.environ.get("LIDARR_API_KEY", "")

    if not api_key:
        print("[fix_album_tags] No LIDARR_API_KEY set — skipping")
        return

    if not Path(download_dir).is_dir():
        print(f"[fix_album_tags] {download_dir} not found — skipping")
        return

    # Collect unique (artist, album) pairs
    albums = {}
    for root, dirs, files in os.walk(download_dir):
        for f in files:
            if not f.lower().endswith(".flac"):
                continue
            path = os.path.join(root, f)
            tags = get_flac_tags(path)
            album = tags.get("ALBUM", "")
            artist = tags.get("ALBUMARTIST", "") or tags.get("ARTIST", "")
            if album and artist:
                albums[(artist, album)] = path

    if not albums:
        print("[fix_album_tags] No FLAC files found")
        return

    # Look up each album in Lidarr
    fixed = 0
    for (artist, old_album), sample_path in albums.items():
        new_album = get_lidarr_album_title(lidarr_url, api_key, artist, old_album)
        if not new_album or new_album == old_album:
            continue

        print(f"[fix_album_tags] {artist} — '{old_album}' → '{new_album}'")
        # Update all FLACs with this album
        for root, dirs, files in os.walk(download_dir):
            for f in files:
                if not f.lower().endswith(".flac"):
                    continue
                path = os.path.join(root, f)
                tags = get_flac_tags(path)
                if tags.get("ALBUM") == old_album and (
                    tags.get("ALBUMARTIST", "") == artist or tags.get("ARTIST", "") == artist
                ):
                    subprocess.run(
                        ["metaflac", "--remove-tag=ALBUM", path],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    subprocess.run(
                        ["metaflac", f"--set-tag=ALBUM={new_album}", path],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    fixed += 1

    print(f"[fix_album_tags] Fixed {fixed} file(s)")


if __name__ == "__main__":
    main()
