#!/bin/bash
set -euo pipefail

# ── Load .env ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

# ── Config ──────────────────────────────────────────────
URLS_FILE="${1:-urls.txt}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/home/ubuntu/lidarr-data/_spotiflac}"
LOG_DIR="${LOG_DIR:-./logs}"

# Providers in priority order (first available wins)
PROVIDERS="${PROVIDERS:-deezer qobuz amazon}"
QUALITY="${QUALITY:-LOSSLESS}"
RETRIES="${RETRIES:-2}"

# Lidarr API (optional — set LIDARR_API_KEY to enable import trigger)
LIDARR_URL="${LIDARR_URL:-http://navidrome:8888}"
LIDARR_API_KEY="${LIDARR_API_KEY:-}"

# ── Setup ───────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/run_$TIMESTAMP.log"
FAILED_FILE="$LOG_DIR/failed_$TIMESTAMP.txt"

mkdir -p "$DOWNLOAD_DIR" "$LOG_DIR"

success=0
failed=0
skipped=0
total=0

# ── Helpers ─────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

url_type() {
    local url="$1"
    if echo "$url" | grep -qP '/artist/'; then
        echo "artist"
    elif echo "$url" | grep -qP '/album/'; then
        echo "album"
    elif echo "$url" | grep -qP '/(playlist|sets)/|/playlist\?'; then
        echo "playlist"
    elif echo "$url" | grep -qP '/track/'; then
        echo "track"
    else
        echo "unknown"
    fi
}

download_url() {
    local url="$1"
    local type
    type=$(url_type "$url")

    log "START $url  [$type]"

    local extra_args=()
    extra_args+=(--quality "$QUALITY")
    extra_args+=(-s $PROVIDERS)
    extra_args+=(--retries "$RETRIES")

    case "$type" in
        artist)
            extra_args+=(--use-artist-subfolders)
            extra_args+=(--use-album-subfolders)
            extra_args+=(--filename-format "{year} - {album}/{track}. {title}")
            ;;
        album|playlist)
            extra_args+=(--use-artist-subfolders)
            extra_args+=(--use-album-subfolders)
            ;;
    esac

    spotiflac "$url" "$DOWNLOAD_DIR" "${extra_args[@]}" >> "$LOG_FILE" 2>&1

    local rc=$?
    if [ $rc -eq 0 ]; then
        log "OK    $url"
        ((success++))
    else
        log "FAIL  $url  (exit=$rc)"
        echo "$url" >> "$FAILED_FILE"
        ((failed++))
    fi
    return $rc
}

trigger_lidarr_scan() {
    if [ -z "$LIDARR_API_KEY" ]; then
        log "SKIP  Lidarr scan (no API key set)"
        return 0
    fi
    log "LDR   Triggering per-artist Lidarr refresh..."
    DOWNLOAD_DIR="$DOWNLOAD_DIR" LIDARR_URL="$LIDARR_URL" LIDARR_API_KEY="$LIDARR_API_KEY" \
        python3 "$SCRIPT_DIR/refresh_lidarr.py" 2>&1 | tee -a "$LOG_FILE"
}

copy_to_library() {
    local src="${1:-$DOWNLOAD_DIR}"
    local dest="/mnt/music"
    log "COPY  Moving files to library..."
    local count=0
    while IFS= read -r -d '' flac; do
        local artist album
        artist=$(metaflac --show-tag=ALBUMARTIST "$flac" 2>/dev/null | sed 's/ALBUMARTIST=//')
        test -z "$artist" && artist=$(metaflac --show-tag=ARTIST "$flac" 2>/dev/null | sed 's/ARTIST=//')
        album=$(metaflac --show-tag=ALBUM "$flac" 2>/dev/null | sed 's/ALBUM=//')
        test -z "$artist" -o -z "$album" && continue
        local target_dir="$dest/$artist/$album"
        mkdir -p "$target_dir"
        cp -n "$flac" "$target_dir/" 2>/dev/null && ((count++))
    done < <(find "$src" -type f \( -name '*.flac' -o -name '*.FLAC' \) -print0 2>/dev/null)
    log "COPY  Copied $count file(s) to library"
}

strip_note_tags() {
    local dir="${1:-$DOWNLOAD_DIR}"
    if ! command -v metaflac &>/dev/null; then
        log "TAG   Skipping tag cleanup (metaflac not found)"
        return 0
    fi
    log "TAG   Stripping SpotiFLAC note from FLAC files..."
    local count=0
    while IFS= read -r -d '' flac; do
        metaflac --remove-tag=DESCRIPTION "$flac" 2>/dev/null && ((count++))
    done < <(find "$dir" -type f \( -name '*.flac' -o -name '*.FLAC' \) -print0 2>/dev/null)
    log "TAG   Cleaned $count files"
}

# ── Main ────────────────────────────────────────────────
if [ ! -f "$URLS_FILE" ]; then
    echo "Error: $URLS_FILE not found"
    echo "Usage: $0 <urls.txt>"
    exit 1
fi

total=$(grep -cEv '^\s*(#|$)' "$URLS_FILE" || true)
log "========================================="
log "Spotiflac Bulk Download"
log "URLs file : $URLS_FILE  ($total urls)"
log "Output    : $DOWNLOAD_DIR"
log "Providers : $PROVIDERS"
log "Quality   : $QUALITY"
log "Retries   : $RETRIES"
log "Log       : $LOG_FILE"
log "========================================="

while IFS= read -r url; do
    # skip empty lines and comments
    [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue
    download_url "$url"
done < "$URLS_FILE"

# ── Post-processing ──────────────────────────────────────
if [ "$success" -gt 0 ]; then
    log "FIX   Normalizing album tags for Lidarr..."
    DOWNLOAD_DIR="$DOWNLOAD_DIR" LIDARR_URL="$LIDARR_URL" LIDARR_API_KEY="$LIDARR_API_KEY" \
        python3 "$SCRIPT_DIR/fix_album_tags.py" 2>&1 | tee -a "$LOG_FILE"

    strip_note_tags

    copy_to_library
fi

# ── Summary ─────────────────────────────────────────────
log "========================================="
log "DONE — $total total | $success OK | $failed failed | $skipped skipped"
log "========================================="

if [ "$success" -gt 0 ]; then
    trigger_lidarr_scan
fi

if [ $failed -gt 0 ]; then
    log "Failed URLs saved to: $FAILED_FILE"
fi
