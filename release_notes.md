## What's Changed in v3.2.2 🚀

### 🧩 Extensions & Multi-Repository Overhaul (Fixes #68 & #69)
- **Built-in vs Android Engines**: Added top segmented switcher (`⚡ Built-in (Fast)` vs `🤖 Android (AniYomi)`) to manage both extension engines effortlessly.
- **Dedicated Repository Management Sheet**: A clean **📁 Manage Repositories** interface divides Built-in (Mangayomi) and Android (AniYomi) repositories into distinct categories with individual controls to filter, add, or delete repos.
- **Fixed Default Extensions Disappearing**: Adding custom repositories no longer hides or overrides default repositories and extensions (#68).
- **Preset Quick-Add**: Instantly add trusted repositories (MSR Hindi Repo, Kohi-den, Keiyoushi) with a single tap.

### 💾 Backup & Export Improvements (Fixes #70)
- **Direct Public Downloads Storage**: Exported backup files are now saved directly into the device's public **Downloads** directory (`/storage/emulated/0/Download/`), making them immediately accessible in any file manager without root permissions.
- **System Share Sheet Integration**: Exporting automatically triggers the Android share sheet to save your backup directly to Google Drive, Files, WhatsApp, or Telegram.
- **Clear File Location Alerts**: SnackBar now displays the exact storage path where your backup file was saved.

### 🎬 Player & PiP Stability Fixes
- **Safe Controls & Display Cutout Clearance**: Added physical hardware cutout and `SafeArea` padding so top player controls, close buttons, and fullscreen icons never clip under the status bar or camera notch.
- **Unstuck Back Navigation**: Completely overhauled Android back button handling in the player. Pressing back when an episode is loading or in portrait mode now immediately and cleanly exits without getting stuck or locked in fullscreen toggles. Rapid back presses force-exit immediately.
- **PiP Lifecycle Synchronization**: Restoring the app from Picture-in-Picture properly resets PiP state so the screen never gets stuck in a tall black player view.

### 🇮🇳 Hindi Dub Servers & Continue Watching
- **Saved Server Priority**: Continue Watching now remembers your exact last-selected server (JustAnime/JustDynamic) and resumes directly on official servers without querying Toonstream.
- **Hindi Dub Notification Navigation**: Tapping the Hindi Dub notification directly opens the Extensions screen on the AniYomi engine, filtered to Hindi dub sources.
- **Smart Hindi Sorting**: Hindi extensions (Toonstream, AnimeDubHindi, MovieBox) are prioritized at the top of the Available extensions list.

---
**Full Changelog**: https://github.com/anshdeepofficial1/AniDash/compare/v3.2.1...v3.2.2
