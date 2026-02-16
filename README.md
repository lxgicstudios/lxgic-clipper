# LXGIC Clipper

**The AI agent that clips your livestreams and posts them automatically.**

You stream. We do the rest.

Connect your Twitch, YouTube, or Kick stream. LXGIC Clipper watches the entire thing, detects the moments that actually matter (kills, clutches, funny reactions, chat explosions), clips them to the right format, and posts directly to TikTok, YouTube Shorts, Instagram Reels, and X.

No editors. No freelancers. No scrubbing through VODs at 2 AM.

## How It Works

1. **Connect your stream** — Twitch, YouTube, or Kick. Takes 2 minutes.
2. **AI watches everything** — Audio spikes, chat velocity, game state changes, visual motion. It knows what's clip-worthy.
3. **Clips go out automatically** — Formatted for each platform, captions burned in, posted while you sleep.

Detection to upload in about 3 minutes.

## What Makes This Different

Every other tool does one thing. Eklipse clips but doesn't post. Clipbot posts but doesn't clip with AI. Opus Clip does both but doesn't understand gaming.

LXGIC Clipper is the only tool that combines:
- Gaming-aware AI clipping (trained on actual stream highlights)
- Auto-posting to ALL platforms (TikTok, Shorts, Reels, X)
- Fully autonomous operation (connect once, never touch it again)

## Quick Start

```bash
# Install dependencies
brew install ffmpeg yt-dlp jq

# Run setup wizard
cd scripts
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
- **Processing:** FFmpeg (clip extraction, vertical/horizontal formatting, auto-captions)
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

## Pricing

| Plan | Price | Streams | Clips | Platforms |
|------|-------|---------|-------|-----------|
| Free | $0 | 1 | 3/stream | 1 (watermarked) |
| Starter | $29/mo | 1 | 10/day | 2 |
| Pro | $49/mo | 3 | Unlimited | All |
| Agency | $99/mo | 10 | Unlimited | All + API |

Get it on [Whop](https://whop.com/lxgic-clipper/).

## Docs

- [SETUP-GUIDE.md](SETUP-GUIDE.md) — Full setup guide with troubleshooting
- [SKILL.md](SKILL.md) — OpenClaw skill documentation
- [MARKETING-MASTER-PLAN.md](MARKETING-MASTER-PLAN.md) — Launch strategy

## License

MIT

---

Built by [LXGIC Studios](https://github.com/lxgicstudios)

[GitHub](https://github.com/lxgicstudios) | [Twitter](https://x.com/lxgicstudios)

Want more free AI tools? We have 20+ on our GitHub: [github.com/lxgicstudios](https://github.com/lxgicstudios)
