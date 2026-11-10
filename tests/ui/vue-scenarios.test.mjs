import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { test } from 'node:test';
import { Window } from 'happy-dom';

const read = relative => fs.readFile(new URL(relative, import.meta.url), 'utf8');
const [html, fixtures, harness, bundle, dictionaries] = await Promise.all([
  read('./harness.html'), read('./mock-env.js'), read('./harness.js'),
  read('../../ui/modules/apps/TaxiDriverHUD/external/hud.bundle.js'),
  read('../../ui/modules/apps/TaxiDriverHUD/locales.json'),
]);

test('the visual harness uses the same Vue bundle as Connected Phone', () => {
  assert.doesNotMatch(html + fixtures + harness, /\bangular\b|\$scope|\$rootScope|\$broadcast|\$apply/);
  assert.match(html, /external\/hud\.bundle\.js/);
  assert.match(harness, /mountTaxiDriver/);
});

const scenarios = ['home', 'fleet', 'fleetTrip', 'orders', 'trip', 'delivery', 'overspeed',
  'boarding', 'forcedExit', 'settings', 'settingsAi', 'settingsFleet', 'settingsEvents',
  'settingsConnection', 'profile', 'profileVehicles', 'profileShifts', 'compact',
  'nextOffer', 'fuelRoute', 'fuel', 'magicFuel', 'shiftHistory'];
const expectedScreen = {
  home: '.taxi-start', fleet: '.taxi-fleet', fleetTrip: '.taxi-fleet',
  trip: '.taxi-trip-dashboard', delivery: '.taxi-trip-dashboard', overspeed: '.taxi-trip-dashboard',
  boarding: '.taxi-transfer', forcedExit: '.taxi-transfer--critical', nextOffer: '.taxi-next-offer',
  fuelRoute: '.taxi-fuel-route', fuel: '.taxi-fuel', magicFuel: '.taxi-fuel--magic',
  shiftHistory: '.taxi-shift-history',
};

function canvasContext(canvas) {
  const context = { canvas, measureText: text => ({width: String(text).length * 8}),
    createLinearGradient: () => ({addColorStop() {}}) };
  return new Proxy(context, {get(target, property) { return property in target ? target[property] : () => {}; }});
}

async function openHarness(scenario, external) {
  const window = new Window({url: `http://localhost/tests/ui/harness.html?scenario=${scenario}&external=${external ? 1 : 0}`});
  window.happyDOM.setWindowSize({width: 520, height: 900});
  window.document.body.innerHTML = '<main class="taxi-test-stage"><div id="taxi-hud-root"></div></main>';
  window.HTMLCanvasElement.prototype.getContext = function() { return canvasContext(this); };
  const errors = [];
  window.console.error = (...args) => errors.push(args.map(String).join(' '));
  window.addEventListener('error', event => errors.push(event.error?.stack || event.message));
  window.addEventListener('unhandledrejection', event => errors.push(String(event.reason)));
  window.XMLHttpRequest = class {
    open() {}
    send() {
      this.status = 200;
      this.responseText = dictionaries;
      queueMicrotask(() => this.onload?.());
    }
    abort() {}
  };
  window.eval(fixtures);
  window.eval(bundle);
  window.eval(harness);
  for (let attempt = 0; attempt < 100 && !window.__taxiHarnessReady; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  return {window, errors};
}

for (const external of [false, true]) {
  test(`all HUD scenarios render through real Vue DOM (${external ? 'Connected Phone' : 'game'})`, async () => {
    for (const scenario of scenarios) {
      const {window, errors} = await openHarness(scenario, external);
      try {
        assert.equal(window.__taxiHarnessReady, true, `${scenario}: initialization`);
        assert(window.document.querySelector('.taxi-shell'), `${scenario}: HUD shell`);
        assert.deepEqual(errors, [], `${scenario}: render errors`);
        assert.equal(window.document.querySelector('.taxi-runtime-error'), null, `${scenario}: startup failure`);
        const model = window.__taxiHudModel;
        assert(model?.view && model?.hud, `${scenario}: exposed model`);
        assert.equal(model.view.externalPhoneMode, external);
        window.__taxiSetState({balance: 123.45});
        await new Promise(resolve => setTimeout(resolve, 0));
        assert.equal(model.view.state.balance, 123.45, `${scenario}: state bridge API`);
        if (scenario.startsWith('settings')) assert(window.document.querySelector('.taxi-settings'), scenario);
        if (scenario.startsWith('profile')) assert(window.document.querySelector('.taxi-profile'), scenario);
        if (scenario === 'orders') assert.equal(window.document.querySelectorAll('.taxi-order-card').length, 12);
        if (scenario === 'compact' && !external) assert(window.document.querySelector('.taxi-compact'));
        if (expectedScreen[scenario]) assert(window.document.querySelector(expectedScreen[scenario]), `${scenario}: expected screen ${expectedScreen[scenario]}`);
      } finally {
        window.__taxiHudHandle?.unmount();
        await window.happyDOM.cancelAsync();
        window.close();
      }
    }
  });
}

test('Vue DOM inputs preserve numeric, boolean and string settings', async () => {
  const {window, errors} = await openHarness('settings', false);
  try {
    const view = window.__taxiHudModel.view;
    const fuel = window.document.getElementById('taxi-initial-fuel');
    fuel.value = '17';
    fuel.dispatchEvent(new window.Event('input', {bubbles: true}));
    assert.equal(view.settings.initialFuelPercent, 17);
    const remember = window.document.querySelector('.taxi-settings__languages').parentElement.querySelector('input[type="checkbox"]');
    remember.checked = false;
    remember.dispatchEvent(new window.Event('change', {bubbles: true}));
    assert.equal(view.settings.rememberLanguage, false);
    const address = window.document.querySelector('input.taxi-lan__url:not([readonly])');
    address.value = '192.168.1.25';
    address.dispatchEvent(new window.Event('input', {bubbles: true}));
    assert.equal(view.settings.lanManualAddress, '192.168.1.25');
    assert.deepEqual(errors, []);
  } finally {
    window.__taxiHudHandle?.unmount();
    await window.happyDOM.cancelAsync();
    window.close();
  }
});

test('home screen offers four keyboard-accessible presets without starting a shift', async () => {
  const {window, errors} = await openHarness('home', false);
  try {
    const buttons = [...window.document.querySelectorAll('.taxi-home__preset')];
    assert.equal(buttons.length, 4);
    buttons[0].click();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(window.__taxiHudModel.view.settings.difficulty, 'elementary');
    assert.equal(buttons[0].getAttribute('aria-pressed'), 'true');
    buttons[3].click();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(window.__taxiHudModel.view.settings.difficulty, 'professional');
    assert.equal(window.document.querySelectorAll('.taxi-home__preset[aria-pressed="true"]').length, 1);
    assert.equal(window.__taxiHudModel.view.state.active, false);
    assert.deepEqual(errors, []);
  } finally {
    window.__taxiHudHandle?.unmount();
    await window.happyDOM.cancelAsync();
    window.close();
  }
});

test('map navigation occupies the toolbar corner when the optional AI button disappears', async () => {
  for (const scenario of ['trip','fleet','fuelRoute','compact']) {
    const {window, errors} = await openHarness(scenario, false);
    try {
      const model = window.__taxiHudModel;
      const controls = window.document.querySelector('.taxi-map-controls');
      const toolbar = controls?.parentElement;
      assert(toolbar?.classList.contains('taxi-map-toolbar'), `${scenario}: shared flow toolbar`);
      model.view.settings.aiDriver.enabled = false;
      await new Promise(resolve => setTimeout(resolve, 0));
      assert.equal(toolbar.firstElementChild, controls, `${scenario}: navigation moves into the first slot`);
      model.view.settings.aiDriver.enabled = true;
      await new Promise(resolve => setTimeout(resolve, 0));
      const aiButton = toolbar.querySelector('.taxi-map__autopilot');
      if (aiButton) assert.equal(toolbar.firstElementChild, aiButton, `${scenario}: AI stays above navigation`);
      assert.equal(controls.querySelectorAll('button').length, 3);
      assert.deepEqual(errors, []);
    } finally {
      window.__taxiHudHandle?.unmount();
      await window.happyDOM.cancelAsync();
      window.close();
    }
  }
});

test('Earth panel renders explicit search, accessible results and isolated navigation controls', async () => {
  const {window, errors} = await openHarness('home', false);
  try {
    const {view, hud} = window.__taxiHudModel;
    const point = {name: 'Paris', detail: 'France · Île-de-France', lat: 48.8, lon: 2.3};
    window.__taxiSetState({earth: {available: true, status: 'ready', mode: 'points', a: {query: 'Paris', selected: point}, b: {query: 'Rome', selected: point}, route: {status: 'ready', distanceM: 1500, durationS: 600}, canNavigate: true}});
    await new Promise(resolve => setTimeout(resolve, 0));
    const button = window.document.querySelector('.taxi-earth-button');
    assert(button, 'Earth available on home'); button.click();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert(window.document.querySelector('.taxi-earth'));
    assert.equal(window.document.querySelector('.taxi-home'), null);
    assert.equal(window.document.querySelectorAll('.taxi-earth input[role="combobox"]').length, 2);
    assert.equal(window.document.querySelectorAll('.taxi-earth__navigate button').length, 2);
    const input = window.document.querySelector('#taxi-earth-a');
    input.value = 'Paris suburbs';
    input.dispatchEvent(new window.Event('input', {bubbles: true}));
    assert.equal(view.earth.a.selected, null);
    assert.equal(view.earth.route.status, 'idle');
    view.earth.a.results = [point]; view.earthExpanded.a = true;
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(window.document.querySelector('[role="option"] small').textContent, point.detail);
    input.dispatchEvent(new window.KeyboardEvent('keydown', {key: 'ArrowDown', bubbles: true}));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(input.getAttribute('aria-activedescendant'), 'taxi-earth-a-result-0');
    input.dispatchEvent(new window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(window.document.querySelector('[role="listbox"]'), null);
    hud.toggleProfile();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(window.document.querySelector('.taxi-earth'), null);
    assert.deepEqual(errors, []);
  } finally {
    window.__taxiHudHandle?.unmount(); await window.happyDOM.cancelAsync(); window.close();
  }
});

test('Earth exposes explicit teleport, random route and a gameplay limit of 600 km', async () => {
  const {window, errors} = await openHarness('home', false);
  try {
    const {view, hud} = window.__taxiHudModel;
    const point = {name: 'Paris', lat: 48.8, lon: 2.3};
    window.__taxiSetState({earth: {available: true, status: 'ready', mode: 'points', a: {selected: point}, canNavigate: true, maxRandomKm: 50}});
    await new Promise(resolve => setTimeout(resolve, 0));
    hud.openEarth();
    await new Promise(resolve => setTimeout(resolve, 0));
    const teleport = window.document.querySelector('.taxi-earth__teleport');
    assert(teleport, 'teleport sits beside selected point A');
    assert.equal(teleport.disabled, false);
    assert.equal((window.__taxiEngineLuaCommands || []).some(command => /earthCommand\("teleport"/.test(command)), false);
    teleport.click();
    assert.ok(window.__taxiEngineLuaCommands.some(command => /earthCommand\("teleport"/.test(command)));
    const random = window.document.querySelector('.taxi-earth__random');
    assert(random); assert.equal(random.disabled, false, 'B is not required'); random.click();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(view.earth.route.status, 'pending'); assert.equal(random.disabled, true);
    hud.toggleSettings(); view.settingsSections.gameplay = true;
    await new Promise(resolve => setTimeout(resolve, 0));
    const limit = window.document.getElementById('taxi-earth-random-limit');
    assert(limit); assert.equal(limit.min, '1'); assert.equal(limit.max, '600');
    limit.value = '700'; limit.dispatchEvent(new window.Event('input', {bubbles: true})); limit.dispatchEvent(new window.Event('change', {bubbles: true}));
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(view.earth.maxRandomKm, 600);
    assert.deepEqual(errors, []);
  } finally {
    window.__taxiHudHandle?.unmount(); await window.happyDOM.cancelAsync(); window.close();
  }
});
