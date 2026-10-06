const ALLOWED_HOSTS = [
  'neko.justanime.to',
  'nexabloom.top',
  'give6beforegtav.site',
];

const allowed = host =>
  ALLOWED_HOSTS.some(domain => host === domain || host.endsWith('.' + domain));

const proxyUrl = target => '/api/media?url=' + encodeURIComponent(target);

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

function rewritePlaylist(playlist, baseUrl) {
  return playlist
    .split('\n')
    .map(line => {
      const value = line.trim();
      if (!value) return line;

      if (value.startsWith('#')) {
        return line.replace(/URI="([^"]+)"/g, (_, uri) => {
          const absolute = new URL(uri, baseUrl).toString();
          return 'URI="' + proxyUrl(absolute) + '"';
        });
      }

      const absolute = new URL(value, baseUrl).toString();
      return proxyUrl(absolute);
    })
    .join('\n');
}

export default async function handler(req, res) {
  try {
    const target = new URL(req.query.url || '');
    if (target.protocol !== 'https:' || !allowed(target.hostname)) {
      return res.status(403).json({ error: 'Media host is not allowed' });
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    const upstream = await fetch(target, {
      signal: controller.signal,
      headers: headersFor(target, req),
    }).finally(() => clearTimeout(timer));

    if (!upstream.ok && upstream.status !== 206) {
      return res.status(upstream.status).end();
    }

    const type = upstream.headers.get('content-type') || '';
    const looksLikeHls =
      type.toLowerCase().includes('mpegurl') ||
      target.pathname.toLowerCase().endsWith('.m3u8') ||
      target.pathname.includes('m3u8-proxy');

    if (looksLikeHls) {
      const playlist = await upstream.text();
      if (!playlist.trim().startsWith('#EXTM3U')) {
        res.setHeader('Content-Type', type || 'text/plain; charset=utf-8');
        return res.status(502).send(playlist.slice(0, 1000));
      }
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
      res.setHeader('Cache-Control', 'public, max-age=8, s-maxage=8');
      return res.status(200).send(rewritePlaylist(playlist, target));
    }

    for (const name of [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      const value = upstream.headers.get(name);
      if (value) res.setHeader(name, value);
    }

    res.setHeader('Cache-Control', 'public, max-age=1800');
    const buffer = Buffer.from(await upstream.arrayBuffer());
    return res.status(upstream.status).send(buffer);
  } catch (error) {
    if (error?.name === 'AbortError') {
      return res.status(504).json({ error: 'Media source timed out' });
    }
    return res.status(400).json({ error: 'Invalid media request' });
  }
}
