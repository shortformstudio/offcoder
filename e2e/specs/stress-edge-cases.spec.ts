import { test, expect } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtureUrl = "file://" + path.join(here, "..", "fixtures", "cockpit-harness.html");

test.describe("Stress Testing & Edge Cases", () => {
  test.beforeEach(async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(fixtureUrl);
  });

  test("High-Frequency Batch Hydration: Ingest 150 journal entries rapidly", async ({ page }) => {
    await page.evaluate(() => {
      (window as any).simulateStressBatch(150);
    });

    const entries = page.locator(".journal-entry");
    await expect(entries).toHaveCount(150);

    // Verify DOM did not crash and header is intact
    await expect(page.locator("#title-journal")).toBeVisible();
  });

  test("High-Volume Candidate Ingestion: Stress staging ring buffer", async ({ page }) => {
    await page.evaluate(() => {
      for (let i = 0; i < 50; i++) {
        (window as any).injectStagingItem({
          id: "bulk-" + i,
          file: `module_${i}.ts`,
          worker: i % 2 === 0 ? "deepseek" : "qwythos"
        });
      }
    });

    await expect(page.locator(".staging-item")).toHaveCount(53); // 3 initial files in files-list + 50 staging
    await expect(page.locator("#staging-summary")).toContainText("50 candidates pending verification");

    // Rapidly accept 10 items
    for (let i = 0; i < 10; i++) {
      const item = page.locator("#staging-item-bulk-" + i);
      await item.locator("button").click();
    }

    await expect(page.locator("#staging-summary")).toContainText("40 candidates pending verification");
  });

  test("Rapid Bento Toggling & Resize: Layout stability under high oscillation", async ({ page }) => {
    const stagingBtn = page.locator("#btn-toggle-staging");
    const journalBtn = page.locator("#btn-toggle-journal");

    for (let i = 0; i < 10; i++) {
      await stagingBtn.click();
      await journalBtn.click();
    }

    // Reset and assert all remain stable
    await page.locator("#btn-reset-layout").click();
    await expect(page.locator("#bento-staging")).toBeVisible();
    await expect(page.locator("#bento-journal")).toBeVisible();
    await expect(page.locator("#bento-chat")).toBeVisible();
  });

  test("Boundary Payloads: Extremely long text handling in chat and marquee", async ({ page }) => {
    const longString = "A".repeat(2000);

    await page.evaluate((text) => {
      (window as any).injectMarquee({
        level: "alert",
        code: "overflow_check",
        text: text
      });
      (window as any).injectChatMessage("user", text);
    }, longString);

    const marqueeText = page.locator("#marquee-text");
    await expect(marqueeText).toBeVisible();

    const userBubble = page.locator(".chat-bubble.user").last();
    await expect(userBubble).toBeVisible();
    await expect(userBubble).toContainText("AAAA");
  });
});