# AniDash v1.20.8 — Exact Playback Identity, Enhanced Skip Belt & Multimodal AI

This release completely fixes anime episode loading identity (Issue #35), polishes intro/outro/recap skip overlays and seek bar markers, improves multimodal vision attachment in AI chat, enhances conversational voice input, and upgrades unreleased anime UI.

## Playback & Identity Resolution (Issue #35)
- Fixed false-fallback bug where opening anime with titles not directly matching provider catalogs defaulted to One Piece Episode 1.
- Removed blind `.first` and `.firstOrNull` fallbacks across `episode_stream_provider`, `episode_list_provider` (JustAnime), `anikoto`, and `animepahe`.
- Fixed MAL ID substring matching collision in `anime_match_service` so IDs like 21 do not collide with unrelated anime.
- Preserved 300s/5-minute deep buffering and instant playback startup.

## Intro, Outro & Recap Skip
- Overhauled seek bar timeline ("belt") highlights with distinct, vibrant colors:
  - **RECAP**: Vibrant Teal / Cyan badge
  - **INTRO**: Warm Amber / Gold badge
  - **OUTRO**: Soft Purple / Violet badge
- Added dedicated "Skip Recap" floating action button alongside Skip Intro and Skip Outro.
- Extended skip button display time from 3 seconds to 8 seconds, and ensure it remains visible whenever player controls are active.
- Relaxed arbitrary recap boundaries so cold opens and mid-episode recaps are correctly recognized and skippable.
- Support auto-skipping recaps automatically when `enableAutoSkip` is active.

## AnyCore AI & Voice Input
- Fixed image vision attachment on Android and desktop: handles paths when `file.bytes` is null and supports uploading multiple anime images at once.
- Updated AI backend routing so prompts with image attachments route directly to multimodal Gemini 2.5 Flash Lite instead of text-only LLMs.
- Upgraded voice input to natural speech dictation mode, removing aggressive word replacements so natural Hindi/English conversational queries work seamlessly.

## Unreleased Anime Experience
- Hidden SUB/DUB audio badges and perpetual loading spinners on unreleased titles.
- Replaced "No episodes found" with an informative countdown / release date card showing the next airing episode schedule or premiere date.

## Validation
- Complete test suite passes.
- Universal, arm64-v8a, armeabi-v7a, and x86_64 signed APK variants.

**Version:** 1.20.8 (141)
