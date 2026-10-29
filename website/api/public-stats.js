const MAX_RECORDS = 50000;
const PAGE_SIZE = 300;

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  res.setHeader('Cache-Control', 'public, s-maxage=900, stale-while-revalidate=3600');
  if (!process.env.ONESIGNAL_APP_ID || !process.env.ONESIGNAL_API_KEY) {
    return badge(res, 'unavailable', 'lightgrey');
  }

  try {
    const cutoff = Math.floor(Date.now() / 1000) - 30 * 24 * 60 * 60;
    const seen = new Set();
    let active = 0;
    for (let offset = 0; offset < MAX_RECORDS; offset += PAGE_SIZE) {
      const response = await fetch(
        `https://api.onesignal.com/players?app_id=${encodeURIComponent(process.env.ONESIGNAL_APP_ID)}&limit=${PAGE_SIZE}&offset=${offset}`,
        { headers: { Authorization: `Key ${process.env.ONESIGNAL_API_KEY}` } },
      );
      if (!response.ok) return badge(res, 'unavailable', 'lightgrey');
      const json = await response.json();
      const players = Array.isArray(json.players) ? json.players : [];
      for (const player of players) {
        const id = String(player.id || '');
        if (!id || seen.has(id)) continue;
        seen.add(id);
        if (Number(player.last_active || 0) >= cutoff) active += 1;
      }
      if (players.length < PAGE_SIZE) break;
    }
    return badge(res, String(active), '2e8b57');
  } catch (_) {
    return badge(res, 'unavailable', 'lightgrey');
  }
}

function badge(res, message, color) {
  return res.status(200).json({
    schemaVersion: 1,
    label: 'actual users (30d)',
    message,
    color,
    namedLogo: 'android',
  });
}
