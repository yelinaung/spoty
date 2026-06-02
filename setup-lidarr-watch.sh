#!/bin/bash
# Configure Lidarr Torrent Blackhole to auto-import from /downloads/
# Run ONCE to set up; requires LIDARR_API_KEY
set -euo pipefail

# ── Load .env ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

LIDARR_URL="${LIDARR_URL:-http://navidrome:8888}"
LIDARR_API_KEY="${LIDARR_API_KEY:?Set LIDARR_API_KEY in .env}"

echo "Checking if _spotiflac download client exists..."
existing=$(curl -s -H "X-Api-Key: $LIDARR_API_KEY" "$LIDARR_URL/api/v1/downloadclient" | \
    python3 -c "import sys,json; clients=json.load(sys.stdin); print(any('_spotiflac' in c.get('name','') for c in clients))" 2>/dev/null || echo "False")

if [ "$existing" = "True" ]; then
    echo "SpotiFLAC download client already configured."
else
    echo "Creating Torrent Blackhole client for SpotiFLAC..."
    curl -s -X POST "$LIDARR_URL/api/v1/downloadclient" \
        -H "X-Api-Key: $LIDARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "enable": true,
            "name": "_spotiflac",
            "implementation": "TorrentBlackhole",
            "configContract": "TorrentBlackholeSettings",
            "fields": [
                {"name": "torrentFolder",     "value": "/downloads/"},
                {"name": "watchFolder",       "value": "/downloads/"},
                {"name": "readOnly",          "value": false},
                {"name": "saveMagnetFiles",   "value": false}
            ]
        }' | python3 -m json.tool
    echo ""
    echo "Done. Lidarr will now watch /downloads/ for new downloads."
fi

echo ""
echo "To trigger a manual scan right now:"
echo "  curl -X POST '$LIDARR_URL/api/v1/command' \\"
echo "    -H 'X-Api-Key: $LIDARR_API_KEY' \\"
echo "    -d '{\"name\":\"DownloadedAlbumsScan\",\"path\":\"/downloads\"}'"
