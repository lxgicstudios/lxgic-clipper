#!/bin/bash
# detect-highlights.sh — Analyze a video segment for highlight moments
# Uses ffmpeg audio analysis + whisper transcription
# Output: JSON array of timestamps with scores
#
# Usage: detect-highlights.sh <video-file> [threshold]
# Environment:
#   CLIPPER_THRESHOLD — minimum score (0-100) to count as highlight (default: 70)

set -euo pipefail

INPUT_FILE="${1:?Usage: detect-highlights.sh <video-file> [threshold]}"
THRESHOLD="${2:-${CLIPPER_THRESHOLD:-70}}"
TEMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# Validate input
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File not found: $INPUT_FILE" >&2
    exit 1
fi

echo "Analyzing: $INPUT_FILE (threshold=$THRESHOLD)" >&2

# Get video duration for context
DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)
echo "Video duration: ${DURATION:-unknown}s" >&2

# Step 1: Extract audio and detect volume peaks
echo "Detecting audio peaks..." >&2
ffmpeg -i "$INPUT_FILE" -af "volumedetect" -vn -f null /dev/null 2>"$TEMP_DIR/volume.txt"

# Extract mean and max volume
MEAN_VOL=$(grep "mean_volume:" "$TEMP_DIR/volume.txt" | awk '{print $5}' || echo "-30")
MAX_VOL=$(grep "max_volume:" "$TEMP_DIR/volume.txt" | awk '{print $5}' || echo "0")
echo "Volume — mean: ${MEAN_VOL}dB, max: ${MAX_VOL}dB" >&2

# Step 2: Get per-second RMS levels via astats
# reset=44100 gives ~1 second windows at 44.1kHz sample rate
echo "Computing per-second RMS levels..." >&2
ffmpeg -i "$INPUT_FILE" \
    -af "astats=metadata=1:reset=44100,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=$TEMP_DIR/rms.txt" \
    -vn -f null /dev/null 2>/dev/null || true

# Step 3: Detect scene changes (visual cuts often correlate with highlights)
echo "Detecting scene changes..." >&2
ffmpeg -i "$INPUT_FILE" \
    -vf "select='gt(scene,0.35)',showinfo" \
    -vsync vfr -f null /dev/null 2>"$TEMP_DIR/scenes.txt" || true

# Step 4: Transcribe with whisper (if available)
TRANSCRIPT_FILE=""
WHISPER_CMD=""

# Check for various whisper implementations
if command -v whisper &>/dev/null; then
    WHISPER_CMD="whisper"
elif command -v whisper-cpp &>/dev/null; then
    WHISPER_CMD="whisper-cpp"
elif python3 -c "import whisper" 2>/dev/null; then
    WHISPER_CMD="python-whisper"
fi

if [ -n "$WHISPER_CMD" ]; then
    echo "Transcribing audio (using $WHISPER_CMD)..." >&2
    ffmpeg -i "$INPUT_FILE" -ar 16000 -ac 1 -f wav "$TEMP_DIR/audio.wav" -y 2>/dev/null

    case "$WHISPER_CMD" in
        whisper)
            whisper "$TEMP_DIR/audio.wav" --model tiny --output_format json --output_dir "$TEMP_DIR" >/dev/null 2>&1 && \
                TRANSCRIPT_FILE="$TEMP_DIR/audio.json"
            ;;
        whisper-cpp)
            whisper-cpp -m tiny -f "$TEMP_DIR/audio.wav" --output-json -of "$TEMP_DIR/audio" >/dev/null 2>&1 && \
                TRANSCRIPT_FILE="$TEMP_DIR/audio.json"
            ;;
        python-whisper)
            python3 -c "
import whisper, json
model = whisper.load_model('tiny')
result = model.transcribe('$TEMP_DIR/audio.wav')
with open('$TEMP_DIR/audio.json', 'w') as f:
    json.dump(result, f)
" >/dev/null 2>&1 && TRANSCRIPT_FILE="$TEMP_DIR/audio.json"
            ;;
    esac
    
    if [ -n "$TRANSCRIPT_FILE" ] && [ -f "$TRANSCRIPT_FILE" ]; then
        echo "Transcription complete." >&2
    else
        echo "Transcription failed, continuing with audio-only analysis." >&2
        TRANSCRIPT_FILE=""
    fi
else
    echo "No whisper found. Using audio-only detection (install whisper for better results)." >&2
fi

# Step 5: Parse all signals and score highlights
export TEMP_DIR TRANSCRIPT_FILE THRESHOLD DURATION
python3 << 'PYEOF'
import sys, json, os, re

temp_dir = os.environ["TEMP_DIR"]
transcript_file = os.environ.get("TRANSCRIPT_FILE", "")
threshold = int(os.environ.get("THRESHOLD", "70"))
video_duration = float(os.environ.get("DURATION", "0") or "0")

# --- Signal 1: Parse RMS levels ---
rms_data = []
rms_file = os.path.join(temp_dir, "rms.txt")
try:
    current_time = 0.0
    with open(rms_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Format: frame:N pts:N pts_time:N.N
            if "pts_time:" in line:
                match = re.search(r'pts_time:([\d.]+)', line)
                if match:
                    current_time = float(match.group(1))
            elif "lavfi.astats.Overall.RMS_level" in line:
                parts = line.split("=")
                if len(parts) >= 2:
                    try:
                        rms = float(parts[-1])
                        rms_data.append({"time": current_time, "rms": rms})
                    except ValueError:
                        pass
except FileNotFoundError:
    pass

# --- Signal 2: Parse scene changes ---
scene_times = []
scenes_file = os.path.join(temp_dir, "scenes.txt")
try:
    with open(scenes_file) as f:
        for line in f:
            if "pts_time:" in line:
                match = re.search(r'pts_time:([\d.]+)', line)
                if match:
                    scene_times.append(float(match.group(1)))
except FileNotFoundError:
    pass

# --- Score audio peaks ---
highlights = []

if rms_data:
    rms_values = [d["rms"] for d in rms_data if d["rms"] > -100]
    if rms_values:
        mean_rms = sum(rms_values) / len(rms_values)
        std_rms = (sum((x - mean_rms) ** 2 for x in rms_values) / len(rms_values)) ** 0.5
        
        for d in rms_data:
            if d["rms"] <= -100:
                continue
            z_score = (d["rms"] - mean_rms) / std_rms if std_rms > 0 else 0
            # Map z-score to 0-100: z=0 -> 50, z=2 -> 100, z=-2 -> 0
            score = min(100, max(0, int(50 + z_score * 25)))
            
            # Boost score if near a scene change (within 3 seconds)
            near_scene = any(abs(d["time"] - st) < 3 for st in scene_times)
            if near_scene:
                score = min(100, score + 10)
            
            if score >= threshold:
                entry = {
                    "timestamp": round(d["time"], 1),
                    "score": score,
                    "rms_db": round(d["rms"], 1),
                    "type": "audio_peak"
                }
                if near_scene:
                    entry["scene_change"] = True
                highlights.append(entry)

# --- Score transcript keywords ---
excitement_words = {
    "oh my god": 85, "no way": 82, "let's go": 80, "holy shit": 90,
    "holy crap": 85, "insane": 82, "crazy": 78, "what the": 80,
    "clutch": 85, "let's gooo": 90, "woah": 78, "wow": 75,
    "poggers": 80, "dude": 70, "unbelievable": 85, "oh no": 75,
    "gg": 72, "bruh": 73, "are you kidding": 82, "sheesh": 78
}

if transcript_file and os.path.exists(transcript_file):
    try:
        with open(transcript_file) as f:
            data = json.load(f)
        for segment in data.get("segments", []):
            text = segment.get("text", "").lower().strip()
            if not text:
                continue
            best_score = 0
            matched_word = ""
            for word, word_score in excitement_words.items():
                if word in text:
                    if word_score > best_score:
                        best_score = word_score
                        matched_word = word
            if best_score >= threshold:
                ts = segment.get("start", 0)
                highlights.append({
                    "timestamp": round(ts, 1),
                    "score": best_score,
                    "text": segment.get("text", "").strip(),
                    "keyword": matched_word,
                    "type": "keyword"
                })
    except (json.JSONDecodeError, KeyError, TypeError):
        pass

# --- Cluster and deduplicate nearby highlights (within 5 seconds) ---
highlights.sort(key=lambda x: x["timestamp"])
clusters = []
for h in highlights:
    if not clusters or h["timestamp"] - clusters[-1]["timestamp"] > 5:
        clusters.append(h)
    else:
        # Merge: keep highest score, combine unique types
        existing = clusters[-1]
        existing_types = set(existing.get("type", "").split("+"))
        new_type = h.get("type", "")
        if h["score"] > existing["score"]:
            clusters[-1] = h
            merged_types = existing_types | {new_type}
            clusters[-1]["type"] = "+".join(sorted(merged_types))
        elif new_type not in existing_types:
            existing_types.add(new_type)
            existing["type"] = "+".join(sorted(existing_types))
            existing["score"] = min(100, existing["score"] + 5)

# --- Add metadata ---
result = {
    "video_duration": video_duration,
    "threshold": threshold,
    "total_highlights": len(clusters),
    "analysis": {
        "rms_samples": len(rms_data),
        "scene_changes": len(scene_times),
        "whisper_available": bool(transcript_file)
    },
    "highlights": clusters
}

print(json.dumps(result, indent=2))
PYEOF
