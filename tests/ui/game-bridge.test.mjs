import assert from 'node:assert/strict';
import test from 'node:test';

test('game adapter preserves API receiver, callbacks and event lifecycle', async () => {
  const { createGameBridge } = await import('../../ui/modules/apps/TaxiDriverHUD/game-bridge.js');
  const calls = [], listeners = new Map();
  const api = { marker: 42, engineLua(code, cb) { calls.push([this.marker, code]); cb?.(7); },
    serializeToLua(value) { return JSON.stringify(value); } };
  const events = { on(name, cb) { listeners.set(name, cb); }, off(name) { listeners.delete(name); } };
  const bridge = createGameBridge({ api, events });
  let value;
  bridge.api.engineLua('return 1', data => { value = data; });
  assert.deepEqual(calls, [[42, 'return 1']]);
  assert.equal(value, 7);
  const listener = () => {};
  bridge.events.on('TaxiDriverHUDState', listener);
  assert.equal(listeners.size, 1);
  bridge.events.off('TaxiDriverHUDState', listener);
  assert.equal(listeners.size, 0);
  assert.equal(bridge.api.serializeToLua({ enabled: true }), '{"enabled":true}');
});

test('missing game API produces one explicit compatibility error', async () => {
  const { createGameBridge } = await import('../../ui/modules/apps/TaxiDriverHUD/game-bridge.js');
  assert.throws(() => createGameBridge({}), /game bridge/);
});
