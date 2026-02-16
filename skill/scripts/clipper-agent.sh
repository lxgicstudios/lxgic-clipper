#!/bin/bash
# clipper-agent.sh — Main orchestrator for LXGIC Clipper
# Full pipeline: record → detect → clip → format → post
#
# Usage: clipper-agent.sh [command] [options]
#   Commands:
#     run          — Run the full pipeline (default)
#     check        — Check if stream is live, don't clip
#     status       — Show current status and history
#     history      — Show clip history
#     clear-history — Clear clip history
#
# Environment:
#   CLIPPER_STREAM_URL      — Stream URL to monitor (required, or set in config)
#   CLIPPER_DURATION         — Recording duration in minutes (default: 10)
#   CLIPPER_THRESHOLD        — Highlight detection threshold 0-100 (default: 70)
#   CLIPPER_CLIP_LENGTH      — Clip length in seconds (default: 30)
#   CLIPPER_MAX_CLIPS        — Max clips per run (default: 3)
#   CLIPPER_MAX_DAILY        — Max clips per day (default: 15)
#   CLIPPER_PLATFORMS        — Platforms to post to (default: tiktok,youtube,x,instagram)
#   CLIPPER_SCHEDULE         — Post time: "now" or ISO datetime (default: now)
#   CLIPPER_DRY_RUN          — If "true", skip posting (default: false)
#   CLIPPER_CAPTION_PREFIX   — Prefix for all captions
#   CLIPPER_CAPTION_HASHTAGS — Hashtags to append
#   POSTIZ_API_KEY           — Postiz API key (required for posting)

set -euo pipefail

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.lxgic-clipper"
CONFIG_FILE="${CONFIG_DIR}/config.json"
HISTORY_FILE="${CONFIG_DIR}/clip-history.json"
LOG_DIR="${CONFIG_DIR}/logs"
WORK_DIR="${CONFIG_DIR}/work"
CLIPS_DIR="${CONFIG_DIR}/clips"

# Create directories
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$WORK_DIR" "$CLIPS_DIR"

# --- Logging ---
LOG_FILE="${LOG_DIR}/clipper-$(date +%Y%m%d).log"

log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# --- Load config ---
load_config() {
    if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
        CLIPPER_STREAM_URL="${CLIPPER_STREAM_URL:-$(jq -r '.stream_url // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_DURATION="${CLIPPER_DURATION:-$(jq -r '.duration_min // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_THRESHOLD="${CLIPPER_THRESHOLD:-$(jq -r '.threshold // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_CLIP_LENGTH="${CLIPPER_CLIP_LENGTH:-$(jq -r '.clip_length // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_MAX_CLIPS="${CLIPPER_MAX_CLIPS:-$(jq -r '.max_clips_per_run // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_MAX_DAILY="${CLIPPER_MAX_DAILY:-$(jq -r '.max_clips_per_day // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_PLATFORMS="${CLIPPER_PLATFORMS:-$(jq -r '.platforms // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_CAPTION_PREFIX="${CLIPPER_CAPTION_PREFIX:-$(jq -r '.caption_prefix // empty' "$CONFIG_FILE" 2>/dev/null)}"
        CLIPPER_CAPTION_HASHTAGS="${CLIPPER_CAPTION_HASHTAGS:-$(jq -r '.caption_hashtags // empty' "$CONFIG_FILE" 2>/dev/null)}"
        POSTIZ_API_KEY="${POSTIZ_API_KEY:-$(jq -r '.postiz_api_key // empty' "$CONFIG_FILE" 2>/dev/null)}"
        
        # Load integration IDs
        export POSTIZ_TIKTOK_ID="${POSTIZ_TIKTOK_ID:-$(jq -r '.integrations.tiktok // empty' "$CONFIG_FILE" 2>/dev/null)}"
        export POSTIZ_YOUTUBE_ID="${POSTIZ_YOUTUBE_ID:-$(jq -r '.integrations.youtube // empty' "$CONFIG_FILE" 2>/dev/null)}"
        export POSTIZ_X_ID="${POSTIZ_X_ID:-$(jq -r '.integrations.x // empty' "$CONFIG_FILE" 2>/dev/null)}"
        export POSTIZ_INSTAGRAM_ID="${POSTIZ_INSTAGRAM_ID:-$(jq -r '.integrations.instagram // empty' "$CONFIG_FILE" 2>/dev/null)}"
    fi
}

# --- Defaults ---
load_config

CLIPPER_STREAM_URL="${CLIPPER_STREAM_URL:?Error: No stream URL. Set CLIPPER_STREAM_URL or run setup.sh}"
CLIPPER_DURATION="${CLIPPER_DURATION:-10}"
CLIPPER_THRESHOLD="${CLIPPER_THRESHOLD:-70}"
CLIPPER_CLIP_LENGTH="${CLIPPER_CLIP_LENGTH:-30}"
CLIPPER_MAX_CLIPS="${CLIPPER_MAX_CLIPS:-3}"
CLIPPER_MAX_DAILY="${CLIPPER_MAX_DAILY:-15}"
CLIPPER_PLATFORMS="${CLIPPER_PLATFORMS:-tiktok,youtube,x,instagram}"
CLIPPER_SCHEDULE="${CLIPPER_SCHEDULE:-now}"
CLIPPER_DRY_RUN="${CLIPPER_DRY_RUN:-false}"
CLIPPER_CAPTION_PREFIX="${CLIPPER_CAPTION_PREFIX:-}"
CLIPPER_CAPTION_HASHTAGS="${CLIPPER_CAPTION_HASHTAGS:-#clips #viral #highlights}"

export CLIPPER_THRESHOLD POSTIZ_API_KEY

# --- History management ---
init_history() {
    if [ ! -f "$HISTORY_FILE" ]; then
        echo '{"clips": [], "stats": {"total_clips": 0, "total_posts": 0, "runs": 0}}' > "$HISTORY_FILE"
    fi
}

get_daily_clip_count() {
    local today
    today=$(date +%Y-%m-%d)
    jq --arg d "$today" '[.clips[] | select(.date | startswith($d))] | length' "$HISTORY_FILE" 2>/dev/null || echo 0
}

is_duplicate() {
    local timestamp="$1"
    local stream_url="$2"
    local result
    # Check if we already clipped within 10 seconds of this timestamp from this URL
    result=$(jq --arg ts "$timestamp" --arg url "$stream_url" \
        '[.clips[] | select(.stream_url == $url and ((.timestamp | tonumber) - ($ts | tonumber) | fabs) < 10)] | length > 0' \
        "$HISTORY_FILE" 2>/dev/null) || result="false"
    echo "${result:-false}"
}

add_to_history() {
    local clip_file="$1"
    local timestamp="$2"
    local score="$3"
    local post_id="${4:-}"
    local platforms="${5:-}"
    
    local tmp
    tmp=$(mktemp)
    jq --arg file "$clip_file" \
       --arg ts "$timestamp" \
       --arg score "$score" \
       --arg pid "$post_id" \
       --arg plat "$platforms" \
       --arg url "$CLIPPER_STREAM_URL" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.clips += [{
           "file": $file,
           "timestamp": ($ts | tonumber),
           "score": ($score | tonumber),
           "post_id": $pid,
           "platforms": $plat,
           "stream_url": $url,
           "date": $date
       }] | .stats.total_clips += 1 | .stats.runs = (.stats.runs // 0)' \
       "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
}

increment_runs() {
    local tmp
    tmp=$(mktemp)
    jq '.stats.runs += 1' "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
}

# --- Commands ---
cmd_status() {
    init_history
    echo "=== LXGIC Clipper Status ==="
    echo "Stream URL: $CLIPPER_STREAM_URL"
    echo "Config: $CONFIG_FILE"
    echo ""
    
    local total_clips daily_clips total_runs
    total_clips=$(jq '.stats.total_clips' "$HISTORY_FILE" 2>/dev/null || echo 0)
    daily_clips=$(get_daily_clip_count)
    total_runs=$(jq '.stats.runs' "$HISTORY_FILE" 2>/dev/null || echo 0)
    
    echo "Total clips: $total_clips"
    echo "Today's clips: $daily_clips / $CLIPPER_MAX_DAILY"
    echo "Total runs: $total_runs"
    echo "Platforms: $CLIPPER_PLATFORMS"
    echo "Dry run: $CLIPPER_DRY_RUN"
    echo ""
    
    # Check if stream is live
    echo "Checking stream status..."
    if yt-dlp --simulate --no-playlist "$CLIPPER_STREAM_URL" 2>/dev/null; then
        echo "Stream: AVAILABLE"
    else
        echo "Stream: OFFLINE or unreachable"
    fi
}

cmd_history() {
    init_history
    if command -v jq &>/dev/null; then
        echo "=== Clip History (last 20) ==="
        jq -r '.clips | sort_by(.date) | reverse | .[0:20][] | 
            "\(.date) | score=\(.score) | \(.platforms) | \(.file)"' \
            "$HISTORY_FILE" 2>/dev/null || echo "No clips yet."
    else
        cat "$HISTORY_FILE"
    fi
}

cmd_check() {
    echo "Checking stream: $CLIPPER_STREAM_URL" >&2
    if yt-dlp --simulate --no-playlist "$CLIPPER_STREAM_URL" 2>/dev/null; then
        echo '{"live": true, "url": "'"$CLIPPER_STREAM_URL"'"}'
    else
        echo '{"live": false, "url": "'"$CLIPPER_STREAM_URL"'"}'
    fi
}

cmd_clear_history() {
    echo '{"clips": [], "stats": {"total_clips": 0, "total_posts": 0, "runs": 0}}' > "$HISTORY_FILE"
    echo "History cleared."
}

# --- Main pipeline ---
cmd_run() {
    init_history
    increment_runs
    
    log_info "=== LXGIC Clipper Pipeline Start ==="
    log_info "Stream: $CLIPPER_STREAM_URL"
    log_info "Duration: ${CLIPPER_DURATION}min, Threshold: $CLIPPER_THRESHOLD, Max clips: $CLIPPER_MAX_CLIPS"
    
    # Check daily limit
    local daily_count
    daily_count=$(get_daily_clip_count)
    if [ "$daily_count" -ge "$CLIPPER_MAX_DAILY" ]; then
        log_warn "Daily clip limit reached ($daily_count/$CLIPPER_MAX_DAILY). Skipping."
        echo '{"status": "skipped", "reason": "daily_limit", "count": '"$daily_count"'}'
        return 0
    fi
    
    local remaining=$((CLIPPER_MAX_DAILY - daily_count))
    local max_this_run=$CLIPPER_MAX_CLIPS
    if [ "$remaining" -lt "$max_this_run" ]; then
        max_this_run=$remaining
    fi
    
    # --- Phase 1: Record ---
    log_info "Phase 1: Recording stream..."
    local run_dir="$WORK_DIR/run_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$run_dir"
    
    local record_result
    if ! record_result=$("$SCRIPT_DIR/record-stream.sh" "$CLIPPER_STREAM_URL" "$CLIPPER_DURATION" "$run_dir" 2>>"$LOG_FILE"); then
        log_error "Recording failed. Stream may be offline."
        echo '{"status": "error", "phase": "record", "reason": "stream_offline_or_failed"}'
        rm -rf "$run_dir"
        return 1
    fi
    
    local video_file
    video_file=$(echo "$record_result" | jq -r '.file' 2>/dev/null)
    
    if [ -z "$video_file" ] || [ ! -f "$video_file" ]; then
        log_error "Recording produced no output file"
        echo '{"status": "error", "phase": "record", "reason": "no_output"}'
        rm -rf "$run_dir"
        return 1
    fi
    
    log_info "Recorded: $video_file ($(du -h "$video_file" | cut -f1))"
    
    # --- Phase 2: Detect highlights ---
    log_info "Phase 2: Detecting highlights..."
    local detect_result
    if ! detect_result=$("$SCRIPT_DIR/detect-highlights.sh" "$video_file" "$CLIPPER_THRESHOLD" 2>>"$LOG_FILE"); then
        log_error "Highlight detection failed"
        echo '{"status": "error", "phase": "detect", "reason": "detection_failed"}'
        rm -rf "$run_dir"
        return 1
    fi
    
    local num_highlights
    num_highlights=$(echo "$detect_result" | jq '.total_highlights' 2>/dev/null || echo 0)
    log_info "Found $num_highlights highlights above threshold $CLIPPER_THRESHOLD"
    
    if [ "$num_highlights" -eq 0 ]; then
        log_info "No highlights found. Stream segment was quiet."
        echo '{"status": "no_highlights", "video": "'"$video_file"'", "threshold": '"$CLIPPER_THRESHOLD"'}'
        # Clean up work directory but keep for debugging
        return 0
    fi
    
    # --- Phase 3: Clip and format top highlights ---
    log_info "Phase 3: Clipping top $max_this_run highlights..."
    
    # Get top highlights sorted by score, limited to max
    # Write to temp file to avoid subshell variable scope issues with pipe
    local highlights_file
    highlights_file=$(mktemp)
    echo "$detect_result" | jq -c \
        --argjson max "$max_this_run" \
        '.highlights | sort_by(-.score) | .[0:$max] | .[] | {timestamp, score}' \
        > "$highlights_file"
    
    local clips_created=0
    local clips_posted=0
    
    while IFS= read -r highlight; do
        [ -z "$highlight" ] && continue
        
        local ts score
        ts=$(echo "$highlight" | jq -r '.timestamp' 2>/dev/null) || continue
        score=$(echo "$highlight" | jq -r '.score' 2>/dev/null) || continue
        
        # Skip if we couldn't parse
        [ -z "$ts" ] || [ -z "$score" ] && continue
        
        # Calculate clip start (center the highlight in the clip)
        local half_clip=$((CLIPPER_CLIP_LENGTH / 2))
        local clip_start
        clip_start=$(python3 -c "print(max(0, $ts - $half_clip))")
        
        # Check for duplicates
        local is_dup
        is_dup=$(is_duplicate "$ts" "$CLIPPER_STREAM_URL")
        if [ "$is_dup" = "true" ]; then
            log_info "Skipping duplicate highlight at ${ts}s"
            continue
        fi
        
        log_info "Clipping highlight: ${ts}s (score=$score, start=${clip_start}s, length=${CLIPPER_CLIP_LENGTH}s)"
        
        # Clip and format
        local clip_result
        if ! clip_result=$("$SCRIPT_DIR/clip-and-format.sh" "$video_file" "$clip_start" "$CLIPPER_CLIP_LENGTH" "$CLIPS_DIR" 2>>"$LOG_FILE"); then
            log_error "Clipping failed for timestamp $ts"
            continue
        fi
        
        # Get the best available clip file
        local vertical_caps vertical_file horizontal_file post_file
        vertical_caps=$(echo "$clip_result" | jq -r '.clips.vertical_captioned // empty' 2>/dev/null)
        vertical_file=$(echo "$clip_result" | jq -r '.clips.vertical // empty' 2>/dev/null)
        horizontal_file=$(echo "$clip_result" | jq -r '.clips.horizontal // empty' 2>/dev/null)
        
        # Prefer: captioned vertical > vertical > horizontal
        post_file=""
        for candidate in "$vertical_caps" "$vertical_file" "$horizontal_file"; do
            if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -s "$candidate" ]; then
                post_file="$candidate"
                break
            fi
        done
        
        if [ -z "$post_file" ]; then
            log_error "No usable clip file produced for ${ts}s"
            continue
        fi
        
        clips_created=$((clips_created + 1))
        
        # Build caption
        local caption="${CLIPPER_CAPTION_PREFIX}"
        if [ -n "$caption" ]; then
            caption="${caption} "
        fi
        caption="${caption}${CLIPPER_CAPTION_HASHTAGS}"
        
        # --- Phase 4: Post ---
        local post_id=""
        if [ "$CLIPPER_DRY_RUN" = "true" ]; then
            log_info "DRY RUN: Would post $post_file to $CLIPPER_PLATFORMS"
            post_id="dry-run"
        else
            if [ -n "${POSTIZ_API_KEY:-}" ]; then
                log_info "Phase 4: Posting clip to $CLIPPER_PLATFORMS..."
                local post_result
                if post_result=$("$SCRIPT_DIR/post-clip.sh" "$post_file" "$caption" "$CLIPPER_PLATFORMS" "$CLIPPER_SCHEDULE" 2>>"$LOG_FILE"); then
                    post_id=$(echo "$post_result" | jq -r '.post_id' 2>/dev/null || echo "")
                    clips_posted=$((clips_posted + 1))
                    log_info "Posted! Post ID: $post_id"
                else
                    log_error "Posting failed for clip at ${ts}s"
                fi
            else
                log_warn "POSTIZ_API_KEY not set. Clip saved but not posted."
                post_id="not-posted"
            fi
        fi
        
        # Record in history
        add_to_history "$post_file" "$ts" "$score" "$post_id" "$CLIPPER_PLATFORMS"
        
        log_info "Clip $clips_created complete: ${ts}s (score=$score)"
    done < "$highlights_file"
    
    rm -f "$highlights_file"
    
    log_info "=== Pipeline Complete ==="
    log_info "Highlights found: $num_highlights, Clips created: $clips_created, Posted: $clips_posted"
    
    # Final output
    cat << EOF
{
  "status": "complete",
  "stream_url": "$CLIPPER_STREAM_URL",
  "recording": "$video_file",
  "highlights_found": $num_highlights,
  "clips_created": $clips_created,
  "clips_posted": $clips_posted,
  "daily_total": $(get_daily_clip_count),
  "daily_limit": $CLIPPER_MAX_DAILY,
  "dry_run": $CLIPPER_DRY_RUN,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# --- Entry point ---
COMMAND="${1:-run}"

case "$COMMAND" in
    run)          cmd_run ;;
    check)        cmd_check ;;
    status)       cmd_status ;;
    history)      cmd_history ;;
    clear-history) cmd_clear_history ;;
    help|--help|-h)
        echo "Usage: clipper-agent.sh [run|check|status|history|clear-history]"
        echo ""
        echo "Commands:"
        echo "  run           Run the full pipeline (record → detect → clip → post)"
        echo "  check         Check if stream is live"
        echo "  status        Show status and stats"
        echo "  history       Show clip history"
        echo "  clear-history Clear all clip history"
        echo ""
        echo "See script header for environment variables."
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        echo "Run 'clipper-agent.sh help' for usage" >&2
        exit 1
        ;;
esac
