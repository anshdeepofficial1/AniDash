# AniDash Watch Web

A standalone, responsive anime discovery and streaming PWA. This folder is deliberately separate from `website/`; the existing AniDash download website is not changed by this project.

## Included in this first build

- AniList-powered anime discovery, search, rankings, detailed metadata, artwork, genres, airing status and mapped MAL ID links.
- Local watchlist and continue-watching history.
- Episode lists supplied by a configured provider, with catalogue episode-number fallback.
- JSON provider adapters for search, episode discovery, SUB/DUB server lists and stream resolution.
- MP4 and HLS playback, native HLS on Safari/iPhone and hls.js on supported browsers.
- Subtitle tracks, source/quality selection, next/previous episode controls, playback resume and skip-intro/outro metadata.
- Installable PWA shell and responsive phone/tablet/desktop layouts.

## Deploy as the separate Watch project

In the existing Vercel project for the Watch domain, set **Root Directory** to `watch-web`, keep the framework preset as **Other**, and leave build command/output directory empty. Do not change the download site's Vercel project or its root directory (`website`).

## Catalogue

The app calls the public AniList GraphQL API for catalogue data. AniList records include a MyAnimeList ID when mapped; the detail page links to the relevant MAL entry. AniList provides metadata, not video streams.

## Connect streaming sources

This build does not assume a catalogue provider is also a video provider. Connect sources you own or are authorised to use.

1. Copy `sources.example.json` to `sources.json`.
2. Add each source's HTTPS API base URL and endpoint templates.
3. The search endpoint should return an array in `results`, `items`, `list`, or `data`. Each result should contain `id`/`animeId`/`url` and `title`/`name`; optional artwork may use `image`, `cover`, or `poster`.
4. The episodes endpoint should return an `episodes` array. Each item should contain `id` and `number`, and optionally `title`, `thumbnail`, `date`, and `isFiller`.
5. The streams endpoint should return `sources` and optionally `servers`, `subtitles`/`tracks`, `intro`, and `outro`.

Endpoint templates support `{query}`, `{page}`, `{id}`, `{anilistId}`, `{malId}`, `{episodeId}`, `{episode}`, `{server}`, and `{category}`.

Example stream response:

```json
{
  "servers": [{"id":"main","name":"Main","isDub":false},{"id":"dub","name":"English Dub","isDub":true}],
  "sources": [{"url":"https://media.example/episode.m3u8","quality":"1080p","type":"hls","isM3U8":true,"isDub":false,"headers":{}}],
  "tracks": [{"url":"https://media.example/subtitles/en.vtt","lang":"English","type":"subtitles"}],
  "intro": {"start":80,"end":165},
  "outro": {"start":1320,"end":1440}
}
```

A browser cannot attach arbitrary Origin/Referer headers to a media element. If your authorised provider requires custom headers or has CORS restrictions, expose a server-side relay under your own domain and restrict it to explicit upstream hosts and paths. Do not use an open proxy.

You may paste a JSON provider manifest under Settings → Sources; that override is stored only in that browser. Editing the deployed `sources.json` is how you configure providers for all visitors.

## iPhone installation

Open the deployed site in Safari, tap Share, choose **Add to Home Screen**, then Add. The PWA shell can open offline, but catalogue requests and video streaming still require an internet connection.

## Local testing

```bash
cd watch-web
python -m http.server 8080
```

Then open `http://localhost:8080`.

## Limits of this initial build

Provider-specific API adapters have not yet been wired because the exact source URLs/contracts have not been supplied for this web build. Watchlist and playback progress are browser-local in this version; cross-device AniList/MAL account sync is not yet enabled.
