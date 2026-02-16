# LXGIC Clipper — Setup Guide

Get from zero to automated stream clipping in under 10 minutes.

## What You'll Need

Before you start, make sure you have:

1. **A Mac** (macOS 13+) or Linux machine
2. **Homebrew** installed (macOS) — [brew.sh](https://brew.sh)
3. **A Postiz account** — for posting clips to social media ([postiz.com](https://postiz.com) or self-host)
4. **A stream URL** — the Kick, Twitch, or YouTube stream you want to clip

## Quick Start (5 minutes)

### 1. Install Dependencies

```bash
brew install ffmpeg yt-dlp jq
```

Optional but recommended for better clip detection:

```bash
pip3 install openai-whisper
```

### 2. Run the Setup Wizard

```bash
cd /path/to/lxgic-clipper/skill/scripts
chmod +x *.sh
./setup.sh
```

The wizard walks you through:
- Checking all dependencies
- Entering your stream URL
- Connecting your Postiz API key
- Auto-detecting your connected social platforms
- Testing the recording pipeline

### 3. Test It

```bash
# Check if your stream is accessible
./clipper-agent.sh check

# Run a dry-run (clips but doesn't post)
CLIPPER_DRY_RUN=true ./clipper-agent.sh run

# Run for real
./clipper-agent.sh run
```

### 4. Set Up Automation

Use OpenClaw cron to run the clipper on a schedule:

```bash
openclaw cron create \
  --schedule "*/30 * * * *" \
  --command "clipper-agent.sh run"
```

See `cron-template.json` for pre-configured templates.

That's it. You're clipping on autopilot.

---

## Detailed Setup

### Setting Up Postiz

Postiz is what posts your clips to TikTok, YouTube, Instagram, X, and 28 other platforms. You can use their hosted version or self-host for free.

**Option A: Hosted (easiest)**

1. Go to [postiz.com](https://postiz.com) and create an account
2. Connect your social media accounts (TikTok, YouTube, etc.) in the dashboard
3. Go to Settings and generate an API key
4. Copy the API key for the setup wizard

**Option B: Self-hosted (free, unlimited)**

Postiz is open source (AGPL-3.0). Self-host on any VPS:

```bash
git clone https://github.com/gitroomhq/postiz-app
cd postiz-app
docker-compose up -d
```

Then connect your social accounts and generate an API key from your instance.

**Pricing reference:**

| Plan | Price | Channels | Posts/month |
|------|-------|----------|-------------|
| Self-hosted | $0 | Unlimited | Unlimited |
| Standard | $29/mo | 5 | 400 |
| Pro | $49/mo | 30 | Unlimited |

### Connecting Social Platforms

In your Postiz dashboard, connect each platform you want to post to:

- **TikTok** — Personal or Business account
- **YouTube** — For YouTube Shorts
- **X (Twitter)** — Personal or brand account
- **Instagram** — For Reels (requires Business/Creator account)

Each connected platform gets an integration ID that the clipper uses for posting.

The setup wizard auto-detects these IDs when you enter your API key. If you add platforms later, re-run `setup.sh` to update.

### Stream URL Formats

The clipper works with any URL that yt-dlp supports:

```
# Kick
https://kick.com/streamer-name

# Twitch
https://twitch.tv/streamer-name

# YouTube Live
https://youtube.com/watch?v=LIVE_VIDEO_ID

# YouTube Channel (clips from latest video)
https://youtube.com/@channel-name

# Direct video URL (for VOD clipping)
https://youtube.com/watch?v=VIDEO_ID
```

---

## Configuration

All config lives in `~/.lxgic-clipper/config.json`. You can edit it directly or re-run `setup.sh`.

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `stream_url` | — | URL to monitor |
| `duration_min` | 10 | How long to record per check (minutes) |
| `clip_length` | 30 | Length of each clip (seconds) |
| `threshold` | 70 | Detection sensitivity (0-100, higher = pickier) |
| `max_clips_per_run` | 3 | Max clips to create per run |
| `max_clips_per_day` | 15 | Daily clip limit |
| `platforms` | tiktok,youtube,x,instagram | Where to post |
| `caption_prefix` | — | Text before each caption |
| `caption_hashtags` | #clips #viral | Hashtags for each post |

### Environment Variables

Every setting can be overridden with environment variables. This is useful for cron jobs:

```bash
CLIPPER_STREAM_URL="https://kick.com/xqc" \
CLIPPER_THRESHOLD=80 \
CLIPPER_MAX_CLIPS=2 \
./clipper-agent.sh run
```

Full list of env vars is at the top of `clipper-agent.sh`.

### Threshold Tuning Guide

The threshold controls how sensitive clip detection is. Start here and adjust:

| Threshold | Behavior | Good For |
|-----------|----------|----------|
| 50-60 | Very sensitive, lots of clips | Testing, high-energy streams |
| 65-75 | Balanced, catches most moments | Most streamers, default |
| 80-90 | Selective, only clear highlights | Calm streams, quality over quantity |
| 90-100 | Very strict, may miss clips | Only the biggest moments |

**Tip:** Start with a dry run at threshold 60 to see what gets caught, then increase until the quality matches what you want.

```bash
CLIPPER_DRY_RUN=true CLIPPER_THRESHOLD=60 ./clipper-agent.sh run
# Review clips in ~/.lxgic-clipper/clips/
# Increase threshold and repeat until quality is right
```

---

## How It Works

The clipper runs a 4-phase pipeline:

### Phase 1: Record
Uses yt-dlp to capture a live stream segment (default 10 minutes). The recording is saved as MP4 in the working directory.

### Phase 2: Detect
Analyzes the recording for highlight moments using multiple signals:
- **Audio peaks** — Sudden volume spikes (reactions, crowd noise, hype)
- **Scene changes** — Rapid visual cuts (action sequences, replays)
- **Whisper transcription** (if installed) — Keywords like "oh my god", "no way", "let's go"

Each moment gets a score from 0 to 100. Only moments above your threshold become clips.

### Phase 3: Clip and Format
FFmpeg extracts each highlight and creates multiple versions:
- **Vertical (9:16)** — For TikTok, YouTube Shorts, Instagram Reels
- **Horizontal (16:9)** — For X/Twitter
- **With captions** — If whisper is installed, burned-in subtitles

### Phase 4: Post
Uploads clips to Postiz, which publishes them to your connected platforms. Supports immediate posting or scheduled posting for peak engagement times.

### Duplicate Prevention
The clipper tracks every clip in `~/.lxgic-clipper/clip-history.json`. If a highlight at the same timestamp from the same stream was already clipped, it gets skipped. This prevents re-posting the same moment.

---

## Cron Templates

Pre-configured scheduling templates in `cron-template.json`:

### Every 15 Minutes (Active Monitoring)
Best for popular streams where you don't want to miss anything:
```bash
openclaw cron create --schedule "*/15 * * * *" --command "clipper-agent.sh run"
```

### Every 30 Minutes (Recommended)
Good balance of coverage and efficiency:
```bash
openclaw cron create --schedule "*/30 * * * *" --command "clipper-agent.sh run"
```

### Every 2 Hours (Light Monitoring)
For less active streams or when you want fewer clips:
```bash
openclaw cron create --schedule "0 */2 * * *" --command "clipper-agent.sh run"
```

---

## Commands Reference

```bash
# Run the full pipeline
clipper-agent.sh run

# Check if stream is online
clipper-agent.sh check

# Show current status and stats
clipper-agent.sh status

# View clip history
clipper-agent.sh history

# Clear clip history
clipper-agent.sh clear-history

# Show help
clipper-agent.sh help
```

### Individual Script Usage

```bash
# Record a stream segment
record-stream.sh <url> [duration-minutes] [output-dir]

# Detect highlights in a video
detect-highlights.sh <video-file> [threshold]

# Clip and format a moment
clip-and-format.sh <video> <start-seconds> <duration> <output-dir>

# Post a clip to social platforms
post-clip.sh <video-file> <caption> [platforms] [schedule-time]
```

---

## File Structure

```
~/.lxgic-clipper/
  config.json          — Your settings
  clip-history.json    — Record of all clips (prevents duplicates)
  clips/               — Saved clip files
  logs/                — Daily log files
  work/                — Temporary recording files
```

---

## Troubleshooting

### "Stream not found" or "URL not accessible"
- Check the stream URL is correct
- Make sure the stream is actually live (for live URLs)
- Try updating yt-dlp: `yt-dlp -U` or `brew upgrade yt-dlp`
- Some streams need cookies for age-gated content: `export YT_DLP_COOKIES=/path/to/cookies.txt`

### "No highlights found"
- Lower the threshold: `CLIPPER_THRESHOLD=60 clipper-agent.sh run`
- The stream segment might genuinely be quiet (no hype moments)
- Install whisper for better detection: `pip3 install openai-whisper`
- Check the logs: `cat ~/.lxgic-clipper/logs/clipper-$(date +%Y%m%d).log`

### "Postiz API error"
- Verify your API key: check Postiz dashboard
- Make sure platforms are connected in Postiz
- Check API base URL (default: `https://api.postiz.com/public/v1`)
- Re-run `setup.sh` to refresh integration IDs

### Clips are low quality
- Lower the CRF value (default 20, try 18 for better quality): `CLIPPER_QUALITY=18 clipper-agent.sh run`
- Make sure the source stream is HD
- Check available stream quality: `yt-dlp -F <stream-url>`

### Clips are too short/long
- Adjust clip length: edit `clip_length` in config.json or set `CLIPPER_CLIP_LENGTH=45`
- Clips are centered on the highlight moment

### "Permission denied" on scripts
```bash
chmod +x /path/to/lxgic-clipper/skill/scripts/*.sh
```

### Disk space filling up
- Old recordings accumulate in `~/.lxgic-clipper/work/`
- Clean up old work files: `rm -rf ~/.lxgic-clipper/work/run_*`
- Clips stay in `~/.lxgic-clipper/clips/` — review and clean periodically

### Checking logs
```bash
# Today's log
cat ~/.lxgic-clipper/logs/clipper-$(date +%Y%m%d).log

# All logs
ls -la ~/.lxgic-clipper/logs/

# Follow live
tail -f ~/.lxgic-clipper/logs/clipper-$(date +%Y%m%d).log
```

---

## FAQ

**Q: Does this work with VODs (not live)?**
Yes. Point it at any YouTube, Twitch, or Kick video URL and it'll download, detect highlights, and clip.

**Q: How much disk space does it use?**
Each 10-minute recording is about 100-300MB (depending on quality). Clips are 5-30MB each. The work directory can be cleaned periodically.

**Q: Can I clip from multiple streams?**
Yes. Run multiple instances with different configs:
```bash
CLIPPER_STREAM_URL="https://kick.com/streamer1" clipper-agent.sh run
CLIPPER_STREAM_URL="https://kick.com/streamer2" clipper-agent.sh run
```

**Q: Is whisper required?**
No. Without whisper, detection uses audio peaks and scene changes only. Whisper adds keyword detection (catches moments when someone says "oh my god" or "let's go") and enables auto-captions on clips.

**Q: Can I review clips before they post?**
Yes. Use dry-run mode (`CLIPPER_DRY_RUN=true`) and review clips in `~/.lxgic-clipper/clips/` before posting.

**Q: What about copyright?**
Clip usage depends on the streamer's content policy. Many streamers encourage clipping (it's free promotion). Always check the streamer's rules and platform TOS.

**Q: Can I add a watermark?**
Not built-in yet, but you can modify `clip-and-format.sh` to add an overlay via ffmpeg. Example:
```bash
ffmpeg -i clip.mp4 -i logo.png -filter_complex "overlay=10:10" output.mp4
```

**Q: How do I stop the clipper?**
Remove or disable the cron job:
```bash
openclaw cron list
openclaw cron delete <job-id>
```

---

## Support

- GitHub: [github.com/lxgicstudios](https://github.com/lxgicstudios)
- Twitter: [@lxgicstudios](https://x.com/lxgicstudios)
- Discord: [discord.gg/lxgic](https://discord.gg/lxgic)

Built by LXGIC Studios
Want more free tools? Check out 100+ on our GitHub: github.com/lxgicstudios
