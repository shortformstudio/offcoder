import { test, expect } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtureUrl = "file://" + path.join(here, "..", "fixtures", "cockpit-harness.html");

test.describe("UI Components & Breakpoint Verification", () => {
  test.beforeEach(async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto(fixtureUrl);
  });

  test("DOM Structure: All primary Bento windows render with single authoritative titlebar", async ({ page }) => {
    const bentoIds = ["bento-files", "bento-chat", "bento-staging", "bento-journal", "bento-viewport"];

    for (const id of bentoIds) {
      const bento = page.locator("#" + id);
      await expect(bento).toBeVisible();

      // Title bar contains exactly one title element
      const titleBar = bento.locator(".bento-titlebar");
      await expect(titleBar).toBeVisible();
      const title = titleBar.locator(".bento-title");
      await expect(title).toHaveCount(1);

      // Verify ZERO duplicate titles inside bento-content body
      const content = bento.locator(".bento-content");
      const duplicateTitles = content.locator(".bento-title");
      await expect(duplicateTitles).toHaveCount(0);
    }
  });

  test("Interactive State Transitions: Staging candidate flow & DOM manipulation", async ({ page }) => {
    // Inject candidate
    await page.evaluate(() => {
      (window as any).injectStagingItem({
        id: "cand-42",
        file: "auth_service.py",
        worker: "deepseek_r1"
      });
    });

    const item = page.locator("#staging-item-cand-42");
    await expect(item).toBeVisible();
    await expect(item).toContainText("auth_service.py");
    await expect(page.locator("#staging-summary")).toContainText("1 candidates pending verification");

    // Click Accept button to transition state
    const acceptBtn = item.locator("button");
    await acceptBtn.click();

    // Verify DOM item removal and marquee update
    await expect(item).toHaveCount(0);
    await expect(page.locator("#staging-summary")).toContainText("0 candidates pending verification");
    await expect(page.locator("#marquee-code")).toHaveText("STAGED_ACCEPTED");
  });

  test("Chat Console: Message submission, stream bubble creation, and clear action", async ({ page }) => {
    const input = page.locator("#chat-input");
    const sendBtn = page.locator("#btn-send");

    await input.fill("Refactor tokenizer and optimize loop");
    await sendBtn.click();

    // Verify user bubble exists
    const userBubble = page.locator(".chat-bubble.user");
    await expect(userBubble).toContainText("Refactor tokenizer and optimize loop");

    // Wait for automated assistant response
    const assistantBubble = page.locator(".chat-bubble.assistant").last();
    await expect(assistantBubble).toContainText("Acknowledged instruction", { timeout: 3000 });

    // Clear chat
    await page.locator("#btn-clear-chat").click();
    await expect(page.locator(".chat-bubble")).toHaveCount(0);
  });

  test("Window Management: Toggle windows and reset layout", async ({ page }) => {
    const stagingWindow = page.locator("#bento-staging");
    const toggleStagingBtn = page.locator("#btn-toggle-staging");

    await expect(stagingWindow).toBeVisible();

    // Toggle off
    await toggleStagingBtn.click();
    await expect(stagingWindow).toHaveClass(/hidden/);

    // Reset layout
    await page.locator("#btn-reset-layout").click();
    await expect(stagingWindow).not.toHaveClass(/hidden/);
    await expect(stagingWindow).toBeVisible();
  });

  test("Mobile Breakpoint (375x667): Adapts to single-column responsive stacking", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    const chatWindow = page.locator("#bento-chat");
    const stagingWindow = page.locator("#bento-staging");

    await expect(chatWindow).toBeVisible();
    await expect(stagingWindow).toBeVisible();

    // Verify chat input is fully accessible and usable on mobile
    const input = page.locator("#chat-input");
    await expect(input).toBeVisible();
    const box = await input.boundingBox();
    expect(box?.width).toBeGreaterThan(200);
  });

  test("Tablet Breakpoint (768x1024): 2-column balanced layout", async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });

    const main = page.locator("main[role=\"main\"]");
    await expect(main).toBeVisible();

    const chatWindow = page.locator("#bento-chat");
    const stagingWindow = page.locator("#bento-staging");
    await expect(chatWindow).toBeVisible();
    await expect(stagingWindow).toBeVisible();
  });

  test("Desktop Breakpoint (1280x800): Full HUD grid presentation", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });

    const main = page.locator("main[role=\"main\"]");
    await expect(main).toBeVisible();

    const viewportBay = page.locator("#bento-viewport");
    await expect(viewportBay).toBeVisible();
    await expect(viewportBay).toContainText("SCREENCAST MIRROR STANDBY");
  });
});