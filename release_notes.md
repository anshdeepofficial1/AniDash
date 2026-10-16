# AniDash v1.20.6 — Continue Watching, exact skip timing and stronger buffering

This update keeps the working playback route intact while fixing progress, metadata and long-buffer edge cases.

## Playback and buffering
- Make Android prioritize the configured 120-second time buffer over ExoPlayer's byte-size threshold, preventing high-bitrate streams from stopping near 40–50 seconds.
- Keep the existing player, stream selection and source hand-off behavior unchanged.
- Accept exact late-opening intro markers instead of rejecting every opening that starts after five minutes.
- Re-fetch episode-specific skip timing when the real media duration replaces an early provisional duration.

## Continue Watching
- Keep a fresh partially watched local episode authoritative when tracker synchronization is temporarily one episode ahead.
- Do not remove Continue Watching history when an unrelated snackbar or route change dismisses the removal prompt.
- Advance only inside the final 90 seconds, and keep completed one-shot movies out of Continue Watching without inventing Episode 2.

## Movies, franchises and manga
- Show movie runtime in details metadata, including Kaiju No. 8: Mission Recon.
- Expand the franchise selector to include movies, specials, OVAs, ONAs and side stories in release order alongside seasons.
- Add a related-manga action when AniList supplies a source/adaptation relation.
- Prefer Comick, then MangaSee and MangaDex for new default manga-source selection while preserving an existing user choice.

## Validation
- Targeted Dart analysis completed with no issues.
- Continue Watching, buffer policy, HLS relay, stream headers, downloads and AnyCore policy regression suites all pass.
- Android release signing and all APK variants are built by the protected GitHub release workflow.

**Version:** 1.20.6 (139)
