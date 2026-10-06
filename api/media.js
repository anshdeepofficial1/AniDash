const ALLOWED_HOSTS = ['nexabloom.top', 'give6beforegtav.site'];
const allowed = host => ALLOWED_HOSTS.some(domain => host === domain || host.endsWith(`.${domain}`));
const proxyUrl = target => `/api/media?url=${encodeURIComponent(target)}`;

function rewritePlaylist(playlist, baseUrl) {
  return playlist.split('\n').map(line => {
    const value = line.trim();
    if (!value) return line;

    // Media playlists can hide URLs inside URI="..." attributes (keys,
    // init maps, alternate renditions). Rewrite those as well as normal
    // segment / child-playlist lines so Safari and HLS.js stay same-origin.
    if (value.startsWith('#')) {
      return line.replace(/URI="([^"]+)"/g, (_, uri) => {
        const absolute = new URL(uri, baseUrl).toString();
        return `URI="${proxyUrl(absolute)}"`;
      });
    }

    const absolute = new URL(value, baseUrl).toString();
    return proxyUrl(absolute);
  }).join('\n');
}

export default async function handler(req, res) {
  try {
    const target = new URL(req.query.url || '');
    if (target.protocol !== 'https:' || !allowed(target.hostname)) {
      return res.status(403).json({ error: 'Media host is not allowed' });
    }

    const headers = {
      Origin: 'https://megaplay.buzz',
      Referer: 'https://megaplay.buzz/',
      'User-Agent': req.headers['user-agent'] || 'Mozilla/5.0 AniDash-PWA',
    };
    if (req.headers.range) headers.Range = req.headers.range;

    const upstream = await fetch(target, { headers });
    if (!upstream.ok && upstream.status !== 206) {
      return res.status(upstream.status).end();
    }

    const type = upstream.headers.get('content-type') || '';
    if (type.includes('mpegurl') || target.pathname.endsWith('.m3u8')) {
      const playlist = await upstream.text();
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
      res.setHeader('Cache-Control', 'public, max-age=10');
      return res.status(200).send(rewritePlaylist(playlist, target));
    }

    for (const name of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
      const value = upstream.headers.get(name);
      if (value) res.setHeader(name, value);
    }
    res.setHeader('Cache-Control', 'public, max-age=3600');
    const buffer = Buffer.from(await upstream.arrayBuffer());
    return res.status(upstream.status).send(buffer);
  } catch (_) {
    return res.status(400).json({ error: 'Invalid media request' });
  }
}
