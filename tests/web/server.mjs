/**
 * Local development / test server that reproduces the Vercel project used by
 * https://anidash-watch.vercel.app
 *
 *   Root directory : <repo>/website/watch
 *   Config file    : <repo>/website/watch/vercel.json
 *
 * It implements the parts of Vercel's routing pipeline we depend on:
 *   1. redirects   (cleanUrls, trailingSlash)
 *   2. filesystem  (static files + directory index)
 *   3. rewrites    (verbatim from vercel.json)
 *   4. headers     (verbatim from vercel.json)
 *   5. functions   (/api/<name> -> website/watch/api/<name>.js default export)
 *
 * Usage: node tests/web/server.mjs [port]
 */
import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../website/watch');
const CONFIG = JSON.parse(await fsp.readFile(path.join(ROOT, 'vercel.json'), 'utf8'));

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.vtt': 'text/vtt; charset=utf-8',
};

const handlerCache = new Map();

function loadHandler(name) {
  if (handlerCache.has(name)) return handlerCache.get(name);
  const file = path.join(ROOT, 'api', `${name}.js`);
  if (!fs.existsSync(file)) return null;
  const promise = import(pathToFileURL(file).href)
    .then(mod => mod.default)
    .catch(error => {
      console.error(`[functions] failed to load api/${name}.js:`, error.message);
      return null;
    });
  handlerCache.set(name, promise);
  return promise;
}

function patchResponse(res) {
  res.status = code => {
    res.statusCode = code;
    return res;
  };
  res.json = payload => {
    if (!res.getHeader('content-type')) {
      res.setHeader('content-type', 'application/json; charset=utf-8');
    }
    if (!res.headersSent) res.setHeader('cache-control', res.getHeader('cache-control') || 'no-store');
    res.end(JSON.stringify(payload));
    return res;
  };
  res.send = body => {
    if (body === undefined || body === null) return res.end();
    if (Buffer.isBuffer(body)) return res.end(body);
    if (typeof body === 'object') return res.json(body);
    res.end(String(body));
    return res;
  };
  return res;
}

async function statFile(rel) {
  try {
    const full = path.join(ROOT, rel);
    const stats = await fsp.stat(full);
    return stats.isFile() ? { full, stats } : null;
  } catch (_) {
    return null;
  }
}

function applyHeaders(res, pathname) {
  for (const rule of CONFIG.headers || []) {
    const source = rule.source.replace(/\*/g, '.*');
    const re = new RegExp(`^${source}$`);
    if (!re.test(pathname)) continue;
    for (const { key, value } of rule.headers) res.setHeader(key, value);
  }
}

function runRewrite(pathname) {
  for (const rule of CONFIG.rewrites || []) {
    const segments = rule.source.split('/').map(part => {
      if (part === '*') return '(.*)';
      if (part.includes(':')) return '([^/]+)';
      return part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    });
    const re = new RegExp(`^${segments.join('/')}$`);
    if (!re.test(pathname)) continue;
    const match = pathname.match(re);
    let destination = rule.destination;
    (rule.source.match(/:[^/]+/g) || []).forEach((name, index) => {
      destination = destination.split(name).join(match?.[index + 1] ?? '');
    });
    if (rule.source.includes('*')) {
      destination = destination.replace('*', match?.[1] ?? '');
    }
    return destination;
  }
  return null;
}

async function serveStatic(res, pathname) {
  const clean = pathname.replace(/\/+$/, '') || '/';
  const candidates = [];

  if (clean === '/' || clean === '') candidates.push('index.html');

  const asIs = await statFile(clean.replace(/^\//, ''));
  if (asIs) {
    const { full, stats } = asIs;
    res.setHeader('content-type', MIME[path.extname(full).toLowerCase()] || 'application/octet-stream');
    res.setHeader('content-length', stats.size);
    res.setHeader('last-modified', stats.mtime.toUTCString());
    res.end(await fsp.readFile(full));
    return true;
  }

  if (!path.extname(clean)) {
    candidates.push(`${clean.replace(/^\//, '')}.html`);
    candidates.push(`${clean.replace(/^\//, '')}/index.html`);
  }

  for (const candidate of candidates) {
    const hit = await statFile(candidate);
    if (hit) {
      const { full, stats } = hit;
      res.setHeader('content-type', MIME[path.extname(full).toLowerCase()] || 'application/octet-stream');
      res.setHeader('content-length', stats.size);
      res.end(await fsp.readFile(full));
      return true;
    }
  }
  return false;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    let pathname = decodeURIComponent(url.pathname);

    applyHeaders(res, pathname);

    // ---- phase 1: redirects (cleanUrls + trailingSlash) --------------------
    if ((CONFIG.trailingSlash === false && pathname !== '/' && pathname.endsWith('/')) ) {
      const target = pathname.replace(/\/+$/, '') || '/';
      res.statusCode = 308;
      res.setHeader('location', target + url.search);
      return res.end();
    }
    if (CONFIG.cleanUrls && pathname.endsWith('.html')) {
      const target = pathname.replace(/\.html$/, '');
      res.statusCode = 308;
      res.setHeader('location', (target === '' ? '/' : target) + url.search);
      return res.end();
    }

    // ---- phase 2: functions ------------------------------------------------
    const apiMatch = pathname.match(/^\/api\/([^/]+?)(?:\.js)?$/);
    if (apiMatch) {
      const handler = await loadHandler(apiMatch[1]);
      if (!handler) {
        res.statusCode = 404;
        return res.end('The page could not be found\n\nNOT_FOUND\n');
      }
      req.query = Object.fromEntries(url.searchParams.entries());
      patchResponse(res);
      await handler(req, res);
      if (!res.writableEnded) res.end();
      return;
    }

    // ---- phase 3: filesystem ----------------------------------------------
    const served = await serveStatic(res, pathname);
    if (served) return;

    // ---- phase 4: rewrites -------------------------------------------------
    const rewritten = runRewrite(pathname);
    if (rewritten) {
      const target = await serveStatic(res, rewritten.split('?')[0]);
      if (target) return;
      // rewrite destination might be an html path that cleanUrls collapses
      const fallback = await serveStatic(res, rewritten.replace(/\.html$/, ''));
      if (fallback) return;
    }

    res.statusCode = 404;
    res.setHeader('content-type', 'text/plain; charset=utf-8');
    res.end('The page could not be found\n\nNOT_FOUND\n');
  } catch (error) {
    console.error('[server]', error);
    if (!res.headersSent) res.statusCode = 500;
    res.end('Internal Server Error');
  }
});

const port = Number(process.argv[2] || process.env.PORT || 4173);
server.listen(port, () => {
  console.log(`AniDash watch dev server -> http://localhost:${port}  (root: ${ROOT})`);
});
