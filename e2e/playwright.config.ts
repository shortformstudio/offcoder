import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './specs',
  timeout: 90_000,
  workers: 1,
  fullyParallel: false,
  retries: 0,
  reporter: [['list']],
  expect: {
    toHaveScreenshot: { maxDiffPixels: 40 },
  },
  use: {
    viewport: { width: 420, height: 90 },
  },
});
