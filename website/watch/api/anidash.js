const API = 'https://core.justanime.to/api';
const STREAM_PROXY = 'https://neko.justanime.to/m3u8-proxy';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) ' +
  'Chrome/122.0.0.0 Safari/537.36';

const BASE_HEADERS = {
  Origin: 'https://justanime.to',
  Referer: 'https://justanime.to/',
  'User-Agent': UA,
  Accept: 'application/json, text/plain, */*',
};

const SERVER_ORDER = [
  {
    id: 'megaplay',
    name: 'Momo',
    type: 'hls',
    referer: 'https://megaplay.buzz/',
    path: (id, episode) => '/watch/' + id + '/episode/' + episode + '/megaplay',
  },
  {
    id: 'zokoanime',
    name: 'Zoko',
    type: 'hls',
    referer: 'https://zokoanime.video/',
    path: (id, episode) => '/watch/' + id + '/episode/' + episode + '/zokoanime',
  },
  {
    id: 'animegg',
    name: 'Gigi',
    type: 'mp4',
    referer: 'https://www.animegg.org/',
    path: (id, episode) => '/watch/' + id + '/episode/' + episode + '/animegg',
  },
  {
    id: 'anineko',
    name: 'Neko',
    type: 'hls',
    referer: 'https://justanime.to/',
    path: (id, episode, audio) =>
      '/watch/' + id + '/episode/' + episode + '/anineko/' + audio,
  },
];

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

function normalizeHeaders(input) {
  const out = {};
  if (!input || typeof input !== 'object') return out;

  for (const [rawKey, rawValue] of Object.entries(input)) {
    const key = String(rawKey || '').trim();
    const value = String(rawValue || '').trim();
    if (!key || !value) continue;

    const lower = key.toLowerCase();
    const canonical =
      lower === 'user-agent'
        ? 'User-Agent'
        : lower === 'referer' || lower === 'referrer'
        ? 'Referer'
        : lower === 'origin'
        ? 'Origin'
        : lower === 'cookie'
        ? 'Cookie'
        : key;

    for (const existing of Object.keys(out)) {
      if (existing.toLowerCase() === canonical.toLowerCase()) delete out[existing];
    }
    out[canonical] = value;
  }
  return out;
}

function externalProxyUrl(url, headers) {
  return (
    STREAM_PROXY +
    '?url=' +
    encodeURIComponent(url) +
    '&headers=' +
    encodeURIComponent(JSON.stringify(headers))
  );
}

function browserProxyUrl(url, headers, isM3U8) {
  const proxy = externalProxyUrl(url, headers);
  return (
    '/api/media?url=' +
    encodeURIComponent(proxy) +
    '&hls=' +
    (isM3U8 ? '1' : '0')
  );
}

function parseServerPayload(server, endpoint, payload, requestedAudio) {
  if (!payload || typeof payload !== 'object') return null;

  let raw = null;
  let actualAudio = requestedAudio;

  if (
    Object.prototype.hasOwnProperty.call(payload, 'sub') ||
    Object.prototype.hasOwnProperty.call(payload, 'dub')
  ) {
    if (requestedAudio === 'dub') {
      raw = payload.dub;
      if (!raw || !Array.isArray(raw.sources) || !raw.sources.length) return null;
      actualAudio = 'dub';
    } else {
      raw = payload.sub || payload.hsub;
      if (!raw || !Array.isArray(raw.sources) || !raw.sources.length) return null;
      actualAudio = 'sub';
    }
  } else {
    const endpointAudio = endpoint.includes('/dub') ? 'dub' : 'sub';
    if (endpoint.includes('/anineko/') && endpointAudio !== requestedAudio) {
      return null;
    }
    raw = payload;
    actualAudio = endpointAudio;
  }

  if (!raw || !Array.isArray(raw.sources) || !raw.sources.length) return null;

  const rawHeaders = normalizeHeaders(raw.headers || payload.headers || {});
  const commonHeaders = normalizeHeaders({
    'User-Agent': UA,
    Referer: server.referer,
    Origin: server.referer.replace(/\/+$/, ''),
    ...rawHeaders,
  });

  const sources = raw.sources
    .map(source => {
      if (!source || typeof source !== 'object') return null;
      const rawUrl = String(source.url || '').trim();
      if (!/^https:\/\//i.test(rawUrl)) return null;

      const itemHeaders = normalizeHeaders(source.headers || {});
      const playbackHeaders = normalizeHeaders({
        ...commonHeaders,
        ...itemHeaders,
      });

      const isM3U8 =
        server.type === 'hls' ||
        source.isM3U8 === true ||
        /\.m3u8(?:$|\?)/i.test(rawUrl);

      let originalHost = '';
      try {
        originalHost = new URL(rawUrl).hostname;
      } catch (_) {}

      return {
        quality: source.quality || 'Auto',
        type: server.name,
        server: server.name,
        serverId: server.id,
        isM3U8,
        isDub: actualAudio === 'dub',
        originalHost,
        url: browserProxyUrl(rawUrl, playbackHeaders, isM3U8),
      };
    })
    .filter(Boolean);

  if (!sources.length) return null;

  const tracks =
    raw.subtitles ||
    raw.tracks ||
    payload.subtitles ||
    payload.tracks ||
    [];

  return {
    server,
    headers: commonHeaders,
    sources,
    subtitles: Array.isArray(tracks) ? tracks : [],
    intro:
      raw.intro ||
      payload.intro ||
      payload.sub?.intro ||
      payload.dub?.intro ||
      null,
    outro:
      raw.outro ||
      payload.outro ||
      payload.sub?.outro ||
      payload.dub?.outro ||
      null,
  };
}

function orderedServers(preferred) {
  if (!preferred) return SERVER_ORDER;
  const first = SERVER_ORDER.find(server => server.id === preferred);
  if (!first) return SERVER_ORDER;
  return [first, ...SERVER_ORDER.filter(server => server.id !== preferred)];
}

async function resolveStreamingSources(id, episode, audio, preferredServer) {
  const servers = orderedServers(preferredServer);

  const results = await Promise.all(
    servers.map(async server => {
      const endpoint = server.path(id, episode, audio);
      const payload = await fetchJson(endpoint, 12000);
      return parseServerPayload(server, endpoint, payload, audio);
    })
  );

  const valid = results.filter(Boolean);
  if (!valid.length) return null;

  const sources = [];
  const seen = new Set();
  for (const model of valid) {
    for (const source of model.sources) {
      const key =
        source.serverId +
        '|' +
        String(source.quality || '') +
        '|' +
        source.url;
      if (seen.has(key)) continue;
      seen.add(key);
      sources.push(source);
    }
  }

  const first = valid[0];
  const subtitles = [];
  const subtitleSeen = new Set();
  for (const model of valid) {
    for (const track of model.subtitles || []) {
      const url = String(track?.url || track?.file || '').trim();
      if (!url || subtitleSeen.has(url)) continue;
      subtitleSeen.add(url);
      subtitles.push({
        ...track,
        url,
        lang: track?.lang || track?.label || 'English',
      });
    }
  }

  return {
    sources,
    subtitles,
    intro: first.intro,
    outro: first.outro,
    resolvedServer: first.server.id,
    resolvedServers: valid.map(model => model.server.id),
  };
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 's-maxage=30, stale-while-revalidate=120');

  const {
    action,
    query = '',
    id = '',
    episode = '1',
    audio = 'sub',
    page = '1',
    server = '',
  } = req.query;

  if (action === 'search') {
    const data = await fetchJson(
      '/search?query=' +
        encodeURIComponent(query) +
        '&page=' +
        encodeURIComponent(page),
      15000
    );
    return data
      ? res.json(data)
      : res
          .status(502)
          .json({ error: 'The source service is temporarily unavailable' });
  }

  if (action === 'episodes' && /^\d+$/.test(id)) {
    const data = await fetchJson(
      '/anime/' + id + '/episodes?page=' + encodeURIComponent(page),
      15000
    );
    return data
      ? res.json(data)
      : res
          .status(504)
          .json({ error: 'Episode source timed out. Please retry.' });
  }

  if (
    action === 'source' &&
    /^\d+$/.test(id) &&
    /^\d+(\.\d+)?$/.test(episode)
  ) {
    const lang = audio === 'dub' ? 'dub' : 'sub';
    const preferredServer = SERVER_ORDER.some(item => item.id === server)
      ? server
      : '';
    const resolved = await resolveStreamingSources(
      id,
      episode,
      lang,
      preferredServer
    );

    if (!resolved?.sources?.length) {
      return res.status(404).json({
        error:
          lang.toUpperCase() +
          ' stream is unavailable for this episode on all Android servers',
      });
    }
    return res.json(resolved);
  }

  return res.status(400).json({ error: 'Invalid request' });
}
