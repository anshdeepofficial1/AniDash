/**
 * End-to-end browser checks for the AniDash watch player.
 *
 * Run against the Vercel-emulating dev server (or a deployed preview):
 *
 *   node tests/web/server.mjs 4173 &
 *   node tests/web/e2e-player.test.mjs [baseUrl]
 *
 * Playback checks drive the app's own engine (openDetails -> episode tab ->
 * playEpisode) rather than poking <video>.src, so a passing run is real
 * evidence that the shipped player resolves, attaches and decodes a stream.
 */
import { chromium } from 'playwright';

const BASE = process.argv[2] || 'http://localhost:4173';
const SERIES_ID = 21; // short, well seeded series used by the API tests
const results = [];
let failures = 0;

const record = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  if (!ok) failures += 1;
  console.log(`${ok ? '  ok  ' : ' FAIL '} ${name}${detail ? `  — ${detail}` : ''}`);
};

const check = async (name, fn, timeoutMs = 90000) => {
  try {
    const detail = await Promise.race([
      fn(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error(`timed out after ${timeoutMs}ms`)), timeoutMs)
      )
    ]);
    record(name, true, typeof detail === 'string' ? detail : '');
  } catch (error) {
    record(name, false, error?.message || String(error));
  }
};

// Allow overriding the browser channel via PW_CHANNEL (e.g. PW_CHANNEL=chromium
// on machines without a system Chrome install). Defaults to system Chrome.
const browser = await chromium.launch({
  channel: process.env.PW_CHANNEL || 'chrome',
  headless: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox']
});

try {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    userAgent: 'AniDash-E2E/1.0'
  });

  const page = await context.newPage();
  const consoleErrors = [];
  page.on('console', message => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('pageerror', error => consoleErrors.push(`pageerror: ${error.message}`));

  const isPlaying = () =>
    page.evaluate(() => {
      const video = document.getElementById('video');
      return {
        playing: Boolean(video && !video.paused && video.currentTime > 0),
        time: video?.currentTime || 0,
        duration: video?.duration || 0,
        width: video?.videoWidth || 0,
        height: video?.videoHeight || 0,
        buffered: video?.buffered?.length || 0,
        hlsAttached: Boolean(window.__anidashHlsAttached ?? false),
        status: document.getElementById('playerStatus')?.textContent || '',
        loading: !document.getElementById('playerLoading')?.hidden,
        error: !document.getElementById('playerError')?.hidden,
        errorText: document.getElementById('playerErrorBody')?.textContent || ''
      };
    });

  // ---------------------------------------------------------------- app boot
  await check('app boots without a crash', async () => {
    await page.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#app', { timeout: 20000 });
    await page.waitForFunction(() => typeof window.openDetails === 'function', null, { timeout: 15000 });
    return 'ready';
  });

  await check('hls.js loads from the vendored copy before app.js', async () => {
    const state = await page.evaluate(() => ({
      hls: typeof window.Hls,
      supported: Boolean(window.Hls && window.Hls.isSupported()),
      scripts: [...document.querySelectorAll('script[src]')].map(s => s.getAttribute('src'))
    }));
    if (state.hls !== 'function') throw new Error(`window.Hls is ${state.hls}`);
    if (!state.supported) throw new Error('Hls.isSupported() is false in Chrome');
    if (!state.scripts.some(src => /vendor\/hls-/.test(src))) {
      throw new Error(`vendored hls not requested: ${state.scripts.join(', ')}`);
    }
    return state.scripts.join(' -> ');
  });

  await check('no page-level script errors during boot', async () => {
    const fatal = consoleErrors.filter(text => !/favicon|ERR_|Failed to load resource/.test(text));
    if (fatal.length) throw new Error(fatal.slice(0, 3).join(' | '));
    return 'clean';
  });

  // ------------------------------------------------------ local assets/icons
  await check('icons and manifest resolve to local files', async () => {
    const icons = await page.evaluate(() =>
      [...document.querySelectorAll('link[rel="icon"],link[rel="apple-touch-icon"],link[rel="manifest"]')]
        .map(link => link.getAttribute('href'))
    );
    if (!icons.length) throw new Error('no icon links');
    const remote = icons.filter(href => /^https?:\/\//.test(href));
    if (remote.length) throw new Error(`remote asset reference: ${remote.join(', ')}`);
    const statuses = await Promise.all(
      icons.map(href => page.request.get(new URL(href, BASE + '/').href).then(r => r.status()))
    );
    const bad = statuses.filter(status => status !== 200);
    if (bad.length) throw new Error(`fetch failed: ${bad.join(',')}`);
    return icons.join(', ');
  });

  await check('service worker registers', async () => {
    const info = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return { present: false };
      const registration = await navigator.serviceWorker.ready.catch(() => null);
      return { present: true, scoped: registration?.scope || '' };
    });
    if (!info.present) throw new Error('serviceWorker missing');
    if (!info.scoped) throw new Error('no active registration');
    return info.scoped;
  });

  // ----------------------------------------------------------- search / open
  await check('search endpoint returns titles', async () => {
    const count = await page.evaluate(async () => {
      const response = await fetch('/api/anidash?action=search&query=naruto');
      const payload = await response.json();
      return (payload.results || []).length;
    });
    if (!count) throw new Error('no search results');
    return `${count} results`;
  });

  await check('details page opens and lists real episodes', async () => {
    await page.evaluate(id => window.openDetails({ id, title: 'AniDash', cover: '' }), SERIES_ID);
    await page.waitForSelector('#playFirst', { timeout: 45000 });
    await page.click('[data-tab="episodes"]');
    await page.waitForSelector('#tabContent .episode', { timeout: 45000 });
    const info = await page.evaluate(() => ({
      count: document.querySelectorAll('#tabContent .episode').length,
      first: document.querySelector('#tabContent .episode')?.textContent?.trim().slice(0, 40),
      note: document.querySelector('#tabContent .episode-loading-note')?.textContent || ''
    }));
    if (!info.count) throw new Error('episode list empty');
    return `${info.count} episodes${info.note ? ` (${info.note})` : ''}`;
  });

  // -------------------------------------------------------------- the player
  await check('custom control bar replaces native video controls', async () => {
    const info = await page.evaluate(() => {
      const ids = [
        'playerPlay', 'playerBigPlay', 'playerBack10', 'playerForward10',
        'playerPrev', 'playerNext', 'playerMute', 'playerVolume',
        'playerSubsBtn', 'playerAudioBtn', 'playerSpeedBtn', 'playerQualityBtn',
        'playerPiP', 'playerFull', 'playerEpisodesButton', 'playerProgress',
        'playerSkipIntro', 'playerNextEpisode', 'playerError', 'playerEpisodes'
      ];
      return {
        missing: ids.filter(id => !document.getElementById(id)),
        native: document.getElementById('video').hasAttribute('controls')
      };
    });
    if (info.missing.length) throw new Error(`missing: ${info.missing.join(', ')}`);
    if (info.native) throw new Error('video still uses native controls');
    return '20 controls present';
  });

  await check('clicking an episode starts real playback through the app engine', async () => {
    await page.click('#tabContent .episode');
    await page.waitForSelector('#playerDialog[open]', { timeout: 20000 });

    const deadline = Date.now() + 75000;
    let last;
    while (Date.now() < deadline) {
      last = await isPlaying();
      if (last.error) throw new Error(`player reported: ${last.errorText}`);
      if (last.playing && last.width > 0 && last.height > 0 && last.time > 0.5) break;
      await page.waitForTimeout(1000);
    }
    if (!last.playing) {
      throw new Error(`never reached playing (time=${last.time}, status="${last.status}", loading=${last.loading})`);
    }
    if (!last.width || !last.height) throw new Error(`no frames decoded (${last.width}x${last.height})`);
    return `${last.width}x${last.height} at ${last.time.toFixed(2)}s of ${last.duration.toFixed(0)}s`;
  });

  await check('progress bar tracks the playhead and duration resolves', async () => {
    await page.waitForFunction(
      () => parseFloat(document.getElementById('playerPlayed').style.width || '0') > 0,
      null,
      { timeout: 25000 }
    );
    const state = await page.evaluate(() => ({
      played: document.getElementById('playerPlayed').style.width,
      buffered: document.getElementById('playerBuffer').style.width,
      current: document.getElementById('playerCurrent').textContent,
      duration: document.getElementById('playerDuration').textContent,
      label: document.getElementById('playerProgress').getAttribute('aria-valuetext')
    }));
    if (state.duration === '--:--') throw new Error('duration not resolved');
    if (!state.buffered || parseFloat(state.buffered) <= 0) throw new Error('buffer bar never filled');
    return `${state.current} / ${state.duration} (played ${state.played}, buffered ${state.buffered})`;
  });

  await check('controls reveal on interaction, then auto-hide while playing', async () => {
    await page.mouse.move(640, 300);
    await page.waitForFunction(
      () => document.getElementById('playerDialog').classList.contains('controls-visible'),
      null,
      { timeout: 8000 }
    );
    await page.waitForFunction(
      () => !document.getElementById('playerDialog').classList.contains('controls-visible'),
      null,
      { timeout: 15000 }
    );
    return 'revealed then auto-hid';
  });

  await check('keyboard shortcuts seek and toggle play', async () => {
    const before = await page.evaluate(() => document.getElementById('video').currentTime);
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(900);
    const after = await page.evaluate(() => document.getElementById('video').currentTime);
    if (after <= before + 5) throw new Error(`seek did not advance (${before} -> ${after})`);

    await page.keyboard.press('k');
    await page.waitForTimeout(500);
    if (!(await page.evaluate(() => document.getElementById('video').paused))) throw new Error('K did not pause');
    await page.keyboard.press('k');
    await page.waitForTimeout(900);
    if (await page.evaluate(() => document.getElementById('video').paused)) throw new Error('K did not resume');
    return `seeked ${before.toFixed(1)} -> ${after.toFixed(1)}`;
  });

  await check('quality menu lists renditions from the manifest', async () => {
    await page.mouse.move(640, 300);
    await page.click('#playerQualityBtn');
    await page.waitForSelector('#playerQualityMenu .player-menu-item', { timeout: 10000 });
    const options = await page.evaluate(() =>
      [...document.querySelectorAll('#playerQualityMenu .player-menu-item')]
        .map(item => item.textContent.trim())
    );
    if (options.length < 2) throw new Error(`only ${options.length} options`);
    return options.join(', ');
  });

  await check('selecting a quality level switches the rendition', async () => {
    const target = await page.evaluate(() => {
      const items = [...document.querySelectorAll('#playerQualityMenu .player-menu-item')];
      const item = items.find(node => /p$/.test(node.dataset.value)) || items[1];
      item?.click();
      return item?.textContent?.trim() || '';
    });
    await page.waitForTimeout(2500);
    const state = await isPlaying();
    if (!state.playing) throw new Error(`playback stopped after switching to ${target}`);
    const label = await page.evaluate(() => document.getElementById('playerQualityBtn').textContent);
    return `${label} still playing`;
  });

  await check('speed menu changes playbackRate and persists the preference', async () => {
    await page.click('#playerSpeedBtn');
    await page.waitForSelector('#playerSpeedMenu .player-menu-item', { timeout: 10000 });
    await page.evaluate(() => {
      [...document.querySelectorAll('#playerSpeedMenu .player-menu-item')]
        .find(node => node.dataset.value === '1.5')?.click();
    });
    const rate = await page.evaluate(() => document.getElementById('video').playbackRate);
    if (Math.abs(rate - 1.5) > 0.01) throw new Error(`playbackRate is ${rate}`);
    const stored = await page.evaluate(() => JSON.parse(localStorage.getItem('anidash-web-settings') || '{}').playbackSpeed);
    if (Number(stored) !== 1.5) throw new Error(`not persisted (${stored})`);
    // restore
    await page.evaluate(() => {
      [...document.querySelectorAll('#playerSpeedMenu .player-menu-item')]
        .find(node => node.dataset.value === '1')?.click();
    });
    return `${rate}x, stored`;
  });

  await check('subtitle menu renders episode subtitles', async () => {
    await page.click('#playerSubsBtn');
    await page.waitForSelector('#playerSubsMenu', { timeout: 8000 });
    const info = await page.evaluate(() => ({
      note: document.querySelector('#playerSubsMenu .player-menu-note')?.textContent || '',
      items: [...document.querySelectorAll('#playerSubsMenu .player-menu-item')]
        .map(item => item.textContent.trim())
    }));
    if (!info.note && !info.items.length) throw new Error('subtitle menu empty');
    return info.items.length ? info.items.join(', ') : info.note;
  });

  await check('volume control changes the element volume', async () => {
    await page.evaluate(() => {
      const slider = document.getElementById('playerVolume');
      slider.value = '0.4';
      slider.dispatchEvent(new Event('input'));
    });
    const state = await page.evaluate(() => ({
      volume: document.getElementById('video').volume,
      muted: document.getElementById('video').muted,
      icon: document.getElementById('playerMute').dataset.muted
    }));
    if (Math.abs(state.volume - 0.4) > 0.02) throw new Error(`volume is ${state.volume}`);
    if (state.icon !== 'false') throw new Error('mute icon not synced');
    return state.volume.toFixed(2);
  });

  await check('episode drawer opens and lists episodes', async () => {
    await page.click('#playerEpisodesButton');
    await page.waitForSelector('#playerEpisodes:not([hidden])', { timeout: 8000 });
    const info = await page.evaluate(() => ({
      count: document.querySelectorAll('#playerEpisodeList .episode').length,
      label: document.getElementById('playerEpisodeCount').textContent
    }));
    if (!info.count) throw new Error('drawer list empty');
    return `${info.count} episodes (${info.label})`;
  });

  await check('switching episodes keeps playing', async () => {
    const jumped = await page.evaluate(() => {
      const items = [...document.querySelectorAll('#playerEpisodeList .episode')];
      const next = items[1];
      if (!next) return false;
      next.click();
      return true;
    });
    if (!jumped) throw new Error('no second episode to switch to');

    const deadline = Date.now() + 60000;
    let last;
    while (Date.now() < deadline) {
      last = await isPlaying();
      if (last.error) throw new Error(`player reported: ${last.errorText}`);
      if (last.playing && last.time > 0.3) break;
      await page.waitForTimeout(1000);
    }
    if (!last.playing) throw new Error(`episode switch did not resume (status="${last.status}")`);

    // Let a few seconds of real playback accrue so the persisted position is
    // meaningful (progress is stored floored to whole seconds).
    await page.waitForTimeout(6000);
    last = await isPlaying();
    if (!last.playing) throw new Error('playback stopped while waiting');
    const title = await page.evaluate(() => document.getElementById('playerTitle').textContent);
    return `${title} at ${last.time.toFixed(1)}s`;
  });

  await check('back button persists progress to anidash-progress', async () => {
    await page.evaluate(() => document.querySelector('.player-back').click());
    await page.waitForFunction(() => !document.getElementById('playerDialog').open, null, { timeout: 8000 });
    const saved = await page.evaluate(() => {
      const raw = localStorage.getItem('anidash-progress');
      return raw ? JSON.parse(raw) : null;
    });
    if (!saved || !Array.isArray(saved)) throw new Error('anidash-progress not written');
    if (!saved.length) throw new Error('progress list empty');
    const entry = saved[0];
    if (!entry.progressSeconds) throw new Error(`no progressSeconds in ${JSON.stringify(entry)}`);
    return `${saved.length} entries, latest E${entry.episode} at ${entry.progressSeconds}s`;
  });

  // --------------------------------------------------------- persistence/UI
  await check('existing localStorage keys survive untouched', async () => {
    const state = await page.evaluate(() => ({
      keys: Object.keys(localStorage).sort(),
      settings: JSON.parse(localStorage.getItem('anidash-web-settings') || 'null')
    }));
    for (const expected of ['anidash-progress', 'anidash-web-settings']) {
      if (!state.keys.includes(expected)) throw new Error(`${expected} missing`);
    }
    if (!state.settings) throw new Error('anidash-web-settings not an object');
    return state.keys.join(', ');
  });

  await check('resume works: reopening the episode restores the saved position', async () => {
    const before = await page.evaluate(() => {
      const raw = localStorage.getItem('anidash-progress');
      const list = raw ? JSON.parse(raw) : [];
      return list[0]?.progressSeconds || 0;
    });
    if (before < 2) throw new Error(`not enough progress saved (${before}s) to test resume`);

    await page.click('[data-tab="episodes"]');
    await page.waitForSelector('#tabContent .episode', { timeout: 30000 });
    await page.click('#tabContent .episode');
    await page.waitForSelector('#playerDialog[open]', { timeout: 20000 });

    const deadline = Date.now() + 70000;
    let time = 0;
    while (Date.now() < deadline) {
      const state = await isPlaying();
      if (state.error) throw new Error(`player reported: ${state.errorText}`);
      time = state.time;
      if (time > 0.5) break;
      await page.waitForTimeout(1000);
    }
    if (time < 0.5) throw new Error('reopened episode never started');
    const resumedNear = Math.abs(time - before) < 45;
    if (!resumedNear) throw new Error(`resume missed: saved ${before}s, playing at ${time.toFixed(1)}s`);
    await page.evaluate(() => document.querySelector('.player-back').click());
    return `saved ${before}s -> resumed at ${time.toFixed(1)}s`;
  });

  await check('responsive: mobile viewport renders the bottom nav', async () => {
    const mobile = await context.newPage();
    await mobile.setViewportSize({ width: 390, height: 844 });
    await mobile.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
    await mobile.waitForSelector('.bottom-nav', { timeout: 20000 });
    const visible = await mobile.evaluate(() =>
      getComputedStyle(document.querySelector('.bottom-nav')).display !== 'none'
    );
    await mobile.close();
    if (!visible) throw new Error('bottom nav hidden on mobile');
    return 'ok';
  });

  await check('no console errors after the full run', async () => {
    const fatal = consoleErrors.filter(text => !/favicon|ERR_BLOCKED_BY_CLIENT|Failed to load resource/.test(text));
    if (fatal.length) throw new Error(fatal.slice(0, 3).join(' | '));
    return `${consoleErrors.length} benign`;
  });
} finally {
  await browser.close();
}

console.log(`\n${results.length - failures} passed, ${failures} failed`);
process.exit(failures ? 1 : 0);
