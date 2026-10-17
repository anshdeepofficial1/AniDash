# AniDash v1.20.7 — Exact skip timing, deeper buffering and AnyCore vision

This release preserves the working video engine while correcting episode identity, skip timing, AI attachments and unreleased-title behavior.

## Playback and buffering
- Increase Android's time-prioritized forward buffer from 120 seconds to a five-minute target while keeping five-second startup.
- Keep the selected playback engine and stream-opening route unchanged.
- Clear stale stream state when switching between different anime with the same episode number.
- Refuse unsafe episode-1 fallback when a provider cannot resolve the requested episode.
- Require a confidence-matched title before switching episode providers.

## Intro, outro and recap
- Prefer AniSkip's exact MAL-title and episode-specific timestamps over provider-average markers.
- Use selected-stream intro/outro markers only when the exact episode marker is unavailable.
- Preserve recap as an independent marker.
- Correctly classify mixed opening and mixed ending records.

## AnyCore AI
- Send attached screenshots as real multimodal image parts to Gemini and compatible vision providers.
- Resize and compress images before upload to stay within backend request limits.
- Keep attachment labels in chat history so users can see what was sent.
- Allow natural confirmed requests such as adding anime from screenshots to Planning.
- Resolve image-recognized anime titles through AniList before saving them locally.
- Improve Android voice recognition using the web-search language model and retain final recognition results.

## Upcoming anime
- Do not search SUB/DUB or streaming sources for titles that have not released.
- Show the known first-episode or start date in the Episodes tab when metadata provides it.
- Start source discovery only after metadata reports that the title has released.

## Validation
- Dart analysis completed with no issues across all changed files.
- The complete Flutter test suite passes: 108 tests.
- GitHub Actions builds signed Universal, arm64-v8a, armeabi-v7a and x86_64 APKs.

**Version:** 1.20.7 (140)
