# AniDash v2.1.2 — Universal Franchise Ordering, In-App Feedback & Playback Polish

AniDash v2.1.2 introduces canonical chronological season ordering across all anime franchises, dual-mode In-App Feedback and Bug Reporting for non-GitHub users, granular subtitle timing adjustments, reliable intro/outro skip controls, and critical extension detection fixes.

## 🌟 What's New in v2.1.2

### ⛩️ Universal Franchise & Chronological Season Ordering
- **Canonical Release Order**: Season navigation chips across all anime franchises (Demon Slayer, Attack on Titan, Jujutsu Kaisen, Bleach, Dr. Stone, JoJo's Bizarre Adventure, and more) are now strictly arranged by canonical release order.
- **Clean Story Arc Recognition**: Clean, human-readable arc names (e.g. *Mugen Train Arc*, *Entertainment District Arc*, *Swordsmith Village Arc*, *Hashira Training Arc*, *Infinity Castle Arc*) replace raw relation tags and duplicate titles.
- **Instant Seamless Season Switching**: Fixed an issue where switching between seasons or tapping back to Season 1 resulted in missing episodes. Each season now retains its resolved sources and loads immediately without restarting.

### 📝 In-App Issue & Feedback System (No GitHub Account Needed)
- **Direct In-App Feedback**: Users without a GitHub account can now submit bug reports, playback issues, and feature requests directly from **Settings > Report Issue / Feedback** and the **About** screen.
- **Auto Diagnostics**: Automatically captures device, OS, and app version metadata for faster diagnosis.
- **Dual Choice**: Choose between direct in-app submission or GitHub issue tracker.

### 🎬 Subtitles & Player Continuity
- **Granular Subtitle Sync**: Added real-time `±0.1s` and `±1.0s` timing buttons to the Subtitle Selection Sheet so users can effortlessly calibrate audio-subtitle synchronization.
- **Multi-line Subtitle Formatting**: Fixed multi-line subtitle rendering with clean line-break preservation.
- **Clean Next-Episode Timeline Reset**: Outro auto-advance now resets the timeline cleanly to `00:00` for the upcoming episode, preventing the new episode from inheriting finished timestamps.
- **Always-Visible Floating Skip Buttons**: Skip Intro and Skip Outro buttons consistently appear for 2 seconds (matching player control fade behavior) in fixed positions, regardless of whether auto-skip is enabled or disabled.

### 🧩 Extension System Fixes (Issues #41, #42, #43)
- **Installed Extensions Visibility (Issue #42)**: Resolved an issue where installed AniYomi and MangaYomi extensions were not appearing in the Installed menu.
- **Download Theme & Contrast Fixes (Issue #41)**: Fixed download card text contrast under single-color themes and ensured automatic temp file cleanup across completed, cancelled, and paused downloads.
- **Subtitle Language Selection Fix (Issue #43)**: Fixed stream headers and encoding normalization so subtitle tracks load reliably upon language selection.

### 📈 Trending & Library Integration
- **AniList Pagination Fix**: Fixed "You reached the end" bug when opening Trending Anime by adding full pagination info to AniList queries.
- **Releasing Anime Metadata**: Fixed an issue where currently releasing anime (e.g., Black Clover Season 2) did not show About and episode listings.
- **Local Watchlist Integration**: "Track" button now seamlessly reflects local Watchlist (Planning / Watching) state even without remote AniList login.

## 🛠️ Verification
- Static analysis verified: 0 errors, 0 warnings (`dart analyze lib/`).
- Full test suite verified: 40/40 tests passed (`flutter test`).
- Available APK Variants: Universal, arm64-v8a, armeabi-v7a, x86_64.

**Version:** 2.1.2 (Build 147)
