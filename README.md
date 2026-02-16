# LXGIC Clipper

Automated livestream clipping + social media posting agent for OpenClaw.

## What It Does
- Monitors livestreams (Kick, Twitch, YouTube) 24/7
- Detects viral/highlight moments via audio analysis + whisper transcription
- Auto-clips those moments in vertical (9:16) and horizontal (16:9) formats
- Posts clips to TikTok, YouTube Shorts, X, Instagram Reels via Postiz API
- Tracks clip history to prevent duplicate posts
- Runs autonomously via OpenClaw cron jobs

## Quick Start

```bash
# Install dependencies
brew install ffmpeg yt-dlp jq

# Run setup wizard
cd skill/scripts
chmod +x *.sh
./setup.sh

# Test it (dry run)
CLIPPER_DRY_RUN=true ./clipper-agent.sh run

# Run for real
./clipper-agent.sh run
```

## Stack
- **Recording:** yt-dlp (any stream platform)
- **Detection:** FFmpeg audio analysis + scene detection + Whisper transcription
- **Processing:** FFmpeg (clip extraction, vertical/horizontal formatting, captions)
- **Distribution:** Postiz API (32 platform support, self-hostable)
- **Orchestration:** OpenClaw cron jobs

## Scripts

| Script | Purpose |
|--------|---------|
| `setup.sh` | Interactive configuration wizard |
| `clipper-agent.sh` | Main orchestrator (run/check/status/history) |
| `record-stream.sh` | Records stream segments via yt-dlp |
| `detect-highlights.sh` | Analyzes video for highlight moments |
| `clip-and-format.sh` | Clips and formats for social platforms |
| `post-clip.sh` | Uploads and posts clips via Postiz API |

## Docs
- [SETUP-GUIDE.md](SETUP-GUIDE.md) — Full setup guide with troubleshooting and FAQ
- [SKILL.md](SKILL.md) — OpenClaw skill documentation
- [cron-template.json](cron-template.json) — Pre-configured cron job templates
- [research/api-research.md](research/api-research.md) — API and market research

## Business Model
- Sold on Whop as monthly subscription
- Tiers: Basic ($29/mo), Pro ($49/mo), Agency ($99/mo)
- Customer provides their own Postiz API key
- Skill + setup guide + support Discord

## Status
- [x] API research (Postiz, clip detection alternatives)
- [x] Record stream script (yt-dlp)
- [x] Detect highlights script (FFmpeg + Whisper)
- [x] Clip and format script (vertical + horizontal + captions)
- [x] Postiz integration script (upload + multi-platform post)
- [x] Main orchestrator pipeline
- [x] Interactive setup wizard
- [x] OpenClaw cron templates
- [x] Setup guide with troubleshooting + FAQ
- [x] Local pipeline testing (end-to-end verified)
- [ ] Create Whop storefront
- [ ] Launch marketing

## Created
2026-02-15 by LXGIC Studios

Built by LXGIC Studios
GitHub: github.com/lxgicstudios | Twitter: @lxgicstudios
Want more free tools? We have 100+ on our GitHub: github.com/lxgicstudios
