export async function armIdleWatcher(page) {
  await page.evaluate(() => {
    const w = window;
    w.__consultLastMutation = Date.now();
    if (!w.__consultObserver) {
      w.__consultObserver = new MutationObserver(() => {
        w.__consultLastMutation = Date.now();
      });
      w.__consultObserver.observe(document.documentElement, {
        childList: true,
        subtree: true,
        characterData: true,
      });
    }
  });
}

export async function idleMs(page) {
  try {
    return await page.evaluate(() => Date.now() - (window.__consultLastMutation ?? Date.now()));
  } catch {
    return 0;
  }
}
