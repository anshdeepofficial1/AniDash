const API = 'https://core.justanime.to/api';
const STREAM_PROXY = 'https://neko.justanime.to/m3u8-proxy';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const BASE_HEADERS = {
  Origin: 'https://justanime.to',
  Referer: 'https://justanime.to/',
  'User-Agent': UA,
  Accept: 'application/json, text/plain, */*',
};

async function fetchJson(path, timeout = 12000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const upstream = await fetch(API + path, {
      signal: controller.signal,
      headers: BASE_HEADERS,
    });
    const data = await upstream.json().catch(() => null);
    if (!upstream.ok || !data || data.error) return null;
    return data;
  } catch (_) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function selectedPayload(data, audio, server) {
  if (!data || typeof data !== 'object') return null;

  if (Array.isArray(data.sources)) {
    if (server === 'Neko HD' || server === 'Neko' || audio === 'sub') return data;
    const hint = String(
      data.audio || data.language || data.category ||
      data.type || ''
    ).toLowerCase();
    const sourceSaysDub = data.sources.some(source =>
      source?.isDub === true ||
      /\bdub\b/i.test(String(source?.audio || source?.language || source?.type || ''))
    );
    return hint.includes('dub') || sourceSaysDub ? data : null;
  }

  if (audio === 'dub') {
    if (Array.isArray(data.dub?.sources) && data.dub.sources.length) return data.dub;
    return null;
  }
  if (Array.isArray(data.sub?.sources) && data.sub.sources.length) return data.sub;
  if (Array.isArray(data.hsub?.sources) && data.hsub.sources.length) return data.hsub;
  return null;
}

function proxyStream(url, isM3U8) {
  const headers = JSON.stringify({
    'User-Agent': UA,
    Referer: 'https://justanime.to/',
    Origin: 'https://justanime.to',
  });
  const upstreamProxy =
    STREAM_PROXY + '?url=' + encodeURIComponent(url) + '&headers=' + encodeURIComponent(headers);
  return {
    sameOrigin:
      '/api/media?url=' + encodeURIComponent(upstreamProxy) + (isM3U8 ? '&hls=1' : ''),
    direct: upstreamProxy,
  };
}

function normalizeSources(payload, server) {
  return (payload?.sources || [])
    .map(source => {
      const url = source?.url?.toString().trim();
      if (!url || !/^https:\/\//i.test(url)) return null;
      let originalHost = '';
      try { originalHost = new URL(url).hostname; } catch (_) {}
      const isM3U8 =
        source?.isM3U8 === true ||
        /\.m3u8(?:$|\?)/i.test(url) ||
        /mpegurl/i.test(String(source?.type || ''));
      const proxied = proxyStream(url, isM3U8);
      return {
        ...source,
        server,
        originalHost,
        isM3U8,
        url: proxied.sameOrigin,
        directProxyUrl: proxied.direct,
      };
    })
    .filter(Boolean);
}

async function resolveStreamingSources(id, episode, audio) {
  const candidates = [
    { server: 'Neko HD', path: '/watch/' + id + '/episode/' + episode + '/anineko/' + audio + '/hd1' },
    { server: 'Momo', path: '/watch/' + id + '/episode/' + episode + '/megaplay' },
    { server: 'Zoko', path: '/watch/' + id + '/episode/' + episode + '/zokoanime' },
    { server: 'Gigi', path: '/watch/' + id + '/episode/' + episode + '/animegg' },
    { server: 'Neko', path: '/watch/' + id + '/episode/' + episode + '/anineko/' + audio },
  ];

  const settled = await Promise.all(
    candidates.map(async candidate => {
      const data = await fetchJson(candidate.path, 10000);
      const selected = selectedPayload(data, audio, candidate.server);
      if (!selected) return null;
      const sources = normalizeSources(selected, candidate.server);
      if (!sources.length) return null;
      return {
        server: candidate.server,
        data,
        selected,
        sources,
      };
    })
  );

  const valid = settled.filter(Boolean);
  if (!valid.length) return null;

  const seen = new Set();
  const sources = [];
  for (const result of valid) {
    for (const source of result.sources) {
      const key = source.server + '|' + (source.quality || '') + '|' + source.url;
      if (seen.has(key)) continue;
      seen.add(key);
      sources.push(source);
    }
  }

  const first = valid[0];
  return {
    ...first.selected,
    sources,
    subtitles:
      first.selected.subtitles ||
      first.selected.tracks ||
      first.data.subtitles ||
      [],
    intro: first.selected.intro || first.data.intro,
    outro: first.selected.outro || first.data.outro,
    resolvedServers: valid.map(item => item.server),
  };
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 's-maxage=45, stale-while-revalidate=180');
  const {
    action,
    query = '',
    id = '',
    episode = '1',
    audio = 'sub',
    page = '1',
  } = req.query;

  if (action === 'search') {
    const data = await fetchJson(
      '/search?query=' + encodeURIComponent(query) + '&page=' + encodeURIComponent(page),
      15000
    );
    return data
      ? res.json(data)
      : res.status(502).json({ error: 'The source service is temporarily unavailable' });
  }

  if (action === 'episodes' && /^\d+$/.test(id)) {
    const data = await fetchJson(
      '/anime/' + id + '/episodes?page=' + encodeURIComponent(page),
      15000
    );
    return data
      ? res.json(data)
      : res.status(504).json({ error: 'Episode source timed out. Please retry.' });
  }

  if (action === 'source' && /^\d+$/.test(id) && /^\d+(\.\d+)?$/.test(episode)) {
    const lang = audio === 'dub' ? 'dub' : 'sub';
    const resolved = await resolveStreamingSources(id, episode, lang);
    if (!resolved?.sources?.length) {
      return res.status(404).json({
        error: lang.toUpperCase() + ' stream is unavailable for this episode',
      });
    }
    return res.json(resolved);
  }

  return res.status(400).json({ error: 'Invalid request' });
}
