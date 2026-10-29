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
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  if (!(await authorizedAdmin(req))) return res.status(403).json({ error: 'Admin access required' });
  if (!process.env.ADMIN_BROADCAST_PIN || req.headers['x-admin-pin'] !== process.env.ADMIN_BROADCAST_PIN) {
    return res.status(403).json({ error: 'Developer verification required' });
  }
  if (!process.env.ONESIGNAL_APP_ID || !process.env.ONESIGNAL_API_KEY) {
    return res.status(503).json({ error: 'OneSignal is not configured' });
  }
  const response = await fetch(`https://api.onesignal.com/apps/${process.env.ONESIGNAL_APP_ID}`, {
    headers: { Authorization: `Key ${process.env.ONESIGNAL_API_KEY}` },
  });
  const data = await response.json();
  if (!response.ok) {
    return res.status(response.status).json({ error: data?.errors?.[0] || 'Unable to load OneSignal statistics' });
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  const cutoffs = {
    activeToday: nowSeconds - 24 * 60 * 60,
    active7Days: nowSeconds - 7 * 24 * 60 * 60,
    active30Days: nowSeconds - 30 * 24 * 60 * 60,
  };
  const active = { activeToday: 0, active7Days: 0, active30Days: 0 };
  const seen = new Set();
  const total = Number(data.players || 0);

  // OneSignal creates an anonymous subscription record for each installation.
  // Its last_active timestamp lets us calculate aggregate activity without
  // collecting names, watch history, IP addresses, or hardware identifiers.
  // The legacy players endpoint caps a page at 200 even when a larger limit
  // is requested. Advancing by 300 skipped 100 devices on every page and made
  // active counts appear capped at 200.
  const pageSize = 200;
  for (let offset = 0; offset < total && offset < 50000; offset += pageSize) {
    const playersResponse = await fetch(
      `https://api.onesignal.com/players?app_id=${encodeURIComponent(process.env.ONESIGNAL_APP_ID)}&limit=${pageSize}&offset=${offset}`,
      { headers: { Authorization: `Key ${process.env.ONESIGNAL_API_KEY}` } },
    );
    if (!playersResponse.ok) break;
    const page = await playersResponse.json();
    const players = Array.isArray(page.players) ? page.players : [];
    if (players.length === 0) break;
    for (const player of players) {
      const id = String(player.id || '');
      if (!id || seen.has(id)) continue;
      seen.add(id);
      const lastActive = Number(player.last_active || 0);
      if (lastActive >= cutoffs.activeToday) active.activeToday += 1;
      if (lastActive >= cutoffs.active7Days) active.active7Days += 1;
      if (lastActive >= cutoffs.active30Days) active.active30Days += 1;
    }
    if (players.length < pageSize) break;
  }

  return res.status(200).json({
    totalDevices: data.players ?? 0,
    subscribedDevices: data.messageable_players ?? 0,
    ...active,
  });
}
