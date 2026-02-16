# LXGIC Clipper

Automated livestream clipping + social media posting agent for OpenClaw.

## What It Does
- Monitors livestreams (Kick, Twitch, YouTube)
- AI detects viral/highlight moments
- Auto-clips those moments
- Posts clips to TikTok, YouTube Shorts, X, Instagram Reels
- Runs 24/7 autonomously via OpenClaw

## Stack
- **Orchestration:** OpenClaw (skill file)
- **Clip Detection:** Vugola AI API (or self-hosted ffmpeg + whisper + AI)
- **Social Posting:** Postiz API (open source, self-hostable)
- **Scheduling:** OpenClaw cron jobs

## Business Model
- Sold on Whop as monthly subscription
- Tiers: Basic ($29/mo), Pro ($49/mo), Agency ($99/mo)
- Customer provides their own API keys
- We provide the skill + setup guide + support Discord

## Status
- [ ] API research
- [ ] Build OpenClaw skill
- [ ] Build setup guide
- [ ] Create Whop storefront
- [ ] Launch marketing

## Created
2026-02-15 by LXGIC Studios
