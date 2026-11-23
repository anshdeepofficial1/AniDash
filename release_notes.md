# AniDash v3.3.6 — Android Update & Episode Navigation Hotfix

## What changed

### Android updates
- Fixed the Android version-code regression that caused v3.3.5 to be rejected as a downgrade on devices running the affected v3.3.4 build.
- Adopted a monotonic semantic version-code scheme and added a regression test so future releases cannot repeat this problem.
- Existing Universal, ARM64, ARMv7, and x86_64 installations continue receiving the matching APK variant.

### Player episode navigation
- Reworked the player episode sheet so its episode list owns an independent scroll controller.
- Removed the nested draggable-sheet/list gesture competition that could leave long episode lists stuck on some Android devices.
- The sheet still closes with Back or an outside tap and opens directly around the currently playing episode.

### Source recovery
- Updated HiAnime matching for its current website layout and AniList-linked catalogue.
- Restored HiAnime episode discovery, subtitles, episode-specific intro/outro metadata, and playable HLS resolution through its current stream service.
- Migrated AniKoto from the retired `.pw` API to its current catalogue and stream route.
- A JustAnime DNS/Cloudflare outage no longer prevents explicitly selected HiAnime, AniKoto, or installed Hindi sources from being used.
- Built-in source status now follows a real catalogue health check: unavailable sources are disabled and shown as `Not available`, then become selectable again automatically after recovery.
- Re-verified the recovered JustAnime website and catalogue API before release.
- Installed Hindi sources remain selectable when a temporary availability probe cannot confirm a title; the app no longer silently redirects them to JustAnime.

## Verification
- Full Flutter test suite: **159 tests passed**.
- Flutter analyzer: **0 issues**.
- Live provider smoke tests: **HiAnime and AniKoto search, episodes, and playable HLS passed**.
- Android release build: **verified by the release workflow**.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater will continue offering the same APK variant already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.5...v3.3.6
