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
  try {
    const response = await fetch(`${url}/get/${encodeURIComponent(`anidash:chat:${id}`)}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;
    const value = (await response.json()).result;
    return value ? JSON.parse(value) : null;
  } catch {
    return null;
  }
}

async function animeMetadata(id) {
  if (!/^\d+$/.test(id)) return null;
  try {
    const response = await fetch('https://graphql.anilist.co', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        query: `query($id: Int) {
          Media(id: $id, type: ANIME) {
            id
            title { english romaji native }
            coverImage { extraLarge large }
            bannerImage
            description(asHtml: false)
            episodes
            format
            genres
            averageScore
          }
        }`,
        variables: { id: Number(id) },
      }),
    });
    if (!response.ok) return null;
    return (await response.json()).data?.Media || null;
  } catch {
    return null;
  }
}

function renderHtml({
  title,
  description,
  image,
  banner,
  canonical,
  deepLinkScheme,
  intentUri,
  id,
  isEpisode,
  episodeNum,
}) {
  const safeTitle = escapeHtml(title);
  const safeDescription = escapeHtml(description);
  const safeImage = escapeHtml(image || `${BASE}/assets/anidash_logo.png`);
  const safeBanner = escapeHtml(banner || image || `${BASE}/assets/anidash_logo.png`);
  const safeCanonical = escapeHtml(canonical);
  const safeDeepLink = escapeHtml(deepLinkScheme);
  const safeIntentUri = escapeHtml(intentUri);
  const webWatchUrl = isEpisode ? `${BASE}/watch?anime=${id}&ep=${episodeNum}` : `${BASE}/watch?anime=${id}`;
  const downloadUrl = `${BASE}/downloads`;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="theme-color" content="#10131b">
  <title>${safeTitle} · AniDash</title>
  <meta name="description" content="${safeDescription}">
  <link rel="canonical" href="${safeCanonical}">
  <link rel="icon" type="image/png" href="${BASE}/assets/anidash_logo.png">

  <!-- Open Graph -->
  <meta property="og:type" content="video.other">
  <meta property="og:site_name" content="AniDash">
  <meta property="og:title" content="${safeTitle}">
  <meta property="og:description" content="${safeDescription}">
  <meta property="og:image" content="${safeImage}">
  <meta property="og:url" content="${safeCanonical}">

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDescription}">
  <meta name="twitter:image" content="${safeImage}">

  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      min-height: 100vh;
      background: #090b10;
      color: #f0f2f8;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 16px;
      position: relative;
      overflow-x: hidden;
    }
    .bg-blur {
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image: url('${safeBanner}');
      background-size: cover;
      background-position: center;
      filter: blur(48px) brightness(0.18);
      transform: scale(1.15);
      z-index: 0;
      pointer-events: none;
    }
    .container {
      position: relative;
      z-index: 1;
      width: 100%;
      max-width: 480px;
      background: rgba(18, 22, 32, 0.88);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 24px;
      padding: 24px;
      box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
      text-align: center;
    }
    .brand-row {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      margin-bottom: 20px;
    }
    .brand-logo {
      width: 32px;
      height: 32px;
      border-radius: 8px;
    }
    .brand-title {
      font-size: 18px;
      font-weight: 800;
      letter-spacing: 0.5px;
      background: linear-gradient(135deg, #ffffff, #a5b4fc);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .badge {
      display: inline-block;
      padding: 3px 8px;
      border-radius: 6px;
      font-size: 10px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      background: rgba(249, 115, 22, 0.18);
      color: #fb923c;
      border: 1px solid rgba(249, 115, 22, 0.3);
      margin-bottom: 14px;
    }
    .poster-wrap {
      width: 130px;
      height: 185px;
      margin: 0 auto 16px;
      border-radius: 14px;
      overflow: hidden;
      box-shadow: 0 12px 30px rgba(0, 0, 0, 0.5);
      border: 1px solid rgba(255, 255, 255, 0.1);
    }
    .poster-wrap img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    h1 {
      font-size: 20px;
      font-weight: 700;
      line-height: 1.3;
      margin-bottom: 8px;
      color: #ffffff;
    }
    .subtitle {
      font-size: 13px;
      color: #94a3b8;
      line-height: 1.5;
      margin-bottom: 22px;
    }
    .loader-box {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 12px;
      padding: 12px 0;
    }
    .spinner {
      width: 32px;
      height: 32px;
      border: 3px solid rgba(99, 102, 241, 0.2);
      border-top-color: #6366f1;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    .opening-text {
      font-size: 13px;
      color: #c7d2fe;
      font-weight: 500;
    }
    .install-box {
      display: none;
      margin-top: 10px;
      animation: fadeIn 0.3s ease;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(6px); }
      to { opacity: 1; transform: translateY(0); }
    }
    .app-notice {
      background: rgba(30, 41, 59, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 14px;
      padding: 14px;
      margin-bottom: 18px;
      text-align: left;
    }
    .app-notice-title {
      font-size: 13px;
      font-weight: 700;
      color: #f8fafc;
      margin-bottom: 4px;
      display: flex;
      align-items: center;
      gap: 6px;
    }
    .app-notice-desc {
      font-size: 12px;
      color: #94a3b8;
      line-height: 1.45;
    }
    .actions {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      padding: 13px 18px;
      border-radius: 14px;
      font-size: 14px;
      font-weight: 700;
      text-decoration: none;
      cursor: pointer;
      transition: all 0.2s ease;
      border: none;
    }
    .btn-primary {
      background: linear-gradient(135deg, #4f46e5, #7c3aed);
      color: #ffffff;
      box-shadow: 0 4px 16px rgba(79, 70, 229, 0.35);
    }
    .btn-primary:hover {
      background: linear-gradient(135deg, #4338ca, #6d28d9);
      transform: translateY(-1px);
    }
    .btn-secondary {
      background: rgba(255, 255, 255, 0.08);
      color: #e2e8f0;
      border: 1px solid rgba(255, 255, 255, 0.1);
    }
    .btn-secondary:hover {
      background: rgba(255, 255, 255, 0.12);
    }
    .btn-ghost {
      background: transparent;
      color: #94a3b8;
      font-size: 12px;
      padding: 8px;
    }
    .btn-ghost:hover {
      color: #ffffff;
    }
  </style>
</head>
<body>
  <div class="bg-blur"></div>
  <main class="container">
    <div class="brand-row">
      <img src="${BASE}/assets/anidash_logo.png" class="brand-logo" alt="AniDash">
      <span class="brand-title">AniDash</span>
    </div>

    <div class="badge">Hindi Dub &amp; Sub · Multi-Quality</div>

    <div class="poster-wrap">
      <img src="${safeImage}" alt="${safeTitle}">
    </div>

    <h1>${safeTitle}</h1>
    <p class="subtitle">${safeDescription}</p>

    <div id="loaderBox" class="loader-box">
      <div class="spinner"></div>
      <div class="opening-text">Opening in AniDash app…</div>
    </div>

    <div id="installBox" class="install-box">
      <div class="app-notice">
        <div class="app-notice-title">
          <span>📱</span> Watch in Full HD on AniDash App
        </div>
        <div class="app-notice-desc">
          For the best experience with Hindi Dub, high-speed streaming, episode downloads, and tracking, install the free AniDash app.
        </div>
      </div>

      <div class="actions">
        <a id="downloadBtn" class="btn btn-primary" href="${downloadUrl}">
          <span>⬇️</span> Download AniDash App (APK)
        </a>
        <a class="btn btn-secondary" href="${webWatchUrl}">
          <span>▶️</span> Watch on Web Player
        </a>
        <a id="retryAppBtn" class="btn btn-ghost" href="${safeDeepLink}">
          Already installed? Tap here to open
        </a>
      </div>
    </div>
  </main>

  <script>
    (function() {
      var ua = navigator.userAgent || '';
      var isAndroid = /Android/i.test(ua);
      var isIOS = /iPhone|iPad|iPod/i.test(ua);
      var isMobile = isAndroid || isIOS;

      var params = new URLSearchParams(window.location.search);
      var isFallback = params.has('fallback') || params.has('no_redirect');

      var appUri = '${safeDeepLink}';
      var intentUri = '${safeIntentUri}';

      var loaderBox = document.getElementById('loaderBox');
      var installBox = document.getElementById('installBox');
      var retryAppBtn = document.getElementById('retryAppBtn');

      function showInstallView() {
        if (loaderBox) loaderBox.style.display = 'none';
        if (installBox) installBox.style.display = 'block';
      }

      // Configure retry button for Android
      if (retryAppBtn && isAndroid) {
        retryAppBtn.href = intentUri;
      }

      // If on desktop or came back via fallback redirect, show install view immediately
      if (!isMobile || isFallback) {
        showInstallView();
        return;
      }

      // Mobile user: attempt instant app launch
      var appLaunched = false;
      function markLaunched() {
        appLaunched = true;
      }
      window.addEventListener('pagehide', markLaunched);
      window.addEventListener('blur', markLaunched);
      document.addEventListener('visibilitychange', function() {
        if (document.hidden) markLaunched();
      });

      if (isAndroid) {
        // Android Intent: if com.anidash.anime is installed, launches directly!
        // If not installed, Android automatically falls back to browser_fallback_url (?fallback=1)
        window.location.href = intentUri;
      } else if (isIOS) {
        window.location.href = appUri;
      }

      // If document stays visible after 1.5 seconds, the app is not installed
      setTimeout(function() {
        if (!appLaunched && !document.hidden) {
          showInstallView();
        }
      }, 1500);
    })();
  </script>
</body>
</html>`;
}

export default async function handler(req, res) {
  const kind = String(req.query?.kind || '');
  const id = String(req.query?.id || '');
  const episode = String(req.query?.episode || '');

  let meta;
  if (kind === 'chat') {
    const chat = await sharedChat(id);
    const title = chat?.title || 'Shared AnyCore Chat';
    const fallbackUrl = `${BASE}/c/${id}?fallback=1`;
    meta = {
      id,
      title,
      description: 'A conversation shared from AnyCore in AniDash.',
      image: `${BASE}/assets/anidash_logo.png`,
      banner: `${BASE}/assets/anidash_logo.png`,
      canonical: `${BASE}/c/${id}`,
      deepLinkScheme: `anidash://c/${id}`,
      intentUri: `intent://c/${id}#Intent;scheme=anidash;package=com.anidash.anime;S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`,
      isEpisode: false,
    };
  } else {
    const anime = await animeMetadata(id);
    const title = anime?.title?.english || anime?.title?.romaji || anime?.title?.native || 'Anime';
    const count = anime?.episodes ? ` · ${anime.episodes} episodes` : '';
    const image = anime?.coverImage?.extraLarge || anime?.coverImage?.large;
    const banner = anime?.bannerImage || image;

    if (kind === 'episode') {
      const fallbackUrl = `${BASE}/episode/${id}/${episode}?fallback=1`;
      meta = {
        id,
        title: `${title} · Episode ${episode}`,
        description: `Watch Episode ${episode} of ${title} on AniDash${count}. Available in Full HD with Hindi Dub and English Sub.`,
        image,
        banner,
        canonical: `${BASE}/episode/${id}/${episode}`,
        deepLinkScheme: `anidash://episode/${id}/${episode}`,
        intentUri: `intent://episode/${id}/${episode}#Intent;scheme=anidash;package=com.anidash.anime;S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`,
        isEpisode: true,
        episodeNum: episode,
      };
    } else {
      const fallbackUrl = `${BASE}/anime/${id}?fallback=1`;
      meta = {
        id,
        title,
        description: `${anime?.format || 'Anime'}${count} · Watch in Full HD with Hindi Dub & English Sub on AniDash.`,
        image,
        banner,
        canonical: `${BASE}/anime/${id}`,
        deepLinkScheme: `anidash://anime/${id}`,
        intentUri: `intent://anime/${id}#Intent;scheme=anidash;package=com.anidash.anime;S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`,
        isEpisode: false,
      };
    }
  }

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=3600');
  return res.status(200).send(renderHtml(meta));
}
