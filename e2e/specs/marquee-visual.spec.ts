import { test, expect } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const harness = 'file://' + path.join(here, '..', 'fixtures', 'marquee.html');

test.describe('marquee visual regression', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(harness);
    await page.evaluate(() => ((window as any).PAUSE = true));
  });

  test('idle state renders green marquee', async ({ page }) => {
    await page.evaluate(() => {
      (window as any).injectMarquee({ level: 'idle', text: 'cdp attached — screencast live', code: 'cdp_connected' });
    });
    await expect(page.locator('#stage')).toHaveScreenshot('marquee-idle.png');
  });

  test('working state renders yellow marquee', async ({ page }) => {
    await page.evaluate(() => {
      (window as any).injectMarquee({ level: 'working', text: 'task running on worker — decomposition in flight', code: 'task_checked_out' });
    });
    await expect(page.locator('#stage')).toHaveScreenshot('marquee-working.png');
  });

  test('alert state renders red marquee', async ({ page }) => {
    await page.evaluate(() => {
      (window as any).injectMarquee({ level: 'alert', text: 'chrome cdp offline — run scripts/chrome_launch.sh', code: 'cdp_offline' });
    });
    await expect(page.locator('#stage')).toHaveScreenshot('marquee-alert.png');
  });
});
