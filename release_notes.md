# AniDash v2.1.1 — Extension Installer Fix, Extended Buffering & UI Polish

AniDash v2.1.1 brings a critical fix for AniYomi external extension installation, alongside all major v2.1.0 playback stability upgrades, 300-second buffering, screen wakelock, and UI refinements.

## 🎬 Playback & Video Player Upgrades
- **Wakelock Screen Sleep Prevention**: Video player now holds an active screen wakelock (`wakelock_plus`) during playback so your screen never dims or goes to sleep while watching.
- **Clean Next-Episode Progress Reset**: Fixed an issue where switching to the next episode would inherit the finished playback position of the previous episode. New episodes now consistently start fresh from 00:00.
- **Deep 300-Second Reservoir & Instant Backward Seek**:
  - Buffer reservoir expanded to 300 seconds (5 minutes) for high-speed connections (`maxBufferMs: 300000`).
  - Added 120-second backward buffer retention (`setBackBuffer(120000, true)` in ExoPlayer) ensuring rewind seeks execute immediately with zero re-buffering lag.
- **Accurate Intro/Outro Skip & Zero Residual Playback**:
  - Automatically identifies and swaps inverted provider markers.
  - Normalizes truncated intervals (70–88s) to full 90-second standard anime TV theme lengths.
  - Skips cleanly to the true end boundary (`ceil()`), completely removing leftover music or trailing frames.
- **Reliable Skip Intro / Skip Outro Floating Buttons**:
  - Appears for 2 seconds upon entering any intro/outro interval, regardless of whether auto-skip is enabled or disabled.
  - Synchronizes seamlessly with player controls visibility.
- **30-Second Next Episode Prompt**:
  - Triggers reliably within the final 30 seconds of an episode or during the detected outro, displaying for 2 seconds and toggling with player controls.

## 🎨 Seekbar & UI Improvements
- **Clean Seekbar Outro Labeling**: Eliminated floating top badges over short seekbar segments. Segments wider than 34px render clean inner text; smaller segments show only the colored interval without visual clutter.
- **Refined Navigation Bar**: Bottom navigation bar now features a frosted translucent surface with 24px blur and a subtle neutral outline.
- **Streamlined Home Screen**: Removed the redundant "Trending 25" header pill, smoothly moving trending posters up for a cleaner layout.
- **Compact Download Menu (Issue #40)**: Revamped the download source selector modal with a compact layout, cleaner category chips, and a frosted blur backdrop.

## 📥 Download Manager Fixes
- **Real-Time Download Size Display (Issue #37)**: Download cards now display real-time progress (`Downloaded / Total MB • Speed • ETA`) during active downloading and resuming.
- **Automatic Temp File Cleanup (Issue #39)**: HLS download temporary directories are automatically purged on failure or cancellation, and any orphaned `.temp_*` folders are wiped on app launch.

## 🧩 Extension System Fixes (Issue #36)
- **AniYomi Extension Installer Fix**: Resolved an issue where AniYomi extensions from third-party repositories failed to install with a SHA-256 validation error. The installer now gracefully accepts standard community repository indexes, ensures fallback APK URL resolution, and safely retains downloaded APKs during the Android PackageInstaller confirmation handoff.

## 🛠️ Verification
- Static analysis verified: 0 errors, 0 warnings (`dart analyze lib/`).
- Full test suite verified: 113 tests passed (`flutter test`).

**Version:** 2.1.1 (Build 146)
