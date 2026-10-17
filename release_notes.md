# AniDash v1.30.0 — Guaranteed Intro/Outro Fetching, 3s Skip Button & 55s Next Episode Prompt

This major update completely resolves intro and outro detection across all providers by integrating JustAnime's direct exact skip endpoint alongside AniSkip, introduces a seamless 3-second auto-hide with player-controls sync for the skip button and next episode prompts, enhances timeline belt visibility matching the user's theme palette, and tunes the fallback next episode prompt to 55 seconds.

## Guaranteed Multi-Source Intro/Outro Detection
- **JustAnime Direct Skip Integration**: Queries JustAnime's exact intro/outro endpoints (`sub.intro`, `sub.outro`, `dub.intro`, `dub.outro`) in parallel with AniSkip, ensuring exact skip markers are detected for virtually all anime titles and episodes.
- **Ani.zip Mapping Acceleration**: High-speed MAL ID resolution via Ani.zip mappings ensures instant crowd-sourced AniSkip query resolution.
- **Unified Merge Engine**: Merges crowd-sourced AniSkip timestamps, JustAnime exact timestamps, and streaming server fallback markers seamlessly.

## Floating Skip Button (3s Auto-Hide & Player Controls Sync)
- **3-Second Initial Visibility**: When playback enters an opening or ending interval, the "Skip Intro" / "Skip Outro" button displays for 3 seconds, then gracefully auto-hides.
- **Sync with Player Controls**: While within the intro/outro, tapping the screen to show player controls instantly surfaces the skip button. When controls hide, the button hides with them.
- **Interval-Bound Lifecycle**: Once the intro or outro completes, the skip button dismisses completely and will not show on controls tap.
- **Instant Manual Skip**: Tapping the button seeks to the end of the marker and immediately dismisses the prompt.

## Next Episode Prompt Tuned to 55 Seconds
- **55-Second Threshold**: When an episode has no detected outro, the "Up Next" prompt now appears exactly 55 seconds before the end (down from 90s).
- **Matching Display Flow**: Shows for 3 seconds upon trigger, then auto-hides; re-appears whenever player controls are active and animates cleanly above the control bar.

## Seekbar & Timeline Belt Visual Clarity
- **Theme Palette Integration**: Intro, outro, and recap markers are styled directly from the user's selected theme palette (`scheme.primary`, `scheme.secondary`, `scheme.tertiary`) with luminous borders and high-contrast labels that remain visible and legible over the scrubber bar.

## Validation
- Complete static analysis verified with 0 issues (`dart analyze`).
- Full unit test and regression suite passed (`flutter test`).
- Signed Android APK variants: Universal, arm64-v8a, armeabi-v7a, and x86_64.

**Version:** 1.30.0 (143)
