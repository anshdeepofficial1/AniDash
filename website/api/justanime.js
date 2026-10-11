const API = 'https://core.justanime.to/api';
const SITE = 'https://justanime.to';
const UA =
  'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

function allowedPath(path) {
  return (
    /^\/search\?(?:[^#]*)$/.test(path) ||
    /^\/anime\/\d+(?:\/episodes\?page=\d+)?$/.test(path) ||
    /^\/watch\/\d+\/episode\/\d+(?:\.\d+)?(?:\/(?:megaplay|zokoanime|animegg|anineko\/(?:sub|dub)(?:\/hd1)?))?$/.test(path)
  );
}

export default async function handler(request, response) {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Cache-Control', 'public, s-maxage=30, stale-while-revalidate=120');
  if (request.method === 'OPTIONS') {
    response.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    response.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    return response.status(204).end();
  }

  const path = String(request.query.path || '');
  if (!allowedPath(path)) {
    return response.status(400).json({ error: 'Invalid JustAnime path' });
  }

  try {
    const upstream = await fetch(API + path, {
      headers: {
        Accept: 'application/json, text/plain, */*',
        Origin: SITE,
        Referer: SITE + '/',
        'User-Agent': UA,
      },
      signal: AbortSignal.timeout(15000),
    });
    const body = await upstream.text();
    if (!upstream.ok) {
      return response.status(502).json({ error: 'Upstream unavailable', status: upstream.status });
    }
    try {
      JSON.parse(body);
    } catch (_) {
      return response.status(502).json({ error: 'Invalid upstream response' });
    }
    return response.status(200).send(body);
  } catch (_) {
    return response.status(504).json({ error: 'JustAnime upstream timed out' });
  }
}
