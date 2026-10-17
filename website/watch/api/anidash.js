/**
 * AniDash anime metadata + stream resolver.
 *
 * Talks to the upstream catalogue API (search / episode lists) and resolves a
 * playable stream for a given episode across several source servers.
 *
 * Every resolved URL is handed back as a same-origin `/api/media?...` link so
 * the browser never has to talk to a content CDN directly (browsers cannot
 * send the Referer / User-Agent these CDNs require, and the page must stay
 * CORS-clean).
 *
 * NOTE: an older implementation proxied every URL through
 * `https://neko.justanime.to/m3u8-proxy`. That hostname no longer has a DNS
 * record, which is what silently broke playback. The proxy is gone: we now
 * point `/api/media` straight at the content host and forward only the
 * whitelisted headers.
 */

const API = 'https://core.justanime.to/api';
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

const REQUEST_TIMEOUT_MS = 12000;
const SEARCH_TIMEOUT_MS = 15000;
/** After the fastest server answers, wait this long for the others to join in. */
const GRACE_PERIOD_MS = 750;

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

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function fetchJson(path, timeout = REQUEST_TIMEOUT_MS, signal) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  const onAbort = () => controller.abort();
  if (signal) {
    if (signal.aborted) controller.abort();
    else signal.addEventListener('abort', onAbort, { once: true });
  }

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
    if (signal) signal.removeEventListener('abort', onAbort);
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
    // Never forward credentials through the public media proxy.
    if (lower === 'cookie' || lower === 'authorization' || lower === 'host') continue;
    if (value.length > 512 || /[\r\n]/.test(value)) continue;

    const canonical =
      lower === 'user-agent'
        ? 'User-Agent'
        : lower === 'referer' || lower === 'referrer'
        ? 'Referer'
        : lower === 'origin'
        ? 'Origin'
        : key;

    for (const existing of Object.keys(out)) {
      if (existing.toLowerCase() === canonical.toLowerCase()) delete out[existing];
    }
    out[canonical] = value;
  }
  return out;
}

/** Same-origin proxy link. `headers` are re-applied upstream by /api/media. */
function browserProxyUrl(url, headers, isM3U8) {
  const params = new URLSearchParams();
  params.set('url', url);
  params.set('headers', JSON.stringify(headers));
  if (isM3U8) params.set('hls', '1');
  return '/api/media?' + params.toString();
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

function mergeResults(models) {
  const valid = models.filter(Boolean);
  if (!valid.length) return null;

  const sources = [];
  const seen = new Set();
  for (const model of valid) {
    for (const source of model.sources) {
      const key = source.serverId + '|' + String(source.quality || '') + '|' + source.url;
      if (seen.has(key)) continue;
      seen.add(key);
      sources.push(source);
    }
  }

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
        kind: track?.kind === 'subtitles' ? 'subtitles' : 'captions',
      });
    }
  }

  const first = valid[0];
  return {
    sources,
    subtitles,
    intro: first.intro,
    outro: first.outro,
    resolvedServer: first.server.id,
    resolvedServers: valid.map(model => model.server.id),
  };
}

/**
 * Resolve a stream.
 *
 * All servers are queried concurrently, but we return as soon as the fastest
 * *successful* one answers (plus a short grace window so slow siblings can
 * contribute extra failover candidates). Remaining requests are cancelled so
 * we never leave upstream work running for nothing.
 */
async function resolveStreamingSources(id, episode, audio, preferredServer) {
  const servers = orderedServers(preferredServer);
  const controllers = servers.map(() => new AbortController());

  const settled = [];
  const pending = servers.map((server, index) => {
    const endpoint = server.path(id, episode, audio);
    return fetchJson(endpoint, REQUEST_TIMEOUT_MS, controllers[index].signal).then(payload => {
      const model = payload ? parseServerPayload(server, endpoint, payload, audio) : null;
      if (model) settled.push({ index, model });
      return model;
    });
  });

  let remaining = pending.length;
  if (!remaining) return null;

  let release;
  const firstSuccess = new Promise(resolve => {
    release = resolve;
  });

  for (const task of pending) {
    task
      .catch(() => null)
      .then(() => {
        remaining -= 1;
        if (settled.length || remaining === 0) release();
      });
  }

  await firstSuccess;
  if (settled.length < servers.length) await delay(GRACE_PERIOD_MS);

  controllers.forEach((controller, index) => {
    if (!settled.some(item => item.index === index)) controller.abort();
  });
  // Give cancellations a tick to settle so no rejection escapes.
  await Promise.allSettled(pending);

  const byPreference = settled
    .slice()
    .sort((a, b) => a.index - b.index)
    .map(item => item.model);

  return mergeResults(byPreference);
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');
}

export default async function handler(req, res) {
  setCors(res);
  res.setHeader('Cache-Control', 'public, max-age=15, s-maxage=30, stale-while-revalidate=120');

  if (req.method === 'OPTIONS') return res.status(204).end();

  const {
    action,
    query = '',
    id = '',
    episode = '1',
    audio = 'sub',
    page = '1',
    server = '',
  } = req.query || {};

  if (action === 'search') {
    const term = String(query).slice(0, 120);
    const pageNum = /^\d+$/.test(String(page)) ? page : '1';
    const data = await fetchJson(
      '/search?query=' + encodeURIComponent(term) + '&page=' + encodeURIComponent(pageNum),
      SEARCH_TIMEOUT_MS
    );
    return data
      ? res.json(data)
      : res.status(502).json({ error: 'The source service is temporarily unavailable' });
  }

  if (action === 'episodes' && /^\d+$/.test(id)) {
    const pageNum = /^\d+$/.test(String(page)) ? page : '1';
    const data = await fetchJson(
      '/anime/' + id + '/episodes?page=' + encodeURIComponent(pageNum),
      SEARCH_TIMEOUT_MS
    );
    return data
      ? res.json(data)
      : res.status(504).json({ error: 'Episode source timed out. Please retry.' });
  }

  if (action === 'source' && /^\d+$/.test(id) && /^\d+(\.\d+)?$/.test(episode)) {
    const lang = audio === 'dub' ? 'dub' : 'sub';
    const preferredServer = SERVER_ORDER.some(item => item.id === server) ? server : '';
    const resolved = await resolveStreamingSources(id, episode, lang, preferredServer);

    if (!resolved?.sources?.length) {
      return res.status(404).json({
        error:
          lang.toUpperCase() +
          ' stream is unavailable for this episode on all source servers',
      });
    }
    res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=60, stale-while-revalidate=300');
    return res.json(resolved);
  }

  return res.status(400).json({ error: 'Invalid request' });
}
