import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { startHarnessServer } from "./server.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const artifacts = path.join(here, "artifacts");
await fs.mkdir(artifacts, { recursive: true });
const { server, port } = await startHarnessServer(41735);
const browser = await chromium.launch({ headless: true });
const scenarios = ["home", "orders", "trip", "delivery", "overspeed", "boarding", "forcedExit", "settings", "settingsConnection", "profile", "compact", "nextOffer", "fuel"];
const viewports = [{ width: 380, height: 736 }, { width: 520, height: 900 }, { width: 760, height: 980 }];

try {
  for (const viewport of viewports) {
    const page = await browser.newPage({ viewport });
    for (const scenario of scenarios) {
      await page.goto(`http://127.0.0.1:${port}/?scenario=${scenario}&width=${viewport.width}&height=${viewport.height}`);
      await page.waitForFunction(() => window.__taxiHarnessReady === true);
      if (scenario === "settingsConnection") {
        const indicator = page.locator(".taxi-settings__group--open .taxi-settings__group-head i").last();
        assert.equal((await indicator.textContent()).trim(), "-", "An expanded Settings group must show '-'");
        await indicator.locator("..").click();
        const collapsedIndicator = page.locator(".taxi-settings__group-head i").filter({ hasText: "+" }).last();
        assert.equal((await collapsedIndicator.textContent()).trim(), "+", "A collapsed Settings group must show '+'");
        await collapsedIndicator.locator("..").click();
      }
      if (scenario === "settings") {
        await page.locator(".taxi-settings__group--open:nth-of-type(5)").scrollIntoViewIfNeeded();
        await page.evaluate(() => {
          const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
          scope.$apply(() => { scope.cheatRating = 2.75; });
        });
        await page.locator(".taxi-settings__cheat-rating button").click();
        await page.waitForFunction(() => {
          const value = document.querySelector(".taxi-settings__cheat-stats strong");
          return value && value.textContent.trim() === "2.75";
        });
        const command = await page.evaluate(() =>
          (window.__taxiEngineLuaCommands || []).find((value) => value.includes("cheatSetRating")) || ""
        );
        assert.match(command, /cheatSetRating\(2\.75\).*requestHudState/,
          "Cheat rating must update Lua and request an authoritative HUD refresh");
      }
      if (scenario === "overspeed") {
        const sign = page.locator(".taxi-map__speed");
        await sign.waitFor();
        assert.equal(await sign.evaluate((element) => element.classList.contains("taxi-map__speed--warning")), true,
          "Speed sign must be red above the configured threshold");
        const firstCount = await page.evaluate(() =>
          window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
        );
        assert.equal(firstCount, 1, "Overspeed alert must play once when entering the warning state");
        await page.evaluate(() => window.__taxiSetState({ currentSpeed: 72 }));
        const repeatedCount = await page.evaluate(() =>
          window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
        );
        assert.equal(repeatedCount, 1, "Overspeed alert must not repeat while the warning remains active");
        await page.evaluate(() => window.__taxiSetState({ currentSpeed: 59 }));
        await page.waitForFunction(() => !document.querySelector(".taxi-map__speed--warning"));
        await page.evaluate(() => window.__taxiSetState({ currentSpeed: 72 }));
        await page.waitForFunction(() => document.querySelector(".taxi-map__speed--warning"));
        const secondCount = await page.evaluate(() =>
          window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
        );
        assert.equal(secondCount, 2, "Overspeed alert must play again after speed returns below the threshold");
      }
      const audit = await page.evaluate(() => window.__taxiVisualAudit());
      assert.deepEqual(audit.failures, [], `${scenario} ${viewport.width}x${viewport.height}: ${audit.failures.join(", ")}`);
      await page.screenshot({ path: path.join(artifacts, `${scenario}-${viewport.width}x${viewport.height}.png`) });
    }
    await page.close();
  }
  const loaderPage = await browser.newPage({ viewport: { width: 380, height: 736 } });
  await loaderPage.goto(`http://127.0.0.1:${port}/ui/modules/apps/TaxiDriverHUD/external/index.html`);
  const loader = loaderPage.locator("#taxi-loader");
  assert.equal(await loader.isVisible(), true, "External phone loader must be visible while connecting");
  assert.equal(await loaderPage.locator("#taxi-loader-steps li").count(), 4, "External phone loader must show four detailed stages");
  const loaderOverflow = await loaderPage.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
  assert.equal(loaderOverflow, false, "External phone loader must not overflow horizontally");
  await loaderPage.screenshot({ path: path.join(artifacts, "external-loader-380x736.png") });
  await loaderPage.close();

  const externalPage = await browser.newPage({ viewport: { width: 520, height: 900 } });
  await externalPage.goto(`http://127.0.0.1:${port}/?scenario=trip&external=1&width=520&height=900&token=0123456789abcdef0123`);
  await externalPage.waitForFunction(() => window.__taxiHarnessReady === true);
  await externalPage.waitForTimeout(150);
  assert.equal(await externalPage.locator(".taxi-shell__toggle").count(), 0,
    "External Web UI must not expose the Minimize control");
  const mapAudit = await externalPage.locator("canvas.taxi-external-minimap").evaluate((canvas) => {
    const ctx = canvas.getContext("2d");
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let roadPixels = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      if (red >= 75 && green >= 85 && blue >= 90 && Math.abs(red - green) < 40) roadPixels += 1;
    }
    const ratioX = canvas.width / canvas.getBoundingClientRect().width;
    const ratioY = canvas.height / canvas.getBoundingClientRect().height;
    const centerX = Math.round(canvas.width * 0.5);
    const centerY = Math.round(canvas.height * 0.68);
    let arrowPixels = 0;
    for (let y = Math.max(0, centerY - 22 * ratioY); y < Math.min(canvas.height, centerY + 22 * ratioY); y += 1) {
      for (let x = Math.max(0, centerX - 18 * ratioX); x < Math.min(canvas.width, centerX + 18 * ratioX); x += 1) {
        const index = (Math.floor(y) * canvas.width + Math.floor(x)) * 4;
        if (pixels[index] > 220 && pixels[index + 1] > 70 && pixels[index + 1] < 170 && pixels[index + 2] < 80) arrowPixels += 1;
      }
    }
    return { roadPixels, arrowPixels };
  });
  await externalPage.screenshot({ path: path.join(artifacts, "external-trip-520x900.png") });
  assert.ok(mapAudit.roadPixels > 500,
    `External map must render a visible road network (${JSON.stringify(mapAudit)})`);
  assert.ok(mapAudit.arrowPixels > 20,
    `External map must keep the vehicle arrow visible at the camera anchor (${JSON.stringify(mapAudit)})`);
  await externalPage.close();
  console.log(`TaxiDriverHUD: ${scenarios.length * viewports.length + 2} visual states passed.`);
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
