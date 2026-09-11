import puppeteer, { Browser, Page, CDPSession } from 'puppeteer-core';
import { mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { CDP_PORT, SCREENSHOT_ROOT } from './config.js';
import { Mutex } from './mutex.js';
import { structLog } from './errors.js';
import { batteryState, batteryPercentage } from './telemetry.js';

export type WebWorker = 'GEMINI_WEB' | 'DEEPSEEK_WEB' | 'KIMI_WEB' | 'OTHER_WEB';

interface TaskResult {
  code: string;
  screenshotPath: string | null;
  layoutBlocks: Array<{ tag: string; x: number; y: number; width: number; height: number; sample: string }>;
}

function withTimeout<T>(promise: Promise<T>, ms: number, onTimeout: () => T): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((resolve) => setTimeout(() => resolve(onTimeout()), ms)),
  ]);
}

export class CDPBroker {
  private browser: Browser | null = null;
  private lastWorker: WebWorker = 'DEEPSEEK_WEB';
  private isVisibleState = false;
  private readonly homeBounds = { left: 240, top: 80, width: 1440, height: 900 };
  private cdpSession: CDPSession | null = null;
  private screencastTimer: ReturnType<typeof setInterval> | null = null;
  private lastFrameAt = 0;
  private readonly workerChains = new Map<WebWorker, Mutex>();

  constructor(private cdpPort = CDP_PORT) {}

  private chain(worker: WebWorker): Mutex {
    let chain = this.workerChains.get(worker);
    if (!chain) {
      chain = new Mutex();
      this.workerChains.set(worker, chain);
    }
    return chain;
  }

  /// Executes a browser command on the mirrored page: read | clear | type.
  async evaluate(action: string, text: string): Promise<string> {
    try {
      const page = await this.resolvePage(this.lastWorker);
      if (action === 'read') {
        const info = await page.evaluate(() => {
          const bodyText = document.body ? document.body.innerText : '';
          return {
            url: location.href,
            title: document.title,
            text: bodyText.slice(0, 4000),
          };
        });
        return `URL: ${info.url}\nTITLE: ${info.title}\n\n${info.text}`;
      }
      if (action === 'clear') {
        const result = await page.evaluate(() => {
          const el = document.activeElement as (HTMLInputElement | HTMLTextAreaElement | HTMLElement) | null;
          if (!el) return 'no focused editable element; focus first';
          if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
            el.value = '';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            return `cleared <${el.tagName.toLowerCase()}> (${el.id || el.name || 'unnamed'})`;
          }
          if (el.isContentEditable) {
            el.innerText = '';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            return 'cleared contenteditable element';
          }
          return 'focused element is not editable';
        });
        return result;
      }
      if (action === 'type') {
        if (!text) return 'type requires a text argument';
        const result = await page.evaluate((value) => {
          let el = document.activeElement as HTMLElement | null;
          const editable = () => el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT' || el.isContentEditable);
          if (!editable()) {
            el = (document.querySelector('textarea, [contenteditable="true"], input[type="text"], input[type="search"], input[type="email"], input[type="password"]') ?? null) as HTMLElement | null;
          }
          if (!el) return 'no editable input found on page';
          el.focus();
          if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
            el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
          } else {
            el.innerText = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
          return `typed ${value.length} chars into <${el.tagName.toLowerCase()}>`;
        }, text);
        return result;
      }
      return `unknown browser action: ${action}`;
    } catch (error) {
      return `browser eval error: ${error instanceof Error ? error.message : String(error)}`;
    }
  }

  /// Opens (or reuses) the login tab for a provider so the mirrored browser
  /// is the very session the user logs into.
  async openProviderTab(worker: WebWorker): Promise<Page> {
    return this.resolvePage(worker);
  }

  isVisible(): boolean {
    return this.isVisibleState;
  }

  /// Raises (true) or parks (false) the offcoder chrome window; driver uses CDP
  /// window bounds so only this instance is affected — never the operator's own
  /// Chrome windows and never other automation profiles.
  async setVisibility(visible: boolean): Promise<string> {
    try {
      const page = await this.resolvePage(this.lastWorker);
      const session = await page.createCDPSession().catch(() => null);
      if (!session) return 'no cdp session for window control';
      const { windowId } = await (session.send('Browser.getWindowForTarget') as Promise<{ windowId: number }>).catch(() => ({ windowId: 0 }));
      if (!windowId) return 'no window handle for browser target';
      const bounds: { windowState: 'normal' | 'minimized' | 'maximized' | 'fullscreen'; left?: number; top?: number; width?: number; height?: number } = visible
        ? { windowState: 'normal', ...this.homeBounds }
        : { windowState: 'normal', left: -32000, top: -32000, width: this.homeBounds.width, height: this.homeBounds.height };
      await session.send('Browser.setWindowBounds', { windowId, bounds }).catch(() => undefined);
      this.isVisibleState = visible;
      return visible ? 'browser window raised' : 'browser window parked offscreen';
    } catch (error) {
      return `visibility error: ${error instanceof Error ? error.message : String(error)}`;
    }
  }

  /// Presence snapshot of the mirrored login browser per provider.
  async presence(): Promise<{ deepseek: boolean; kimi: boolean; other: boolean }> {
    let pages: Page[] = [];
    if (this.browser?.connected) {
      pages = await this.browser.pages().catch(() => []);
    }
    const urls = pages.map((p) => p.url());
    return {
      deepseek: urls.some((u) => u.includes('chat.deepseek.com')),
      kimi: urls.some((u) => u.includes('kimi.moonshot.cn') || u.includes('kimi.com')),
      other: pages.length > 0,
    };
  }

  async checkConnection(): Promise<boolean> {
    try {
      const res = await fetch(`http://127.0.0.1:${this.cdpPort}/json/version`);
      return res.ok;
    } catch {
      return false;
    }
  }

  async connect(): Promise<void> {
    this.browser = await puppeteer.connect({
      browserURL: `http://127.0.0.1:${this.cdpPort}`,
      defaultViewport: { width: 1440, height: 900 },
    });
    const version = await fetch(`http://127.0.0.1:${this.cdpPort}/json/version`).then((r) => r.json().catch(() => ({})));
    const userDataDir = (version as { userDataDir?: string }).userDataDir ?? '';
    if (userDataDir) {
      structLog({ level: 'debug', code: 'cdp_profile', msg: `attached chrome profile ${userDataDir}` });
    }
  }

  private async resolvePage(worker: WebWorker): Promise<Page> {
    this.lastWorker = worker;
    if (!this.browser) throw new Error('browser not connected');
    const targetMatch = (url: string) => {
      if (worker === 'GEMINI_WEB') return url.includes('gemini.google.com');
      if (worker === 'KIMI_WEB') return url.includes('kimi.moonshot.cn') || url.includes('kimi.com');
      if (worker === 'OTHER_WEB') return true;
      return url.includes('chat.deepseek.com');
    };
    let page = (await this.browser.pages()).find((p) => targetMatch(p.url())) ?? null;
    if (!page) {
      page = await this.browser.newPage();
      const homeUrl = worker === 'GEMINI_WEB'
        ? 'https://gemini.google.com/app'
        : worker === 'KIMI_WEB'
          ? 'https://www.kimi.com'
          : worker === 'OTHER_WEB'
            ? 'about:blank'
            : 'https://chat.deepseek.com';
      await page.goto(homeUrl, {
        waitUntil: 'domcontentloaded',
        timeout: 30_000,
      });
    }
    await page.bringToFront();
    return page;
  }

  async executeTask(worker: WebWorker, prompt: string, taskId: string): Promise<TaskResult> {
    return this.chain(worker).acquire(async () => {
      let page: Page;
      try {
        page = await this.resolvePage(worker);
      } catch (error) {
        structLog({ level: 'error', code: 'browser_unreachable', msg: String(error instanceof Error ? error.message : error), taskId });
        throw error;
      }
      this.cdpSession = await page.createCDPSession().catch(() => null);

      const inputSelector = worker === 'GEMINI_WEB'
        ? 'div[role="textbox"], .ql-editor'
        : worker === 'KIMI_WEB'
          ? 'div.chat-input-editor, div[contenteditable="true"], textarea'
          : 'textarea, #chat-input';

      await page.waitForSelector(inputSelector, { timeout: 15_000 });
      await page.focus(inputSelector);

      // Adversarial Guardrail: Turn-marker stamping to guarantee idempotency and avoid stale scrapes
      const turnMarker = `\n\n§TURN ${taskId}`;
      const stampedPrompt = prompt.includes('§TURN') ? prompt : `${prompt}${turnMarker}`;

      await page.evaluate(
        (sel, text) => {
          const el = document.querySelector(sel) as HTMLElement | null;
          if (!el) return;
          if (el.tagName === 'TEXTAREA') {
            (el as HTMLTextAreaElement).value = text;
          } else {
            el.innerText = text;
          }
          el.dispatchEvent(new Event('input', { bubbles: true }));
        },
        inputSelector,
        stampedPrompt
      );
      await page.keyboard.press('Enter');

      const stopIndicator = worker === 'GEMINI_WEB'
        ? 'button[aria-label*="Stop"], .streaming-active'
        : worker === 'KIMI_WEB'
          ? 'button[aria-label*="stop" i], button[aria-label*="停止" i], .stop-icon, button[class*="stop" i]'
          : '.ds-stop-button, button[aria-label="Stop Generating"]';

      await page.waitForSelector(stopIndicator, { timeout: 10_000 }).catch(() => undefined);

      // Early 45s cutoff for completion or challenge gate
      await withTimeout(
        page.waitForFunction(
          (sel) => !document.querySelector(sel),
          { timeout: 45_000, polling: 500 },
          stopIndicator
        ),
        45_000,
        () => undefined
      ).catch(() => undefined);

      const pageBody = (await page.evaluate(() => document.body.innerText.slice(0, 500)).catch(() => '')) ?? '';
      if (pageBody.match(/captcha|challenge|access denied|sign in|log in|cloudflare|cf-browser-verification/i)) {
        structLog({ level: 'warning', code: 'auth_gate', msg: 'web session gated at login/captcha/challenge', taskId });
        throw new Error('auth_gate');
      }

      mkdirSync(SCREENSHOT_ROOT, { recursive: true });
      const screenshotPath = path.join(SCREENSHOT_ROOT, `${taskId}.png`);
      const layoutBlocks = await this.captureLayoutMap(page).catch(() => []);
      let clipped = false;
      try {
        await page.screenshot({ path: screenshotPath, fullPage: false, clip: this.codeClip(layoutBlocks, page) });
        clipped = true;
      } catch (error) {
        structLog({ level: 'warning', code: 'screenshot_clip_failed', msg: String(error instanceof Error ? error.message : error) });
        // Delete partial/failed screenshot immediately
        rmSync(screenshotPath, { force: true });
      }

      const code = await page.evaluate((workerType: WebWorker) => {
        const selectors = workerType === 'GEMINI_WEB'
          ? ['pre code', '.code-block-decoration', '.message-content']
          : workerType === 'KIMI_WEB'
            ? ['pre code', 'pre', 'div.markdown', '.segment-content']
            : ['pre', '.ds-message-body'];
        for (const sel of selectors) {
          const els = document.querySelectorAll(sel);
          if (els.length > 0) {
            const raw = els[els.length - 1].textContent ?? '';
            return raw.trim();
          }
        }
        return '';
      }, worker).catch(() => '');

      return { code, screenshotPath: clipped ? screenshotPath : null, layoutBlocks };
    });
  }

  private codeClip(blocks: TaskResult['layoutBlocks'], page: Page): { x: number; y: number; width: number; height: number } {
    const biggest = [...blocks].filter((b) => b.tag === 'pre' || b.tag === 'code').sort((a, b) => b.height - a.height)[0];
    if (biggest && biggest.width > 40 && biggest.height > 40) {
      return {
        x: Math.max(0, biggest.x),
        y: Math.max(0, biggest.y),
        width: Math.min(1440, biggest.width),
        height: Math.min(900, biggest.height),
      };
    }
    return { x: 0, y: 0, width: 1440, height: 900 };
  }

  async captureLayoutMap(page: Page): Promise<TaskResult['layoutBlocks']> {
    return page.evaluate(() => {
      const nodes = Array.from(document.querySelectorAll('pre, pre code, h1, h2, h3, .code-block, article'));
      return nodes.slice(0, 64).map((el) => {
        const rect = (el as HTMLElement).getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          sample: (el.textContent ?? '').slice(0, 200),
        };
      });
    });
  }

  async attachScreencast(worker: WebWorker, onFrame: (base64Data: string) => void): Promise<void> {
    await this.detachScreencast();
    const page = await this.resolvePage(worker).catch(() => null);
    if (!page) return;
    this.cdpSession = await page.createCDPSession().catch(() => null);
    if (!this.cdpSession) return;
    await this.cdpSession.send('Page.enable').catch(() => undefined);

    // Chrome 152+ stops emitting Page.startScreencast frames; mirror streams a
    // periodic Page.captureScreenshot poll instead (reliable on headful chrome).
    const quality = 45;
    const shoot = async () => {
      try {
        const shot = await this.cdpSession?.send('Page.captureScreenshot', {
          format: 'jpeg',
          quality,
          fromSurface: true,
        });
        if (shot?.data) {
          this.lastFrameAt = Date.now();
          onFrame(shot.data);
        }
      } catch {}
    };

    await shoot();
    this.screencastTimer = setInterval(async () => {
      if (this.cdpSession) {
        await shoot();
      }
      if (Date.now() - this.lastFrameAt > 30_000) {
        await this.attachScreencast(worker, onFrame).catch(() => undefined);
      }
    }, 1_500);
  }

  async detachScreencast(): Promise<void> {
    if (this.screencastTimer) {
      clearInterval(this.screencastTimer);
      this.screencastTimer = null;
    }
    if (this.cdpSession && this.browser?.connected) {
      await this.cdpSession.send('Page.stopScreencast').catch(() => undefined);
      await this.cdpSession.detach().catch(() => undefined);
    }
    this.cdpSession = null;
  }

  async dispose(): Promise<void> {
    await this.detachScreencast();
    if (this.browser?.connected) {
      await this.browser.disconnect().catch(() => undefined);
    }
    this.browser = null;
  }
}
