# AniDash v3.3.9 — AniDash Go Device Pairing

## What changed

### AniDash Go
- Added an AniDash Go website card to **Settings → About**.
- Added a first-launch website preview with direct external-browser access.
- Added **Settings → Devices** for QR-code and manual-code browser pairing.
- Pairing now shows the requesting browser and operating system before approval.
- Added explicit approve and deny handling for one-time pairing requests.

### Device history and sync
- Records locally verified paired-device details, connection time, last verification time, and pairing age.
- Shares supported tracker identity and playback preferences through the deployed AniDash Go pairing contract.
- Keeps credentials out of QR codes and app-visible website URLs.
- Clearly distinguishes local pairing history from live server activity.

### Player reliability
- The manual intro/outro skip control remains available when an automatic seek does not land successfully.
- Automatic episode transitions now rebind the replacement video controller so duration, position, buffering, and the progress bar update immediately.

## Verification
- Flutter analysis: **no issues**.
- Flutter tests: **169 passed**.
- Release APK produced successfully from the updated source.

## Android downloads
- **Universal** — safest choice when the device architecture is unknown.
- **arm64-v8a** — most modern Android phones and tablets.
- **armeabi-v7a** — older 32-bit ARM devices.
- **x86_64** — Android emulators and x86_64 devices.

AniDash's in-app updater continues offering the same APK architecture already installed on the device.

---
**Full changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.3.8...v3.3.9
