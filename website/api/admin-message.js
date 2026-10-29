const ANILIST_ENDPOINT = 'https://graphql.anilist.co';
const ADMIN_ANILIST_ID = process.env.ADMIN_ANILIST_ID || '8013267';

async function authorizedAdmin(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) return false;
  const response = await fetch(ANILIST_ENDPOINT, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'query { Viewer { id } }' }),
  });
  if (!response.ok) return false;
  const json = await response.json();
  return String(json?.data?.Viewer?.id || '') === ADMIN_ANILIST_ID;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  if (!(await authorizedAdmin(req))) return res.status(403).json({ error: 'Admin access required' });
  if (!process.env.ADMIN_BROADCAST_PIN || req.headers['x-admin-pin'] !== process.env.ADMIN_BROADCAST_PIN) {
    return res.status(403).json({ error: 'Developer verification required' });
  }
  const title = String(req.body?.title || '').trim();
  const message = String(req.body?.message || '').trim();
  const route = String(req.body?.route || '/').trim();
  if (!title || !message || title.length > 80 || message.length > 1000) {
    return res.status(400).json({ error: 'Enter a valid title and message' });
  }
  if (!process.env.ONESIGNAL_APP_ID || !process.env.ONESIGNAL_API_KEY) {
    return res.status(503).json({ error: 'OneSignal is not configured' });
  }
  const response = await fetch('https://api.onesignal.com/notifications', {
    method: 'POST',
    headers: {
      Authorization: `Key ${process.env.ONESIGNAL_API_KEY}`,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: JSON.stringify({
      app_id: process.env.ONESIGNAL_APP_ID,
      target_channel: 'push',
      included_segments: ['Subscribed Users'],
      headings: { en: title },
      contents: { en: message },
      data: { route, type: 'developer_announcement' },
      name: `AniDash admin: ${title}`,
    }),
  });
  const json = await response.json();
  return res.status(response.ok ? 200 : response.status).json(json);
}
