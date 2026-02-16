#!/bin/bash
# post-clip.sh — Upload a video clip and post to social platforms via Postiz API
#
# Usage: post-clip.sh <video-file> <caption> [platforms] [schedule-time]
#   platforms: comma-separated list (tiktok,youtube,x,instagram) — default: all configured
#   schedule-time: ISO 8601 datetime or "now" (default: now)
#
# Environment (required):
#   POSTIZ_API_KEY         — Postiz API key
#   POSTIZ_BASE_URL        — API base URL (default: https://api.postiz.com/public/v1)
#
# Environment (optional):
#   POSTIZ_TIKTOK_ID       — TikTok integration ID
#   POSTIZ_YOUTUBE_ID      — YouTube integration ID
#   POSTIZ_X_ID            — X/Twitter integration ID
#   POSTIZ_INSTAGRAM_ID    — Instagram integration ID
#
# Config file: ~/.lxgic-clipper/config.json (auto-loaded if exists)

set -euo pipefail

# --- Load config ---
CONFIG_FILE="${HOME}/.lxgic-clipper/config.json"
if [ -f "$CONFIG_FILE" ]; then
    # Load integration IDs from config if not set in env
    if command -v jq &>/dev/null; then
        POSTIZ_API_KEY="${POSTIZ_API_KEY:-$(jq -r '.postiz_api_key // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_BASE_URL="${POSTIZ_BASE_URL:-$(jq -r '.postiz_base_url // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_TIKTOK_ID="${POSTIZ_TIKTOK_ID:-$(jq -r '.integrations.tiktok // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_YOUTUBE_ID="${POSTIZ_YOUTUBE_ID:-$(jq -r '.integrations.youtube // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_X_ID="${POSTIZ_X_ID:-$(jq -r '.integrations.x // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_INSTAGRAM_ID="${POSTIZ_INSTAGRAM_ID:-$(jq -r '.integrations.instagram // empty' "$CONFIG_FILE" 2>/dev/null)}"
    fi
fi

# --- Arguments ---
VIDEO_FILE="${1:?Usage: post-clip.sh <video-file> <caption> [platforms] [schedule-time]}"
CAPTION="${2:?Caption is required}"
PLATFORMS="${3:-tiktok,youtube,x,instagram}"
SCHEDULE="${4:-now}"

# --- Validate ---
POSTIZ_API_KEY="${POSTIZ_API_KEY:?Error: POSTIZ_API_KEY is required. Set it or run setup.sh}"
POSTIZ_BASE_URL="${POSTIZ_BASE_URL:-https://api.postiz.com/public/v1}"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Error: Video file not found: $VIDEO_FILE" >&2
    exit 1
fi

if [ ! -s "$VIDEO_FILE" ]; then
    echo "Error: Video file is empty: $VIDEO_FILE" >&2
    exit 1
fi

# Check file size (most platforms limit to ~500MB)
FILE_SIZE_MB=$(du -m "$VIDEO_FILE" | cut -f1)
if [ "$FILE_SIZE_MB" -gt 500 ]; then
    echo "Warning: File is ${FILE_SIZE_MB}MB. Some platforms may reject files over 500MB." >&2
fi

echo "Posting clip: $VIDEO_FILE" >&2
echo "Caption: $CAPTION" >&2
echo "Platforms: $PLATFORMS" >&2
echo "Schedule: $SCHEDULE" >&2
echo "API: $POSTIZ_BASE_URL" >&2

# --- Helper: API request ---
postiz_api() {
    local method="$1"
    local endpoint="$2"
    shift 2
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X "$method" \
        "${POSTIZ_BASE_URL}${endpoint}" \
        -H "Authorization: ${POSTIZ_API_KEY}" \
        "$@")
    
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ge 400 ]; then
        echo "Error: Postiz API returned HTTP $http_code" >&2
        echo "$body" >&2
        return 1
    fi
    
    echo "$body"
}

# --- Step 1: Upload video ---
echo "Uploading video to Postiz..." >&2
UPLOAD_RESPONSE=$(postiz_api POST "/upload" \
    -F "file=@${VIDEO_FILE}")

if [ -z "$UPLOAD_RESPONSE" ]; then
    echo "Error: Upload failed — empty response" >&2
    exit 1
fi

MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id // empty' 2>/dev/null)
MEDIA_PATH=$(echo "$UPLOAD_RESPONSE" | jq -r '.path // empty' 2>/dev/null)

if [ -z "$MEDIA_ID" ] || [ -z "$MEDIA_PATH" ]; then
    echo "Error: Upload failed — couldn't parse response" >&2
    echo "Response: $UPLOAD_RESPONSE" >&2
    exit 1
fi

echo "Upload complete: id=$MEDIA_ID" >&2

# --- Step 2: Build post payload for each platform ---
build_platform_post() {
    local platform="$1"
    local integration_id="$2"
    
    if [ -z "$integration_id" ]; then
        echo "Warning: No integration ID for $platform, skipping" >&2
        return 1
    fi
    
    local settings=""
    case "$platform" in
        tiktok)
            settings='{
                "__type": "tiktok",
                "privacy_level": "PUBLIC_TO_EVERYONE",
                "duet": true,
                "stitch": true,
                "comment": true,
                "autoAddMusic": "no",
                "brand_content_toggle": false,
                "brand_organic_toggle": false,
                "content_posting_method": "DIRECT_POST"
            }'
            ;;
        youtube)
            # Extract title from caption (first line or first 100 chars)
            local title
            title=$(echo "$CAPTION" | head -1 | cut -c1-100)
            settings=$(cat << YTEOF
{
    "__type": "youtube",
    "title": $(echo "$title" | jq -Rs .),
    "type": "public",
    "selfDeclaredMadeForKids": "no",
    "tags": []
}
YTEOF
)
            ;;
        x|twitter)
            settings='{"__type": "x"}'
            ;;
        instagram)
            settings='{"__type": "instagram", "post_type": "post"}'
            ;;
        *)
            echo "Warning: Unknown platform '$platform', using defaults" >&2
            settings="{\"__type\": \"$platform\"}"
            ;;
    esac
    
    cat << POSTEOF
{
    "integration": {"id": "$integration_id"},
    "value": [{
        "content": $(echo "$CAPTION" | jq -Rs .),
        "image": [{"id": "$MEDIA_ID", "path": "$MEDIA_PATH"}]
    }],
    "settings": $settings
}
POSTEOF
}

# --- Step 3: Build full post payload ---
POSTS_ARRAY="["
FIRST=true
IFS=',' read -ra PLATFORM_LIST <<< "$PLATFORMS"

for platform in "${PLATFORM_LIST[@]}"; do
    platform=$(echo "$platform" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    
    # Get integration ID for this platform
    integration_id=""
    case "$platform" in
        tiktok)    integration_id="${POSTIZ_TIKTOK_ID:-}" ;;
        youtube)   integration_id="${POSTIZ_YOUTUBE_ID:-}" ;;
        x|twitter) integration_id="${POSTIZ_X_ID:-}" ;;
        instagram) integration_id="${POSTIZ_INSTAGRAM_ID:-}" ;;
    esac
    
    if [ -z "$integration_id" ]; then
        echo "Skipping $platform — no integration ID configured" >&2
        continue
    fi
    
    post_json=$(build_platform_post "$platform" "$integration_id") || continue
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        POSTS_ARRAY+=","
    fi
    POSTS_ARRAY+="$post_json"
    echo "Added $platform to post" >&2
done

POSTS_ARRAY+="]"

if [ "$FIRST" = true ]; then
    echo "Error: No platforms configured. Run setup.sh or set integration IDs." >&2
    exit 1
fi

# Build schedule fields
POST_TYPE="now"
POST_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
if [ "$SCHEDULE" != "now" ]; then
    POST_TYPE="schedule"
    POST_DATE="$SCHEDULE"
fi

PAYLOAD=$(cat << PAYEOF
{
    "type": "$POST_TYPE",
    "date": "$POST_DATE",
    "shortLink": false,
    "tags": [],
    "posts": $POSTS_ARRAY
}
PAYEOF
)

# --- Step 4: Create post ---
echo "Creating post ($POST_TYPE)..." >&2
POST_RESPONSE=$(postiz_api POST "/posts" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

if [ -z "$POST_RESPONSE" ]; then
    echo "Error: Post creation failed — empty response" >&2
    exit 1
fi

POST_ID=$(echo "$POST_RESPONSE" | jq -r '.id // .postId // empty' 2>/dev/null)

echo "Post created successfully!" >&2
if [ -n "$POST_ID" ]; then
    echo "Post ID: $POST_ID" >&2
fi

# Output result JSON
cat << EOF
{
  "success": true,
  "post_id": "${POST_ID:-unknown}",
  "media_id": "$MEDIA_ID",
  "media_path": "$MEDIA_PATH",
  "platforms": "$PLATFORMS",
  "schedule": "$SCHEDULE",
  "post_type": "$POST_TYPE",
  "caption": $(echo "$CAPTION" | jq -Rs .),
  "video_file": "$VIDEO_FILE",
  "posted_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
