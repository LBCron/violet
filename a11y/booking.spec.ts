import { test, expect, type Page } from '@playwright/test';
import { PLACED_BUTTON, useAvarosStandIn } from './avaros-standin';

// The Avaros landing page's "Book an appointment" button must sit inside the
// booking frame. A frame shorter than the page hides it below the frame's edge,
// and one narrower than Avaros's ~335px minimum cuts off its right side, both
// behind an inner scroll nobody notices (#165). The iframe is replaced by a
// stand-in sized from fixtures/avaros-landing.json, which booking-check.yml
// keeps in step with the real page.

const openBookPage = async (page: Page) => {
  await page.goto('/book/');
  return '.book-page__frame';
};

const CASES = [
  { name: 'iPhone SE 1st gen, /book/', viewport: { width: 320, height: 568 }, open: openBookPage },
  { name: 'iPhone SE 2nd/3rd gen, /book/', viewport: { width: 375, height: 667 }, open: openBookPage },
  { name: 'iPhone 16, /book/', viewport: { width: 393, height: 734 }, open: openBookPage },
  { name: 'desktop, /book/', viewport: { width: 1280, height: 800 }, open: openBookPage },
  { name: 'short laptop, /book/', viewport: { width: 1366, height: 768 }, open: openBookPage },
];

for (const { name, viewport, open } of CASES) {
  test.describe(name, () => {
    test.use({ viewport });

    test('Avaros "Book an appointment" button inside the frame', async ({ page }) => {
      await useAvarosStandIn(page);
      const frameSelector = await open(page);
      const button = page.frameLocator(frameSelector).locator(PLACED_BUTTON).filter({ hasText: /book an appointment/i });
      await button.waitFor();
      const f = (await page.locator(frameSelector).boundingBox())!;
      const b = (await button.boundingBox())!;
      expect(b.x, 'button left vs frame left').toBeGreaterThanOrEqual(f.x);
      expect(b.y, 'button top vs frame top').toBeGreaterThanOrEqual(f.y);
      expect(b.x + b.width, 'button right vs frame right').toBeLessThanOrEqual(f.x + f.width);
      expect(b.y + b.height, 'button bottom vs frame bottom').toBeLessThanOrEqual(f.y + f.height);
    });
  });
}
