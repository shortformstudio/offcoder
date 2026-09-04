import { humanApproach, humanPause } from './stealth.js';

const COMPOSER =
  'div.chat-input-editor[contenteditable="true"], div[contenteditable="true"][role="textbox"], div[contenteditable="true"], textarea[placeholder*="Kimi"], textarea';
const RESPONSES = [
  'div[class*="markdown"]',
  'div.markdown',
  'div[class*="segment-content"]',
  '.chat-content-item',
  'div[data-role="assistant"]',
];

export const KIMI = {
  id: 'kimi',
  label: 'Kimi (web)',
  home: 'https://www.kimi.com/',

  isThreadUrl(url) {
    return /kimi\.(?:com|moonshot\.cn)\/(?:chat\/|c\/).+/.test(url);
  },

  async isLoggedIn(page) {
    if (/\/login|\/auth|accounts\.moonshot\.cn/.test(page.url())) return false;
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
    
    // Fallback: click send button if enter was swallowed
    for (const sel of ['button[aria-label*="发送" i]', 'button[aria-label*="send" i]', 'div[class*="send-button"]']) {
      const btn = page.locator(sel).last();
      try {
        if (await btn.count() && await btn.isVisible()) {
          await btn.click({ timeout: 1500 });
          break;
        }
      } catch {}
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
    for (const sel of [
      'button[aria-label*="stop" i]',
      'button[aria-label*="停止" i]',
      'div[role="button"][aria-label*="stop" i]',
      '.stop-icon',
      'button[class*="stop" i]',
    ]) {
      try {
        if (await page.locator(sel).count()) return true;
      } catch {}
    }
    return false;
  },
};
