## AniDash v3.2.4 — Status Bar & Player Orientation Experience 🚀

### 📱 Portrait & Landscape Status Bar Fixes
- **Portrait Mode Status Bar Restored**: The system status bar (clock, battery, Wi-Fi, notifications) is now fully preserved and clearly visible at the top in portrait mode with `SafeArea(bottom: false)`, providing a clean, standard mobile experience while browsing and watching.
- **Landscape Fullscreen Completely Immersive**: In landscape fullscreen mode, the system status bar and navigation bars are now 100% hidden via Android native `WindowInsetsController` (`BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`) and `SystemUiMode.immersiveSticky`.
- **Hardware Cutout & Notch Polish**: Player controls and fullscreen buttons never overlap or clip under the status bar or notch when rotating between portrait and landscape.
- **Orientation Transition Handlers**: Added native Android configuration change callbacks (`onConfigurationChanged`) and Flutter orientation listeners so rotating into landscape automatically hides the system bars instantly without flicker.

### 🎬 Playback & Navigation Refinements
- **Async Navigation Safety**: Guarded watch screen back navigation against unmounted widget contexts, ensuring instant, lag-free exits.
- **One-Time Audio Banner Toast**: Retained refined non-repeating language banner at the bottom of the screen.
- **Accurate Download Sizes & Fast HLS Buffering**: Continues high-speed multithreaded downloads with dynamic bitrate probing.

---
**Full Changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.2.3...v3.2.4
