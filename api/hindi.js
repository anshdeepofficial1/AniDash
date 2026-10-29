const BASE = 'https://toonstream.us';
const SITE_HOSTS = new Set(['toonstream.us', 'www.toonstream.us', 'toonstream.vip', 'www.toonstream.vip']);
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const BASE_HEADERS = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
  'Referer': BASE + '/',
};

const ENTITY_MAP = {
  '&amp;': '&',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&lt;': '<',
  '&gt;': '>',
  '&nbsp;': ' ',
};

function decodeEntities(value = '') {
  return String(value).replace(/&(?:#x([0-9a-f]+)|#([0-9]+)|[a-z0-9]+);/gi, (match, hex, dec) => {
    if (hex) {
      try {
        const cp = parseInt(hex, 16);
        return cp ? String.fromCodePoint(cp) : '';
      } catch {
        return match;
      }
    }
    if (dec) {
      try {
        const cp = parseInt(dec, 10);
        return cp ? String.fromCodePoint(cp) : '';
      } catch {
        return match;
      }
    }
    const lower = match.toLowerCase();
    return Object.prototype.hasOwnProperty.call(ENTITY_MAP, lower) ? ENTITY_MAP[lower] : match;
  });
}

function stripHtmlTags(str = '') {
  let insideTag = false;
  let inQuote = null;
  let text = '';
  const s = String(str);
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (insideTag) {
      if (inQuote) {
        if (ch === inQuote) inQuote = null;
      } else if (ch === '"' || ch === "'") {
        inQuote = ch;
      } else if (ch === '>') {
        insideTag = false;
      }
    } else {
      if (ch === '<') {
        insideTag = true;
      } else {
        text += ch;
      }
    }
  }
  return text;
}

function plainText(value = '') {
  return decodeEntities(stripHtmlTags(value).replace(/\s+/g, ' ').trim());
}
function attr(tag, name) {
  const match = String(tag).match(new RegExp('(?:^|\\s)' + name + '\\s*=\\s*(?:"([^"]*)"|\\x27([^\\x27]*)\\x27|([^\\s>]+))', 'i'));
  return match ? decodeEntities(match[1] ?? match[2] ?? match[3] ?? '') : '';
}
function safeSiteUrl(raw, fallback = BASE) {
  let url;
  try { url = new URL(raw, fallback); } catch { throw new Error('Invalid Toonstream URL'); }
  if (url.protocol !== 'https:' || !SITE_HOSTS.has(url.hostname.toLowerCase())) {
    throw new Error('This source URL is not supported');
  }
  return url;
}
async function requestText(url, options = {}, timeout = 14000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, {
      redirect: 'follow',
      ...options,
      signal: controller.signal,
      headers: { ...BASE_HEADERS, ...(options.headers || {}) },
    });
    if (!response.ok) throw new Error('Source returned HTTP ' + response.status);
    const finalUrl = new URL(response.url || url);
    if (finalUrl.protocol !== 'https:' || !SITE_HOSTS.has(finalUrl.hostname.toLowerCase())) {
      throw new Error('Source redirected to an unsupported domain');
    }
    return { html: await response.text(), url: finalUrl.toString() };
  } finally {
    clearTimeout(timer);
  }
}
function absoluteSiteUrl(raw, base) {
  try {
    const url = new URL(raw, base);
    if (url.protocol !== 'https:' || !SITE_HOSTS.has(url.hostname.toLowerCase())) return '';
    return url.toString();
  } catch { return ''; }
}
function resultBlocks(html) {
  const root = html.match(/id=["']movies-a["'][\s\S]*?<\/ul>/i)?.[0] || html;
  let blocks = root.match(/<li\b[\s\S]*?<\/li>/gi) || [];
  if (!blocks.some(block => /<h2\b/i.test(block))) {
    blocks = html.match(/<article\b[\s\S]*?<\/article>/gi) || [];
  }
  return blocks;
}
function parseCards(html, baseUrl) {
  const seen = new Set();
  const results = [];
  for (const block of resultBlocks(html)) {
    const titleMatch = block.match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i) ||
      block.match(/<h3\b[^>]*>([\s\S]*?)<\/h3>/i);
    const anchorTags = [...block.matchAll(/<a\b[^>]*>[\s\S]*?<\/a>/gi)].map(m => m[0]);
    let url = '';
    for (const tag of anchorTags) {
      const open = tag.match(/^<a\b[^>]*>/i)?.[0] || tag;
      url = absoluteSiteUrl(attr(open, 'href'), baseUrl);
      if (url && !/\/(category|tag|page)\//i.test(new URL(url).pathname)) break;
      url = '';
    }
    const title = plainText(titleMatch?.[1] || anchorTags[0] || '');
    if (!url || !title || title.length < 2 || seen.has(url)) continue;
    const imageTag = block.match(/<img\b[^>]*>/i)?.[0] || '';
    const imageRaw = attr(imageTag, 'data-src') || attr(imageTag, 'data-lazy-src') ||
      attr(imageTag, 'src') || attr(imageTag, 'data-original');
    let image = '';
    try { const parsed = new URL(imageRaw, baseUrl); if (parsed.protocol === 'https:') image = parsed.toString(); } catch {}
    seen.add(url);
    results.push({ id: url, url, title, image, source: 'Toonstream', language: 'Hindi' });
    if (results.length >= 36) break;
  }
  return results;
}
function episodeCards(html, baseUrl) {
  const blocks = html.match(/<article\b[\s\S]*?<\/article>/gi) || [];
  const rows = [];
  const seen = new Set();
  for (const block of blocks) {
    const aMatch = block.match(/<a\b[^>]*>[\s\S]*?<\/a>/i);
    if (!aMatch) continue;
    const openTag = aMatch[0].match(/^<a\b[^>]*>/i)?.[0] || aMatch[0];
    const url = absoluteSiteUrl(attr(openTag, 'href'), baseUrl);
    const title = plainText((block.match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i) ||
      block.match(/<h3\b[^>]*>([\s\S]*?)<\/h3>/i) || [])[1] || aMatch[0]);
    if (!url || !title || seen.has(url)) continue;
    const episodeMatch = title.match(/(?:episode|ep\.?|e)\s*[-:#]?\s*(\d+(?:\.\d+)?)/i) ||
      title.match(/\b(\d+(?:\.\d+)?)\b/);
    const imageTag = block.match(/<img\b[^>]*>/i)?.[0] || '';
    const imageRaw = attr(imageTag, 'data-src') || attr(imageTag, 'src');
    let image = '';
    try { const parsed = new URL(imageRaw, baseUrl); if (parsed.protocol === 'https:') image = parsed.toString(); } catch {}
    seen.add(url);
    rows.push({ id: url, url, title, number: episodeMatch ? Number(episodeMatch[1]) : rows.length + 1, image });
  }
  return rows.sort((a, b) => a.number - b.number).slice(0, 500);
}
function anchorRecords(html) {
  return [...html.matchAll(/<a\b[^>]*>[\s\S]*?<\/a>/gi)].map(match => {
    const tag = match[0];
    const open = tag.match(/^<a\b[^>]*>/i)?.[0] || tag;
    return { open, inner: tag.slice(open.length).replace(/<\/a>$/i, '') };
  });
}
function extractEmbeds(html, baseUrl) {
  const marker = html.search(/id=["']aa-options["']/i);
  const section = marker >= 0 ? html.slice(marker) : html;
  const frames = [...section.matchAll(/<iframe\b[^>]*>/gi)].map(m => m[0]);
  const known = /(vidmoly|streamwish|cdnwish|filelions|vidhide|streamhide|guccihide|streamvid|earnvid|streamhg|dood|d000d|filemoon|streamruby|awstream|zephyrflick|mixdrop|mp4upload|streamtape|voe|vidsrc|kwik|megacloud|zokoanime|megaplay|animegg|anineko)/i;
  const out = [];
  const seen = new Set();
  for (const frame of frames) {
    const raw = attr(frame, 'data-src') || attr(frame, 'src');
    if (!raw || /about:blank|acceptable\.a-ads|doubleclick|googlesyndication|adsystem/i.test(raw)) continue;
    let url;
    try { url = new URL(raw, baseUrl); } catch { continue; }
    if (url.protocol !== 'https:' || SITE_HOSTS.has(url.hostname.toLowerCase()) || seen.has(url.toString())) continue;
    if (!known.test(url.hostname + url.pathname)) continue;
    seen.add(url.toString());
    out.push({ url: url.toString(), kind: 'embed', label: url.hostname.replace(/^www\./, '') });
    if (out.length >= 8) break;
  }
  return out;
}
function extractDirectVideos(html, baseUrl) {
  const out = [];
  const seen = new Set();
  const patterns = [
    /\bfile\s*:\s*["']((?:https?:)?\/\/[^"'\s]+?\.(?:m3u8|mp4)(?:\?[^"'\s]*)?)["']/gi,
    /<source\b[^>]*src=["']([^"']+\.(?:m3u8|mp4)(?:\?[^"']*)?)["']/gi,
  ];
  for (const pattern of patterns) {
    for (const match of html.matchAll(pattern)) {
      let url;
      try { url = new URL(match[1], baseUrl); } catch { continue; }
      if (url.protocol !== 'https:' || seen.has(url.toString())) continue;
      seen.add(url.toString());
      out.push({ url: url.toString(), kind: 'video', label: /\.m3u8/i.test(url.pathname) ? 'HLS stream' : 'MP4 stream' });
      if (out.length >= 6) return out;
    }
  }
  return out;
}
async function handle(req, res) {
  res.setHeader('Cache-Control', 's-maxage=45, stale-while-revalidate=120');
  const action = String(req.query.action || '');
  if (req.method !== 'GET') return res.status(405).json({ error: 'Use GET' });

  if (action === 'search') {
    const query = String(req.query.query || '').trim().slice(0, 100);
    const page = Math.min(30, Math.max(1, Number.parseInt(req.query.page || '1', 10) || 1));
    const url = query
      ? new URL(page > 1 ? '/page/' + page + '/' : '/', BASE)
      : new URL(page > 1 ? '/category/language/hindi-language/page/' + page + '/' : '/category/language/hindi-language/', BASE);
    if (query) url.searchParams.set('s', query);
    const result = await requestText(url.toString());
    const results = parseCards(result.html, result.url);
    return res.status(200).json({ source: 'Toonstream', language: 'Hindi', results, page, hasMore: results.length >= 30 });
  }

  if (action === 'episodes') {
    const detailUrl = safeSiteUrl(String(req.query.url || ''));
    const detail = await requestText(detailUrl.toString(), { headers: { Referer: BASE + '/' } });
    const seasons = anchorRecords(detail.html).map(anchor => ({
      post: attr(anchor.open, 'data-post'),
      season: attr(anchor.open, 'data-season'),
      title: plainText(anchor.inner),
    })).filter(x => x.post && x.season);

    let episodes = [];
    if (seasons.length) {
      const tasks = seasons.slice(0, 40).map(async season => {
        const body = new URLSearchParams({ action: 'action_select_season', season: season.season, post: season.post });
        const result = await requestText(new URL('/wp-admin/admin-ajax.php', detail.url).toString(), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
            'Origin': new URL(detail.url).origin,
            'Referer': detail.url,
          },
          body: body.toString(),
        }, 12000);
        return episodeCards(result.html, result.url).map(ep => ({ ...ep, season: season.title }));
      });
      const settled = await Promise.allSettled(tasks);
      episodes = settled.flatMap(x => x.status === 'fulfilled' ? x.value : []);
    } else {
      const ogImage = attr(detail.html.match(/<meta\b[^>]*property=["']og:image["'][^>]*>/i)?.[0] || '', 'content');
      episodes = [{ id: detail.url, url: detail.url, title: 'Movie', number: 1, image: ogImage }];
    }
    const unique = [...new Map(episodes.sort((a, b) => a.number - b.number).map(ep => [ep.url, ep])).values()];
    return res.status(200).json({ source: 'Toonstream', episodes: unique.slice(0, 500), totalEpisodes: unique.length });
  }

  if (action === 'source') {
    const episodeUrl = safeSiteUrl(String(req.query.url || ''));
    const episodePage = await requestText(episodeUrl.toString());
    const sources = [...extractEmbeds(episodePage.html, episodePage.url), ...extractDirectVideos(episodePage.html, episodePage.url)];
    if (!sources.length) {
      return res.status(404).json({ error: 'No browser-compatible player link was found for this episode. Try opening the source website.' });
    }
    return res.status(200).json({ source: 'Toonstream', sources: sources.slice(0, 8) });
  }
  return res.status(400).json({ error: 'Invalid request' });
}
export default async function handler(req, res) {
  try {
    return await handle(req, res);
  } catch (error) {
    const message = error?.name === 'AbortError'
      ? 'Hindi source request timed out. Please retry.'
      : String(error?.message || 'Hindi source is temporarily unavailable');
    return res.status(502).json({ error: message.slice(0, 220) });
  }
}
