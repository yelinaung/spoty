# SpotiFLAC Bulk Downloader

Automate downloading Spotify tracks, albums, playlists, and artist discographies as FLAC files, then auto-import into Lidarr/Navidrome.

## Setup

```bash
# Install SpotiFLAC CLI
uv tool install spotiflac

# Install ffmpeg (required for Amazon Music downloads)
sudo apt install -y ffmpeg metaflac

# Configure Lidarr API key
echo "LIDARR_API_KEY=your-lidarr-api-key" > .env

# Optional: one-time Lidarr download client setup
./setup-lidarr-watch.sh
```

## Usage

```bash
# Add URLs to urls.txt (one per line)
./spotiflac-bulk.sh urls.txt

# Override defaults
PROVIDERS="deezer amazon" RETRIES=5 ./spotiflac-bulk.sh urls.txt
```

### Supported URL types

| Type | Format |
|------|--------|
| Artist | `https://open.spotify.com/artist/...` |
| Album | `https://open.spotify.com/album/...` |
| Track | `https://open.spotify.com/track/...` |
| Playlist | `https://open.spotify.com/playlist/...` |

### Config (via env vars or `.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `DOWNLOAD_DIR` | `/home/ubuntu/lidarr-data/_spotiflac` | Output directory |
| `PROVIDERS` | `deezer qobuz amazon` | Providers in priority order |
| `QUALITY` | `LOSSLESS` | Download quality |
| `RETRIES` | `2` | Retry attempts per track |
| `LIDARR_API_KEY` | — | Lidarr API key for auto-import |
| `LIDARR_URL` | `http://navidrome:8888` | Lidarr URL |

## Pipeline

```
urls.txt → spotiflac-bulk.sh → ~/lidarr-data/_spotiflac/ → Lidarr → Navidrome
```

- Downloads land in `$DOWNLOAD_DIR` with artist/album subfolders
- Description tag auto-stripped from FLAC files
- Lidarr import triggered automatically when `LIDARR_API_KEY` is set
- Failed URLs saved to `./logs/failed_*.txt` for retry
