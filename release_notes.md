# AniDash v3.3.7 — Automatic Source Recovery

## What changed

### Source availability
- JustAnime is detected as unavailable while its website, catalogue, and stream API are down.
- Unavailable built-in sources are greyed out and cannot be selected until their live health checks recover.
- HiAnime is now the default built-in source for new installations.
- Existing native-source users saved on the unavailable JustAnime route are moved to HiAnime automatically.
- If any selected built-in source goes offline later, AniDash automatically selects the next healthy built-in source. Installed extensions are never changed by this migration.

### Faster episode and stream recovery
- Episode fallback probes now accept the first provider that returns a valid episode list instead of waiting for every failed provider timeout.
- Playback fallback skips providers already confirmed offline.
- Removed the old extension fallback that always waited for JustAnime even when JustAnime was known to be down.
- Provider-specific episode IDs remain paired with the provider that supplied them, preventing wrong-episode playback after a fallback.

### Episode source UI
- Replaced the cramped underlined source header with a responsive, theme-aware source status card.
- Added clear `Ready`, `Checking`, `Limited`, and `Unavailable` states.
- Source selection in onboarding, settings, and anime details consistently reflects live availability.

## Live verification
- JustAnime frontend: **503 Service Unavailable**.
- JustAnime core search, episode, and stream endpoints: **unavailable**.
- HiAnime catalogue: **working**.
- AniKoto catalogue: **working**.
- Current episode metadata and HLS playback chain: **working**.
- One Piece episodes 1, 440 SUB, 440 DUB, and 750 resolved to playable media responses.
- Flutter tests: **162 passed**.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater continues offering the same APK architecture already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.6...v3.3.7
