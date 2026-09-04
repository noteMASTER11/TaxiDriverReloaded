import assert from "node:assert/strict";
import { chromium } from "playwright";
import { startHarnessServer } from "./server.mjs";

const { server, port } = await startHarnessServer(0);
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true, channel: process.env.TAXIDRIVER_BROWSER_CHANNEL || undefined });
const failures = [];
const check = async (name, test) => {
  const page = await browser.newPage({ viewport: { width: 520, height: 900 } });
  try { await test(page); console.log(`PASS ${name}`); }
  catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.message}`); }
  finally { await page.close(); }
};
const open = async (page, query = "scenario=trip") => {
  await page.goto(`${base}/?${query}`);
  await page.waitForFunction(() => !!window.__taxiHarnessReady);
  await page.locator(".taxi-shell").waitFor();
};
const state = (page, key) => page.evaluate(key => angular.element(document.querySelector("taxi-driver-hud")).scope()[key], key);
const emit = (page, name, data) => page.evaluate(({ name, data }) => {
  const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
  scope.$apply(() => scope.$root.$broadcast(name, data));
}, { name, data });
try {
  await check("minimized preference survives HUD recreation", async page => {
    await open(page);
    await page.locator(".taxi-shell__toggle").first().click();
    assert.equal(await state(page, "phoneMinimized"), true);
    await page.reload();
    await page.locator(".taxi-shell").waitFor();
    assert.equal(await state(page, "phoneMinimized"), true);
    assert.ok(await page.evaluate(() => window.__taxiEngineLuaCommands.some(c => c.includes("resetMinimapView()"))),
      "recreated native HUD must align its follow state with the native map camera");
  });
  await check("vanilla routes hide HUD and preserve collapse", async page => {
    await open(page);
    await page.locator(".taxi-shell__toggle").first().click();
    await emit(page, "ui_router_afterRouteChange", { request: { name: "pause.bigmap" } });
    assert.equal(await page.locator(".taxi-shell").isVisible(), false);
    await emit(page, "ui_router_afterRouteChange", { request: { name: "play" } });
    assert.equal(await page.locator(".taxi-compact").isVisible(), true);
    await emit(page, "ShowApps", false);
    assert.equal(await page.locator(".taxi-shell").isVisible(), false);
    await emit(page, "ShowApps", true);
    assert.equal(await page.locator(".taxi-compact").isVisible(), true);
  });
  await check("recreated HUD reads current route and ignores a stale route reply", async page => {
    await page.route("**/tests/ui/mock-env.js", async route => {
      const response = await route.fetch();
      const source = await response.text();
      await route.fulfill({ response, body: source + `
        const originalLua = bngApi.engineLua;
        bngApi.engineLua = (command, callback) => {
          if (command.includes('ui_router.getCurrent')) {
            window.__initialRouteReply = callback;
            callback('pause.bigmap');
          } else originalLua(command, callback);
        };` });
    });
    await page.goto(`${base}/?scenario=trip`);
    await page.waitForFunction(() => !!window.__taxiHarnessReady);
    assert.equal(await page.locator(".taxi-shell").isVisible(), false);
    await emit(page, "ui_router_afterRouteChange", { request: { name: "play" } });
    await page.evaluate(() => window.__initialRouteReply('pause.bigmap'));
    assert.equal(await page.locator(".taxi-shell").isVisible(), true);
  });
  await check("outer phone corners remain rounded after controls", async page => {
    await open(page);
    for (let i = 0; i < 2; i++) {
      const radius = await page.locator(".taxi-phone").evaluate(el => parseFloat(getComputedStyle(el).borderTopLeftRadius));
      assert.ok(radius >= 12, `phone radius ${radius}`);
      await page.locator(".taxi-shell__toggle").first().click();
      await page.locator(".taxi-shell__toggle").first().click();
    }
  });
  await check("starting fuel slider sends selected percentage", async page => {
    await open(page, "scenario=settings&realistic=1");
    const slider = page.locator('input[ng-model="settings.initialFuelPercent"]');
    assert.equal(await slider.count(), 1);
    assert.equal(await slider.getAttribute("min"), "5");
    assert.equal(await slider.getAttribute("max"), "30");
    await slider.fill("23");
    assert.equal((await state(page, "settings")).initialFuelPercent, 23);
    await page.waitForFunction(() => window.__taxiEngineLuaCommands.some(c => c.includes('"initialFuelPercent":23')));
  });
  await check("native map supports zoom, drag and follow", async page => {
    await open(page);
    await page.evaluate(() => { window.__taxiEngineLuaCommands = []; });
    const controls = page.locator(".taxi-map-controls").first();
    assert.equal(await controls.count(), 1);
    await controls.locator("button").first().click();
    assert.ok(await page.evaluate(() => window.__taxiEngineLuaCommands.some(c => c.includes("zoomMinimap(0.8)"))));
    const map = page.locator(".taxi-map-interaction").first();
    const box = await map.boundingBox();
    await page.mouse.move(box.x + box.width * .5, box.y + box.height * .6);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width * .7, box.y + box.height * .65, { steps: 3 });
    await page.mouse.up();
    assert.equal(await state(page, "mapFollowing"), false);
    assert.ok(await page.evaluate(() => window.__taxiEngineLuaCommands.some(c => c.includes("panMinimap("))));
    await controls.locator("button").last().click();
    assert.equal(await state(page, "mapFollowing"), true);
    assert.ok(await page.evaluate(() => window.__taxiEngineLuaCommands.some(c => c.includes("resetMinimapView()"))));
  });
  await check("phone map zooms and stays panned until follow", async page => {
    await open(page, "scenario=trip&external=1");
    await page.evaluate(() => {
      const original = bngApi.engineLua;
      bngApi.engineLua = (command, callback) => command.includes("pollExternalState")
        ? callback({ vehicle: { position: [0, 0, 0], direction: [0, 1] }, roads: [[-500, 0, 500, 0, 5, 1]] })
        : original(command, callback);
    });
    const controls = page.locator(".taxi-map-controls").first();
    assert.equal(await controls.count(), 1);
    await page.waitForFunction(() => Number(document.querySelector("canvas.taxi-external-minimap").dataset.mapRadius) > 0);
    const radius = await page.locator("canvas.taxi-external-minimap").evaluate(c => Number(c.dataset.mapRadius));
    await controls.locator("button").first().click();
    await page.waitForFunction(r => Number(document.querySelector("canvas.taxi-external-minimap").dataset.mapRadius) < r * .9, radius);
    const box = await page.locator(".taxi-map-interaction").first().boundingBox();
    await page.mouse.move(box.x + box.width * .5, box.y + box.height * .6);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width * .7, box.y + box.height * .65, { steps: 3 });
    await page.mouse.up();
    assert.equal(await state(page, "mapFollowing"), false);
    await page.waitForFunction(() => Number(document.querySelector("canvas.taxi-external-minimap").dataset.mapCenterX) < -10);
    await controls.locator("button").last().click();
    assert.equal(await state(page, "mapFollowing"), true);
    await page.waitForFunction(() => Math.abs(Number(document.querySelector("canvas.taxi-external-minimap").dataset.mapCenterX)) < 1);
  });
  await check("map buttons remain accessible in compact and narrow layouts", async page => {
    for (const [width, height, scenario, external] of [[320, 568, "trip", 0], [320, 568, "compact", 0], [390, 844, "trip", 1], [844, 390, "trip", 1]]) {
      await page.setViewportSize({ width, height });
      await open(page, `scenario=${scenario}&width=${width}&height=${height}&external=${external}`);
      for (const button of await page.locator(".taxi-map-controls button").all()) {
        assert.ok(await button.evaluate(el => {
          const r = el.getBoundingClientRect();
          return el.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2));
        }), `${scenario} ${width}x${height} button must not be clipped or covered`);
      }
    }
  });
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
assert.equal(failures.length, 0, failures.join(", "));
