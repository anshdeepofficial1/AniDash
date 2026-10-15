# AniDash v1.20.2 — Playback stability, extension repositories and AniCORE

This update prioritizes preserving the stable v1.20.1 player and fixing source selection, downloads and extension management.

## Playback and downloads
- Keep the explicitly selected JustAnime, HiAnime or installed extension authoritative throughout episode matching and playback. No silent provider replacement.
- Retain v1.20.1's direct MPV streaming path, audio synchronization, 100-second ahead readahead policy, intro/outro and recap skipping.
- Make the authenticated on-device HLS relay an explicit Retry fallback instead of forcing it on streams that already play successfully.
- Reject missing or malformed episode download URLs before queueing, and do not silently substitute SUB for an unavailable English DUB.

## Extensions and backups
- Group Anime and Manga extension catalogs by their original JSON repository in the hamburger navigation, with clear catalog names.
- Prevent duplicate sources during updates and refresh, validate repository loading, and make pull-to-refresh functional.
- Preserve engine/source selection and include JSON repository lists and MangaYomi extension identities in backup/restore. Android APK-based AniYomi extensions still require Android's installer approval.

## AniCORE and app experience
- Add phone-default or user-selected microphone languages and stop stale transcription events from restoring sent text.
- Add Edit and resend / Resend for user messages, and restore interrupted chat requests after leaving and reopening the chat.
- Replace the old sparkle emblem with an original animated, theme-colored CoreBall.
- Improve Recents task clean-up after the in-app APK installer relaunches AniDash.
- Apply recent-app privacy protection independently of screenshot protection.

## Validation
- Flutter static analysis and focused player, HLS, source-header, AI-routing and download tests are run in GitHub Actions.
- Playback performance still depends on the selected upstream streaming provider, phone hardware and network conditions. No fixed buffering time is guaranteed.

**Version:** 1.20.2 (135)
