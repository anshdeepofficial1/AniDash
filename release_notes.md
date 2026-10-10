# AniDash v1.19.3 — Windows Desktop Quality & Playback Reliability

This release focuses on making AniDash feel native and dependable on Windows while preserving the familiar poster artwork and mobile experience.

## What's New & Fixed

- **Desktop-first interface polish**
  - Refined the Windows navigation rail, spacing, hover states, page widths, and settings layout.
  - Removed duplicate settings headers and eliminated clipped cards in Home, Browse, and Manga sections.
  - Desktop spotlight sections now use the available window width cleanly while poster artwork keeps its original portrait ratio.

- **Reliable source selection, auto-failover, and playback**
  - The selected native provider or extension is now respected throughout server and stream resolution.
  - Automatic seamless failover to alternative pre-installed native providers (HiAnime, AniKoto, JustAnime) if the active source times out or fails.
  - Provider-specific caches prevent stale JustAnime results from appearing after the user changes source.
  - Eliminated the startup volume overlay flicker when opening the video player.
  - Improved request invalidation, playback controls, and PiP background streaming stability.

- **Cross-device watch progress synchronization (Android ⇄ Windows ⇄ macOS)**
  - Seamlessly syncs exact episode numbers and second-level timestamps across devices via tracker notes.
  - Automatically restores exact progress into 'Continue Watching' and local history upon opening the app on any platform.

- **Responsive player UI & dedicated episode actions**
  - Redesigned player side sheet into an ergonomic modal bottom sheet on mobile portrait mode and clamped drawer on landscape/desktop.
  - Separated video player stream settings from portrait episode actions (mark watched/unwatched, jump to timestamp, share episode, synopsis, cache clear).

- **Safer updates and local data**
  - Windows downloads now receive SHA-256 verification when a checksum is supplied.
  - Downloads can be cancelled cleanly from the update dialog.
  - A temporary Hive open failure no longer deletes the user's stored data.

- **Authentication and security hardening**
  - AniList desktop OAuth now validates a cryptographically random state value.
  - Removed the embedded AniList client-secret fallback; release credentials are injected at build time.

- **Maintenance and compatibility**
  - Updated deprecated Flutter APIs and resolved all analyzer findings.
  - Unified Windows installer identity to preserve upgrades across versions.
  - Improved asynchronous file logging and fixed duplicate movie metadata labels.

**Version:** 1.19.3 (127)
