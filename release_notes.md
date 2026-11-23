# AniDash v3.3.6 — Android Update & Episode Navigation Hotfix

## What changed

### Android updates
- Fixed the Android version-code regression that caused v3.3.5 to be rejected as a downgrade on devices running the affected v3.3.4 build.
- Adopted a monotonic semantic version-code scheme and added a regression test so future releases cannot repeat this problem.
- Existing Universal, ARM64, ARMv7, and x86_64 installations continue receiving the matching APK variant.

### Player episode navigation
- Reworked the player episode sheet so its episode list owns an independent scroll controller.
- Removed the nested draggable-sheet/list gesture competition that could leave long episode lists stuck on some Android devices.
- The sheet remains swipe-dismissible and opens directly around the currently playing episode.

## Verification
- Full Flutter test suite: **157 tests passed**.
- Flutter analyzer: **0 issues**.
- Android APK build: **intentionally deferred** for this source-only hotfix stage.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater will continue offering the same APK variant already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.5...v3.3.6
