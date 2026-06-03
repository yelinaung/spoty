#!/usr/bin/env python3
"""Trigger per-artist Lidarr refresh based on downloaded FLAC files.

Walks the download directory, extracts unique artist names from FLAC tags,
looks up each artist in Lidarr, and triggers a RefreshArtist command.
"""

import os
import json
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path


def lidarr_get(url, api_key):
    """GET request to Lidarr API."""
    req = urllib.request.Request(url, headers={"X-Api-Key": api_key})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def lidarr_post(url, api_key, data=None):
    """POST request to Lidarr API."""
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(
        url, data=body, headers={"X-Api-Key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def find_artists(download_dir):
    """Walk download dir and collect unique artist names from FLAC tags."""
    artists = set()
    for root, dirs, files in os.walk(download_dir):
        for f in files:
            if not f.lower().endswith(".flac"):
                continue
            path = os.path.join(root, f)
            r = subprocess.run(
                ["metaflac", "--show-tag=ALBUMARTIST", "--show-tag=ARTIST", path],
                capture_output=True, text=True,
            )
            if r.returncode != 0:
                continue
            for line in r.stdout.strip().split("\n"):
                if "=" in line:
                    artists.add(line.split("=", 1)[1])
    return artists


def main():
    download_dir = os.environ.get("DOWNLOAD_DIR", "/home/ubuntu/lidarr-data/_spotiflac")
    lidarr_url = os.environ.get("LIDARR_URL", "http://navidrome:8888")
    api_key = os.environ.get("LIDARR_API_KEY", "")

    if not api_key:
        print("[refresh_lidarr] No LIDARR_API_KEY set — skipping")
        return

    if not Path(download_dir).is_dir():
        print(f"[refresh_lidarr] {download_dir} not found — skipping")
        return

    artists = find_artists(download_dir)
    if not artists:
        print("[refresh_lidarr] No FLAC files found")
        return

    refreshed = 0
    for artist_name in sorted(artists):
        try:
            results = lidarr_get(
                f"{lidarr_url}/api/v1/artist/lookup?term={urllib.parse.quote(artist_name)}",
                api_key,
            )
            if results:
                artist_id = results[0]["id"]
                lidarr_post(f"{lidarr_url}/api/v1/command", api_key, {
                    "name": "RefreshArtist",
                    "artistId": artist_id,
                })
                print(f"[refresh_lidarr] {artist_name} (id={artist_id}) — refresh triggered")
                refreshed += 1
        except Exception as e:
            print(f"[refresh_lidarr] {artist_name} — failed: {e}")

    print(f"[refresh_lidarr] Triggered refresh for {refreshed} artist(s)")


if __name__ == "__main__":
    main()
