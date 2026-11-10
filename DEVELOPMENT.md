# Development

This source build targets BeamNG.drive 0.40.5 and uses native Vue 3 UI Apps. The in-game entry point is `ui/modules/apps/TaxiDriverHUD/app.vue`; its `vue` and `@/bridge` imports resolve to the game's own runtime. It does not load AngularJS or the deprecated `createVueApp` helper.

## UI boundaries

- `hud-model.js`: reactive state, actions, sounds, map behavior and owned-resource cleanup. Both clients use this module.
- `hud-template.html`: all UI screens; precompiled during the build.
- `hud-render.js`: generated Vue render function, with no runtime template compiler on the game path.
- `hud-component.js`: mount, unmount, rendering and component-level startup reporting.
- `game-bridge.js`: the browser-to-game API boundary. Preserve receiver bindings and callback-expression semantics here.
- `external/entry.js`: Connected Phone entry; esbuild bundles the same component with pinned Vue 3.5.43 for browsers outside the game.

Lua owns gameplay state. Vue receives a full snapshot and revisioned patches, and requests a new snapshot after a gap. Reloading the UI must not reset the active order, wallet, settings or profile. The game and phone do not maintain separate gameplay stores.

Home difficulty presets are discrete settings commits: save them immediately, without the slider debounce, and preserve custom sliders and unrelated preferences. When browser assets change, update the shared resource revision in app.vue, external/index.html and external/external.js; CEF can retain an imported CSS URL through a UI reload.

## Build and test

Use Node.js 24 and pnpm. Dependencies are pinned in `pnpm-lock.yaml`.

```powershell
pnpm install --frozen-lockfile
pnpm test
pnpm test:game
.\scripts\package-mod.ps1
```

`pnpm test` rebuilds generated UI assets and runs Vue behavior, template, DOM-scenario and font checks. `pnpm test:game` requires the running game's MCP at `http://127.0.0.1:29292/mcp`; override with `BEAMNG_MCP_URL`. It compiles runtime Lua and executes mock-based regressions with separate globals and module caches. It does not drive the car or modify player settings.

`pnpm test:visual` additionally requires a Playwright browser. `TAXIDRIVER_BROWSER_CHANNEL=msedge` selects an installed Edge. Visual artifacts go to `tests/ui/artifacts`, which is ignored by Git.

Packaging rebuilds the UI and creates `dist/taxidriver.zip`. Build dependencies and tests are excluded from the mod archive. `-InstallDirectory <mods-directory>` also copies the archive and verifies its SHA256.

Distribute readable JavaScript for BeamNG Repo review. `build-ui.mjs` disables minification and keeps module labels and application function names in the bundled Connected Phone runtime. Vue still uses its production configuration. Original HUD modules and template are included in the archive, alongside Vue's license notices. `sounds-data.js` contains embedded MP3 data URLs, not encoded executable code. The asset tests check that the shipped bundle stays formatted.

## Game updates

After an update, run both test commands and verify UI recreation, simultaneous maps, pause behavior and AI Driver arrival/hand-back in the game. Compare the installed native AI contracts before changing route arguments: `path` follows a resolved graph sequence; `wpTargetList` performs new searches between targets.

For a new drive, the observer seeds only the first two nodes through `wpTargetList`. The first vehicle extension frame after native AI initialization appends the resolved suffix through `ai.setPath`, including the shared terminal node required by native `pathExtend`. Keep vehicle update ordering and map availability covered by regressions. Installing changed vehicle Lua requires reloading the player vehicle as well as GE Lua and the UI; a GE reload alone leaves the old vehicle extension alive.

Native 0.40 intersection indicators are part of `trafficActions`, called by `trafficPlan` in traffic mode. `driveUsingPath` uses manual mode and does not execute that branch. The stock-AI observer therefore derives junction turn signals from the assigned route; it leaves steering and braking with native AI. Signal setters must run only on state changes because each call resets BeamNG's flasher pulse. Release owned signals on pause, parking, failure and handoff; preserve hazard lights.

The native minimap API is experimental. `nativeMinimap.lua` is its compatibility boundary: the HUD must not change the stock map's singleton, camera, texture or callbacks. POIs are rendered with private utilities because native marker objects can close over the stock map's utilities. Changes to that native API belong in this adapter, not across the HUD.

Do not silently enable optional features after a settings change, retain listeners or timers after unmount, or issue vehicle commands after a vehicle-generation change. Add a regression test for each such failure before changing the implementation.
