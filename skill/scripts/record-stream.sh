#!/bin/bash
# record-stream.sh — Record a livestream segment or download a video clip
# Supports: YouTube, Twitch, Kick, and any yt-dlp compatible URL
#
# Usage: record-stream.sh <url> [duration-minutes] [output-dir]
#   - For live streams: records for the specified duration
#   - For VODs/videos: downloads the full video (or first N minutes)
#
# Environment:
#   CLIPPER_QUALITY    — max video height (default: 1080)
#   YT_DLP_COOKIES     — path to cookies file for auth-required streams

set -euo pipefail

STREAM_URL="${1:?Usage: record-stream.sh <stream-url> [duration-minutes] [output-dir]}"
DURATION_MIN="${2:-10}"
OUTPUT_DIR="${3:-.}"
MAX_HEIGHT="${CLIPPER_QUALITY:-1080}"

# Validate yt-dlp exists
if ! command -v yt-dlp &>/dev/null; then
    echo "Error: yt-dlp not found. Install with: brew install yt-dlp" >&2
    exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg not found. Install with: brew install ffmpeg" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/stream_${TIMESTAMP}.mp4"
DURATION_SEC=$((DURATION_MIN * 60))

echo "Recording: $STREAM_URL" >&2
echo "Duration: ${DURATION_MIN} minutes (${DURATION_SEC}s)" >&2
echo "Output: $OUTPUT_FILE" >&2

# Build yt-dlp arguments
YT_ARGS=(
    --downloader ffmpeg
    --downloader-args "ffmpeg:-t $DURATION_SEC"
    --format "best[height<=${MAX_HEIGHT}]/best"
    --no-part
    --no-playlist
    --output "$OUTPUT_FILE"
)

# Add cookies if provided
if [ -n "${YT_DLP_COOKIES:-}" ] && [ -f "${YT_DLP_COOKIES}" ]; then
    YT_ARGS+=(--cookies "$YT_DLP_COOKIES")
    echo "Using cookies file: $YT_DLP_COOKIES" >&2
fi

# Check if stream/video is available first
echo "Checking availability..." >&2
if ! yt-dlp --simulate --no-playlist "$STREAM_URL" >/dev/null 2>&1; then
    echo "Error: Cannot access URL. Stream may be offline or URL is invalid." >&2
    echo "Tip: If the stream requires login, set YT_DLP_COOKIES to a cookies.txt file" >&2
    exit 1
fi

# Record (all yt-dlp output goes to stderr)
echo "Recording started at $(date '+%H:%M:%S')..." >&2
if ! yt-dlp "${YT_ARGS[@]}" "$STREAM_URL" >&2 2>&1; then
    echo "Error: Recording failed. Check URL and try again." >&2
    exit 1
fi

# Validate output
if [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
    echo "Error: Output file is missing or empty" >&2
    exit 1
fi

# Get file metadata
FILESIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null | cut -d. -f1)
RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")

echo "Recording complete: $FILESIZE, ${ACTUAL_DURATION}s, ${RESOLUTION}" >&2

# Output JSON result (machine-readable)
cat << EOF
{
  "file": "$OUTPUT_FILE",
  "url": "$STREAM_URL",
  "requested_duration": $DURATION_SEC,
  "actual_duration": ${ACTUAL_DURATION:-0},
  "size": "$FILESIZE",
  "resolution": "$RESOLUTION",
  "timestamp": "$TIMESTAMP"
}
EOF
