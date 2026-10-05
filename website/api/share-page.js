const BASE = 'https://anidashweb.vercel.app';

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function redisConfig() {
  return {
    url: process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN,
  };
}

async function sharedChat(id) {
  const { url, token } = redisConfig();
  if (!url || !token || !/^[A-Za-z0-9_-]{10,32}$/.test(id)) return null;
  const response = await fetch(`${url}/get/${encodeURIComponent(`anidash:chat:${id}`)}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!response.ok) return null;
  const value = (await response.json()).result;
  return value ? JSON.parse(value) : null;
}

async function animeMetadata(id) {
  if (!/^\d+$/.test(id)) return null;
  const response = await fetch('https://graphql.anilist.co', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      query: 'query($id:Int){Media(id:$id,type:ANIME){title{english romaji}coverImage{extraLarge large}episodes format}}',
      variables: { id: Number(id) },
    }),
  });
  if (!response.ok) return null;
  return (await response.json()).data?.Media || null;
}

function page({ title, description, image, canonical, deepLink }) {
  const safeTitle = escapeHtml(title);
  const safeDescription = escapeHtml(description);
  const safeImage = escapeHtml(image || `${BASE}/assets/anidash_logo.png`);
  const safeCanonical = escapeHtml(canonical);
  const safeDeepLink = escapeHtml(deepLink);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${safeTitle} · AniDash</title><meta name="description" content="${safeDescription}"><link rel="canonical" href="${safeCanonical}"><meta property="og:type" content="website"><meta property="og:site_name" content="AniDash"><meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeDescription}"><meta property="og:image" content="${safeImage}"><meta property="og:url" content="${safeCanonical}"><meta name="twitter:card" content="summary_large_image"><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0d12;color:#f7f8fb;font:16px system-ui}.card{width:min(560px,calc(100% - 40px));background:#171a22;border:1px solid #2b3040;border-radius:24px;padding:24px;box-shadow:0 24px 70px #0008}.cover{width:100%;max-height:360px;object-fit:cover;border-radius:16px}h1{margin:18px 0 8px;font-size:28px}.muted{color:#adb5c7;line-height:1.55}.actions{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}a{padding:13px 18px;border-radius:999px;text-decoration:none;font-weight:700;background:#5677ff;color:white}a.secondary{background:#292e3c}</style></head><body><main class="card">${image ? `<img class="cover" src="${safeImage}" alt="">` : ''}<h1>${safeTitle}</h1><p class="muted">${safeDescription}</p><div class="actions"><a href="${safeDeepLink}">Open in AniDash</a><a class="secondary" href="${BASE}">Get AniDash</a></div></main></body></html>`;
}

export default async function handler(req, res) {
  const kind = String(req.query?.kind || '');
  const id = String(req.query?.id || '');
  const episode = String(req.query?.episode || '');
  let meta;
  if (kind === 'chat') {
    const chat = await sharedChat(id);
    meta = {
      title: chat?.title || 'Shared AnyCore chat',
      description: 'A conversation shared from AnyCore in AniDash.',
      image: `${BASE}/assets/anidash_logo.png`,
      canonical: `${BASE}/c/${id}`,
      deepLink: `anidash:///c/${id}`,
    };
  } else {
    const anime = await animeMetadata(id);
    const title = anime?.title?.english || anime?.title?.romaji || 'Anime';
    const count = anime?.episodes ? ` · ${anime.episodes} episodes` : '';
    const image = anime?.coverImage?.extraLarge || anime?.coverImage?.large;
    if (kind === 'episode') {
      meta = {
        title: `${title} · Episode ${episode}`,
        description: `Watch Episode ${episode} of ${title} in AniDash${count}.`,
        image,
        canonical: `${BASE}/episode/${id}/${episode}`,
        deepLink: `anidash:///episode/${id}/${episode}`,
      };
    } else {
      meta = {
        title,
        description: `${anime?.format || 'Anime'}${count} · Open in AniDash.`,
        image,
        canonical: `${BASE}/anime/${id}`,
        deepLink: `anidash:///anime/${id}`,
      };
    }
  }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=3600');
  return res.status(200).send(page(meta));
}
