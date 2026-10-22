# AniDash v2.1.3 — Seamless Playback, Instant Fillers & UI Notch Hardening

AniDash v2.1.3 delivers instant filler episode tag rendering, resolves the next-episode auto-play loading spinner lockup, hardens video player orientation and notch/status bar spacing in portrait mode, secures the developer issue dashboard, and resolves repository security advisories.

## 🌟 What's New in v2.1.3

### ⚡ Instant 0s Filler Episode Tags
- **Persistent Disk & Memory Cache**: Once fetched, canon/mixed/filler episode classification is cached locally (`SharedPreferences`). Opening any anime or episode list renders filler tags immediately (**0ms delay**).
- **AnimeFillerList Priority**: Flipped priority to query AnimeFillerList directly first (~250–400ms for entire series metadata), keeping Jikan strictly as a capped fast fallback.
- **Eager Prefetching**: Details screen eagerly prefetches filler information in parallel during metadata initialization so tags are already available before episode lists render.

### 🎬 Next-Episode Auto-Play "Starting Video" Fix
- **Smooth Playback Handoff**: Fixed a critical race condition where auto-advancing at the end of an episode left the "Starting video…" loading spinner spinning endlessly over a playing video.
- **Playback Event Driven**: Integrated BetterPlayer `play` and `progress` event listeners so loading indicators and buffering states dismiss immediately upon first frame decoding.
- **Timeline Synchronization**: Fixed `_episodeTransitionInProgress` timeline latching in `WatchController` so progress bar and player controls track seamlessly from 0:00 without freezing.

### 📱 Portrait Mode & Status Bar / Notch Spacing
- **Hardware-Aware Notch Clearance**: Replaced naive padding with true physical display cutout insets (`viewPadding.top`). The top circular back button, title, and controls never get obscured by camera cutouts or status bar icons.
- **Auto-Sync Rotation**: Turning the phone upright to portrait now cleanly restores the 16:9 pinned player and detailed tabs, preventing accidental full-screen layout lockup in portrait.
- **Adaptive Fullscreen Button**: Bottom toolbar icon dynamically toggles between fullscreen and exit-fullscreen icons based on the current screen state.

### 🛡️ Developer-Exclusive Issues Dashboard & Security Hardening
- **Admin-Only Access**: The "User Feedback & Issues" viewer is strictly restricted to developer AniList account (`ID: 8013267`) and protected by the 4-digit Developer PIN.
- **Repository Security Governance**: Added GitHub-standard `.github/SECURITY.md` security policy, automated `.github/dependabot.yml` vulnerability tracking, and secret scanning CI workflow.
- **Credential Cleanliness**: Removed tracked Google API Key from `google-services.json` and resolved GitHub secret scanning alert #1. Root repository cleaned and un-cluttered.

## 🛠️ Verification
- Static analysis verified: 0 errors, 0 warnings (`dart analyze lib/`).
- Full unit test suite verified: 117/117 tests passed (`flutter test test/unit/`).
- Available APK Variants: Universal, arm64-v8a, armeabi-v7a, x86_64.

**Version:** 2.1.3 (Build 148)
