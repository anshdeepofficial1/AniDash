# AniDash v1.20.9 — Theme-Matched Skip Markers, Seek Auto-Skip & Instant Next Episode Countdown

This release fixes intro auto-skipping and button visibility when fast-forwarding/seeking 10 seconds into the opening, aligns intro and outro timeline highlights with the app's user-selected theme color, instantly zeroes progress and countdown on next episode transitions, and enables automatic thumbnail and episode title resolution for Home Continue Watching.

## Intro & Outro Timeline Belt & Skip Buttons
- **Theme-Matched Colors**: Replaced hardcoded yellow and pink accents on the seek bar and skip buttons with the active theme color (`scheme.primary` and `scheme.onPrimary`), ensuring complete visual consistency with the user's selected app palette.
- **Auto-Skip & Skip Button on 10s Fast-Forward**: Eliminated rigid boolean guards that prevented auto-skipping or hiding the skip button when seeking directly into an ongoing intro/outro. Per-segment range keys now ensure auto-skip triggers reliably at any playback position within the opening.
- **Immediate Pre-Fetching**: Trigger AniSkip lookup as soon as the media manifest initializes or when the next episode is selected, so skip ranges are available before playback starts.

## Next Episode Transitions & Progress Scrubber
- **Instant Scrubber & Countdown Reset**: When an episode ends and the subsequent episode auto-loads (e.g., from Ep 277 to Ep 278), `resetForNewEpisode` immediately sets position, duration, and buffer to zero. The player countdown timer and seek bar start cleanly from `00:00` without freezing at 100% completion.

## Home Continue Watching Auto-Refetch
- **Automatic Metadata Enrichment**: The Home screen "Continue Watching" card now enriches episode metadata directly without requiring users to manually open the anime's episodes screen.
- **Multi-Source Fallback**: Leverages high-resolution Ani.zip mapping screenshots, canonical TVMaze animation episode titles, TMDB JustAnime direct details, and provider lookups, caching results in memory and persisting them into local storage.

## Validation
- Complete static analysis verified with 0 issues (`dart analyze`).
- Unit and regression test suite passed (`flutter test`).
- Signed Android APK variants generated: Universal, arm64-v8a, armeabi-v7a, and x86_64.

**Version:** 1.20.9 (142)
