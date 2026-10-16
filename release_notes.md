# AniDash v1.20.5 — Reliable progress, notifications and cleaner playback controls

This release focuses on preserving stable playback while correcting progress, notification and player-interface edge cases.

## Playback and progress
- Keep a 120-second streaming buffer target while retaining a short startup threshold.
- Prevent the previous episode frame from appearing while a different episode or anime opens.
- Prevent a completed episode's final position from leaking into the next episode during transitions.
- Keep partially watched episodes on the current episode until playback reaches the final 90 seconds.
- Sync only fully completed episode counts to AniList and MyAnimeList while preserving exact local playback position.

## Player interface
- Simplify the player menu by removing duplicate Share, Content Source and Source entries.
- Present quality choices as clear resolution labels such as Auto, 1080p and 720p.
- Keep server selection and playback preferences organized without changing the playback engine.

## Episodes and library
- Do not request episode data for unreleased anime; show a clear availability message instead.
- Remove the extra Your Library sorting control and retain the library's established order.
- Correct the Skypiea arc label and keep long-series grouping consistent.

## Notifications
- Remove the former 12-episode release restriction. Enabled SUB and DUB alerts now follow active and planned anime regardless of how far behind the viewer is.
- Keep completed and dropped titles excluded from release alerts.
- Make Continue Watching reminders depend on real playback activity instead of tracker refresh timestamps.
- Keep News, SUB, DUB, Continue Watching and Download notification switches independent.

## Interface polish
- Improve dark-mode navigation blur, translucency and outline contrast.

## Validation
- All 103 Flutter tests pass.
- Flutter static analysis reports no issues.

**Version:** 1.20.5 (138)
