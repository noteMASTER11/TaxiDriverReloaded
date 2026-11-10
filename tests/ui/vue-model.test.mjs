import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { Window } from 'happy-dom';
import * as vue from 'vue';

const localeText = await fs.readFile(new URL('../../ui/modules/apps/TaxiDriverHUD/locales.json', import.meta.url), 'utf8');
let fixtureId = 0;

async function fixture(t, { external = false, rememberedLanguage = 'en', deferLocales = false } = {}) {
  const browser = new Window({ url: 'http://localhost/?token=0123456789abcdef0123' });
  const { document } = browser;
  Object.defineProperty(document, 'visibilityState', { configurable: true, writable: true, value: 'visible' });
  Object.defineProperty(document, 'hidden', { configurable: true, writable: true, value: false });
  const host = document.createElement('taxi-driver-hud'); document.body.append(host);
  const events = new EventEmitter(), commands = [], requests = [], sounds = [], timers = new Map();
  let now = 10000, nextTimer = 0;
  const previous = new Map();
  const replace = (key, value) => {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, { configurable: true, writable: true, value });
  };
  const schedule = (fn, delay, repeat = false) => {
    const id = ++nextTimer; timers.set(id, { fn, at: now + delay, delay, repeat }); return id;
  };
  const timeout = (fn, delay = 0) => schedule(fn, delay);
  const cancel = id => timers.delete(id);
  replace('window', browser); replace('document', document);
  replace('Date', class extends Date { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } });
  replace('setTimeout', timeout); replace('clearTimeout', cancel);
  replace('setInterval', (fn, delay) => schedule(fn, delay, true)); replace('clearInterval', cancel);
  replace('requestAnimationFrame', fn => schedule(fn, 16)); replace('cancelAnimationFrame', cancel);
  replace('ResizeObserver', undefined);
  replace('Audio', class { constructor(source) { this.src = source; } play() { sounds.push(this.src); return Promise.resolve(); } pause() {} });
  replace('XMLHttpRequest', class {
    constructor() { requests.push(this); }
    open(method, url, async) { Object.assign(this, { method, url, async }); }
    send() { if (!deferLocales) queueMicrotask(() => this.respond()); }
    respond() { this.status = 200; this.responseText = localeText; this.onload(); }
  });
  browser.setTimeout = timeout; browser.clearTimeout = cancel;
  browser.localStorage.setItem('taxiDriverHUD.settings.v1', JSON.stringify({ rememberLanguage: true, language: rememberedLanguage }));
  const bridge = { events, api: {
    serializeToLua: JSON.stringify,
    engineLua(command, callback) {
      commands.push(command);
      if (command.includes('ui_router.getCurrent')) callback?.('play');
      else if (command.includes('AudioUiVol')) callback?.(1);
      else if (command.includes('pollExternalState')) callback?.({ available: false });
    },
  } };
  const { createHudModel } = await import(`../../ui/modules/apps/TaxiDriverHUD/hud-model.js?case=${++fixtureId}`);
  const create = () => createHudModel({ host, bridge, vue, externalPhoneMode: external });
  const models = [create()];
  const flush = async () => { for (let i = 0; i < 4; i++) await vue.nextTick(); };
  const advance = async ms => {
    const end = now + ms;
    while (true) {
      const next = [...timers.entries()].filter(([, value]) => value.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      const [id, timer] = next; now = timer.at;
      if (timer.repeat) timer.at += timer.delay; else timers.delete(id);
      timer.fn(); await flush();
    }
    now = end; await flush();
  };
  const button = () => {
    const target = document.createElement('button'); target.className = 'taxi-offline-hold';
    target.innerHTML = '<span class="taxi-offline-hold__fill"></span><span>Offline</span>';
    host.append(target); return target;
  };
  t.after(async () => {
    models.forEach(model => model.destroy()); timers.clear();
    for (const [key, descriptor] of previous) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor); else delete globalThis[key];
    }
    await browser.happyDOM.abort();
  });
  await flush();
  return { ...models[0], host, bridge, commands, sounds, requests, timers, browser, button, advance, flush,
    recreate() { const model = create(); models.push(model); return model; },
    send(data) { events.emit('TaxiDriverHUDState', { ...vue.toRaw(models[0].view.state), ...data }); },
  };
}

test('Vue model bootstraps without an Angular runtime and shares async locale loading', async t => {
  const h = await fixture(t, { rememberedLanguage: 'ru' });
  assert.equal(vue.isReactive(h.view), true);
  assert.equal(h.view.t('sortDistance'), 'Длина маршрута');
  assert.ok(h.commands.some(command => command.includes('requestHudState()')));
  assert.equal(h.requests[0].async, true);
  h.recreate(); await h.flush();
  assert.equal(h.requests.length, 1);
});

test('Vue dependencies update translations and preserve selected backend language', async t => {
  const h = await fixture(t);
  const translated = vue.computed(() => h.view.t('sortDistance'));
  assert.equal(translated.value, 'Route distance');
  h.hud.selectLanguage('ru'); await h.flush();
  assert.equal(translated.value, 'Длина маршрута');
  h.send({ active: true, settings: { ...vue.toRaw(h.view.settings) } });
  h.send({ active: true, settings: { ...vue.toRaw(h.view.settings), language: 'uk' } }); await h.flush();
  assert.equal(h.view.language, 'uk');
  assert.equal(translated.value, 'Довжина маршруту');
});

test('home presets apply only penalty rules and flush the selection before a new shift', async t => {
  const h = await fixture(t);
  h.view.settings.difficulty = 'custom';
  h.view.settings.penaltyToggles.speeding = false;
  h.view.settings.penaltyToggles.rushBonus = false;
  const custom = JSON.stringify(h.view.settings.customDifficulty);
  const unrelated = JSON.stringify({ai: h.view.settings.aiDriver, realistic: h.view.settings.realisticMode,
    random: h.view.settings.randomEventsEnabled, economy: h.view.settings.economyMultiplier});
  assert.deepEqual([...h.view.homeDifficultyPresets], ['elementary','easy','standard','professional']);
  assert.equal(h.view.hasHomeDifficultyPreset(), false, 'custom settings must not be silently replaced');
  h.hud.selectHomeDifficulty('elementary');
  const penaltyKeys = ['speeding','collision','aggression','pickupDelay','fuelStop','cargoDamage'];
  assert(penaltyKeys.every(key => h.view.settings.penaltyToggles[key] === false));
  assert.equal(h.view.settings.penaltyToggles.rushBonus, false, 'presets preserve the independent bonus switch');
  assert.equal(h.view.isHomeDifficultySelected('elementary'), true);
  h.hud.selectHomeDifficulty('easy');
  assert(penaltyKeys.every(key => h.view.settings.penaltyToggles[key] === true));
  assert.equal(h.view.hasHomeDifficultyPreset(), true);
  assert.equal(JSON.stringify(h.view.settings.customDifficulty), custom, 'custom sliders stay saved');
  assert.equal(JSON.stringify({ai: h.view.settings.aiDriver, realistic: h.view.settings.realisticMode,
    random: h.view.settings.randomEventsEnabled, economy: h.view.settings.economyMultiplier}), unrelated);
  h.hud.settingsChanged(); // Other controls can still have a debounced save.
  const beforeStart = h.commands.length;
  h.hud.startMode();
  const startCommands = h.commands.slice(beforeStart);
  assert.match(startCommands[0], /saveSettings\(/, 'save must precede start even when clicked without waiting');
  assert.match(startCommands[1], /startMode\(/);
  const saved = JSON.parse(startCommands[0].match(/saveSettings\((.*)\)$/)[1]);
  assert.equal(saved.difficulty, 'easy');
  const savedCalls = h.commands.filter(command => command.includes('.saveSettings(')).length;
  await h.advance(500);
  assert.equal(h.commands.filter(command => command.includes('.saveSettings(')).length, savedCalls,
    'starting the shift cancels the pending debounce instead of saving twice');
  h.view.settings.penaltyToggles.collision = false;
  assert.equal(h.view.hasHomeDifficultyPreset(), false, 'manual overrides must not pretend to be a full preset');
  h.hud.selectHomeDifficulty('invalid');
  assert.equal(h.view.settings.difficulty, 'easy');
});

test('a selected home preset saves immediately and survives immediate HUD destruction', async t => {
  const h = await fixture(t);
  const before = h.commands.filter(command => command.includes('.saveSettings(')).length;
  h.hud.selectHomeDifficulty('elementary');
  const saves = h.commands.filter(command => command.includes('.saveSettings('));
  assert.equal(saves.length, before + 1, 'a discrete preset choice must not wait for a debounce timer');
  const saved = JSON.parse(saves.at(-1).match(/saveSettings\((.*)\)$/)[1]);
  assert.equal(saved.difficulty, 'elementary');
  assert.equal(saved.penaltyToggles.cargoDamage, false);
  h.destroy();
  await h.advance(500);
  assert.equal(h.commands.filter(command => command.includes('.saveSettings(')).length, before + 1,
    'shutdown must neither discard nor duplicate the already submitted choice');
});

test('a computed translation invalidates when the asynchronous locale response arrives', async t => {
  const h = await fixture(t, { deferLocales: true });
  const translated = vue.computed(() => h.view.t('sortDistance'));
  assert.equal(translated.value, 'sortDistance');
  h.requests[0].respond(); await h.flush();
  assert.equal(translated.value, 'Route distance');
});

test('late external bridge replies cannot restart map work after the model is destroyed', async t => {
  const h = await fixture(t, { external: true });
  let reply;
  const original = h.bridge.api.engineLua;
  h.bridge.api.engineLua = (command, callback) => {
    if (command.includes('pollExternalState')) reply = callback;
    else original(command, callback);
  };
  h.send({ active: true, phase: 'toDestination' });
  await h.advance(500);
  assert.equal(typeof reply, 'function');
  h.destroy();
  reply({ vehicle: { position: [20, 30], direction: [1, 0] }, roads: [[0, 0, 10, 10, 5, 1]], map: { route: [[0, 0], [10, 10]] } });
  assert.equal(h.timers.size, 0);
});

test('route sorting and memoized views work with actual Vue reactive arrays', async t => {
  const h = await fixture(t);
  h.send({ active: true, offers: [
    { id: 1, rideDistance: 8000, pickupDistance: 10, estimatedFare: 90 },
    { id: 2, rideDistance: 2000, pickupDistance: 900, estimatedFare: 20 },
    { id: 3, rideDistance: 5000, pickupDistance: 20, estimatedFare: 50 },
  ] });
  h.hud.selectOfferSort('distance');
  const offers = h.view.getSortedOffers();
  assert.deepEqual(offers.map(offer => offer.id), [2, 3, 1]);
  assert.deepEqual(h.view.state.offers.map(offer => offer.id), [1, 2, 3]);
  for (let i = 0; i < 1000; i++) assert.equal(h.view.getSortedOffers(), offers);
  h.hud.selectOfferSort('fare');
  assert.deepEqual(h.view.getSortedOffers().map(offer => offer.id), [1, 3, 2]);
});

test('bridge revisions apply patches locally, ignore duplicates and request missing baselines', async t => {
  const h = await fixture(t);
  h.send({ hudEpoch: 'session-a', hudRevision: 1, balance: 10 });
  h.bridge.events.emit('TaxiDriverHUDPatch', { epoch: 'session-a', baseRevision: 1, revision: 2, values: { balance: 25 } });
  assert.equal(h.view.state.balance, 25);
  h.bridge.events.emit('TaxiDriverHUDPatch', { epoch: 'session-a', baseRevision: 1, revision: 2, values: { balance: 5 } });
  assert.equal(h.view.state.balance, 25);
  h.bridge.events.emit('TaxiDriverHUDPatch', { epoch: 'session-a', baseRevision: 9, revision: 10, values: { balance: 99 } });
  assert.equal(h.view.state.balance, 25);
  assert.ok(h.commands.some(command => command.includes('requestExternalHudState()')));
});

test('native route events and configuration visibility preserve collapse preference', async t => {
  const h = await fixture(t);
  h.hud.toggleMinimized(); assert.equal(h.view.phoneMinimized, true);
  h.bridge.events.emit('ui_router_afterRouteChange', { request: { name: 'pause.bigmap' } });
  assert.equal(h.view.nativeUiSuspended, true);
  h.bridge.events.emit('ui_router_afterRouteChange', { request: { name: 'play' } });
  assert.equal(h.view.nativeUiSuspended, false);
  h.bridge.events.emit('TaxiDriverUiSuspended', { suspended: true });
  assert.equal(h.view.vehicleConfigSuspended, true);
  assert.equal(h.view.phoneMinimized, true);
  const recreated = h.recreate(); assert.equal(recreated.view.phoneMinimized, true);
});

test('settings, profile, fleet and AI controls retain their bridge commands', async t => {
  const h = await fixture(t);
  h.hud.toggleSettings(); assert.equal(h.view.settingsOpen, true);
  h.hud.selectDifficulty('professional');
  h.hud.selectAiDriverPreset('cautious');
  h.view.settings.initialFuelPercent = 23; h.hud.settingsChanged();
  await h.advance(1000);
  assert.ok(h.commands.some(command => command.includes('"initialFuelPercent":23')));
  assert.equal(h.view.settings.aiDriver.preset, 'cautious');
  h.hud.fleetCommand('hire', { id: 7 });
  assert.ok(h.commands.some(command => command.includes('.fleetCommand("hire", {"id":7})')));
  h.hud.toggleProfile();
  h.view.profileDraft.fullName = 'Driver Test'; h.hud.saveProfile();
  assert.ok(h.commands.some(command => command.includes('.saveDriverProfile(') && command.includes('Driver Test')));
});

test('profile bridge data still builds reviews and sortable vehicle history', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverProfileData', { profile: { fullName: 'Test' }, progress: { reviews: [
    { id: 1, rating: 5 }, { id: 2, rating: 4 },
  ] }, vehicles: [
    { key: 'a', name: 'Car A', income: 10, distanceMeters: 100 },
    { key: 'b', name: 'Car B', income: 20, distanceMeters: 50 },
  ] });
  assert.deepEqual(h.view.profileReviews.map(review => review.id), [2, 1]);
  h.hud.selectVehicleSort('income');
  assert.deepEqual(h.view.getSortedProfileVehicles().map(vehicle => vehicle.key), ['b', 'a']);
});

test('Offline pointer hold animates the pressed DOM button and completes only after two seconds', async t => {
  const h = await fixture(t), button = h.button();
  button.dispatchEvent(new h.browser.PointerEvent('pointerdown', { bubbles: true, button: 0 }));
  assert.equal(button.classList.contains('taxi-offline-hold--holding'), true);
  await h.advance(1999);
  assert.equal(h.commands.filter(command => command.includes('.stopMode()')).length, 0);
  await h.advance(1);
  assert.equal(h.commands.filter(command => command.includes('.stopMode()')).length, 1);
  assert.equal(button.classList.contains('taxi-offline-hold--holding'), false);
});

for (const interruption of ['pointerup', 'pointercancel', 'blur', 'visibilitychange', 'keyup']) {
  test(`Offline hold cancels on global ${interruption}`, async t => {
    const h = await fixture(t), button = h.button();
    button.dispatchEvent(new h.browser.PointerEvent('pointerdown', { bubbles: true, button: 0 }));
    await h.advance(500);
    if (interruption === 'visibilitychange') {
      document.hidden = true; document.visibilityState = 'hidden'; document.dispatchEvent(new h.browser.Event(interruption));
    } else if (interruption === 'keyup') h.browser.dispatchEvent(new h.browser.KeyboardEvent('keyup', { key: ' ' }));
    else h.browser.dispatchEvent(new h.browser.Event(interruption));
    await h.advance(2000);
    assert.equal(h.commands.filter(command => command.includes('.stopMode()')).length, 0);
    assert.equal(button.classList.contains('taxi-offline-hold--holding'), false);
  });
}

test('Offline with a passenger opens the confirmation, and Vue watchers focus the dialog', async t => {
  const h = await fixture(t), button = h.button();
  h.view.state.passengerOnboard = true;
  h.host.insertAdjacentHTML('beforeend', '<div class="taxi-offline-confirm" role="dialog"><div class="taxi-offline-confirm__card"><button id="confirm">Confirm</button></div></div>');
  button.dispatchEvent(new h.browser.PointerEvent('pointerdown', { bubbles: true, button: 0 }));
  await h.advance(2000);
  assert.equal(h.view.offlineConfirmOpen, true);
  assert.equal(document.activeElement.id, 'confirm');
  assert.equal(h.commands.filter(command => command.includes('.stopMode()')).length, 0);
});

test('next-offer expiry remains deadline-based and rejects stale repeat packets', async t => {
  const h = await fixture(t);
  const offer = { id: 42, timeRemaining: 2, duration: 2, accepted: false };
  h.send({ active: true, nextOffer: { ...offer } });
  await h.advance(1000); assert.equal(h.view.nextOfferUiRemaining, 1);
  h.send({ active: true, nextOffer: { ...offer } });
  await h.advance(1000); assert.equal(h.view.state.nextOffer, null);
  assert.equal(h.commands.filter(command => command.includes('.expireNextOffer(42)')).length, 1);
});

test('external client uses the supplied bridge and view watcher without global bngApi', async t => {
  const h = await fixture(t, { external: true });
  assert.equal(h.view.externalPhoneMode, true);
  assert.ok(h.commands.some(command => command.includes('.externalPhoneHeartbeat(')));
  const before = h.commands.length;
  h.view.settingsOpen = true; await h.flush();
  assert.ok(h.commands.slice(before).some(command => command.includes('"settings"')));
});

test('regression: external map polling recovers after a missing reply and ignores its late callback', async t => {
  const h = await fixture(t, { external: true });
  const replies = [];
  const original = h.bridge.api.engineLua;
  h.bridge.api.engineLua = (command, callback) => {
    if (command.includes('pollExternalState')) replies.push({ command, callback });
    else original(command, callback);
  };
  h.send({ active: true, phase: 'toDestination' });
  await h.advance(500);
  assert.equal(replies.length, 1);
  await h.advance(6000);
  assert.equal(replies.length, 2, 'a missing map reply must eventually allow a new request');
  replies[0].callback({ mapRevision: 99, map: { route: [[1, 2], [3, 4]] } });
  await h.advance(500);
  assert.equal(replies.length, 2, 'a late response must not finish the current request');
  replies[1].callback({ available: false });
  await h.advance(500);
  assert.equal(replies.length, 3);
  assert.match(replies[2].command, /pollExternalState\(0, 0\)/, 'late data must not replace the newer map');
  h.destroy();
  assert.equal(h.timers.size, 0, 'request watchdog is owned by the model');
});

test('regression: a new HUD epoch permits reused next-offer and notification ids', async t => {
  const h = await fixture(t);
  h.send({ hudEpoch: 'old', hudRevision: 1, active: true, phase: 'toDestination',
    nextOffer: { id: 1, duration: 1, timeRemaining: 1 },
    notification: { id: 1, key: 'notify_orderAccepted' } });
  await h.advance(1000);
  assert.equal(h.view.state.nextOffer, null);
  h.bridge.events.emit('TaxiDriverHUDState', { ...vue.toRaw(h.view.state),
    hudEpoch: 'new', hudRevision: 1,
    nextOffer: { id: 1, duration: 10, timeRemaining: 10 },
    notification: { id: 1, key: 'notify_deliveryAccepted' } });
  assert.equal(h.view.state.nextOffer?.id, 1, 'new session must not inherit expired offer ids');
  assert.equal(h.view.nextOfferUiRemaining, 10);
  assert.equal(h.view.phoneToast?.key, 'notify_deliveryAccepted', 'new session must accept its first notification');
});

test('regression: a new HUD epoch starts a fresh deadline for a still-tracked offer id', async t => {
  const h = await fixture(t);
  h.send({ hudEpoch: 'old', hudRevision: 1, active: true, phase: 'toDestination',
    nextOffer: { id: 7, duration: 5, timeRemaining: 5 } });
  await h.advance(4000);
  h.send({ hudEpoch: 'new', hudRevision: 1,
    nextOffer: { id: 7, duration: 10, timeRemaining: 10 } });
  assert.equal(h.view.nextOfferUiRemaining, 10, 'the previous session deadline must not shorten a new offer');
});

test('regression: full snapshots clear absent nullable fields without patches reviving an old offer', async t => {
  const h = await fixture(t);
  h.send({ hudEpoch: 'session', hudRevision: 1, active: true, phase: 'toDestination',
    nextOffer: { id: 9, duration: 10, timeRemaining: 10 },
    notification: { id: 1, key: 'notify_orderAccepted' } });
  h.bridge.events.emit('TaxiDriverHUDPatch', { epoch: 'session', baseRevision: 1, revision: 2,
    values: { balance: 20 } });
  assert.equal(h.view.state.nextOffer?.id, 9, 'an unrelated patch must preserve an active offer');
  const fullState = { ...vue.toRaw(h.view.state), hudRevision: 3 };
  delete fullState.nextOffer; delete fullState.notification;
  h.bridge.events.emit('TaxiDriverHUDState', fullState);
  assert.equal(h.view.state.nextOffer, null, 'Lua nil omits this field from the full snapshot');
  assert.equal(h.view.state.notification, null);
  h.bridge.events.emit('TaxiDriverHUDPatch', { epoch: 'session', baseRevision: 3, revision: 4,
    values: { balance: 30 } });
  assert.equal(h.view.state.nextOffer, null);
  assert.equal(h.view.nextOfferUiRemaining, 0, 'an unrelated patch must not restart an obsolete countdown');
  assert.equal(h.view.shouldShowNextOffer(), false);
});

test('100 model mount/destroy cycles release listeners, timers and frames despite late bridge replies', async t => {
  const h = await fixture(t, { external: true });
  h.destroy();
  const listeners = [];
  const restore = [];
  const captureOf = options => typeof options === 'boolean' ? options : options?.capture === true;
  for (const target of [h.host, h.browser, h.browser.document]) {
    const add = target.addEventListener, remove = target.removeEventListener;
    target.addEventListener = function(name, callback, options) {
      const capture = captureOf(options);
      if (!listeners.some(item => item.target === target && item.name === name &&
          item.callback === callback && item.capture === capture)) {
        listeners.push({ target, name, callback, capture });
      }
      return add.call(this, name, callback, options);
    };
    target.removeEventListener = function(name, callback, options) {
      const index = listeners.findIndex(item => item.target === target && item.name === name &&
        item.callback === callback && item.capture === captureOf(options));
      if (index >= 0) listeners.splice(index, 1);
      return remove.call(this, name, callback, options);
    };
    restore.push(() => { target.addEventListener = add; target.removeEventListener = remove; });
  }
  t.after(() => restore.forEach(callback => callback()));
  let pendingReply;
  const original = h.bridge.api.engineLua;
  h.bridge.api.engineLua = (command, callback) => {
    if (command.includes('pollExternalState')) pendingReply = callback;
    else original(command, callback);
  };
  const lateReplies = [];
  let activeListenerCount;
  for (let cycle = 0; cycle < 100; cycle += 1) {
    const model = h.recreate();
    h.bridge.events.emit('TaxiDriverHUDState', { ...vue.toRaw(model.view.state),
      active: true, phase: 'toDestination', balance: cycle });
    await h.advance(250);
    assert.equal(typeof pendingReply, 'function');
    lateReplies.push(pendingReply); pendingReply = null;
    activeListenerCount ??= listeners.length;
    assert.equal(listeners.length, activeListenerCount, `cycle ${cycle}: listener count must not grow`);
    h.bridge.events.emit('TaxiDriverProfileData', { progress: { reviews: [{ id: cycle + 1 }] } });
    assert.ok([...h.timers.values()].some(timer => timer.delay === 16), 'exercise a pending review RAF');
    model.destroy(); model.destroy();
    for (const reply of lateReplies) reply({ vehicle: { position: [20, 30], direction: [1, 0] },
      roads: [[0, 0, 10, 10, 5, 1]], mapRevision: 1, map: { route: [[0, 0], [10, 10]] } });
    h.bridge.events.emit('TaxiDriverHUDState', { balance: -1 });
    await h.flush();
    assert.equal(model.view.state.balance, cycle, `cycle ${cycle}: destroyed state must stay unchanged`);
    assert.equal(h.bridge.events.eventNames().length, 0, `cycle ${cycle}: no bridge subscriptions`);
    assert.equal(listeners.length, 0, `cycle ${cycle}: no DOM subscriptions`);
    assert.equal([...h.timers.values()].filter(timer => timer.delay === 16).length, 0, `cycle ${cycle}: no RAF`);
    assert.equal(h.timers.size, 0, `cycle ${cycle}: no timers or watchdogs`);
  }
});

test('destroy removes bridge subscriptions and all owned timers; late events do not mutate Vue state', async t => {
  const h = await fixture(t);
  h.hud.beginOfflineHold({ target: h.button(), button: 0, preventDefault() {} });
  await h.advance(100);
  h.destroy(); h.destroy();
  assert.equal(h.bridge.events.eventNames().length, 0);
  assert.equal(h.timers.size, 0);
  const balance = h.view.state.balance;
  h.send({ balance: 999 }); await h.advance(5000);
  assert.equal(h.view.state.balance, balance);
  assert.equal(h.commands.filter(command => command.includes('.stopMode()')).length, 0);
});

test('destroy before the first frame cancels every scheduled native map and review frame', async t => {
  const h = await fixture(t);
  h.destroy();
  assert.equal(h.timers.size, 0);
});

for (const [failingCommand, external] of [
  ['requestHudState()', false], ['AudioUiVol', false], ['ui_router.getCurrent', false],
  ['requestExternalHudState()', true],
]) {
  test(`a startup bridge failure at ${failingCommand} releases resources before the factory returns`, async t => {
    const h = await fixture(t, { external });
    h.destroy();
    const original = h.bridge.api.engineLua;
    const failure = new Error('startup bridge failure');
    h.bridge.api.engineLua = (command, callback) => {
      if (command.includes(failingCommand)) throw failure;
      return original(command, callback);
    };
    assert.throws(() => h.recreate(), error => error === failure, 'factory must preserve the original startup error');
    await h.flush();
    assert.equal(h.bridge.events.eventNames().length, 0, 'failed startup must remove its bridge listeners');
    assert.equal(h.timers.size, 0, 'failed startup must cancel timers and animation frames');
    const commandCount = h.commands.length;
    h.browser.dispatchEvent(new h.browser.Event('focus'));
    const button = h.button();
    button.dispatchEvent(new h.browser.PointerEvent('pointerdown', { bubbles: true, button: 0 }));
    assert.equal(button.classList.contains('taxi-offline-hold--holding'), false, 'failed startup must remove input handlers');
    assert.equal(h.timers.size, 0, 'failed startup must not create timers after a later input event');
    await h.advance(2500);
    assert.equal(h.commands.length, commandCount, 'failed startup must remove its DOM handlers');
  });
}

test('Earth snapshots open an independent route panel and close it when switching screens', async t => {
  const h = await fixture(t);
  assert.ok(h.commands.some(command => command.includes('requestEarthState()')));
  h.bridge.events.emit('TaxiDriverEarthState', { available: true, status: 'ready' });
  h.view.settingsOpen = true; h.view.profileOpen = true; h.view.fleetOpen = true;
  h.hud.openEarth();
  assert.equal(h.view.earthOpen, true);
  assert.equal(h.view.settingsOpen || h.view.profileOpen || h.view.fleetOpen, false);
  assert.equal(earthCalls(h).at(-1).action, 'open');
  h.hud.toggleSettings();
  assert.equal(h.view.earthOpen, false);
  assert.ok(earthCalls(h).some(call => call.action === 'close'));
  h.bridge.events.emit('TaxiDriverEarthState', { available: true, status: 'ready' });
  assert.equal(h.view.earthOpen, false, 'late snapshots cannot reopen a closed panel');
});

test('Earth search is explicit, clears edited selections and keeps backend result indexes', async t => {
  const h = await fixture(t);
  const point = {name: 'Paris', detail: 'France', lat: 48.8, lon: 2.3};
  h.send({earth: {available: true, status: 'ready', mode: 'points', a: {query: 'Paris', selected: point}, b: {query: 'Rome', selected: point}, route: {status: 'ready', distanceM: 1234, durationS: 600}, canNavigate: true}});
  assert.equal(h.view.earth.available, true);
  h.hud.openEarth();
  h.hud.editEarth('a', 'New York');
  assert.equal(h.view.earth.a.selected, null);
  assert.equal(h.view.earth.route.status, 'idle');
  assert.equal(h.view.canPreviewEarth(), false);
  assert.equal(h.commands.some(command => /earthCommand\("search"/.test(command)), false);
  h.hud.searchEarth('a');
  assert.equal(earthCalls(h).at(-1).action, 'search');
  assert.equal(earthCalls(h).at(-1).args.field, 'a');
  assert.equal(earthCalls(h).at(-1).args.query, 'New York');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'points', a: {query: 'New York', results: Array.from({length: 10}, (_, i) => ({...point, name: `Place ${i}`}))}});
  assert.equal(h.view.earthResults('a').length, 8);
  h.hud.earthKeydown('a', {key: 'ArrowDown', preventDefault() {}});
  h.hud.earthKeydown('a', {key: 'ArrowDown', preventDefault() {}});
  h.hud.earthKeydown('a', {key: 'Enter', preventDefault() {}});
  assert.equal(earthCalls(h).at(-1).action, 'select');
  assert.equal(earthCalls(h).at(-1).args.field, 'a');
  assert.equal(earthCalls(h).at(-1).args.index, 2);
});

test('Earth supports both route origins, localized fallback and separate navigation targets', async t => {
  const h = await fixture(t, {rememberedLanguage: 'de'});
  const point = {name: 'Place', lat: 40, lon: 30};
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'vehicle', b: {selected: point}, canNavigate: true});
  assert.equal(h.view.t('earthTitle'), 'Earth routes');
  assert.equal(h.view.canPreviewEarth(), true);
  h.hud.previewEarth();
  assert.equal(earthCalls(h).at(-1).action, 'preview');
  h.hud.setEarthMode('points');
  assert.equal(h.view.canPreviewEarth(), false);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'points', a: {selected: point}, b: {selected: point}, canNavigate: true});
  h.hud.navigateEarth('a'); assert.equal(earthCalls(h).at(-1).args.target, 'a');
  h.hud.navigateEarth('b'); assert.equal(earthCalls(h).at(-1).args.target, 'b');
  assert.equal(h.commands.some(command => /acceptOffer|startMode|teleport/i.test(command)), false);
});

test('Earth preserves a newer draft against late snapshots and debounces only local edits', async t => {
  const h = await fixture(t);
  const point = {name: 'Old place', lat: 40, lon: 30};
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', a: {query: 'Old place', selected: point}, route: {status: 'ready'}});
  h.hud.openEarth();
  h.hud.editEarth('a', 'New'); h.hud.editEarth('a', 'New place');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', a: {query: 'Old place', selected: point}, route: {status: 'ready'}});
  assert.equal(h.view.earth.a.query, 'New place');
  assert.equal(h.view.earth.a.selected, null);
  assert.equal(h.view.earth.route.status, 'idle');
  await h.advance(250);
  const edits = h.commands.filter(command => /earthCommand\("edit"/.test(command));
  assert.equal(edits.length, 1);
  assert.match(edits[0], /"query":"New place"/);
  assert.equal(h.commands.some(command => /earthCommand\("search"/.test(command)), false);
});

test('Earth keyboard chooses the last result with ArrowUp and does not search unavailable Earth', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', a: {query: 'Place', results: [{name: 'A'}, {name: 'B'}, {name: 'C'}]}});
  h.hud.earthKeydown('a', {key: 'ArrowUp', preventDefault() {}});
  assert.equal(h.view.earthActive.a, 2);
  h.hud.earthKeydown('a', {key: 'Escape', preventDefault() {}});
  assert.equal(h.view.earthExpanded.a, false);
  assert.equal(h.view.earthActive.a, -1);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'disconnected', b: {query: 'Place'}});
  const before = h.commands.length;
  h.hud.earthKeydown('b', {key: 'Enter', preventDefault() {}});
  assert.equal(h.commands.length, before);
});

test('Earth normalizes empty Lua result objects without breaking combobox rendering', async t => {
  const h = await fixture(t);
  h.send({earth: {available: true, status: 'ready', a: {results: {}}, b: {results: {}}}});
  assert.deepEqual(h.view.earthResults('a'), []);
  assert.deepEqual(h.view.earthResults('b'), []);
  assert.equal(h.view.earth.route.from, null);
  assert.equal(h.view.earth.route.to, null);
});

test('Earth search trims its submitted draft so normalized backend results clear loading', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready'});
  h.hud.openEarth();
  h.hud.editEarth('b', ' Paris ');
  h.hud.searchEarth('b');
  assert.equal(h.view.earth.b.query, 'Paris');
  assert.match(h.commands.at(-1), /"query":"Paris"/);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', b: {query: 'Paris', searching: false, results: [{name: 'Paris', detail: 'France', lat: 48.8, lon: 2.3}]}});
  assert.equal(h.view.earth.b.searching, false);
  assert.equal(h.view.earthResults('b')[0].name, 'Paris');
});

const earthCalls = h => h.commands.flatMap(command => {
  const match = command.match(/earthCommand\("([^"]+)", (\{.*\})\)$/);
  return match ? [{action: match[1], args: JSON.parse(match[2])}] : [];
});

test('Earth owns its heartbeat and closes backend polling when an open model is destroyed', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready'});
  h.hud.openEarth();
  const owner = earthCalls(h).find(call => call.action === 'open').args.owner;
  assert.equal(typeof owner, 'string'); assert.ok(owner.length > 0);
  await h.advance(2500);
  assert.equal(earthCalls(h).filter(call => call.action === 'heartbeat' && call.args.owner === owner).length, 1);
  h.hud.editEarth('a', 'Pending');
  h.destroy();
  assert.equal(earthCalls(h).filter(call => call.action === 'close' && call.args.owner === owner).length, 1);
  const count = earthCalls(h).length;
  await h.advance(5000);
  assert.equal(earthCalls(h).length, count);
});

test('Earth instances use distinct owners and a foreign snapshot retires local work without closing the new owner', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready'});
  h.hud.openEarth();
  const ownerA = earthCalls(h).at(-1).args.owner;
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: ownerA});
  h.hud.editEarth('a', 'Pending');
  const other = h.recreate();
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready'});
  other.hud.openEarth();
  const ownerB = earthCalls(h).at(-1).args.owner;
  assert.notEqual(ownerA, ownerB);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: ownerB});
  assert.equal(h.view.earthOpen, false);
  assert.equal(other.view.earthOpen, true);
  h.destroy();
  await h.advance(2500);
  assert.equal(earthCalls(h).filter(call => ['edit', 'close', 'heartbeat'].includes(call.action) && call.args.owner === ownerA).length, 0);
  other.hud.closeEarth();
  const count = earthCalls(h).length;
  await h.advance(5000);
  assert.equal(earthCalls(h).length, count);
});

test('destroying a model that never opened Earth does not send close', async t => {
  const h = await fixture(t);
  h.destroy();
  assert.equal(earthCalls(h).some(call => call.action === 'close'), false);
});

test('Earth random limit remains independent of taxi settings and clamps to 1–600 km', async t => {
  const h = await fixture(t);
  assert.equal(h.view.earth.maxRandomKm, 50);
  h.hud.setEarthRandomLimit(900);
  assert.equal(h.view.earth.maxRandomKm, 600);
  assert.equal(earthCalls(h).at(-1).action, 'setRandomLimit');
  assert.equal(earthCalls(h).at(-1).args.maxRandomKm, 600);
  h.hud.setEarthRandomLimit(-2);
  assert.equal(h.view.earth.maxRandomKm, 1);
  assert.equal(earthCalls(h).at(-1).args.maxRandomKm, 1);
  assert.equal('maxRandomKm' in h.view.settings, false);
});

test('Earth teleports only by its explicit A button in points mode', async t => {
  const h = await fixture(t);
  const point = {name: 'Paris', lat: 48.8, lon: 2.3};
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'points', a: {selected: point}, canNavigate: true});
  assert.equal(earthCalls(h).some(call => call.action === 'teleport'), false);
  h.hud.teleportEarthA();
  assert.equal(earthCalls(h).at(-1).action, 'teleport');
  assert.equal(earthCalls(h).at(-1).args.target, 'a');
  h.hud.setEarthMode('vehicle');
  const before = earthCalls(h).length;
  h.hud.teleportEarthA();
  assert.equal(earthCalls(h).length, before);
});

test('Earth random preview works without B and accepts its generated destination over an old draft', async t => {
  const h = await fixture(t);
  const point = {name: 'Paris', lat: 48.8, lon: 2.3};
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'vehicle'});
  h.hud.editEarth('b', 'Abandoned draft');
  assert.equal(h.view.canRandomEarth(), true);
  h.hud.randomEarth();
  assert.equal(earthCalls(h).at(-1).action, 'randomPreview');
  assert.equal(h.view.earth.route.status, 'pending');
  assert.equal(h.view.canRandomEarth(), false);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'vehicle', b: {query: 'Paris', selected: point}, route: {status: 'ready', distanceM: 1000}, randomAttempt: 2});
  assert.equal(h.view.earth.b.selected.name, 'Paris');
  assert.equal(h.view.earth.route.status, 'ready');
  h.hud.setEarthMode('points');
  assert.equal(h.view.canRandomEarth(), false, 'points mode needs selected A');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', mode: 'points', a: {selected: point}});
  assert.equal(h.view.canRandomEarth(), true);
  await h.advance(250);
  assert.equal(earthCalls(h).some(call => call.action === 'edit'), false, 'old B draft timer was cancelled');
});

const typingCalls = h => h.commands.filter(command => command.includes('setCEFTyping('));
const addTypingField = (h, tag = 'input', type = 'text', outside = false) => {
  const element = h.browser.document.createElement(tag);
  if (tag === 'input') element.type = type;
  if (tag === 'div') { element.setAttribute('contenteditable', 'true'); element.tabIndex = 0; }
  (outside ? h.browser.document.body : h.host).append(element);
  return element;
};

test('native editable focus locks game bindings once and keeps the lock across HUD fields', async t => {
  const h = await fixture(t);
  const first = addTypingField(h), second = addTypingField(h, 'textarea');
  first.focus(); await h.flush();
  assert.deepEqual(typingCalls(h), ['if setCEFTyping then setCEFTyping(true) end']);
  second.focus(); await h.flush();
  assert.equal(typingCalls(h).length, 1);
  second.blur(); await h.flush();
  assert.deepEqual(typingCalls(h), ['if setCEFTyping then setCEFTyping(true) end', 'if setCEFTyping then setCEFTyping(false) end']);
});

for (const event of ['windowBlur', 'hidden', 'engineLost', 'destroy']) {
  test(`native typing releases on ${event}`, async t => {
    const h = await fixture(t);
    const field = addTypingField(h, 'div'); field.focus(); await h.flush();
    if (event === 'windowBlur') h.browser.dispatchEvent(new h.browser.Event('blur'));
    if (event === 'hidden') { h.browser.document.hidden = true; h.browser.document.dispatchEvent(new h.browser.Event('visibilitychange')); }
    if (event === 'engineLost') h.bridge.events.emit('CEFTypingLostFocus');
    if (event === 'destroy') h.destroy();
    await h.flush();
    assert.equal(typingCalls(h).at(-1), 'if setCEFTyping then setCEFTyping(false) end', event);
    if (event === 'engineLost') assert.notEqual(h.browser.document.activeElement, field);
    h.destroy();
  });
}

test('native typing hands focus to other game editors without sending false', async t => {
  const h = await fixture(t);
  addTypingField(h).focus(); await h.flush();
  addTypingField(h, 'input', 'text', true).focus(); await h.flush();
  h.destroy();
  assert.deepEqual(typingCalls(h), ['if setCEFTyping then setCEFTyping(true) end']);
});

test('nontext controls never acquire the native typing lock', async t => {
  const h = await fixture(t);
  for (const type of ['checkbox', 'range', 'button', 'radio', 'file', 'submit']) { addTypingField(h, 'input', type).focus(); await h.flush(); }
  assert.deepEqual(typingCalls(h), []);
});

test('Connected Phone never acquires the native typing lock', async t => {
  const external = await fixture(t, {external: true});
  const field = addTypingField(external); field.focus(); await external.flush(); field.blur();
  external.destroy();
  assert.deepEqual(typingCalls(external), []);
});

test('native editable keys stay in the HUD while Vue field handlers still run', async t => {
  const h = await fixture(t);
  const field = addTypingField(h);
  let fieldEvents = 0, escapedEvents = 0;
  for (const type of ['keydown', 'keyup']) {
    field.addEventListener(type, () => fieldEvents++);
    h.browser.document.addEventListener(type, () => escapedEvents++);
    field.dispatchEvent(new h.browser.KeyboardEvent(type, {key: 'w', bubbles: true}));
  }
  assert.equal(fieldEvents, 2);
  assert.equal(escapedEvents, 0);
});

test('Earth opening waits for its owner acknowledgement before accepting a takeover snapshot', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: 'prior-owner'});
  h.hud.openEarth();
  const owner = earthCalls(h).at(-1).args.owner;
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: 'prior-owner'});
  assert.equal(h.view.earthOpen, true, 'queued state from the previous owner cannot close a newly opening panel');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner});
  assert.equal(h.view.earthOpen, true);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: 'next-owner'});
  assert.equal(h.view.earthOpen, false, 'a takeover after own acknowledgement retires this panel');
  assert.equal(earthCalls(h).some(call => call.action === 'close'), false);
});

test('Earth retires an expired owner lease and can reopen only on a new click', async t => {
  const h = await fixture(t);
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready'});
  h.hud.openEarth();
  const owner = earthCalls(h).at(-1).args.owner;
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner});
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: ''});
  assert.equal(h.view.earthOpen, false, 'expired lease closes the panel locally');
  const count = earthCalls(h).length;
  await h.advance(2500);
  assert.equal(earthCalls(h).length, count, 'expired lease stops heartbeat');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner});
  assert.equal(h.view.earthOpen, false, 'late own snapshot cannot reopen the panel');
  h.hud.openEarth();
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner: ''});
  assert.equal(h.view.earthOpen, true, 'queued empty owner is ignored while waiting for the new open acknowledgement');
  h.bridge.events.emit('TaxiDriverEarthState', {available: true, status: 'ready', owner});
  assert.equal(h.view.earthOpen, true);
});
