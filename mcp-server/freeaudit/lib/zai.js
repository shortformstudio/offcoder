import { humanApproach, humanPause } from './stealth.js';

const COMPOSER = 'textarea[placeholder="How can I help you today?"], textarea.input-scroll, textarea';
const RESPONSES = ['div[class*="markdown" i]', '.ds-markdown', 'div[class*="answer" i]'];
const STOP = ['button[aria-label*="stop" i]', 'div[role="button"][aria-label*="stop" i]', 'svg[class*="stop" i]'];

export const ZAI = {
  id: 'zai',
  label: 'Z.ai (GLM-5.3-Flash, web)',
  role: 'general fallback analysis — quick review, cross-check, alternative perspective',
  home: 'https://chat.z.ai/',
  needsSession: true,

  isThreadUrl(url) {
    return /chat\.z\.ai\/(?:chat|c|home|assistant).+/.test(url);
  },

  async isLoggedIn(page) {
    if (/signin|sign_in|\/login/.test(page.url())) return false;
    try {
      await page.waitForSelector(COMPOSER, { state: 'visible', timeout: 12000 });
    } catch {
      return false;
    }
    const text = await page.evaluate(() => document.body.innerText.slice(0, 1500));
    if (/security verification|drag the slider|CertifyId|verify to continue/i.test(text)) return false;
    return true;
  },

  async send(page, text) {
    await page.keyboard.press('Escape').catch(() => {});
    const el = page.locator(COMPOSER).first();
    await el.scrollIntoViewIfNeeded().catch(() => {});
    await humanPause(page, 250, 700);
    await humanApproach(page, el);
    await el.fill(text);
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
        if (await page.locator(sel).count()) return true;
      } catch {}
    }
    return false;
  },
};
