(() => {
  "use strict";

  const $ = (selector, root) => (root || document).querySelector(selector);
  const $$ = (selector, root) => Array.from((root || document).querySelectorAll(selector));
  const STORE_KEY = "anidash.watch.web.v1";
  const API = "https://graphql.anilist.co";
  const MEDIA_FIELDS = [
    "id idMal",
    "title { romaji english native }",
    "coverImage { extraLarge large medium }",
    "bannerImage format status episodes duration averageScore popularity",
    "genres season seasonYear startDate { year month day }",
    "nextAiringEpisode { episode airingAt timeUntilAiring }",
    "siteUrl isAdult"
  ].join("\n");

  function readStore() {
    try {
      const raw = JSON.parse(localStorage.getItem(STORE_KEY) || "{}");
      return {
        watchlist: raw.watchlist || {},
        history: raw.history || {},
        manualStreams: raw.manualStreams || {},
        providerManifest: raw.providerManifest || null,
        adultContent: raw.adultContent === true
      };
    } catch (_) {
      return { watchlist: {}, history: {}, manualStreams: {}, providerManifest: null, adultContent: false };
    }
  }

  const store = readStore();
  const state = {
    route: "/home",
    token: 0,
    home: null,
    discover: null,
    search: [],
    searchTerm: "",
    selectedGenre: "",
    detail: null,
    detailMatches: [],
    detailEpisodes: [],
    selectedMatch: null,
    player: null,
    providers: [],
    currentVideo: null,
    hls: null,
    installEvent: null,
    progressTimer: 0
  };

  const escapeHtml = value => String(value == null ? "" : value).replace(/[&<>"']/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
  }[char]));
  const titleOf = media => media && media.title ? (media.title.english || media.title.romaji || media.title.native || "Unknown title") : "Unknown title";
  const formatScore = score => score ? (Number(score) / 10).toFixed(1) : "—";
  const cleanText = value => String(value || "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  const mediaYear = media => media && (media.seasonYear || (media.startDate && media.startDate.year)) || "";
  const imageOf = media => media && media.coverImage && (media.coverImage.extraLarge || media.coverImage.large || media.coverImage.medium) || "";
  const slug = value => String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

  function persist() {
    try { localStorage.setItem(STORE_KEY, JSON.stringify(store)); }
    catch (_) { toast("This browser storage is full. Some history may not save."); }
  }

  function toast(message) {
    const root = $("#toast-root");
    if (!root) return;
    const el = document.createElement("div");
    el.className = "toast";
    el.textContent = message;
    root.appendChild(el);
    window.setTimeout(() => el.remove(), 3200);
  }

  async function gql(query, variables) {
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 18000);
    try {
      const response = await fetch(API, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json" },
        body: JSON.stringify({ query: query, variables: variables || {} }),
        signal: controller.signal
      });
      const body = await response.json();
      if (!response.ok || body.errors) {
        const message = body.errors && body.errors[0] && body.errors[0].message;
        throw new Error(message || "AniList is temporarily unavailable.");
      }
      return body.data;
    } catch (error) {
      if (error.name === "AbortError") throw new Error("AniList request timed out. Please retry.");
      throw error;
    } finally {
      window.clearTimeout(timeout);
    }
  }

  function pageQuery(sort, page, perPage, extra) {
    return "query ($page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { hasNextPage currentPage lastPage } media(type: ANIME, sort: " +
      sort + ", isAdult: false" + (extra || "") + ") { " + MEDIA_FIELDS + " } } }";
  }

  async function getCollection(sort, page, perPage) {
    const data = await gql(pageQuery(sort, page || 1, perPage || 18), { page: page || 1, perPage: perPage || 18 });
    return data.Page;
  }

  async function getAnime(id) {
    const query = "query ($id: Int) { Media(id: $id, type: ANIME) { " + MEDIA_FIELDS +
      " description(asHtml: false) studios(isMain: true) { nodes { name } } relations { edges { relationType node { id type title { english romaji } coverImage { large } } } } recommendations(sort: RATING_DESC) { nodes { mediaRecommendation { id title { english romaji } coverImage { large } averageScore format } } } trailer { id site thumbnail } } }";
    const data = await gql(query, { id: Number(id) });
    return data.Media;
  }

  async function searchAniList(term, page) {
    const query = "query ($search: String!, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { hasNextPage } media(search: $search, type: ANIME, sort: SEARCH_MATCH, isAdult: false) { " + MEDIA_FIELDS + " } } }";
    const data = await gql(query, { search: term, page: page || 1, perPage: 24 });
    return data.Page;
  }

  function showLoading(message) {
    $("#view").innerHTML = '<section class="loading-state"><div class="loader"></div><p>' + escapeHtml(message || "Loading…") + '</p></section>';
  }

  function card(media) {
    const progress = store.history[String(media.id)];
    const poster = imageOf(media);
    const pct = progress && progress.duration > 0 ? Math.max(0, Math.min(100, (progress.position / progress.duration) * 100)) : 0;
    return '<article class="anime-card" data-anime="' + escapeHtml(media.id) + '" tabindex="0" role="button" aria-label="Open ' + escapeHtml(titleOf(media)) + '">' +
      '<div class="poster-wrap">' +
        (poster ? '<img loading="lazy" src="' + escapeHtml(poster) + '" alt="' + escapeHtml(titleOf(media)) + '">' : '<div class="poster-fallback">' + escapeHtml(titleOf(media)) + '</div>') +
        '<div class="poster-shade"></div>' +
        (media.averageScore ? '<span class="poster-score">★ ' + formatScore(media.averageScore) + '</span>' : '') +
        (media.format ? '<span class="poster-format">' + escapeHtml(media.format) + '</span>' : '') +
      '</div>' +
      '<div class="card-title">' + escapeHtml(titleOf(media)) + '</div>' +
      '<p class="card-subtitle">' + escapeHtml([mediaYear(media), media.episodes ? media.episodes + " eps" : media.status].filter(Boolean).join(" · ")) + '</p>' +
      (progress ? '<div class="card-progress"><span style="width:' + pct + '%"></span></div><div class="card-resume">Resume episode ' + escapeHtml(progress.episode || 1) + '</div>' : '') +
    '</article>';
  }

  function grid(items) {
    if (!items || !items.length) return '<div class="empty-state"><div class="empty-icon">✦</div><h3>Nothing here yet</h3><p>Try another search or explore the catalogue.</p></div>';
    return '<div class="anime-grid">' + items.map(card).join("") + '</div>';
  }

  function section(title, note, items, route) {
    return '<section class="section"><div class="section-heading"><div><h2 class="section-title">' + escapeHtml(title) + '</h2>' +
      (note ? '<p class="section-note">' + escapeHtml(note) + '</p>' : '') + '</div>' +
      (route ? '<button class="section-link" data-route="' + route + '">View all ↗</button>' : '') +
      '</div>' + grid(items) + '</section>';
  }

  function pageHead(eyebrow, title, subtitle, extra) {
    return '<div class="page-head"><div><div class="eyebrow">' + escapeHtml(eyebrow) + '</div><h1 class="page-title">' + escapeHtml(title) + '</h1>' +
      (subtitle ? '<p class="page-subtitle">' + escapeHtml(subtitle) + '</p>' : '') + '</div>' + (extra || '') + '</div>';
  }

  async function renderHome() {
    const token = ++state.token;
    showLoading("Finding your next favourite…");
    try {
      const results = await Promise.all([
        getCollection("TRENDING_DESC", 1, 18),
        getCollection("POPULARITY_DESC", 1, 18),
        getCollection("SCORE_DESC", 1, 18)
      ]);
      if (token !== state.token) return;
      state.home = { trending: results[0].media, popular: results[1].media, top: results[2].media };
      const hero = results[0].media[0];
      const heroImage = hero && (hero.bannerImage || imageOf(hero));
      const continueItems = Object.values(store.history).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0)).slice(0, 6);
      $("#view").innerHTML =
        (hero ? '<section class="hero-stage"><div class="hero-bg" style="background-image:url(&quot;' + escapeHtml(heroImage) + '&quot;)"></div><div class="hero-content">' +
          '<div class="hero-kicker">Trending right now</div><h1 class="hero-title">' + escapeHtml(titleOf(hero)) + '</h1>' +
          '<div class="hero-meta"><span>★ ' + formatScore(hero.averageScore) + '</span><span>' + escapeHtml(hero.format || "Anime") + '</span><span>' + escapeHtml(mediaYear(hero)) + '</span><span>' + escapeHtml(hero.status || "") + '</span></div>' +
          '<p class="hero-description">' + escapeHtml(cleanText(hero.description) || "Discover details, episodes and connected streams for this series.") + '</p>' +
          '<div class="hero-actions"><button class="btn btn-primary" data-anime="' + hero.id + '">Explore anime <span>→</span></button><button class="btn btn-secondary" data-watchlist="' + hero.id + '">♡ Add to list</button></div>' +
          '</div></section>' : '') +
        (continueItems.length ? section("Pick up where you left off", "Your recent progress is saved on this device.", continueItems.map(item => item.media).filter(Boolean)) : '') +
        section("Trending this season", "What anime fans are watching right now.", results[0].media.slice(0, 12), "/discover") +
        section("Popular picks", "Big stories, fan favourites and new discoveries.", results[1].media.slice(0, 12), "/discover") +
        section("Top rated", "Highly rated titles from the AniList catalogue.", results[2].media.slice(0, 12), "/discover");
    } catch (error) {
      if (token !== state.token) return;
      $("#view").innerHTML = '<div class="empty-state"><div class="empty-icon">◌</div><h3>Could not load the catalogue</h3><p>' + escapeHtml(error.message) + '</p><button class="btn btn-primary" data-route="/home">Try again</button></div>';
    }
  }

  async function renderDiscover() {
    const token = ++state.token;
    showLoading("Loading the catalogue…");
    try {
      const sort = state.discoverSort || "TRENDING_DESC";
      const data = await getCollection(sort, 1, 30);
      if (token !== state.token) return;
      state.discover = data.media;
      const options = [
        ["TRENDING_DESC", "Trending"], ["POPULARITY_DESC", "Most popular"], ["SCORE_DESC", "Top rated"]
      ];
      $("#view").innerHTML = pageHead("THE ANIME INDEX", "Find your next story", "Explore AniList metadata, ratings, seasons and series information.") +
        '<div class="toolbar"><select class="select-control" id="discover-sort">' + options.map(o => '<option value="' + o[0] + '"' + (sort === o[0] ? " selected" : "") + '>' + o[1] + '</option>').join("") + '</select><span class="form-help">Adult catalogue entries are hidden by default.</span></div>' +
        '<div style="height:18px"></div><div id="discover-grid">' + grid(data.media) + '</div>';
    } catch (error) {
      if (token !== state.token) return;
      $("#view").innerHTML = '<div class="empty-state"><h3>Catalogue unavailable</h3><p>' + escapeHtml(error.message) + '</p><button class="btn btn-primary" data-route="/discover">Retry</button></div>';
    }
  }

  async function renderSearch(term) {
    const token = ++state.token;
    state.searchTerm = term || "";
    $("#view").innerHTML = pageHead("SEARCH", "Search anime", "Search titles using the AniList catalogue.") +
      '<form id="search-form" class="search-box-large"><span>⌕</span><input id="search-page-input" value="' + escapeHtml(term || "") + '" placeholder="Try Naruto, Frieren, One Piece…" autocomplete="off"><button class="btn btn-primary" type="submit">Search</button></form>' +
      '<div id="search-results"><div class="empty-state"><div class="empty-icon">⌕</div><h3>What are you in the mood for?</h3><p>Enter an anime title to find matching entries.</p></div></div>';
    if (!term) return;
    try {
      const result = await searchAniList(term, 1);
      if (token !== state.token) return;
      state.search = result.media || [];
      $("#search-results").innerHTML = '<div class="section-heading"><div><h2 class="section-title">Results</h2><p class="section-note">' + state.search.length + ' matching titles</p></div></div>' + grid(state.search);
    } catch (error) {
      if (token !== state.token) return;
      $("#search-results").innerHTML = '<div class="empty-state"><h3>Search could not complete</h3><p>' + escapeHtml(error.message) + '</p></div>';
    }
    const input = $("#search-page-input");
    if (input) input.focus({ preventScroll: true });
  }

  function currentProviders() {
    return state.providers || [];
  }

  async function loadProviders() {
    if (store.providerManifest && Array.isArray(store.providerManifest.providers)) {
      state.providers = store.providerManifest.providers;
      return state.providers;
    }
    try {
      const response = await fetch("/sources.json", { cache: "no-store" });
      if (!response.ok) throw new Error("Source manifest unavailable");
      const data = await response.json();
      state.providers = Array.isArray(data.providers) ? data.providers : [];
    } catch (_) {
      state.providers = [];
    }
    return state.providers;
  }

  function expandEndpoint(provider, key, values) {
    const endpoint = provider && provider.endpoints && provider.endpoints[key];
    if (!endpoint) return null;
    let path = String(endpoint);
    Object.keys(values || {}).forEach(name => {
      path = path.replace(new RegExp("\\{" + name + "\\}", "g"), encodeURIComponent(String(values[name] == null ? "" : values[name])));
    });
    try {
      return /^https:\/\//i.test(path) ? path : new URL(path, provider.baseUrl.endsWith("/") ? provider.baseUrl : provider.baseUrl + "/").toString();
    } catch (_) {
      return null;
    }
  }

  async function providerGet(provider, key, values) {
    const url = expandEndpoint(provider, key, values);
    if (!url) return null;
    const response = await fetch(url, { headers: { "Accept": "application/json" } });
    if (!response.ok) throw new Error(provider.name + " returned " + response.status);
    return response.json();
  }

  function extractArray(payload, names) {
    if (Array.isArray(payload)) return payload;
    const paths = names || ["results", "items", "list", "episodes", "sources", "data"];
    for (const name of paths) {
      if (Array.isArray(payload && payload[name])) return payload[name];
      if (payload && payload.data && Array.isArray(payload.data[name])) return payload.data[name];
      if (payload && payload.result && Array.isArray(payload.result[name])) return payload.result[name];
    }
    if (payload && Array.isArray(payload.data)) return payload.data;
    return [];
  }

  function normaliseResult(item) {
    const title = item.title || item.name || item.animeTitle || item.jname || "Unknown";
    return {
      id: item.id || item.animeId || item.session || item.slug || item.url || item.link,
      title: typeof title === "string" ? title : (title.english || title.romaji || title.native || "Unknown"),
      image: item.image || item.cover || item.poster || item.imageUrl || item.thumbnail || "",
      raw: item
    };
  }

  function titleMatchScore(a, b) {
    const x = slug(a);
    const y = slug(b);
    if (!x || !y) return 0;
    if (x === y) return 100;
    if (x.includes(y) || y.includes(x)) return 80;
    const xs = new Set(x.split(" "));
    const ys = new Set(y.split(" "));
    let overlap = 0;
    xs.forEach(word => { if (ys.has(word)) overlap++; });
    return Math.round((overlap / Math.max(xs.size, ys.size)) * 65);
  }

  async function findProviderMatches(media) {
    await loadProviders();
    const providers = currentProviders().filter(provider => provider && provider.endpoints && provider.endpoints.search && provider.baseUrl);
    const found = await Promise.all(providers.map(async provider => {
      try {
        const payload = await providerGet(provider, "search", {
          query: titleOf(media), page: 1, anilistId: media.id, malId: media.idMal, title: titleOf(media)
        });
        const results = extractArray(payload, ["results", "items", "list", "anime", "data"]).map(normaliseResult).filter(item => item.id);
        const best = results.map(item => ({ item, score: titleMatchScore(titleOf(media), item.title) }))
          .sort((a, b) => b.score - a.score)[0];
        return best && best.score >= 45 ? { provider, animeId: String(best.item.id), item: best.item, score: best.score } : null;
      } catch (error) {
        return { provider, error: error.message, score: 0 };
      }
    }));
    return found.filter(Boolean).sort((a, b) => b.score - a.score);
  }

  async function episodesFromMatch(match, media) {
    if (!match || !match.provider.endpoints || !match.provider.endpoints.episodes) return [];
    const payload = await providerGet(match.provider, "episodes", {
      id: match.animeId, anilistId: media.id, malId: media.idMal, title: titleOf(media), page: 1
    });
    const list = extractArray(payload, ["episodes", "items", "results", "list", "data"]);
    return list.map((item, index) => ({
      id: item.id || item.episodeId || item.url || String(item.number || index + 1),
      number: Number(item.number || item.episode || item.episodeNumber || index + 1),
      title: item.title || item.name || "Episode " + Number(item.number || item.episode || item.episodeNumber || index + 1),
      thumbnail: item.thumbnail || item.image || item.snapshot || "",
      date: item.date || item.airDate || item.aired || "",
      isFiller: item.isFiller === true || item.filler === true || item.filler === 1,
      raw: item
    })).sort((a, b) => a.number - b.number);
  }

  function generatedEpisodes(media) {
    const total = Number(media.episodes || 0);
    if (!total) return [];
    const limit = Math.min(total, 300);
    return Array.from({ length: limit }, (_, index) => ({
      id: String(index + 1), number: index + 1, title: "Episode " + (index + 1),
      thumbnail: "", date: "", isFiller: false, generated: true
    }));
  }

  async function renderAnime(id) {
    const token = ++state.token;
    state.detail = null;
    state.detailMatches = [];
    state.detailEpisodes = [];
    state.selectedMatch = null;
    showLoading("Loading anime details…");
    try {
      const media = await getAnime(id);
      if (token !== state.token) return;
      state.detail = media;
      $("#view").innerHTML = '<div class="loading-state"><div class="loader"></div><p>Finding connected episode sources…</p></div>';
      const matches = await findProviderMatches(media);
      if (token !== state.token) return;
      state.detailMatches = matches;
      const good = matches.filter(match => !match.error);
      state.selectedMatch = good[0] || null;
      let episodes = [];
      if (state.selectedMatch) {
        try { episodes = await episodesFromMatch(state.selectedMatch, media); }
        catch (error) { toast("Could not load episodes from " + state.selectedMatch.provider.name + "."); }
      }
      if (token !== state.token) return;
      state.detailEpisodes = episodes.length ? episodes : generatedEpisodes(media);
      paintAnimeDetails(media);
    } catch (error) {
      if (token !== state.token) return;
      $("#view").innerHTML = '<div class="empty-state"><h3>Anime details unavailable</h3><p>' + escapeHtml(error.message) + '</p><button class="btn btn-primary" data-route="/home">Back home</button></div>';
    }
  }

  function isInWatchlist(id) {
    return !!store.watchlist[String(id)];
  }

  function paintAnimeDetails(media) {
    const banner = media.bannerImage || imageOf(media);
    const genres = (media.genres || []).slice(0, 10);
    const watched = isInWatchlist(media.id);
    const matches = state.detailMatches.filter(match => !match.error);
    const sourceInfo = matches.length ? matches.map(match => match.provider.name).join(", ") : "No provider connected";
    const episodes = state.detailEpisodes || [];
    const relationItems = media.relations && media.relations.edges ? media.relations.edges.filter(edge => edge.node && edge.node.type === "ANIME").slice(0, 6) : [];
    const malLink = media.idMal ? '<a href="https://myanimelist.net/anime/' + media.idMal + '" target="_blank" rel="noopener">MyAnimeList ↗</a>' : "Not mapped";
    $("#view").innerHTML =
      '<div class="details-hero"><div class="details-banner" style="background-image:url(&quot;' + escapeHtml(banner) + '&quot;)"></div><div class="details-content">' +
        '<img class="details-poster" src="' + escapeHtml(imageOf(media)) + '" alt="' + escapeHtml(titleOf(media)) + '">' +
        '<div class="details-copy"><div class="eyebrow">ANIME DETAILS</div><h1 class="details-title">' + escapeHtml(titleOf(media)) + '</h1>' +
          '<div class="details-native">' + escapeHtml(media.title && (media.title.romaji || media.title.native) || "") + '</div>' +
          '<div class="details-meta"><span class="meta-chip">★ ' + formatScore(media.averageScore) + '</span><span class="meta-chip">' + escapeHtml(media.format || "Anime") + '</span><span class="meta-chip">' + escapeHtml(media.status || "Unknown") + '</span><span class="meta-chip">' + escapeHtml(media.episodes ? media.episodes + " episodes" : "Episode count unknown") + '</span><span class="meta-chip">' + escapeHtml(mediaYear(media)) + '</span></div>' +
          '<p class="details-description">' + escapeHtml(cleanText(media.description) || "No synopsis is available for this title yet.") + '</p>' +
          '<div class="button-row"><button class="btn btn-primary" data-play-first="' + media.id + '" ' + (episodes.length ? "" : "disabled") + '>▶ Start watching</button><button class="btn btn-secondary" data-watchlist="' + media.id + '">' + (watched ? "✓ In watchlist" : "♡ Add to watchlist") + '</button></div>' +
        '</div></div></div>' +
      '<div class="details-layout"><section class="content-panel"><div class="section-heading"><div><h2 class="panel-title">Episodes</h2><p class="section-note">' + (matches.length ? "Source: " + escapeHtml(sourceInfo) : "Episode numbers are based on AniList metadata until you connect a source.") + '</p></div><span class="watchlist-badge">' + episodes.length + ' listed</span></div>' +
        '<div class="episode-toolbar"><select id="episode-source" class="select-control">' + (matches.length ? matches.map((match, index) => '<option value="' + index + '"' + (match === state.selectedMatch ? " selected" : "") + '>' + escapeHtml(match.provider.name) + '</option>').join("") : '<option value="">No connected source</option>') + '</select><input id="episode-filter" class="input-control" style="max-width:155px" placeholder="Find episode…"></div>' +
        '<div id="episode-list" class="episode-list">' + episodes.map(episodeCard).join("") + '</div>' +
        (matches.length ? '' : '<div class="notice" style="margin-top:14px">Connect a provider in Settings → Sources, or use a direct MP4/HLS link on the player screen. AniList supplies metadata, not video streams.</div>') +
      '</section><aside class="content-panel"><h2 class="panel-title">About this anime</h2><div class="info-list">' +
        infoRow("Genres", genres.length ? genres.join(", ") : "Not listed") +
        infoRow("Season", [media.season, media.seasonYear].filter(Boolean).join(" ") || "Not listed") +
        infoRow("Studios", media.studios && media.studios.nodes.length ? media.studios.nodes.map(studio => studio.name).join(", ") : "Not listed") +
        infoRow("MyAnimeList", malLink) +
        infoRow("AniList", '<a href="https://anilist.co/anime/' + media.id + '" target="_blank" rel="noopener">Open AniList ↗</a>') +
        infoRow("Sources", sourceInfo) +
      '</div></aside></div>' +
      (relationItems.length ? '<section class="section" style="margin-top:28px"><div class="section-heading"><div><h2 class="section-title">Related anime</h2></div></div><div class="anime-grid">' + relationItems.map(edge => relationCard(edge.node)).join("") + '</div></section>' : '');
  }

  function relationCard(item) {
    const poster = item.coverImage && item.coverImage.large || "";
    return '<article class="anime-card" data-anime="' + item.id + '" tabindex="0"><div class="poster-wrap">' + (poster ? '<img loading="lazy" src="' + escapeHtml(poster) + '" alt="' + escapeHtml(item.title && (item.title.english || item.title.romaji) || "Related anime") + '">' : '<div class="poster-fallback">Related anime</div>') + '</div><div class="card-title">' + escapeHtml(item.title && (item.title.english || item.title.romaji) || "Related anime") + '</div><p class="card-subtitle">Related title</p></article>';
  }

  function infoRow(label, value) {
    return '<div class="info-row"><div class="info-label">' + escapeHtml(label) + '</div><div class="info-value">' + value + '</div></div>';
  }

  function episodeCard(episode) {
    const thumb = episode.thumbnail ? '<img class="episode-thumb" loading="lazy" src="' + escapeHtml(episode.thumbnail) + '" alt="">' : '<div class="episode-thumb"></div>';
    return '<button class="episode-item" data-play-episode="' + escapeHtml(episode.number) + '|' + escapeHtml(episode.id) + '">' + thumb +
      '<span><span class="episode-number">EPISODE ' + escapeHtml(episode.number) + (episode.isFiller ? ' · FILLER' : '') + '</span><span class="episode-name">' + escapeHtml(episode.title) + '</span><span class="episode-date">' + escapeHtml(episode.date || (episode.generated ? "Connect a source to load stream links" : "")) + '</span></span><span class="episode-play">›</span></button>';
  }

  async function selectDetailProvider(index) {
    if (!state.detail) return;
    const match = state.detailMatches.filter(item => !item.error)[Number(index)];
    if (!match) return;
    showLoading("Loading episodes from " + match.provider.name + "…");
    try {
      const episodes = await episodesFromMatch(match, state.detail);
      state.selectedMatch = match;
      state.detailEpisodes = episodes.length ? episodes : generatedEpisodes(state.detail);
      paintAnimeDetails(state.detail);
    } catch (error) {
      toast("Source unavailable: " + error.message);
      paintAnimeDetails(state.detail);
    }
  }

  function toggleWatchlist(id) {
    const key = String(id);
    if (store.watchlist[key]) {
      delete store.watchlist[key];
      toast("Removed from your watchlist.");
    } else {
      const media = state.detail && String(state.detail.id) === key ? state.detail :
        state.home && [...state.home.trending, ...state.home.popular].find(item => String(item.id) === key);
      if (media) store.watchlist[key] = media;
      else store.watchlist[key] = { id: Number(key), title: { english: "Saved anime " + key }, coverImage: {} };
      toast("Added to your watchlist.");
    }
    persist();
    if (state.detail && String(state.detail.id) === key) paintAnimeDetails(state.detail);
  }

  async function startEpisode(number, episodeId) {
    if (!state.detail) return;
    const episode = state.detailEpisodes.find(item => Number(item.number) === Number(number)) || {
      id: episodeId, number: Number(number), title: "Episode " + number
    };
    state.player = {
      media: state.detail,
      episode: episode,
      match: state.selectedMatch,
      streams: [],
      servers: [],
      tracks: [],
      selectedServer: "default",
      category: "sub",
      intro: null,
      outro: null,
      direct: store.manualStreams[String(state.detail.id) + ":" + String(number)] || ""
    };
    location.hash = "#/watch/" + state.detail.id + "/" + number;
  }

  function playerEpisodeItems() {
    if (!state.player || !state.detailEpisodes) return "";
    return state.detailEpisodes.map(episode => '<button class="player-episode' + (Number(episode.number) === Number(state.player.episode.number) ? " active" : "") + '" data-player-episode="' + episode.number + '"><span>' + episode.number + '</span>' + escapeHtml(episode.title) + '</button>').join("");
  }

  async function renderWatch(id, number) {
    const token = ++state.token;
    const media = state.detail && String(state.detail.id) === String(id) ? state.detail : await getAnime(id).catch(() => null);
    if (!media) {
      $("#view").innerHTML = '<div class="empty-state"><h3>Anime not found</h3><p>Return to the catalogue and open the title again.</p><button class="btn btn-primary" data-route="/home">Home</button></div>';
      return;
    }
    if (!state.detail || String(state.detail.id) !== String(id)) {
      state.detail = media;
      state.detailMatches = await findProviderMatches(media);
      const match = state.detailMatches.find(item => !item.error) || null;
      state.selectedMatch = match;
      state.detailEpisodes = match ? await episodesFromMatch(match, media).catch(() => []) : [];
      if (!state.detailEpisodes.length) state.detailEpisodes = generatedEpisodes(media);
    }
    const episode = state.detailEpisodes.find(item => Number(item.number) === Number(number)) || {
      id: String(number), number: Number(number), title: "Episode " + number, generated: true
    };
    state.player = state.player && state.player.media && String(state.player.media.id) === String(id) ?
      state.player : { media: media, episode: episode, match: state.selectedMatch, streams: [], servers: [], tracks: [], selectedServer: "default", category: "sub", intro: null, outro: null, direct: store.manualStreams[String(id) + ":" + String(number)] || "" };
    state.player.media = media;
    state.player.episode = episode;
    if (token !== state.token) return;
    paintPlayer();
    if (state.player.direct) {
      attachStream(state.player.direct, { quality: "Direct link", type: /\.m3u8(\?|$)/i.test(state.player.direct) ? "hls" : "mp4" }, []);
    } else if (state.player.match && !episode.generated) {
      await loadPlayerStreams(token);
    }
  }

  function paintPlayer() {
    const player = state.player;
    const media = player.media;
    const episode = player.episode;
    const episodeIndex = state.detailEpisodes.findIndex(item => Number(item.number) === Number(episode.number));
    const hasPrev = episodeIndex > 0;
    const hasNext = episodeIndex >= 0 && episodeIndex < state.detailEpisodes.length - 1;
    $("#view").innerHTML = '<div class="player-page"><div class="player-topline"><button class="back-button" data-anime="' + media.id + '" aria-label="Back to anime">←</button><div><h1>' + escapeHtml(titleOf(media)) + '</h1><p>Episode ' + escapeHtml(episode.number) + ' · ' + escapeHtml(episode.title) + '</p></div></div>' +
      '<div class="player-layout"><section><div class="video-frame"><video id="anime-video" controls playsinline webkit-playsinline preload="metadata"></video><div class="player-overlay" id="player-overlay"><div class="loader"></div><strong>Preparing your player</strong><p>Checking the connected source and browser playback support…</p></div></div>' +
      '<div class="player-under"><div><h2>' + escapeHtml(episode.title) + '</h2><p>' + escapeHtml(titleOf(media)) + ' · Episode ' + escapeHtml(episode.number) + '</p></div><div class="player-controls"><button class="btn btn-quiet" data-prev ' + (hasPrev ? "" : "disabled") + '>← Previous</button><button class="btn btn-quiet" data-next ' + (hasNext ? "" : "disabled") + '>Next →</button><button class="btn btn-secondary" data-open-direct>Paste stream link</button></div></div>' +
      '<div class="button-row" style="margin-top:14px" id="skip-buttons"></div></section>' +
      '<aside class="player-sidebar"><div class="player-panel"><h3>Audio & server</h3><div class="source-row" id="category-pills"><button class="source-pill active" data-category="sub">SUB</button><button class="source-pill" data-category="dub">DUB</button></div><div style="height:9px"></div><div class="source-row" id="server-pills"><span class="form-help">Load a source to see servers.</span></div><div style="height:12px"></div><div class="source-row" id="quality-pills"></div></div>' +
      '<div class="player-panel"><h3>Episode list</h3><div class="player-episode-list">' + playerEpisodeItems() + '</div></div>' +
      '<div class="notice">Playback sources come from the provider you connect or a direct link you enter. Video URLs must be browser-compatible (MP4 or HLS) and permit playback from this site.</div></aside></div></div>';
    updateActiveNav("/watch");
  }

  async function loadPlayerStreams(token) {
    const player = state.player;
    if (!player || !player.match || !player.match.provider.endpoints.streams) {
      showPlayerOverlay("No stream source connected", "Connect a provider in Settings → Sources, or paste an authorised MP4/HLS URL.", true);
      return;
    }
    showPlayerOverlay("Resolving episode", "Asking " + player.match.provider.name + " for available servers…", false);
    try {
      const payload = await providerGet(player.match.provider, "streams", {
        id: player.match.animeId,
        episodeId: player.episode.id,
        episode: player.episode.number,
        anilistId: player.media.id,
        malId: player.media.idMal,
        server: player.selectedServer || "default",
        category: player.category || "sub"
      });
      if (token !== state.token) return;
      const servers = extractArray(payload, ["servers", "serverList"]);
      const streams = extractArray(payload, ["sources", "streams", "videos", "data"]);
      player.servers = servers;
      player.streams = streams;
      player.tracks = extractArray(payload, ["tracks", "subtitles"]);
      player.intro = payload && payload.intro || null;
      player.outro = payload && payload.outro || null;
      renderPlayerOptions();
      if (streams.length) {
        attachStream(streams[0].url || streams[0].src || streams[0].file, streams[0], player.tracks);
      } else {
        showPlayerOverlay("No playable stream returned", "The source answered, but it did not return a browser-compatible MP4 or HLS URL.", true);
      }
    } catch (error) {
      if (token !== state.token) return;
      showPlayerOverlay("Source could not be reached", error.message + " You can retry with another source or paste a direct link.", true);
      renderPlayerOptions();
    }
  }

  function showPlayerOverlay(title, description, showAction) {
    const overlay = $("#player-overlay");
    if (!overlay) return;
    overlay.innerHTML = '<div style="font-size:28px;color:#b99aff">◈</div><strong>' + escapeHtml(title) + '</strong><p>' + escapeHtml(description) + '</p>' +
      (showAction ? '<button class="btn btn-primary" data-open-direct>Paste stream link</button>' : '');
  }

  function renderPlayerOptions() {
    const player = state.player;
    if (!player) return;
    const servers = $("#server-pills");
    if (servers) {
      servers.innerHTML = player.servers.length ? player.servers.map(server => '<button class="source-pill' + (String(server.id) === String(player.selectedServer) ? " active" : "") + '" data-server="' + escapeHtml(server.id || "default") + '">' + escapeHtml(server.name || server.id || "Server") + '</button>').join("") : '<span class="form-help">Default source</span>';
    }
    const qualities = $("#quality-pills");
    if (qualities) {
      qualities.innerHTML = player.streams.map((stream, index) => '<button class="source-pill' + (index === 0 ? " active" : "") + '" data-stream="' + index + '">' + escapeHtml(stream.quality || stream.label || stream.type || ("Source " + (index + 1))) + '</button>').join("");
    }
    const skip = $("#skip-buttons");
    if (skip) {
      skip.innerHTML = (player.intro && Number(player.intro.end) > Number(player.intro.start) ? '<button class="btn btn-quiet" data-skip="intro">Skip intro ↗</button>' : '') +
        (player.outro && Number(player.outro.end) > Number(player.outro.start) ? '<button class="btn btn-quiet" data-skip="outro">Skip outro ↗</button>' : '');
    }
  }

  function attachStream(url, stream, tracks) {
    if (!url) {
      showPlayerOverlay("Invalid stream URL", "The provider did not return a media URL.", true);
      return;
    }
    let parsed;
    try { parsed = new URL(url); } catch (_) {
      showPlayerOverlay("Invalid stream URL", "The source URL is not valid.", true);
      return;
    }
    if (parsed.protocol !== "https:" && parsed.hostname !== "localhost") {
      showPlayerOverlay("Insecure stream blocked", "Only HTTPS video sources are allowed on the deployed website.", true);
      return;
    }
    const video = $("#anime-video");
    if (!video) return;
    if (state.hls) {
      try { state.hls.destroy(); } catch (_) {}
      state.hls = null;
    }
    video.pause();
    video.removeAttribute("src");
    while (video.firstChild) video.removeChild(video.firstChild);
    (tracks || []).forEach(track => {
      if (!track.url) return;
      const el = document.createElement("track");
      el.kind = track.type === "captions" ? "captions" : "subtitles";
      el.label = track.lang || "Subtitles";
      el.srclang = (track.lang || "en").slice(0, 2).toLowerCase();
      el.src = track.url;
      video.appendChild(el);
    });
    const isHls = stream && (stream.isM3U8 === true || String(stream.type || "").toLowerCase().includes("hls") || /\.m3u8(\?|$)/i.test(url));
    const overlay = $("#player-overlay");
    if (isHls && video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = url;
    } else if (isHls && window.Hls && window.Hls.isSupported()) {
      state.hls = new window.Hls({ enableWorker: true, lowLatencyMode: false, backBufferLength: 45, maxBufferLength: 45 });
      state.hls.loadSource(url);
      state.hls.attachMedia(video);
      state.hls.on(window.Hls.Events.ERROR, function (_event, data) {
        if (data && data.fatal) {
          showPlayerOverlay("Stream playback failed", "The browser could not load this HLS stream. Try a different source or quality.", true);
          try { state.hls.destroy(); } catch (_) {}
          state.hls = null;
        }
      });
    } else {
      video.src = url;
    }
    state.currentVideo = url;
    if (overlay) overlay.style.display = "none";
    video.onloadedmetadata = () => {
      const key = String(state.player.media.id);
      const saved = store.history[key];
      if (saved && Number(saved.episode) === Number(state.player.episode.number) && saved.position > 15 && video.duration > saved.position + 15) {
        video.currentTime = saved.position;
      }
      video.play().catch(() => {});
    };
    video.ontimeupdate = () => savePlaybackProgress(video);
    video.onended = () => {
      savePlaybackProgress(video, true);
      toast("Episode finished. Choose Next to continue.");
    };
  }

  function savePlaybackProgress(video, ended) {
    if (!state.player || !video.duration || !Number.isFinite(video.duration)) return;
    const now = Date.now();
    if (!ended && now - state.progressTimer < 7000) return;
    state.progressTimer = now;
    const media = state.player.media;
    const episode = state.player.episode;
    store.history[String(media.id)] = {
      media: {
        id: media.id, idMal: media.idMal, title: media.title, coverImage: media.coverImage,
        bannerImage: media.bannerImage, format: media.format, status: media.status,
        episodes: media.episodes, averageScore: media.averageScore, seasonYear: media.seasonYear
      },
      episode: episode.number,
      episodeTitle: episode.title,
      position: ended ? video.duration : video.currentTime,
      duration: video.duration,
      updatedAt: now
    };
    persist();
  }

  function renderLibrary() {
    const items = Object.values(store.watchlist).sort((a, b) => titleOf(a).localeCompare(titleOf(b)));
    $("#view").innerHTML = pageHead("YOUR COLLECTION", "My watchlist", "Anime you have saved on this device.") +
      (items.length ? grid(items) : '<div class="empty-state"><div class="empty-icon">♡</div><h3>Your list is waiting</h3><p>Open any anime and tap Add to watchlist to keep it here.</p><button class="btn btn-primary" data-route="/discover">Explore anime</button></div>');
  }

  function renderHistory() {
    const items = Object.values(store.history).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
    const media = items.map(item => item.media).filter(Boolean);
    $("#view").innerHTML = pageHead("RECENT ACTIVITY", "Continue watching", "Your playback progress is stored locally in this browser.") +
      (items.length ? '<div class="anime-grid">' + items.map(item => {
        const pct = item.duration ? Math.min(100, Math.max(0, item.position / item.duration * 100)) : 0;
        const poster = imageOf(item.media);
        return '<article class="anime-card" data-resume="' + item.media.id + '" tabindex="0"><div class="poster-wrap">' + (poster ? '<img loading="lazy" src="' + escapeHtml(poster) + '" alt="">' : '<div class="poster-fallback">' + escapeHtml(titleOf(item.media)) + '</div>') + '<span class="poster-score">EP ' + escapeHtml(item.episode) + '</span></div><div class="card-title">' + escapeHtml(titleOf(item.media)) + '</div><p class="card-subtitle">' + escapeHtml(item.episodeTitle || "Episode " + item.episode) + '</p><div class="card-progress"><span style="width:' + pct + '%"></span></div><div class="card-resume">Resume at ' + Math.floor((item.position || 0) / 60) + ' min</div></article>';
      }).join("") + '</div>' : '<div class="empty-state"><div class="empty-icon">◷</div><h3>No episodes watched yet</h3><p>When you start watching, AniDash will remember your episode and playback position on this device.</p><button class="btn btn-primary" data-route="/discover">Find anime</button></div>');
  }

  function renderSettings() {
    loadProviders().then(providers => {
      if (state.route !== "/settings") return;
      const manifest = store.providerManifest || { version: 1, providers: providers };
      $("#source-config").value = JSON.stringify(manifest, null, 2);
      $("#provider-count").textContent = providers.length + (providers.length === 1 ? " source configured" : " sources configured");
    });
    $("#view").innerHTML = pageHead("PREFERENCES", "Settings", "Manage source connectors, playback defaults and the app experience.") +
      '<div class="settings-grid"><section class="settings-card"><div class="eyebrow">STREAMING</div><h3>Source connectors</h3><p id="provider-count">Checking configured sources…</p><p>Connect JSON API providers for anime search, episode lists and stream resolution. The source manifest is kept in this browser when saved here.</p><button class="btn btn-primary" data-open-sources>Manage sources</button></section>' +
      '<section class="settings-card"><div class="eyebrow">LOCAL DATA</div><h3>Your watch activity</h3><p>Watchlist and playback progress are stored on this device. Clearing browser storage will remove this local data.</p><button class="btn btn-quiet" data-clear-history>Clear watch history</button><button class="btn btn-quiet" data-clear-watchlist style="margin-left:6px">Clear watchlist</button></section>' +
      '<section class="settings-card"><div class="eyebrow">INSTALLATION</div><h3>Install AniDash</h3><p>Add the website to your device home screen or desktop app launcher for an app-like experience.</p><button class="btn btn-secondary" data-install>Installation guide</button></section>' +
      '<section class="settings-card"><div class="eyebrow">CATALOGUE</div><h3>AniList + MAL metadata</h3><p>Anime details, artwork, ratings and MyAnimeList IDs are read from the AniList public catalogue. No account sign-in is required for discovery.</p><a class="btn btn-quiet" href="https://docs.anilist.co/guide/graphql/" target="_blank" rel="noopener">API information ↗</a></section></div>';
  }

  function openModal(content) {
    $("#modal-root").innerHTML = '<div class="modal-backdrop" data-close-modal><section class="modal-card" role="dialog" aria-modal="true">' + content + '</section></div>';
    const cardEl = $(".modal-card");
    if (cardEl) cardEl.addEventListener("click", event => event.stopPropagation());
  }

  function closeModal() {
    $("#modal-root").innerHTML = "";
  }

  function openSourcesModal() {
    loadProviders().then(providers => {
      const manifest = store.providerManifest || { version: 1, providers: providers };
      openModal('<div class="modal-head"><div><div class="eyebrow">SOURCE CONNECTORS</div><h2>Connect your sources</h2><p>Paste your AniDash-compatible JSON source manifest. Sources must provide searchable anime, episode IDs and browser-playable stream URLs.</p></div><button class="close-modal" data-close>×</button></div>' +
        '<div class="form-field"><label for="source-config">Provider manifest (JSON)</label><textarea id="source-config" class="textarea-control" spellcheck="false">' + escapeHtml(JSON.stringify(manifest, null, 2)) + '</textarea><div class="form-help">Use the format from <code>sources.example.json</code>. This saves locally for this browser; edit the deployed watch-web/sources.json file to publish a source to everyone.</div></div>' +
        '<div class="modal-actions"><button class="btn btn-quiet" data-reset-sources>Reset local override</button><button class="btn btn-primary" data-save-sources>Save source manifest</button></div>');
    });
  }

  function openDirectModal() {
    const current = state.player && state.player.direct || "";
    openModal('<div class="modal-head"><div><div class="eyebrow">MANUAL SOURCE</div><h2>Paste a stream link</h2><p>Use an MP4 or HLS (.m3u8) URL that you own or are authorised to stream. The browser must be able to access it from this site.</p></div><button class="close-modal" data-close>×</button></div>' +
      '<div class="form-field"><label for="direct-url">Video URL</label><input class="input-control" id="direct-url" type="url" placeholder="https://media.example/video.m3u8" value="' + escapeHtml(current) + '"></div>' +
      '<div class="form-field"><label for="direct-subtitle">Optional English subtitle URL (.vtt)</label><input class="input-control" id="direct-subtitle" type="url" placeholder="https://media.example/subtitles/en.vtt"></div>' +
      '<div class="modal-actions"><button class="btn btn-quiet" data-close>Cancel</button><button class="btn btn-primary" data-save-direct>Play stream</button></div>');
  }

  function openInstallGuide() {
    const ua = navigator.userAgent || "";
    const ios = /iPhone|iPad|iPod/i.test(ua);
    const android = /Android/i.test(ua);
    const steps = ios ? [
      "Open this site in Safari.",
      "Tap the Share button in the browser toolbar.",
      "Choose Add to Home Screen, then tap Add."
    ] : android ? [
      "Open this site in Chrome or Samsung Internet.",
      "Open the browser menu and choose Install app or Add to Home screen.",
      "Confirm the installation."
    ] : [
      "Open this site in a supported browser such as Chrome, Edge or Safari.",
      "Use the install icon in the address bar or the Install AniDash button.",
      "Confirm to add AniDash to your desktop or app launcher."
    ];
    openModal('<div class="modal-head"><div><div class="eyebrow">INSTALL ANIDASH</div><h2>Take your anime corner with you</h2><p>AniDash can be installed as a Progressive Web App. The app shell works offline; catalogue and streaming still need an internet connection.</p></div><button class="close-modal" data-close>×</button></div><div class="install-guide">' +
      steps.map((step, index) => '<div class="install-step"><b>' + (index + 1) + '</b><span>' + escapeHtml(step) + '</span></div>').join("") +
      '</div><div class="modal-actions"><button class="btn btn-primary" data-close>Got it</button></div>');
  }

  function updateActiveNav(route) {
    const active = route === "/watch" ? "/history" : route;
    $$("[data-route]").forEach(item => {
      const value = item.getAttribute("data-route");
      item.classList.toggle("active", value === active || (route.startsWith("/anime") && value === "/discover"));
    });
  }

  async function route() {
    const hash = location.hash.replace(/^#/, "") || "/home";
    const parts = hash.split("?")[0].split("/").filter(Boolean);
    const current = "/" + (parts[0] || "home");
    state.route = current;
    updateActiveNav(current);
    if (current === "/home") return renderHome();
    if (current === "/discover") return renderDiscover();
    if (current === "/search") {
      const params = new URLSearchParams(hash.split("?")[1] || "");
      return renderSearch(params.get("q") || "");
    }
    if (current === "/library") return renderLibrary();
    if (current === "/history") return renderHistory();
    if (current === "/settings") return renderSettings();
    if (current === "/anime" && parts[1]) return renderAnime(parts[1]);
    if (current === "/watch" && parts[1]) return renderWatch(parts[1], parts[2] || "1");
    location.hash = "#/home";
  }

  function navigate(path) {
    location.hash = "#" + path;
  }

  async function submitSearch(term) {
    const value = String(term || "").trim();
    if (!value) return;
    navigate("/search?q=" + encodeURIComponent(value));
  }

  document.addEventListener("click", async event => {
    const target = event.target.closest("button,a,article");
    if (!target) {
      if (event.target.matches("[data-close-modal]")) closeModal();
      return;
    }
    if (target.hasAttribute("data-route")) {
      event.preventDefault();
      navigate(target.getAttribute("data-route"));
      return;
    }
    if (target.hasAttribute("data-anime")) {
      navigate("/anime/" + target.getAttribute("data-anime"));
      return;
    }
    if (target.hasAttribute("data-watchlist")) {
      toggleWatchlist(target.getAttribute("data-watchlist"));
      return;
    }
    if (target.hasAttribute("data-open-sources")) { openSourcesModal(); return; }
    if (target.hasAttribute("data-open-direct")) { openDirectModal(); return; }
    if (target.hasAttribute("data-install")) { openInstallGuide(); return; }
    if (target.hasAttribute("data-close")) { closeModal(); return; }
    if (target.hasAttribute("data-play-first")) {
      const first = state.detailEpisodes[0];
      if (first) startEpisode(first.number, first.id);
      return;
    }
    if (target.hasAttribute("data-play-episode")) {
      const pair = target.getAttribute("data-play-episode").split("|");
      startEpisode(pair[0], pair[1]);
      return;
    }
    if (target.hasAttribute("data-player-episode")) {
      const number = target.getAttribute("data-player-episode");
      const item = state.detailEpisodes.find(ep => Number(ep.number) === Number(number));
      if (item) {
        state.player.episode = item;
        state.player.direct = store.manualStreams[String(state.player.media.id) + ":" + String(item.number)] || "";
        navigate("/watch/" + state.player.media.id + "/" + item.number);
      }
      return;
    }
    if (target.hasAttribute("data-next") || target.hasAttribute("data-prev")) {
      const direction = target.hasAttribute("data-next") ? 1 : -1;
      const index = state.detailEpisodes.findIndex(ep => Number(ep.number) === Number(state.player.episode.number));
      const item = state.detailEpisodes[index + direction];
      if (item) {
        state.player.episode = item;
        state.player.direct = store.manualStreams[String(state.player.media.id) + ":" + String(item.number)] || "";
        navigate("/watch/" + state.player.media.id + "/" + item.number);
      }
      return;
    }
    if (target.hasAttribute("data-resume")) {
      const item = store.history[target.getAttribute("data-resume")];
      if (item) {
        const media = item.media;
        state.detail = media;
        state.detailEpisodes = generatedEpisodes(media);
        state.selectedMatch = null;
        state.player = { media: media, episode: { id: String(item.episode), number: item.episode, title: item.episodeTitle || "Episode " + item.episode }, match: null, streams: [], servers: [], tracks: [], selectedServer: "default", category: "sub", direct: store.manualStreams[String(media.id) + ":" + String(item.episode)] || "" };
        navigate("/watch/" + media.id + "/" + item.episode);
      }
      return;
    }
    if (target.hasAttribute("data-category")) {
      const category = target.getAttribute("data-category");
      state.player.category = category;
      $$("[data-category]").forEach(el => el.classList.toggle("active", el.getAttribute("data-category") === category));
      loadPlayerStreams(state.token);
      return;
    }
    if (target.hasAttribute("data-server")) {
      state.player.selectedServer = target.getAttribute("data-server");
      loadPlayerStreams(state.token);
      return;
    }
    if (target.hasAttribute("data-stream")) {
      const index = Number(target.getAttribute("data-stream"));
      const stream = state.player.streams[index];
      if (stream) {
        $$("[data-stream]").forEach(el => el.classList.toggle("active", Number(el.getAttribute("data-stream")) === index));
        attachStream(stream.url || stream.src || stream.file, stream, state.player.tracks);
      }
      return;
    }
    if (target.hasAttribute("data-skip")) {
      const video = $("#anime-video");
      const range = target.getAttribute("data-skip") === "intro" ? state.player.intro : state.player.outro;
      if (video && range && Number.isFinite(Number(range.end))) {
        video.currentTime = Number(range.end);
        video.play().catch(() => {});
      }
      return;
    }
    if (target.hasAttribute("data-save-sources")) {
      try {
        const manifest = JSON.parse($("#source-config").value);
        if (!manifest || !Array.isArray(manifest.providers)) throw new Error("The manifest must contain a providers array.");
        for (const provider of manifest.providers) {
          if (!provider.id || !provider.name || !provider.baseUrl || !provider.endpoints) throw new Error("Each provider needs id, name, baseUrl and endpoints.");
          const base = new URL(provider.baseUrl);
          if (base.protocol !== "https:" && base.hostname !== "localhost") throw new Error("Provider base URLs must use HTTPS.");
        }
        store.providerManifest = manifest;
        persist();
        state.providers = manifest.providers;
        closeModal();
        toast("Source manifest saved for this browser.");
        if (state.route === "/settings") renderSettings();
      } catch (error) { toast(error.message); }
      return;
    }
    if (target.hasAttribute("data-reset-sources")) {
      store.providerManifest = null;
      persist();
      state.providers = null;
      closeModal();
      toast("Local source override removed.");
      if (state.route === "/settings") renderSettings();
      return;
    }
    if (target.hasAttribute("data-save-direct")) {
      const url = String($("#direct-url").value || "").trim();
      try {
        const parsed = new URL(url);
        if (parsed.protocol !== "https:" && parsed.hostname !== "localhost") throw new Error("Use a valid HTTPS URL.");
        if (!state.player) throw new Error("Open an episode first.");
        const key = String(state.player.media.id) + ":" + String(state.player.episode.number);
        store.manualStreams[key] = url;
        persist();
        state.player.direct = url;
        const subtitle = String($("#direct-subtitle").value || "").trim();
        const tracks = subtitle ? [{ url: subtitle, lang: "English", type: "subtitles" }] : [];
        closeModal();
        const video = $("#anime-video");
        if (video) {
          state.player.tracks = tracks;
          attachStream(url, { quality: "Direct link", type: /\.m3u8(\?|$)/i.test(url) ? "hls" : "mp4" }, tracks);
        }
        toast("Stream link saved for this episode.");
      } catch (error) { toast(error.message); }
      return;
    }
    if (target.hasAttribute("data-clear-history")) {
      if (confirm("Clear all locally saved watch progress?")) {
        store.history = {};
        persist();
        renderHistory();
        toast("Watch history cleared.");
      }
      return;
    }
    if (target.hasAttribute("data-clear-watchlist")) {
      if (confirm("Clear your local watchlist?")) {
        store.watchlist = {};
        persist();
        renderLibrary();
        toast("Watchlist cleared.");
      }
      return;
    }
  });

  document.addEventListener("submit", event => {
    if (event.target.id === "search-form") {
      event.preventDefault();
      submitSearch($("#search-page-input").value);
    }
  });

  document.addEventListener("change", event => {
    if (event.target.id === "discover-sort") {
      state.discoverSort = event.target.value;
      renderDiscover();
    }
    if (event.target.id === "episode-source") {
      selectDetailProvider(event.target.value);
    }
  });

  document.addEventListener("input", event => {
    if (event.target.id === "episode-filter") {
      const term = slug(event.target.value);
      $$(".episode-item").forEach(item => {
        item.hidden = term && !slug(item.textContent).includes(term);
      });
    }
  });

  const globalSearch = $("#global-search");
  globalSearch.addEventListener("keydown", event => {
    if (event.key === "Enter") submitSearch(globalSearch.value);
  });

  window.addEventListener("beforeinstallprompt", event => {
    event.preventDefault();
    state.installEvent = event;
    const button = $(".install-button");
    if (button) button.style.color = "var(--accent)";
  });

  window.addEventListener("hashchange", route);
  window.addEventListener("online", () => toast("You are back online."));
  window.addEventListener("offline", () => toast("You are offline. The app shell is still available."));

  if ("serviceWorker" in navigator && location.protocol === "https:") {
    window.addEventListener("load", () => navigator.serviceWorker.register("/sw.js").catch(() => {}));
  }

  loadProviders();
  route();
})();