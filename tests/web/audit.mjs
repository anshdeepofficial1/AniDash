/**
 * AniDash visual + functional audit.
 *
 *   node tests/web/audit.mjs [baseUrl] [outDir]
 *
 * Walks every page/dialog in a real Chrome instance, captures screenshots and
 * reports concrete defects: console errors, horizontal overflow, dead buttons,
 * broken images, duplicate ids, tiny tap targets, empty sections.
 */
import { chromium } from 'playwright';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// Allow overriding the browser channel via PW_CHANNEL (e.g. PW_CHANNEL=chromium
// on machines without a system Chrome install). Defaults to system Chrome.
const CHANNEL = process.env.PW_CHANNEL || 'chrome';

const BASE = process.argv[2] || 'http://localhost:4173';
const OUT = process.argv[3] || path.join(os.tmpdir(), 'anidash-audit');

const VIEWPORTS = {
  desktop: { width: 1440, height: 900, isMobile: false },
  laptop: { width: 1180, height: 800, isMobile: false },
  tablet: { width: 834, height: 1112, isMobile: true },
  iphone: { width: 390, height: 844, isMobile: true, deviceScaleFactor: 3, ua: true },
};

await fs.mkdir(OUT, { recursive: true });

const report = { generatedAt: new Date().toISOString(), base: BASE, viewports: {} };

function fmt(n) {
  return Number.isFinite(n) ? Math.round(n) : n;
}

async function auditPage(page, label) {
  return page.evaluate((lbl) => {
    const out = { label: lbl, console: [], defects: [], stats: {} };
    const de = document.documentElement;

    // --- horizontal overflow -------------------------------------------------
    out.stats.viewport = { w: window.innerWidth, h: window.innerHeight };
    out.stats.doc = { scrollW: de.scrollWidth, clientW: de.clientWidth, overflow: de.scrollWidth - de.clientWidth };
    if (de.scrollWidth - de.clientWidth > 1) out.defects.push(`document overflows horizontally by ${de.scrollWidth - de.clientWidth}px`);

    // --- elements sticking out of the viewport -------------------------------
    const esc = [];
    for (const el of document.querySelectorAll('body *')) {
      const cs = getComputedStyle(el);
      if (cs.display === 'none' || cs.visibility === 'hidden' || cs.position === 'fixed') continue;
      const b = el.getBoundingClientRect();
      if (b.width < 4 || b.height < 4) continue;
      // inside a horizontal scroller = intentional
      let p = el.parentElement, inScroller = false;
      while (p && p !== document.body) {
        const pc = getComputedStyle(p);
        if ((pc.overflowX === 'auto' || pc.overflowX === 'scroll') && p.scrollWidth > p.clientWidth + 2) { inScroller = true; break; }
        p = p.parentElement;
      }
      if (inScroller) continue;
      if (b.right > window.innerWidth + 2 || b.left < -2) {
        esc.push({ tag: el.tagName, cls: String(el.className || '').slice(0, 40), left: Math.round(b.left), right: Math.round(b.right) });
      }
    }
    out.defects.push(...esc.slice(0, 8).map(e => `overflowing element <${e.tag.toLowerCase()} class="${e.cls}"> (${e.left}..${e.right}, vw=${window.innerWidth})`));
    out.stats.escaping = esc.length;

    // --- duplicate ids -------------------------------------------------------
    const ids = {};
    for (const el of document.querySelectorAll('[id]')) ids[el.id] = (ids[el.id] || 0) + 1;
    const dupes = Object.entries(ids).filter(([, c]) => c > 1);
    if (dupes.length) out.defects.push(`duplicate ids: ${dupes.map(([i, c]) => `${i}x${c}`).join(', ')}`);

    // --- broken images -------------------------------------------------------
    const broken = [...document.images].filter(i => i.complete && i.naturalWidth === 0 && i.src && !i.src.startsWith('data:'));
    if (broken.length) out.defects.push(`${broken.length} broken image(s): ${broken.slice(0, 3).map(i => i.src.split('/').pop()).join(', ')}`);
    out.stats.images = { total: document.images.length, broken: broken.length };

    // --- dead buttons --------------------------------------------------------
    // A button is "dead" when it has no click listener (checked via getEventListeners
    // is unavailable, so approximate: no handler attr, not a known form control,
    // and no ancestor handler — we instead flag ones that are inert to dispatch.)
    const buttons = [...document.querySelectorAll('button, a[href], [role="button"], [role="tab"], [role="menuitem"]')];
    // Widgets that bind with addEventListener delegation rather than inline onclick.
    const DELEGATED = '.anime-card,.news-card,.episode,.history,.settings-row,.mac-nav-item,.mac-settings-link,.chip,.desktop-history-grid,[data-filter],[data-status],[data-page],[data-tab],[data-theme-value],[data-history-id],[data-settings-focus]';
    const dead = [];
    for (const b of buttons) {
      if (b.disabled) continue;
      const cs = getComputedStyle(b);
      if (cs.display === 'none' || cs.visibility === 'hidden') continue;
      const r = b.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) continue;
      // Plain links navigate; submit buttons are handled by their form.
      if (b.tagName === 'A' && b.getAttribute('href')) continue;
      if (b.closest('form')) continue;
      if (b.closest(DELEGATED)) continue;
      // skip elements inside a known working widget tree (player/dialog closed)
      if (!b.closest('dialog:not([open])')) {
        if (b.onclick === null && !b.dataset.bound && !b.getAttribute('onclick')) {
          // check for delegated listeners on parents up to 6 levels
          let hasDelegated = false;
          let p = b.parentElement, depth = 0;
          while (p && depth < 6) {
            if (p.onclick) { hasDelegated = true; break; }
            p = p.parentElement; depth++;
          }
          if (!hasDelegated) dead.push({ tag: b.tagName, txt: (b.textContent || b.title || b.getAttribute('aria-label') || '').trim().slice(0, 28), cls: String(b.className || '').slice(0, 34) });
        }
      }
    }
    out.stats.buttons = { total: buttons.length, suspect: dead.length };
    if (dead.length) out.defects.push(`${dead.length} button(s) with no detected handler: ${dead.slice(0, 6).map(d => `"${d.txt}"`).join(', ')}`);

    // --- tiny tap targets (mobile only) --------------------------------------
    if (window.innerWidth < 800) {
      const small = buttons.filter(b => {
        const r = b.getBoundingClientRect();
        return r.width > 2 && r.height > 2 && (r.height < 36 || r.width < 36) && getComputedStyle(b).visibility !== 'hidden';
      });
      out.stats.smallTargets = small.length;
      if (small.length) out.defects.push(`${small.length} tap target(s) under 36px: ${small.slice(0, 5).map(b => (b.textContent || b.getAttribute('aria-label') || '?').trim().slice(0, 16)).join(', ')}`);
    }

    // --- empty visible sections ---------------------------------------------
    const empties = [...document.querySelectorAll('.page.active section, .page.active .card-grid, .page.active .rail')]
      .filter(s => {
        const cs = getComputedStyle(s);
        if (cs.display === 'none') return false;
        if (s.closest('[hidden]')) return false; // e.g. collapsed Continue Watching
        return s.children.length === 0 && s.textContent.trim().length < 4;
      })
      .map(s => String(s.className).slice(0, 40));
    if (empties.length) out.defects.push(`empty visible container(s): ${empties.join(' | ')}`);

    // --- active page ---------------------------------------------------------
    const active = document.querySelector('.page.active');
    out.stats.activePage = active ? active.id : '(none)';
    out.stats.activeTitle = active ? (active.querySelector('h1,h2') || {}).textContent?.trim().slice(0, 40) : '';
    out.stats.scrollHeight = document.scrollingElement.scrollHeight;

    return out;
  }, label);
}

for (const [vpName, vp] of Object.entries(VIEWPORTS)) {
  const browser = await chromium.launch({
    channel: CHANNEL,
    headless: true,
    args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox', '--disable-blink-features=AutomationControlled'],
  });
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: vp.deviceScaleFactor || 1,
    isMobile: vp.isMobile,
    hasTouch: vp.isMobile,
    userAgent: vp.ua
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
      : undefined,
  });
  const page = await ctx.newPage();
  const consoleErrors = [];
  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 160)); });
  page.on('pageerror', e => consoleErrors.push('PAGEERROR: ' + e.message.slice(0, 160)));

  const vpReport = { shots: [], pages: {}, consoleErrors };
  report.viewports[vpName] = vpReport;

  const shot = async (name) => {
    const p = path.join(OUT, `${vpName}-${name}.png`);
    await page.screenshot({ path: p }).catch(() => null);
    vpReport.shots.push(p);
    return p;
  };

  await page.goto(BASE + '/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.waitForFunction(() => typeof window.openDetails === 'function', null, { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2500);

  vpReport.pages.home = await auditPage(page, 'home');
  await shot('01-home');

  // Walk every sidebar/topbar destination that exists in this viewport
  const destinations = [
    ['Browse', 'browse'], ['Manga', 'manga'],
    ['Watchlist', 'watchlist'], ['Watch History', 'history'], ['AniAI Assistant', 'ai'],
    ['Anime News', 'news'], ['Notifications', 'notifications'],
  ];

  for (const [label, key] of destinations) {
    const clicked = await page.evaluate((lbl) => {
      const cands = [...document.querySelectorAll('.mac-nav-item, .bottom-nav button, .side-nav button, [data-page], button, a')];
      const b = cands.find(x => new RegExp('^' + lbl, 'i').test((x.textContent || '').trim().replace(/\s+/g, ' ')));
      if (!b) return false;
      b.click();
      return true;
    }, label).catch(() => false);
    if (!clicked) { vpReport.pages[key] = { skipped: true }; continue; }
    await page.waitForTimeout(2200);
    vpReport.pages[key] = await auditPage(page, key);
    await shot(`02-${key}`);
  }

  // dialogs: settings, account, details
  await page.evaluate(() => {
    const el = document.getElementById('macSettingsButton') || document.querySelector('[data-dialog="settings"]') || [...document.querySelectorAll('button')].find(b => /all settings/i.test(b.textContent));
    el && el.click();
  }).catch(() => {});
  await page.waitForTimeout(1500);
  vpReport.pages.settingsDialog = await auditPage(page, 'settingsDialog');
  await shot('03-settings');
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(600);

  // details dialog via the first *visible* card
  await page.evaluate(() => {
    const cards = [...document.querySelectorAll('.card, .anime-card, [data-id]')];
    const card = cards.find(c => c.getBoundingClientRect().width > 8 && getComputedStyle(c).visibility !== 'hidden');
    if (card) card.click();
  }).catch(() => {});
  await page.waitForTimeout(3000);
  vpReport.pages.details = await auditPage(page, 'details');
  await shot('04-details');

  vpReport.consoleErrors = [...new Set(consoleErrors)].slice(0, 30);
  await browser.close();
}

await fs.writeFile(path.join(OUT, 'report.json'), JSON.stringify(report, null, 2));
console.log('audit written to', path.join(OUT, 'report.json'));
