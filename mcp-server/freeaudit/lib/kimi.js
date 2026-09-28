import { humanApproach, humanPause } from './stealth.js';

const COMPOSER = 'div.chat-input-editor[contenteditable="true"], div.chat-input-editor';
const RESPONSES = ['div[class*="markdown" i]', 'div[class*="answer" i]', '.markdown-body'];
const STOP = ['button[aria-label*="stop" i]', 'div[role="button"][aria-label*="stop" i]', 'button[class*="stop" i]'];

export const KIMI = {
  id: 'kimi',
  label: 'Kimi (web, Moonshot AI)',
  role: 'visual design work — UI/UX critique, aesthetic direction, layouts, brand, imagery, presentation',
  home: 'https://www.kimi.ai/',
  needsSession: true,

  isThreadUrl(url) {
    return /kimi\.(com|ai)\//.test(url) && !/^(https?:\/\/)?(www\.)?kimi\.(com|ai)\/?$/.test(url);
  },

  async isLoggedIn(page) {
    if (/sign_in|\/login|passport/.test(page.url())) return false;
    try {
      await page.waitForSelector(COMPOSER, { state: 'visible', timeout: 12000 });
    } catch {
      return false;
    }
    await page.waitForTimeout(1200);
    const text = await page.evaluate(() => document.body.innerText.slice(0, 3000));
    const signedOut = /Log in|登录|Sign in|Sign up/.test(text);
    return !signedOut;
  },

  async send(page, text) {
    await page.keyboard.press('Escape').catch(() => {});
    const el = page.locator(COMPOSER).first();
    await el.scrollIntoViewIfNeeded().catch(() => {});
    await humanPause(page, 250, 700);
    await humanApproach(page, el);
    await el.click({ force: true }).catch(() => {});
    await page.keyboard.insertText(text);
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
    for (const sel of STOP) {
      try {
        if (await page.locator(sel).count()) {
          const txt = await page
            .locator(sel)
            .first()
            .innerText()
            .catch(() => '');
          if (txt || (await page.locator(sel).first().isVisible().catch(() => false))) return true;
        }
      } catch {}
    }
    return false;
  },
};
