# Changelog

## 3.4.1 RC — Native AI Driver and Dynamic Events

This release candidate contains every change made after `3.4.0-beta`. It replaces the overextended predictive driving experiment with a smaller adapter around BeamNG's native vehicle AI, adds traffic-aware protection for the player and hired Fleet vehicles, and expands Random Events and physical pickups.

> **Experimental AI notice:** AI Driver still depends on BeamNG road graphs, vehicle controllers and traffic behavior. It is intended as an entertaining assisted-driving mode rather than a guarantee of human-level autonomous driving on every map or mod vehicle.

### Native AI Driver architecture

- Replaced runtime use of the predictive free-space planner, local A* controller, aggressive bypass and custom reverse-recovery stack with BeamNG's native `ai.driveUsingPath`.
- Added an explicit player-vehicle identity guard. AI commands for a stale or NPC vehicle ID are rejected instead of moving, teleporting or despawning the player's car.
- Disabled native `setRecoverOnCrash` for the player vehicle so a stationary boarding sequence cannot be mistaken for a crashed traffic bot and safe-teleported.
- Kept native obstacle avoidance and lane following enabled during ordinary travel.
- Simplified AI presets and Custom settings to parameters the current native adapter actually uses: aggression, following time, minimum following distance, comfortable braking, traffic wait time, speed-limit compliance and lane discipline.
- Removed the obsolete decision-visualization setting from the UI.

### Legal routes and optional strict GPS

- Added directed-edge route planning for the final target road. It approaches the target edge in its legal travel direction and forbids an immediate reversal through the opposing lane.
- Added **Strict GPS route** as a setting independent of driving temperament. When enabled, AI receives the exact ordered road-node sequence currently displayed by BeamNG ground navigation.
- A recalculated GPS route immediately marks the AI route dirty and sends the updated shortest route to the vehicle.
- If a strict GPS path is temporarily unavailable, AI falls back to the legal autonomous graph route instead of turning itself off.
- Filtered coordinate-only ground-marker entries before Vehicle Lua serialization, preventing invalid `table: 0x...` waypoint IDs and native AI errors.
- Native `Route Done` is accepted only after checking physical distance to the active TaxiDriver target. A premature completion causes an immediate current-position replan, bounded to three retries.
- Final-target braking activates only after the vehicle is aligned with the target-side travel direction, preventing early stops on the opposite side of the road.

### Smooth traffic guard

- Added the lazy Vehicle Lua `taxiDriverStockAiObserver` around native driving.
- It observes map-tracked vehicles, maintains both a configurable time gap and minimum bumper gap, and derives a progressive speed cap from relative speed and comfortable stopping distance.
- Speed reduction is jerk-limited. Full emergency braking is reserved for critical time-to-collision or a physically excessive required deceleration.
- Added steering-arc prediction so vehicles crossing the swept path during a turn can be detected even when they are outside the straight lane corridor.
- Added target-aligned final-approach speed limiting without taking steering away from native AI.
- The observer owns the protected native `Route Done` hook only while an AI route is active and restores the original BeamNG hook when stopped.

### Passenger and cargo pickup flow

- Passenger orders can spawn BeamNG's unicycle character at the pickup point; cargo orders can spawn the small cardboard-box vehicle.
- Physical pickup is optional at runtime: missing content or an unsupported spawn falls back to the existing logical pickup without cancelling the order.
- A manual horn near the passenger starts walking toward the taxi.
- AI pickup now requires the taxi to be within seven metres and fully stopped.
- After stopping, AI emits two 600 ms horn pulses separated by 200 ms, waits for the passenger boarding event, and only then starts the destination route.
- The passenger is treated as a pickup obstacle. Hitting the passenger cancels the order, records the incident and applies a major fine.
- Reduced physical-passenger command frequency and excluded its prop from broad vehicle prediction scans to prevent pickup-area frame spikes.

### Configurable Random Events

- Added a dedicated Random Events settings expander.
- Every event has an independent enable switch and probability from 0% to 100%.
- Existing cancellation, destination-change, additional-stop, conditional-tip and fragile-cargo events now use the same configuration model.
- Added passenger no-show, VIP/quiet ride, forgotten-item return and temporary road-reroute events.
- Added an opt-in police inspection using BeamNG's native police and pursuit systems.
- Police content is selected from installed compatible configurations, preloaded asynchronously and activated 500–600 metres behind the player when the event begins.
- Police inspection is disabled by default. Enabling it requires a confirmation explaining that preparing a police vehicle can stall the start of a shift for 5–15 seconds.
- A completed native police stop can apply a small randomized administrative fine; unavailable police content fails safely without breaking the trip.

### Trip history and Fleet access

- Reviews are now expandable trip-history records containing outcome, fare, date, penalties and Random Event history.
- AI-assisted trips remain marked in review and profile history.
- The Fleet map button remains present with `F 0` when no driver is hired, allowing the hiring screen to be opened during an active personal shift.
- Fleet controls and driver-count labels remain CEF overlays above both personal and Fleet maps.

### Traffic-aware Fleet workers

- Hired drivers keep the low-cost native route worker introduced in 3.3.1 Beta.
- Each Fleet vehicle now runs a simplified instance of the traffic guard: smooth following, minimum-gap control and steering-arc collision prediction.
- Fleet observation runs every 200 ms with six trajectory samples, versus the player's 100 ms and twelve samples, limiting aggregate CPU cost.
- Fleet presets provide aggression, legal-speed behavior, following time and braking values without instantiating player-only target logic.
- Fleet route progress remains staggered at 250 ms, trims already passed nodes, rebuilds from the current road segment and abandons an unreachable job after bounded retries.
- Fleet traffic state is isolated per worker and never uses the player's position when selecting or repairing a route.

### Runtime modularization

- Extracted native minimap ownership, dynamic zoom, occlusion regions and restoration of BeamNG navigation settings into `navigationUi.lua`.
- Reduced `taxiDriver.lua` from 4,199 to 4,026 lines and from 179 to 166 main-chunk locals, restoring meaningful safety margin below LuaJIT's 200-local limit.
- Kept Vehicle Config suspension and lazy vehicle rescanning unchanged so editing parts does not reintroduce the previous long configuration stalls.
- Added dedicated `physicalPickup.lua`, `policeCheckEvent.lua` and `tripHistory.lua` services.

### Validation and compatibility

- Passed the Lua gameplay combinatorics suite, including native player routing, strict GPS, directed-edge approach, premature `Route Done`, traffic observation, physical pickup, Random Events, police lifecycle, Fleet economy/routing and 500 deferred respawns.
- Passed 357 responsive UI states across all supported locales, native/Connected Phone layouts and DPR 2 HiDPI rendering.
- Built a deterministic 59-entry release archive and verified the installed archive hash.
- Existing `3.4.0-beta` settings, driver progress, reviews, vehicle history, shift history, Fleet records and LAN identity remain compatible. Removed AI fields are safely ignored during settings migration.
- UI cache revision: `341-rc`.

## 3.4.0 Beta — Runtime Stability and Compact UI

This cumulative prerelease contains every change made after `3.3.1-beta`. It focuses on making the in-game UI less intrusive, reducing periodic runtime work, and preventing stale asynchronous callbacks or optional subsystem failures from destabilizing a game session.

### Three-stage in-game UI

- Added three explicit native UI App stages: the full phone, the existing compact route-map view, and a new translucent button-only stage.
- Replaced the old CSS-rotated minimization control with two clearly separated controls for regular minimize/expand and super-minimize/restore.
- The button-only stage hides the phone body and native minimap completely while retaining a small restoration control.
- Added an attention indicator for a new queued order or notification while the phone is collapsed. Incoming events no longer force the interface open.
- Every new UI App session starts in the full interface. Collapse state is intentionally not persisted.
- Kept the external Connected Phone interface independent from the native three-stage collapse behavior.
- Fixed the Vehicles profile tab sort selector by replacing the clipped native `<select>` popup with a layered in-app menu that remains above vehicle cards.

### Lua architecture and fault isolation

- Reduced the main `taxiDriver.lua` chunk to 174 top-level locals, leaving additional safety margin below LuaJIT's 200-local limit.
- Extracted fare/ETA/phase rules, offer-type planning, guarded vehicle-bridge work, runtime fault boundaries, and optional LAN loading into focused modules.
- Added per-subsystem runtime boundaries around vehicle history, shift validation/restoration, Fleet updates, dashboard energy, LAN, active gameplay, HUD publication, and teardown work.
- A failure in an optional or periodic subsystem is logged, temporarily circuit-broken, and no longer aborts all remaining work in that game tick.
- Mission and extension teardown now execute independent cleanup operations so one failed cleanup cannot prevent persistence, AI shutdown, LAN shutdown, or navigation restoration.
- Removed the unused `onTelemetryVehicleReset` entry point after verifying that Vehicle Config suspension is owned by `vehicleScanGuard`, `onUiChangedState`, and the normal vehicle spawn/reset lifecycle.

### Safe vehicle callbacks and fuel control

- Added a guarded wrapper for asynchronous `core_vehicleBridge` reads and writes.
- Every callback captures the selected vehicle ID and vehicle-scan generation, re-resolves the live object, and rejects responses from a destroyed or replaced vehicle VM.
- Callback failures are contained and logged instead of escaping through BeamNG's vehicle bridge.
- Dashboard energy, realistic refueling, magic-station routing, cheat fuel/charge assignment, and shift fuel restoration now use the guarded path.
- The cheat fuel/charge slider and Realistic Mode initialization share the same proven `setEnergyStorageEnergy` implementation.
- Opening Vehicle Config or receiving a relevant vehicle lifecycle event invalidates outstanding energy requests and clears their pending flags before lazy scanning resumes.
- AI route-complete and recovery callbacks now validate that the active vehicle still exists before invoking the controller.

### HUD, LAN, and road-network performance

- Periodic HUD updates now publish revisioned partial patches instead of rebuilding and retransmitting complete authoritative snapshots.
- Heavy order, shift-history, Fleet, garage, and settings collections are rebuilt only for explicit full updates or when their owning subsystem reports a real change.
- Fixed Fleet HUD dirty-state consumption so a collection refresh is published once instead of remaining dirty forever or being lost between periodic frames.
- Moved Connected Phone behind a lazy optional adapter. Missing LAN/socket support can no longer prevent the core taxi extension from loading.
- LAN method failures are contained and reported through status data instead of propagating into gameplay.
- Road-network serialization now runs as a coroutine and yields every 500 examined edges, preventing a large map from being synchronously scanned in one frame.
- Road chunks are published only after the level-specific background build completes and stale builds are discarded after a level or terrain-setting change.
- `lan.json` persistence is protected against filesystem write failures.
- Connected Phone is stopped at mission shutdown and safely restarted for the next mission when sharing remains enabled.

### AI safety timing and lifecycle

- Split collision-supervisor and exact-approach raycasting into independent fixed-rate 50 ms clocks so the two controllers no longer consume the same timer.
- Removed the frame-rate-dependent “scan every frame while braking” path; braking envelopes now advance using the fixed safety step.
- Reused one nearby-object snapshot for the directional fan and curved predicted trajectory instead of enumerating scene vehicles twice per safety pass.
- Stationary forward/reverse preflight rays are calculated only when the vehicle has actual movement intent and share the same nearby-object snapshot.
- Replaced the permanent `guihooks.trigger` modification with a protected route observer installed only while TaxiDriver watches an active native-AI route. The original trigger is restored when route watching stops.

### Logging, lifecycle, and Connected Phone shutdown

- Extended operation logging now filters reset events from unrelated traffic vehicles while preserving player and active TaxiDriver vehicle events.
- Native and external HUD heartbeat timers stop on early page shutdown, Angular destruction, and mission teardown rather than waiting for late failed callbacks.
- Back/forward-cache page transitions remain supported and do not permanently disable a restored Connected Phone page.

### Localization

- Incorporated a second native-speaker Simplified Chinese revision by replacing only the translator-provided values for existing `zh-CN` keys.
- Added localized labels for button-only collapse and interface restoration in every supported language.
- English and Simplified Chinese retain identical key coverage.

### Validation and compatibility

- Added regression coverage for stale vehicle generations, isolated callback failures, runtime cleanup continuation, lazy LAN loading, chunked road export, partial HUD publication, logger filtering, fixed-rate raycasting, and early heartbeat shutdown.
- Passed the Lua gameplay combinatorics suite, including Fleet lifecycle, AI recovery, vehicle powertrain, refueling, shift persistence, and 500 deferred respawns.
- Passed 343 responsive UI states across supported locales, HiDPI rendering, native UI, and Connected Phone layouts.
- Passed the live LAN probe for subnet HTTP access, loopback proxying, WebSocket Upgrade, and bidirectional traffic.
- Existing `3.3.1-beta` settings, driver progress, reviews, vehicle history, shift history, Fleet records, and LAN identity remain compatible.
- UI cache revision: `340-beta`.

## 3.3.1 Beta — Lightweight Fleet Routing

This focused prerelease separates hired Fleet drivers from the experimental predictive AI Driver used by the player's vehicle.

### Fleet worker architecture

- Replaced the full predictive/spatial AI supervisor in every hired Fleet vehicle with a lightweight worker built on BeamNG's native `ai.driveUsingPath` route following.
- Kept the player's optional AI Driver unchanged: its predictive target approach, spatial sensing, collision supervisor, visualization, and recovery logic remain available only to the actively controlled vehicle.
- Removed per-worker scene-wide vehicle scans, surface ray fans, spatial-graph searches, gearbox overrides, and predictive recovery passes. The player's position is no longer used when selecting or repairing a Fleet route.
- Preserved hired vehicles as persistent world objects, including purple map markers, nearby world labels, Fleet monitoring, job accounting, wages, and owner-profit statistics.
- Fleet driving presets now configure the native driver's aggression and speed-limit behavior without instantiating the heavier player-AI stack.

### Route progress and recovery

- Fleet workers monitor progress every 250 ms, staggered across four 62.5 ms phases to avoid updating every hired vehicle on the same simulation tick.
- A failed route is rebuilt from the worker's current road segment. Already passed road nodes are removed so a vehicle does not turn around to revisit the beginning of its old path.
- Native `Route Done` is accepted as arrival only inside a 22-metre target radius; otherwise the worker immediately requests a corrected path from its current position.
- Recovery is deliberately bounded to three replans and a minimum 45-second no-progress window. An unreachable job is abandoned safely after the retry budget and replaced after a short rest instead of leaving the vehicle permanently blocked or consuming CPU indefinitely.
- Vehicle speed is read directly from the worker's own tracked map object; the manager no longer performs broad traffic-state work on behalf of every Fleet driver.

### Validation and compatibility

- Added Lua combinatorics for native Fleet route dispatch, current-segment replanning, passed-node trimming, bounded stuck recovery, and clean failure hand-off.
- Re-ran the Fleet economy/lifecycle, AI logging, adaptive bypass, trajectory-ray, powertrain, gameplay-mode, and 500 deferred-respawn regression suites.
- Existing `3.3.0-beta` settings, progression, Fleet records, vehicle history, and shift history remain compatible.
- UI cache revision: `331-beta`.

## 3.3.0 Beta — Predictive Routing and Spatial AI

This cumulative prerelease contains every change made after `3.2.0-beta`, including the Connected Phone reliability work first published as `3.2.1-beta`.

> **Experimental AI notice:** AI Driver remains a gameplay experiment around BeamNG's built-in vehicle AI. The predictive planner and spatial supervisor make target approaches and recovery more deliberate, but unusual map graphs, vehicle controllers, traffic layouts, and community content can still produce imperfect decisions. The player can take control at any time.

### Predictive target routing

- Added a predictive access-route model for passenger, cargo, stop, and refueling triggers. It begins planning before the final entrance instead of waiting for native AI to report `Route Done` beside the target.
- Samples every drivable road edge near the physical target, projects the target onto each edge, and asks BeamNG's graph for candidate paths from both nearby start nodes to both access-edge endpoints.
- Rejects graph prefixes that initially move backwards along the active route, jump to an unrelated parallel road, or exceed the early cross-track envelope.
- Ranks complete routes by graph-prefix length plus the collision-checked local suffix. Clearance and local-path quality break only near-equal route costs, preventing a visually attractive detour from beating the shortest feasible entrance.
- Densifies selected graph polylines to at most four metres between controller waypoints and removes the first graph-centre point when it would demand an immediate full-lock lateral turn.
- Verifies final arrival against the physical trigger, uses a sub-metre completion radius, and gives the exact-approach controller a path-length-derived timeout instead of a fixed final-approach window.
- Added early graph planning at 75 metres with retry and failure cooldowns so entrances are selected while the vehicle can still turn into them.

### Vehicle-aligned spatial perception

- Replaced narrow road-lane-only recovery sensing with complete 180° forward and reverse sensor fans sampled every 10 degrees.
- Aligns every ray with the vehicle's forward/left/up basis, including pitch and roll, so slopes, descents, banked roads, and serpentine sections are measured relative to the car instead of the world horizon.
- Evaluates the full vehicle width with five parallel static probes, including both body edges plus a safety margin. Thin chargers, bollards, fences, barriers, and other edge contacts can no longer pass through a single centre ray.
- Merges BeamNG map objects with all live scene vehicles and temporarily enables tracking for nearby parked vehicles that BeamNG normally removes from `map.objects`.
- Uses oriented vehicle dimensions and projected traffic motion when validating a candidate corridor.
- Samples surface height, longitudinal slope, cross-slope, and step height. Traversable kerbs and pavements can participate in a recovery path when the vehicle geometry can climb them; unsafe ledges and inclines are rejected.
- Reassesses the strategic space model every 330 ms, approximately a human reaction interval, while drawing the cached result every render frame.

### Local planning, reverse escape, and collision safety

- Added a local spatial graph with seven distance rings and 24 angular samples. A bounded A* search can construct a multi-segment route around geometry when a single smooth left/right corridor is insufficient.
- Preserved the smooth minimum-offset bypass as the preferred simple solution and falls back to the spatial graph only when it produces the better feasible path.
- Expanded rear-space evaluation and reverse telemetry. A blocked vehicle can select a collision-checked 3–6 metre escape, rescan the rear trajectory while moving, stop, and replan forward.
- Centralized conversion between geometric travel angle and BeamNG steering input. This fixes forward and reverse recovery turning to the opposite side from the selected green path.
- Curved safety trajectories now cover steering arcs as well as straight motion and apply progressive comfortable braking before the emergency threshold.
- Added rapid static-contact recovery: repeated contact with nearby untracked geometry starts replanning after 1.5 seconds instead of waiting for the normal 15-second stuck timer.
- Fixed the safety brake releasing itself through TaxiDriver's own input override.

### AI decision visualization and diagnostics

- Added an independent **Visualize AI decisions** toggle to AI Driver settings; it is persisted and disabled by default.
- World rendering distinguishes free/blocked sensor rays, evaluated candidates, surface samples, spatial-graph nodes, selected waypoints, and the current planner reason.
- Expanded streaming AI journals with waypoint best-distance/no-progress fields and reverse remaining distance, steering, fan clearance, trajectory clearance, and ray count.
- Added structured planner records for strategy, route/access nodes, graph and local lengths, candidate counts, score, clearance, target error, and timeout.

### Queued-order fail-safe

- Added an explicit close button to a proposed next-order modal. It dismisses that exact order and removes it from the active queue.
- Moved next-offer expiry into a dedicated Lua guard driven by real time and independent of the trip-update phase.
- Invalid, stale, negative, or overlong timers are clamped and closed safely, including while Vehicle Config temporarily suspends normal gameplay work.
- Added a browser-side monotonic deadline that stale HUD packets cannot extend. The modal closes locally and notifies Lua even if no newer state packet arrives.
- Added localized dismissal text in all nine interface languages.

### Connected Phone reliability since 3.2.0

- Added ranked private-IPv4 discovery across BeamNG adapter data, native-server results, Windows route-selected sockets, Winsock hostname resolution, and a previously confirmed address.
- Added bind validation, physical-adapter preference, virtual/VPN adapter penalties, structured selection diagnostics, and clean `lan.json` creation only after a usable endpoint is confirmed.
- Replaced an empty QR placeholder with an actionable localized server-unavailable state.
- Restored a bounded non-blocking LAN-to-loopback byte proxy when BeamNG creates its External UI listener only on `127.0.0.1`; native all-interface listening remains preferred when reachable.
- The transparent fallback carries both static HTTP assets and the `bng-ext-app-v1` WebSocket without creating a second gameplay state.
- Added a live phone simulator that reads a fresh `lan.json`, loads every external asset over the selected LAN address, performs the WebSocket handshake, sends a real heartbeat, and waits for `TaxiDriverHUDState`.
- Incorporated 156 native-speaker Simplified Chinese corrections while preserving newer keys.

### Validation and compatibility

- Expanded Lua combinatorics for route-reference alignment, graph candidate ordering, 180° sensor coverage, slope-aware rays, vehicle-footprint probes, parked vehicles, steering direction, reverse escape, static-contact recovery, next-offer expiry, and 500 deferred vehicle respawns.
- Verified **343 responsive UI states** across the in-game UI App, Connected Phone, all nine locales, compact/full layouts, and DPR 2 HiDPI rendering.
- Passed LAN HTTP/WebSocket transport tests and deterministic **49-entry** package validation.
- Existing 3.2.0/3.2.1 Beta settings, profile, progression, fleet, vehicle history, and shift history remain compatible.
- UI cache revision: `330-beta`.

## 3.2.1 Beta — Connected Phone Reliability

This patch contains every change made after `3.2.0-beta`.

### Connected Phone networking

- Replaced the loopback proxy path with BeamNG's native all-interface External UI listener.
- Added ranked IPv4 discovery from BeamNG adapter data, the native server result, the Windows route-selected socket, Winsock hostname resolution, and a previously confirmed address.
- Added RFC1918/CGNAT validation, real bind checks, physical-adapter preference, and penalties for common VPN, Hyper-V, VirtualBox, VMware, tunnel, Bluetooth, and other virtual interfaces.
- Added a Windows 10/11 fallback for systems where BeamNG reports only `127.0.0.1`: LuaSocket resolves the computer hostname through Winsock and evaluates every returned IPv4.
- Persisted `lan.json` only after a usable address and server have been confirmed.
- Added structured `native_server_started`, `adapter_discovery`, `hostname_discovery`, `route_discovery`, `address_candidate`, and `address_selected` diagnostics.
- Replaced the empty white QR square on failed startup with a localized **Local server unavailable** state and the underlying diagnostic message.
- Confirmed clean discovery with no pre-existing `lan.json`: `192.168.93.143` was selected over the Hyper-V address `172.25.192.1`, and the phone connected successfully.

### Localization and documentation

- Incorporated 156 native-speaker corrections to the Simplified Chinese interface while preserving keys introduced after the contributed locale revision.
- Added a plain-language BeamNG Repository description covering supported gameplay modes, physical cargo mass, shifts, AI driving, fleet operations, refueling, persistence, and diagnostics.
- Updated the runtime documentation for native LAN listening and the dedicated `networkAddress.lua` selector.

### Validation and compatibility

- Passed LAN address-selection combinatorics, Lua syntax verification, and HTTP/WebSocket subnet transport checks.
- Verified 343 responsive UI states across the in-game UI App, Connected Phone, all nine locales, and DPR 2 HiDPI rendering.
- Passed deterministic 48-entry package validation.
- Existing 3.2.0 Beta settings, progression, fleet, vehicle, and shift data remain compatible. UI cache revision: `321-beta`.

## 3.2.0 Beta — Fleet Operations

This prerelease contains every change made after `3.1.1-rc`.

> **Experimental systems notice:** fleet workers reuse TaxiDriver's experimental AI-driver supervisor rather than BeamNG's stock traffic behavior. This makes their work visible and configurable, but they can still hesitate, choose imperfect paths, or require intervention on unusual maps, junctions, vehicles, and traffic layouts.

### Player-owned taxi fleet

- Added **My Fleet** to the start screen, allowing the player to operate as both a driver and a fleet owner.
- Added two hiring paths: spawn a separate vehicle from the garage or recruit an existing traffic vehicle from the current map.
- Recruited traffic vehicles are removed from the ordinary traffic despawn pool for the duration of employment and restored when dismissed where possible.
- Every hired vehicle receives an independent worker service and the same supervised route-following foundation used by the player's AI Driver; workers do not fall back to unsupervised stock traffic AI.
- Fleet drivers independently choose passenger or cargo work, navigate through pickup and destination phases, complete jobs, rest, and request a new assignment.
- Added session hiring fees, wages charged every ten minutes, configurable owner revenue share, insufficient-funds suspension, and a maximum active-driver limit.
- Added persistent fleet totals for jobs, gross revenue, wages, hiring costs, and the player's net fleet profit in `/settings/TaxiDriver/fleet.json`.
- Added separate **Careful**, **Standard**, and **Fast** worker presets. Fleet AI settings remain intentionally simpler and independent from the player's detailed AI Driver configuration.
- Added toggles for passenger and cargo assignments plus configurable fleet economics in a dedicated **Fleet** settings section.
- Hired workers are safely released when the gameplay session ends; persistent statistics remain available between sessions.

### Fleet monitoring and map integration

- Added a dedicated fleet screen with a player-centered live map, aggregate statistics, active-driver cards, route phase, speed and remaining-distance information, employment source, and per-driver controls.
- The fleet screen remains available during an active passenger, cargo, or refueling route through a purple map overlay button. Closing it returns to the exact previous trip state.
- Added purple fleet markers to both the native in-game minimap and the Connected Phone canvas map.
- Added localized in-world labels for owned taxis showing the driver identity and current activity when they are near the player.
- Added a **World label distance** slider from 50 to 1,000 metres, with a 400-metre default, so players can balance visibility and rendering cost.
- Added translations for fleet screens, settings, statuses, actions, validation messages, and world labels in all nine supported languages.
- Added a dedicated native-map occlusion region for the **Active drivers** overlay so road rendering can no longer cover its status label.
- Kept fleet map publishing active on Connected Phone even when the player has no personal route, without enabling the native minimap outside an explicitly opened fleet view.

### AI diagnostics

- Added an independent **AI trip logger** switch to AI Driver settings; it remains disabled by default.
- While enabled, every manual AI-control session writes a crash-readable JSON Lines journal named `taxidriver_ailog_<timestamp>.jsonl` in the BeamNG user `current` directory.
- Logs are written continuously from AI activation until manual deactivation or session shutdown instead of being generated only at the end.
- Added one-second navigation snapshots with route progress, physical target distance, cross-track error, controller mode, lead vehicle, traffic signal, speed caps, recovery state, powertrain inputs, gearbox state, and damage.
- Added structured events for route changes, target changes, lead acquisition and release, traffic-signal transitions, recovery attempts, collision-safety braking, ignition changes, gearbox drift, gear hunting, and damage increases.
- Added a final session summary with duration, route starts, recoveries, safety interventions, gear changes, damage delta, and minimum route/target distances.

### AI Driver reliability pass

- Added route-segment progress tracking so completion and recovery decisions can use remaining graph distance instead of relying only on straight-line distance to the trigger.
- Added curve and junction look-ahead speed caps for earlier, smoother braking before sharp route changes.
- Hardened lead-vehicle detection with temporal confirmation and collision-ray validation, reducing false following targets and premature lane changes.
- Improved signal tracking and queue release diagnostics, including explicit acquisition, phase changes, disappearance, and green-release timing.
- Added a preflight readiness phase that waits for ignition, gearbox, and controller state before handing the route to native AI.
- Improved recovery from repeated failure loops: equivalent stuck states are detected, escalated, and can use a short controlled forward creep or a rescanned reverse escape before replanning.
- Expanded reverse recovery telemetry with rear-clearance planning, steering choice, travelled distance, timeout, and obstruction reasons.
- Preserved collision-safety braking during curved trajectories and exposed its live observation to the GE supervisor for better lead validation.

### Validation and compatibility

- Expanded Lua combinatorics for fleet presets, passenger/cargo combinations, garage and traffic hiring, wages, owner share, insufficient funds, worker lifecycle, persistence sanitization, world-label distance boundaries, and revised AI recovery states.
- Expanded responsive UI coverage with fleet screens during idle and active trips, Fleet settings, native/Web maps, all nine locales, compact/full layouts, and DPR 2 HiDPI rendering.
- Verified **343 responsive UI states**, the LAN bridge self-test, Lua gameplay combinatorics, and deterministic package validation.
- The release archive contains **47 verified entries** and includes the new fleet manager, fleet worker, and AI journal modules.
- Existing settings, progression, vehicle history, and shift history remain compatible. The release uses cache revision `320-beta` so in-game and external clients cannot mix older UI assets with this build.

## 3.1.1 RC — Experimental AI Driver Tuning

This release candidate contains every change made after `3.1.0-beta`.

> **Experimental AI notice:** the AI driver remains a little clumsy and is provided mainly for fun. It is an experiment built around BeamNG's native vehicle AI, with an additional TaxiDriver supervisor that tries to make the built-in behavior more sensible in a visible passenger, delivery, and refueling scenario. It is not intended to behave like a production autonomous-driving system on every map, vehicle, junction, or traffic layout.

### Driving presets and custom controls

- Added complete AI driving presets: **Modest Novice**, **Cautious Driver**, **Balanced**, **Assertive**, **Mad Racer**, and **Custom**.
- Ready-made presets atomically configure aggression, following gap, braking, stuck timeout, road-rule behavior, overtaking, clearance, recovery limits, and final-approach speed.
- Manual controls are now shown only for the **Custom** preset, matching the existing custom-difficulty interaction.
- Split the former traffic-rule switch into independent **Obey speed limits** and **Obey traffic signals** settings.
- Added a nested **Maneuvers and recovery** section for overtaking, lane-change clearance, oncoming-lane recovery, reverse recovery, maximum recovery attempts, and exact final-approach speed.
- Existing 3.1.0 Beta AI settings migrate to **Custom** and retain their values. New installations start with **Balanced**.
- Added complete preset and recovery text for all nine supported interface languages.

### Reverse recovery and obstacle handling

- Added a rear-facing collision fan that evaluates several reverse steering angles against static geometry and nearby vehicles.
- A vehicle boxed against a wall, obstacle, or stopped car can now select the safest available rear corridor, reverse approximately 3–6 metres, stop, and replan its forward bypass.
- Rear clearance is rescanned throughout the maneuver; newly occupied space aborts the escape instead of blindly reversing into traffic.
- Added a configurable recovery-attempt limit. Once exhausted, AI stops and waits for player intervention instead of repeating aggressive recovery indefinitely.
- Lane-change clearance now scales the required free space both ahead and behind, while exact-approach speed controls the final physical trigger handoff.

### Gearbox and stationary behavior

- Reworked the Arcade gearbox handoff to be idempotent: supported vehicles switch once instead of repeatedly changing behavior during the same session.
- Removed direct gear-index commands that could push manual transmissions back toward Realistic behavior or damage a reverse gear without clutch control.
- AI now leaves clutch and direction selection to BeamNG's Arcade controller.
- Stopped vehicles remain in Drive under the service brake and no longer cycle continuously between Drive and Neutral at signals or in slow queues.
- A short forward-pedal/parking-brake handoff recovers from Neutral or Reverse without rolling backward.
- Improved drive-readiness handling so the parking brake holds the vehicle while ignition, starter, and powertrain state settle.

### Refueling behavior

- Removed automatic low-fuel and low-charge detours from AI mode.
- TaxiDriver no longer interrupts or redirects an accepted route solely because energy reaches a threshold.
- Refueling is now explicit: open **Refuel**, then enable AI on that fuel route if automatic driving is desired.
- Starting a fuel detour releases any currently active AI route so the player explicitly chooses whether to hand the new route back to AI.

### Validation and compatibility

- Expanded Lua combinatorics for rear-fan planning, blocked reverse paths, Arcade idempotence, Drive holding, legacy-setting migration, all AI presets, independent road-rule combinations, clearance bounds, recovery limits, and final-approach speeds.
- Expanded functional UI checks for atomic preset application, Custom-only controls, the nested maneuver expander, and independent rule switches.
- Verified **301 responsive UI states** across the in-game UI App, Connected Phone, all nine locales, compact/full layouts, and DPR 2 HiDPI rendering.
- The deterministic archive still contains 44 verified entries and rejects accidental automatic loading of TaxiDriver Vehicle Lua extensions.
- Existing settings and progress remain compatible; the release uses cache revision `311-rc` so the in-game and external UIs do not mix assets with 3.1.0 Beta.

## 3.1.0 Beta — Shift Memory and AI Driver

This prerelease contains every change made after `3.0.0-beta`.

### Restorable shift history

- Added `shiftHistory.lua` and a separate `shiftshistory.json` persistence document for vehicle-bound shift sessions.
- Added **Previous shifts** to the start screen and a **Shifts** tab to Driver Profile.
- Saved shifts retain the BeamNG model/configuration, selector name, preview, fuel/charge percentages, rides, AI rides, gross income, fuel cost, penalties, net income, and average rating.
- Selecting a saved shift replaces the current vehicle with the recorded configuration and restores its compatible energy storages.
- Active shifts are snapshotted every 60 seconds and during relevant lifecycle transitions, so closing the game does not require a dedicated finish action.
- Starting a shift in another vehicle closes and records the previous vehicle-bound session before opening the new one.
- Zero-ride sessions are not persisted, the list is capped and sanitized, and entries whose vehicle configuration is no longer installed are removed after BeamNG's vehicle registry becomes ready.

### Configurable AI driver

- Added an AI control overlay to active trip and refueling maps, including Connected Phone and the in-game UI App.
- Added a GE-side supervisor around BeamNG's native vehicle AI for passenger pickup, scheduled stops, cargo delivery, destination, and fuel-station routes.
- Added user settings for aggression, following time gap, comfortable braking deceleration, stuck timeout, traffic-rule obedience, same-direction overtaking, and oncoming-lane recovery.
- Added lead-vehicle tracking with a speed-dependent safe gap, progressive speed caps, emergency-gap handling, and automatic release when the lane clears.
- Added same-direction multi-lane overtaking with road-lane validation, adjacent-lane clearance checks, cooldowns, and turn indicators.
- Added traffic-signal handling for red and yellow phases, stopping-distance decisions, stop-line commitment, and intersection exit priority so a vehicle does not stop halfway through a manoeuvre.
- Fixed queues at traffic lights being mistaken for permanent obstacles. The AI now waits for the signal/traffic, rescans the lane, restores its route and speed cap as soon as traffic moves, and only starts bypass recovery for a genuinely stationary blockage.
- Added immediate native `Route Done` observation and physical target validation. A route ending outside the trigger starts a low-speed exact-approach path instead of waiting for the generic stuck timer.
- Added automatic engine-start requests and a temporary Arcade gearbox override while AI controls the vehicle; the previous gearbox behavior is restored when control returns to the player.
- Stopped repeated Neutral/Drive hunting: short stops are held with the service brake in Drive and prolonged stationary holds transition after ten seconds.

### Adaptive obstacle recovery and collision prevention

- Added `autopilotPerception.lua`, which measures the current road, vehicle, stationary obstacle, road boundaries, nearby traffic and both bypass sides before choosing a recovery corridor.
- Replaced fixed recovery offsets with a smooth seven-point local path that uses the smallest collision-free lateral movement around the obstacle.
- Added projected traffic checks along the whole bypass path, including vehicle dimensions and movement during the manoeuvre.
- Added `taxiDriverAutopilotRecovery.lua` as a lazy Vehicle Lua controller for exact approach, bypass steering, indicators, powertrain/gearbox coordination and completion callbacks.
- Added straight and steering-curved trajectory rays across the vehicle width. They check dynamic oriented vehicle boxes and static geometry, then blend comfortable braking or apply emergency braking when impact is imminent.
- Kept BeamNG obstacle avoidance enabled during normal route following; local recovery only takes control after the supervisor confirms a blocked corridor.

### Energy-aware routing

- Added critical-energy checks at 5% for combustion vehicles and 15% for EVs.
- If AI is enabled before passenger pickup or cargo loading, critical energy inserts the same priority fuel detour used by the **Refuel** action without cancelling the accepted order.
- A trip already carrying a passenger or cargo is never interrupted solely because the critical threshold is reached; refueling is deferred until the current order is complete.
- When a map has no compatible station, AI stops and opens Magic Fuel so the player can select the amount before continuing.
- Fuel routes use exact trigger approach, and the AI control remains accessible above the map throughout refueling.

### Driver profile, analytics and reviews

- Recorded whether AI was used at least once during each completed order.
- Added AI-assisted markers to reviews and stored AI trip totals in shift and per-vehicle history.
- Added a simple cumulative **AI-driven trips** counter to Profile Analytics.
- Reviews now show the customer's order score separately from the resulting profile rating, with green/equal-yellow/red comparison colors.
- Reworked review pagination to measure the actual available panel height and the rendered heights of regular and AI-assisted rows. It recalculates after resize, UI scale, tab, locale, or data changes and keeps the pager at the bottom without overlap.

### Routing, localization and UI

- Added **Unlimited route length** to Trip settings. When enabled, passenger and delivery generation keeps the normal minimum distance but removes the standard 25 km maximum.
- Added complete Simplified Chinese localization, bringing the shared in-game and Connected Phone UI to nine languages.
- Expanded profile navigation to five tabs and added responsive shift cards with vehicle previews and restore progress.
- Added cache revision `310-beta` to the in-game and external UI assets so browsers do not mix this build with 3.0.0 Beta files.

### Reliability, architecture and testing

- Preserved active shift/autopilot accounting across vehicle replacement, reset and mission lifecycle callbacks while rejecting callbacks from stale vehicle instances.
- Kept restorable shift data in a focused module rather than increasing the main Lua chunk toward LuaJIT's 200-local limit.
- Updated deterministic packaging to require the shift and autopilot modules plus the lazy Vehicle Lua recovery controller; the release archive contains 44 verified entries.
- Expanded Lua combinatorics with route limits, shift-history sanitization/restoration, AI phases and settings, signal queues, early `Route Done`, following, overtaking, adaptive bypass, trajectory rays, engine/gearbox control, and 500 deferred vehicle respawns.
- Expanded responsive UI coverage to **301 states** across nine locales, both UI surfaces, compact/full layouts, 80–180% scaling and DPR 2 HiDPI rendering.
- Added functional checks for shift restoration, fuel-route AI control, AI trip analytics, customer/profile review ratings, adaptive height-based pagination and the full AI/settings matrix.

### Compatibility and Beta status

- Existing 3.0.0 Beta settings, difficulty, profile, progress, vehicles, LAN identity and active gameplay data remain compatible.
- New AI and unlimited-route settings are normalized with safe defaults; `shiftshistory.json` is created independently.
- The build remains a prerelease while the AI supervisor and recovery controller receive broader testing across maps, traffic layouts, powertrains and community vehicles.

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
