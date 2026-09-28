import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { CHANNEL, HEADLESS, PROFILE_ROOT } from './config.js';
import { applyStealth } from './stealth.js';

const holders = new Map();
const locks = new Map();

export function profilePath(provider) {
  return path.join(PROFILE_ROOT, provider);
}

export async function withLock(key, fn) {
  const tail = (locks.get(key) ?? Promise.resolve()).then(fn, fn);
  locks.set(key, tail.catch(() => {}));
  return tail;
}

async function launch(provider) {
  const dir = profilePath(provider);
  fs.mkdirSync(dir, { recursive: true });
  const base = {
    headless: HEADLESS,
    timeout: 60000,
    viewport: null,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-first-run',
      '--no-default-browser-check',
      '--start-maximized',
    ],
    ignoreDefaultArgs: ['--enable-automation'],
  };
  let ctx;
  if (CHANNEL && CHANNEL !== 'chromium') {
    try {
      ctx = await chromium.launchPersistentContext(dir, { ...base, channel: CHANNEL });
    } catch {
      ctx = await chromium.launchPersistentContext(dir, base);
    }
  } else {
    ctx = await chromium.launchPersistentContext(dir, base);
  }
  await applyStealth(ctx);
  holders.set(provider, ctx);
  return ctx;
}

export async function getContext(provider) {
  const ctx = holders.get(provider);
  if (ctx) {
    try {
      ctx.pages();
      return ctx;
    } catch {
      holders.delete(provider);
    }
  }
  return launch(provider);
}

export async function getPage(provider) {
  const ctx = await getContext(provider);
  return ctx.pages().find((p) => !p.isClosed()) ?? (await ctx.newPage());
}

export async function closeAll() {
  for (const [key, ctx] of holders) {
    holders.delete(key);
    await ctx.close().catch(() => {});
  }
}
