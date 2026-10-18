# AniDash v2.0.0 (Generation 2) — Exact Stream Timestamps, Instant Playback Engine & Refined Theme Seekbar

Welcome to AniDash 2.0! This landmark milestone overhauls the video playback architecture for blazing-fast loading across initial playback, forward/backward seeking, and Continue Watching, guarantees frame-accurate intro/outro placement, validates recaps to eliminate false triggers, and refines seekbar styling to perfectly match your selected app theme.

## ⚡ Instant Playback & Fast Seek Engine
- **Instant Seek Resumption**: Reduced buffer thresholds from 5000ms to 1000ms (`bufferForPlaybackMs: 1000ms`, `bufferForPlaybackAfterRebufferMs: 1500ms`). Seeking backwards or forwards now resumes playback almost instantly instead of stalling for 5–10 seconds.
- **Optimized Stream Reservoir**: Adjusted media buffer to 25–60 seconds (`minBufferMs: 25000`, `maxBufferMs: 60000`), preventing connection choking and bandwidth queues on anime CDN hosts.
- **Always-Visible Loading Indicator**: The central buffering spinner is now guaranteed to display whenever data is loading or seeking, ensuring clear visual feedback at all times.
- **Fast Continue Watching**: Instant startup when launching episodes directly from the Home screen Continue Watching carousel.

## 🎯 Frame-Accurate Intro, Outro & Recap Detection
- **Stream-First Priority**: The active stream source's exact timestamps (`data.intro`, `data.outro` from HiAnime, JustAnime, MegaCloud, Zoro) are now prioritized as ground truth for the file loaded in the player.
- **JustAnime Direct Backup**: Direct exact intro/outro endpoints serve as second-tier priority.
- **Recap Desynchronization Protection**: Crowd-sourced AniSkip recaps are strictly validated against the actual opening timing. Desynchronized recaps from different cuts are discarded, ensuring recap prompts never appear during dialogue.
- **Instant Pre-Registration**: Skip intervals are registered immediately upon stream resolution before the video player starts rendering.

## 🎨 Clean Theme-Harmonized Seekbar
- **No White Borders**: Removed harsh white border lines from the seekbar highlight segments and floating badges.
- **Theme Palette Integration**: Intro, outro, and recap regions are now styled with subtle, elegant lighter tints of the user's selected app theme (`scheme.primary`), keeping them clean, distinct, and pleasant to view.

## ⏱️ Floating Skip Controls & 55s Next Episode Prompt
- **3-Second Auto-Hide**: Skip Intro/Outro buttons display for 3 seconds upon entering the interval, then auto-hide.
- **Player Controls Sync**: Tapping to reveal player controls brings the skip button back into view; hiding controls hides the button.
- **55s Fallback Prompt**: For episodes without an outro, the "Up Next" prompt activates at 55 seconds before the end.

## 🛠️ Verification
- Static analysis verified with 0 issues (`dart analyze lib/features/watch/ test/unit/`).
- Full unit test and regression suite passed (`flutter test test/unit/episode_transition_and_skip_test.dart`).
- Signed Android APK variants generated: Universal, arm64-v8a, armeabi-v7a, and x86_64.

**Version:** 2.0.0 (Build 144)
