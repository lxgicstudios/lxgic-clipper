---
name: lxgic-clipper
description: Automated livestream clipping and social media posting agent. Monitors Kick/Twitch/YouTube streams, detects highlight moments via audio analysis and whisper transcription, clips them, and posts to TikTok, YouTube Shorts, X, and Instagram Reels — 24/7 on autopilot.
homepage: https://whop.com/lxgic-clipper/
metadata:
  {
    "openclaw":
      {
        "emoji": "🎬",
        "requires": { "bins": ["ffmpeg", "yt-dlp"] },
        "install":
          [
            {
              "id": "ffmpeg",
              "kind": "brew",
              "formula": "ffmpeg",
              "bins": ["ffmpeg"],
              "label": "Install ffmpeg (video processing)",
            },
            {
              "id": "yt-dlp",
              "kind": "brew",
              "formula": "yt-dlp",
              "bins": ["yt-dlp"],
              "label": "Install yt-dlp (stream downloading)",
            },
          ],
      },
  }
---

# LXGIC Clipper — Automated Stream Clipping Agent

## What This Does

Monitors livestreams 24/7 and automatically:
1. Records stream segments (configurable 5-30 minute windows)
2. Detects viral/highlight moments via audio peaks, scene changes, and whisper transcription
3. Clips those moments (15-60 second clips)
4. Formats for each platform (vertical 9:16 + horizontal 16:9, with optional burned-in captions)
5. Posts to TikTok, YouTube Shorts, X, and Instagram Reels via Postiz API
6. Tracks clip history to prevent duplicate posts

## Requirements

### API Keys (customer provides)
- **Postiz API key** — for social media posting (get at [postiz.com](https://postiz.com) or self-host for free)

### Tools (auto-installed)
- `ffmpeg` — video processing, clipping, encoding, audio analysis
- `yt-dlp` — stream recording and downloading

### Optional (recommended)
- `whisper` — OpenAI Whisper for transcription-based detection + auto-captions
  - Install: `pip3 install openai-whisper`
  - Without it, detection uses audio peaks + scene changes only

### Environment Variables
Set via `setup.sh` wizard, config file, or env:
```
CLIPPER_STREAM_URL=https://kick.com/yourstreamer
CLIPPER_DURATION=10           # recording length in minutes
CLIPPER_THRESHOLD=70          # detection sensitivity (0-100)
CLIPPER_CLIP_LENGTH=30        # clip duration in seconds
CLIPPER_MAX_CLIPS=3           # max clips per run
CLIPPER_MAX_DAILY=15          # max clips per day
CLIPPER_PLATFORMS=tiktok,youtube,x,instagram
CLIPPER_DRY_RUN=false         # true to skip posting
POSTIZ_API_KEY=your_postiz_key
```

## Setup

### Quick Start
```bash
# 1. Install dependencies
brew install ffmpeg yt-dlp jq

# 2. Run interactive setup
./setup.sh

# 3. Test it
./clipper-agent.sh run
```

See `SETUP-GUIDE.md` for detailed walkthrough.

### Step 1: Install the skill
```bash
openclaw skill install lxgic-clipper
```

### Step 2: Run setup wizard
```bash
./setup.sh
```
This walks you through configuration interactively:
- Stream URL
- Postiz API key and platform connections
- Detection settings
- Test recording

### Step 3: Start the agent
Set up an OpenClaw cron job using the templates in `cron-template.json`:
```bash
openclaw cron create --schedule "*/30 * * * *" --command "clipper-agent.sh run"
```

## How Clip Detection Works

The skill uses local analysis (zero external API cost for detection):

1. **Audio peaks** — FFmpeg RMS analysis detects sudden volume spikes (reactions, hype moments, crowd noise)
2. **Scene changes** — FFmpeg scene detection flags rapid visual cuts (action, replays)
3. **Speech keywords** (requires whisper) — Transcribes audio and flags excitement phrases ("oh my god", "no way", "let's go", "insane", etc.)
4. **Multi-signal scoring** — Each moment is scored 0-100. Audio peaks near scene changes get boosted. Only moments above your threshold become clips.
5. **Deduplication** — Nearby highlights (within 5 seconds) are merged to avoid redundant clips.

```
Stream → Record segment → FFmpeg audio analysis + scene detection
→ Whisper transcription (optional) → Score moments → Clip top N
→ Format (vertical + horizontal + captions) → Post via Postiz
```

## Clip Processing Pipeline

1. **Record:** `yt-dlp` captures stream in configurable segments
2. **Detect:** Multi-signal scoring (audio + visual + speech)
3. **Clip:** `ffmpeg` extracts highlight with configurable padding
4. **Format:**
   - 9:16 vertical crop for TikTok/Reels/Shorts
   - 16:9 padded horizontal for X/Twitter
   - Burned-in captions via whisper transcription (optional)
5. **Post:** Postiz API publishes to all connected platforms
6. **Log:** History tracked in JSON to prevent duplicate posts

## Scripts

| Script | Purpose |
|--------|---------|
| `setup.sh` | Interactive configuration wizard |
| `clipper-agent.sh` | Main orchestrator (run/check/status/history) |
| `record-stream.sh` | Records stream segments via yt-dlp |
| `detect-highlights.sh` | Analyzes video for highlight moments |
| `clip-and-format.sh` | Clips and formats for social platforms |
| `post-clip.sh` | Uploads and posts clips via Postiz API |

## Commands

```bash
clipper-agent.sh run          # Full pipeline: record → detect → clip → post
clipper-agent.sh check        # Check if stream is live
clipper-agent.sh status       # Show status, stats, stream availability
clipper-agent.sh history      # Show clip history
clipper-agent.sh clear-history # Reset clip history
```

## Platform Formatting

| Platform | Aspect | Max Length | Captions |
|----------|--------|-----------|----------|
| TikTok | 9:16 | 60s | Auto (burned in if whisper installed) |
| YouTube Shorts | 9:16 | 60s | Auto (SRT file) |
| X/Twitter | 16:9 or 9:16 | 140s | Optional |
| Instagram Reels | 9:16 | 90s | Auto (burned in if whisper installed) |

## File Structure

```
~/.lxgic-clipper/
  config.json           — Settings (created by setup.sh)
  clip-history.json     — Clip tracking (prevents duplicates)
  clips/                — Saved clip files
  logs/                 — Daily log files
  work/                 — Temporary recording files
```

## Troubleshooting

### Stream not recording
- Check URL is correct and stream is live
- Update yt-dlp: `yt-dlp -U` or `brew upgrade yt-dlp`
- Some streams require cookies: `export YT_DLP_COOKIES=/path/to/cookies.txt`

### No highlights detected
- Lower threshold: `CLIPPER_THRESHOLD=60`
- Install whisper for better detection: `pip3 install openai-whisper`
- Check logs: `cat ~/.lxgic-clipper/logs/clipper-$(date +%Y%m%d).log`

### Clips not posting
- Verify Postiz API key and platform connections
- Re-run `setup.sh` to refresh integration IDs
- Check API base URL in config

### Low quality clips
- Lower CRF value: `CLIPPER_QUALITY=18` (default 20, lower = better)
- Ensure source stream is HD

## Support
- GitHub: [github.com/lxgicstudios](https://github.com/lxgicstudios)
- Twitter: [@lxgicstudios](https://x.com/lxgicstudios)
- Discord: [discord.gg/lxgic](https://discord.gg/lxgic)

Built by LXGIC Studios
Want more free tools? We have 100+ on our GitHub: github.com/lxgicstudios
