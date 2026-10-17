/**
 * Unit tests for the pure helpers inside website/watch/api/media.js
 *
 * Usage: node tests/web/media-unit.test.mjs
 */
import { safeHeaders, rewritePlaylist, hostAllowed, isPrivateHost, blockedTarget } from '../../website/watch/api/media.js';

let passed = 0;
let failed = 0;
const failures = [];

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

console.log('\n== rewritePlaylist ==');

const headersJson = JSON.stringify({ Referer: 'https://megaplay.buzz/' });

const master = [
  '#EXTM3U',
  '#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1201097,RESOLUTION=1440x1080,CODECS="avc1.640028,mp4a.40.2"',
  'index-f1-v1-a1.m3u8',
  '#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=40570,URI="iframes-f3-v1-a1.m3u8"',
  '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio-en.m3u8"',
  '',
].join('\n');

const outMaster = rewritePlaylist(master, 'https://fetch.nexabloom.top/anime/x/master.m3u8?token=abc', headersJson);
const masterLines = outMaster.split('\n');
const variantLine = masterLines[2];
const iframeLine = masterLines[3];
const mediaLine = masterLines[4];

check('variant URI is proxied', variantLine.startsWith('/api/media?') && variantLine.includes('index-f1-v1-a1.m3u8'), variantLine);
check('variant marked as playlist', variantLine.includes('hls=1'), variantLine);
check('variant URI resolves against playlist base', variantLine.includes(encodeURIComponent('https://fetch.nexabloom.top/anime/x/index-f1-v1-a1.m3u8')), variantLine.slice(0, 200));
check('iframe playlist URI proxied', iframeLine.includes('URI="/api/media?') && iframeLine.includes('iframes-f3-v1-a1.m3u8'), iframeLine);
check('EXT-X-MEDIA URI proxied', mediaLine.includes('URI="/api/media?') && mediaLine.includes('audio-en.m3u8'), mediaLine);
check('non-URI attributes preserved', mediaLine.includes('GROUP-ID="aud"') && mediaLine.includes('DEFAULT=YES'), mediaLine);
check('headers survive every rewrite', outMaster.includes(encodeURIComponent(headersJson)));

const mediaPlaylist = [
  '#EXTM3U',
  '#EXT-X-VERSION:3',
  '#EXT-X-TARGETDURATION:13',
  '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x1234',
  '#EXT-X-MAP:URI="init.mp4"',
  '#EXTINF:11.386,',
  'seg-1-f1-v1-a1.ts',
  '#EXTINF:8.842,',
  'https://7v8gl.eclipseharbor.space/anime/seg-2.ts',
  '',
].join('\r\n');

const outMedia = rewritePlaylist(mediaPlaylist, 'https://fetch.nexabloom.top/anime/x/index.m3u8?token=abc', headersJson);
check('EXT-X-KEY URI proxied', outMedia.includes('#EXT-X-KEY:METHOD=AES-128,URI="/api/media?'), outMedia);
check('EXT-X-KEY IV preserved', outMedia.includes('IV=0x1234'));
check('EXT-X-MAP URI proxied', outMedia.includes('#EXT-X-MAP:URI="/api/media?'), outMedia);
check('relative segment proxied', /#EXTINF:11\.386,\r?\n\/api\/media\?/.test(outMedia), outMedia);
check('absolute cross-host segment proxied', outMedia.includes(encodeURIComponent('https://7v8gl.eclipseharbor.space/anime/seg-2.ts')));
check('segment is not marked as a playlist', !/seg-2\.ts[^"]*&hls=1/.test(outMedia));
check('CRLF line endings preserved', outMedia.split('\r\n').length === mediaPlaylist.split('\r\n').length);

const weird = rewritePlaylist(
  '#EXTM3U\n#EXT-X-DATERANGE:ID="x",URI="https://[bad"\nnot-a-playlist-line\n',
  'https://fetch.nexabloom.top/dir/a.m3u8',
  '{}'
);
check('unresolvable URI falls back to original', weird.includes('URI="https://[bad"'), weird);
check('plain line is proxied against the playlist dir', weird.includes(encodeURIComponent('https://fetch.nexabloom.top/dir/not-a-playlist-line')), weird);

console.log('\n== safeHeaders ==');
const filtered = safeHeaders(
  JSON.stringify({
    Referer: 'https://megaplay.buzz/',
    Origin: 'https://megaplay.buzz',
    'User-Agent': 'Mozilla/5.0',
    Cookie: 'secret=1',
    Authorization: 'Bearer nope',
    Host: 'evil.test',
    'X-Custom': 'nope',
    'X-Injected': 'a\r\nX-Evil: 1',
    Empty: '',
  })
);
check('Referer forwarded', filtered.Referer === 'https://megaplay.buzz/', JSON.stringify(filtered));
check('Origin forwarded', filtered.Origin === 'https://megaplay.buzz');
check('User-Agent forwarded', filtered['User-Agent'] === 'Mozilla/5.0');
check('Cookie stripped', !('Cookie' in filtered) && !('cookie' in filtered));
check('Authorization stripped', !('Authorization' in filtered));
check('Host stripped', !('Host' in filtered));
check('unknown header stripped', !('X-Custom' in filtered));
check('CRLF value stripped', !('X-Injected' in filtered));
check('empty value stripped', !('Empty' in filtered));

const badJson = safeHeaders('{not json');
check('invalid JSON yields empty headers', Object.keys(badJson).length === 0, JSON.stringify(badJson));

const crlfReferer = safeHeaders(JSON.stringify({ Referer: 'https://a.test/\r\nX-Evil: 1' }));
check('CRLF inside Referer drops the value', !('Referer' in crlfReferer), JSON.stringify(crlfReferer));

console.log('\n== host allow list ==');
check('playlist host allowed', hostAllowed('fetch.nexabloom.top'));
check('segment host allowed', hostAllowed('7v8gl.eclipseharbor.space'));
check('subdomain allowed', hostAllowed('s121.vidcache.net'));
check('lookalike suffix rejected', !hostAllowed('notnexabloom.top'));
check('unrelated host rejected', !hostAllowed('example.com'));
check('empty host rejected', !hostAllowed(''));

console.log('\n== private / SSRF guard ==');
check('127.0.0.1 blocked', isPrivateHost('127.0.0.1'));
check('10.x blocked', isPrivateHost('10.0.0.5'));
check('172.16 blocked', isPrivateHost('172.16.1.1'));
check('192.168 blocked', isPrivateHost('192.168.0.1'));
check('169.254 blocked', isPrivateHost('169.254.169.254'));
check('localhost blocked', isPrivateHost('localhost'));
check('IPv6 loopback blocked', isPrivateHost('::1'));
check('public host allowed', !isPrivateHost('fetch.nexabloom.top'));
check('172.32 not private', !isPrivateHost('172.32.0.1'));

check('http target blocked', blockedTarget(new URL('http://fetch.nexabloom.top/a.m3u8')));
check('https target allowed', !blockedTarget(new URL('https://fetch.nexabloom.top/a.m3u8')));
check('credentials blocked', blockedTarget(new URL('https://user:pass@fetch.nexabloom.top/a.m3u8')));

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) {
  console.log('failures:');
  for (const failure of failures) console.log('  - ' + failure);
  process.exitCode = 1;
}
