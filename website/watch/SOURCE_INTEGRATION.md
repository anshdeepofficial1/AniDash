# AniDash Watch — source and integration notes

## Application structure

AniDash Watch is a from-scratch responsive web app served at `/watch`. It uses plain HTML, CSS and JavaScript to keep the deploy lightweight and avoid a separate build pipeline.

- `index.html`: app shell, navigation and PWA metadata.
- `styles.css`: responsive desktop, tablet and mobile layouts.
- `app.js`: AniList discovery, detail pages, provider matching, episode navigation, video playback, library and local progress.
- `manifest.webmanifest` / `sw.js`: installable PWA shell.
- `vendor/hls-1.6.13.min.js`: HLS playback library used where Media Source Extensions are available.

## Data flow

1. AniList GraphQL supplies the anime's metadata, cover art, banner, genres, rating, season, synopsis, episode count and optional MyAnimeList cross-reference (`idMal`).
2. When the user opens a title's episode panel, AniDash searches the connected source catalogue by English, romaji and native titles/aliases.
3. The returned numeric provider ID is stored separately from the AniList ID. This is essential: the two ID systems are not interchangeable.
4. `/api/anidash?action=episodes&id=PROVIDER_ID&page=1` returns available episodes.
5. `/api/anidash?action=source&id=PROVIDER_ID&episode=N&audio=sub|dub` resolves browser-playable media.
6. The existing root `/api/media` handler transports the media URL according to its host and redirect validation rules.

## Compatibility

The player supports HLS playlists through hls.js or native Safari HLS, plus browser-playable MP4 files. Subtitle tracks are attached when a provider returns compatible tracks. DRM-only streams, Android extension APKs, and providers requiring a native SDK do not automatically work in browsers.

## User data

Watchlist and watch progress are stored locally in the current browser profile. This release does not provide cloud account synchronization; browser-local data is not shared automatically between an iPhone and a desktop. An account/database sync layer can be added without changing the AniList/provider ID separation.

## Provider requirements

A provider must offer title search, provider IDs, episode listing and a browser-compatible stream response. Provider credentials must remain server-side. Only connect sources that are authorised for the intended use and respect each source's licences, content rights, geographic restrictions and terms. Do not expose private keys in client JavaScript.
