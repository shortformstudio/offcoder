import { humanApproach, humanPause } from './stealth.js';

const COMPOSER =
  'div.ql-editor[contenteditable="true"], rich-textarea div[contenteditable="true"], div[contenteditable="true"][role="textbox"]';

const RESPONSES = [
  'model-response .markdown',
  'message-content .markdown',
  'model-response',
  'message-content',
  'response-container',
  'div[aria-live="polite"]',
];

const RESPONSE_GROUP = 'model-response, message-content, response-container';

async function clickSendFallback(page) {
  for (const sel of ['button[aria-label*="Send" i]', 'button[data-test-id="send-button"]']) {
    const btn = page.locator(sel).last();
    try {
      if (await btn.count()) {
        await btn.click({ timeout: 2000 });
        return;
      }
    } catch {}
  }
}

export const GEMINI = {
  id: 'gemini',
  label: 'Gemini (web)',
  home: 'https://gemini.google.com/app',

  isThreadUrl(url) {
    return /gemini\.google\.com\/app\/.+/.test(url);
  },

  async isLoggedIn(page) {
    if (/accounts\.google\.[a-z.]+/.test(page.url())) return false;
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
    await page.keyboard.insertText(text);
    await humanPause(page, 300, 900);
    await page.keyboard.press('Enter');
    try {
      await page.waitForFunction(
        (sel) => {
          const nodes = document.querySelectorAll(sel);
          const last = nodes[nodes.length - 1];
          return last ? (last.textContent ?? '').trim().length > 0 : false;
        },
        RESPONSE_GROUP,
        { timeout: 8000 },
      );
    } catch {
      await clickSendFallback(page);
    }
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
    for (const sel of ['button[aria-label*="Stop" i]', 'button[aria-label*="pause" i]']) {
      try {
        if (await page.locator(sel).count()) return true;
      } catch {}
    }
    return false;
  },
};
