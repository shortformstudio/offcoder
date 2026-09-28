import { test, expect } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtureUrl = "file://" + path.join(here, "..", "fixtures", "cockpit-harness.html");

test.describe("Network Interception & Latency Resilience", () => {
  test.beforeEach(async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(fixtureUrl);
  });

  test("Offline Mode: Interception triggers modal overlay and alert marquee", async ({ page }) => {
    const offlineOverlay = page.locator("#offline-overlay");
    await expect(offlineOverlay).not.toBeVisible();

    // Trigger simulated offline state
    await page.evaluate(() => {
      (window as any).setNetworkState("offline");
    });

    await expect(offlineOverlay).toBeVisible();
    await expect(page.locator("#network-label")).toHaveText("OFFLINE");
    await expect(page.locator("#marquee-code")).toHaveText("NET_OFFLINE");

    // Recover via modal reconnect button
    await page.locator("#btn-reconnect").click();
    await expect(offlineOverlay).not.toBeVisible();
    await expect(page.locator("#network-label")).toHaveText("ONLINE");
    await expect(page.locator("#marquee-code")).toHaveText("NET_RESTORED");
  });

  test("Latency Simulation: 500ms network delay with timely response", async ({ page }) => {
    await page.evaluate(() => {
      (window as any).setNetworkState("latent", 500);
    });

    await expect(page.locator("#network-label")).toContainText("LATENT (500ms)");
    await expect(page.locator("#marquee-code")).toHaveText("HIGH_LATENCY");

    const input = page.locator("#chat-input");
    await input.fill("Execute latency benchmark");
    await page.locator("#btn-send").click();

    // Verify response arrives within bounds
    const assistantBubble = page.locator(".chat-bubble.assistant").last();
    await expect(assistantBubble).toContainText("Acknowledged instruction", { timeout: 3000 });
  });

  test("Extreme Latency Simulation: 1500ms degraded network recovery", async ({ page }) => {
    await page.evaluate(() => {
      (window as any).setNetworkState("latent", 1500);
    });

    await expect(page.locator("#network-label")).toContainText("LATENT (1500ms)");

    const input = page.locator("#chat-input");
    await input.fill("Perform deep audit under latency");
    await page.locator("#btn-send").click();

    const assistantBubble = page.locator(".chat-bubble.assistant").last();
    await expect(assistantBubble).toContainText("Acknowledged instruction", { timeout: 5000 });
  });
});