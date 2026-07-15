import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright";
import { startHarnessServer } from "./server.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const artifacts = path.join(here, "artifacts");
const baselines = path.join(here, "baselines");
await fs.mkdir(artifacts, { recursive: true });
await fs.mkdir(baselines, { recursive: true });
const playwrightEntry = fileURLToPath(import.meta.resolve("playwright"));
const coreBundlePath = path.join(path.dirname(path.dirname(playwrightEntry)), "playwright-core", "lib", "coreBundle.js");
const { utils: playwrightUtils } = await import(pathToFileURL(coreBundlePath).href);
const comparePng = playwrightUtils.getComparator("image/png");
const externalLoaderSource = await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/external/external.js"),
  "utf8"
);
assert.match(
  externalLoaderSource,
  /\.api\.subscribeToEvents\(\s*["']\{\}["']\s*\)/,
  "External phone loader must subscribe before expecting TaxiDriver GUI hooks"
);
const { server, port } = await startHarnessServer(41735);
const browser = await chromium.launch({ headless: true });

const scenarios = [
  "home", "orders", "trip", "delivery", "overspeed", "boarding", "forcedExit",
  "settings", "settingsConnection", "profile", "compact", "nextOffer", "fuelRoute", "fuel",
];
const viewports = [
  { width: 320, height: 568 },
  { width: 360, height: 640 },
  { width: 390, height: 844 },
  { width: 520, height: 900 },
  { width: 768, height: 1024 },
  { width: 844, height: 390 },
  { width: 1024, height: 768 },
];
const locales = ["de", "en", "es", "fr", "it", "pl", "ru", "uk"];
const baselineScreenshots = new Set([
  "web-home-390x844.png",
  "web-orders-1024x768.png",
  "web-trip-390x844.png",
  "web-fuelRoute-390x844.png",
  "game-compact-320x568.png",
  "web-settingsConnection-1024x768.png",
  "web-profile-768x1024.png",
  "web-forcedExit-390x844.png",
  "web-fuel-390x844.png",
  "hidpi-trip-390x844@2x.png",
  "external-loader-844x390.png",
]);

const harnessUrl = (scenario, viewport, options = {}) => {
  const query = new URLSearchParams({
    scenario,
    width: String(viewport.width),
    height: String(viewport.height),
  });
  if (options.external) {
    query.set("external", "1");
    query.set("token", "0123456789abcdef0123");
  }
  if (options.locale) query.set("locale", options.locale);
  if (options.uiScale !== undefined) query.set("uiScale", String(options.uiScale));
  if (options.mockWebAudio) query.set("mockWebAudio", "1");
  if (options.extreme) query.set("extreme", "1");
  return `http://127.0.0.1:${port}/?${query}`;
};

const waitForHarness = async (page) => {
  await page.waitForFunction(() => window.__taxiHarnessReady === true);
  await page.evaluate(() => document.fonts && document.fonts.ready);
};

const assertVisualAudit = async (page, label) => {
  const audit = await page.evaluate(() => window.__taxiVisualAudit());
  assert.deepEqual(audit.failures, [], `${label}: ${audit.failures.join(", ")}`);
};

const screenshot = async (page, name, dpr = 1) => {
  const data = await page.screenshot({ path: path.join(artifacts, name) });
  if (dpr > 1) {
    const width = data.readUInt32BE(16);
    const height = data.readUInt32BE(20);
    const viewport = page.viewportSize();
    assert.equal(width, viewport.width * dpr, `${name}: HiDPI screenshot width must be native-resolution`);
    assert.equal(height, viewport.height * dpr, `${name}: HiDPI screenshot height must be native-resolution`);
  }
  if (baselineScreenshots.has(name)) {
    const baselinePath = path.join(baselines, name);
    if (process.env.UPDATE_UI_BASELINES === "1") {
      await fs.writeFile(baselinePath, data);
    } else {
      const expected = await fs.readFile(baselinePath).catch(() => null);
      assert.ok(expected, `${name}: baseline is missing; run with UPDATE_UI_BASELINES=1`);
      const result = comparePng(data, expected, { threshold: 0.2, maxDiffPixelRatio: 0.015 });
      if (result && result.diff) await fs.writeFile(path.join(artifacts, `${name}.diff.png`), result.diff);
      assert.equal(result, null, `${name}: ${result && result.errorMessage}`);
    }
  }
  return data;
};

try {
  let visualCount = 0;

  for (const external of [false, true]) {
    for (const viewport of viewports) {
      const page = await browser.newPage({ viewport });
      for (const scenario of scenarios) {
        await page.goto(harnessUrl(scenario, viewport, { external }));
        await waitForHarness(page);
        await assertVisualAudit(page, `${external ? "web" : "game"} ${scenario} ${viewport.width}x${viewport.height}`);
        if (external) {
          assert.equal(await page.locator(".taxi-shell__toggle").count(), 0,
            "External Web UI must not expose the Minimize control");
        }
        const prefix = external ? "web" : "game";
        await screenshot(page, `${prefix}-${scenario}-${viewport.width}x${viewport.height}.png`);
        visualCount += 1;
      }
      await page.close();
    }
  }

  const functionalPage = await browser.newPage({ viewport: { width: 520, height: 900 } });
  await functionalPage.goto(harnessUrl("settingsConnection", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const openIndicator = functionalPage.locator(".taxi-settings__group--open .taxi-settings__group-head i").last();
  assert.equal((await openIndicator.textContent()).trim(), "-", "An expanded Settings group must show '-'");
  await openIndicator.locator("..").click();
  const collapsedIndicator = functionalPage.locator(".taxi-settings__group-head i").filter({ hasText: "+" }).last();
  assert.equal((await collapsedIndicator.textContent()).trim(), "+", "A collapsed Settings group must show '+'");
  await collapsedIndicator.locator("..").click();

  await functionalPage.goto(harnessUrl("settings", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  await functionalPage.locator(".taxi-settings__group--open:nth-of-type(5)").scrollIntoViewIfNeeded();
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => { scope.cheatRating = 2.75; });
  });
  await functionalPage.locator(".taxi-settings__cheat-rating button").click();
  await functionalPage.waitForFunction(() => {
    const value = document.querySelector(".taxi-settings__cheat-stats strong");
    return value && value.textContent.trim() === "2.75";
  });
  const command = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("cheatSetRating")) || ""
  );
  assert.match(command, /^taxiDriver_taxiDriver\.cheatSetRating\(["']2\.75["']\)$/,
    "Cheat rating must be sent as a plain Lua statement with a serialized value");
  assert.doesNotMatch(command, /\b(?:if|return)\b/,
    "Cheat rating command must not use callback-incompatible Lua control flow");

  await functionalPage.goto(harnessUrl("overspeed", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const sign = functionalPage.locator(".taxi-map__speed");
  await sign.waitFor();
  assert.equal(await sign.evaluate((element) => element.classList.contains("taxi-map__speed--warning")), true,
    "Speed sign must be red above the configured threshold");
  const firstCount = await functionalPage.evaluate(() =>
    window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
  );
  assert.equal(firstCount, 1, "Overspeed alert must play once when entering the warning state");
  await functionalPage.evaluate(() => window.__taxiSetState({ currentSpeed: 59 }));
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-map__speed--warning"));
  await functionalPage.evaluate(() => window.__taxiSetState({ currentSpeed: 72 }));
  await functionalPage.waitForFunction(() => document.querySelector(".taxi-map__speed--warning"));
  const secondCount = await functionalPage.evaluate(() =>
    window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
  );
  assert.equal(secondCount, 2, "Overspeed alert must play again after returning below the threshold");
  await functionalPage.close();

  const iphoneAudioPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await iphoneAudioPage.goto(harnessUrl("trip", { width: 390, height: 844 }, {
    external: true, mockWebAudio: true,
  }));
  await waitForHarness(iphoneAudioPage);
  await iphoneAudioPage.waitForFunction(() => window.__taxiMockWebAudio?.decoded === 7);
  await iphoneAudioPage.evaluate(() => window.__taxiSetState({ active: false }));
  await iphoneAudioPage.waitForFunction(() => window.__taxiMockWebAudio.resumeCalls > 0);
  assert.equal(await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length), 0,
    "External event audio must remain queued until iOS grants a user gesture");
  await iphoneAudioPage.locator(".taxi-appbar__settings").click();
  await iphoneAudioPage.waitForFunction(() => window.__taxiMockWebAudio.starts.length >= 2);
  const unlockedStarts = await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length);
  await iphoneAudioPage.evaluate(() => window.__taxiSetState({ active: true }));
  await iphoneAudioPage.waitForFunction((count) => window.__taxiMockWebAudio.starts.length > count, unlockedStarts);
  const burstStart = await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length);
  await iphoneAudioPage.evaluate(() => {
    window.__taxiSetState({ currentSpeed: 72 });
    window.__taxiSetState({ nextOffer: {
      id: 999, passengerName: "Audio Test", accepted: false, duration: 5, timeRemaining: 5,
    } });
    window.__taxiSetState({ penaltyEvents: [
      ...window.__taxiScenarios.trip.penaltyEvents,
      { id: 999, type: "collision", penaltyPercent: 1, detail: "Audio test" },
    ] });
  });
  await iphoneAudioPage.waitForFunction((count) =>
    window.__taxiMockWebAudio.starts.length >= count + 3, burstStart
  );
  await iphoneAudioPage.close();

  for (const locale of locales) {
    const page = await browser.newPage({ viewport: { width: 360, height: 640 } });
    await page.goto(harnessUrl("orders", { width: 360, height: 640 }, {
      external: true, locale, uiScale: 180, extreme: true,
    }));
    await waitForHarness(page);
    await assertVisualAudit(page, `locale ${locale}`);
    await screenshot(page, `locale-${locale}-orders-360x640.png`);
    visualCount += 1;
    await page.close();
  }

  for (const external of [false, true]) {
    const measuredWidths = new Map();
    for (const uiScale of [80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180]) {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      await page.goto(harnessUrl("trip", { width: 390, height: 844 }, { external, uiScale }));
      await waitForHarness(page);
      await assertVisualAudit(page, `uiScale ${uiScale} ${external ? "web" : "game"}`);
      const geometry = await page.evaluate(() => {
        const rect = (selector) => {
          const value = document.querySelector(selector).getBoundingClientRect();
          return { left: value.left, top: value.top, right: value.right, bottom: value.bottom,
            width: value.width, height: value.height };
        };
        return {
          shell: rect(".taxi-shell"),
          stage: rect(".taxi-shell__scale-stage"),
          logo: rect(".taxi-appbar__logo"),
          settings: rect(".taxi-appbar__settings"),
          map: rect(".taxi-map"),
        };
      });
      assert.ok(Math.abs(geometry.stage.width - geometry.shell.width) < 1 &&
        Math.abs(geometry.stage.height - geometry.shell.height) < 1,
      `Scaled stage must fill its viewport at ${uiScale}% (${JSON.stringify(geometry)})`);
      assert.ok(geometry.map.left >= geometry.shell.left - 1 &&
        geometry.map.right <= geometry.shell.right + 1,
      `Scaled map must stay inside its viewport at ${uiScale}% (${JSON.stringify(geometry)})`);
      measuredWidths.set(uiScale, { logo: geometry.logo.width, settings: geometry.settings.width });
      if ([80, 100, 180].includes(uiScale)) {
        await screenshot(page, `scale-${uiScale}-${external ? "web" : "game"}-trip-390x844.png`);
      }
      visualCount += 1;
      await page.close();
    }
    const base = measuredWidths.get(100);
    for (const uiScale of [80, 180]) {
      const measured = measuredWidths.get(uiScale);
      const ratio = uiScale / 100;
      assert.ok(Math.abs(measured.logo / base.logo - ratio) < 0.03,
        `Logo geometry must scale to ${uiScale}% (${JSON.stringify(measuredWidths)})`);
      assert.ok(Math.abs(measured.settings / base.settings - ratio) < 0.03,
        `Control geometry must scale to ${uiScale}% (${JSON.stringify(measuredWidths)})`);
    }
  }

  const legacyScalePage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await legacyScalePage.goto(harnessUrl("trip", { width: 390, height: 844 }));
  await waitForHarness(legacyScalePage);
  await legacyScalePage.evaluate(() => window.__taxiSetState({ settings: { fontBoost: 2 } }));
  await legacyScalePage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope && scope.getUiScalePercent() === 100;
  });
  assert.equal(await legacyScalePage.locator(".taxi-shell__scale-stage").evaluate((element) =>
    Number.parseFloat(getComputedStyle(element).zoom)
  ), 1, "Legacy fontBoost 2 must migrate to the new 100% full-interface scale");
  await legacyScalePage.close();

  for (const hidpi of [
    { scenario: "trip", viewport: { width: 390, height: 844 } },
    { scenario: "orders", viewport: { width: 1024, height: 768 } },
  ]) {
    const page = await browser.newPage({ viewport: hidpi.viewport, deviceScaleFactor: 2 });
    await page.goto(harnessUrl(hidpi.scenario, hidpi.viewport, { external: true }));
    await waitForHarness(page);
    assert.equal(await page.evaluate(() => window.devicePixelRatio), 2, "HiDPI page must render at DPR 2");
    assert.equal(await page.evaluate(() => document.fonts.check('16px "Taxi Noto Sans"')), true,
      "Bundled UI font must be available before the HiDPI screenshot");
    await assertVisualAudit(page, `hidpi ${hidpi.scenario}`);
    await screenshot(page, `hidpi-${hidpi.scenario}-${hidpi.viewport.width}x${hidpi.viewport.height}@2x.png`, 2);
    visualCount += 1;
    await page.close();
  }

  for (const viewport of [{ width: 320, height: 568 }, { width: 844, height: 390 }]) {
    const loaderPage = await browser.newPage({ viewport });
    await loaderPage.goto(`http://127.0.0.1:${port}/ui/modules/apps/TaxiDriverHUD/external/index.html`);
    const loader = loaderPage.locator("#taxi-loader");
    assert.equal(await loader.isVisible(), true, "External phone loader must be visible while connecting");
    assert.equal(await loaderPage.locator("#taxi-loader-steps li").count(), 4,
      "External phone loader must show four detailed stages");
    const loaderAudit = await loaderPage.evaluate(() => {
      const card = document.querySelector(".taxi-loader__card");
      const rect = card.getBoundingClientRect();
      const loaderStyle = getComputedStyle(document.querySelector(".taxi-loader"));
      return {
        horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        bottom: rect.bottom,
        viewportHeight: window.innerHeight,
        scrollable: ["auto", "scroll"].includes(loaderStyle.overflowY),
      };
    });
    assert.equal(loaderAudit.horizontalOverflow, false, "External loader must not overflow horizontally");
    assert.ok(loaderAudit.bottom <= loaderAudit.viewportHeight + 1 || loaderAudit.scrollable,
      `External loader content must remain reachable (${JSON.stringify(loaderAudit)})`);
    await screenshot(loaderPage, `external-loader-${viewport.width}x${viewport.height}.png`);
    visualCount += 1;
    await loaderPage.close();
  }

  const mapPage = await browser.newPage({ viewport: { width: 520, height: 900 }, deviceScaleFactor: 2 });
  await mapPage.goto(harnessUrl("trip", { width: 520, height: 900 }, { external: true }));
  await waitForHarness(mapPage);
  const mapAudit = await mapPage.locator("canvas.taxi-external-minimap").evaluate((canvas) => {
    const ctx = canvas.getContext("2d");
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let roadPixels = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      if (red >= 75 && green >= 85 && blue >= 90 && Math.abs(red - green) < 40) roadPixels += 1;
    }
    const rect = canvas.getBoundingClientRect();
    return { roadPixels, width: canvas.width, height: canvas.height, cssWidth: rect.width, cssHeight: rect.height };
  });
  assert.ok(mapAudit.roadPixels > 1000, `External map must render a visible road network (${JSON.stringify(mapAudit)})`);
  assert.ok(mapAudit.width >= mapAudit.cssWidth * 2 - 1 && mapAudit.height >= mapAudit.cssHeight * 2 - 1,
    `External map must use a sharp DPR 2 backing store (${JSON.stringify(mapAudit)})`);
  const readExternalTargetRadius = async (speed) => {
    await mapPage.evaluate((value) => window.__taxiSetState({ currentSpeed: value }), speed);
    await mapPage.waitForFunction((value) => {
      const canvas = document.querySelector("canvas.taxi-external-minimap");
      return canvas && Number(canvas.dataset.mapSpeed) === value;
    }, speed);
    return mapPage.locator("canvas.taxi-external-minimap").evaluate((canvas) =>
      Number(canvas.dataset.mapTargetRadius)
    );
  };
  const externalRadius0 = await readExternalTargetRadius(0);
  const externalRadius60 = await readExternalTargetRadius(60);
  const externalRadius120 = await readExternalTargetRadius(120);
  assert.ok(externalRadius0 <= 230,
    `External map must start with a close camera (${externalRadius0})`);
  assert.ok(externalRadius60 <= 430,
    `External map must remain close at city speed (${externalRadius60})`);
  assert.ok(externalRadius120 <= 750,
    `External map must limit high-speed zoom-out (${externalRadius120})`);
  assert.ok(externalRadius0 < externalRadius60 && externalRadius60 < externalRadius120,
    `External map radius must grow smoothly with speed (${externalRadius0}, ${externalRadius60}, ${externalRadius120})`);
  await mapPage.close();

  console.log(`TaxiDriverHUD: ${visualCount} responsive visual states passed, including locales and HiDPI.`);
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
