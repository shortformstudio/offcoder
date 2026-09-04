import puppeteer, { Browser, Page, CDPSession } from 'puppeteer-core';
import { mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { CDP_PORT, SCREENSHOT_ROOT } from './config.js';
import { Mutex } from './mutex.js';
import { structLog } from './errors.js';
import { batteryState, batteryPercentage } from './telemetry.js';

export type WebWorker = 'GEMINI_WEB' | 'DEEPSEEK_WEB' | 'KIMI_WEB';

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
    if (!this.browser) throw new Error('browser not connected');
    const targetMatch = (url: string) => {
      if (worker === 'GEMINI_WEB') return url.includes('gemini.google.com');
      if (worker === 'KIMI_WEB') return url.includes('kimi.moonshot.cn') || url.includes('kimi.com');
      return url.includes('chat.deepseek.com');
    };
    let page = (await this.browser.pages()).find((p) => targetMatch(p.url())) ?? null;
    if (!page) {
      page = await this.browser.newPage();
      const homeUrl = worker === 'GEMINI_WEB'
        ? 'https://gemini.google.com/app'
        : worker === 'KIMI_WEB'
          ? 'https://www.kimi.com'
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

    const start = () => {
      let quality = 45;
      let everyNthFrame = 2;
      let maxWidth = 1280;
      try {
        if (batteryState() === 'BATTERY' && batteryPercentage() < 30) {
          quality = 30;
          everyNthFrame = 4;
          maxWidth = 960;
        }
      } catch {}

      void this.cdpSession?.send('Page.startScreencast', {
        format: 'jpeg',
        quality,
        everyNthFrame,
        maxWidth,
      }).catch(() => undefined);
    };
    start();

    this.cdpSession.on('Page.screencastFrame', (event) => {
      this.lastFrameAt = Date.now();
      onFrame(event.data);
      void this.cdpSession
        ?.send('Page.screencastFrameAck', { sessionId: event.sessionId })
        .catch(() => undefined);
    });

    this.screencastTimer = setInterval(async () => {
      if (Date.now() - this.lastFrameAt > 20_000) {
        await this.attachScreencast(worker, onFrame).catch(() => undefined);
      }
    }, 10_000);
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
