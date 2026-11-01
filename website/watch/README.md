# AniDash Watch

A fresh, responsive anime discovery and streaming PWA inside the AniDash repository.

## Local development

Run the existing website project from the `website/` directory with Vercel dev so that `/api/anidash` and `/api/media` are available:

```bash
cd website
vercel dev
```

The web app is served at `/watch`.

## Current integrations

- AniList GraphQL supplies anime metadata, artwork, search, genre, season and ranking data. The `idMal` field is retained as a MyAnimeList cross-reference where available.
- The existing root website handlers are reused: `/api/anidash` for provider search, episode lookup and stream resolution; `/api/media` for the existing media transport/proxy contract.
- Provider lookup is performed by title and aliases. AniList IDs and provider catalogue IDs are different namespaces; AniDash persists the resolved provider ID separately and never assumes they are interchangeable.
- HLS playback uses the bundled hls.js build where Media Source Extensions are available and native HLS on Safari. Direct MP4 playback is also supported.
- Watchlist and progress are saved locally for guests. This version does not claim to provide cloud account sync.

## Player compatibility

The browser must be allowed to play the media format returned by a provider. DRM-only streams, native Android extension APKs, and providers that require a native SDK are not automatically web-compatible. Sources must be authorised for the intended use and should expose browser-compatible playback.

## Add another provider

Keep metadata identity (AniList ID and optional MAL ID) separate from provider identity. A provider adapter must offer title search, provider ID, episode listing and a browser-playable source response compatible with the existing player shape.

Do not put private tokens in client JavaScript. Keep credentials server-side, validate media hosts and redirects, and respect each provider's licence and terms.
