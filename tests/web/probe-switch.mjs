import { chromium } from 'playwright';

const BASE = process.argv[2] || 'http://localhost:4173';
const browser = await chromium.launch({
  channel: process.env.PW_CHANNEL || 'chrome',
  headless: true,
  args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox']
});
const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
page.on('console', m => { if (m.type() === 'error') console.log('  [console.error]', m.text()); });
page.on('pageerror', e => console.log('  [pageerror]', e.message));

await page.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => typeof window.openDetails === 'function', null, { timeout: 20000 });

// canPlayType probe
const cpt = await page.evaluate(() => {
  const v = document.createElement('video');
  return {
    apple: JSON.stringify(v.canPlayType('application/vnd.apple.mpegurl')),
    mpeg: JSON.stringify(v.canPlayType('application/x-mpegURL')),
    ts: JSON.stringify(v.canPlayType('video/mp2t')),
    mp4: JSON.stringify(v.canPlayType('video/mp4'))
  };
});
console.log('canPlayType:', cpt);

await page.evaluate(id => window.openDetails({ id, title: 'AniDash', cover: '' }), 21);
await page.waitForSelector('#playFirst', { timeout: 45000 });
await page.click('[data-tab="episodes"]');
await page.waitForSelector('#tabContent .episode', { timeout: 45000 });

// Episode 1
await page.click('#tabContent .episode');
await page.waitForSelector('#playerDialog[open]', { timeout: 20000 });
await page.waitForFunction(() => {
  const v = document.getElementById('video');
  return v && !v.paused && v.currentTime > 0.5;
}, null, { timeout: 75000 });
console.log('EP1 playing:', await page.evaluate(() => {
  const v = document.getElementById('video');
  return { t: v.currentTime.toFixed(2), d: v.duration.toFixed(0), w: v.videoWidth, h: v.videoHeight };
}));

// Inspect what the app resolved for ep1
const ep1 = await page.evaluate(() => ({
  sources: (window.state?.player?.sources || []).map(s => ({ server: s.server, q: s.quality, m3u8: s.isM3U8, url: s.url.slice(0, 90) })),
  index: window.state?.player?.index,
  hls: Boolean(window.state?.hls),
  levels: (window.state?.player?.levels || []).map(l => l.label)
}));
console.log('EP1 resolved:', JSON.stringify(ep1, null, 1));

// Switch to episode 2 via the drawer
await page.click('#playerEpisodesButton');
await page.waitForSelector('#playerEpisodes:not([hidden])', { timeout: 8000 });
await page.evaluate(() => {
  document.querySelectorAll('#playerEpisodeList .episode')[1]?.click();
});
console.log('clicked episode 2');

// Watch what happens for 30s
for (let i = 0; i < 10; i++) {
  await page.waitForTimeout(3000);
  const s = await page.evaluate(() => {
    const v = document.getElementById('video');
    return {
      t: +v.currentTime.toFixed(2),
      paused: v.paused,
      err: v.error ? { code: v.error.code, msg: v.error.message } : null,
      errShown: !document.getElementById('playerError').hidden,
      errText: document.getElementById('playerErrorBody').textContent,
      status: document.getElementById('playerStatus').textContent,
      loading: !document.getElementById('playerLoading').hidden,
      hls: Boolean(window.state?.hls),
      idx: window.state?.player?.index,
      src: (v.currentSrc || v.src || '').slice(0, 100)
    };
  });
  console.log(`  t+${(i + 1) * 3}s`, JSON.stringify(s));
  if (s.errShown) break;
}
await browser.close();
