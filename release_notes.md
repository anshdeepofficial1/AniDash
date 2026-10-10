# AniDash v1.19.4 — Fast Stream Resolution, Auto-Skip Recap & Mobile Layout Restoration

This release resolves JustAnime stream loading issues, restores instant multi-source failover, recovers the mobile bottom navigation bar on anime details, adds automatic recap skipping, and restores the 100-second video playback readahead buffer.

## What's New & Fixed

- **Fast JustAnime Stream Resolution**
  - Prioritized direct high-performance endpoints (`/watch/:id/episode/:ep/megaplay` and `/watch/:id/episode/:ep`) for sub and dub streams.
  - Eliminated infinite loading spinners with aggressive 6-second timeouts and fast 250ms hedging across stream probes.

- **Non-blocking Multi-Source Failover**
  - Instant concurrent fallback when primary or external providers (such as HiAnime or AniKoto) are slow or unreachable.
  - Reduced individual probe timeouts so playback begins in seconds instead of hanging on the loading screen.

- **High-Performance Video Playback & Buffering**
  - Restored 100-second readahead buffer (`demuxer-readahead-secs: 100`) and 600-second cache time.
  - Buffer memory clamped to 100MB–256MB with instant startup (`cache-pause-initial: no`), ensuring zero stutter and instant seek response.

- **Auto-Skip Recap, OP & ED**
  - Integrated full automatic skipping for "Recap / Previously-on" segments in addition to Opening and Ending themes.
  - Added dedicated "Skip Recap" floating overlay button and labeled recap markers on the playback seekbar.

- **Mobile Navigation Bar Restored on Details Screen**
  - Restored 'About', 'Episodes', and 'Characters' navigation tabs to the bottom navigation bar on Android and iOS.
  - Preserved sticky inline header exclusively for desktop platforms (Windows and macOS).

**Version:** 1.19.4 (128)
