/**
 * AniDash media proxy.
 *
 * Responsibilities:
 *   1. Fetch an authorised media resource (HLS playlist or media segment / MP4)
 *      from the content CDN on behalf of the browser, attaching the Referer /
 *      Origin / User-Agent the CDN requires (browsers cannot set those).
 *   2. Rewrite every URI inside an HLS playlist so the player keeps talking to
 *      this origin instead of the CDN (segments, variant playlists, EXT-X-KEY,
 *      EXT-X-MAP, EXT-X-MEDIA, I-frame playlists, ...).
 *   3. Stream bytes through instead of buffering them in memory, preserving
 *      Range / 206 responses so seeking keeps working.
 *
 * SECURITY
 *   - Only the content hosts below may be requested directly.
 *   - Redirect hops are followed manually and must stay on https:// and must
 *     never point at a loopback / private / link-local address.
 *   - Only a small whitelist of request headers can be forwarded upstream.
 */

const ALLOWED_DOMAINS = [
  // HLS master playlists + signed tokens
  'nexabloom.top',
  // HLS media segments (separate CDN from the playlist host)
  'eclipseharbor.space',
  'stellarfrontier.space',
  // subtitle / vtt host
  'broforgotsave.online',
  // MP4 source + its redirect target
  'animegg.org',
  'vidcache.net',
  // source server referers
  'megaplay.buzz',
  'zokoanime.video',
  'justanime.to',
  // legacy hosts kept for older saved links
  'give6beforegtav.site',
];

const FORWARD_HEADERS = ['referer', 'origin', 'user-agent', 'accept', 'accept-language'];
const MAX_URL_LENGTH = 8192;
const MAX_HEADER_LENGTH = 512;
const MAX_REDIRECTS = 6;
const RESPONSE_TIMEOUT_MS = 20000;
const MAX_RATE = 180; // requests per minute, per instance
const RATE_WINDOW_MS = 60000;

const HLS_TYPES = /mpegurl|x-mpegurl|vnd\.apple\.mpegurl/i;

function hostAllowed(hostname) {
  const host = String(hostname || '')
    .toLowerCase()
    .replace(/\.$/, '');
  if (!host) return false;
  return ALLOWED_DOMAINS.some(domain => host === domain || host.endsWith('.' + domain));
}

function isPrivateHost(hostname) {
  const host = String(hostname || '')
    .toLowerCase()
    .replace(/^\[|\]$/g, '')
    .replace(/\.$/, '');

  if (!host) return true;
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return true;
  if (host === '::1' || host === '0:0:0:0:0:0:0:1') return true;
  if (/^fe80:/i.test(host) || /^fc/i.test(host) || /^fd/i.test(host)) return true;

  const ipv4 = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (ipv4) {
    const [a, b] = [Number(ipv4[1]), Number(ipv4[2])];
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a >= 224) return true;
  }
  return false;
}

/** Safety net applied to *every* URL we end up fetching, including redirects. */
function blockedTarget(url) {
  if (!url || url.protocol !== 'https:') return true;
  if (url.username || url.password) return true;
  return isPrivateHost(url.hostname);
}

function safeHeaders(raw) {
  let parsed = {};
  if (typeof raw === 'string' && raw.trim()) {
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = {};
    }
  }
  if (!parsed || typeof parsed !== 'object') parsed = {};

  const out = {};
  for (const [key, value] of Object.entries(parsed)) {
    const lower = String(key).toLowerCase();
    if (!FORWARD_HEADERS.includes(lower)) continue;
    const text = String(value ?? '').trim().slice(0, MAX_HEADER_LENGTH);
    if (!text || /[\r\n]/.test(text)) continue;
    // Canonical casing keeps some CDNs happy.
    out[lower === 'referer' ? 'Referer'
      : lower === 'origin' ? 'Origin'
      : lower === 'user-agent' ? 'User-Agent'
      : lower === 'accept' ? 'Accept'
      : 'Accept-Language'] = text;
  }
  return out;
}

function defaultHeaders() {
  return {
    'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    Accept: '*/*',
    'Accept-Encoding': 'identity',
  };
}

function buildUpstreamHeaders(target, queryHeaders, req) {
  const headers = defaultHeaders();
  const forwarded = safeHeaders(queryHeaders);
  for (const [key, value] of Object.entries(forwarded)) headers[key] = value;

  if (!headers.Origin && !headers.Referer) {
    headers.Origin = target.origin;
    headers.Referer = target.origin + '/';
  } else if (headers.Referer && !headers.Origin) {
    try {
      headers.Origin = new URL(headers.Referer).origin;
    } catch (_) {}
  }

  const range = req.headers && req.headers.range;
  if (typeof range === 'string' && range && !/[\r\n]/.test(range)) headers.Range = range;

  const conditional = {
    'if-none-match': 'If-None-Match',
    'if-modified-since': 'If-Modified-Since',
    'if-range': 'If-Range',
  };
  for (const [incoming, outgoing] of Object.entries(conditional)) {
    const value = req.headers && req.headers[incoming];
    if (typeof value === 'string' && value && !/[\r\n]/.test(value)) headers[outgoing] = value;
  }
  return headers;
}

/** Follow redirects manually so every hop can be validated. */
async function requestUpstream(url, headers) {
  let current = url;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), RESPONSE_TIMEOUT_MS);

    let response;
    try {
      response = await fetch(current, {
        method: 'GET',
        headers,
        redirect: 'manual',
        signal: controller.signal,
      });
    } catch (error) {
      clearTimeout(timer);
      if (error?.name === 'AbortError') return { error: 504, message: 'Media source timed out' };
      return { error: 502, message: 'Media source is unreachable' };
    }
    clearTimeout(timer);

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');
      try {
        await response.body?.cancel();
      } catch (_) {}
      if (!location) return { error: 502, message: 'Media source returned a broken redirect' };

      let next;
      try {
        next = new URL(location, current);
      } catch (_) {
        return { error: 502, message: 'Media source returned an invalid redirect' };
      }
      if (blockedTarget(next)) return { error: 403, message: 'Media redirect was rejected' };
      current = next;
      continue;
    }

    return { response, url: current };
  }
  return { error: 508, message: 'Media source redirected too many times' };
}

function proxyUrl(target, headersJson, isPlaylist) {
  const params = new URLSearchParams();
  params.set('url', target);
  if (headersJson && headersJson !== '{}') params.set('headers', headersJson);
  if (isPlaylist) params.set('hls', '1');
  return '/api/media?' + params.toString();
}

function rewritePlaylist(playlist, baseUrl, headersJson) {
  let nextIsVariant = false;
  const eol = playlist.includes('\r\n') ? '\r\n' : '\n';

  return playlist
    .split('\n')
    .map(rawLine => {
      const line = rawLine.replace(/\r$/, '');
      const value = line.trim();
      if (!value) return line;

      if (value.startsWith('#')) {
        const upper = value.toUpperCase();
        // Every HLS tag that can carry a URI: KEY, MAP, MEDIA, I-FRAME-STREAM-INF,
        // SESSION-KEY, PART, PRELOAD-HINT, RENDITION-REPORT, DATERANGE ...
        let rewritten = line;
        if (upper.includes('URI="')) {
          rewritten = rewritten.replace(/URI="([^"]+)"/g, (_, uri) => {
            let absolute;
            try {
              absolute = new URL(uri, baseUrl).toString();
            } catch (_) {
              return `URI="${uri}"`;
            }
            const nestedPlaylist =
              upper.startsWith('#EXT-X-MEDIA:') ||
              upper.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
              /\.m3u8(?:$|\?)/i.test(uri);
            return `URI="${proxyUrl(absolute, headersJson, nestedPlaylist)}"`;
          });
        }
        nextIsVariant = upper.startsWith('#EXT-X-STREAM-INF');
        return rewritten;
      }

      let absolute;
      try {
        absolute = new URL(value, baseUrl).toString();
      } catch (_) {
        return line;
      }
      const isPlaylist = nextIsVariant || /\.m3u8(?:$|\?)/i.test(absolute);
      nextIsVariant = false;
      return proxyUrl(absolute, headersJson, isPlaylist);
    })
    .join(eol);
}

function looksLikePlaylist(response, target, query, bufferedLength) {
  const type = response.headers.get('content-type') || '';
  if (query.hls === '1') return true;
  if (HLS_TYPES.test(type)) return true;
  if (/\.m3u8(?:$|\?)/i.test(target.pathname + target.search)) return true;
  if (/^text\/|^application\/json/i.test(type)) return true;
  if (!type && bufferedLength > 0) return true;
  return false;
}

/**
 * The content CDN disguises MPEG-TS segments (`.jpg`, `text/html`-looking
 * paths, `image/jpeg` content-type) to defeat hotlinking. Correct the
 * Content-Type we hand to the player so native HLS (iOS Safari) and MSE both
 * see a media type instead of an image type.
 */
function sniffMediaType(head, fallback) {
  if (!head || head.length < 189) return null;
  if (head[0] === 0x47 && head[188] === 0x47) return 'video/mp2t';
  if (head.subarray(4, 8).toString('latin1') === 'ftyp') return 'video/mp4';
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'image/jpeg';
  if (head[0] === 0x00 && head[1] === 0x00 && head[2] === 0x01 && (head[3] === 0xba || head[3] === 0xb3)) {
    return 'video/mpeg';
  }
  if (head[0] === 0x49 && head[1] === 0x44 && head[2] === 0x33) return 'audio/mpeg';
  return null;
}

const TRUSTED_MEDIA_TYPE = /^(video|audio)\//i;
const SNIFFABLE_TYPE = /^(image\/|text\/|application\/octet-stream|$)/i;

/**
 * Read at least `minimum` bytes from the body while keeping the reader alive,
 * so the peeked bytes can be stitched back in front of the remaining stream.
 * Returns `null` when the body cannot be read at all.
 */
async function peekHead(body, minimum) {
  const reader = body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (size < minimum) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(Buffer.from(value));
        size += value.length;
      }
    }
    return { head: Buffer.concat(chunks, size), reader };
  } catch (_) {
    try {
      await reader.cancel();
    } catch (_) {}
    try {
      reader.releaseLock();
    } catch (_) {}
    return null;
  }
}

/** Re-attach already consumed bytes in front of what the reader has left. */
function restream(head, reader) {
  let sentHead = false;
  return new ReadableStream({
    pull(controller) {
      if (!sentHead) {
        sentHead = true;
        if (head.length) {
          controller.enqueue(head);
          return undefined;
        }
      }
      return reader
        .read()
        .then(({ value, done }) => {
          if (done) controller.close();
          else controller.enqueue(value);
        })
        .catch(error => controller.error(error));
    },
    cancel(reason) {
      return reader.cancel(reason).catch(() => {});
    },
  });
}

async function streamBody(upstream, res) {
  if (!upstream.body) {
    res.end();
    return;
  }

  const upstreamType = upstream.headers.get('content-type') || '';
  const sniffable = SNIFFABLE_TYPE.test(upstreamType);
  const peek = sniffable ? await peekHead(upstream.body, 189) : null;

  let source;
  if (peek) {
    if (!peek.head.length) {
      res.removeHeader('content-length');
      res.end();
      return;
    }
    const detected = sniffMediaType(peek.head, upstreamType);
    if (detected && !TRUSTED_MEDIA_TYPE.test(upstreamType)) {
      res.setHeader('content-type', detected);
    }
    source = (await import('node:stream')).Readable.fromWeb(restream(peek.head, peek.reader));
  } else {
    try {
      source = (await import('node:stream')).Readable.fromWeb(upstream.body);
    } catch (_) {
      try {
        const buffer = Buffer.from(await upstream.arrayBuffer());
        res.end(buffer);
      } catch (_) {
        res.end();
      }
      return;
    }
  }

  // If the player aborts (seek / source switch / tab close) stop pulling from
  // the CDN instead of leaving a dangling upstream socket.
  const release = () => {
    try {
      source.destroy();
    } catch (_) {}
  };
  res.on('close', release);
  res.on('error', release);
  source.pipe(res);

  try {
    const { finished } = await import('node:stream/promises');
    await finished(res);
  } catch (_) {
    // Client went away or the upstream stream broke mid-flight.
  } finally {
    release();
  }
}

function passThroughHeaders(upstream, res) {
  const raw = upstream.headers;
  const hasEncoding = Boolean(raw.get('content-encoding'));

  for (const name of [
    'content-type',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
    'content-disposition',
  ]) {
    const value = raw.get(name);
    if (value) res.setHeader(name, value);
  }

  // Only forward the length when we are certain the bytes are unmodified.
  const length = raw.get('content-length');
  if (length && !hasEncoding) res.setHeader('content-length', length);

  res.setHeader('accept-ranges', raw.get('accept-ranges') || 'bytes');
}

// Minimal per-instance sliding-window limiter. Serverless instances are short
// lived, so this only needs to blunt accidental loops and scripted abuse.
const hits = new Map();
function rateLimited(key) {
  const now = Date.now();
  const window = hits.get(key) || { count: 0, start: now };
  if (now - window.start > RATE_WINDOW_MS) {
    window.count = 0;
    window.start = now;
  }
  window.count += 1;
  hits.set(key, window);
  if (hits.size > 2000) hits.clear();
  return window.count > MAX_RATE;
}

function clientKey(req) {
  const forwarded = req.headers && req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded) return forwarded.split(',')[0].trim();
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}

function fail(res, status, message, cacheable = false) {
  res.setHeader('Cache-Control', cacheable ? 'public, max-age=60' : 'no-store');
  return res.status(status).json({ error: message });
}

// Named exports exist for the unit tests; Vercel only loads `default`.
export { safeHeaders, rewritePlaylist, hostAllowed, isPrivateHost, blockedTarget };

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Range, Content-Type');
  res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');

  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method && req.method !== 'GET' && req.method !== 'HEAD') {
    return fail(res, 405, 'Method not allowed');
  }

  if (rateLimited(clientKey(req))) return fail(res, 429, 'Too many media requests');

  const query = req.query || {};
  const rawUrl = String(query.url || '');
  if (!rawUrl || rawUrl.length > MAX_URL_LENGTH) {
    return fail(res, 400, 'Invalid media request');
  }

  let target;
  try {
    target = new URL(rawUrl);
  } catch (_) {
    return fail(res, 400, 'Invalid media request');
  }

  if (blockedTarget(target)) return fail(res, 400, 'Invalid media request');
  if (!hostAllowed(target.hostname)) return fail(res, 403, 'Media host is not allowed');

  const headersJson = typeof query.headers === 'string' ? query.headers : '{}';
  const headers = buildUpstreamHeaders(target, headersJson, req);

  const attempt = await requestUpstream(target, headers);
  if (!attempt.response) return fail(res, attempt.error || 502, attempt.message || 'Media request failed');

  const upstream = attempt.response;
  if (!upstream.ok && upstream.status !== 206 && upstream.status !== 304) {
    try {
      await upstream.body?.cancel();
    } catch (_) {}
    const status = upstream.status === 404 ? 404 : upstream.status === 403 ? 403 : 502;
    return fail(
      res,
      status,
      status === 403 ? 'The media host refused this request' : 'Media source is unavailable'
    );
  }

  const contentType = upstream.headers.get('content-type') || '';
  const declaredLength = Number(upstream.headers.get('content-length') || 0);
  const typeIsHls = HLS_TYPES.test(contentType);
  const pathIsHls = /\.m3u8(?:$|\?)/i.test(attempt.url.pathname + attempt.url.search);
  const typeIsTextish = /^text\/|^application\/json|^application\/xml/i.test(contentType);
  const typeIsEmpty = !contentType;
  const MAX_BUFFER = 4 * 1024 * 1024;

  const explicitlyHls = typeIsHls || pathIsHls || query.hls === '1';

  // Only ever buffer when we are confident the payload is small and textual.
  // A missing content-length on an unknown type is NOT a licence to read a
  // 60MB video into memory.
  const mayBuffer =
    req.method !== 'HEAD' &&
    (explicitlyHls ||
      (typeIsTextish && declaredLength <= MAX_BUFFER) ||
      (typeIsEmpty && declaredLength > 0 && declaredLength <= 256 * 1024));

  let bufferedBody = null;
  if (mayBuffer) {
    let text = null;
    try {
      text = await upstream.text();
    } catch (_) {
      text = null;
    }

    if (text === null) {
      return fail(res, 502, 'Media source returned an unreadable response');
    }
    if (text.trimStart().startsWith('#EXTM3U')) {
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl; charset=utf-8');
      res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=30, stale-while-revalidate=60');
      res.status(200);
      return res.send(rewritePlaylist(text, attempt.url, headersJson));
    }
    if (explicitlyHls) {
      // Upstream claimed to be a playlist but sent an error document.
      return fail(res, 502, 'Media source did not return a valid HLS playlist');
    }
    bufferedBody = Buffer.from(text, 'utf8');
  }

  passThroughHeaders(upstream, res);
  if (bufferedBody !== null) {
    if (!upstream.headers.get('content-type')) res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('content-length', String(bufferedBody.byteLength));
  }

  const status = upstream.status;
  const isRange = status === 206 || Boolean(req.headers && req.headers.range);
  res.setHeader(
    'Cache-Control',
    isRange ? 'public, max-age=3600, stale-while-revalidate=86400' : 'public, max-age=3600, s-maxage=3600'
  );
  res.status(status);

  if (bufferedBody !== null) return res.send(bufferedBody);

  if (req.method === 'HEAD' || !upstream.body) {
    try {
      await upstream.body?.cancel();
    } catch (_) {}
    return res.end();
  }

  return streamBody(upstream, res);
}
