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

## Experimental Earth branch

`earthRouting.lua` owns WGS84 selections, search history, route previews and the persisted random-distance limit in `/settings/TaxiDriver/earth_routes.json`. Random routes use at most four asynchronous OSRM attempts and accept only the returned road distance within the configured 1–600 km limit. Explicit A-to-B routes have no 600 km cap. The Start trip action creates a paid passenger order through normal acceptance, boarding, fare and completion, using road-snapped endpoints.

On an Earth level, the ordinary dispatcher automatically uses `earthCandidates.lua` and `earthDispatcher.lua`, never the finite local-map destination generator or XYZ route cache. Candidate discovery reads cached Earth map labels at zoom 12, prioritises towns and adds bounded radial fallback seeds. One world-route request runs at a time; short, medium and long destinations are mixed. Unlimited uses the configured random limit up to 600 km; otherwise the usual 25 km limit applies. Hard NoRoute/over-limit results are not repeated. Temporary loss of pose/ground readiness waits and recovers with bounded backoff.

`earthTripSupport.lua` keeps geographic stops authoritative over origin rebases and supplies the whole Earth GPS remaining distance and ETA. `navigationUi.lua` delegates geographic targets to Earth GPS and only draws nearby local markers. Boarding/arrival still require physical proximity and a stopped car. Earth AI Driver, dynamic multi-stop/route-changing events and follow-up offers are not enabled by this integration.

`earthAddresses.lua` enriches published cards independently: at most 24 queued lookups, one request every 3 seconds, 128 cached addresses for 10 minutes. Earth's `where` supplies an available road/place; it does not invent house numbers. Forward address searches retain the house/street text that Earth's geocoder actually returns.

`earthTransport.lua` opens a separate nonblocking request-only connection to the running Earth server. Read the endpoint from Earth's existing network module; do not mutate its singleton. Each connection has its own route/prefetch state. Send only `geocode`, `map_labels`, `where` or `route` (`download="off"`), never world `hello`, `pose` or anchor commands. Reuse Earth's fetcher and provider limits. Close the socket on completion, cancellation or timeout; do not leave a connection owning world state. The current Earth route handler still obtains elevation samples even with corridor download disabled.

The UI owns its Earth panel with a unique token, 2.5-second heartbeats and a 10-second backend lease. Destroy/unmount cancels only that owner's work. Ignore stale owners until the open acknowledgement; release the panel if confirmed ownership is lost. Gameplay settings can save the random limit without holding a panel lease.

Native editable fields use the game's `setCEFTyping` contract to suppress driving keybindings while typing. Release owned input capture on blur, hidden documents, removed fields and unmount; Connected Phone must not capture the game's keyboard.

For hot deployment, package the mod, unload only `taxiDriver_taxiDriver`, deactivate its archive with `core_modmanager`, replace the ZIP, activate it, clear changed TaxiDriver modules from `package.loaded`, reload the TaxiDriver extension and reload the UI. Do not reload the GE VM, level or vehicle for a UI/GE-only Earth change: keep the running Earth server and session. Retain the previous ZIP in `dist/backups` and never mount two TaxiDriver archives together. Reloading changed vehicle Lua is a separate operation.
