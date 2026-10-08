# AniDash v1.19.2 — Desktop Window Controls, Zero-Lag Playback & Cross-Device Sync ✨

This release brings universal window controls, high-performance zero-lag desktop playback, instant pause responsiveness, and seamless cross-device watch progress synchronization between mobile and PC.

## What's New & Fixed

- 🖥️ **Universal Desktop Window Controls:**
  - Dedicated **Minimize (—)**, **Maximize/Restore (□)**, and **Close (✕)** caption buttons now appear across every single screen in AniDash on macOS, Windows, and Linux.
  - Available across Home, Browse, Manga, Downloads, Library, Details, History, Notifications, Extensions, Settings, and Video Player.
  - Drag anywhere on the top bar to move the window; double-click empty space to toggle Maximize/Restore.

- ⚡ **Zero-Lag Video Playback (Eliminated Rebuild Spam):**
  - Completely decoupled continuous playback position stream ticks from video player widget tree rebuilds.
  - Eliminated high-frequency UI stutter, dropped frames, and input latency. Video now plays at silky-smooth 60/120 FPS.

- ⏯️ **Instant Pause Responsiveness & Bottom Bar Controls:**
  - The Play/Pause button in Center Controls is now permanently visible and interactive—it no longer disappears during background MPV buffer caching.
  - Added dedicated Play/Pause and Next Episode action buttons directly on the bottom controls bar.
  - Direct bottom toolbar access for Subtitles, Quality/Sources, and Episodes list on laptops and desktops.

- 🔄 **Flawless Mobile ➔ PC Cross-Device Watch Sync:**
  - Fixed an issue where unfinished local sessions on PC prevented newly watched episodes from mobile (AniList/MAL) from advancing.
  - Watching ahead on mobile automatically completes prior episodes on PC and sets Continue Watching to the next up episode.

- 🎮 **Desktop Player Parity (YouTube / Crunchyroll Standard):**
  - Single-click anywhere on the video toggles **Play / Pause**.
  - Double-click anywhere on the video toggles **Fullscreen**.
  - Smooth hover reveals controls without stutter.
  - Keyboard shortcuts: `Space`/`K` (Play/Pause), `Left`/`Right` (10s Seek), `Up`/`Down` (Volume), `F`/`F11` (Fullscreen), `Esc` (Exit Fullscreen/Minimize).

- 🚀 **Faster Details & Episodes Fetching:**
  - Parallelized anime metadata and episode provider queries so details load noticeably faster.

- 📱 **Mobile Touch Gestures Preserved:**
  - Android and iOS touch swipe gestures (vertical brightness/volume, horizontal swipe seek) remain 100% intact and untouched.

**Version:** 1.19.2 (126)
