const ANILIST_ENDPOINT = 'https://graphql.anilist.co';
const ADMIN_ANILIST_ID = process.env.ADMIN_ANILIST_ID || '8013267';
const REPO = process.env.GITHUB_REPOSITORY || 'anshdeepofficial1/AniDash';

function config() {
  return {
    url: process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL,
    token: process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN,
  };
}

async function redis(command) {
  const { url, token } = config();
  if (!url || !token) return null;
  try {
    const response = await fetch(`${url}/${command.map(encodeURIComponent).join('/')}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;
    return (await response.json()).result;
  } catch (_) {
    return null;
  }
}

async function isAuthorizedAdmin(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  const pin = req.headers['x-admin-pin'] || '';

  if (process.env.ADMIN_BROADCAST_PIN && pin === process.env.ADMIN_BROADCAST_PIN) {
    return true;
  }

  if (!token) return false;
  try {
    const response = await fetch(ANILIST_ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: 'query { Viewer { id } }' }),
    });
    if (!response.ok) return false;
    const json = await response.json();
    return String(json?.data?.Viewer?.id || '') === ADMIN_ANILIST_ID;
  } catch (_) {
    return false;
  }
}

async function forwardToGitHub(report) {
  const token = process.env.GITHUB_FEEDBACK_TOKEN || process.env.GITHUB_TOKEN;
  if (!token) return null;

  try {
    const title = `[In-App ${String(report.type || 'feedback').toUpperCase()}]: ${String(report.title || 'Untitled')}`;
    const body = `### 📥 In-App User Feedback Report
- **Category:** ${report.type || 'General'}
- **Anime Subject:** ${report.animeTitle || 'None specified'}
- **App Version:** ${report.appVersion || 'Unknown'}
- **Platform:** ${report.platform || 'Android'}
- **Contact:** ${report.contact || 'None provided'}
- **Submitted At:** ${report.createdAt || new Date().toISOString()}

---
### Description
${report.description || 'No description provided'}
`;

    const labels = ['in-app-feedback'];
    if (report.type === 'bug') labels.push('bug');
    if (report.type === 'playback') labels.push('bug', 'playback');
    if (report.type === 'request') labels.push('enhancement');

    const res = await fetch(`https://api.github.com/repos/${REPO}/issues`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'User-Agent': 'AniDash-Feedback-Bot',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ title, body, labels }),
    });

    if (res.ok) {
      const json = await res.json();
      return json.html_url;
    }
  } catch (err) {
    console.error('GitHub forward failed:', err);
  }
  return null;
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method === 'POST') {
    const title = String(req.body?.title || '').trim().slice(0, 150);
    const description = String(req.body?.description || '').trim().slice(0, 3000);
    const type = String(req.body?.type || 'other').trim();
    const contact = String(req.body?.contact || '').trim().slice(0, 100);
    const appVersion = String(req.body?.appVersion || '').trim().slice(0, 50);
    const platform = String(req.body?.platform || 'Android').trim();
    const animeTitle = String(req.body?.animeTitle || '').trim().slice(0, 150);

    if (!title || !description) {
      return res.status(400).json({ error: 'Title and description are required' });
    }

    const id = `fb_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const report = {
      id,
      title,
      description,
      type,
      contact,
      appVersion,
      platform,
      animeTitle: animeTitle || null,
      createdAt: new Date().toISOString(),
      isResolved: false,
    };

    // Forward to GitHub Issues if token available
    const githubUrl = await forwardToGitHub(report);
    if (githubUrl) {
      report.githubIssueUrl = githubUrl;
    }

    // Persist in Redis / KV if configured
    try {
      await redis(['set', `anidash:feedback:${id}`, JSON.stringify(report), 'EX', '5184000']); // 60 days
      await redis(['lpush', 'anidash:feedback:ids', id]);
    } catch (_) {}

    return res.status(201).json({
      success: true,
      id,
      githubIssueUrl: githubUrl,
      message: 'Feedback received',
    });
  }

  if (req.method === 'GET') {
    if (!(await isAuthorizedAdmin(req))) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    try {
      const ids = await redis(['lrange', 'anidash:feedback:ids', '0', '99']);
      if (!Array.isArray(ids) || !ids.length) {
        return res.status(200).json({ reports: [] });
      }

      const reports = [];
      for (const id of ids) {
        const val = await redis(['get', `anidash:feedback:${id}`]);
        if (val) {
          try {
            reports.push(JSON.parse(val));
          } catch (_) {}
        }
      }
      return res.status(200).json({ reports });
    } catch (_) {
      return res.status(200).json({ reports: [] });
    }
  }

  if (req.method === 'DELETE') {
    if (!(await isAuthorizedAdmin(req))) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const id = String(req.query?.id || '').trim();
    if (!id) return res.status(400).json({ error: 'Missing report id' });

    try {
      await redis(['del', `anidash:feedback:${id}`]);
      await redis(['lrem', 'anidash:feedback:ids', '0', id]);
    } catch (_) {}

    return res.status(200).json({ success: true, message: 'Report removed' });
  }

  return res.status(405).json({ error: 'Method not allowed' });
}
