# AniDash v3.3.5 — Playback Lifecycle & Navigation Reliability

## What changed

### Calls, background playback, and audio focus
- Incoming and active calls now pause video reliably, including OEM and VoIP call modes reported through Android audio focus.
- Playback resumes after the call only when AniDash is back in the foreground and the interruption had paused an actively playing video.
- Ordinary notification sounds no longer trigger the call-only pause/resume path.
- Duplicate transient audio-focus events preserve the pending resume state instead of losing it.
- Background focus gain cannot restart audio while AniDash is still behind another app.

### Player and Picture-in-Picture
- Entering Picture-in-Picture no longer forces a video that the user had paused to start playing.
- Native Picture-in-Picture state is synchronized with the actual player state before the transition.
- Intro/outro auto-skip seeks immediately when the current position enters a validated skip range.

### Episode navigation
- The player episode sheet now uses the draggable sheet's own scroll controller, restoring smooth scrolling through long episode lists.
- Deep links now preserve supported query parameters and Android intent extras when opening AniDash content.

### Safe architecture-specific updates
- Universal, ARM64, ARMv7, and x86_64 installations remain on their own APK update channels.
- The updater no longer falls back to an incompatible or different APK architecture when the matching release asset is absent.

### Website
- Refreshed the official AniDash website and release archive.
- Improved the web-app preview, direct web-app entry point, responsive layout, and release navigation.

## Verification
- Full Flutter test suite: **156 tests passed**.
- Flutter analyzer: **0 issues**.
- Android release Kotlin compilation: **passed**.
- All `api/*.js` endpoint files: **syntax validated**.
- Production AI endpoint: **HTTP 200 with a non-empty response**.
- GitHub issue audit: **no open issues at release preparation time**.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater will continue offering the same APK variant already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.4...v3.3.5
