/* AniDash Watch — rebuilt web client */
const $ = selector => document.querySelector(selector);
const app = $("#app");
const STORE = {
  watchlist: "anidash-watchlist-v2",
  progress: "anidash-progress-v2",
  providerMap: "anidash-provider-map-v2",
  settings: "anidash-watch-settings-v2"
};
const GRAPHQL = "https://graphql.anilist.co";
const API = "/api/anidash";
const MEDIA_FIELDS = "id idMal title{english romaji native userPreferred} synonyms coverImage{extraLarge large medium} bannerImage seasonYear season episodes duration format averageScore meanScore popularity favourites status isAdult description(asHtml:false) genres studios(isMain:true){nodes{name}} nextAiringEpisode{episode airingAt timeUntilAiring}";
const state = {
  view: "home",
  home: null,
  heroIndex: 0,
  heroTimer: null,
  cache: new Map(),
  current: null,
  provider: null,
  episodes: [],
  currentEpisode: null,
  streams: [],
  streamIndex: 0,
  hls: null,
  activeAudio: "sub",
  providerChoices: [],
  settings: loadSettings(),
  loadingToken: 0,
  lastSavedAt: 0
};

function loadSettings() {
  try { return Object.assign({ audio: "sub", autoNext: true, quality: "Auto" }, JSON.parse(localStorage.getItem(STORE.settings) || "{}")); }
  catch (_) { return { audio: "sub", autoNext: true, quality: "Auto" }; }
}
function saveSettings() {
  try { localStorage.setItem(STORE.settings, JSON.stringify(state.settings)); } catch (_) {}
}
function escapeHtml(value) {
  return String(value == null ? "" : value).replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[char]));
}
function titleOf(media) {
  return media && media.title ? (media.title.english || media.title.userPreferred || media.title.romaji || media.title.native || "Untitled") : (media && media.name) || "Untitled";
}
function coverOf(media) {
  return media && media.coverImage ? (media.coverImage.extraLarge || media.coverImage.large || media.coverImage.medium || "") : (media && (media.cover || media.poster)) || "";
}
function bannerOf(media) { return (media && media.bannerImage) || coverOf(media); }
function yearOf(media) { return (media && media.seasonYear) || ""; }
function scoreOf(media) { return media && media.averageScore ? (Number(media.averageScore) / 10).toFixed(1) : "—"; }
function normaliseTitle(value) {
  return String(value || "").toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
}
function unique(values) { return [...new Set((values || []).filter(Boolean))]; }
function readStore(key, fallback) {
  try { const value = JSON.parse(localStorage.getItem(key) || "null"); return Array.isArray(value) ? value : fallback; }
  catch (_) { return fallback; }
}
function writeStore(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch (_) { toast("This browser could not save local data."); }
}
function toast(message) {
  const root = $("#toastRoot");
  if (!root) return;
  const item = document.createElement("div");
  item.className = "toast";
  item.textContent = message;
  root.appendChild(item);
  setTimeout(() => item.remove(), 3200);
}
function setBusy(element, text) {
  if (element) element.innerHTML = '<div class="empty-state"><span class="loader-mark"></span><h2>' + escapeHtml(text || "Loading") + '</h2><p>Just a moment…</p></div>';
}
async function fetchJson(url, options, timeout) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout || 20000);
  try {
    const response = await fetch(url, Object.assign({}, options || {}, { signal: controller.signal }));
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || ("Request failed (" + response.status + ")"));
    return body;
  } catch (error) {
    if (error && error.name === "AbortError") throw new Error("The request timed out. Please try again.");
    throw error;
  } finally { clearTimeout(timer); }
}
async function aniList(query, variables) {
  const response = await fetchJson(GRAPHQL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({ query, variables: variables || {} })
  }, 22000);
  if (response.errors && response.errors.length) throw new Error(response.errors[0].message || "AniList request failed.");
  return response.data;
}
async function providerApi(params, timeout) {
  const query = new URLSearchParams(params);
  return fetchJson(API + "?" + query.toString(), null, timeout || 20000);
}
function rememberMedia(media) {
  if (!media || !media.id) return media;
  state.cache.set(String(media.id), media);
  return media;
}
function cacheMarkup() {
  return '<div class="empty-state"><span class="loader-mark"></span><h2>Loading AniDash</h2><p>Finding something good to watch.</p></div>';
}
function renderMeta(media) {
  return [
    media.format ? String(media.format).replace(/_/g, " ") : "",
    yearOf(media),
    media.episodes ? media.episodes + " eps" : "",
    media.status ? String(media.status).replace(/_/g, " ") : ""
  ].filter(Boolean).map(item => '<span class="meta-pill">' + escapeHtml(item) + '</span>').join("");
}
function posterCard(media, options) {
  rememberMedia(media);
  const title = titleOf(media);
  const cover = coverOf(media);
  const episode = options && options.episode ? '<span class="poster-episode">EP ' + escapeHtml(options.episode) + '</span>' : "";
  return '<button class="anime-card" type="button" data-open-anime="' + escapeHtml(media.id) + '" aria-label="Open ' + escapeHtml(title) + '">' +
    '<span class="poster-wrap"><img loading="lazy" src="' + escapeHtml(cover) + '" alt="' + escapeHtml(title) + '" onerror="this.style.opacity=.15"><span class="poster-gradient"></span>' +
    '<span class="poster-badge">' + escapeHtml(media.format || "ANIME") + '</span><span class="poster-score">★ ' + scoreOf(media) + '</span>' + episode + '</span>' +
    '<span class="card-title">' + escapeHtml(title) + '</span><span class="card-sub"><span>' + escapeHtml(yearOf(media) || "Anime") + '</span><span>' + escapeHtml(media.status === "RELEASING" ? "Airing" : (media.episodes ? media.episodes + " eps" : "Explore")) + '</span></span></button>';
}
function railSection(name, items, subtitle) {
  if (!items || !items.length) return "";
  return '<section class="section"><div class="section-head"><div><h2>' + escapeHtml(name) + '</h2>' + (subtitle ? '<p>' + escapeHtml(subtitle) + '</p>' : '') + '</div><button class="section-link" type="button" data-section="' + escapeHtml(name) + '">Explore more ↗</button></div><div class="rail">' + items.map(item => posterCard(item)).join("") + '</div></section>';
}
function heroSlide(media, index, count) {
  const synopsis = String(media.description || "Discover the story, characters and episodes behind this series.").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  return '<div class="hero-image" style="background-image:url(&quot;' + escapeHtml(bannerOf(media)) + '&quot;)"></div>' +
    '<div class="hero-content"><span class="eyebrow"><i class="live-dot"></i> ANIDASH SPOTLIGHT · ' + (index + 1) + '</span>' +
    '<h1>' + escapeHtml(titleOf(media)) + '</h1><div class="hero-meta"><span class="meta-pill">★ ' + scoreOf(media) + '</span>' + renderMeta(media) + '</div>' +
    '<p class="hero-copy">' + escapeHtml(synopsis) + '</p><div class="hero-actions">' +
    '<button class="btn btn-primary" type="button" data-watch-first="' + media.id + '">▶ &nbsp;Start watching</button>' +
    '<button class="btn btn-secondary" type="button" data-open-anime="' + media.id + '">View details&nbsp; ↗</button></div></div>' +
    '<div class="hero-dots">' + Array.from({ length: count }, (_, i) => '<button type="button" data-hero-dot="' + i + '" class="' + (i === index ? "active" : "") + '" aria-label="Spotlight ' + (i + 1) + '"></button>').join("") + '</div>';
}
function renderContinueRail() {
  const list = readStore(STORE.progress, []).filter(item => item && item.progressSeconds > 0 && (!item.durationSeconds || item.progressSeconds / item.durationSeconds < .94)).sort((a, b) => (b.time || 0) - (a.time || 0)).slice(0, 12);
  if (!list.length) return "";
  return '<section class="section"><div class="section-head"><div><h2>Pick up where you left off</h2><p>Your recent episodes, saved on this device</p></div><a class="section-link" href="#history">View history ↗</a></div><div class="rail continue-rail">' +
    list.map(item => {
      const percent = item.durationSeconds ? Math.max(2, Math.min(100, item.progressSeconds / item.durationSeconds * 100)) : 8;
      return '<button class="continue-card" type="button" data-resume="' + escapeHtml(item.id) + '" data-episode="' + escapeHtml(item.episode) + '">' +
        '<img loading="lazy" src="' + escapeHtml(item.cover || "") + '" alt=""><span><b>' + escapeHtml(item.title || "Continue watching") + '</b><small>Episode ' + escapeHtml(item.episode || "?") + ' · ' + escapeHtml(item.episodeTitle || "Resume episode") + '</small><span class="card-progress"><span style="width:' + percent.toFixed(1) + '%"></span></span></span></button>';
    }).join("") + '</div></section>';
}
function seasonNow() {
  const month = new Date().getMonth() + 1;
  return { season: month <= 3 ? "WINTER" : month <= 6 ? "SPRING" : month <= 9 ? "SUMMER" : "FALL", year: new Date().getFullYear() };
}
async function loadHome() {
  state.view = "home";
  updateNavigation("home");
  app.innerHTML = cacheMarkup();
  try {
    const current = seasonNow();
    const query = "query($season:MediaSeason,$year:Int){trending:Page(page:1,perPage:12){media(type:ANIME,sort:TRENDING_DESC){ " + MEDIA_FIELDS + " }} popular:Page(page:1,perPage:12){media(type:ANIME,sort:POPULARITY_DESC){ " + MEDIA_FIELDS + " }} top:Page(page:1,perPage:12){media(type:ANIME,sort:SCORE_DESC){ " + MEDIA_FIELDS + " }} seasonal:Page(page:1,perPage:12){media(type:ANIME,season:$season,seasonYear:$year,sort:POPULARITY_DESC){ " + MEDIA_FIELDS + " }} upcoming:Page(page:1,perPage:12){media(type:ANIME,status:NOT_YET_RELEASED,sort:POPULARITY_DESC){ " + MEDIA_FIELDS + " }}}";
    const data = await aniList(query, { season: current.season, year: current.year });
    state.home = {
      trending: data.trending.media.filter(item => !item.isAdult),
      popular: data.popular.media.filter(item => !item.isAdult),
      top: data.top.media.filter(item => !item.isAdult),
      seasonal: data.seasonal.media.filter(item => !item.isAdult),
      upcoming: data.upcoming.media.filter(item => !item.isAdult)
    };
    const heroes = state.home.trending.slice(0, 5);
    if (state.heroTimer) clearInterval(state.heroTimer);
    app.innerHTML = '<section class="hero" id="spotlightHero"></section>' + renderContinueRail() +
      railSection("Trending this week", state.home.trending, "The shows anime fans are talking about") +
      railSection(current.season.charAt(0) + current.season.slice(1).toLowerCase() + " " + current.year, state.home.seasonal, "Fresh releases from the current season") +
      railSection("Popular anime", state.home.popular, "A good place to start") +
      railSection("All-time favourites", state.home.top, "Highly rated by the AniList community") +
      railSection("Coming soon", state.home.upcoming, "Get ready for what is next");
    renderHero(heroes);
    if (heroes.length > 1) {
      state.heroTimer = setInterval(() => {
        if (state.view !== "home" || document.hidden) return;
        state.heroIndex = (state.heroIndex + 1) % heroes.length;
        renderHero(heroes);
      }, 6500);
    }
  } catch (error) {
    app.innerHTML = '<div class="empty-state"><span class="empty-icon">✦</span><h2>Could not load AniDash</h2><p>' + escapeHtml(error.message) + '</p><button class="btn btn-primary" type="button" data-action="retry-home">Try again</button></div>';
  }
}
function renderHero(heroes) {
  if (!heroes || !heroes.length) return;
  state.heroIndex = state.heroIndex % heroes.length;
  const hero = $("#spotlightHero");
  if (hero) hero.innerHTML = heroSlide(heroes[state.heroIndex], state.heroIndex, heroes.length);
}
function updateNavigation(active) {
  document.querySelectorAll("[data-nav]").forEach(link => link.classList.toggle("active", link.dataset.nav === active));
  const profile = $("#profileShortcut");
  if (profile) profile.classList.toggle("active", active === "watchlist" || active === "history");
}
function pageHeading(title, description, right) {
  return '<header class="page-heading"><div><h1>' + escapeHtml(title) + '</h1><p>' + escapeHtml(description || "") + '</p></div>' + (right || "") + '</header>';
}
function renderExploreShell(title, description) {
  return pageHeading(title, description) +
    '<div class="filters" id="formatFilters"><button class="filter active" data-format="ALL">All titles</button><button class="filter" data-format="TV">TV series</button><button class="filter" data-format="MOVIE">Movies</button><button class="filter" data-format="OVA">OVA</button><button class="filter" data-format="ONA">ONA</button></div>' +
    '<div class="filters" id="sortFilters"><button class="filter active" data-sort="TRENDING_DESC">Trending</button><button class="filter" data-sort="POPULARITY_DESC">Popular</button><button class="filter" data-sort="SCORE_DESC">Top rated</button><button class="filter" data-sort="START_DATE_DESC">Newest</button></div>' +
    '<div id="exploreStatus" class="subtle"></div><div class="poster-grid" id="exploreGrid"></div>';
}
const exploreState = { format: "ALL", sort: "TRENDING_DESC", genre: "", query: "" };
async function loadExplore(query) {
  state.view = "explore";
  updateNavigation("explore");
  exploreState.query = query || "";
  app.innerHTML = renderExploreShell(query ? "Search results" : "Explore anime", query ? 'Results for "' + query + '"' : "Find your next favourite series.");
  if (query) {
    await runAnimeSearch(query);
  } else {
    await fetchExplore();
  }
}
async function fetchExplore() {
  const status = $("#exploreStatus");
  const grid = $("#exploreGrid");
  if (!grid) return;
  status.textContent = "Loading anime…";
  grid.innerHTML = "";
  document.querySelectorAll("[data-format]").forEach(button => button.classList.toggle("active", button.dataset.format === exploreState.format));
  document.querySelectorAll("[data-sort]").forEach(button => button.classList.toggle("active", button.dataset.sort === exploreState.sort));
  try {
    let filter = 'type:ANIME,sort:' + exploreState.sort;
    if (exploreState.format !== "ALL") filter += ',format:' + exploreState.format;
    if (exploreState.genre) filter += ',genre:"' + exploreState.genre.replace(/"/g, "") + '"';
    const query = "query{Page(page:1,perPage:48){media(" + filter + "){" + MEDIA_FIELDS + "}}}";
    const data = await aniList(query);
    const items = data.Page.media.filter(item => !item.isAdult);
    grid.innerHTML = items.map(item => posterCard(item)).join("");
    status.textContent = items.length + " titles";
  } catch (error) { status.textContent = error.message; }
}
async function runAnimeSearch(query) {
  const clean = String(query || "").trim();
  const status = $("#exploreStatus");
  const grid = $("#exploreGrid");
  if (!clean || !grid) return;
  status.textContent = "Searching AniList…";
  grid.innerHTML = "";
  try {
    const data = await aniList("query($search:String){Page(page:1,perPage:48){media(type:ANIME,search:$search,sort:SEARCH_MATCH){" + MEDIA_FIELDS + "}}}", { search: clean });
    const items = data.Page.media.filter(item => !item.isAdult);
    grid.innerHTML = items.map(item => posterCard(item)).join("");
    status.textContent = items.length ? items.length + " results for " + clean : "No matching anime found. Try another title.";
  } catch (error) { status.textContent = error.message; }
}
async function loadSchedule() {
  state.view = "schedule";
  updateNavigation("schedule");
  app.innerHTML = renderExploreShell("Airing now", "Currently releasing anime, updated from AniList.");
  exploreState.format = "ALL";
  exploreState.sort = "UPDATED_AT_DESC";
  const status = $("#exploreStatus");
  const grid = $("#exploreGrid");
  status.textContent = "Loading the release schedule…";
  try {
    const data = await aniList("query{Page(page:1,perPage:48){media(type:ANIME,status:RELEASING,sort:UPDATED_AT_DESC){" + MEDIA_FIELDS + "}}}");
    const items = data.Page.media.filter(item => !item.isAdult);
    grid.innerHTML = items.map(item => posterCard(item)).join("");
    status.textContent = items.length + " currently airing titles";
  } catch (error) { status.textContent = error.message; }
}
async function getMediaById(id) {
  if (state.cache.has(String(id))) return state.cache.get(String(id));
  const data = await aniList("query($id:Int){Media(id:$id,type:ANIME){" + MEDIA_FIELDS + " characters(sort:ROLE,perPage:12){nodes{id name{full}image{large}}} relations{edges{relationType(version:2)node{id type title{english romaji native}coverImage{large}format}}}}}", { id: Number(id) });
  if (!data.Media) throw new Error("Anime title was not found.");
  return rememberMedia(data.Media);
}
function providerMap() { try { return JSON.parse(localStorage.getItem(STORE.providerMap) || "{}"); } catch (_) { return {}; } }
function saveProviderMap(mediaId, provider) {
  const map = providerMap();
  map[String(mediaId)] = { id: String(provider.id), title: provider.title, updatedAt: Date.now() };
  try { localStorage.setItem(STORE.providerMap, JSON.stringify(map)); } catch (_) {}
}
function mappedProvider(mediaId) { return providerMap()[String(mediaId)] || null; }
function detailMarkup(media) {
  const title = titleOf(media);
  const cover = coverOf(media);
  const studios = media.studios && media.studios.nodes ? media.studios.nodes.map(item => item.name).join(", ") : "";
  const synopsis = String(media.description || "No synopsis has been added yet.").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  const watched = readStore(STORE.watchlist, []).some(item => String(item.id) === String(media.id));
  return '<section class="detail-hero"><div class="detail-backdrop" style="background-image:url(&quot;' + escapeHtml(bannerOf(media)) + '&quot;)"></div><div class="detail-main">' +
    '<img class="detail-cover" src="' + escapeHtml(cover) + '" alt="' + escapeHtml(title) + '">' +
    '<div class="detail-info"><span class="eyebrow"><i class="live-dot"></i> ANIME DETAILS</span><h1>' + escapeHtml(title) + '</h1>' +
    '<div class="detail-facts">' + renderMeta(media) + '<span class="meta-pill">★ ' + scoreOf(media) + '</span>' + (media.idMal ? '<a class="meta-pill" href="https://myanimelist.net/anime/' + media.idMal + '" target="_blank" rel="noopener">MAL ↗</a>' : "") + '</div>' +
    '<p class="synopsis">' + escapeHtml(synopsis) + '</p><div class="detail-actions"><button class="btn btn-primary" type="button" data-action="load-episodes">▶ &nbsp;Choose episode</button>' +
    '<button class="btn btn-secondary" type="button" data-action="toggle-watchlist">' + (watched ? "✓ In my library" : "＋ Add to library") + '</button></div></div></div></section>' +
    '<section class="detail-content"><div class="panel"><div class="episode-toolbar"><strong>Episodes</strong><span id="episodeCount" class="subtle">Choose an episode to load the list</span></div><div id="providerStatus" class="provider-note">AniDash will find this title in the available streaming catalogue when you open the episode list.</div><div id="providerChoices" class="provider-list"></div><div id="episodeList" class="episode-grid"></div></div>' +
    '<aside class="panel"><h2>About this anime</h2><p><b>Genres</b><br>' + escapeHtml((media.genres || []).join(" · ") || "Not listed") + '</p><p><b>Studio</b><br>' + escapeHtml(studios || "Not listed") + '</p><p><b>Format</b><br>' + escapeHtml(media.format || "Not listed") + '</p><p><b>Episodes</b><br>' + escapeHtml(media.episodes || "To be announced") + '</p></aside></section>';
}
async function showAnime(id) {
  state.view = "anime";
  state.current = null;
  state.provider = null;
  state.currentEpisode = null;
  state.streams = [];
  state.episodes = [];
  state.providerChoices = [];
  updateNavigation("");
  app.innerHTML = cacheMarkup();
  try {
    const media = await getMediaById(id);
    state.current = media;
    app.innerHTML = detailMarkup(media);
    if (mappedProvider(media.id)) {
      $("#providerStatus").textContent = "Streaming catalogue match saved for this title. Load episodes when ready.";
    }
  } catch (error) {
    app.innerHTML = '<div class="empty-state"><h2>Could not open this anime</h2><p>' + escapeHtml(error.message) + '</p><a class="btn btn-secondary" href="#home">Back home</a></div>';
  }
}
function candidateArrays(payload) {
  const output = [];
  const visited = new Set();
  function walk(node, depth) {
    if (!node || depth > 5 || typeof node !== "object" || visited.has(node)) return;
    visited.add(node);
    if (Array.isArray(node)) {
      if (node.some(item => item && typeof item === "object" && (item.title || item.name || item.animeTitle || item.id))) output.push(node);
      else node.forEach(item => walk(item, depth + 1));
      return;
    }
    Object.keys(node).forEach(key => walk(node[key], depth + 1));
  }
  walk(payload, 0);
  return output.flat();
}
function providerTitle(item) {
  const raw = item && (item.title || item.name || item.animeTitle || item.anime_name || item.jname || item.japaneseName);
  if (typeof raw === "string") return raw;
  if (raw && typeof raw === "object") return raw.english || raw.romaji || raw.native || raw.userPreferred || "";
  return "";
}
function providerId(item) {
  const raw = item && (item.id != null ? item.id : item.animeId != null ? item.animeId : item.anime_id != null ? item.anime_id : item.animeID != null ? item.animeID : item.providerId);
  return /^\d+$/.test(String(raw == null ? "" : raw)) ? String(raw) : "";
}
function similarity(left, right) {
  const a = normaliseTitle(left);
  const b = normaliseTitle(right);
  if (!a || !b) return 0;
  if (a === b) return 1;
  if (a.includes(b) || b.includes(a)) return Math.min(a.length, b.length) / Math.max(a.length, b.length) * .25 + .62;
  const aa = new Set(a.split(" "));
  const bb = new Set(b.split(" "));
  let overlap = 0;
  aa.forEach(token => { if (bb.has(token)) overlap++; });
  return overlap / Math.max(aa.size, bb.size);
}
function mediaAliases(media) {
  return unique([
    titleOf(media), media.title && media.title.english, media.title && media.title.romaji,
    media.title && media.title.native, ...(media.synonyms || [])
  ]).filter(value => typeof value === "string" && value.trim());
}
async function findProviderTitle(media) {
  const saved = mappedProvider(media.id);
  if (saved && saved.id) return saved;
  const aliases = mediaAliases(media);
  const attempts = unique(aliases.slice(0, 3));
  if (!attempts.length) throw new Error("This anime has no searchable title.");
  let candidates = [];
  for (const term of attempts) {
    const payload = await providerApi({ action: "search", query: term, page: "1" }, 15000);
    candidates = candidateArrays(payload).map(item => ({
      id: providerId(item),
      title: providerTitle(item),
      image: item.poster || item.image || item.cover || "",
      raw: item
    })).filter(item => item.id && item.title);
    if (candidates.length) break;
  }
  if (!candidates.length) throw new Error("The streaming catalogue returned no matching titles. The provider may be temporarily unavailable.");
  candidates = candidates.map(candidate => {
    const score = Math.max(...aliases.map(alias => similarity(candidate.title, alias)));
    return Object.assign({}, candidate, { score });
  }).sort((a, b) => b.score - a.score);
  state.providerChoices = candidates.slice(0, 5);
  const best = candidates[0];
  if (!best || best.score < .42) throw new Error("AniDash could not confidently match this AniList title with the streaming catalogue. Check the title before trying another match.");
  if (candidates.length > 1 && best.score - candidates[1].score < .035 && best.score < .98) {
    throw new Error("More than one streaming title looks similar. Choose the correct match below.");
  }
  const result = { id: best.id, title: best.title, image: best.image };
  saveProviderMap(media.id, result);
  return result;
}
function extractEpisodes(payload) {
  const direct = payload && (payload.episodes || payload.data && payload.data.episodes || payload.results || payload.items);
  if (Array.isArray(direct)) return direct;
  const arrays = candidateArrays(payload);
  return arrays.filter(item => item && (item.number != null || item.episodeNumber != null || item.episode != null || item.episodeId != null));
}
function normaliseEpisodes(payload) {
  const raw = extractEpisodes(payload);
  return raw.map((item, index) => {
    const number = item.number != null ? item.number : item.episodeNumber != null ? item.episodeNumber : item.episode != null ? item.episode : index + 1;
    return {
      number: String(number),
      title: item.title || item.name || item.episodeTitle || ("Episode " + number),
      image: item.image || item.thumbnail || item.poster || "",
      description: item.description || "",
      raw: item
    };
  }).filter(item => /^\d+(\.\d+)?$/.test(item.number)).sort((a, b) => Number(a.number) - Number(b.number));
}
async function loadEpisodeList() {
  const media = state.current;
  if (!media) return;
  const status = $("#providerStatus");
  const list = $("#episodeList");
  const choices = $("#providerChoices");
  status.textContent = "Matching this anime with the streaming catalogue…";
  list.innerHTML = "";
  choices.innerHTML = "";
  try {
    const provider = await findProviderTitle(media);
    state.provider = provider;
    status.textContent = "Matched with " + provider.title + ". Loading episode list…";
    const payload = await providerApi({ action: "episodes", id: provider.id, page: "1" }, 20000);
    const episodes = normaliseEpisodes(payload);
    if (!episodes.length) throw new Error("The provider matched this anime but did not return any episodes.");
    state.episodes = episodes;
    const totalPages = Number(payload.totalPages || payload.pageInfo && payload.pageInfo.lastPage || payload.pagination && payload.pagination.totalPages || 1);
    status.textContent = episodes.length + " episodes loaded · " + provider.title;
    $("#episodeCount").textContent = (Number.isFinite(totalPages) && totalPages > 1 ? "Page 1 of " + totalPages + " · " : "") + episodes.length + " episodes";
    renderEpisodeGrid();
    if (totalPages > 1) loadMoreEpisodePages(provider, totalPages, episodes);
  } catch (error) {
    status.textContent = error.message;
    if (state.providerChoices.length) renderProviderChoices();
  }
}
async function loadMoreEpisodePages(provider, totalPages, firstPage) {
  const maxPages = Math.min(30, totalPages);
  if (maxPages <= 1) return;
  const pages = Array.from({ length: maxPages - 1 }, (_, index) => index + 2);
  for (const page of pages) {
    if (!state.current || !state.provider || state.provider.id !== provider.id) return;
    try {
      const payload = await providerApi({ action: "episodes", id: provider.id, page: String(page) }, 18000);
      const more = normaliseEpisodes(payload);
      const byNumber = new Map(state.episodes.map(item => [item.number, item]));
      more.forEach(item => byNumber.set(item.number, item));
      state.episodes = [...byNumber.values()].sort((a, b) => Number(a.number) - Number(b.number));
      renderEpisodeGrid();
      $("#episodeCount").textContent = state.episodes.length + " episodes loaded";
    } catch (_) { break; }
  }
}
function renderProviderChoices() {
  const root = $("#providerChoices");
  if (!root) return;
  root.innerHTML = '<p class="subtle">Choose the correct streaming catalogue match:</p>' + state.providerChoices.map((item, index) =>
    '<button class="provider-choice" type="button" data-provider-choice="' + index + '"><span><b>' + escapeHtml(item.title) + '</b><small>Match confidence ' + Math.round(item.score * 100) + '%</small></span><span>Use this ↗</span></button>'
  ).join("");
}
async function chooseProvider(index) {
  const candidate = state.providerChoices[index];
  if (!candidate || !state.current) return;
  const provider = { id: candidate.id, title: candidate.title, image: candidate.image };
  saveProviderMap(state.current.id, provider);
  state.provider = provider;
  const status = $("#providerStatus");
  if (status) status.textContent = "Matched " + provider.title + ". Loading episodes…";
  $("#providerChoices").innerHTML = "";
  try {
    const payload = await providerApi({ action: "episodes", id: provider.id, page: "1" }, 20000);
    state.episodes = normaliseEpisodes(payload);
    if (!state.episodes.length) throw new Error("No episodes returned for this match.");
    $("#episodeCount").textContent = state.episodes.length + " episodes";
    if (status) status.textContent = "Streaming catalogue: " + provider.title;
    renderEpisodeGrid();
  } catch (error) { if (status) status.textContent = error.message; }
}
function renderEpisodeGrid() {
  const list = $("#episodeList");
  if (!list) return;
  const active = state.currentEpisode ? String(state.currentEpisode.number) : "";
  list.innerHTML = state.episodes.map((episode, index) =>
    '<button class="episode-btn ' + (episode.number === active ? "active" : "") + '" type="button" data-play-episode="' + index + '"><b>EP ' + escapeHtml(episode.number) + '</b><small>' + escapeHtml(episode.title) + '</small></button>'
  ).join("");
}
function setWatchlist(media) {
  const list = readStore(STORE.watchlist, []);
  const index = list.findIndex(item => String(item.id) === String(media.id));
  if (index >= 0) list.splice(index, 1);
  else list.unshift({ id: media.id, idMal: media.idMal, title: titleOf(media), cover: coverOf(media), year: yearOf(media), format: media.format, addedAt: Date.now() });
  writeStore(STORE.watchlist, list);
  toast(index >= 0 ? "Removed from your library." : "Added to your library.");
  if (state.view === "anime") showAnime(media.id);
}
function loadWatchlist() {
  state.view = "watchlist";
  updateNavigation("watchlist");
  const list = readStore(STORE.watchlist, []);
  app.innerHTML = pageHeading("My library", "The anime you have saved to come back to.") +
    (list.length ? '<div class="poster-grid">' + list.map(item => posterCard({ id: item.id, idMal: item.idMal, title: { english: item.title }, coverImage: { large: item.cover }, seasonYear: item.year, format: item.format })).join("") + '</div>' :
      '<div class="empty-state"><span class="empty-icon">＋</span><h2>Your library is waiting</h2><p>Add anime to your library and it will be easy to find here.</p><a class="btn btn-primary" href="#explore">Explore anime</a></div>');
}
function loadHistory() {
  state.view = "history";
  updateNavigation("history");
  const list = readStore(STORE.progress, []).sort((a, b) => (b.time || 0) - (a.time || 0));
  app.innerHTML = pageHeading("Watch history", "Episodes you have started on this browser.", '<button class="btn btn-quiet btn-small" data-action="clear-history">Clear history</button>') +
    (list.length ? '<div class="history-list">' + list.map(item =>
      '<button class="history-row" type="button" data-resume="' + escapeHtml(item.id) + '" data-episode="' + escapeHtml(item.episode) + '"><img src="' + escapeHtml(item.cover || "") + '" alt=""><span><b>' + escapeHtml(item.title) + '</b><small>Episode ' + escapeHtml(item.episode) + ' · ' + escapeHtml(item.episodeTitle || "") + '</small><small>' + escapeHtml(new Date(item.time || Date.now()).toLocaleString()) + '</small></span><span>Continue ↗</span></button>'
    ).join("") + '</div>' : '<div class="empty-state"><span class="empty-icon">◷</span><h2>No watch history yet</h2><p>Start an episode and AniDash will keep your progress on this device.</p><a class="btn btn-primary" href="#explore">Find anime</a></div>');
}
function getProgress(id, episode) {
  return readStore(STORE.progress, []).find(item => String(item.id) === String(id) && String(item.episode) === String(episode)) || null;
}
function saveProgress(force) {
  const video = $("#video");
  if (!video || !state.current || !state.currentEpisode || !state.provider) return;
  const now = Date.now();
  if (!force && now - state.lastSavedAt < 8000) return;
  state.lastSavedAt = now;
  const list = readStore(STORE.progress, []);
  const entry = {
    id: state.current.id,
    idMal: state.current.idMal,
    providerId: state.provider.id,
    title: titleOf(state.current),
    cover: coverOf(state.current),
    episode: state.currentEpisode.number,
    episodeTitle: state.currentEpisode.title,
    progressSeconds: Math.max(0, Math.floor(video.currentTime || 0)),
    durationSeconds: Number.isFinite(video.duration) ? Math.floor(video.duration) : 0,
    time: now
  };
  const existing = list.findIndex(item => String(item.id) === String(entry.id) && String(item.episode) === String(entry.episode));
  if (existing >= 0) list.splice(existing, 1);
  list.unshift(entry);
  writeStore(STORE.progress, list.slice(0, 80));
}
function updatePlayerStatus(message) {
  const status = $("#playerStatus");
  if (status) status.textContent = message || "";
}
function destroyPlayer() {
  if (state.hls) {
    try { state.hls.destroy(); } catch (_) {}
    state.hls = null;
  }
  const video = $("#video");
  if (video) {
    try { video.pause(); } catch (_) {}
    video.removeAttribute("src");
    video.querySelectorAll("track").forEach(track => track.remove());
    try { video.load(); } catch (_) {}
  }
}
function mediaUrl(raw) {
  if (!raw) return "";
  const value = String(raw);
  if (value.startsWith("/") || value.startsWith("blob:")) return value;
  if (/^https:\/\//i.test(value)) return "/api/media?url=" + encodeURIComponent(value);
  return "";
}
function normaliseTracks(tracks) {
  return (Array.isArray(tracks) ? tracks : []).map(track => ({
    label: track.label || track.lang || track.language || "Subtitle",
    lang: track.lang || track.language || "en",
    kind: track.kind === "subtitles" ? "subtitles" : "captions",
    url: mediaUrl(track.url || track.file)
  })).filter(track => track.url);
}
async function resolveStreams(episode, audio) {
  const provider = state.provider;
  if (!provider) throw new Error("No streaming catalogue match has been selected.");
  return providerApi({ action: "source", id: provider.id, episode: episode.number, audio: audio }, 26000);
}
function sourceIsHls(source) {
  return source && (source.isM3U8 === true || /\\.m3u8(?:$|\\?)/i.test(source.url || ""));
}
function sourceList(payload) {
  return (payload.sources || []).filter(source => source && source.url).map(source => Object.assign({}, source, { url: mediaUrl(source.url) })).filter(source => source.url);
}
function renderWatchPage() {
  const media = state.current;
  const episode = state.currentEpisode;
  if (!media || !episode) return;
  app.innerHTML = '<div class="watch-head"><div><a class="section-link" href="#anime/' + media.id + '">← Back to anime</a><h1>' + escapeHtml(titleOf(media)) + '</h1><p>Episode ' + escapeHtml(episode.number) + ' · ' + escapeHtml(episode.title) + '</p></div><button class="btn btn-quiet btn-small" type="button" data-action="watchlist-from-player">＋ Library</button></div>' +
    '<div class="watch-layout"><section class="player-column"><div class="player-frame" id="playerFrame"><video id="video" controls playsinline webkit-playsinline preload="metadata" poster="' + escapeHtml(bannerOf(media)) + '"></video><div class="player-overlay" id="playerOverlay"><div class="player-loading"><span class="player-spinner"></span><b>Preparing your episode…</b></div></div><div class="player-error" id="playerError" hidden><b>Playback could not start</b><p id="playerErrorText">The selected stream is unavailable.</p><button class="btn btn-primary btn-small" data-action="retry-stream">Try again</button></div></div>' +
    '<div class="player-controls"><span class="control-label">Audio</span><div class="segmented" id="audioSwitch"><button type="button" data-audio="sub" class="' + (state.activeAudio === "sub" ? "active" : "") + '">SUB</button><button type="button" data-audio="dub" class="' + (state.activeAudio === "dub" ? "active" : "") + '">DUB</button></div><span class="control-label">Server</span><select class="control-select" id="serverSelect" aria-label="Streaming server"><option>Loading…</option></select><span class="control-label">Quality</span><select class="control-select" id="qualitySelect" aria-label="Video quality"><option>Auto</option></select><label class="control-label"><input type="checkbox" id="autoNextToggle" ' + (state.settings.autoNext ? "checked" : "") + '> Auto next</label></div>' +
    '<h2 class="player-title">' + escapeHtml(episode.title) + '</h2><p class="player-subtitle">' + escapeHtml(titleOf(media)) + ' · ' + escapeHtml(episode.number) + ' / ' + escapeHtml(state.episodes.length) + ' episodes</p><div class="watch-note">Playback availability depends on the connected provider and the browser-supported media format. Your progress is saved locally on this device.</div></section>' +
    '<aside class="panel episode-sidebar"><div class="episode-sidebar-head"><b>Episodes</b><span class="subtle">' + state.episodes.length + ' total</span></div><div class="episode-sidebar-list" id="watchEpisodeList">' + state.episodes.map((item, index) =>
      '<button class="episode-row ' + (String(item.number) === String(episode.number) ? "active" : "") + '" type="button" data-watch-index="' + index + '"><span class="episode-thumb">' + escapeHtml(item.number) + '</span><span><b>' + escapeHtml(item.title) + '</b><small>Episode ' + escapeHtml(item.number) + '</small></span></button>'
    ).join("") + '</div></aside></div>';
}
async function playCurrentEpisode(retry) {
  const video = $("#video");
  if (!video || !state.currentEpisode) return;
  const token = ++state.loadingToken;
  destroyPlayer();
  $("#playerOverlay").hidden = false;
  $("#playerError").hidden = true;
  updatePlayerStatus("Resolving stream…");
  try {
    const payload = await resolveStreams(state.currentEpisode, state.activeAudio);
    if (token !== state.loadingToken) return;
    const sources = sourceList(payload);
    if (!sources.length) throw new Error("No browser-playable " + state.activeAudio.toUpperCase() + " stream was returned for this episode.");
    state.streams = sources;
    state.streamIndex = 0;
    const tracks = normaliseTracks(payload.subtitles || []);
    state.lastTracks = tracks;
    video.querySelectorAll("track").forEach(track => track.remove());
    tracks.forEach(track => {
      const element = document.createElement("track");
      element.kind = track.kind;
      element.label = track.label;
      element.srclang = track.lang;
      element.src = track.url;
      video.appendChild(element);
    });
    populateServerSelect();
    populateQualitySelect();
    await attachStream(sources[0], token);
  } catch (error) {
    if (token !== state.loadingToken) return;
    $("#playerOverlay").hidden = true;
    $("#playerError").hidden = false;
    $("#playerErrorText").textContent = error.message;
    updatePlayerStatus("Stream unavailable");
  }
}
function populateServerSelect() {
  const select = $("#serverSelect");
  if (!select) return;
  const active = state.streams[state.streamIndex];
  select.innerHTML = state.streams.map((source, index) => '<option value="' + index + '">' + escapeHtml(source.server || source.type || "Server " + (index + 1)) + (source.quality ? " · " + escapeHtml(source.quality) : "") + '</option>').join("");
  select.value = String(state.streamIndex);
  if (active) updatePlayerStatus((active.server || active.type || "Server") + " · " + (active.quality || "Auto"));
}
function populateQualitySelect() {
  const select = $("#qualitySelect");
  if (!select) return;
  select.dataset.hls = "0";
  const values = unique(["Auto"].concat(state.streams.map(source => source.quality).filter(Boolean)));
  select.innerHTML = values.map(value => '<option value="' + escapeHtml(value) + '">' + escapeHtml(value) + '</option>').join("");
  select.value = "Auto";
}
function populateHlsQualitySelect(hls) {
  const select = $("#qualitySelect");
  if (!select || !hls || !hls.levels || !hls.levels.length) return;
  select.dataset.hls = "1";
  const levels = hls.levels.map((level, index) => ({ index, height: Number(level.height) || 0, bitrate: Number(level.bitrate) || 0 }));
  levels.sort((a, b) => b.height - a.height || b.bitrate - a.bitrate);
  select.innerHTML = '<option value="-1">Auto</option>' + levels.map(level =>
    '<option value="' + level.index + '">' + (level.height ? level.height + 'p' : Math.round(level.bitrate / 1000) + ' kbps') + '</option>'
  ).join("");
  select.value = "-1";
}
async function attachStream(source, token) {
  const video = $("#video");
  if (!video || !source || token !== state.loadingToken) return;
  if (state.hls) { try { state.hls.destroy(); } catch (_) {} state.hls = null; }
  populateQualitySelect();
  video.pause();
  video.removeAttribute("src");
  video.querySelectorAll("track").forEach(track => track.remove());
  const payloadTracks = state.lastTracks || [];
  payloadTracks.forEach(track => {
    const element = document.createElement("track");
    element.kind = track.kind;
    element.label = track.label;
    element.srclang = track.lang;
    element.src = track.url;
    video.appendChild(element);
  });
  $("#playerOverlay").hidden = false;
  updatePlayerStatus("Loading " + (source.quality || "stream") + "…");
  const saved = getProgress(state.current.id, state.currentEpisode.number);
  const resumeAt = saved && saved.progressSeconds > 20 && (!saved.durationSeconds || saved.progressSeconds < saved.durationSeconds - 20) ? saved.progressSeconds : 0;
  const play = async () => {
    if (token !== state.loadingToken) return;
    try {
      if (resumeAt > 0 && video.duration && resumeAt < video.duration - 10) video.currentTime = resumeAt;
      await video.play();
      $("#playerOverlay").hidden = true;
      $("#playerError").hidden = true;
      updatePlayerStatus(source.server || source.type || "Playing");
    } catch (_) {
      $("#playerOverlay").hidden = true;
      updatePlayerStatus("Tap play to start");
    }
  };
  if (sourceIsHls(source)) {
    if (window.Hls && Hls.isSupported()) {
      const hls = new Hls({ enableWorker: true, lowLatencyMode: false, backBufferLength: 60, maxBufferLength: 30, maxMaxBufferLength: 60 });
      state.hls = hls;
      hls.on(Hls.Events.MEDIA_ATTACHED, () => hls.loadSource(source.url));
      hls.on(Hls.Events.MANIFEST_PARSED, () => { populateHlsQualitySelect(hls); play(); });
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data && data.fatal && token === state.loadingToken) {
          if (data.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad();
          else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
          else {
            $("#playerOverlay").hidden = true;
            $("#playerError").hidden = false;
            $("#playerErrorText").textContent = "The HLS stream failed. Try another server.";
          }
        }
      });
      hls.attachMedia(video);
    } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = source.url;
      video.addEventListener("loadedmetadata", play, { once: true });
      video.load();
    } else {
      throw new Error("This browser cannot play HLS video. Try Safari or another compatible browser.");
    }
  } else {
    video.src = source.url;
    video.addEventListener("loadedmetadata", play, { once: true });
    video.load();
  }
}
async function openWatch(mediaId, episodeNumber) {
  if (state.view === "watch") { saveProgress(true); destroyPlayer(); }
  state.provider = null;
  state.currentEpisode = null;
  state.streams = [];
  state.episodes = [];
  state.providerChoices = [];
  state.view = "watch";
  app.innerHTML = cacheMarkup();
  try {
    const media = await getMediaById(mediaId);
    state.current = media;
    const saved = mappedProvider(media.id);
    if (saved) state.provider = saved;
    else state.provider = await findProviderTitle(media);
    const firstPage = await providerApi({ action: "episodes", id: state.provider.id, page: "1" }, 20000);
    state.episodes = await fetchAllEpisodePages(state.provider, firstPage);
    if (!state.episodes.length) throw new Error("No episodes were returned by the streaming catalogue.");
    const index = state.episodes.findIndex(item => String(item.number) === String(episodeNumber));
    if (index < 0 && Number(episodeNumber) > 1) throw new Error("Episode " + episodeNumber + " is not present in the current provider episode list.");
    state.currentEpisode = state.episodes[index >= 0 ? index : 0];
    state.activeAudio = state.settings.audio || "sub";
    renderWatchPage();
    bindPlayerEvents();
    await playCurrentEpisode();
  } catch (error) {
    if (state.providerChoices.length && state.current) {
      app.innerHTML = '<div class="empty-state"><span class="empty-icon">↔</span><h2>Choose the correct catalogue match</h2><p>' + escapeHtml(error.message) + '</p></div>' +
        '<section class="panel"><div id="providerStatus" class="provider-note">Pick the matching title to continue.</div><div id="providerChoices" class="provider-list"></div><div id="episodeCount" class="subtle"></div><div id="episodeList" class="episode-grid"></div></section>';
      renderProviderChoices();
    } else {
      app.innerHTML = '<div class="empty-state"><h2>Could not start this episode</h2><p>' + escapeHtml(error.message) + '</p><a class="btn btn-secondary" href="#anime/' + escapeHtml(mediaId) + '">Back to anime</a></div>';
    }
  }
}
function bindPlayerEvents() {
  const video = $("#video");
  if (!video) return;
  video.addEventListener("timeupdate", () => saveProgress(false));
  video.addEventListener("pause", () => saveProgress(true));
  video.addEventListener("ended", () => {
    saveProgress(true);
    if (state.settings.autoNext) playAdjacent(1);
  });
  video.addEventListener("error", () => {
    if (video.error && !$("#playerError").hidden) return;
    if (video.error && state.streams.length) {
      $("#playerOverlay").hidden = true;
      $("#playerError").hidden = false;
      $("#playerErrorText").textContent = "This stream could not be decoded. Try another server or audio version.";
    }
  });
}
async function playEpisodeAt(index) {
  if (!state.episodes[index]) return;
  saveProgress(true);
  state.currentEpisode = state.episodes[index];
  history.replaceState(null, "", "#watch/" + state.current.id + "/" + state.currentEpisode.number);
  renderWatchPage();
  bindPlayerEvents();
  await playCurrentEpisode();
}
function playAdjacent(offset) {
  const index = state.episodes.findIndex(item => String(item.number) === String(state.currentEpisode.number));
  const next = state.episodes[index + offset];
  if (next) playEpisodeAt(index + offset);
  else toast(offset > 0 ? "You are at the latest available episode." : "This is the first available episode.");
}
function go(hash) { if (location.hash === hash) route(); else location.hash = hash; }
async function route() {
  const value = decodeURIComponent((location.hash || "#home").slice(1));
  const parts = value.split("/");
  const root = parts[0] || "home";
  if (state.view === "watch" && root !== "watch") { saveProgress(true); destroyPlayer(); }
  if (state.heroTimer && root !== "home") { clearInterval(state.heroTimer); state.heroTimer = null; }
  if (root === "home") return loadHome();
  if (root === "explore") return loadExplore("");
  if (root === "search") return loadExplore(parts.slice(1).join("/"));
  if (root === "schedule") return loadSchedule();
  if (root === "anime") return showAnime(parts[1]);
  if (root === "watch") return openWatch(parts[1], parts[2]);
  if (root === "watchlist") return loadWatchlist();
  if (root === "history") return loadHistory();
  go("#home");
}
function setupEvents() {
  $("#globalSearchForm").addEventListener("submit", event => {
    event.preventDefault();
    const query = $("#globalSearch").value.trim();
    if (query) go("#search/" + encodeURIComponent(query));
  });
  $("#watchlistShortcut").addEventListener("click", () => go("#watchlist"));
  $("#profileShortcut").addEventListener("click", () => go("#watchlist"));
  document.addEventListener("click", async event => {
    const target = event.target;
    const open = target.closest("[data-open-anime]");
    if (open) { go("#anime/" + open.dataset.openAnime); return; }
    const first = target.closest("[data-watch-first]");
    if (first) { go("#watch/" + first.dataset.watchFirst + "/1"); return; }
    const dot = target.closest("[data-hero-dot]");
    if (dot && state.home) { state.heroIndex = Number(dot.dataset.heroDot); renderHero(state.home.trending.slice(0, 5)); return; }
    const sectionLink = target.closest("[data-section]");
    if (sectionLink) { go("#explore"); return; }
    const action = target.closest("[data-action]");
    if (action) {
      const name = action.dataset.action;
      if (name === "retry-home") loadHome();
      if (name === "load-episodes") loadEpisodeList();
      if (name === "toggle-watchlist" && state.current) setWatchlist(state.current);
      if (name === "clear-history") { writeStore(STORE.progress, []); loadHistory(); toast("Watch history cleared."); }
      if (name === "retry-stream") playCurrentEpisode(true);
      if (name === "watchlist-from-player" && state.current) setWatchlist(state.current);
      return;
    }
    const play = target.closest("[data-play-episode]");
    if (play) { await playEpisodeAt(Number(play.dataset.playEpisode)); return; }
    const provider = target.closest("[data-provider-choice]");
    if (provider) { await chooseProvider(Number(provider.dataset.providerChoice)); return; }
    const resume = target.closest("[data-resume]");
    if (resume) { go("#watch/" + resume.dataset.resume + "/" + resume.dataset.episode); return; }
    const watchIndex = target.closest("[data-watch-index]");
    if (watchIndex) { await playEpisodeAt(Number(watchIndex.dataset.watchIndex)); return; }
    const audio = target.closest("[data-audio]");
    if (audio) {
      state.activeAudio = audio.dataset.audio;
      state.settings.audio = state.activeAudio;
      saveSettings();
      document.querySelectorAll("[data-audio]").forEach(button => button.classList.toggle("active", button.dataset.audio === state.activeAudio));
      await playCurrentEpisode();
      return;
    }
    const format = target.closest("[data-format]");
    if (format) {
      exploreState.format = format.dataset.format;
      document.querySelectorAll("[data-format]").forEach(button => button.classList.toggle("active", button === format));
      fetchExplore();
      return;
    }
    const sort = target.closest("[data-sort]");
    if (sort) {
      exploreState.sort = sort.dataset.sort;
      document.querySelectorAll("[data-sort]").forEach(button => button.classList.toggle("active", button === sort));
      fetchExplore();
      return;
    }
  });
  document.addEventListener("change", event => {
    if (event.target.id === "serverSelect") {
      const index = Number(event.target.value);
      if (state.streams[index]) {
        state.streamIndex = index;
        const token = ++state.loadingToken;
        attachStream(state.streams[index], token).catch(error => toast(error.message));
      }
    }
    if (event.target.id === "qualitySelect") {
      if (state.hls && event.target.dataset.hls === "1") {
        state.hls.currentLevel = Number(event.target.value);
        return;
      }
      const value = event.target.value;
      const index = state.streams.findIndex(source => source.quality === value);
      if (index >= 0) {
        state.streamIndex = index;
        populateServerSelect();
        const token = ++state.loadingToken;
        attachStream(state.streams[index], token).catch(error => toast(error.message));
      }
    }
    if (event.target.id === "autoNextToggle") {
      state.settings.autoNext = event.target.checked;
      saveSettings();
    }
  });
  document.addEventListener("keydown", event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      $("#globalSearch").focus();
    }
    if (event.key === "Escape" && state.view === "watch") {
      saveProgress(true);
      go("#anime/" + (state.current ? state.current.id : ""));
    }
  });
  window.addEventListener("hashchange", route);
  window.addEventListener("pagehide", () => saveProgress(true));
  window.addEventListener("beforeunload", () => saveProgress(true));
  document.addEventListener("visibilitychange", () => { if (document.hidden) saveProgress(true); });
}
function registerPwa() {
  if (!("serviceWorker" in navigator)) return;
  navigator.serviceWorker.register("/watch/sw.js", { scope: "/watch/" }).catch(() => {});
}
setupEvents();
registerPwa();
route();
