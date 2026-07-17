# Changelog

## 3.0.0 Beta — Runtime, Connected Phone, and Diagnostics Overhaul

This prerelease contains every change made after `2.25.1`.

### Connected Phone performance and battery use

- Added three external-map performance presets:
  - **Eco:** up to 6 map frames per second, 0.5-second vehicle snapshots, and a 1× canvas pixel-ratio cap;
  - **Balanced:** up to 15 map frames per second and 0.25-second vehicle snapshots;
  - **Smooth:** up to 30 map frames per second and 0.125-second vehicle snapshots.
- Added independent **External map** and **Terrain layer** switches to Connected Phone settings. Disabling terrain also prevents terrain metadata from being rebuilt and transmitted.
- Replaced continuous mobile map repainting with motion-driven rendering. The canvas redraws only after meaningful position, heading, speed, route, or camera changes and stops drawing while its map view is not visible.
- Reduced repeated HUD traffic while a phone is connected by publishing revisioned field-level patches instead of complete state documents on every periodic update.
- Kept full authoritative snapshots for initial load, explicit resynchronization, settings/profile operations, and the in-game UI App when no phone is connected.
- Increased heartbeat tolerance from 3.5 to 8 seconds so mobile-browser timer throttling does not cause needless disconnect/reconnect cycles.
- Added cache revisions to the external bootstrap, HTML, styles, scripts, and localization requests so phones do not retain mixed assets from an older mod build.

### State synchronization and race-condition fixes

- Added a HUD epoch and monotonically increasing revision to every authoritative state stream.
- Added `baseRevision` validation for delta packets. Missing, delayed, duplicated, or out-of-order patches are rejected instead of being merged onto stale state.
- Added automatic full-state recovery through both in-game and external-client heartbeats when a revision gap is detected.
- Fixed the in-game UI App showing an offer screen while Connected Phone had already entered an active trip.
- Fixed the Connected Phone route being drawn once and then remaining frozen while the vehicle continued moving.
- Made Lua's active trip phase authoritative for external navigation. Hiding the in-game CEF layer or backgrounding a browser can no longer silently stop the live phone route.
- Added explicit external-view reporting for home, orders, trip, compact, fuel-route, settings, profile, fuel, and status screens.
- Protected recently changed settings from older periodic packets until Lua acknowledges the same normalized settings document.
- Fixed language, toggle, and other setting controls briefly changing and then reverting to their previous values.

### Vehicle configuration performance

- Removed TaxiDriver telemetry and cargo extensions from BeamNG's automatic Vehicle Lua extension directory.
- Telemetry now loads only while a TaxiDriver shift needs it and unloads when inactive. Physical cargo support follows the same lazy lifecycle.
- Added a Vehicle Config guard that suspends TaxiDriver vehicle scans, energy requests, telemetry, cargo work, HUD work, and the in-game Angular root before BeamNG rebuilds the vehicle VM.
- Added a 1.5-second settle window after parts/configuration changes before deferred vehicle-side work resumes.
- Added generation checks so late callbacks from a replaced vehicle VM cannot overwrite the stable current-vehicle state.
- Changed vehicle-history identity tracking to treat live part changes on the same BeamNG vehicle object as the same automobile.
- Prevented repeated vehicle-detail lookups, JSON writes, profile-row recreation, odometer jumps, and cargo/telemetry reloads during parts selection.
- Restored telemetry and active delivery mass lazily after the replacement vehicle VM becomes stable.

### Cheat Zone and diagnostics

- Added **Tank / battery level**, allowing the current vehicle's compatible energy storages to be set from 0% to 100%.
- Reused the exact BeamNG energy-storage bridge used by Realistic Mode: Realistic Mode supplies its fixed 5% fuel / 30% charge values, while the cheat supplies the player's selected percentage for both.
- Fixed the range control sending a stale Angular value by reading the actual HTML slider value at the moment **Set** is pressed.
- Updated **Set rating** to re-rate the driver's complete history rather than changing only the visible aggregate.
- Rating changes now update stored reviews, rating-history points, vehicle journal totals, the active/previous shift summaries, and the profile approximation consistently.
- Added **God Mode**, disabled by default. When enabled, resetting the current vehicle preserves the active trip and reapplies required delivery state after the VM settles.
- Added **Debug logging**, enabled by default, to Cheat Zone.
- Added structured `[TaxiDriver]` records for public operations, runtime phase changes, LAN lifecycle and map preparation, vehicle-config suspension, deferred vehicle work, and cheat actions.
- Warnings and errors remain visible even when verbose debug logging is disabled.

### Architecture and packaging

- Added `hudPublisher.lua` for full snapshots, compact patches, epochs, revisions, and resynchronization checks.
- Added `vehicleScanGuard.lua` for configuration-screen detection, lifecycle generations, and stable-VM settling.
- Added `logger.lua` for consistent structured diagnostics.
- Kept cargo-mass control in `delivery.lua` and vehicle telemetry lifecycle in `vehicleControl.lua`.
- Moved Vehicle Lua files from `lua/vehicle/extensions/auto/` to `lua/vehicle/extensions/` so they can only be loaded on demand.
- Extended the deterministic packaging check to require all new runtime modules, reject automatic TaxiDriver vehicle extensions, and verify the complete 40-entry archive.

### Testing

- Passed 258 responsive UI states across the in-game UI App, Connected Phone, eight localizations, compact/expanded layouts, interface scaling, and DPR 2 HiDPI rendering.
- Added 48 combinations covering map enablement, terrain enablement, Eco/Balanced/Smooth quality, God Mode, and debug logging.
- Added mobile-map frame-budget checks for all new rendering behavior, including idle-frame suppression and continued phone updates while the in-game CEF layer is hidden.
- Added revision-gap, delayed-patch, full-resynchronization, settings-race, and external-view heartbeat regression tests.
- Added a physical HTML range-input test that verifies a selected `73%` is transmitted as `cheatSetEnergyPercent(73)`.
- Added Lua combinatorics for structured logging, full-history rating changes, lazy vehicle extensions, and 500 deferred vehicle respawns/configuration events.
- Parsed all 19 Lua files successfully and retained the LuaJIT main-chunk local/size guards.

### Compatibility and Beta status

- Existing `2.25.1` settings, custom difficulty, profile, progress, shift, LAN identity, and vehicle-history files remain compatible.
- New Connected Phone performance options, God Mode, and debug logging are sanitized into the existing settings schema.
- Connected Phone sharing remains session-only and disabled whenever the UI App starts.
- This build is published as a GitHub prerelease while the new synchronization and lazy vehicle lifecycle receive wider hardware, browser, map, and mod-compatibility testing.
