// Compares two deployments of the site element by element, so a change meant
// to be visually a no-op can be shown to be one, and an intended change shown
// to touch only what it should. See docs/runbooks/testing-changes-before-release.md.
//
//   npm run compare                       # production vs default staging
//   npm run compare -- <before> <after>   # any two base URLs, e.g. local builds
//
// For every page in a11y/pages.ts plus a 404, at desktop and phone widths, and
// with the quiz modal open on the desktop homepage, it records every element's box
// size and the computed properties in PROPS, skipping the staging banner, then
// prints the differences grouped by element and change. Screenshots of every
// state go to test-results/compare/ for eyeballing.
//
// Elements are matched by document order. If the two pages differ in
// structure, that page reports where they first diverge and stops comparing it.
// Always exits 0 when the comparison ran: differences are expected for an
// intended change, and judging them is the reviewer's job.
import { chromium } from 'playwright';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PAGES } from '../a11y/pages.ts';

const [before = 'https://ontariomenopauseclinic.ca', after = 'https://staging.ontariomenopauseclinic.ca'] =
  process.argv.slice(2);
const OUT = fileURLToPath(new URL('../test-results/compare/', import.meta.url));

const ROUTES = [...PAGES, '/no-such-page/'];
const VIEWPORTS = { desktop: { width: 1280, height: 900 }, phone: { width: 375, height: 812 } };
// Extra states, checked on the desktop homepage only: the modal is the same
// partial on every page. Each returns false where it can't apply (the
// maintenance placeholder has no quiz), and that state is then skipped.
const STATES = {
  quizModal: () => { const t = document.querySelector('[data-quiz-trigger]'); return !!t && (t.click(), true); },
};
const PROPS = ['display', 'position', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'border-top-left-radius',
  'border-bottom-right-radius', 'transition-duration', 'color', 'background-color', 'font-family',
  'font-size', 'font-weight', 'line-height', 'gap', 'opacity', 'visibility'];

async function snapshot(browser, base, route, viewport, open, shot) {
  const ctx = await browser.newContext({ viewport, reducedMotion: 'reduce' });
  try {
    const page = await ctx.newPage();
    await page.goto(base + route, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    if (open) {
      if (!await page.evaluate(open)) return null;
      await page.waitForTimeout(500);
    }
    await page.screenshot({ path: OUT + shot, fullPage: !open });
    return await page.evaluate((props) => {
      const banner = document.querySelector('.staging-banner');
      return [...document.body.querySelectorAll('*')]
        .filter(el => !banner?.contains(el) && !['SCRIPT', 'STYLE'].includes(el.tagName))
        .map(el => {
          const cs = getComputedStyle(el), r = el.getBoundingClientRect();
          const cls = typeof el.className === 'string' && el.className.trim();
          return {
            id: el.tagName.toLowerCase() + (cls ? '.' + cls.split(/\s+/).join('.') : ''),
            size: `${Math.round(r.width)}x${Math.round(r.height)}`,
            ...Object.fromEntries(props.map(p => [p, cs.getPropertyValue(p)])),
          };
        });
    }, PROPS);
  } finally {
    await ctx.close();
  }
}

function diff(a, b) {
  const out = [];
  if (a.length !== b.length) out.push(`element count ${a.length} → ${b.length}`);
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i].id !== b[i].id) {
      out.push(`structure diverges at element ${i}: ${a[i].id} → ${b[i].id} (rest of page not compared)`);
      break;
    }
    for (const k of Object.keys(a[i])) {
      if (a[i][k] !== b[i][k]) out.push(`${a[i].id} ${k}: ${a[i][k]} → ${b[i][k]}`);
    }
  }
  return out;
}

const checks = [];
for (const [vp, viewport] of Object.entries(VIEWPORTS)) {
  for (const route of ROUTES) checks.push({ label: `${vp} ${route}`, vp, viewport, route });
}
for (const [state, open] of Object.entries(STATES)) {
  checks.push({ label: `desktop / ${state}`, vp: 'desktop', viewport: VIEWPORTS.desktop, route: '/', state, open });
}

fs.mkdirSync(OUT, { recursive: true });
console.log(`before: ${before}\nafter:  ${after}\n`);
const browser = await chromium.launch();
const changes = new Map(); // change -> labels it appeared on
const skipped = [];
try {
  for (const c of checks) {
    const name = `${c.vp}${c.route.replace(/\//g, '_')}${c.state ? '-' + c.state : ''}`;
    const [a, b] = await Promise.all([
      snapshot(browser, before, c.route, c.viewport, c.open, `${name}-before.png`),
      snapshot(browser, after, c.route, c.viewport, c.open, `${name}-after.png`),
    ]);
    if (!a || !b) {
      if (a || b) changes.set(`${c.state} available only ${a ? 'before' : 'after'}`, [c.label]);
      else skipped.push(c.label);
      continue;
    }
    for (const change of diff(a, b)) changes.set(change, [...(changes.get(change) ?? []), c.label]);
    process.stderr.write('.');
  }
} finally {
  await browser.close();
}

process.stderr.write('\n');
if (skipped.length) console.log(`Skipped (not available on either side): ${skipped.join(', ')}\n`);
if (!changes.size) {
  console.log(`No differences across ${checks.length} page states.`);
} else {
  console.log(`${changes.size} distinct differences across ${checks.length} page states:\n`);
  for (const [change, labels] of [...changes].sort((x, y) => y[1].length - x[1].length)) {
    const where = labels.length === checks.length ? 'everywhere' : labels.join(', ');
    console.log(`${String(labels.length).padStart(3)}×  ${change}\n      ${where}`);
  }
}
console.log(`\nScreenshots: ${OUT}`);
