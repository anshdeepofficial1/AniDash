const FEED = 'https://www.animenewsnetwork.com/all/rss.xml?ann-edition=us';

const decode = value =>
  String(value || '')
    .replace(/<!\[CDATA\[|\]\]>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .trim();

const stripTags = value =>
  decode(value)
    .replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

const pick = (block, tag) => {
  const match = block.match(new RegExp('<' + tag + '[^>]*>([\\s\\S]*?)<\\/' + tag + '>', 'i'));
  return match ? decode(match[1]) : '';
};

function imageFrom(block) {
  const enclosure = block.match(/<enclosure[^>]+url=["']([^"']+)["'][^>]*>/i);
  if (enclosure) return decode(enclosure[1]);
  const media = block.match(/<media:(?:content|thumbnail)[^>]+url=["']([^"']+)["'][^>]*>/i);
  if (media) return decode(media[1]);
  const html = pick(block, 'description') || pick(block, 'content:encoded');
  const img = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  return img ? decode(img[1]) : '';
}

export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=900');

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    const response = await fetch(FEED, {
      signal: controller.signal,
      headers: {
        Accept: 'application/rss+xml, application/xml, text/xml, */*',
        'User-Agent': 'Mozilla/5.0 AniDash-PWA',
      },
    }).finally(() => clearTimeout(timer));

    if (!response.ok) throw new Error('feed:' + response.status);
    const xml = await response.text();
    const items = [...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)]
      .slice(0, 30)
      .map(match => {
        const block = match[1];
        const title = stripTags(pick(block, 'title'));
        const url = stripTags(pick(block, 'link'));
        const dateRaw = stripTags(pick(block, 'pubDate'));
        const description = stripTags(pick(block, 'description'));
        const imageUrl = imageFrom(block);
        let date = dateRaw;
        try {
          date = new Date(dateRaw).toISOString();
        } catch (_) {}
        return { title, url, date, excerpt: description, imageUrl };
      })
      .filter(item => item.title && /^https?:\/\//i.test(item.url));

    return res.json({ items });
  } catch (_) {
    return res.status(502).json({ error: 'Anime news is temporarily unavailable' });
  }
}
