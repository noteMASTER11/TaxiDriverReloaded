// Browser layout checks for the production Vue component. The regular test
// command covers behavior and rendering without requiring a browser process.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { startHarnessServer } from './server.mjs';

const artifacts = path.join(path.dirname(fileURLToPath(import.meta.url)), 'artifacts');
await fs.mkdir(artifacts, {recursive: true});
const {server, port} = await startHarnessServer(0);
let browser;
let checked = 0;
try {
  browser = await chromium.launch({headless: true, channel: process.env.TAXIDRIVER_BROWSER_CHANNEL || undefined});
  for (const external of [false, true]) {
    for (const [width, height] of [[320,568], [390,844], [520,900], [1024,768]]) {
      for (const scenario of ['home','orders','trip','settings','profile','fleet','fuel','magicFuel']) {
        const page = await browser.newPage({viewport: {width, height}});
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        try {
          const params = new URLSearchParams({scenario, width, height, external: external ? '1' : '0'});
          await page.goto(`http://127.0.0.1:${port}/?${params}`);
          await page.waitForFunction(() => window.__taxiHarnessReady);
          assert.deepEqual(errors, [], `${scenario}: runtime errors`);
          assert.equal(await page.locator('[data-runtime="vue3"]').count(), 1);
          const audit = await page.evaluate(() => window.__taxiVisualAudit());
          assert.deepEqual(audit.failures, [], `${scenario} ${width}x${height}: ${audit.failures.join(', ')}`);
          await page.screenshot({path: path.join(artifacts, `vue-${external ? 'web':'game'}-${scenario}-${width}x${height}.png`)});
          checked++;
        } finally { await page.close(); }
      }
    }
  }
  console.log(`TaxiDriver Vue: ${checked} browser layouts passed.`);
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
