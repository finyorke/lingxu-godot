const { test, expect } = require("playwright/test");

test("Godot web build boots and reaches arena", async ({ page }) => {
  const browserErrors = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") browserErrors.push(msg.text());
  });
  page.on("pageerror", (err) => browserErrors.push(err.message));

  await page.goto("http://127.0.0.1:8008/index.html", { waitUntil: "domcontentloaded" });
  const canvas = page.locator("canvas").first();
  await expect(canvas).toBeVisible({ timeout: 15000 });
  await page.waitForTimeout(7000);

  const menuCanvas = await canvas.evaluate((c) => {
    const gl = c.getContext("webgl2") || c.getContext("webgl");
    return { width: c.width, height: c.height, webgl: !!gl };
  });
  expect(menuCanvas.width).toBeGreaterThan(200);
  expect(menuCanvas.height).toBeGreaterThan(200);
  expect(menuCanvas.webgl).toBeTruthy();
  await page.screenshot({ path: "test-results/web-menu.png", fullPage: true });

  await page.mouse.click(350, 230);
  await page.waitForTimeout(1000);
  await page.screenshot({ path: "test-results/web-root-choice.png", fullPage: true });
  await page.mouse.click(690, 405);
  await page.waitForTimeout(12000);

  await page.screenshot({ path: "test-results/web-arena.png", fullPage: true });
  expect(browserErrors.filter((e) => !/favicon|SharedArrayBuffer/i.test(e))).toEqual([]);
});
