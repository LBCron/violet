// Measures the real Avaros booking landing page across frame widths and
// records the results in a11y/fixtures/avaros-landing.json, which the booking tests
// replay as a stand-in for the iframe (#165). Avaros content is edited outside
// this repo, so booking-check.yml runs this daily and opens a PR on change.
//
//   npm run avaros:measure -- <booking URL>
//
// Exits 0 whether or not anything changed (prints "changed"/"unchanged");
// exits 1 without touching the fixture if any width fails to measure.
//
// Commit only fixtures measured by booking-check.yml: text wraps differently
// under other OSes' fonts, so a locally measured fixture is undone by the next
// daily run (#183).
import { chromium } from 'playwright';
import fs from 'node:fs';

const url = process.argv[2];
if (!url) {
  console.error('usage: npm run avaros:measure -- <booking URL>');
  process.exit(2);
}

const FIXTURE = new URL('../a11y/fixtures/avaros-landing.json', import.meta.url);
// Covers every frame the site renders: /book/ on a 320px phone (272px) up to
// the desktop /book/ container. Avaros changes layout at breakpoints, so the
// stand-in uses the taller of the two samples either side of the real width.
const WIDTHS = Array.from({ length: (1200 - 260) / 20 + 1 }, (_, i) => 260 + i * 20);

async function measure(browser, width) {
  // Short viewport so nothing sized in vh inflates the measured height.
  const page = await browser.newPage({ viewport: { width, height: 400 } });
  try {
    await page.goto(url);
    const button = page.getByRole('button', { name: /book an appointment/i })
      .or(page.getByText(/book an appointment/i)).first();
    await button.waitFor({ timeout: 30_000 });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(500);
    return await page.evaluate(() => {
      const b = [...document.querySelectorAll('button, a')]
        .find(e => /book an appointment/i.test(e.textContent))
        .getBoundingClientRect();
      // The button's whole box, so no dimension is assumed constant: any
      // change to its size or position changes the fixture and opens a PR.
      // (Avaros stops shrinking below ~335px, so on narrow frames the button
      // overhangs the right edge rather than the page reflowing.)
      return {
        buttonLeft: Math.floor(b.left + scrollX),
        buttonTop: Math.floor(b.top + scrollY),
        buttonRight: Math.ceil(b.right + scrollX),
        buttonBottom: Math.ceil(b.bottom + scrollY),
        height: Math.ceil(document.documentElement.scrollHeight),
      };
    });
  } finally {
    await page.close();
  }
}

const browser = await chromium.launch();
const samples = [];
try {
  for (const width of WIDTHS) samples.push({ width, ...(await measure(browser, width)) });
} finally {
  await browser.close();
}

const previous = fs.existsSync(FIXTURE) ? JSON.parse(fs.readFileSync(FIXTURE, 'utf8')) : { samples: [] };
const FIELDS = ['buttonLeft', 'buttonTop', 'buttonRight', 'buttonBottom', 'height'];
const key = s => [s.width, ...FIELDS.map(f => s[f])].join(':');
if (previous.samples.map(key).join() === samples.map(key).join()) {
  console.log('unchanged');
  process.exit(0);
}

for (const s of samples) {
  const p = previous.samples.find(x => x.width === s.width);
  if (!p || key(p) !== key(s)) {
    const diffs = FIELDS.filter(f => p?.[f] !== s[f]).map(f => `${f} ${p?.[f] ?? '-'} -> ${s[f]}`);
    console.log(`width ${s.width}px: ${diffs.join(', ')}`);
  }
}
// Full timestamp: the fixture's version, unique even across same-day runs.
const measuredAt = new Date().toISOString();
fs.writeFileSync(FIXTURE, JSON.stringify({ measuredAt, samples }, null, 2) + '\n');
console.log('changed');
