const STREAM_PROXY = 'https://neko.justanime.to/m3u8-proxy';

const ALLOWED_HOSTS = [
  'neko.justanime.to',
  'nexabloom.top',
  'give6beforegtav.site',
];

const allowed = host =>
  ALLOWED_HOSTS.some(domain => host === domain || host.endsWith('.' + domain));

function headersFor(target, req) {
  const isJustAnimeProxy =
    target.hostname === 'neko.justanime.to' ||
    target.hostname.endsWith('.justanime.to');

  const headers = {
    Origin: isJustAnimeProxy ? 'https://justanime.to' : 'https://megaplay.buzz',
    Referer: isJustAnimeProxy ? 'https://justanime.to/' : 'https://megaplay.buzz/',
    'User-Agent': req.headers['user-agent'] || 'Mozilla/5.0 AniDash-PWA',
    Accept: '*/*',
  };
  if (req.headers.range) headers.Range = req.headers.range;
  return headers;
}

function proxyContext(target) {
  try {
    if (
      target.hostname === 'neko.justanime.to' &&
      target.pathname.includes('m3u8-proxy')
    ) {
      const rawUrl = target.searchParams.get('url');
      const rawHeaders = target.searchParams.get('headers') || '{}';
      const original = rawUrl ? new URL(rawUrl) : null;
      return {
        original,
        headersJson: rawHeaders,
      };
    }
  } catch (_) {}
  return {
    original: null,
    headersJson: '{}',
  };
}

function externalProxyUrl(url, headersJson) {
  return (
    STREAM_PROXY +
    '?url=' +
    encodeURIComponent(url) +
    '&headers=' +
    encodeURIComponent(headersJson || '{}')
  );
}

function sameOriginProxy(url, headersJson, isHls) {
  let upstream = url;
  try {
    const parsed = new URL(url);
    const alreadyProxy =
      parsed.hostname === 'neko.justanime.to' &&
      parsed.pathname.includes('m3u8-proxy');
    if (!alreadyProxy) upstream = externalProxyUrl(url, headersJson);
  } catch (_) {
    upstream = externalProxyUrl(url, headersJson);
  }

  return (
    '/api/media?url=' +
    encodeURIComponent(upstream) +
    '&hls=' +
    (isHls ? '1' : '0')
  );
}

function rewriteUriAttributes(line, baseUrl, headersJson) {
  const upper = line.trim().toUpperCase();
  const playlistUri =
    upper.startsWith('#EXT-X-MEDIA:') ||
    upper.startsWith('#EXT-X-I-FRAME-STREAM-INF:');

  const binaryUri =
    upper.startsWith('#EXT-X-KEY:') ||
    upper.startsWith('#EXT-X-SESSION-KEY:') ||
    upper.startsWith('#EXT-X-MAP:');

  if (!playlistUri && !binaryUri) return line;

  return line.replace(/URI="([^"]+)"/g, (_, uri) => {
    const absolute = new URL(uri, baseUrl).toString();
    return (
      'URI="' +
      sameOriginProxy(absolute, headersJson, playlistUri) +
      '"'
    );
  });
}

function rewritePlaylist(playlist, target) {
  const context = proxyContext(target);
  const baseUrl = context.original || target;
  const headersJson = context.headersJson;

  let nextLineIsPlaylist = false;

  return playlist
    .split('\n')
    .map(line => {
      const value = line.trim();
      if (!value) return line;

      if (value.startsWith('#')) {
        const upper = value.toUpperCase();
        const rewritten = rewriteUriAttributes(line, baseUrl, headersJson);
        nextLineIsPlaylist = upper.startsWith('#EXT-X-STREAM-INF');
        return rewritten;
      }

      const absolute = new URL(value, baseUrl).toString();
      const isPlaylist =
        nextLineIsPlaylist || /\.m3u8(?:$|\?)/i.test(absolute);
      nextLineIsPlaylist = false;
      return sameOriginProxy(absolute, headersJson, isPlaylist);
    })
    .join('\n');
}

async function streamBody(upstream, res) {
  if (!upstream.body) return res.end();
  try {
    const { Readable } = await import('node:stream');
    Readable.fromWeb(upstream.body).pipe(res);
  } catch (_) {
    const buffer = Buffer.from(await upstream.arrayBuffer());
    res.end(buffer);
  }
}

export default async function handler(req, res) {
  try {
    const target = new URL(req.query.url || '');
    if (target.protocol !== 'https:' || !allowed(target.hostname)) {
      return res.status(403).json({ error: 'Media host is not allowed' });
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 25000);

    const upstream = await fetch(target, {
      signal: controller.signal,
      headers: headersFor(target, req),
    }).finally(() => clearTimeout(timer));

    if (!upstream.ok && upstream.status !== 206) {
      return res.status(upstream.status).end();
    }

    const type = upstream.headers.get('content-type') || '';
    const looksLikeHls =
      req.query.hls === '1' ||
      type.toLowerCase().includes('mpegurl') ||
      (() => {
        const ctx = proxyContext(target);
        return !!ctx.original && /\.m3u8(?:$|\?)/i.test(ctx.original.toString());
      })();

    if (looksLikeHls) {
      const playlist = await upstream.text();
      if (!playlist.trim().startsWith('#EXTM3U')) {
        return res.status(502).json({
          error: 'Stream proxy did not return a valid HLS playlist',
        });
      }

      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
      res.setHeader('Cache-Control', 'public, max-age=5, s-maxage=5');
      return res.status(200).send(rewritePlaylist(playlist, target));
    }

    for (const name of [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
      'etag',
      'last-modified',
    ]) {
      const value = upstream.headers.get(name);
      if (value) res.setHeader(name, value);
    }

    res.setHeader('Cache-Control', 'public, max-age=1800');
    res.status(upstream.status);
    return streamBody(upstream, res);
  } catch (error) {
    if (error?.name === 'AbortError') {
      return res.status(504).json({ error: 'Media source timed out' });
    }
    return res.status(400).json({ error: 'Invalid media request' });
  }
}
