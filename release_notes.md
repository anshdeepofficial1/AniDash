# AniDash v3.3.8 — Episode Navigation & Progress Sync

## What changed

### Episode navigation
- Opening the Episodes tab now automatically selects the relevant range or arc and scrolls the current/next episode into view.
- The in-player episode sheet now reveals the currently playing episode instead of stopping at the beginning of its arc.
- Scrolling uses the episode list's own controller and does not accidentally switch the parent details tab.
- The episode match repair action is integrated into the source status card to reduce unused space.

### Continue Watching
- Tapping a Continue Watching card immediately shows an `Opening episode…` state.
- Duplicate taps are blocked while navigation is in progress, preventing multiple overlapping playback launches.
- Bulk `Mark All Previous Episodes` now persists complete records for every selected episode and advances Continue Watching to the correct next episode.

### AniList, MAL, and local progress
- Explicit bulk watch edits sync even when automatic syncing is configured as manual or `Ask before sync`.
- Missing AniList bindings are repaired for older local entries before syncing.
- Tracker writes are awaited instead of being reported as complete while still running.
- Failed tracker writes remain in the offline retry queue rather than being silently lost.

## Verification
- Flutter analysis: **no issues**.
- Flutter tests: **164 passed**.
- Regression coverage includes marking One Piece through episode 455 and resolving Continue Watching to episode 456.
- GitHub issue #87 episode scrolling paths are covered on both the details page and player episode sheet.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater continues offering the same APK architecture already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.7...v3.3.8
