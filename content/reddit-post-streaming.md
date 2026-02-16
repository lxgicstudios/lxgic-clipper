# r/streaming Post

**Title:** I built an AI that watches my entire stream and posts clips while I sleep — AMA

---

I know the title sounds like an ad. It's not, or at least not intentionally. I genuinely just want to talk about this because it changed how I think about streaming as a content pipeline and I haven't seen many people doing it this way.

**Background:**

I'm a mid-size Twitch streamer. Around 80-120 concurrent viewers on a good day. I play mostly FPS games (Valorant, Apex, some Warzone). I've been streaming for about 3 years.

For the first 2 years I did everything manually. Stream for 4 hours, then spend another 3-4 hours going through the VOD, clipping highlights, editing them into vertical format, writing captions, and posting to TikTok and YouTube Shorts. Some weeks I just didn't have the energy and my socials would go dead for days. My TikTok growth was completely inconsistent because of it.

I'm also a software dev by day job so about 8 months ago I started building a tool to automate this. It turned into a real product and I launched it on Whop a couple months ago. It's called LXGIC Clipper.

**What it actually does:**

It watches your livestream in real time (Twitch, YouTube, or Kick) and uses AI to detect highlight moments. Kills, clutch plays, funny moments, chat going crazy, rage quits, all that stuff. Then it automatically clips them, formats them for vertical, adds captions, and posts them to TikTok, YouTube Shorts, Instagram Reels, and X.

You literally go to sleep after your stream and wake up with clips already posted.

**My actual numbers (being transparent):**

- Average stream: 3.5 hours
- Clips generated per stream: 10-15 (I have sensitivity set to medium, you can adjust this)
- Clips I'd actually post manually: 8-12 of those (the AI isn't perfect, some clips are mid)
- Time saved per week: roughly 15-20 hours of editing and posting
- TikTok views since automating: went from averaging 500-2k per clip to pretty consistently hitting 3-8k. I think this is mostly because I'm posting more consistently now, not because the clips are magically better
- Best performing auto-posted clip: 47k views on a Valorant clutch. Chat was going insane and the clip caught all of it including my reaction after

**What it's NOT good at (honest limitations):**

- It misses stuff sometimes. Maybe 1 in 10 really good moments get skipped. The AI is good but it's not a human editor who knows your content style.
- Caption customization is limited right now. You get templates but you can't do super creative per-clip captions yet. Working on this.
- It doesn't do long-form edits. This is for short clips only (15-60 seconds). If you want 10-minute YouTube compilations, you still need an editor.
- The auto-posting can feel a bit impersonal. I've started manually checking the queue before bed and removing the ones that aren't great. Takes about 5 minutes vs the 3 hours I used to spend.
- Game detection works best for popular FPS titles right now. It supports other genres but the highlight detection is noticeably better for shooters since that's what I trained it on first.
- Sometimes it clips your worst moments too. I had it post a clip of me whiffing an entire magazine and dying. Chat loved it, I did not. You can set a review queue instead of auto-post if this scares you.

**Pricing since someone will ask:**

$29/month for one channel, $49 for three channels with more features, $99 for the full thing with priority processing and API access. It's on Whop. Not cheap, I know. But I was genuinely spending 15-20 hours a week on clip work so the math made sense for me.

**The thing nobody talks about:**

The hardest part of growing as a streamer isn't streaming. It's the content machine around it. You have to be a streamer AND a TikTok creator AND a YouTube Shorts creator AND an Instagram Reels creator. It's four jobs.

Most streamers I know either burn out trying to do all of it or just don't do the short-form stuff and wonder why their channel isn't growing. The streams themselves are only the raw material. The real growth comes from clips hitting algorithms on other platforms and bringing people back to your stream.

Automating the boring parts (clipping, formatting, posting) means I can focus on actually being entertaining while live instead of dreading the 3 hours of editing after.

**AMA. Genuinely happy to answer questions about:**

- How the AI detection works
- My growth numbers before/after
- Technical stuff if you're curious
- Whether this is worth it for your specific situation (I'll be honest if it's not)
- Stream workflow and how I integrate this

And yes I know some people will call this an ad. That's fair. I did build the thing and I'm obviously biased. But I tried to be as transparent as possible about what works and what doesn't. Take it for what it is.

[edit] Getting a lot of questions about whether this works for non-gaming content. Short answer: kind of. It detects audio spikes and chat activity regardless of game, so funny moments and audience reactions get caught. But the game-specific stuff (kill detection, clutch detection) obviously only works for supported games. Working on expanding this.

[edit 2] Someone asked if I was worried about posting "bad" clips hurting my brand. Honestly yeah, a little. That's why I switched from full auto-post to review queue mode. Takes 5 min to scroll through and remove the ones I don't want going live. Best of both worlds.
