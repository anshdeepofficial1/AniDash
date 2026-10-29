const ANILIST_ENDPOINT = 'https://graphql.anilist.co';
const ADMIN_ANILIST_ID = process.env.ADMIN_ANILIST_ID || '8013267';

async function authenticatedAdmin(req) {
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
  if (!(await authenticatedAdmin(req))) {
    return res.status(403).json({ error: 'Developer account required' });
  }
  const configuredPin = String(process.env.ADMIN_BROADCAST_PIN || '');
  const suppliedPin = String(req.body?.pin || '');
  if (!/^\d{4}$/.test(configuredPin)) {
    return res.status(503).json({ error: 'Developer PIN is not configured' });
  }
  if (suppliedPin !== configuredPin) {
    return res.status(401).json({ error: 'Incorrect developer PIN' });
  }
  return res.status(200).json({ unlocked: true });
}
