#!/bin/bash
# clip-and-format.sh — Extract a clip from video and format for social platforms
# Outputs: vertical (9:16) clip with optional captions
#
# Usage: clip-and-format.sh <video> <start-seconds> <duration> <output-dir>
# Environment:
#   CLIPPER_QUALITY — CRF value for encoding (default: 20, lower = better quality)

set -euo pipefail

INPUT_FILE="${1:?Usage: clip-and-format.sh <video> <start-seconds> <duration> <output-dir>}"
START="${2:?Start time in seconds required}"
DURATION="${3:-30}"  # default 30 seconds
OUTPUT_DIR="${4:-.}"
QUALITY="${CLIPPER_QUALITY:-20}"  # CRF value

mkdir -p "$OUTPUT_DIR"

BASENAME=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
TIMESTAMP=$(echo "$START" | sed 's/\./_/')

echo "Clipping: ${START}s for ${DURATION}s from $INPUT_FILE" >&2

# Step 1: Extract clip (original aspect)
CLIP_ORIG="$OUTPUT_DIR/${BASENAME}_clip_${TIMESTAMP}_orig.mp4"
ffmpeg -ss "$START" -i "$INPUT_FILE" -t "$DURATION" \
    -c:v libx264 -crf "$QUALITY" -preset fast \
    -c:a aac -b:a 128k \
    -y "$CLIP_ORIG" 2>/dev/null

# Step 2: Create vertical (9:16) version for TikTok/Reels/Shorts
# Center crop from 16:9 to 9:16
CLIP_VERT="$OUTPUT_DIR/${BASENAME}_clip_${TIMESTAMP}_vertical.mp4"
ffmpeg -i "$CLIP_ORIG" \
    -vf "crop=ih*9/16:ih,scale=1080:1920" \
    -c:v libx264 -crf "$QUALITY" -preset fast \
    -c:a aac -b:a 128k \
    -y "$CLIP_VERT" 2>/dev/null

# Step 3: Create horizontal (16:9) version for X/Twitter
CLIP_HORIZ="$OUTPUT_DIR/${BASENAME}_clip_${TIMESTAMP}_horizontal.mp4"
ffmpeg -i "$CLIP_ORIG" \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" \
    -c:v libx264 -crf "$QUALITY" -preset fast \
    -c:a aac -b:a 128k \
    -y "$CLIP_HORIZ" 2>/dev/null

# Step 4: Generate captions via whisper (if available)
CAPTIONS=""
if command -v whisper &>/dev/null; then
    echo "Generating captions..." >&2
    ffmpeg -i "$CLIP_ORIG" -ar 16000 -ac 1 -f wav "$OUTPUT_DIR/temp_audio.wav" -y 2>/dev/null
    whisper "$OUTPUT_DIR/temp_audio.wav" --model tiny --output_format srt --output_dir "$OUTPUT_DIR" >/dev/null 2>&1
    CAPTIONS="$OUTPUT_DIR/temp_audio.srt"
    
    # Burn captions into vertical video
    if [ -f "$CAPTIONS" ] && [ -s "$CAPTIONS" ]; then
        CLIP_VERT_CAPS="$OUTPUT_DIR/${BASENAME}_clip_${TIMESTAMP}_vertical_caps.mp4"
        
        # Check if ffmpeg has subtitle filter (needs libass)
        HAS_SUBTITLES=$(ffmpeg -filters 2>&1 | grep -c "subtitles" || true)
        
        BURN_OK=false
        if [ "$HAS_SUBTITLES" -gt 0 ]; then
            # Use subtitle filter (best quality)
            cp "$CAPTIONS" "$OUTPUT_DIR/_subs.srt"
            pushd "$OUTPUT_DIR" > /dev/null
            if ffmpeg -i "$(basename "$CLIP_VERT")" \
                -vf "subtitles=_subs.srt:force_style='FontSize=24,FontName=Arial,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,Outline=2,Alignment=2,MarginV=40'" \
                -c:v libx264 -crf "$QUALITY" -preset fast \
                -c:a copy \
                -y "$(basename "$CLIP_VERT_CAPS")" 2>/dev/null; then
                BURN_OK=true
            fi
            rm -f "$OUTPUT_DIR/_subs.srt"
            popd > /dev/null
        fi
        
        if [ "$BURN_OK" = false ]; then
            # Fallback: use drawtext filter to burn first caption line
            CAPTION_TEXT=$(sed -n '3p' "$CAPTIONS" | head -c 80)
            if [ -n "$CAPTION_TEXT" ] && ffmpeg -filters 2>&1 | grep -q "drawtext"; then
                ESCAPED_TEXT=$(echo "$CAPTION_TEXT" | sed "s/'/\\\\'/g" | sed 's/:/\\:/g')
                if ffmpeg -i "$CLIP_VERT" \
                    -vf "drawtext=text='${ESCAPED_TEXT}':fontsize=28:fontcolor=white:borderw=2:bordercolor=black:x=(w-text_w)/2:y=h-th-60" \
                    -c:v libx264 -crf "$QUALITY" -preset fast \
                    -c:a copy \
                    -y "$CLIP_VERT_CAPS" 2>/dev/null; then
                    BURN_OK=true
                fi
            fi
        fi
        
        if [ "$BURN_OK" = true ]; then
            echo "Captioned: $CLIP_VERT_CAPS" >&2
        else
            echo "Info: Caption burn-in not available. SRT file saved alongside clip." >&2
            CLIP_VERT_CAPS=""
        fi
    fi
    rm -f "$OUTPUT_DIR/temp_audio.wav"
fi

# Output manifest
cat << EOF
{
  "source": "$INPUT_FILE",
  "start": $START,
  "duration": $DURATION,
  "clips": {
    "original": "$CLIP_ORIG",
    "vertical": "$CLIP_VERT",
    "vertical_captioned": "${CLIP_VERT_CAPS:-}",
    "horizontal": "$CLIP_HORIZ"
  },
  "captions": "${CAPTIONS:-}",
  "quality_crf": $QUALITY
}
EOF

echo "Done. Clips saved to $OUTPUT_DIR" >&2
