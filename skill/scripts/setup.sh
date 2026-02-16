#!/bin/bash
# setup.sh — Interactive setup wizard for LXGIC Clipper
# Creates config at ~/.lxgic-clipper/config.json
# Validates all dependencies and API keys

set -euo pipefail

CONFIG_DIR="${HOME}/.lxgic-clipper"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🎬 LXGIC Clipper — Setup Wizard${NC}         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Automated livestream clipping agent     ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
info() { echo -e "  ${BLUE}ℹ${NC} $*"; }
ask()  { echo -en "  ${BOLD}$*${NC} "; }

# Read input with default
read_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    if [ -n "$default" ]; then
        ask "$prompt [$default]: "
    else
        ask "$prompt: "
    fi
    
    local input
    read -r input
    eval "$varname=\"${input:-$default}\""
}

# --- Step 1: Check dependencies ---
check_dependencies() {
    echo -e "${BOLD}Step 1: Checking dependencies${NC}"
    echo ""
    
    local all_good=true
    
    # ffmpeg
    if command -v ffmpeg &>/dev/null; then
        local ffmpeg_ver
        ffmpeg_ver=$(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')
        ok "ffmpeg $ffmpeg_ver"
    else
        fail "ffmpeg not found"
        info "Install: brew install ffmpeg"
        all_good=false
    fi
    
    # yt-dlp
    if command -v yt-dlp &>/dev/null; then
        local ytdlp_ver
        ytdlp_ver=$(yt-dlp --version 2>/dev/null)
        ok "yt-dlp $ytdlp_ver"
    else
        fail "yt-dlp not found"
        info "Install: brew install yt-dlp"
        all_good=false
    fi
    
    # ffprobe
    if command -v ffprobe &>/dev/null; then
        ok "ffprobe (bundled with ffmpeg)"
    else
        fail "ffprobe not found"
        all_good=false
    fi
    
    # python3
    if command -v python3 &>/dev/null; then
        local py_ver
        py_ver=$(python3 --version 2>&1 | awk '{print $2}')
        ok "Python $py_ver"
    else
        fail "python3 not found"
        info "Install: brew install python3"
        all_good=false
    fi
    
    # jq
    if command -v jq &>/dev/null; then
        ok "jq $(jq --version 2>/dev/null)"
    else
        fail "jq not found"
        info "Install: brew install jq"
        all_good=false
    fi
    
    # curl
    if command -v curl &>/dev/null; then
        ok "curl"
    else
        fail "curl not found"
        all_good=false
    fi
    
    # whisper (optional)
    if command -v whisper &>/dev/null; then
        ok "whisper (enhanced clip detection with transcription)"
    elif python3 -c "import whisper" 2>/dev/null; then
        ok "whisper (Python module — enhanced clip detection)"
    else
        warn "whisper not installed (optional — audio-only detection will be used)"
        info "For better results: pip3 install openai-whisper"
    fi
    
    echo ""
    
    if [ "$all_good" = false ]; then
        fail "Missing required dependencies. Install them and re-run setup."
        exit 1
    fi
    
    ok "All required dependencies found!"
    echo ""
}

# --- Step 2: Stream URL ---
configure_stream() {
    echo -e "${BOLD}Step 2: Stream Configuration${NC}"
    echo ""
    info "Enter the livestream URL to monitor."
    info "Supported: YouTube, Twitch, Kick, or any yt-dlp compatible URL"
    echo ""
    
    local existing_url=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_url=$(jq -r '.stream_url // empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    read_with_default "Stream URL" "$existing_url" STREAM_URL
    
    if [ -z "$STREAM_URL" ]; then
        fail "Stream URL is required"
        exit 1
    fi
    
    # Test the URL
    echo ""
    info "Testing URL..."
    if yt-dlp --simulate --no-playlist "$STREAM_URL" 2>/dev/null; then
        ok "URL is valid and accessible"
    else
        warn "URL not reachable right now (stream may be offline)"
        info "This is OK if the stream is not currently live"
        ask "Continue anyway? [Y/n]: "
        local cont
        read -r cont
        if [[ "${cont,,}" == "n" ]]; then
            exit 0
        fi
    fi
    
    echo ""
    read_with_default "Recording duration per segment (minutes)" "10" DURATION
    read_with_default "Clip length (seconds)" "30" CLIP_LENGTH
    read_with_default "Detection threshold (0-100, higher = fewer but better clips)" "70" THRESHOLD
    read_with_default "Max clips per run" "3" MAX_CLIPS
    read_with_default "Max clips per day" "15" MAX_DAILY
    
    echo ""
}

# --- Step 3: Postiz API ---
configure_postiz() {
    echo -e "${BOLD}Step 3: Postiz API (social media posting)${NC}"
    echo ""
    info "Postiz handles posting clips to TikTok, YouTube, X, Instagram, etc."
    info "Get an API key from your Postiz dashboard (postiz.com or self-hosted)"
    echo ""
    
    local existing_key=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_key=$(jq -r '.postiz_api_key // empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    local display_key=""
    if [ -n "$existing_key" ]; then
        display_key="${existing_key:0:8}...${existing_key: -4}"
    fi
    
    read_with_default "Postiz API Key" "$display_key" POSTIZ_KEY
    
    # If they entered the masked version, keep the old key
    if [ "$POSTIZ_KEY" = "$display_key" ] && [ -n "$existing_key" ]; then
        POSTIZ_KEY="$existing_key"
    fi
    
    local existing_base=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_base=$(jq -r '.postiz_base_url // empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    read_with_default "Postiz API Base URL" "${existing_base:-https://api.postiz.com/public/v1}" POSTIZ_BASE
    
    if [ -n "$POSTIZ_KEY" ]; then
        echo ""
        info "Testing Postiz API connection..."
        
        local response
        response=$(curl -s -w "\n%{http_code}" \
            -X GET "${POSTIZ_BASE}/integrations" \
            -H "Authorization: ${POSTIZ_KEY}" 2>/dev/null || true)
        
        local http_code
        http_code=$(echo "$response" | tail -1)
        local body
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" = "200" ]; then
            ok "Postiz API connected!"
            
            # Show available integrations
            echo ""
            info "Connected platforms:"
            echo "$body" | jq -r '.[] | "    \(.name // .provider) (\(.id))"' 2>/dev/null || true
            
            # Auto-detect integration IDs
            TIKTOK_ID=$(echo "$body" | jq -r '[.[] | select(.provider == "tiktok" or .name == "TikTok")] | first | .id // empty' 2>/dev/null || echo "")
            YOUTUBE_ID=$(echo "$body" | jq -r '[.[] | select(.provider == "youtube" or .name == "YouTube")] | first | .id // empty' 2>/dev/null || echo "")
            X_ID=$(echo "$body" | jq -r '[.[] | select(.provider == "x" or .provider == "twitter" or .name == "X")] | first | .id // empty' 2>/dev/null || echo "")
            INSTAGRAM_ID=$(echo "$body" | jq -r '[.[] | select(.provider == "instagram" or .name == "Instagram")] | first | .id // empty' 2>/dev/null || echo "")
            
            echo ""
            if [ -n "$TIKTOK_ID" ]; then ok "TikTok: $TIKTOK_ID"; fi
            if [ -n "$YOUTUBE_ID" ]; then ok "YouTube: $YOUTUBE_ID"; fi
            if [ -n "$X_ID" ]; then ok "X/Twitter: $X_ID"; fi
            if [ -n "$INSTAGRAM_ID" ]; then ok "Instagram: $INSTAGRAM_ID"; fi
            
        elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
            fail "API key is invalid (HTTP $http_code)"
            warn "Check your key and try again"
        else
            warn "Could not verify API key (HTTP $http_code)"
            info "This might be a network issue. Config will be saved anyway."
        fi
    else
        warn "No Postiz API key provided. Clips will be saved locally but NOT posted."
        TIKTOK_ID=""
        YOUTUBE_ID=""
        X_ID=""
        INSTAGRAM_ID=""
    fi
    
    echo ""
}

# --- Step 4: Platform selection ---
configure_platforms() {
    echo -e "${BOLD}Step 4: Platform Selection${NC}"
    echo ""
    info "Which platforms should clips be posted to?"
    info "Enter comma-separated list (e.g., tiktok,youtube,x,instagram)"
    echo ""
    
    local existing_platforms=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_platforms=$(jq -r '.platforms // empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    # Build default from available integrations
    local available=""
    if [ -n "${TIKTOK_ID:-}" ]; then available+="tiktok,"; fi
    if [ -n "${YOUTUBE_ID:-}" ]; then available+="youtube,"; fi
    if [ -n "${X_ID:-}" ]; then available+="x,"; fi
    if [ -n "${INSTAGRAM_ID:-}" ]; then available+="instagram,"; fi
    available="${available%,}"
    
    local default="${existing_platforms:-${available:-tiktok,youtube,x,instagram}}"
    read_with_default "Platforms" "$default" PLATFORMS
    
    echo ""
    read_with_default "Caption prefix (e.g., streamer name)" "" CAPTION_PREFIX
    read_with_default "Hashtags" "#clips #viral #highlights" CAPTION_HASHTAGS
    
    echo ""
}

# --- Step 5: Save config ---
save_config() {
    echo -e "${BOLD}Step 5: Saving configuration${NC}"
    echo ""
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" << EOF
{
  "stream_url": $(echo "$STREAM_URL" | jq -Rs .),
  "duration_min": $DURATION,
  "clip_length": $CLIP_LENGTH,
  "threshold": $THRESHOLD,
  "max_clips_per_run": $MAX_CLIPS,
  "max_clips_per_day": $MAX_DAILY,
  "platforms": $(echo "$PLATFORMS" | jq -Rs . | sed 's/\\n//g'),
  "caption_prefix": $(echo "$CAPTION_PREFIX" | jq -Rs . | sed 's/\\n//g'),
  "caption_hashtags": $(echo "$CAPTION_HASHTAGS" | jq -Rs . | sed 's/\\n//g'),
  "postiz_api_key": $(echo "${POSTIZ_KEY:-}" | jq -Rs . | sed 's/\\n//g'),
  "postiz_base_url": $(echo "${POSTIZ_BASE:-https://api.postiz.com/public/v1}" | jq -Rs . | sed 's/\\n//g'),
  "integrations": {
    "tiktok": $(echo "${TIKTOK_ID:-}" | jq -Rs . | sed 's/\\n//g'),
    "youtube": $(echo "${YOUTUBE_ID:-}" | jq -Rs . | sed 's/\\n//g'),
    "x": $(echo "${X_ID:-}" | jq -Rs . | sed 's/\\n//g'),
    "instagram": $(echo "${INSTAGRAM_ID:-}" | jq -Rs . | sed 's/\\n//g')
  },
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "version": "1.0.0"
}
EOF
    
    # Validate JSON
    if jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        ok "Config saved to $CONFIG_FILE"
    else
        fail "Config file has invalid JSON!"
        cat "$CONFIG_FILE"
        exit 1
    fi
    
    # Initialize history file
    if [ ! -f "${CONFIG_DIR}/clip-history.json" ]; then
        echo '{"clips": [], "stats": {"total_clips": 0, "total_posts": 0, "runs": 0}}' > "${CONFIG_DIR}/clip-history.json"
        ok "Clip history initialized"
    fi
    
    # Create directories
    mkdir -p "${CONFIG_DIR}/logs" "${CONFIG_DIR}/work" "${CONFIG_DIR}/clips"
    ok "Working directories created"
    
    echo ""
}

# --- Step 6: Test recording ---
test_recording() {
    echo -e "${BOLD}Step 6: Test Recording (optional)${NC}"
    echo ""
    
    ask "Test recording a 30-second clip? [y/N]: "
    local test
    read -r test
    
    if [[ "${test,,}" != "y" ]]; then
        info "Skipping test. You can test later with: clipper-agent.sh check"
        return 0
    fi
    
    echo ""
    info "Recording 30 seconds from $STREAM_URL..."
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local test_dir="${CONFIG_DIR}/test"
    mkdir -p "$test_dir"
    
    if "$script_dir/record-stream.sh" "$STREAM_URL" 1 "$test_dir" 2>&1 | tail -5; then
        echo ""
        ok "Test recording successful!"
        
        # Quick highlight detection test
        local test_video
        test_video=$(ls -t "$test_dir"/*.mp4 2>/dev/null | head -1)
        
        if [ -n "$test_video" ] && [ -f "$test_video" ]; then
            info "Running highlight detection on test clip..."
            if "$script_dir/detect-highlights.sh" "$test_video" 50 2>&1 | tail -5; then
                ok "Detection pipeline works!"
            else
                warn "Detection had issues, but recording works fine"
            fi
        fi
    else
        fail "Test recording failed"
        info "Check that the stream URL is correct and accessible"
    fi
    
    echo ""
    ask "Clean up test files? [Y/n]: "
    local cleanup
    read -r cleanup
    if [[ "${cleanup,,}" != "n" ]]; then
        rm -rf "$test_dir"
        ok "Test files cleaned up"
    fi
    
    echo ""
}

# --- Summary ---
print_summary() {
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}Setup Complete!${NC}                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Config:${NC}    $CONFIG_FILE"
    echo -e "  ${BOLD}Stream:${NC}    $STREAM_URL"
    echo -e "  ${BOLD}Platforms:${NC} $PLATFORMS"
    echo -e "  ${BOLD}Clips:${NC}     ${CLIP_LENGTH}s, max ${MAX_DAILY}/day"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    1. Run manually:  ${CYAN}clipper-agent.sh run${NC}"
    echo -e "    2. Check status:  ${CYAN}clipper-agent.sh status${NC}"
    echo -e "    3. Set up cron:   Use cron-template.json for OpenClaw scheduling"
    echo ""
    echo -e "  ${BOLD}Files:${NC}"
    echo -e "    Config:     $CONFIG_FILE"
    echo -e "    History:    ${CONFIG_DIR}/clip-history.json"
    echo -e "    Logs:       ${CONFIG_DIR}/logs/"
    echo -e "    Clips:      ${CONFIG_DIR}/clips/"
    echo ""
    echo -e "  Built by ${BOLD}LXGIC Studios${NC}"
    echo -e "  ${BLUE}github.com/lxgicstudios${NC}"
    echo ""
}

# --- Main ---
print_header
check_dependencies
configure_stream
configure_postiz
configure_platforms
save_config
test_recording
print_summary
