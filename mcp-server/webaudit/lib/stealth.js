export const STEALTH_INIT = () => {
  const nav = navigator;
  try {
    Object.defineProperty(Navigator.prototype, 'webdriver', { configurable: true, get: () => false });
  } catch {}
  try {
    if (!window.chrome) {
      window.chrome = {
        runtime: {},
        loadTimes: () => ({}),
        csi: () => ({}),
        app: {
          isInstalled: false,
          InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
          RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
        },
      };
    }
  } catch {}
  try {
    Object.defineProperty(nav, 'languages', { configurable: true, get: () => ['en-US', 'en'] });
  } catch {}
  try {
    const makePlugin = (name, description, filename) => ({
      0: { type: 'application/pdf', suffixes: 'pdf', description },
      name,
      description,
      filename,
      length: 1,
    });
    Object.defineProperty(nav, 'plugins', {
      configurable: true,
      get: () => {
        const arr = [
          makePlugin('Chrome PDF Viewer', 'Portable Document Format', 'internal-pdf-viewer'),
          makePlugin('Chromium PDF Viewer', 'Portable Document Format', 'internal-pdf-viewer'),
          makePlugin('Microsoft Edge PDF Viewer', 'Portable Document Format', 'internal-pdf-viewer'),
          makePlugin('WebKit built-in PDF', '', 'application/pdf'),
          makePlugin('PDF Viewer', '', 'internal-pdf-viewer'),
        ];
        arr.item = (i) => arr[i] ?? null;
        arr.namedItem = (n) => arr.find((p) => p.name === n) ?? null;
        arr.refresh = () => {};
        return arr;
      },
    });
    Object.defineProperty(nav, 'mimeTypes', {
      configurable: true,
      get: () => {
        const arr = [{ type: 'application/pdf', suffixes: 'pdf', description: 'Portable Document Format' }];
        arr.item = (i) => arr[i] ?? null;
        arr.namedItem = (n) => arr.find((m) => m.type === n) ?? null;
        return arr;
      },
    });
  } catch {}
  try {
    const perm = window.Notification ? Notification.permission : 'prompt';
    const origQuery = window.Permissions.prototype.query;
    window.Permissions.prototype.query = function (desc) {
      if (desc && desc.name === 'notifications') {
        return Promise.resolve({ state: perm, name: 'notifications', onchange: null });
      }
      return origQuery.call(this, desc);
    };
  } catch {}
  try {
    const vendor = 'Intel Inc.';
    const renderer = 'Intel Iris OpenGL Engine';
    const patch = (proto) => {
      const orig = proto.getParameter;
      proto.getParameter = function (p) {
        if (p === 37445) return vendor;
        if (p === 37446) return renderer;
        return orig.call(this, p);
      };
    };
    if (window.WebGLRenderingContext) patch(WebGLRenderingContext.prototype);
    if (window.WebGL2RenderingContext) patch(WebGL2RenderingContext.prototype);
  } catch {}
  try {
    Object.defineProperty(nav, 'hardwareConcurrency', { configurable: true, get: () => 8 });
  } catch {}
  try {
    Object.defineProperty(nav, 'deviceMemory', { configurable: true, get: () => 8 });
  } catch {}
};

export async function applyStealth(context) {
  await context.addInitScript(STEALTH_INIT);
}

export async function humanPause(page, min = 220, max = 620) {
  const ms = min + Math.floor(Math.random() * Math.max(1, max - min));
  await page.waitForTimeout(ms);
}

export async function humanApproach(page, locator) {
  try {
    const box = await locator.boundingBox();
    if (!box) return;
    const x = box.x + box.width * (0.3 + Math.random() * 0.4);
    const y = box.y + box.height * (0.4 + Math.random() * 0.3);
    await page.mouse.move(x - 50 + Math.random() * 100, y - 40 + Math.random() * 80, { steps: 5 });
    await page.mouse.move(x, y, { steps: 4 });
  } catch {}
}
