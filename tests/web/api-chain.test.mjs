/**
 * End-to-end API chain test.
 *
 * Runs against the local Vercel-emulating server and the *real* upstream
 * content CDNs (no mocks): source resolution -> master playlist -> variant
 * playlist -> media segment, plus the MP4/Range path and the proxy's security
 * rules.
 *
 * Usage: node tests/web/api-chain.test.mjs [baseUrl]
 */
const BASE = process.argv[2] || 'http://localhost:4173';

let passed = 0;
let failed = 0;
const failures = [];
const timings = {};

function check(name, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`  ok   ${name}`);
  } else {
    failed += 1;
    failures.push(`${name} ${detail}`);
    console.log(`  FAIL ${name} ${detail}`);
  }
}

async function get(path, init = {}, label = null) {
  const start = Date.now();
  const response = await fetch(BASE + path, init);
  const buffer = Buffer.from(await response.arrayBuffer());
  const ms = Date.now() - start;
  if (label) timings[label] = ms;
  return {
    status: response.status,
    ok: response.ok,
    headers: response.headers,
    buffer,
    ms,
    text: () => buffer.toString('utf8'),
    json: () => JSON.parse(buffer.toString('utf8')),
  };
}

console.log('\n== 1. source resolution ==');
const source = await get('/api/anidash?action=source&id=21&episode=1&audio=sub', {}, 'resolveSource');

check('source returns 200', source.status === 200, `got ${source.status}`);
const payload = source.status === 200 ? source.json() : { sources: [] };
const sources = payload.sources || [];
check('source list is not empty', sources.length > 0);
check(
  'sources are same-origin /api/media links',
  sources.length > 0 && sources.every(s => s.url.startsWith('/api/media?')),
  JSON.stringify(sources.map(s => String(s.url).slice(0, 30)))
);
check('no dead neko.justanime.to reference survives', !JSON.stringify(payload).includes('neko.justanime.to'));
const hlsSource = sources.find(s => s.isM3U8);
check('an HLS source is offered', Boolean(hlsSource));
console.log(
  `  ..   resolveSource ${source.ms}ms, ${sources.length} sources, servers=${(payload.resolvedServers || []).join(',')}`
);

let segmentLines = [];

if (hlsSource) {
  console.log('\n== 2. master playlist ==');
  const master = await get(hlsSource.url, {}, 'masterPlaylist');
  check('master playlist is 200', master.status === 200, `got ${master.status}`);
  const masterBody = master.text();
  check('master starts with #EXTM3U', masterBody.trimStart().startsWith('#EXTM3U'));
  check(
    'content-type is an HLS type',
    /mpegurl/i.test(master.headers.get('content-type') || ''),
    String(master.headers.get('content-type'))
  );
  const masterLines = masterBody.split('\n').map(l => l.trim()).filter(Boolean);
  const variants = masterLines.filter(l => !l.startsWith('#'));
  check(
    'variant playlist URIs are proxied',
    variants.length > 0 && variants.every(v => v.startsWith('/api/media?')),
    JSON.stringify(variants.slice(0, 3))
  );
  console.log(`  ..   masterPlaylist ${master.ms}ms, ${variants.length} variant(s)`);

  console.log('\n== 3. variant playlist ==');
  const variant = await get(variants[0], {}, 'variantPlaylist');
  check('variant playlist is 200', variant.status === 200, `got ${variant.status}`);
  const variantBody = variant.text();
  check('variant starts with #EXTM3U', variantBody.trimStart().startsWith('#EXTM3U'));
  segmentLines = variantBody
    .split('\n')
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));
  check(
    'segment URIs are proxied',
    segmentLines.length > 0 && segmentLines.every(s => s.startsWith('/api/media?')),
    JSON.stringify(segmentLines.slice(0, 2))
  );
  check('segment URIs carry upstream headers', segmentLines.length > 0 && segmentLines.every(s => s.includes('headers=')));
  console.log(`  ..   variantPlaylist ${variant.ms}ms, ${segmentLines.length} segments`);

  if (segmentLines.length) {
    console.log('\n== 4. media segment ==');
    const segment = await get(segmentLines[0], {}, 'segment');
    check('segment is 200', segment.status === 200, `got ${segment.status}`);
    const type = segment.headers.get('content-type') || '';
    check('segment is not an HTML error page', !/text\/html/i.test(type), type);
    check('segment carries real bytes', segment.buffer.length > 1024, `${segment.buffer.length} bytes`);
    check(
      'segment exposes accept-ranges',
      Boolean(segment.headers.get('accept-ranges')),
      String(segment.headers.get('accept-ranges'))
    );
    console.log(`  ..   segment ${segment.ms}ms, ${segment.buffer.length} bytes, ${type}`);

    if (segmentLines[1]) {
      const again = await get(segmentLines[1], {}, 'segmentCached');
      check('second segment plays', again.status === 200, `got ${again.status}`);
      console.log(`  ..   segmentCached ${again.ms}ms`);
    }
  }

  console.log('\n== 5. sequential playback (8 segments) ==');
  let playable = 0;
  const walkStart = Date.now();
  for (const line of segmentLines.slice(0, 8)) {
    const res = await fetch(BASE + line);
    const bytes = Buffer.from(await res.arrayBuffer());
    if (res.status === 200 && bytes.length > 1024 && !/text\/html/.test(res.headers.get('content-type') || '')) {
      playable += 1;
    }
  }
  const walkMs = Date.now() - walkStart;
  timings.segmentWalk = walkMs;
  check('consecutive segments keep playing', playable >= 6, `${playable}/8 ok`);
  console.log(`  ..   ${playable}/8 segments ok in ${walkMs}ms (${Math.round(walkMs / 8)}ms each)`);
}

console.log('\n== 6. MP4 source with Range ==');
const mp4Source = sources.find(s => !s.isM3U8);
if (mp4Source) {
  const start = Date.now();
  const response = await fetch(BASE + mp4Source.url, { headers: { Range: 'bytes=0-2047' } });
  timings.mp4Range = Date.now() - start;
  const status = response.status;
  const declared = Number(response.headers.get('content-length') || 0);
  let body = null;
  if (status === 206 || declared <= 8 * 1024 * 1024) {
    body = Buffer.from(await response.arrayBuffer());
  } else {
    await response.body?.cancel();
  }

  check('range request returns 200 or 206', status === 206 || status === 200, `got ${status}`);
  check(
    'content-type is video',
    /video|octet-stream/i.test(response.headers.get('content-type') || ''),
    String(response.headers.get('content-type'))
  );
  check(
    'range bytes are correct',
    status !== 206 || (response.headers.get('content-range') || '').startsWith('bytes 0-2047/'),
    String(response.headers.get('content-range'))
  );
  check('range body has payload', Boolean(body && body.length >= 2048), body ? `${body.length} bytes` : 'unbounded body');
  console.log(
    `  ..   mp4Range ${timings.mp4Range}ms status=${status} type=${response.headers.get('content-type')}`
  );
} else {
  console.log('  skip no MP4 source for this episode');
}

console.log('\n== 7. proxy security rules ==');
const forbidden = await get('/api/media?url=' + encodeURIComponent('https://evil.example.com/x.m3u8'));
check('unknown host rejected', forbidden.status === 403, `got ${forbidden.status}`);

const privateHost = await get('/api/media?url=' + encodeURIComponent('https://127.0.0.1/x.mp4'));
check('loopback target rejected', privateHost.status === 400, `got ${privateHost.status}`);

const metadataIp = await get('/api/media?url=' + encodeURIComponent('https://169.254.169.254/latest/meta-data/'));
check('link-local target rejected', metadataIp.status === 400, `got ${metadataIp.status}`);

const notUrl = await get('/api/media?url=not-a-url');
check('malformed target rejected', notUrl.status === 400, `got ${notUrl.status}`);

const noQuery = await get('/api/media');
check('missing url rejected', noQuery.status === 400, `got ${noQuery.status}`);

const headerInjection = await get(
  '/api/media?url=' +
    encodeURIComponent('https://fetch.nexabloom.top/x.m3u8') +
    '&headers=' +
    encodeURIComponent(
      JSON.stringify({ 'X-Secret': 'leak', Referer: 'https://megaplay.buzz/\r\nX-Injected: 1' })
    )
);
check('bad upstream headers never crash the proxy', headerInjection.status !== 500, `got ${headerInjection.status}`);

console.log('\n== 8. other endpoints ==');
const search = await get('/api/anidash?action=search&query=naruto&page=1', {}, 'search');
check('search works', search.status === 200 && Array.isArray(search.json().results), `got ${search.status}`);

const episodes = await get('/api/anidash?action=episodes&id=21&page=1', {}, 'episodes');
check('episodes work', episodes.status === 200 && Array.isArray(episodes.json().episodes), `got ${episodes.status}`);
check('episode list has entries', episodes.status === 200 && episodes.json().episodes.length > 0);

const news = await get('/api/news', {}, 'news');
check('news works', news.status === 200 && Array.isArray(news.json().items), `got ${news.status}`);

const hls = await get('/api/hls', {}, 'hls');
check('hls.js served', hls.status === 200 && hls.buffer.length > 400000, `${hls.status} ${hls.buffer.length}`);

const badEpisode = await get('/api/anidash?action=source&id=abc&episode=1');
check('invalid id rejected', badEpisode.status === 400, `got ${badEpisode.status}`);

const badAction = await get('/api/anidash?action=nope');
check('invalid action rejected', badAction.status === 400, `got ${badAction.status}`);

console.log('\n== timings (ms) ==');
for (const [label, value] of Object.entries(timings)) {
  console.log(`  ${label.padEnd(18)} ${value}`);
}

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) {
  console.log('failures:');
  for (const failure of failures) console.log('  - ' + failure);
  process.exitCode = 1;
}
