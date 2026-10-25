# AniDash v2.1.5 — Offline Subtitle Engine, Accurate Quality Downloads & Multi-Language Support

AniDash v2.1.5 resolves key community-reported issues (#60, #61, #62, #63), delivering complete offline subtitle support with ASS/SSA parsing, accurate HLS video quality matching during downloads, dynamic multi-language source support, black screen prevention, and export/share capabilities.

## 🌟 What's New in v2.1.5

### 📝 Complete Subtitle Engine & Offline Subtitles (#60, #62)
- **ASS/SSA Subtitle Parser**: Added full ASS/SSA format dialogue parsing in the video player engine (`BetterPlayerSubtitle.fromAss`), automatically stripping styling override tags (such as `{\an8}`), formatting line breaks (`\N`), and rendering subtitles smoothly.
- **Offline Subtitle Playback**: Downloaded video files now properly load and bind their local `.vtt`, `.srt`, and `.ass` subtitle sidecars during offline playback.
- **Auto-Activation**: Playback automatically selects the preferred subtitle track matching the source language (or English) on startup without requiring manual toggling.
- **Cross-Platform File Resolution**: Fixed local file path URI parsing on Windows and Android so file-based subtitles load reliably.

### 📥 Accurate Quality Matching & Probed File Size (#60, #63)
- **Explicit Quality Downloader**: Selecting 360p, 480p, 720p, or 1080p now accurately downloads that exact stream variant from HLS master playlists instead of always defaulting to highest bandwidth.
- **Probed File Size Estimation**: Replaced static size estimates with live M3U8 bandwidth-probed size calculations, accurately reflecting true episode size (~800MB–1.1GB for 1080p) before downloading.

### 🌐 Universal Multi-Language Support (#61)
- **Dynamic Source Language Detection**: Added `LanguageUtils` mapping 18+ languages (German, French, Spanish, Italian, Portuguese, Russian, Arabic, Hindi, Japanese, English, etc.).
- **Dynamic DUB/SUB Options**: When browsing German or other international sources, the player and download sheets dynamically adapt to show appropriate audio and subtitle chips (e.g. "German (SUB)" and "German (DUB)").
- **Language-Agnostic Settings**: Clarified default audio track preferences across Player and Download settings.

### 🧹 Automatic Temp Cleanup & Black Screen Fix (#63)
- **Black Screen Prevention**: Fixed an issue where tapping "View Downloads" from a landscape video player locked orientation in an immersive state, ensuring safe portrait restoration and smooth navigation.
- **Orphaned `.temp_*` Cache Cleaner**: Temporary segment download folders are now cleanly removed upon item deletion, automatically swept at app launch, and can be manually cleared via Download Settings.
- **Export / Share Completed Downloads**: Added an "Export / Share" button directly to completed download cards to easily send video files to external video players, file managers, or messaging apps.

## 🛠️ Verification
- Full test suite: 125/125 tests passed (`flutter test`).
- Split-per-ABI & Universal APK builds verified:
  - `AniDash-v2.1.5-Universal.apk`
  - `AniDash-v2.1.5-arm64-v8a.apk`
  - `AniDash-v2.1.5-armeabi-v7a.apk`
  - `AniDash-v2.1.5-x86_64.apk`

**Version:** 2.1.5 (Build 150)
