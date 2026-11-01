# AniDash Watch source integration

This document records the current web-player contract before connecting additional providers.

## Existing architecture

- Anime catalogue, search, synopsis, artwork, genres, scores and episode counts come from the AniList GraphQL API in `app.js`.
- The current metadata object uses an **AniList media ID** (`Media.id`).
- Episode and stream lookup currently goes through `/api/anidash`.
- The player accepts browser-playable HTTPS HLS playlists (`.m3u8`) and MP4 files. HLS uses native playback where supported (notably Safari) and hls.js where Media Source Extensions are available.
- Watch history and Continue Watching are currently stored in browser-local storage. That is device-local, not account sync.

## Important ID mapping issue

The current web UI sends the AniList media ID as the `id` to the episode/source endpoint. A content provider normally has its own catalogue ID; those ID namespaces must **not** be assumed to match.

Before a provider is enabled, implement an explicit mapping step:

1. Resolve the AniList title to a provider title using a provider search endpoint or a verified mapping table.
2. Store the provider's own title ID separately from the AniList ID.
3. Use the provider ID for episode and stream lookup.
4. Keep AniList IDs for metadata, watch-list references and cross-device library identity.

A title match should consider English, romaji and native titles, aliases, release year and format. Ambiguous matches should be shown to the user rather than silently selecting the wrong series.

## Player response contract

The existing player expects a source resolver response shaped like this:

```json
{
  "sources": [
    {
      "url": "https://media.example.com/episode/master.m3u8",
      "quality": "Auto",
      "server": "Licensed provider",
      "isM3U8": true,
      "isDub": false
    }
  ],
  "subtitles": [
    {
      "url": "https://media.example.com/subtitles/en.vtt",
      "lang": "en",
      "label": "English",
      "kind": "subtitles"
    }
  ],
  "intro": null,
  "outro": null
}
```

Supported browser media paths:

- HLS: HTTPS `.m3u8` playlist; nested playlists, segments and keys must remain reachable.
- MP4: HTTPS media URL with correct byte-range support for seeking.
- Subtitles: WebVTT or another format the browser player can render after conversion where needed.

DRM-protected streams, native Android extension packages and provider-specific apps do not automatically work in Safari/PWA. Those need an official web SDK/player or a provider-authorised browser embed.

## Security and rights requirements

- Connect only sources that AniDash is authorised to access and display.
- Keep provider credentials and private API keys on the server; never ship them in `app.js` or a public JSON file.
- Validate provider response URLs and use a strict HTTPS host allowlist for any server-side media proxy.
- Do not accept arbitrary proxy URLs from visitors. Validate redirects, range requests, response size and content type.
- Respect each provider's terms, geographic restrictions and content licences.

## Cross-device roadmap

The current web app's local progress is useful for guests but does not sync. A production multi-device experience needs authentication plus a database record keyed by user ID, AniList media ID, episode number and updated timestamp. Progress writes should be debounced and conflict-resolved by the latest valid playback position. Native AniDash clients can later use the same account API.

## What is needed to finish provider integration

For each source, collect its official API/SDK documentation or an authorised sample response for: title search, title ID, episode list, stream resolution, audio languages, subtitle tracks, authentication requirements, allowed playback domains and licensing/usage terms. Do not send private account passwords or long-lived secrets in chat.
