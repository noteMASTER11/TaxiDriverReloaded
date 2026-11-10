import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import { Window } from 'happy-dom';

const read = relative => fs.readFile(new URL(relative, import.meta.url), 'utf8');
const [fixtures, harness, bundle, dictionaries] = await Promise.all([
  read('./mock-env.js'), read('./harness.js'),
  read('../../ui/modules/apps/TaxiDriverHUD/external/hud.bundle.js'),
  read('../../ui/modules/apps/TaxiDriverHUD/locales.json'),
]);

async function openPhone() {
  const window = new Window({url: 'http://localhost/tests/ui/harness.html?scenario=home&external=1'});
  window.document.body.innerHTML = '<main class="taxi-test-stage"><div id="taxi-hud-root"></div></main>';
  const errors = [];
  window.console.error = window.console.warn = (...args) => errors.push(args.map(String).join(' '));
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
  const subscriptions = new Map();
  const events = window.__taxiNativeBridge.events;
  const on = events.on, off = events.off;
  events.on = (name, callback) => {
    if (!subscriptions.has(name)) subscriptions.set(name, new Set());
    subscriptions.get(name).add(callback);
    on(name, callback);
  };
  events.off = (name, callback) => {
    subscriptions.get(name)?.delete(callback);
    off(name, callback);
  };
  const pagehideListeners = new Set();
  const add = window.addEventListener.bind(window), remove = window.removeEventListener.bind(window);
  window.addEventListener = (name, callback, options) => {
    if (name === 'pagehide') pagehideListeners.add(callback);
    add(name, callback, options);
  };
  window.removeEventListener = (name, callback, options) => {
    if (name === 'pagehide') pagehideListeners.delete(callback);
    remove(name, callback, options);
  };
  window.eval(bundle);
  window.eval(harness);
  for (let attempt = 0; attempt < 100 && !window.__taxiHarnessReady; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  return {window, errors, subscriptions, pagehideListeners};
}

async function closePhone({window}) {
  window.__taxiHudHandle?.unmount();
  await window.happyDOM.cancelAsync();
  window.close();
}

function transition(window, type, persisted) {
  // happy-dom currently aliases PageTransitionEvent to Event, which drops persisted.
  const event = new window.Event(type);
  Object.defineProperty(event, 'persisted', {value: persisted});
  window.dispatchEvent(event);
}

test('Connected Phone retains its live HUD through BFCache and unmounts on the later real exit', async () => {
  const phone = await openPhone();
  const {window, errors, subscriptions, pagehideListeners} = phone;
  try {
    assert.equal(window.__taxiHarnessReady, true);
    const shell = window.document.querySelector('.taxi-shell');
    assert(shell);
    const model = window.__taxiHudHandle.getModel();
    model.view.settingsOpen = true;
    await new Promise(resolve => setTimeout(resolve, 0));
    for (let visit = 0; visit < 2; visit += 1) {
      transition(window, 'pagehide', true);
      transition(window, 'pageshow', true);
      assert.ok(window.document.querySelector('.taxi-shell') === shell, 'cached page retains its rendered HUD');
      assert.ok(window.__taxiHudHandle.getModel() === model);
      assert.equal(model.view.settingsOpen, true, 'cached page retains local UI state');
    }
    window.__taxiSetState({balance: 123.45});
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(model.view.state.balance, 123.45, 'restored HUD still receives game state');
    assert(window.document.querySelector('.taxi-settings'));
    transition(window, 'pagehide', false);
    assert.ok(!window.document.querySelector('taxi-driver-hud'), 'real exit unmounts the HUD');
    assert.equal([...subscriptions.values()].reduce((count, set) => count + set.size, 0), 0);
    assert.equal(pagehideListeners.size, 0, 'unmount removes its own page lifecycle listener');
    window.__taxiHudHandle.unmount();
    assert.deepEqual(errors, [], 'repeated unmount is silent');
  } finally {
    await closePhone(phone);
  }
});

test('explicit Connected Phone unmount removes lifecycle handlers and is idempotent', async () => {
  const phone = await openPhone();
  const {window, errors, subscriptions, pagehideListeners} = phone;
  try {
    assert.equal(window.__taxiHarnessReady, true);
    window.__taxiHudHandle.unmount();
    window.__taxiHudHandle.unmount();
    transition(window, 'pagehide', false);
    assert.ok(!window.document.querySelector('taxi-driver-hud'));
    assert.equal([...subscriptions.values()].reduce((count, set) => count + set.size, 0), 0);
    assert.equal(pagehideListeners.size, 0);
    assert.deepEqual(errors, []);
  } finally {
    await closePhone(phone);
  }
});
