import { humanApproach, humanPause } from './stealth.js';

const COMPOSER = '#chat-input, textarea[placeholder], textarea';
const RESPONSES = ['.ds-markdown', 'div[class*="ds-markdown"]', 'div[class*="markdown"]'];

export const DEEPSEEK = {
  id: 'deepseek',
  label: 'DeepSeek (web)',
  home: 'https://chat.deepseek.com/',

  isThreadUrl(url) {
    return /deepseek\.com\/(?:a\/chat\/s\/|chat\/).+/.test(url);
  },

  async isLoggedIn(page) {
    if (/sign_in|\/login/.test(page.url())) return false;
    try {
      await page.waitForSelector(COMPOSER, { state: 'visible', timeout: 12000 });
      return true;
    } catch {
      return false;
    }
  },

  async send(page, text) {
    const el = page.locator(COMPOSER).first();
    await el.scrollIntoViewIfNeeded().catch(() => {});
    await humanPause(page, 250, 700);
    await humanApproach(page, el);
    await el.click();
    const tag = await el.evaluate((n) => n.tagName.toLowerCase()).catch(() => 'textarea');
    if (tag === 'textarea') {
      await el.fill(text);
    } else {
      await page.keyboard.insertText(text);
    }
    await humanPause(page, 300, 900);
    await page.keyboard.press('Enter');
  },

  async readLatest(page) {
    for (const sel of RESPONSES) {
      try {
        const t = await page.locator(sel).last().innerText({ timeout: 1200 });
        if (t.trim()) return t.trim();
      } catch {}
    }
    return '';
  },

  async isBusy(page) {
    for (const sel of ['button[aria-label*="stop" i]', 'div[role="button"][aria-label*="stop" i]']) {
      try {
        if (await page.locator(sel).count()) return true;
      } catch {}
    }
    return false;
  },
};
