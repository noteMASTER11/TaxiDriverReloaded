import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';
import { startHarnessServer } from './server.mjs';

test('the shipped Connected Phone JavaScript remains readable for repository review', async () => {
  const bundle = await fs.readFile(new URL('../../ui/modules/apps/TaxiDriverHUD/external/hud.bundle.js', import.meta.url), 'utf8');
  const lines = bundle.split(/\r?\n/);
  assert(lines.length > 1000, 'ship a formatted bundle rather than minified JavaScript');
  assert(Math.max(...lines.map(line => line.length)) < 2000, 'bundle must not contain compressed code lines');
  assert.match(bundle, /hud-model\.js/, 'retain source-module labels for reviewers');
  assert(bundle.includes('function createHudModel('), 'preserve application function names');
});

test('the primary HUD font URLs return usable fonts from the installed BeamNG UI', async () => {
  const css = await fs.readFile(new URL('../../ui/modules/apps/TaxiDriverHUD/app.css', import.meta.url), 'utf8');
  const urls = Array.from(css.matchAll(/@font-face\s*\{[^}]*?src:\s*url\("([^"]+)"\)/g), match => match[1]);
  assert.equal(urls.length, 4);
  const { server } = await startHarnessServer(0);
  try {
    for (const url of urls) {
      const response = await fetch(`http://127.0.0.1:${server.address().port}${url}`);
      assert.equal(response.status, 200, url);
      const bytes = Buffer.from(await response.arrayBuffer());
      assert.equal(bytes.readUInt32BE(0), 0x00010000, `${url} must be TrueType`);
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
