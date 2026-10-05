const ID = /^[A-Za-z0-9_-]{10,32}$/;

function config() {
  return {
    url: process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN,
  };
}

async function redis(command) {
  const { url, token } = config();
  if (!url || !token) throw new Error('SHARE_STORE_NOT_CONFIGURED');
  const response = await fetch(`${url}/${command.map(encodeURIComponent).join('/')}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error('SHARE_STORE_UNAVAILABLE');
  return (await response.json()).result;
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  try {
    if (req.method === 'POST') {
      const id = String(req.body?.id || '');
      const messages = Array.isArray(req.body?.messages)
        ? req.body.messages.slice(-100)
        : [];
      const title = String(req.body?.title || 'AnyCore chat').trim().slice(0, 120);
      if (!ID.test(id) || !messages.length) {
        return res.status(400).json({ error: 'Invalid share' });
      }
      const payload = JSON.stringify({ title, messages, createdAt: Date.now() });
      const stored = await redis(['set', `anidash:chat:${id}`, payload, 'EX', '2592000', 'NX']);
      if (stored !== 'OK') {
        return res.status(409).json({ error: 'Share ID already exists' });
      }
      return res.status(201).json({ id, url: `https://anidashweb.vercel.app/c/${id}` });
    }
    if (req.method === 'GET') {
      const id = String(req.query?.id || '');
      if (!ID.test(id)) return res.status(400).json({ error: 'Invalid share' });
      const value = await redis(['get', `anidash:chat:${id}`]);
      if (!value) return res.status(404).json({ error: 'Share not found' });
      return res.status(200).json(JSON.parse(value));
    }
    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    return res.status(503).json({ error: error.message || 'Share unavailable' });
  }
}
