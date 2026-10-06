const API = 'https://core.justanime.to/api';

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
  const { action, query = '', id = '', episode = '1', audio = 'sub', page = '1' } = req.query;
  let path;
  if (action === 'search') path = `/search?query=${encodeURIComponent(query)}&page=${encodeURIComponent(page)}`;
  if (action === 'episodes' && /^\d+$/.test(id)) path = `/anime/${id}/episodes?page=${encodeURIComponent(page)}`;
  if (action === 'source' && /^\d+$/.test(id) && /^\d+(\.\d+)?$/.test(episode)) path = `/watch/${id}/episode/${episode}/megaplay`;
  if (!path) return res.status(400).json({ error: 'Invalid request' });
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    const upstream = await fetch(`${API}${path}`, {
      signal: controller.signal,
      headers: { Origin: 'https://justanime.to', Referer: 'https://justanime.to/', 'User-Agent': 'Mozilla/5.0 AniDash-PWA' }
    }).finally(() => clearTimeout(timer));
    const data = await upstream.json();
    if (!upstream.ok) return res.status(upstream.status).json({ error: 'Source unavailable' });
    if (action === 'source') {
      const selected = data[audio === 'dub' ? 'dub' : 'sub'];
      if (!selected?.sources?.length) return res.status(404).json({ error: `${audio.toUpperCase()} is unavailable` });
      return res.json({ ...selected, sources: selected.sources.map(source => ({ ...source, url: `/api/media?url=${encodeURIComponent(source.url)}` })), intro: selected.intro || data.intro, outro: selected.outro || data.outro });
    }
    return res.json(data);
  } catch (error) {
    const timedOut = error?.name === 'AbortError';
    return res.status(timedOut ? 504 : 502).json({
      error: timedOut ? 'Episode source timed out. Please retry.' : 'The source service is temporarily unavailable',
    });
  }
}
