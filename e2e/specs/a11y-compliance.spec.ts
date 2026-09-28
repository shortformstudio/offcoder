import { test, expect } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtureUrl = "file://" + path.join(here, "..", "fixtures", "cockpit-harness.html");

test.describe("Accessibility (a11y) & Semantic Compliance", () => {
  test.beforeEach(async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(fixtureUrl);
  });

  test("Semantic Landmarks: banner, main, regions, statuses", async ({ page }) => {
    // Header landmark
    const banner = page.locator("header[role=\"banner\"]");
    await expect(banner).toBeVisible();

    // Main landmark
    const main = page.locator("main[role=\"main\"]");
    await expect(main).toBeVisible();

    // Bento sections have role="region" and aria-labelledby matching title IDs
    const regions = page.locator("section[role=\"region\"]");
    const count = await regions.count();
    expect(count).toBeGreaterThanOrEqual(4);

    for (let i = 0; i < count; i++) {
      const region = regions.nth(i);
      const labelledBy = await region.getAttribute("aria-labelledby");
      expect(labelledBy).toBeTruthy();
      if (labelledBy) {
        const titleEl = page.locator("#" + labelledBy);
        await expect(titleEl).toBeVisible();
      }
    }
  });

  test("Live Regions: Status and Log elements possess aria-live=\"polite\"", async ({ page }) => {
    const marquee = page.locator("#marquee-banner");
    await expect(marquee).toHaveAttribute("role", "status");
    await expect(marquee).toHaveAttribute("aria-live", "polite");

    const chatLog = page.locator("#chat-messages");
    await expect(chatLog).toHaveAttribute("role", "log");
    await expect(chatLog).toHaveAttribute("aria-live", "polite");

    const netStatus = page.locator("#network-badge");
    await expect(netStatus).toHaveAttribute("role", "status");
    await expect(netStatus).toHaveAttribute("aria-live", "polite");
  });

  test("Keyboard Navigation: Focus cycles sequentially through interactive controls", async ({ page }) => {
    // Tab through header buttons
    await page.keyboard.press("Tab");
    const firstActiveId = await page.evaluate(() => (document.activeElement as HTMLElement)?.id);
    expect(["btn-toggle-staging", "btn-toggle-journal", "btn-reset-layout"]).toContain(firstActiveId);

    // Tab into chat input
    const input = page.locator("#chat-input");
    await input.focus();
    await expect(input).toBeFocused();

    // Tab to Send button
    await page.keyboard.press("Tab");
    const sendBtn = page.locator("#btn-send");
    await expect(sendBtn).toBeFocused();
  });

  test("Accessible Naming: Form controls and icon buttons have valid accessible labels", async ({ page }) => {
    const input = page.locator("#chat-input");
    await expect(input).toHaveAttribute("aria-label", "Chat input message");

    const closeBtns = page.locator("button[data-close]");
    const closeCount = await closeBtns.count();
    for (let i = 0; i < closeCount; i++) {
      await expect(closeBtns.nth(i)).toHaveAttribute("aria-label");
    }
  });
});