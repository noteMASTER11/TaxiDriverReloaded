import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright";
import { startHarnessServer } from "./server.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const artifacts = path.join(here, "artifacts");
const baselines = path.join(here, "baselines");
await fs.mkdir(artifacts, { recursive: true });
await fs.mkdir(baselines, { recursive: true });
const playwrightEntry = fileURLToPath(import.meta.resolve("playwright"));
const coreBundlePath = path.join(path.dirname(path.dirname(playwrightEntry)), "playwright-core", "lib", "coreBundle.js");
const { utils: playwrightUtils } = await import(pathToFileURL(coreBundlePath).href);
const comparePng = playwrightUtils.getComparator("image/png");
const externalLoaderSource = await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/external/external.js"),
  "utf8"
);
const appJsSource = await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/app.js"),
  "utf8"
);
const appHtmlSource = await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/app.html"),
  "utf8"
);
const appCssSource = await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/app.css"),
  "utf8"
);
const localeData = JSON.parse(await fs.readFile(
  path.join(here, "../../ui/modules/apps/TaxiDriverHUD/locales.json"),
  "utf8"
));
const taxiDriverLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/taxiDriver.lua"),
  "utf8"
);
const configLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/config.lua"),
  "utf8"
);
const vehicleHistoryLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/vehicleHistory.lua"),
  "utf8"
);
const vehicleControlLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/vehicleControl.lua"),
  "utf8"
);
const persistenceLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/persistence.lua"),
  "utf8"
);
const routePlannerLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/routePlanner.lua"),
  "utf8"
);
const routeCacheLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/routeCache.lua"),
  "utf8"
);
const shiftTrackerLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/shiftTracker.lua"),
  "utf8"
);
const shiftHistoryLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/shiftHistory.lua"),
  "utf8"
);
const tripEventsLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/tripEvents.lua"),
  "utf8"
);
const policeCheckLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/policeCheckEvent.lua"),
  "utf8"
);
const physicalPickupLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/physicalPickup.lua"),
  "utf8"
);
const tripHistoryLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/tripHistory.lua"),
  "utf8"
);
const lanBridgeLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/lanBridge.lua"),
  "utf8"
);
const networkAddressLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/networkAddress.lua"),
  "utf8"
);
const hudPublisherLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/hudPublisher.lua"),
  "utf8"
);
const loggerLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/logger.lua"),
  "utf8"
);
const aiLoggerLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/aiLogger.lua"),
  "utf8"
);
const nextOfferGuardLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/nextOfferGuard.lua"),
  "utf8"
);
const autopilotLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/autopilot.lua"),
  "utf8"
);
const aiDriverRouteLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/aiDriverRoute.lua"),
  "utf8"
);
const autopilotPerceptionLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/autopilotPerception.lua"),
  "utf8"
);
const autopilotRecoveryLuaSource = await fs.readFile(
  path.join(here, "../../lua/vehicle/extensions/taxiDriverAutopilotRecovery.lua"),
  "utf8"
);
const stockAiObserverLuaSource = await fs.readFile(
  path.join(here, "../../lua/vehicle/extensions/taxiDriverStockAiObserver.lua"),
  "utf8"
);
const fleetWorkerLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/fleetWorker.lua"),
  "utf8"
);
const navigationUiLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/navigationUi.lua"),
  "utf8"
);
const telemetryLuaSource = await fs.readFile(
  path.join(here, "../../lua/vehicle/extensions/taxiDriverTelemetry.lua"),
  "utf8"
);
const vehicleBridgeGuardLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/vehicleBridgeGuard.lua"),
  "utf8"
);
const optionalLanBridgeLuaSource = await fs.readFile(
  path.join(here, "../../lua/ge/extensions/taxiDriver/optionalLanBridge.lua"),
  "utf8"
);
const cssToken = (name) => {
  const match = appCssSource.match(new RegExp(`--${name}:\\s*(#[0-9a-f]{6})`, "i"));
  assert.ok(match, `CSS token --${name} must be declared as a solid hex color`);
  return match[1];
};
const relativeLuminance = (hex) => {
  const channels = hex.slice(1).match(/../g).map((part) => parseInt(part, 16) / 255);
  const linear = channels.map((value) => value <= 0.04045
    ? value / 12.92
    : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
};
const contrastRatio = (foreground, background) => {
  const a = relativeLuminance(foreground);
  const b = relativeLuminance(background);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
};
assert.doesNotMatch(appCssSource, /rgba?\(\s*255\s*,\s*209\s*,\s*26|#ffd11a/i,
  "The retired yellow palette must never return");
assert.doesNotMatch(appCssSource, /rgba\(\s*255\s*,\s*102\s*,\s*0/i,
  "Brand orange must not be used as a translucent tinted surface");
assert.doesNotMatch(appCssSource, /#9254e8|rgba\(\s*174\s*,\s*116\s*,\s*255|rgba\(\s*146\s*,\s*84\s*,\s*232/i,
  "Fleet must use the shared neutral palette instead of a purple sub-theme");
for (const value of ["#ff6600", "#ff7a24", "#e95600", "#4cd984", "#ffb020", "#ff5c68", "#5aa7ff"]) {
  assert.equal((appCssSource.match(new RegExp(value, "gi")) || []).length, 1,
    `${value} must be declared only once in the semantic token block`);
}
for (const [foreground, background, label] of [
  [cssToken("td-text"), cssToken("td-bg"), "primary text"],
  [cssToken("td-text-secondary"), cssToken("td-surface-1"), "secondary text"],
  [cssToken("td-on-accent"), cssToken("td-accent"), "text on brand action"],
  [cssToken("td-success"), cssToken("td-surface-1"), "success status"],
  [cssToken("td-warning"), cssToken("td-surface-1"), "warning status"],
  [cssToken("td-danger"), cssToken("td-surface-1"), "danger status"],
  [cssToken("td-info"), cssToken("td-surface-1"), "navigation status"]
]) {
  assert.ok(contrastRatio(foreground, background) >= 4.5,
    `${label} must meet the 4.5:1 driver-HMI contrast floor`);
}
assert.match(
  externalLoaderSource,
  /\.api\.subscribeToEvents\(\s*["']\{\}["']\s*\)/,
  "External phone loader must subscribe before expecting TaxiDriver GUI hooks"
);
assert.match(vehicleHistoryLuaSource, /filePath\s*=\s*settingsDirectoryPath\s*\.\.\s*["']\/vehicles\.json["']/,
  "Vehicle odometer and ride history must use a separate vehicles.json document");
assert.match(taxiDriverLuaSource, /require\(["']taxiDriver\/optionalLanBridge["']\)/,
  "LAN support must be loaded lazily instead of remaining a hard dependency of the mod");
assert.match(optionalLanBridgeLuaSource, /pcall\(require,\s*["']taxiDriver\/lanBridge["']\)/,
  "An unavailable LAN implementation must not abort the core extension");
assert.match(vehicleBridgeGuardLuaSource,
  /scanGeneration[\s\S]*?isRequestCurrent[\s\S]*?getObjectByID[\s\S]*?pcall\(callback/,
  "Vehicle bridge callbacks must reject stale VM generations and isolate callback failures");
assert.doesNotMatch(taxiDriverLuaSource, /core_vehicleBridge\.requestValue/,
  "The orchestrator must not issue unguarded asynchronous vehicle bridge requests");
assert.doesNotMatch(shiftHistoryLuaSource, /core_vehicleBridge\.requestValue/,
  "Shift energy restoration must not issue unguarded vehicle bridge requests");
assert.doesNotMatch(taxiDriverLuaSource, /onTelemetryVehicleReset/,
  "The duplicate telemetry reset entry point must not bypass the vehicle scan guard");
assert.match(taxiDriverLuaSource, /runtimeBoundary:call\(["']activeMode\.update["']/,
  "A failure in active gameplay work must not abort every later game tick subsystem");
assert.match(lanBridgeLuaSource, /coroutine\.yield\(false\)[\s\S]*?coroutine\.resume\(roadBuildJob\)/,
  "Road-network serialization must be chunked across frames");
assert.match(loggerLuaSource, /setOperationFilter[\s\S]*?pcall\(operationFilter/,
  "Extended operation logging must support filtering high-volume traffic events");
assert.match(appJsSource, /pagehide[\s\S]*?beforeunload[\s\S]*?stopHudHeartbeats/,
  "HUD heartbeat timers must stop before late Angular teardown");
assert.match(appJsSource,
  /visibilitychange[\s\S]*?handleNativeHeartbeatVisibility[\s\S]*?blur[\s\S]*?suspendNativeHudHeartbeat[\s\S]*?focus[\s\S]*?resumeNativeHudHeartbeat/,
  "Native HUD heartbeats must pause before CEF or the game window becomes unavailable");
assert.match(taxiDriverLuaSource, /if not bestFacility then\s+realisticFuel\.openMagicStation\(currentVehicle\)/,
  "Missing compatible stations must open the magic refueling fallback");
assert.match(taxiDriverLuaSource, /state\.completedRides\s*=\s*state\.completedRides\s*\+\s*1[\s\S]*?vehicleHistory\.recordRide\(\{/,
  "Completed rides and income must be attributed to the current vehicle");
assert.match(vehicleHistoryLuaSource, /maximumPlausibleDistance\s*=\s*math\.max/,
  "Vehicle odometer must reject implausible teleport/reset distance jumps");
assert.match(vehicleHistoryLuaSource, /if vehicleId == tracking\.vehicleId and tracking\.entry then[\s\S]*?return false/,
  "Live part edits must keep the existing vehicle-history identity");
assert.doesNotMatch(vehicleHistoryLuaSource, /fingerprint\s*~=/,
  "Vehicle partConfig changes must not trigger expensive identity rebuilds in the update loop");
assert.doesNotMatch(vehicleHistoryLuaSource, /getPlayerVehicle\(\s*\)/,
  "BeamNG's global getPlayerVehicle API requires an explicit player index");
assert.match(vehicleHistoryLuaSource, /be:getPlayerVehicle\(0\)/,
  "Vehicle history must resolve the primary player's vehicle through BeamNGEngine");
assert.match(taxiDriverLuaSource, /function M\.onVehicleSwitched[\s\S]*?vehicleHistory\.selectVehicle\(newId\)[\s\S]*?notifyHud\(\)/,
  "Switching vehicles must select the new vehicle and publish its odometer immediately");
assert.match(taxiDriverLuaSource, /function M\.onClientStartMission\(\)[\s\S]*?vehicleHistory\.refreshCurrentVehicle\(\)[\s\S]*?notifyHud\(\)/,
  "Loading a level must refresh and publish the selected vehicle independently of taxi mode");
assert.match(taxiDriverLuaSource, /function M\.openVehicleSelector\(\)[\s\S]*?navigationUi:setUiBlocked\(true\)[\s\S]*?guihooks\.trigger\(["']ChangeState["'],\s*\{state\s*=\s*["']menu\.vehicles["']\}\)/,
  "Vehicle card must hide the native map before opening BeamNG's vehicle selector");
assert.match(navigationUiLuaSource, /function service:canShow\(allowFleet\)[\s\S]*?appVisible and not uiBlocked[\s\S]*?isRouteActive[\s\S]*?allowFleet == true/,
  "Native map updates must require a visible unobstructed UI, an active route, or the explicit Fleet map mode");
assert.match(navigationUiLuaSource, /function service:setAppVisibility\(visible\)[\s\S]*?appVisible\s*=\s*nextVisible[\s\S]*?TaxiDriverMinimapInvalidated/,
  "Native map visibility must follow the actual CEF UI App visibility");
assert.match(navigationUiLuaSource,
  /local nextVisible = visible == true[\s\S]*?if appVisible == nextVisible then return end[\s\S]*?TaxiDriverMinimapInvalidated/,
  "Repeated BeamNG 0.39 CEF visibility events must not invalidate an unchanged minimap");
assert.match(navigationUiLuaSource,
  /function service:setTransform[\s\S]*?lastTransform[\s\S]*?math\.abs\(lastTransform\[1\] - x\) < 0\.00001[\s\S]*?then return end[\s\S]*?setDrawTransform\(x, y, width, height\)/,
  "Identical minimap transforms must be rejected before reaching TextureDraw");
assert.match(navigationUiLuaSource,
  /local visible = not options\.isRouteGuidanceHidden[\s\S]*?showNavigationGroundmarkers["'], visible\)[\s\S]*?showNavigationArrows["'], visible\)[\s\S]*?core_groundMarkers\.onSettingsChanged/,
  "TaxiDriver's route-guidance toggle must explicitly apply both BeamNG 0.39 navigation settings");
assert.match(navigationUiLuaSource,
  /core_groundMarkers\.setPath\(target\.pos[\s\S]*?if not guidanceVisible and core_groundMarkerArrows then[\s\S]*?core_groundMarkerArrows\.clearArrows\(\)/,
  "Disabled guidance must clear the arrow pool that BeamNG 0.39 recreates inside setPath");
assert.match(navigationUiLuaSource,
  /scenario\/raceMarkers\/attention[\s\S]*?setDestinationMarker[\s\S]*?marker:createMarkers\(\)[\s\S]*?marker:setToCheckpoint[\s\S]*?function service:onPreRender/,
  "Every active route must own and animate a BeamNG 0.39 destination marker independently of setPath");
assert.match(navigationUiLuaSource,
  /function service:clearNavigation\(\)[\s\S]*?core_groundMarkers\.setPath\(nil\)[\s\S]*?clearDestinationMarker\(\)/,
  "Clearing navigation must also remove TaxiDriver's destination marker");
assert.match(taxiDriverLuaSource, /function M\.onUiChangedState\(to, from\)[\s\S]*?menu\.vehiclesnew[\s\S]*?menu\.appedit[\s\S]*?if isBlocking\(to\)[\s\S]*?navigationUi:setUiBlocked\(true\)[\s\S]*?elseif isBlocking\(from\)[\s\S]*?TaxiDriverMinimapInvalidated/,
  "Known BeamNG overlays must hide the native map without blocking unrelated intermediate UI states");
assert.match(taxiDriverLuaSource, /function M\.openVehicleSelector\(\)[\s\S]*?navigationUi:setUiBlocked\(true\)/,
  "Opening the vehicle selector must block timer-driven map redraws immediately");
assert.match(vehicleHistoryLuaSource, /configData and configData\.preview/,
  "Current-vehicle state must expose BeamNG's configuration preview asset");
assert.match(taxiDriverLuaSource, /require\(["']taxiDriver\/persistence["']\)/,
  "The main extension must delegate JSON schemas and storage to persistence.lua");
assert.match(taxiDriverLuaSource, /require\(["']taxiDriver\/vehicleControl["']\)/,
  "The main extension must delegate vehicle controls to vehicleControl.lua");
assert.match(taxiDriverLuaSource, /require\(["']taxiDriver\/routePlanner["']\)/,
  "The main extension must delegate route generation and stop caches to routePlanner.lua");
assert.match(persistenceLuaSource, /function store:loadSettings\(\)/,
  "Persistence module must own settings loading and canonicalization");
assert.match(routePlannerLuaSource, /function service\.chooseStop\(/,
  "Route planner module must expose a named stop-selection API");
assert.match(routePlannerLuaSource,
  /calculateGraphDistance[\s\S]*?getRoutePoints[\s\S]*?chooseGraphRoadStop/,
  "Order generation must retain an in-memory road-graph fallback independent from semantic map modules");
assert.match(routePlannerLuaSource,
  /function service\.chooseStop[\s\S]*?getRoutePoints\(\)[\s\S]*?chooseSemanticStop/,
  "Road-graph fallback points must be prepared even when semantic anchors can satisfy the first order");
assert.match(routeCacheLuaSource,
  /\/settings\/TaxiDriver\/route_cache[\s\S]*?routes_%s_%s\.json[\s\S]*?schemaVersion/,
  "Every map must persist dispatcher routes in its own user-folder JSON cache");
assert.match(routeCacheLuaSource,
  /function M\.appendOffer\(offer, originPos\)[\s\S]*?document\.routes\s*=\s*routes[\s\S]*?writeDocument/,
  "Every offer shown by the dispatcher must be appended to the current map JSON");
assert.match(taxiDriverLuaSource,
  /table\.insert\(offers, offer\)[\s\S]*?cachePublishedOffer\(offer\)[\s\S]*?notifyHud\(\)/,
  "A generated offer must be cached in the same transition that publishes it to the UI");
assert.match(taxiDriverLuaSource,
  /if not offer then offer = createOfferFromRouteCache\(requestedType\) end/,
  "A failed live generator must restore a compatible dispatcher offer from the map cache");
assert.match(taxiDriverLuaSource,
  /local function beginSearching[\s\S]*?routeCache\.ensureCurrentMapFile/,
  "Starting dispatcher search must immediately create or migrate the current map cache file");
assert.match(routePlannerLuaSource,
  /pcall\(scenetree\.findClassObjects[\s\S]*?pcall\(sitesManager\.getCurrentLevelSitesFiles[\s\S]*?logSemanticFallback/,
  "Broken semantic triggers, sites, or POIs must not disable road-graph order generation");
assert.match(persistenceLuaSource, /unlimitedRouteDistance\s*=\s*false/,
  "Unlimited route generation must remain opt-in by default");
assert.match(routePlannerLuaSource,
  /maximumDistance\s*==\s*nil[\s\S]*?chooseUnboundedRoadStop\(startPos, minimumDistance, maximumAttempts\)/,
  "The route planner must use map-wide road sampling when no upper limit is requested");
assert.match(taxiDriverLuaSource,
  /unlimitedRouteDistance\s*=\s*userSettings\.unlimitedRouteDistance\s*==\s*true[\s\S]*?destinationMaxDistance\s*=\s*nil[\s\S]*?elseif not unlimitedRouteDistance/,
  "Passenger and delivery offers must omit the 25 km ceiling only when the toggle is enabled");
assert.match(routePlannerLuaSource, /function service\.getStopCandidateCount\(\)/,
  "Route planner module must expose semantic stop availability to the orchestrator");
assert.match(taxiDriverLuaSource, /routePlanning\.getStopCandidateCount\(\)/,
  "Multi-stop offer generation must query the extracted route planner API");
assert.doesNotMatch(taxiDriverLuaSource, /\bgetStopCandidates\s*\(/,
  "The main extension must not call route planner internals after extraction");
assert.match(configLuaSource, /nextOfferErrorLimit\s*=\s*3/,
  "Repeated late next-offer failures must have a bounded per-trip retry limit");
assert.match(taxiDriverLuaSource, /local function recordNextOfferError[\s\S]*?trip\.nextOfferDisabled\s*=\s*true/,
  "Repeated next-offer errors must disable only that optional subsystem for the current trip");
assert.match(taxiDriverLuaSource, /local function updateNextOfferOpportunitySafely[\s\S]*?xpcall\([\s\S]*?updateNextOfferOpportunity\(dtSim\)[\s\S]*?recordNextOfferError/,
  "Late next-offer generation must not propagate Lua errors into the main update loop");
assert.match(taxiDriverLuaSource, /updateNextOfferOpportunitySafely\(dtSim\)[\s\S]*?beginAlighting\(\)/,
  "A failed optional next-offer update must not prevent destination arrival handling");
assert.match(nextOfferGuardLuaSource,
  /phaseChanged[\s\S]*?invalidTimer[\s\S]*?value\s*=\s*math\.min\(value, duration\)[\s\S]*?dtReal/,
  "Next offers must have a phase-independent real-time expiry guard for corrupt and stale timers");
assert.match(taxiDriverLuaSource,
  /runtimeBoundary:call\(["']nextOffer\.lifetime["'],\s*updateNextOfferLifetime,\s*dtReal\)[\s\S]*?vehicleScanGuard\.isConfigurationOpen/,
  "The offer expiry guard must run while vehicle configuration suspends normal gameplay updates");
assert.match(appHtmlSource,
  /taxi-next-offer__close[\s\S]*?dismissNextOffer\(state\.nextOffer\.id\)/,
  "The proposed-order modal must expose an explicit per-order dismiss button");
assert.match(appJsSource,
  /trackedNextOfferDeadline[\s\S]*?Math\.min\(trackedNextOfferDeadline, candidateDeadline\)[\s\S]*?nextOfferCountdownTimer/,
  "The UI countdown must use a monotonic local deadline that stale HUD packets cannot extend");
assert.match(routePlannerLuaSource, /function service\.getNearestRoadSpeedLimit\(pos\)/,
  "Road speed-limit lookup must remain in the route planner module");
assert.match(taxiDriverLuaSource, /routePlanning\.getNearestRoadSpeedLimit\(vehicle:getPosition\(\)\)/,
  "Speed penalties must use the route planner instead of an unavailable global getRoadLink function");
assert.doesNotMatch(taxiDriverLuaSource, /\bgetRoadLink\s*\(/,
  "The main extension must not call BeamNG's unavailable global getRoadLink function");
assert.match(taxiDriverLuaSource, /userSettings\.randomEventsEnabled\s*==\s*true[\s\S]*?tripEvents\.create/,
  "Random trip events must be gated by their persisted mode toggle");
assert.doesNotMatch(appHtmlSource,
  /taxi-home__realistic--fuel[\s\S]*?<small>5% \/ EV 30%<\/small>/,
  "Home must not show the fuel and EV percentages beside the mode toggle");
assert.doesNotMatch(appHtmlSource,
  /taxi-home__realistic--events[\s\S]*?<small>\{\{ t\('randomEventsShort'\) \}\}<\/small>/,
  "Home must not show the optional-trip-surprises subtitle beside the events toggle");
assert.match(appHtmlSource,
  /taxi-home__realistic--fuel[\s\S]*?ng-attr-title="\{\{ t\('realisticMode'\) \}\}"[\s\S]*?ng-attr-aria-label="\{\{ t\('realisticMode'\) \}\}"/,
  "The fuel mode toggle must retain localized title and accessible text");
assert.match(appHtmlSource,
  /taxi-home__realistic--events[\s\S]*?ng-attr-title="\{\{ t\('randomEvents'\) \}\}"[\s\S]*?ng-attr-aria-label="\{\{ t\('randomEvents'\) \}\}"/,
  "The random-events toggle must retain localized title and accessible text");
assert.match(hudPublisherLuaSource, /TaxiDriverHUDPatch/,
  "Periodic HUD updates must use compact delta packets");
assert.match(hudPublisherLuaSource, /baseRevision[\s\S]*?revision[\s\S]*?clientNeedsSync/,
  "HUD deltas must be revisioned and support loss detection");
assert.match(taxiDriverLuaSource,
  /if not state\.active[\s\S]*?["']hud\.patch["'],\s*notifyHudPatch[\s\S]*?hudTimer >= runtimeConfig\.hudUpdateInterval[\s\S]*?["']hud\.patch["'],\s*notifyHudPatch/,
  "The active and inactive periodic loops must avoid repeating full HUD snapshots");
assert.match(lanBridgeLuaSource, /canPublishNavigation\(\)[\s\S]*?navigationPhases\[authoritativePhase\]/,
  "Remote map telemetry must follow Lua's authoritative trip phase");
assert.doesNotMatch(lanBridgeLuaSource,
  /return connected and externalVisible and externalMapEnabled/,
  "Remote map telemetry must not stop because a browser view reported itself hidden");
assert.match(lanBridgeLuaSource, /heartbeatTimeout\s*=\s*8\.0/,
  "Battery-friendly heartbeats must tolerate browser timer throttling");
assert.match(lanBridgeLuaSource,
  /wsUtils\.createOrGetWS\([\s\S]*?"any"[\s\S]*?selectLanAddress\(nativeAddress\)[\s\S]*?probeNativeLanListener[\s\S]*?startLanProxy/,
  "Connected Phone must prefer BeamNG's native LAN listener and restore a loopback proxy when the native server exposes only localhost");
assert.match(lanBridgeLuaSource,
  /routedLanAddress[\s\S]*?setpeername[\s\S]*?getsockname[\s\S]*?canBindAddress[\s\S]*?socketLib\.bind/,
  "LAN discovery must combine the Windows route-selected address with an ownership bind probe");
assert.match(lanBridgeLuaSource,
  /hostnameAddresses[\s\S]*?dns\.gethostname[\s\S]*?dns\.getaddrinfo[\s\S]*?hostname_discovery/,
  "LAN discovery must fall back to Windows hostname resolution when BeamNG exposes only loopback");
assert.match(networkAddressLuaSource,
  /virtualMarkers[\s\S]*?openvpn[\s\S]*?wi%-fi[\s\S]*?candidate\.bindable[\s\S]*?candidate\.score/,
  "LAN selection must prefer a bindable physical Wi-Fi/Ethernet adapter over VPN and virtual interfaces");
assert.match(appHtmlSource,
  /state\.lan\.enabled && state\.lan\.url[\s\S]*?state\.lan\.bridgeError/,
  "A failed LAN start must show its error instead of an empty white QR container");
assert.match(taxiDriverLuaSource, /state\.ratingCount\s*=\s*math\.max\(0,[\s\S]*?state\.completedRides[\s\S]*?vehicleHistory\.setAllRatings\(rating\)/,
  "The rating cheat must re-rate the complete ride history");
assert.match(taxiDriverLuaSource,
  /function realisticFuel\.setVehicleEnergyLevels[\s\S]*?setEnergyStorageEnergy/,
  "Realistic mode and the energy cheat must share BeamNG's proven bridge path");
assert.match(taxiDriverLuaSource,
  /function M\.cheatSetEnergyPercent[\s\S]*?realisticFuel\.setVehicleEnergyLevels\(vehicle, percent \/ 100, percent \/ 100/,
  "The energy cheat must pass the selected percentage through realistic mode's energy setter");
assert.match(taxiDriverLuaSource, /if userSettings\.godMode == true[\s\S]*?notifyHud\(\)[\s\S]*?return/,
  "God Mode must preserve an active ride across vehicle resets");
assert.match(persistenceLuaSource, /debugLogging\s*=\s*true/,
  "Debug logging must default to enabled");
assert.match(persistenceLuaSource, /aiDebugLogging\s*=\s*false[\s\S]*?source\.aiDebugLogging\s*==\s*true/,
  "The dedicated AI trip logger must be persisted separately and disabled by default");
assert.match(appHtmlSource, /aiDebugLogger[\s\S]*?ng-model="settings\.aiDebugLogging"/,
  "AI driver settings must expose a dedicated trip-debug toggle");
assert.doesNotMatch(persistenceLuaSource, /aiDecisionVisualization/,
  "Removed AI visualization state must no longer be persisted");
assert.doesNotMatch(appHtmlSource, /aiDecisionVisualization/,
  "The non-functional AI visualization toggle must be removed from settings");
assert.match(loggerLuaSource, /\[TaxiDriver\]/,
  "The structured logger must prefix every diagnostic record");
assert.match(loggerLuaSource, /function M\.observeRuntime[\s\S]*?function M\.attachOperations/,
  "The structured logger must track runtime transitions and public operations");
assert.match(loggerLuaSource, /pcall\(eventSink[\s\S]*?function M\.setEventSink/,
  "Structured events must remain available to the dedicated AI log when BeamNG debug logging is disabled");
assert.match(aiLoggerLuaSource, /taxidriver_ailog_[\s\S]*?\.jsonl[\s\S]*?navigation_snapshot/,
  "AI sessions must be written to a timestamped JSON Lines log in the BeamNG user root");
assert.match(aiLoggerLuaSource, /vehicle_damage_increased[\s\S]*?gear_hunting_detected[\s\S]*?collision_safety_engaged/,
  "AI logging must retain damage, drivetrain, and collision-safety anomalies");
assert.match(taxiDriverLuaSource, /aiLogger:update[\s\S]*?autopilot:getDiagnostics/,
  "The gameplay loop must publish authoritative route diagnostics to the AI logger");
assert.match(taxiDriverLuaSource, /require\(["']taxiDriver\/autopilot["']\)\.new/,
  "The gameplay orchestrator must delegate autonomous driving to a focused module");
assert.match(appJsSource, /autopilotValues[\s\S]*?setMinimapOcclusions/,
  "The native minimap layout must reserve an occlusion rectangle for the autopilot control");
assert.doesNotMatch(appJsSource, /hudStateReceived\s*=\s*true;\s*lastMinimapRect\s*=\s*["']["']/,
  "Periodic HUD telemetry must not rebuild the native minimap texture every frame");
assert.match(appJsSource,
  /phoneSuperMinimized[\s\S]*?toggleSuperMinimized[\s\S]*?hideMinimap\(true\)/,
  "The button-only native UI stage must explicitly hide the minimap");
assert.match(appJsSource,
  /hasNewNextOffer \|\| hasNewNotification[\s\S]*?collapseAttention\s*=\s*true/,
  "Collapsed UI notifications must set an indicator instead of forcing expansion");
assert.match(appJsSource,
  /updateReviewPagination[\s\S]*?getBoundingClientRect[\s\S]*?availableHeight[\s\S]*?reviewsPerPage[\s\S]*?ResizeObserver/,
  "Review pagination must derive its page size from the live profile-panel height");
assert.match(appHtmlSource, /taxi-ai-ride-counter[\s\S]*?profileProgress\.aiRideCount/,
  "AI-assisted trips must be presented as a numeric statistic");
assert.doesNotMatch(appHtmlSource, /getChartPoints\(profileProgress\.aiRideHistory/,
  "AI-assisted trip statistics must not be rendered as a time-series graph");
assert.match(navigationUiLuaSource, /setOcclusions[\s\S]*?taxiDriverAutopilot/,
  "The native minimap must apply the autopilot control occlusion rectangle");
assert.doesNotMatch(autopilotLuaSource, /autopilotPerception|beginRecovery|planLocalBypass|castRayStatic/,
  "The stock-AI experiment must not execute predictive perception or custom recovery");
assert.match(autopilotLuaSource,
  /aiDriverRoute\.new[\s\S]*?requestedRevision[\s\S]*?requestedSession[\s\S]*?pcall\(route\.request, route, vehicle/,
  "The player AI must use the asynchronous route adapter and validate its session and revision");
assert.match(autopilotLuaSource,
  /ai\.driveUsingPath[\s\S]*?ai\.setParameters[\s\S]*?ai\.setRacing\(false\)[\s\S]*?ai\.setRecoverOnCrash\(false\)[\s\S]*?taxiObserver\.watch/,
  "BeamNG 0.39 route initialization must precede the native profile and safety observer settings");
assert.match(aiDriverRouteLuaSource,
  /filterGraphNodes[\s\S]*?marker\.wp[\s\S]*?setupPathMultiJob[\s\S]*?generation\s*~=\s*runtime\.generation/,
  "Route planning must be asynchronous, stale-safe, and serialize graph node IDs only");
assert.match(aiDriverRouteLuaSource,
  /trimStartPath[\s\S]*?maximumRemoval\s*=\s*math\.min\(3[\s\S]*?targetSuffixProtected[\s\S]*?cumulativeDistance\s*>\s*30/,
  "Stock taxi start-path trimming must stay bounded and preserve the target suffix");
assert.match(stockAiObserverLuaSource,
  /mapmgr\.getObjects[\s\S]*?tCPA[\s\S]*?dCPA[\s\S]*?followingTimeGap/,
  "The stock AI traffic guard must observe NPC vehicles and impose a following-speed limit");
assert.match(stockAiObserverLuaSource,
  /math\.abs\(dz\)\s*<=\s*4[\s\S]*?kind\s*==\s*"oncoming"[\s\S]*?math\.abs\(candidate\.lateral\)\s*>\s*collisionCorridor[\s\S]*?stableThreatScans\s*\/\s*3/,
  "Ordinary opposing-lane and vertically separated traffic must not become a predictive collision threat");
assert.match(stockAiObserverLuaSource,
  /local function scanStatic[\s\S]*?rayDistance\s*<\s*maximumDistance\s*-\s*0\.25[\s\S]*?not centerClearance and hitCount < 2[\s\S]*?staticStableScans\s*>=\s*2/,
  "A clear static ray sentinel or one roadside ray must not brake the vehicle");
assert.match(stockAiObserverLuaSource,
  /local function applySpeedCaps[\s\S]*?safeAiCall\("setSpeedMode", "limit"\)/,
  "The safety arbiter must apply its winner through the stock AI speed limiter");
assert.match(stockAiObserverLuaSource,
  /materiallyLimiting[\s\S]*?smoothedSpeedLimit\s*<\s*context\.speed\s*-\s*0\.3[\s\S]*?state\.safetyHolding/,
  "A non-binding cap must not be reported as a braking intervention");
assert.match(stockAiObserverLuaSource,
  /tryEmergencyEvasion[\s\S]*?safeAiCall\("laneChange"[\s\S]*?threat\.kind\s*==\s*"oncoming"\s*and\s*1\.4/,
  "The supervisor must brake predictively and use only native lane changes for a proven emergency escape");
assert.match(fleetWorkerLuaSource,
  /taxiDriverStockAiObserver\.watch[\s\S]*?followingTimeGap[\s\S]*?brakingDeceleration[\s\S]*?updateInterval/,
  "Fleet workers must run a lower-cost instance of the stock-AI traffic guard");
assert.match(stockAiObserverLuaSource,
  /maximumTrackedVehicles\s*=\s*16[\s\S]*?updateP95Us[\s\S]*?adaptiveInterval\s*=\s*0\.05[\s\S]*?adaptiveInterval\s*=\s*0\.2/,
  "The supervisor must bound nearby traffic and adapt its scan rate while measuring CPU cost");
assert.match(stockAiObserverLuaSource,
  /road\.plusCount\s*<\s*2[\s\S]*?road\.minusCount\s*>\s*0[\s\S]*?road\.edge\.oneWay\s*~=\s*true[\s\S]*?remainingEdgeDistance\s*<\s*70/,
  "Native racing may only overtake on an explicit one-way multilane segment away from a junction");
assert.match(aiDriverRouteLuaSource,
  /orientedTargetEdge[\s\S]*?setupPathMultiJob[\s\S]*?oneWayApproachWouldReverse[\s\S]*?bidirectionalPass/,
  "Stock AI routes must reject a reversed one-way approach without adding a bidirectional U-turn");
assert.match(stockAiObserverLuaSource,
  /targetApproach[\s\S]*?maximumArrivalSpeed[\s\S]*?targetApproachActive/,
  "Final approach braking must bring the vehicle into the gameplay arrival trigger");
assert.match(stockAiObserverLuaSource,
  /local cap\s*=\s*math\.sqrt\(2\s*\*\s*deceleration\s*\*\s*remaining\)[\s\S]*?parkingHandoffSpeed[\s\S]*?context\.absoluteSpeed\s*<=\s*parkingHandoffSpeed/,
  "The arrival envelope must converge to zero before handing control to parking");
assert.doesNotMatch(stockAiObserverLuaSource, /input\.event\("steering"/,
  "The traffic guard must leave steering and route selection to native BeamNG AI");
assert.match(autopilotLuaSource,
  /isCurrentPlayerVehicle[\s\S]*?be:getPlayerVehicleID\(0\)[\s\S]*?route_result_no_longer_applicable/,
  "The player AI adapter must reject every vehicle except the current player vehicle");
assert.doesNotMatch(autopilotLuaSource, /ai\.setRecoverOnCrash\(true\)/,
  "The player vehicle must never inherit NPC crash recovery or safe-teleport behavior");
assert.match(autopilotLuaSource,
  /local function requestPark[\s\S]*?ai\.setMode\('stop'\)[\s\S]*?stationarySeconds\s*>=\s*0\.6[\s\S]*?commitPark/,
  "A completed route must stop under native AI before committing the parking brake");
assert.match(stockAiObserverLuaSource,
  /local function selectParkingGear[\s\S]*?grb_mde\s*=\s*"P"[\s\S]*?grb_idx\s*=\s*0[\s\S]*?local function updateParkingConfirmation[\s\S]*?parkingStableChecks\s*<\s*2[\s\S]*?parkingConfirmed\s*=\s*true/,
  "Vehicle Lua must select P or neutral and acknowledge only verified parking");
assert.match(stockAiObserverLuaSource,
  /local function restoreParkingGearboxBehavior[\s\S]*?setGearboxMode[\s\S]*?parkingGearboxBehavior[\s\S]*?main\.setGearboxMode, "realistic"[\s\S]*?current\.grb_mde[\s\S]*?actual == "P"/,
  "Arcade parking must hold visible P in Realistic and restore the user's behavior before the next route");
assert.match(stockAiObserverLuaSource,
  /local function holdParkingGearboxBehavior[\s\S]*?main\.setGearboxMode, "realistic"[\s\S]*?local function requestPark[\s\S]*?safeAiCall\("setMode", "stop"\)[\s\S]*?holdParkingGearboxBehavior\(\)[\s\S]*?parkingInput\("brake", 1\)[\s\S]*?local function commitPark[\s\S]*?safeAiCall\("setMode", "disabled"\)[\s\S]*?selectParkingGear/,
  "Parking must switch Arcade out before braking, then disable AI and select a parking gear");
assert.doesNotMatch(autopilotLuaSource, /stationaryFallback|parking_ack_fallback/,
  "Parking must never be declared successful from a timeout alone");
assert.match(autopilotLuaSource,
  /stuck_recovery_requested[\s\S]*?requestRoute\(vehicle, "stuckRecovery"\)[\s\S]*?stuck_recovery_exhausted[\s\S]*?requestPark\(vehicle, "stuckAfterRecovery"\)/,
  "A stationary native route gets one bounded replan before a controlled parking fault");
assert.match(autopilotLuaSource,
  /closeLead[\s\S]*?minimumFollowingDistance\s*\*\s*2[\s\S]*?safetyHold[\s\S]*?closeLead/,
  "The stuck watchdog must not replan or park while waiting behind close traffic");
assert.match(autopilotLuaSource,
  /completionRadius\s*=\s*math\.min\(8[\s\S]*?route_done_recovery_exhausted[\s\S]*?routeDoneOutsideTarget/,
  "Native route completion outside the pickup-safe radius must never count as arrival");
assert.match(stockAiObserverLuaSource,
  /local function supervisorStep[\s\S]*?state\.supervisorMode\s*=\s*"cruise"[\s\S]*?applySpeedCaps/,
  "Every safety scan must clear a stale emergency mode before arbitration");
assert.match(stockAiObserverLuaSource,
  /imminentOncomingOverlap[\s\S]*?threat\.ttc\s*<=\s*1\.1[\s\S]*?threat\.lateralClearance[\s\S]*?threat\.dCPA[\s\S]*?confidence\s*=\s*1/,
  "A physically overlapping oncoming threat must brake immediately instead of waiting for three scans");
assert.match(stockAiObserverLuaSource,
  /warningTtc[\s\S]*?predictiveWarningScale[\s\S]*?emergencyTtc/,
  "Driving presets may shift predictive warnings without weakening the common emergency barrier");
assert.match(vehicleControlLuaSource,
  /function M\.setForcedStop\(vehicle, enabled, preserveParkingBrake\)[\s\S]*?setForcedStop\(false\)[\s\S]*?input\.event\('parkingbrake',1,'FILTER_AI'/,
  "Releasing the boarding brake must be able to preserve the parked AI handbrake");
assert.match(taxiDriverLuaSource,
  /local function beginRide[\s\S]*?autopilot\.isParked[\s\S]*?autopilot:isParked\(\)/,
  "Starting the passenger leg must retain the handbrake after AI Driver parks and switches off");
assert.match(taxiDriverLuaSource,
  /local function stoppedForArrival[\s\S]*?runtimeConfig\.maxArrivalSpeedKmh[\s\S]*?trip\.usedAutopilot\s*~=\s*true\s*or\s*autopilot:isParked\(\)[\s\S]*?pickupReached[\s\S]*?stoppedForArrival\(speedKmh\)/,
  "Boarding must wait for near-zero speed and the verified AI parking handshake");
assert.match(taxiDriverLuaSource,
  /function M\.onAutopilotRouteDone\(vehicleId, sessionId, routeRevision\)[\s\S]*?autopilot:onRouteDone[\s\S]*?function M\.onAiRouteDone/,
  "Final native Route Done must immediately start the parked AI handoff");
assert.match(taxiDriverLuaSource,
  /local function beginSearching[\s\S]*?autopilot:isEnabled\(\)[\s\S]*?autopilot:park\(vehicle, "searchingWithoutRoute"\)/,
  "Searching without an active order must never leave the previous AI route running");
assert.match(taxiDriverLuaSource,
  /updateTripCooldowns[\s\S]*?trip_cancelled_by_passenger[\s\S]*?beginSearching\("Passenger cancelled the order"\)[\s\S]*?beginSearching\("Passenger did not arrive"\)/,
  "Passenger cancellation and no-show events must use the parked search transition");
assert.doesNotMatch(autopilotLuaSource, /taxiDriverAutopilotRecovery\.start|allowReverse|spatialGraph|routeForwardTurn/,
  "No custom maneuver controller may remain reachable from the player AI service");
if (false) {
assert.match(autopilotLuaSource, /stuckDelay\s*=\s*15[\s\S]*?signalRequiresStop[\s\S]*?beginRecovery/,
  "Autopilot must distinguish signal waits before starting stuck recovery");
assert.doesNotMatch(autopilotLuaSource, /ai\.setAvoidCars\(\\"off\\"\)/,
  "Adaptive recovery must not disable BeamNG collision avoidance");
assert.match(autopilotLuaSource, /enableElectrics=true[\s\S]*?signal=%d/,
  "Autopilot must enable graph-aware indicators and pass the adaptive maneuver signal");
assert.match(autopilotRecoveryLuaSource,
  /setSignal\(direction\)[\s\S]*?electrics\.set_left_signal[\s\S]*?electrics\.set_right_signal/,
  "The local maneuver controller must operate the appropriate indicator");
assert.match(autopilotLuaSource,
  /perception:planLocalBypass\(vehicle, runtime\.followLeadId,\s*\{[\s\S]*?referencePoints[\s\S]*?taxiDriverAutopilotRecovery\.start/,
  "Recovery must use the independent adaptive corridor planner");
assert.match(autopilotLuaSource,
  /recovery_waiting_for_lead_vehicle[\s\S]*?waitingObstacle[\s\S]*?allowReverse=false/,
  "Recovery must wait for traffic, retry static obstacles, and keep adaptive paths forward-only");
assert.match(autopilotLuaSource,
  /routeNeedsLocalRejoin[\s\S]*?route_rejoin_requested[\s\S]*?beginRecovery\(vehicle, target, distance\)/,
  "A large low-speed graph offset must start a forward local rejoin before the car hits a boundary");
assert.match(autopilotPerceptionLuaSource,
  /scanSpaceFan[\s\S]*?evaluateSurface[\s\S]*?evaluateCandidate[\s\S]*?buildCandidate/,
  "Adaptive bypasses must evaluate free-space rays, traversable surfaces, vehicle dimensions and smooth recovery paths");
assert.match(autopilotPerceptionLuaSource,
  /routeForwardTurn[\s\S]*?directionCount,\s*rings\s*=\s*12,\s*\{6,\s*13,\s*22,\s*32\}[\s\S]*?iterations\s*<\s*140/,
  "Recovery must prefer driveable forward arcs and keep the synchronous fallback graph tightly bounded");
assert.match(autopilotPerceptionLuaSource,
  /climbableStep[\s\S]*?stepTooHigh[\s\S]*?slopeTooSteep[\s\S]*?crossSlopeTooSteep/,
  "Free-space planning must accept climbable pavements while rejecting steps and slopes unsafe for the vehicle");
assert.match(autopilotPerceptionLuaSource,
  /drawDebug[\s\S]*?drawLine[\s\S]*?drawSphere[\s\S]*?drawTextAdvanced/,
  "AI perception must render its sensor fan, candidate paths, waypoints, and decision label in world space");
assert.match(autopilotPerceptionLuaSource,
  /getDirectionVectorUp[\s\S]*?sensorForwardZ[\s\S]*?sensorLeftZ[\s\S]*?directionZ \* distance/,
  "AI world rays must follow the vehicle's three-dimensional pitch and roll instead of the world horizon");
assert.match(autopilotPerceptionLuaSource, /debugTimer\s*=\s*0\.33/,
  "Strategic free-space rays must refresh at the requested human-reaction interval");
assert.match(autopilotRecoveryLuaSource,
  /rayOrientedBox[\s\S]*?castTrajectoryRay[\s\S]*?scanPredictedTrajectory[\s\S]*?comfortableDistance[\s\S]*?emergencyDistance/,
  "Vehicle safety must ray-test straight and curved trajectories with smooth and emergency braking");
assert.match(autopilotRecoveryLuaSource,
  /safetyStepSeconds\s*=\s*0\.05[\s\S]*?pointApproachSafetyTimer[\s\S]*?nearbyOverride/,
  "Collision and point-approach raycasts must use independent fixed-rate timers and shared object snapshots");
assert.match(autopilotRecoveryLuaSource,
  /ensureDriveReady[\s\S]*?setIgnitionLevel[\s\S]*?setStarter/,
  "AI activation must explicitly start and verify the selected vehicle powertrain");
assert.match(autopilotLuaSource, /findLeadVehicle[\s\S]*?followTimeGap[\s\S]*?followComfortableDeceleration[\s\S]*?applySpeedCap/,
  "Normal autopilot must synchronize to lead traffic with an early comfortable braking envelope");
assert.doesNotMatch(autopilotLuaSource,
  /runtime\.laneChangeTimer\s*>\s*0[\s\S]{0,180}runtime\.followSpeedCap\s*=\s*nil/,
  "Starting a lane change must not remove the lead-vehicle braking envelope prematurely");
assert.match(autopilotLuaSource, /findUpcomingSignal[\s\S]*?yellowDecisionDeceleration[\s\S]*?signalSpeedCap/,
  "Normal autopilot must apply an explicit braking envelope for red and stoppable yellow signals");
assert.match(autopilotLuaSource, /directApproachDistance[\s\S]*?controllerMode = "approach"[\s\S]*?stopAtEnd=true/,
  "Autopilot must bridge the gap between a graph endpoint and the exact gameplay trigger");
assert.match(autopilotLuaSource,
  /function service:onRouteDone[\s\S]*?route_done_before_target[\s\S]*?beginDirectApproach\(vehicle, target, distance\)/,
  "Native Route Done must start the exact final approach immediately");
assert.match(autopilotLuaSource, /target\.exactApproach == true and 1\.25/,
  "Fuel detours must use a collision-sized final radius instead of the normal arrival radius");
assert.match(autopilotRecoveryLuaSource, /onAutopilotRouteDone[\s\S]*?AIStatusChange[\s\S]*?route done/,
  "The vehicle observer must report native Route Done immediately instead of waiting for a stuck timeout");
assert.match(autopilotRecoveryLuaSource,
  /ensureArcadeMode[\s\S]*?gearboxBehavior ~= "arcade"[\s\S]*?setGearboxMode\("arcade"\)[\s\S]*?enabled == gearboxOverrideActive/,
  "AI control must apply Arcade idempotently and leave it enabled after releasing control");
assert.doesNotMatch(autopilotRecoveryLuaSource, /shiftToGearIndex/,
  "AI control must not use direct gear selection because BeamNG switches Arcade manuals back to Realistic");
assert.match(autopilotRecoveryLuaSource,
  /updateStationaryDriveHold[\s\S]*?gearIndex > 0[\s\S]*?input\.event\("throttle", 0\.03[\s\S]*?input\.event\("brake", 1/,
  "Stopped native AI must remain in D under the service brake instead of cycling through N");
assert.match(autopilotRecoveryLuaSource,
  /local reverseDrive[\s\S]*?input\.event\("throttle", reverseStop[\s\S]*?input\.event\("brake", reverseStop > 0 and 0 or reverseDrive/,
  "Reverse recovery must use Arcade pedal semantics so BeamNG operates the clutch itself");
assert.match(autopilotLuaSource, /intersectionClearDistance[\s\S]*?intersection_committed/,
  "Signal enforcement must end after the stop line while an intersection maneuver is being cleared");
assert.match(autopilotLuaSource, /forwardLanes < 2[\s\S]*?laneChangeFreeBehind[\s\S]*?overtake_lane_change_started/,
  "Congestion overtakes must use only a verified free lane in the same direction");
assert.match(persistenceLuaSource, /aiDriver\s*=\s*taxiConfig\.sanitizeAiDriver\(nil\)/,
  "AI driver controls must use the centralized preset defaults");
assert.match(configLuaSource,
  /aiDriverPresets\s*=\s*\{[\s\S]*?novice[\s\S]*?cautious[\s\S]*?balanced[\s\S]*?assertive[\s\S]*?racer/,
  "AI driver settings must provide a progression of ready-made presets");
assert.match(configLuaSource,
  /sanitizeAiDriver[\s\S]*?aggressionPercent[\s\S]*?followingTimeGap[\s\S]*?minimumFollowingDistance[\s\S]*?brakingDeceleration[\s\S]*?trafficWaitSeconds[\s\S]*?laneDiscipline[\s\S]*?strictGpsRoute/,
  "AI driver settings must sanitize only controls implemented by the stock AI adapter");
assert.match(autopilotLuaSource,
  /function service:configure\(profile\)[\s\S]*?runtime\.profile[\s\S]*?minimumFollowingDistance[\s\S]*?trafficWaitSeconds/,
  "Saved stock AI controls must configure the active autopilot service");
assert.match(appHtmlSource,
  /settingsSections\.aiDriver[\s\S]*?aiPreset_[\s\S]*?strictGpsRoute[\s\S]*?settings\.aiDriver\.preset === 'custom'[\s\S]*?aiTrafficAwareness[\s\S]*?minimumFollowingDistance[\s\S]*?trafficWaitSeconds[\s\S]*?laneDiscipline/,
  "Settings must expose monolithic presets and only implemented stock AI controls in Custom mode");
assert.match(autopilotLuaSource,
  /strictGpsRoute[\s\S]*?readNativeRoute\(\)[\s\S]*?routeSource[\s\S]*?"gps"/,
  "Strict GPS mode must feed the exact displayed route node sequence to native AI");
assert.match(taxiDriverLuaSource,
  /onRecalculatedRoute[\s\S]*?strictGpsRoute[\s\S]*?autopilot:markRouteDirty/,
  "A GPS reroute must atomically replace the active strict AI path");
assert.doesNotMatch(configLuaSource, /automaticFuelStopPercent|automaticElectricStopPercent|isCriticalEnergy/,
  "Low energy must not create an automatic fuel detour");
assert.doesNotMatch(taxiDriverLuaSource, /automaticStopDeferred|resumeAutopilotAtStation|isCriticalEnergy/,
  "Autopilot must never redirect itself to fuel or resume there without an explicit driver action");
assert.match(taxiDriverLuaSource,
  /function realisticFuel\.beginDetour[\s\S]*?autopilot:isEnabled\(\)[\s\S]*?autopilot:disable\(activeVehicle, "fuelStopRequested"\)/,
  "Refuel must release an active AI driver so the player explicitly enables it on the fuel screen");
assert.match(autopilotRecoveryLuaSource, /input\.event\("steering"[\s\S]*?input\.event\("throttle"[\s\S]*?onAutopilotBypassComplete/,
  "The opposing-lane bypass must steer independently and hand control back to route AI");
assert.match(autopilotLuaSource, /restoreNormal[\s\S]*?issueRoute\(vehicle, target\)/,
  "Successful bypass must restore the safe route profile");
}
assert.match(shiftTrackerLuaSource, /function service:finish\(\)/,
  "Shift lifecycle must remain isolated in shiftTracker.lua");
assert.match(shiftHistoryLuaSource, /shiftshistory\.json[\s\S]*?snapshotInterval\s*=\s*60/,
  "Restorable shifts must persist separately and checkpoint once per minute");
assert.match(shiftHistoryLuaSource, /setEnergyStorageEnergy[\s\S]*?core_vehicles\.replaceVehicle/,
  "Restoring a shift must replace the selected vehicle and then restore its energy storage");
assert.match(shiftHistoryLuaSource, /function M\.pruneUnavailable\(\)[\s\S]*?table\.remove\(history\.shifts/,
  "Shift history must remove vehicles that are no longer installed");
assert.match(shiftHistoryLuaSource, /entry\.summary\.rides > 0[\s\S]*?persisted\.shifts/,
  "Zero-ride shifts must never be written to shift history");
assert.match(appHtmlSource, /profileTab === 'shifts'[\s\S]*?hud\.resumeShift\(shift\.id\)/,
  "Profile shift cards must restore the selected saved vehicle");
assert.match(persistenceLuaSource, /orderRating[\s\S]*?usedAutopilot[\s\S]*?aiRideHistory/,
  "Ride history must preserve customer scores and AI-assisted trip analytics");
assert.equal(Object.keys(localeData["zh-CN"] || {}).length, Object.keys(localeData.en).length,
  "Simplified Chinese must cover every interface translation key");
assert.deepEqual(Object.keys(localeData["zh-CN"]).sort(), Object.keys(localeData.en).sort(),
  "Simplified Chinese and English locale keys must remain in sync");
assert.match(tripEventsLuaSource, /function M\.calculateTip\(/,
  "Trip event rules must expose deterministic tip calculation");
assert.match(configLuaSource,
  /randomEventDefaults[\s\S]*?cancellation[\s\S]*?destinationChange[\s\S]*?additionalStop[\s\S]*?tip[\s\S]*?fragileCargo[\s\S]*?policeCheck/,
  "Every current random event must have a sanitized independent probability");
assert.match(configLuaSource,
  /policeCheck\s*=\s*\{enabled\s*=\s*false[\s\S]*?preloadConfirmed[\s\S]*?key\s*==\s*["']policeCheck["'][\s\S]*?enabled\s*=\s*false/,
  "Police vehicle preloading must be opt-in, including for settings saved before the warning existed");
assert.match(appHtmlSource,
  /settingsSections\.randomEvents[\s\S]*?randomEventOptions[\s\S]*?chancePercent/,
  "Settings must expose an independent switch and probability slider for every random event");
assert.match(appHtmlSource,
  /policeCheckConfirmOpen[\s\S]*?policeCheckEnableDesc[\s\S]*?cancelPoliceCheckEnable[\s\S]*?confirmPoliceCheckEnable/,
  "Enabling the police event must require an explicit preload warning confirmation");
assert.match(taxiDriverLuaSource,
  /pickupRadius\s*=\s*trip\.isDelivery[\s\S]*?runtimeConfig\.passengerPickupRadius[\s\S]*?not trip\.isDelivery and not passengerNoShow then beginBoarding\(\)/,
  "Passenger pickup must use the dedicated logical trigger while physical pickup remains delivery-only");
assert.match(configLuaSource, /passengerPickupRadius\s*=\s*10/,
  "The logical passenger pickup trigger must be exactly ten metres");
assert.match(taxiDriverLuaSource,
  /if trip\.isDelivery then physicalPickup:start\(trip\) else physicalPickup:clear\(\) end/,
  "Passenger jobs must never spawn the physical dummy");
assert.doesNotMatch(physicalPickupLuaSource, /unicycle|playerController|passengerInsideTaxi|pickupHonk/,
  "The physical pickup module must not retain the walking passenger or horn workflow");
assert.match(physicalPickupLuaSource, /cardboard_box[\s\S]*?order\.isDelivery ~= true/,
  "Physical pickup must be limited to the optional delivery cargo prop");
assert.doesNotMatch(telemetryLuaSource, /pickupHonk|startPickupHonk|stopPickupHonk/,
  "Vehicle telemetry must not retain the removed beep-beep sequencer");
assert.match(taxiDriverLuaSource,
  /waitingNoShowAtPickup[\s\S]*?setVehicleForcedStop\(vehicle, true\)[\s\S]*?autopilot:suspend[\s\S]*?waitingNoShowAtPickup/,
  "AI must stop and suspend while a no-show passenger event resolves at the pickup point");
if (false) {
assert.match(autopilotLuaSource,
  /target\.simpleApproach\s*==\s*true[\s\S]*?strategy\s*=\s*"simplePickup"[\s\S]*?completionRadius\s*=\s*config\.stopDistance/,
  "Pickup approach must avoid the expensive predictive graph and stop before the physical passenger");
assert.match(autopilotLuaSource,
  /signedLateral[\s\S]*?routeLane[\s\S]*?laneDelta[\s\S]*?speedCapFallRate[\s\S]*?filteredSpeedCap/,
  "Normal driving must prioritize the active lane and smooth transient speed caps");
assert.match(autopilotLuaSource,
  /ai\.setSpeedMode\("limit"\)[\s\S]*?getSpeedLimitKmh[\s\S]*?legalSpeedCap/,
  "Speed-limit-aware presets must enforce the current road limit explicitly");
assert.match(autopilotPerceptionLuaSource,
  /smoothDriveablePolyline[\s\S]*?turningRadius[\s\S]*?math\.tan\(angle\s*\*\s*0\.5\)[\s\S]*?graphAccess/,
  "Predictive route points must be rounded using a vehicle-sized turning radius");
assert.match(autopilotLuaSource,
  /route_turn_signal_started[\s\S]*?upcomingRouteTurn[\s\S]*?turnSignalSeconds[\s\S]*?junctionPassed/,
  "AI route transitions must signal predictively and cancel the indicator after the junction");
}
assert.match(configLuaSource, /aiDriverDefaults\s*=\s*\{[\s\S]*?enabled\s*=\s*false/,
  "AI Driver must be opt-in for new and upgraded settings");
assert.match(appHtmlSource,
  /aiDriverEnabled[\s\S]*?ng-model=["']settings\.aiDriver\.enabled["'][\s\S]*?aiDriverToggleChanged[\s\S]*?aiDriverConfirmOpen[\s\S]*?confirmAiDriverEnable/,
  "AI Driver controls must be gated by an explicit experimental confirmation");
assert.match(taxiDriverLuaSource,
  /function M\.toggleAutopilot\(\)[\s\S]*?userSettings\.aiDriver\.enabled ~= true[\s\S]*?return false/,
  "Lua must reject AI Driver activation while the master feature is disabled");
assert.match(taxiDriverLuaSource,
  /updateNextOfferLifetime[\s\S]*?clearNextOffer\(\)[\s\S]*?scheduleNextOfferRetry\(\)[\s\S]*?offer_closed_by_guard/,
  "An expired proposed order must schedule another offer during the same ending trip");
assert.match(taxiDriverLuaSource,
  /function M\.dismissNextOffer[\s\S]*?clearNextOffer\(\)[\s\S]*?scheduleNextOfferRetry\(\)[\s\S]*?offer_dismissed_by_driver/,
  "Dismissing one proposed order must leave the remaining-trip offer queue active");
assert.doesNotMatch(
  taxiDriverLuaSource.match(/local function updateNextOfferLifetime[\s\S]*?(?=local function recordNextOfferError)/)?.[0] || "",
  /nextOfferDisabled\s*=\s*true/,
  "An ordinary offer timeout must not disable the remaining-trip offer queue");
assert.match(policeCheckLuaSource,
  /createPoliceGroup[\s\S]*?Config Type[\s\S]*?preloadGroupName[\s\S]*?gap\s*=\s*1000[\s\S]*?instant\s*=\s*false/,
  "Police checks must preselect installed police content and preload it through a yielding job");
assert.match(policeCheckLuaSource,
  /_activatePreparedPolice[\s\S]*?500\s*\+\s*math\.random\(\)\s*\*\s*100[\s\S]*?setActive[\s\S]*?_beginPursuit[\s\S]*?setupPursuitGameplay/,
  "A prepared police unit must appear 500-600 metres away and enter BeamNG's native pursuit flow");
assert.match(vehicleHistoryLuaSource, /if completedRides > 0 then table\.insert\(result\.vehicles/,
  "Vehicles with zero completed rides must not be persisted in history");
const mainChunkLocalCount = taxiDriverLuaSource.split(/\r?\n/).reduce((count, line) => {
  if (!line.startsWith("local ")) return count;
  if (line.startsWith("local function ")) return count + 1;
  const declaration = line.slice(6).split("=", 1)[0];
  return count + declaration.split(",").filter(Boolean).length;
}, 0);
assert.ok(mainChunkLocalCount < 199,
  `taxiDriver.lua has ${mainChunkLocalCount} main-chunk locals and is too close to LuaJIT's 200-local limit`);
assert.ok(taxiDriverLuaSource.split(/\r?\n/).length < 4200,
  "taxiDriver.lua must remain an orchestrator instead of absorbing extracted domain modules again");
const { server, port } = await startHarnessServer(41735);
const browser = await chromium.launch({ headless: true });

const scenarios = [
  "home", "shiftHistory", "fleet", "fleetTrip", "orders", "trip", "delivery", "overspeed", "boarding", "forcedExit",
  "settings", "settingsAi", "settingsEvents", "settingsFleet", "settingsConnection", "profile", "profileVehicles", "profileShifts", "compact", "nextOffer", "fuelRoute", "fuel", "magicFuel",
];
const viewports = [
  { width: 320, height: 568 },
  { width: 360, height: 640 },
  { width: 390, height: 844 },
  { width: 520, height: 900 },
  { width: 768, height: 1024 },
  { width: 844, height: 390 },
  { width: 1024, height: 768 },
];
const locales = ["de", "en", "es", "fr", "it", "pl", "ru", "uk", "zh-CN"];
const baselineScreenshots = new Set([
  "web-home-390x844.png",
  "web-orders-1024x768.png",
  "game-trip-320x568.png",
  "game-trip-360x640.png",
  "web-trip-320x568.png",
  "web-trip-360x640.png",
  "web-trip-390x844.png",
  "web-fuelRoute-390x844.png",
  "game-compact-320x568.png",
  "web-settingsConnection-1024x768.png",
  "web-settingsAi-390x844.png",
  "web-settingsEvents-390x844.png",
  "web-settingsFleet-390x844.png",
  "web-fleet-390x844.png",
  "game-fleet-520x900.png",
  "game-fleetTrip-520x900.png",
  "web-fleetTrip-390x844.png",
  "web-profile-768x1024.png",
  "web-profileVehicles-768x1024.png",
  "web-profileShifts-768x1024.png",
  "web-magicFuel-390x844.png",
  "web-forcedExit-390x844.png",
  "web-fuel-390x844.png",
  "web-extreme-home-390x844.png",
  "web-extreme-shiftHistory-390x844.png",
  "web-extreme-orders-1024x768.png",
  "web-extreme-trip-390x844.png",
  "web-extreme-fleet-390x844.png",
  "game-extreme-compact-320x568.png",
  "hidpi-trip-390x844@2x.png",
  "external-loader-844x390.png",
]);

const harnessUrl = (scenario, viewport, options = {}) => {
  const query = new URLSearchParams({
    scenario,
    width: String(viewport.width),
    height: String(viewport.height),
  });
  if (options.external) {
    query.set("external", "1");
    query.set("token", "0123456789abcdef0123");
  }
  if (options.locale) query.set("locale", options.locale);
  if (options.uiScale !== undefined) query.set("uiScale", String(options.uiScale));
  if (options.mockWebAudio) query.set("mockWebAudio", "1");
  if (options.extreme) query.set("extreme", "1");
  query.set("motion", options.motion ? "1" : "0");
  if (options.realistic !== undefined) query.set("realistic", options.realistic ? "1" : "0");
  if (options.events !== undefined) query.set("events", options.events ? "1" : "0");
  if (options.unlimitedRoutes !== undefined) {
    query.set("unlimitedRoutes", options.unlimitedRoutes ? "1" : "0");
  }
  return `http://127.0.0.1:${port}/?${query}`;
};

const waitForHarness = async (page) => {
  await page.waitForFunction(() => window.__taxiHarnessReady === true);
  await page.evaluate(() => document.fonts && document.fonts.ready);
  await page.evaluate(() => new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve))
  ));
  if (new URL(page.url()).searchParams.get("external") === "1") {
    await page.waitForFunction(() => {
      const canvas = Array.from(document.querySelectorAll("canvas.taxi-external-minimap"))
        .find((item) => item.getBoundingClientRect().width > 20);
      if (!canvas) return true;
      const rect = canvas.getBoundingClientRect();
      const ratio = Math.min(2, window.devicePixelRatio || 1);
      return canvas.width + 1 >= rect.width * ratio && canvas.height + 1 >= rect.height * ratio;
    });
  }
};

const assertVisualAudit = async (page, label) => {
  const audit = await page.evaluate(() => window.__taxiVisualAudit());
  assert.deepEqual(audit.failures, [], `${label}: ${audit.failures.join(", ")}`);
};

const screenshot = async (page, name, dpr = 1) => {
  const data = await page.screenshot({ path: path.join(artifacts, name) });
  if (dpr > 1) {
    const width = data.readUInt32BE(16);
    const height = data.readUInt32BE(20);
    const viewport = page.viewportSize();
    assert.equal(width, viewport.width * dpr, `${name}: HiDPI screenshot width must be native-resolution`);
    assert.equal(height, viewport.height * dpr, `${name}: HiDPI screenshot height must be native-resolution`);
  }
  if (baselineScreenshots.has(name)) {
    const baselinePath = path.join(baselines, name);
    if (process.env.UPDATE_UI_BASELINES === "1") {
      await fs.writeFile(baselinePath, data);
    } else {
      const expected = await fs.readFile(baselinePath).catch(() => null);
      assert.ok(expected, `${name}: baseline is missing; run with UPDATE_UI_BASELINES=1`);
      const result = comparePng(data, expected, { threshold: 0.2, maxDiffPixelRatio: 0.015 });
      if (result && result.diff) await fs.writeFile(path.join(artifacts, `${name}.diff.png`), result.diff);
      assert.equal(result, null, `${name}: ${result && result.errorMessage}`);
    }
  }
  return data;
};

try {
  let visualCount = 0;

  for (const external of [false, true]) {
    for (const viewport of viewports) {
      const page = await browser.newPage({ viewport });
      for (const scenario of scenarios) {
        await page.goto(harnessUrl(scenario, viewport, { external }));
        await waitForHarness(page);
        if (scenario === "settingsConnection" && external) {
          await page.waitForFunction(() => {
            const target = document.querySelector(".taxi-lan__qr-code");
            const image = target && target.querySelector("img");
            const canvas = target && target.querySelector("canvas");
            return Boolean(
              (image && image.complete && image.naturalWidth > 0) ||
              (canvas && canvas.width > 0 && canvas.height > 0)
            );
          });
        }
        await assertVisualAudit(page, `${external ? "web" : "game"} ${scenario} ${viewport.width}x${viewport.height}`);
        if (external) {
          assert.equal(await page.locator(".taxi-shell__toggle").count(), 0,
            "External Web UI must not expose the Minimize control");
        }
        const prefix = external ? "web" : "game";
        await screenshot(page, `${prefix}-${scenario}-${viewport.width}x${viewport.height}.png`);
        visualCount += 1;
      }
      await page.close();
    }
  }

  const extremeStates = [
    { scenario: "home", viewport: { width: 390, height: 844 }, external: true },
    { scenario: "shiftHistory", viewport: { width: 390, height: 844 }, external: true },
    { scenario: "orders", viewport: { width: 1024, height: 768 }, external: true },
    { scenario: "trip", viewport: { width: 390, height: 844 }, external: true },
    { scenario: "fleet", viewport: { width: 390, height: 844 }, external: true },
    { scenario: "compact", viewport: { width: 320, height: 568 }, external: false },
  ];
  for (const stress of extremeStates) {
    const page = await browser.newPage({ viewport: stress.viewport });
    await page.goto(harnessUrl(stress.scenario, stress.viewport, {
      external: stress.external, extreme: true,
    }));
    await waitForHarness(page);
    await assertVisualAudit(page,
      `extreme ${stress.external ? "web" : "game"} ${stress.scenario} ${stress.viewport.width}x${stress.viewport.height}`);
    if (stress.scenario === "home") {
      const formatterAudit = await page.evaluate(() => {
        const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
        return {
          exactCount: scope.formatCount(193),
          boundedCount: scope.formatCount(1000),
          compactMoney: scope.formatMoney(9876543.21),
          signedMoney: scope.formatMoneyFull(-91.26),
          historyBadge: document.querySelector(".taxi-shift-history-button .taxi-count-badge")?.textContent.trim(),
        };
      });
      assert.equal(formatterAudit.exactCount, "193", "A three-digit shift count must remain exact");
      assert.equal(formatterAudit.boundedCount, "999+", "Four-digit counts must use a bounded badge");
      assert.equal(formatterAudit.compactMoney, "$9.88M", "Large aggregates must use compact K/M notation");
      assert.equal(formatterAudit.signedMoney, "−$91.26", "Negative money must place the sign before the currency symbol");
      assert.equal(formatterAudit.historyBadge, "193", "The Home history badge must visibly fit 193");
    }
    const prefix = stress.external ? "web" : "game";
    await screenshot(page,
      `${prefix}-extreme-${stress.scenario}-${stress.viewport.width}x${stress.viewport.height}.png`);
    visualCount += 1;
    await page.close();
  }

  const motionPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await motionPage.goto(harnessUrl("home", { width: 390, height: 844 }, {
    external: true, motion: true,
  }));
  await waitForHarness(motionPage);
  const homeMotion = await motionPage.evaluate(() => {
    const home = getComputedStyle(document.querySelector(".taxi-home"));
    const start = getComputedStyle(document.querySelector(".taxi-start"), "::after");
    const infinite = document.getAnimations().filter((animation) =>
      animation.effect && animation.effect.getTiming().iterations === Infinity
    ).length;
    return {
      pageName: home.animationName,
      pageDuration: home.animationDuration,
      sheenName: start.animationName,
      sheenDuration: start.animationDuration,
      sheenIterations: start.animationIterationCount,
      infinite,
    };
  });
  assert.equal(homeMotion.pageName, "taxi-flat-page-in", "Parked screens must use the shared flat entry motion");
  assert.equal(homeMotion.pageDuration, "0.2s", "Screen entry must stay within the 200 ms comfort budget");
  assert.equal(homeMotion.sheenName, "taxi-start-sheen", "New shift must receive the startup sheen");
  assert.equal(homeMotion.sheenDuration, "0.68s", "The startup sheen must stay brief");
  assert.equal(homeMotion.sheenIterations, "1", "The startup sheen must never loop while idle");
  assert.equal(homeMotion.infinite, 0, "The idle Home screen must not contain infinite decorative animations");
  await motionPage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope && scope.newShiftSheenActive === false;
  });
  await motionPage.locator(".taxi-appbar__settings").click();
  await motionPage.waitForFunction(() => document.querySelector(".taxi-settings"));
  const closedGroup = motionPage.locator(".taxi-settings__group:not(.taxi-settings__group--open) .taxi-settings__group-head").first();
  await closedGroup.click();
  const disclosure = await motionPage.locator(".taxi-settings__group--open .taxi-settings__group-body").last()
    .evaluate((element) => {
      const style = getComputedStyle(element);
      return { name: style.animationName, duration: style.animationDuration };
    });
  assert.equal(disclosure.name, "taxi-flat-disclosure-in", "Accordion bodies must use the shared disclosure motion");
  assert.equal(disclosure.duration, "0.16s", "Accordion motion must remain short");
  await motionPage.locator(".taxi-appbar__settings").click();
  await motionPage.waitForFunction(() => document.querySelector(".taxi-start"));
  assert.equal(await motionPage.locator(".taxi-start").evaluate((element) =>
    getComputedStyle(element, "::after").animationName
  ), "none", "Returning from Settings must not replay the New shift sheen");
  await motionPage.close();

  const reducedMotionPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await reducedMotionPage.emulateMedia({ reducedMotion: "reduce" });
  await reducedMotionPage.goto(harnessUrl("home", { width: 390, height: 844 }, { external: true, motion: true }));
  await waitForHarness(reducedMotionPage);
  assert.equal(await reducedMotionPage.locator(".taxi-start").evaluate((element) =>
    getComputedStyle(element, "::after").animationName
  ), "none", "Reduced-motion users must not receive the startup sheen");
  const reducedMotionScenarios = [
    { scenario: "settingsAi", selectors: [".taxi-settings", ".taxi-settings__group-body"] },
    { scenario: "nextOffer", selectors: [".taxi-trip-layout", ".taxi-next-offer__card"] },
    { scenario: "overspeed", selectors: [".taxi-trip-layout", ".taxi-map__speed--warning"] },
    { scenario: "compact", selectors: [".taxi-compact"] },
  ];
  for (const item of reducedMotionScenarios) {
    await reducedMotionPage.goto(harnessUrl(item.scenario, { width: 390, height: 844 }, {
      external: item.scenario !== "compact", motion: true,
    }));
    await waitForHarness(reducedMotionPage);
    const audit = await reducedMotionPage.evaluate((selectors) => ({
      running: document.getAnimations().length,
      animated: selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)))
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0 && getComputedStyle(element).animationName !== "none";
        })
        .map((element) => `${element.className}:${getComputedStyle(element).animationName}`),
    }), item.selectors);
    assert.equal(audit.running, 0, `${item.scenario}: reduced motion must stop every active animation`);
    assert.deepEqual(audit.animated, [], `${item.scenario}: reduced motion left animated components`);
  }
  await reducedMotionPage.goto(harnessUrl("settingsAi", { width: 390, height: 844 }, {
    external: true, motion: true,
  }));
  await waitForHarness(reducedMotionPage);
  await reducedMotionPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => scope.hud.requestAiDriverToggle());
  });
  assert.equal(await reducedMotionPage.locator(".taxi-offline-confirm__card").evaluate((element) =>
    getComputedStyle(element).animationName
  ), "none", "Reduced motion must disable modal entry animation");
  await reducedMotionPage.close();

  const nativeHeartbeatPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await nativeHeartbeatPage.goto(harnessUrl("home", { width: 390, height: 844 }));
  await waitForHarness(nativeHeartbeatPage);
  await nativeHeartbeatPage.evaluate(() => {
    window.__taxiEngineLuaCommands = [];
    window.dispatchEvent(new Event("blur"));
  });
  await nativeHeartbeatPage.waitForTimeout(2700);
  assert.equal(await nativeHeartbeatPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).filter((command) => command.includes("hudClientHeartbeat")).length
  ), 0, "Native HUD must not queue heartbeats while the game window is unavailable");
  await nativeHeartbeatPage.evaluate(() => window.dispatchEvent(new Event("focus")));
  await nativeHeartbeatPage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((command) => command.includes("hudClientHeartbeat"))
  );
  await nativeHeartbeatPage.close();

  const wideSettingsPage = await browser.newPage({ viewport: { width: 1024, height: 768 } });
  await wideSettingsPage.goto(harnessUrl("settingsConnection", { width: 1024, height: 768 }, {
    external: true,
  }));
  await waitForHarness(wideSettingsPage);
  assert.equal(await wideSettingsPage.locator(".taxi-settings__nav button:visible").count(), 9,
    "Wide Settings must keep every category visible in a persistent sidebar");
  assert.equal(await wideSettingsPage.locator(".taxi-settings__group-head:visible").count(), 0,
    "Wide Settings must not duplicate accordion headers beside the sidebar");
  const wideSettingsColumns = await wideSettingsPage.evaluate(() => {
    const nav = document.querySelector(".taxi-settings__nav").getBoundingClientRect();
    const body = document.querySelector(".taxi-settings__group--open .taxi-settings__group-body").getBoundingClientRect();
    return { navRight: nav.right, bodyLeft: body.left };
  });
  assert.ok(wideSettingsColumns.bodyLeft >= wideSettingsColumns.navRight,
    `Wide Settings content must remain independent from its category rail (${JSON.stringify(wideSettingsColumns)})`);
  await wideSettingsPage.locator(".taxi-settings__nav button").filter({ hasText: "General" }).click();
  assert.equal(await wideSettingsPage.locator(".taxi-settings__nav button:visible").count(), 9,
    "Changing a wide Settings section must keep the category sidebar available");
  await wideSettingsPage.close();

  const functionalPage = await browser.newPage({ viewport: { width: 520, height: 900 } });
  await functionalPage.goto(harnessUrl("settingsConnection", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const settingsBoundary = await functionalPage.evaluate(() => {
    const appbar = document.querySelector(".taxi-appbar").getBoundingClientRect();
    const settings = document.querySelector(".taxi-settings").getBoundingClientRect();
    return { appbarBottom: appbar.bottom, settingsTop: settings.top };
  });
  assert.ok(settingsBoundary.settingsTop >= settingsBoundary.appbarBottom - 1,
    `Settings must begin below the complete header (${JSON.stringify(settingsBoundary)})`);
  const openIndicator = functionalPage.locator(".taxi-settings__group--open .taxi-settings__group-head i").last();
  assert.equal((await openIndicator.textContent()).trim(), "-", "An expanded Settings group must show '-'");
  await openIndicator.locator("..").click();
  const collapsedIndicator = functionalPage.locator(".taxi-settings__group-head i").filter({ hasText: "+" }).last();
  assert.equal((await collapsedIndicator.textContent()).trim(), "+", "A collapsed Settings group must show '+'");
  await collapsedIndicator.locator("..").click();

  const lanFailureAudit = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => {
      Object.keys(scope.settingsSections).forEach((key) => { scope.settingsSections[key] = false; });
      scope.settingsSections.connectivity = true;
      scope.state.lan = {
        enabled: false, connected: 0, bridgeReady: 0, address: "127.0.0.1",
        url: "", bridgeError: "No bindable LAN IPv4 address was found"
      };
    });
    return {
      qrCount: document.querySelectorAll(".taxi-lan__qr").length,
      errorText: document.querySelector(".taxi-lan__error")?.textContent.trim() || "",
      statusError: document.querySelector(".taxi-lan__status")?.classList.contains("taxi-lan__status--error") || false,
    };
  });
  assert.equal(lanFailureAudit.qrCount, 0,
    "A failed Connected Phone start must not leave an empty white QR square");
  assert.match(lanFailureAudit.errorText, /No bindable LAN IPv4/);
  assert.equal(lanFailureAudit.statusError, true);

  const aiOptInAudit = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => {
      Object.keys(scope.settingsSections).forEach((key) => { scope.settingsSections[key] = false; });
      scope.settingsSections.aiDriver = true;
      scope.hud.requestAiDriverToggle();
    });
    return {
      enabledBeforeConfirmation: scope.settings.aiDriver.enabled === true,
      confirmationOpen: scope.aiDriverConfirmOpen,
      optionsVisible: document.querySelectorAll(".taxi-settings__ai-options").length,
    };
  });
  assert.deepEqual(aiOptInAudit, {
    enabledBeforeConfirmation: false, confirmationOpen: true, optionsVisible: 0,
  }, "AI Driver must remain disabled until its experimental warning is confirmed");
  const aiDialog = functionalPage.locator(".taxi-ai-confirm");
  assert.equal(await aiDialog.getAttribute("role"), "dialog",
    "Confirmation overlays must expose dialog semantics");
  assert.equal(await aiDialog.getAttribute("aria-modal"), "true",
    "Confirmation overlays must identify themselves as modal");
  await functionalPage.waitForFunction(() =>
    document.activeElement?.classList.contains("taxi-offline-confirm__cancel")
  );
  await functionalPage.keyboard.press("Escape");
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-ai-confirm"));
  assert.equal(await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.settings.aiDriver.enabled;
  }), false, "Escape must cancel the experimental AI confirmation");
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => scope.hud.requestAiDriverToggle());
  });
  await functionalPage.locator(".taxi-ai-confirm .taxi-offline-confirm__confirm").click();
  assert.equal(await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.settings.aiDriver.enabled;
  }), true, "AI Driver confirmation must enable its runtime setting");
  const aiMasterToggle = functionalPage.locator(
    '#taxi-settings-ai-driver input[ng-model="settings.aiDriver.enabled"]'
  );
  assert.equal(await aiMasterToggle.isChecked(), true,
    "AI Driver master toggle must render ON after confirmation");
  await aiMasterToggle.click({ force: true });
  const aiDisableAudit = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return {
      enabled: scope.settings.aiDriver.enabled,
      confirmationOpen: scope.aiDriverConfirmOpen,
      optionsVisible: document.querySelectorAll(".taxi-settings__ai-options").length,
    };
  });
  assert.deepEqual(aiDisableAudit, {
    enabled: false, confirmationOpen: false, optionsVisible: 0,
  }, "Turning AI Driver off must update the model and hide its controls immediately");
  assert.equal(await aiMasterToggle.isChecked(), false,
    "AI Driver master toggle must render OFF after disabling");
  await aiMasterToggle.click({ force: true });
  await functionalPage.locator(".taxi-ai-confirm .taxi-offline-confirm__confirm").click();
  assert.equal(await aiMasterToggle.isChecked(), true,
    "AI Driver master toggle must return ON only after reconfirmation");

  const aiPresetAudit = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => {
      Object.keys(scope.settingsSections).forEach((key) => { scope.settingsSections[key] = false; });
      scope.settingsSections.aiDriver = true;
      scope.settings.aiDriver.strictGpsRoute = true;
      scope.hud.selectAiDriverPreset("balanced");
    });
    const balanced = {
      preset: scope.settings.aiDriver.preset,
      customPanels: document.querySelectorAll(".taxi-settings__custom").length,
      obeySpeedLimits: scope.settings.aiDriver.obeySpeedLimits,
      laneDiscipline: scope.settings.aiDriver.laneDiscipline,
      followingTimeGap: scope.settings.aiDriver.followingTimeGap,
      strictGpsRoute: scope.settings.aiDriver.strictGpsRoute,
    };
    scope.$apply(() => scope.hud.selectAiDriverPreset("custom"));
    const customPanels = document.querySelectorAll(".taxi-settings__custom").length;
    return {
      balanced,
      customPreset: scope.settings.aiDriver.preset,
      customPanels,
      ruleToggles: document.querySelectorAll(
        'input[ng-model="settings.aiDriver.obeySpeedLimits"], input[ng-model="settings.aiDriver.laneDiscipline"]'
      ).length,
      trafficControls: document.querySelectorAll(
        'input[ng-model="settings.aiDriver.followingTimeGap"], input[ng-model="settings.aiDriver.minimumFollowingDistance"], input[ng-model="settings.aiDriver.brakingDeceleration"], input[ng-model="settings.aiDriver.trafficWaitSeconds"]'
      ).length,
      gpsRouteToggles: document.querySelectorAll(
        'input[ng-model="settings.aiDriver.strictGpsRoute"]'
      ).length,
      visualizationToggles: document.querySelectorAll(
        'input[ng-model="settings.aiDecisionVisualization"]'
      ).length,
    };
  });
  assert.deepEqual(aiPresetAudit.balanced, {
    preset: "balanced", customPanels: 0, obeySpeedLimits: true,
    laneDiscipline: true, followingTimeGap: 2.3, strictGpsRoute: true,
  }, "A ready-made AI preset must apply atomically without exposing manual controls");
  assert.equal(aiPresetAudit.customPreset, "custom");
  assert.equal(aiPresetAudit.customPanels, 1,
    "Manual AI controls must appear only after selecting Custom");
  assert.equal(aiPresetAudit.ruleToggles, 2,
    "Speed-limit and lane-discipline controls must remain independent");
  assert.equal(aiPresetAudit.trafficControls, 4,
    "Custom mode must expose only the implemented following and traffic-wait controls");
  assert.equal(aiPresetAudit.gpsRouteToggles, 1,
    "GPS route fidelity must remain available independently from the selected preset");
  assert.equal(aiPresetAudit.visualizationToggles, 0,
    "The obsolete AI decision visualization toggle must not be rendered");

  const settingsRaceAudit = await functionalPage.evaluate(async () => {
    const root = angular.element(document).injector().get("$rootScope");
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    const staleSettings = angular.copy(scope.state.settings);
    scope.$apply(() => scope.hud.selectLanguage("ru"));
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      settings: staleSettings,
    }));
    const languageAfterStalePacket = scope.language;
    await new Promise((resolve) => setTimeout(resolve, 260));
    const savedSettings = angular.copy(scope.settings);
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      settings: savedSettings,
    }));
    const languageAfterAcknowledgement = scope.language;
    const remoteSettings = Object.assign({}, savedSettings, { language: "de" });
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      settings: remoteSettings,
    }));
    return {
      languageAfterStalePacket,
      languageAfterAcknowledgement,
      languageAfterRemoteUpdate: scope.language,
      saveCommands: (window.__taxiEngineLuaCommands || [])
        .filter((value) => value.includes("saveSettings(")),
    };
  });
  assert.equal(settingsRaceAudit.languageAfterStalePacket, "ru",
    "A stale HUD packet must not roll back a freshly selected setting");
  assert.equal(settingsRaceAudit.languageAfterAcknowledgement, "ru",
    "The Lua acknowledgement must preserve the selected setting");
  assert.equal(settingsRaceAudit.languageAfterRemoteUpdate, "de",
    "A later confirmed setting from another UI client must still synchronize");
  assert.ok(settingsRaceAudit.saveCommands.some((value) => value.includes('language="ru"') ||
    value.includes('"language":"ru"')),
  "The debounced settings save must send the user's selected language to Lua");

  await functionalPage.goto(harnessUrl("profile", { width: 520, height: 1028 }));
  await waitForHarness(functionalPage);
  await functionalPage.waitForFunction(() =>
    document.querySelectorAll(".taxi-review:not(.taxi-review--measure)").length >= 8
  );
  const tallReviewLayout = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    const reviews = Array.from(document.querySelectorAll(".taxi-review:not(.taxi-review--measure)"));
    const pager = document.querySelector(".taxi-profile__pager").getBoundingClientRect();
    return {
      count: reviews.length,
      perPage: scope.reviewsPerPage,
      lastBottom: reviews.at(-1).getBoundingClientRect().bottom,
      pagerTop: pager.top,
    };
  });
  assert.ok(tallReviewLayout.count >= 8 && tallReviewLayout.lastBottom <= tallReviewLayout.pagerTop + 1,
    `Tall review panels must use their available height (${JSON.stringify(tallReviewLayout)})`);
  await functionalPage.evaluate(() => {
    document.documentElement.style.setProperty("--test-height", "640px");
    window.dispatchEvent(new Event("resize"));
  });
  await functionalPage.waitForFunction((previous) => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.reviewsPerPage < previous;
  }, tallReviewLayout.perPage);
  const shortReviewLayout = await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    const reviews = Array.from(document.querySelectorAll(".taxi-review:not(.taxi-review--measure)"));
    const pager = document.querySelector(".taxi-profile__pager").getBoundingClientRect();
    return {
      count: reviews.length,
      perPage: scope.reviewsPerPage,
      lastBottom: reviews.at(-1).getBoundingClientRect().bottom,
      pagerTop: pager.top,
    };
  });
  assert.ok(shortReviewLayout.perPage < tallReviewLayout.perPage &&
    shortReviewLayout.lastBottom <= shortReviewLayout.pagerTop + 1,
  `Review pagination must shrink without overlapping its pager (${JSON.stringify(shortReviewLayout)})`);

  await functionalPage.goto(harnessUrl("settings", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  await functionalPage.locator(".taxi-settings__group--open:nth-of-type(5)").scrollIntoViewIfNeeded();
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => { scope.cheatRating = 2.75; });
  });
  await functionalPage.locator(".taxi-settings__cheat-rating button").first().click();
  await functionalPage.waitForFunction(() => {
    const value = document.querySelector(".taxi-settings__cheat-stats strong");
    return value && value.textContent.trim() === "2.75";
  });
  const command = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("cheatSetRating")) || ""
  );
  assert.match(command, /^taxiDriver_taxiDriver\.cheatSetRating\(["']2\.75["']\)$/,
    "Cheat rating must be sent as a plain Lua statement with a serialized value");
  assert.doesNotMatch(command, /\b(?:if|return)\b/,
    "Cheat rating command must not use callback-incompatible Lua control flow");
  const energySlider = functionalPage.locator(
    '.taxi-settings__cheat-card input[type="range"][max="100"]'
  );
  await energySlider.fill("73");
  await functionalPage.locator(".taxi-settings__cheat-rating button").nth(1).click();
  const energyCommand = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("cheatSetEnergyPercent")) || ""
  );
  assert.equal(energyCommand, "taxiDriver_taxiDriver.cheatSetEnergyPercent(73)",
    "Energy cheat must send the selected tank/battery percentage");

  await functionalPage.goto(harnessUrl("home", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  assert.equal((await functionalPage.locator(".taxi-home__vehicle-copy strong").textContent()).trim(), "ETK 854t",
    "Home screen must show the currently selected vehicle name");
  assert.equal(await functionalPage.locator(".taxi-home__vehicle-preview img").evaluate((image) => image.naturalWidth > 0), true,
    "Home screen must render the selected vehicle preview");
  await functionalPage.locator(".taxi-home__vehicle").click();
  const selectorCommand = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("openVehicleSelector")) || ""
  );
  assert.match(selectorCommand, /taxiDriver_taxiDriver\.openVehicleSelector\(\)/,
    "Clicking the vehicle card must ask Lua to open the native selector");
  assert.equal((await functionalPage.locator(".phone-odometer strong").textContent()).trim(), "0012.8 km",
    "Current-vehicle odometer must use a four-digit, one-decimal metric format");
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => { scope.settings.unitSystem = "imperial"; });
  });
  assert.equal((await functionalPage.locator(".phone-odometer strong").textContent()).trim(), "0008.0 mi",
    "Current-vehicle odometer must convert to the selected imperial unit");
  await functionalPage.locator(".taxi-shift-history-button").click();
  assert.equal(await functionalPage.locator(".taxi-shift-card").count(), 2,
    "Previous Shift must open every valid saved session");
  await functionalPage.locator(".taxi-shift-card").first().click();
  const resumeShiftCommand = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("resumeShift")) || ""
  );
  assert.match(resumeShiftCommand, /taxiDriver_taxiDriver\.resumeShift\(3\)/,
    "Selecting a saved shift must request its vehicle restoration");

  await functionalPage.goto(harnessUrl("orders", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const sortValues = ["fare", "pickup", "duration", "perKm"];
  for (let index = 0; index < sortValues.length; index += 1) {
    await functionalPage.locator(".taxi-sort-menu__trigger").click();
    assert.equal(await functionalPage.locator(".taxi-sort-menu__options button").count(), 4,
      "Order sorting menu must expose all four choices");
    await functionalPage.locator(".taxi-sort-menu__options button").nth(index).click();
    assert.equal(await functionalPage.evaluate(() => {
      const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
      return scope.offerSort;
    }), sortValues[index], `Order sorting choice ${sortValues[index]} must be clickable`);
    assert.equal(await functionalPage.locator(".taxi-sort-menu__options").count(), 0,
      "Order sorting menu must close after selection");
  }

  await functionalPage.goto(harnessUrl("profile", { width: 520, height: 900 }, { external: true }));
  await waitForHarness(functionalPage);
  await functionalPage.locator(".taxi-review-wrap .taxi-review").first().click();
  assert.equal(await functionalPage.locator(".taxi-review-wrap--open").count(), 1,
    "Trip history must expand one selected ride at a time");
  assert.match(await functionalPage.locator(".taxi-review-details").textContent(),
    /Penalties[\s\S]*Speeding[\s\S]*Random events[\s\S]*VIP/,
    "Expanded trip history must show penalties and random-event history");
  assert.equal(await functionalPage.locator(".taxi-review-wrap").count(), 1,
    "Adaptive pagination must reserve the page for an expanded trip");
  await assertVisualAudit(functionalPage, "expanded trip history");

  await functionalPage.goto(harnessUrl("profileVehicles", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  assert.equal(await functionalPage.locator(".taxi-vehicle-history").count(), 3,
    "Vehicle history tab must list every persisted vehicle record");
  assert.match((await functionalPage.locator(".taxi-vehicle-history").filter({ hasText: "ETK 854t" }).textContent()), /ETK 854t[\s\S]*7[\s\S]*\$184\.25/,
    "Vehicle history must show selector name, completed rides, and income");
  const vehicleSortValues = ["distance", "income", "rides"];
  for (let index = 0; index < vehicleSortValues.length; index += 1) {
    await functionalPage.locator(".taxi-vehicle-history__sort .taxi-sort-menu__trigger").click();
    const vehicleSortOptions = functionalPage.locator(
      ".taxi-vehicle-history__sort .taxi-sort-menu__options button"
    );
    assert.equal(await vehicleSortOptions.count(), 3,
      "Vehicle sorting menu must render all choices above the vehicle cards");
    await vehicleSortOptions.nth(index).click();
    assert.equal(await functionalPage.evaluate(() => {
      const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
      return scope.vehicleSort;
    }), vehicleSortValues[index], `Vehicle sorting choice ${vehicleSortValues[index]} must be clickable`);
    assert.equal(await functionalPage.locator(
      ".taxi-vehicle-history__sort .taxi-sort-menu__options"
    ).count(), 0, "Vehicle sorting menu must close after selection");
  }

  for (const realistic of [false, true]) {
    for (const events of [false, true]) {
      for (const unlimitedRoutes of [false, true]) {
        for (const scenario of ["home", "orders", "trip", "delivery", "magicFuel"]) {
          await functionalPage.goto(harnessUrl(scenario, { width: 390, height: 844 }, {
            realistic, events, unlimitedRoutes,
          }));
          await waitForHarness(functionalPage);
          await assertVisualAudit(functionalPage,
            `mode matrix realistic=${realistic} events=${events} unlimited=${unlimitedRoutes} scenario=${scenario}`);
          const settingsState = await functionalPage.evaluate(() => {
            const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
            return {
              realistic: scope.settings.realisticMode === true,
              events: scope.settings.randomEventsEnabled === true,
              unlimitedRoutes: scope.settings.unlimitedRouteDistance === true,
            };
          });
          assert.deepEqual(settingsState, { realistic, events, unlimitedRoutes });
        }
      }
    }
  }

  await functionalPage.goto(harnessUrl("trip", { width: 390, height: 844 }));
  await waitForHarness(functionalPage);
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => { scope.state.fleet.activeDrivers = 0; });
  });
  assert.equal(await functionalPage.locator("button.taxi-map__autopilot").count(), 0,
    "Active trip map must hide AI Driver while the experimental feature is disabled");
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => {
      window.__taxiEngineLuaCommands = [];
      scope.settings.aiDriver.enabled = true;
      scope.state.settings.aiDriver.enabled = true;
      scope.hud.settingsChanged();
    });
  });
  assert.equal(await functionalPage.locator("button.taxi-map__autopilot").count(), 1,
    "Active trip map must expose one autopilot control after opt-in");
  await functionalPage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) => value.includes("setMinimapOcclusions"))
  );
  const minimapOcclusionCommand = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).find((value) => value.includes("setMinimapOcclusions")) || ""
  );
  const minimapOcclusionArgs = /setMinimapOcclusions\(([^)]*)\)/.exec(minimapOcclusionCommand)?.[1]
    .split(",") || [];
  assert.equal(minimapOcclusionArgs.length, 21,
    "Native minimap must receive five complete overlay occlusion rectangles and an explicit Fleet-mode flag");
  assert.ok(minimapOcclusionArgs.slice(12, 16).map(Number).every((value) => Number.isFinite(value) && value > 0),
    "Autopilot control must reserve a visible native-minimap occlusion rectangle");
  assert.ok(minimapOcclusionArgs.slice(16, 20).map(Number).every((value) => Number.isFinite(value) && value > 0),
    "The Fleet shortcut must reserve a visible native-map occlusion even when no driver is hired");
  assert.equal(minimapOcclusionArgs[20].trim(), "false",
    "A normal trip map must not request inactive Fleet-map privileges");
  await functionalPage.evaluate(() => { window.__taxiEngineLuaCommands = []; });
  await functionalPage.locator("button.taxi-map__autopilot").click();
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("toggleAutopilot")),
  "Autopilot control must call the authoritative Lua controller");
  assert.equal(await functionalPage.locator("button.taxi-map__fleet").count(), 1,
    "An active trip with zero hired drivers must expose the Fleet hiring shortcut");
  assert.equal((await functionalPage.locator("button.taxi-map__fleet span").textContent()).trim(), "0",
    "The Fleet shortcut must explicitly show a zero driver count");
  await functionalPage.locator("button.taxi-map__fleet").click();
  assert.equal(await functionalPage.locator(".taxi-fleet .taxi-minimap-surface").count(), 1,
    "Fleet monitoring must retain a player-centered map during an active trip");
  await functionalPage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) =>
      /setMinimapTransform\([^)]*,\s*true\)/.test(value)
    )
  );
  const fleetOcclusionArgs = await functionalPage.evaluate(() => {
    const command = (window.__taxiEngineLuaCommands || []).findLast((value) =>
      value.includes("setMinimapOcclusions") && value.trim().includes(", true) end")
    ) || "";
    return /setMinimapOcclusions\(([^)]*)\)/.exec(command)?.[1].split(",") || [];
  });
  assert.ok(fleetOcclusionArgs.slice(16, 20).map(Number).every((value) => Number.isFinite(value) && value > 0),
    "Fleet status must reserve its own native-map occlusion and remain above the map texture");
  assert.equal(await functionalPage.locator(".taxi-trip-layout").count(), 0,
    "The Fleet monitor must replace, rather than collide with, the trip sheet");
  await functionalPage.locator(".taxi-fleet__head > button").click();
  assert.equal(await functionalPage.locator(".taxi-trip-layout").count(), 1,
    "Closing Fleet monitoring must return to the still-active trip");
  assert.equal(await functionalPage.locator(".taxi-penalty-log__events").count(), 0,
    "Penalty details must start collapsed");
  await functionalPage.locator("button.taxi-penalty-log__header").click();
  assert.equal(await functionalPage.locator(".taxi-penalty-event").count(), 3,
    "Penalty summary must expand into individual events");

  await functionalPage.goto(harnessUrl("fuelRoute", { width: 390, height: 844 }));
  await waitForHarness(functionalPage);
  assert.equal(await functionalPage.locator("button.taxi-map__autopilot").count(), 0,
    "Fuel detour map must hide AI Driver before opt-in");
  await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    scope.$apply(() => {
      scope.settings.aiDriver.enabled = true;
      scope.state.settings.aiDriver.enabled = true;
    });
  });
  assert.equal(await functionalPage.locator("button.taxi-map__autopilot").count(), 1,
    "Fuel detour map must expose the autopilot control after opt-in");
  await functionalPage.evaluate(() => { window.__taxiEngineLuaCommands = []; });
  await functionalPage.locator("button.taxi-map__autopilot").click();
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("toggleAutopilot")),
  "Fuel detour autopilot control must allow the driver to take control");

  await functionalPage.goto(harnessUrl("trip", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const nativeMapHeight = await functionalPage.locator(".taxi-trip-layout > .taxi-map")
    .evaluate((element) => element.getBoundingClientRect().height);
  assert.ok(nativeMapHeight >= 235 && nativeMapHeight <= 245,
    `Native trip map must use the compact 240px block (${nativeMapHeight}px)`);
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("setMinimapAppVisibility(true)")),
  "Native UI initialization must explicitly release stale Lua map visibility state");
  await functionalPage.evaluate(() => {
    window.__taxiEngineLuaCommands = [];
    const rootScope = angular.element(document).injector().get("$rootScope");
    rootScope.$broadcast("onCefVisibilityChanged", false);
    rootScope.$broadcast("onCefVisibilityChanged", true);
  });
  await functionalPage.waitForFunction(() => {
    const commands = window.__taxiEngineLuaCommands || [];
    return commands.some((value) => value.includes("setMinimapAppVisibility(false)")) &&
      commands.some((value) => value.includes("setMinimapAppVisibility(true)")) &&
      commands.some((value) => value.includes("setMinimapTransform"));
  });
  await functionalPage.evaluate(() => {
    window.__taxiEngineLuaCommands = [];
    angular.element(document).injector().get("$rootScope")
      .$broadcast("TaxiDriverMinimapInvalidated");
  });
  await functionalPage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) => value.includes("setMinimapTransform"))
  );
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("setMinimapTransform")),
  "Returning from a BeamNG menu must republish the native trip-map transform");
  await functionalPage.evaluate(() => window.__taxiSetState({ penaltyEvents: [] }));
  const emptyPenaltyFooter = await functionalPage.evaluate(() => {
    const screen = document.querySelector(".taxi-phone__screen").getBoundingClientRect();
    const footer = document.querySelector(".taxi-ride-footer").getBoundingClientRect();
    const energy = document.querySelector(".taxi-ride-footer__energy").getBoundingClientRect();
    const fuelNotice = document.querySelector(".taxi-trip-notice--fuel");
    return {
      bottomGap: Math.abs(screen.bottom - footer.bottom),
      footerHeight: footer.height,
      energyHeight: energy.height,
      footerPosition: getComputedStyle(document.querySelector(".taxi-ride-footer")).position,
      fuelNoticeDisplay: getComputedStyle(fuelNotice).display,
    };
  });
  assert.equal(emptyPenaltyFooter.footerPosition, "static",
    `Trip footer must remain in normal flow and never cover ride data (${JSON.stringify(emptyPenaltyFooter)})`);
  assert.ok(emptyPenaltyFooter.footerHeight >= 100 && emptyPenaltyFooter.energyHeight >= 36,
    `Fuel status must not collapse with no penalties (${JSON.stringify(emptyPenaltyFooter)})`);
  assert.equal(emptyPenaltyFooter.fuelNoticeDisplay, "none",
    "Native trip UI must not duplicate fuel sufficiency as a separate vertical badge");

  await functionalPage.goto(harnessUrl("compact", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const compactMapHeight = await functionalPage.locator(".taxi-compact__map")
    .evaluate((element) => element.getBoundingClientRect().height);
  assert.ok(compactMapHeight >= 318 && compactMapHeight <= 344,
    `Minimized native map must preserve a compact navigation-first block (${compactMapHeight}px)`);
  await functionalPage.evaluate(() => {
    window.__taxiEngineLuaCommands = [];
    angular.element(document).injector().get("$rootScope")
      .$broadcast("TaxiDriverMinimapInvalidated");
  });
  await functionalPage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) => value.includes("setMinimapTransform"))
  );
  const compactMapCommand = await functionalPage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).findLast((value) => value.includes("setMinimapTransform")) || ""
  );
  assert.match(compactMapCommand, /setMinimapTransform\([^)]*[1-9][0-9]*,\s*false\)/,
    "Minimized native UI must publish a non-empty map rectangle");
  assert.equal(await functionalPage.locator(".taxi-shell__controls button").count(), 2,
    "Minimized native UI must expose separate expand and collapse-to-button controls");
  await functionalPage.locator(".taxi-shell__toggle--super").click();
  assert.equal(await functionalPage.locator(".taxi-shell--super-minimized").count(), 1,
    "The secondary control must enter the button-only stage");
  assert.equal(await functionalPage.locator(".taxi-phone").count(), 0,
    "Button-only mode must remove the full phone");
  assert.equal(await functionalPage.locator(".taxi-compact").count(), 0,
    "Button-only mode must remove the compact map interface");
  assert.equal(await functionalPage.locator(".taxi-shell__controls button").count(), 1,
    "Button-only mode must retain exactly one restore control");
  const superMinimizedBounds = await functionalPage.locator(".taxi-shell__toggle--super")
    .evaluate((element) => {
      const rect = element.getBoundingClientRect();
      return { width: rect.width, height: rect.height };
    });
  assert.ok(superMinimizedBounds.width <= 46 && superMinimizedBounds.height <= 46,
    `Button-only restore control must remain unobtrusive (${JSON.stringify(superMinimizedBounds)})`);
  await assertVisualAudit(functionalPage, "game button-only 520x900");
  await screenshot(functionalPage, "game-button-only-520x900.png");
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("hideMinimap")),
  "Button-only mode must explicitly hide the native minimap");
  await functionalPage.evaluate(() => window.__taxiSetState({
    notification: { id: 9901, key: "notify_orderAccepted", severity: "success" },
  }));
  await functionalPage.waitForFunction(() =>
    document.querySelector(".taxi-shell__notification") !== null
  );
  assert.notEqual(await functionalPage.locator(".taxi-shell__notification").evaluate((element) =>
    getComputedStyle(element).animationIterationCount
  ), "infinite", "Collapsed notifications must use a finite attention pulse");
  assert.equal(await functionalPage.locator(".taxi-shell--super-minimized").count(), 1,
    "A notification must not force button-only mode to expand");
  await functionalPage.locator(".taxi-shell__toggle--super").click();
  assert.equal(await functionalPage.locator(".taxi-compact").isVisible(), true,
    "Super-expand must restore the previously selected compact stage");
  await functionalPage.locator(".taxi-shell__toggle:not(.taxi-shell__toggle--super)").click();
  assert.equal(await functionalPage.locator(".taxi-phone").isVisible(), true,
    "The primary expand control must restore the full interface");

  await functionalPage.goto(harnessUrl("magicFuel", { width: 390, height: 844 }));
  await waitForHarness(functionalPage);
  assert.equal(await functionalPage.locator(".taxi-fuel__magic").isVisible(), true,
    "Missing stations must show an explanatory magic-fuel panel");
  assert.equal(await functionalPage.locator(".taxi-fuel__range").isEnabled(), true,
    "Magic fuel must reuse the ordinary amount slider while stopped");
  await functionalPage.evaluate(() => window.__taxiSetState({
    fuelStation: Object.assign({}, window.__taxiScenarios.magicFuel.fuelStation, { vehicleStopped: false }),
  }));
  await functionalPage.waitForFunction(() =>
    document.querySelector(".taxi-fuel__buy")?.textContent.includes("Keep the vehicle stopped")
  );
  assert.equal(await functionalPage.locator(".taxi-fuel__range").isDisabled(), true,
    "Magic refueling controls must remain locked while the vehicle is moving");

  await functionalPage.goto(harnessUrl("overspeed", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  const sign = functionalPage.locator(".taxi-map__speed");
  await sign.waitFor();
  assert.equal(await sign.evaluate((element) => element.classList.contains("taxi-map__speed--warning")), true,
    "Speed sign must be red above the configured threshold");
  const firstCount = await functionalPage.evaluate(() =>
    window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
  );
  assert.equal(firstCount, 1, "Overspeed alert must play once when entering the warning state");
  await functionalPage.evaluate(() => window.__taxiSetState({ currentSpeed: 59 }));
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-map__speed--warning"));
  await functionalPage.evaluate(() => window.__taxiSetState({ currentSpeed: 72 }));
  await functionalPage.waitForFunction(() => document.querySelector(".taxi-map__speed--warning"));
  const secondCount = await functionalPage.evaluate(() =>
    window.__taxiPlayedSounds.filter((source) => source.includes("taxidriver_overspeed.mp3")).length
  );
  assert.equal(secondCount, 2, "Overspeed alert must play again after returning below the threshold");

  await functionalPage.goto(harnessUrl("settingsEvents", { width: 390, height: 844 }));
  await waitForHarness(functionalPage);
  const policeRow = functionalPage.locator(".taxi-settings__section")
    .filter({ hasText: "Police inspection" });
  const policeToggle = policeRow.locator('input[type="checkbox"]');
  assert.equal(await policeToggle.isChecked(), false,
    "Police inspection must be disabled by default");
  await policeToggle.click({ force: true });
  await functionalPage.locator(".taxi-police-confirm").waitFor();
  assert.equal(await policeToggle.isChecked(), false,
    "The police event must stay disabled until the warning is confirmed");
  await functionalPage.locator(".taxi-police-confirm .taxi-offline-confirm__cancel").click();
  assert.equal(await policeToggle.isChecked(), false,
    "Cancelling the warning must leave police preloading disabled");
  await policeToggle.click({ force: true });
  await functionalPage.locator(".taxi-police-confirm .taxi-offline-confirm__confirm").click();
  assert.equal(await policeToggle.isChecked(), true,
    "Confirming the warning must enable the police event");

  await functionalPage.goto(harnessUrl("orders", { width: 390, height: 844 }));
  await waitForHarness(functionalPage);
  const offlineHold = functionalPage.locator(".taxi-orders__footer .taxi-offline-hold");
  await offlineHold.focus();
  await functionalPage.keyboard.down("Space");
  await functionalPage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.offlineHoldProgress > 0;
  });
  await functionalPage.keyboard.up("Space");
  assert.equal(await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.offlineHoldProgress;
  }), 0, "Offline hold must support keyboard press and release");
  await offlineHold.dispatchEvent("pointerdown", { button: 0, pointerType: "touch" });
  await functionalPage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.offlineHoldProgress > 0;
  });
  await offlineHold.dispatchEvent("pointerup", { button: 0, pointerType: "touch" });
  assert.equal(await functionalPage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.offlineHoldProgress;
  }), 0, "Offline hold must support touch/pointer press and release");

  await functionalPage.goto(harnessUrl("nextOffer", { width: 520, height: 900 }));
  await waitForHarness(functionalPage);
  await functionalPage.evaluate(() => { window.__taxiEngineLuaCommands = []; });
  await functionalPage.locator(".taxi-next-offer__close").click();
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-next-offer"));
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("dismissNextOffer(9)")),
    "The close button must dismiss exactly the displayed queued offer");
  await functionalPage.evaluate(() => {
    window.__taxiEngineLuaCommands = [];
    window.__taxiSetState({ phase: "toDestination", nextOffer: {
      id: 901, passengerName: "Watchdog", accepted: false,
      duration: 5, timeRemaining: 0.15, rideDistance: 1000, estimatedFare: 5,
    } });
  });
  await functionalPage.waitForFunction(() => document.querySelector(".taxi-next-offer"));
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-next-offer"), null, { timeout: 1500 });
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("expireNextOffer(901)")),
    "The local monotonic watchdog must close an offer even when no newer HUD tick arrives");
  await functionalPage.evaluate(() => window.__taxiSetState({ phase: "toDestination", nextOffer: {
    id: 901, passengerName: "Stale watchdog", accepted: false,
    duration: 5, timeRemaining: 5, rideDistance: 1000, estimatedFare: 5,
  } }));
  await functionalPage.waitForTimeout(250);
  assert.equal(await functionalPage.locator(".taxi-next-offer").count(), 0,
    "A stale packet must not flash an already expired offer back onto the screen");
  await functionalPage.evaluate(() => window.__taxiSetState({ phase: "toDestination", nextOffer: {
    id: 902, passengerName: "Second queued offer", accepted: false,
    duration: 5, timeRemaining: 0.15, rideDistance: 1200, estimatedFare: 7,
  } }));
  await functionalPage.waitForFunction(() =>
    document.querySelector(".taxi-next-offer")?.textContent.includes("Second queued offer")
  );
  await functionalPage.waitForFunction(() => !document.querySelector(".taxi-next-offer"), null, { timeout: 1500 });
  assert.ok((await functionalPage.evaluate(() => window.__taxiEngineLuaCommands || []))
    .some((value) => value.includes("expireNextOffer(902)")),
    "A replacement offer must keep its own timer and expire independently");
  await functionalPage.evaluate(() => window.__taxiSetState({ phase: "toDestination", nextOffer: {
    id: 903, passengerName: "Third queued offer", accepted: false,
    duration: 5, timeRemaining: 5, rideDistance: 1400, estimatedFare: 9,
  } }));
  await functionalPage.waitForFunction(() =>
    document.querySelector(".taxi-next-offer")?.textContent.includes("Third queued offer")
  );
  assert.equal(await functionalPage.locator(".taxi-next-offer").count(), 1,
    "The proposed-order slot must continue displaying offers after multiple expirations");
  await functionalPage.close();

  const iphoneAudioPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await iphoneAudioPage.goto(harnessUrl("trip", { width: 390, height: 844 }, {
    external: true, mockWebAudio: true,
  }));
  await waitForHarness(iphoneAudioPage);
  assert.equal(await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.contextsCreated), 0,
    "Mobile AudioContext must not be created before a trusted user gesture");
  assert.equal(await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.decoded), 0,
    "Mobile sound decoding must wait for the first user gesture");
  await iphoneAudioPage.evaluate(() => window.__taxiSetState({ active: false }));
  assert.equal(await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length), 0,
    "External event audio must remain queued until iOS grants a user gesture");
  await iphoneAudioPage.locator(".taxi-appbar__settings").click();
  await iphoneAudioPage.waitForFunction(() => window.__taxiMockWebAudio?.decoded === 7);
  await iphoneAudioPage.waitForFunction(() => window.__taxiMockWebAudio.starts.length >= 2);
  const unlockedStarts = await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length);
  await iphoneAudioPage.evaluate(() => window.__taxiSetState({ active: true }));
  await iphoneAudioPage.waitForFunction((count) => window.__taxiMockWebAudio.starts.length > count, unlockedStarts);
  const burstStart = await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.starts.length);
  await iphoneAudioPage.evaluate(() => {
    window.__taxiSetState({ currentSpeed: 72 });
    window.__taxiSetState({ nextOffer: {
      id: 999, passengerName: "Audio Test", accepted: false, duration: 5, timeRemaining: 5,
    } });
    window.__taxiSetState({ penaltyEvents: [
      ...window.__taxiScenarios.trip.penaltyEvents,
      { id: 999, type: "collision", penaltyPercent: 1, detail: "Audio test" },
    ] });
  });
  await iphoneAudioPage.waitForFunction((count) =>
    window.__taxiMockWebAudio.starts.length >= count + 3, burstStart
  );
  const interruptedStart = await iphoneAudioPage.evaluate(() => {
    window.__taxiMockWebAudio.interrupt();
    window.__taxiSetState({ active: false });
    return window.__taxiMockWebAudio.starts.length;
  });
  await iphoneAudioPage.locator(".taxi-appbar__settings").click();
  await iphoneAudioPage.waitForFunction((count) =>
    window.__taxiMockWebAudio.starts.length > count, interruptedStart
  );
  assert.ok(await iphoneAudioPage.evaluate(() => window.__taxiMockWebAudio.stateChanges >= 2),
    "Mobile audio must observe and recover from Safari's interrupted context state");
  await iphoneAudioPage.close();

  const htmlAudioPage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await htmlAudioPage.goto(harnessUrl("trip", { width: 390, height: 844 }, { external: true }));
  await waitForHarness(htmlAudioPage);
  await htmlAudioPage.evaluate(() => window.__taxiSetState({ active: false }));
  assert.equal(await htmlAudioPage.evaluate(() =>
    window.__taxiPlayedSounds.some((source) => source.includes("taxidriver_offline.mp3"))
  ), false, "HTMLAudio fallback must queue events before mobile user activation");
  await htmlAudioPage.locator(".taxi-appbar__settings").click();
  await htmlAudioPage.waitForFunction(() =>
    window.__taxiPlayedSounds.some((source) => source.includes("taxidriver_offline.mp3"))
  );
  await htmlAudioPage.close();

  for (const locale of locales) {
    const page = await browser.newPage({ viewport: { width: 360, height: 640 } });
    await page.goto(harnessUrl("orders", { width: 360, height: 640 }, {
      external: true, locale, uiScale: 180, extreme: true,
    }));
    await waitForHarness(page);
    await assertVisualAudit(page, `locale ${locale}`);
    await screenshot(page, `locale-${locale}-orders-360x640.png`);
    visualCount += 1;
    await page.close();
  }

  const tripScaleCases = [
    ...[100, 140, 150, 180].map((uiScale) => ({ viewport: { width: 390, height: 844 }, uiScale })),
    ...[100, 150, 180].map((uiScale) => ({ viewport: { width: 320, height: 568 }, uiScale })),
  ];
  for (const external of [false, true]) {
    for (const scaleCase of tripScaleCases) {
      const { viewport, uiScale } = scaleCase;
      const page = await browser.newPage({ viewport });
      await page.goto(harnessUrl("trip", viewport, { external, uiScale }));
      await waitForHarness(page);
      await assertVisualAudit(page,
        `uiScale ${uiScale} ${external ? "web" : "game"} ${viewport.width}x${viewport.height}`);
      const geometry = await page.evaluate(() => {
        const rect = (selector) => {
          const value = document.querySelector(selector).getBoundingClientRect();
          return { left: value.left, top: value.top, right: value.right, bottom: value.bottom,
            width: value.width, height: value.height };
        };
        const stage = document.querySelector(".taxi-shell__scale-stage");
        return {
          shell: rect(".taxi-shell"),
          stage: rect(".taxi-shell__scale-stage"),
          map: rect(".taxi-map"),
          stageClass: stage.className,
          inlineZoom: stage.style.zoom,
          computedZoom: Number.parseFloat(getComputedStyle(stage).zoom) || 1,
          horizontalOverflow: document.documentElement.scrollWidth > window.innerWidth + 1,
        };
      });
      const expectedTier = uiScale >= 160 ? "accessibility"
        : (uiScale >= 140 ? "large" : (uiScale >= 110 ? "reduced" : "regular"));
      assert.ok(Math.abs(geometry.stage.width - geometry.shell.width) < 1 &&
        Math.abs(geometry.stage.height - geometry.shell.height) < 1,
      `Scale stage must fill its viewport at ${uiScale}% without composition scaling (${JSON.stringify(geometry)})`);
      assert.equal(geometry.inlineZoom, "", `Scale ${uiScale}% must not set inline zoom`);
      assert.equal(geometry.computedZoom, 1, `Scale ${uiScale}% must not use CSS zoom`);
      assert.match(geometry.stageClass, new RegExp(`(?:^|\\s)taxi-ui-scale--${uiScale}(?:\\s|$)`),
        `Scale ${uiScale}% must expose its exact scale class`);
      assert.match(geometry.stageClass, new RegExp(`(?:^|\\s)taxi-ui-tier--${expectedTier}(?:\\s|$)`),
        `Scale ${uiScale}% must expose the ${expectedTier} reflow tier`);
      assert.equal(geometry.horizontalOverflow, false,
        `Scale ${uiScale}% must not introduce document horizontal overflow`);
      assert.ok(geometry.map.left >= geometry.shell.left - 1 &&
        geometry.map.right <= geometry.shell.right + 1,
      `Scaled map must stay inside its viewport at ${uiScale}% (${JSON.stringify(geometry)})`);
      await screenshot(page,
        `scale-${uiScale}-${external ? "web" : "game"}-trip-${viewport.width}x${viewport.height}.png`);
      visualCount += 1;
      await page.close();
    }
  }

  const legacyScalePage = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await legacyScalePage.goto(harnessUrl("trip", { width: 390, height: 844 }));
  await waitForHarness(legacyScalePage);
  await legacyScalePage.evaluate(() => window.__taxiSetState({ settings: { fontBoost: 2 } }));
  await legacyScalePage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope && scope.getUiScalePercent() === 100;
  });
  const legacyScalePresentation = await legacyScalePage.locator(".taxi-shell__scale-stage").evaluate((element) => ({
    className: element.className,
    inlineZoom: element.style.zoom,
    computedZoom: Number.parseFloat(getComputedStyle(element).zoom) || 1,
  }));
  assert.equal(legacyScalePresentation.inlineZoom, "", "Legacy fontBoost migration must not set inline zoom");
  assert.equal(legacyScalePresentation.computedZoom, 1, "Legacy fontBoost migration must not use CSS zoom");
  assert.match(legacyScalePresentation.className, /(?:^|\s)taxi-ui-scale--100(?:\s|$)/,
    "Legacy fontBoost 2 must migrate to the exact 100% scale class");
  assert.match(legacyScalePresentation.className, /(?:^|\s)taxi-ui-tier--regular(?:\s|$)/,
    "Legacy fontBoost 2 must use the regular reflow tier");
  await legacyScalePage.close();

  for (const hidpi of [
    { scenario: "trip", viewport: { width: 390, height: 844 } },
    { scenario: "orders", viewport: { width: 1024, height: 768 } },
  ]) {
    const page = await browser.newPage({ viewport: hidpi.viewport, deviceScaleFactor: 2 });
    await page.goto(harnessUrl(hidpi.scenario, hidpi.viewport, { external: true }));
    await waitForHarness(page);
    assert.equal(await page.evaluate(() => window.devicePixelRatio), 2, "HiDPI page must render at DPR 2");
    assert.equal(await page.evaluate(() => document.fonts.check('16px "Taxi Noto Sans"')), true,
      "Bundled UI font must be available before the HiDPI screenshot");
    await assertVisualAudit(page, `hidpi ${hidpi.scenario}`);
    await screenshot(page, `hidpi-${hidpi.scenario}-${hidpi.viewport.width}x${hidpi.viewport.height}@2x.png`, 2);
    visualCount += 1;
    await page.close();
  }

  for (const viewport of [{ width: 320, height: 568 }, { width: 844, height: 390 }]) {
    const loaderPage = await browser.newPage({ viewport });
    await loaderPage.goto(`http://127.0.0.1:${port}/ui/modules/apps/TaxiDriverHUD/external/index.html`);
    const loader = loaderPage.locator("#taxi-loader");
    assert.equal(await loader.isVisible(), true, "External phone loader must be visible while connecting");
    assert.equal(await loaderPage.locator("#taxi-loader-steps li").count(), 4,
      "External phone loader must show four detailed stages");
    const loaderAudit = await loaderPage.evaluate(() => {
      const card = document.querySelector(".taxi-loader__card");
      const rect = card.getBoundingClientRect();
      const loaderStyle = getComputedStyle(document.querySelector(".taxi-loader"));
      return {
        horizontalOverflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        bottom: rect.bottom,
        viewportHeight: window.innerHeight,
        scrollable: ["auto", "scroll"].includes(loaderStyle.overflowY),
      };
    });
    assert.equal(loaderAudit.horizontalOverflow, false, "External loader must not overflow horizontally");
    assert.ok(loaderAudit.bottom <= loaderAudit.viewportHeight + 1 || loaderAudit.scrollable,
      `External loader content must remain reachable (${JSON.stringify(loaderAudit)})`);
    await screenshot(loaderPage, `external-loader-${viewport.width}x${viewport.height}.png`);
    visualCount += 1;
    await loaderPage.close();
  }

  const mapPage = await browser.newPage({ viewport: { width: 520, height: 900 }, deviceScaleFactor: 2 });
  await mapPage.goto(harnessUrl("trip", { width: 520, height: 900 }, { external: true }));
  await waitForHarness(mapPage);
  const mapAudit = await mapPage.locator("canvas.taxi-external-minimap").evaluate((canvas) => {
    const ctx = canvas.getContext("2d");
    const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
    let roadPixels = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      if (red >= 75 && green >= 85 && blue >= 90 && Math.abs(red - green) < 40) roadPixels += 1;
    }
    const rect = canvas.getBoundingClientRect();
    return { roadPixels, width: canvas.width, height: canvas.height, cssWidth: rect.width, cssHeight: rect.height };
  });
  assert.ok(mapAudit.roadPixels > 1000, `External map must render a visible road network (${JSON.stringify(mapAudit)})`);
  assert.ok(mapAudit.width >= mapAudit.cssWidth * 2 - 1 && mapAudit.height >= mapAudit.cssHeight * 2 - 1,
    `External map must use a sharp DPR 2 backing store (${JSON.stringify(mapAudit)})`);
  const readExternalTargetRadius = async (speed) => {
    await mapPage.evaluate((value) => window.__taxiSetState({ currentSpeed: value }), speed);
    await mapPage.waitForFunction((value) => {
      const canvas = document.querySelector("canvas.taxi-external-minimap");
      return canvas && Number(canvas.dataset.mapSpeed) === value;
    }, speed);
    return mapPage.locator("canvas.taxi-external-minimap").evaluate((canvas) =>
      Number(canvas.dataset.mapTargetRadius)
    );
  };
  const externalRadius0 = await readExternalTargetRadius(0);
  const externalRadius60 = await readExternalTargetRadius(60);
  const externalRadius120 = await readExternalTargetRadius(120);
  assert.ok(externalRadius0 <= 230,
    `External map must start with a close camera (${externalRadius0})`);
  assert.ok(externalRadius60 <= 430,
    `External map must remain close at city speed (${externalRadius60})`);
  assert.ok(externalRadius120 <= 750,
    `External map must limit high-speed zoom-out (${externalRadius120})`);
  assert.ok(externalRadius0 < externalRadius60 && externalRadius60 < externalRadius120,
    `External map radius must grow smoothly with speed (${externalRadius0}, ${externalRadius60}, ${externalRadius120})`);
  await mapPage.close();

  const performancePage = await browser.newPage({ viewport: { width: 520, height: 900 }, deviceScaleFactor: 2 });
  await performancePage.addInitScript(() => {
    window.__externalMapFrames = 0;
    const original = CanvasRenderingContext2D.prototype.setTransform;
    CanvasRenderingContext2D.prototype.setTransform = function(...args) {
      if (this.canvas && this.canvas.classList.contains("taxi-external-minimap")) {
        window.__externalMapFrames += 1;
      }
      return original.apply(this, args);
    };
  });
  await performancePage.goto(harnessUrl("trip", { width: 520, height: 900 }, { external: true }));
  await waitForHarness(performancePage);
  await performancePage.waitForFunction(() => window.__externalMapFrames > 0);
  await performancePage.evaluate(async () => {
    window.__externalMapFrames = 0;
    const root = angular.element(document).injector().get("$rootScope");
    for (let index = 0; index < 40; index += 1) {
      root.$broadcast("TaxiDriverExternalVehicleState", {
        position: [index * 2, index], direction: [0.05, 0.998],
      });
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  });
  const movingFrames = await performancePage.evaluate(() => window.__externalMapFrames);
  assert.ok(movingFrames >= 15 && movingFrames <= 36,
    `Balanced remote map must stay near its 15 FPS budget (${movingFrames} frames in 2 seconds)`);
  await performancePage.waitForTimeout(1800);
  await performancePage.evaluate(() => { window.__externalMapFrames = 0; });
  await performancePage.waitForTimeout(1000);
  assert.ok(await performancePage.evaluate(() => window.__externalMapFrames) <= 1,
    "A settled remote map must not keep repainting while the car is stationary");
  const stateRevisionAudit = await performancePage.evaluate(() => {
    const root = angular.element(document).injector().get("$rootScope");
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    const commandStart = (window.__taxiEngineLuaCommands || []).length;
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      active: true, phase: "searching", hudEpoch: "race-epoch", hudRevision: 100,
    }));
    root.$broadcast("TaxiDriverHUDPatch", {
      epoch: "race-epoch", baseRevision: 101, revision: 102,
      values: { phase: "toPickup" }, removed: [],
    });
    const phaseAfterMissedPatch = scope.state.phase;
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      active: true, phase: "toPickup", hudEpoch: "race-epoch", hudRevision: 103,
    }));
    const phaseAfterFullSync = scope.state.phase;
    root.$broadcast("TaxiDriverHUDPatch", {
      epoch: "race-epoch", baseRevision: 100, revision: 101,
      values: { phase: "searching" }, removed: [],
    });
    return {
      phaseAfterMissedPatch,
      phaseAfterFullSync,
      phaseAfterLatePatch: scope.state.phase,
      commands: (window.__taxiEngineLuaCommands || []).slice(commandStart),
    };
  });
  assert.equal(stateRevisionAudit.phaseAfterMissedPatch, "searching",
    "A patch with a missing predecessor must not be merged onto stale state");
  assert.equal(stateRevisionAudit.phaseAfterFullSync, "toPickup",
    "A full authoritative snapshot must recover a client after packet loss");
  assert.equal(stateRevisionAudit.phaseAfterLatePatch, "toPickup",
    "A delayed older patch must not roll a synchronized client back");
  assert.ok(stateRevisionAudit.commands.some((value) => value.includes("requestExternalHudState")),
    "A detected HUD revision gap must request a full snapshot");
  const cefVisibilityAudit = await performancePage.evaluate(async () => {
    const commandStart = (window.__taxiEngineLuaCommands || []).length;
    window.__externalMapFrames = 0;
    const root = angular.element(document).injector().get("$rootScope");
    root.$broadcast("onCefVisibilityChanged", false);
    for (let index = 0; index < 5; index += 1) {
      root.$broadcast("TaxiDriverExternalVehicleState", {
        position: [200 + index * 3, 100 + index], direction: [0.08, 0.997],
      });
      await new Promise((resolve) => setTimeout(resolve, 70));
    }
    return {
      frames: window.__externalMapFrames,
      commands: (window.__taxiEngineLuaCommands || []).slice(commandStart),
    };
  });
  assert.ok(cefVisibilityAudit.frames > 0,
    "In-game CEF hiding must not freeze the independently visible phone map");
  assert.ok(!cefVisibilityAudit.commands.some((value) => value.includes('setExternalPhoneView("hidden"')),
    "In-game CEF hiding must not report the external browser as hidden");
  await performancePage.evaluate(() => {
    const root = angular.element(document).injector().get("$rootScope");
    root.$broadcast("TaxiDriverHUDPatch", {
      epoch: "race-epoch", baseRevision: 103, revision: 104,
      values: { currentSpeed: 47 }, removed: [],
    });
  });
  await performancePage.waitForFunction(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return Number(scope.state.currentSpeed) === 47;
  });
  assert.ok(await performancePage.evaluate(() =>
    (window.__taxiEngineLuaCommands || []).some((value) => value.includes('setExternalPhoneView("trip"'))
  ), "External client must report the active trip screen to Lua");
  await performancePage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) =>
      value.includes('externalPhoneHeartbeat(') && value.includes('"trip", true')
    )
  );
  await performancePage.locator(".taxi-appbar__settings").click();
  await performancePage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) => value.includes('setExternalPhoneView("settings"'))
  );
  await performancePage.locator(".taxi-settings__group-head", { hasText: "Gameplay & difficulty" }).click();
  const unlimitedRouteToggle = performancePage.locator(
    'input[ng-model="settings.unlimitedRouteDistance"]'
  );
  await performancePage.locator("label.taxi-settings__switch-row", {
    hasText: "Unlimited route length",
  }).click();
  assert.equal(await unlimitedRouteToggle.isChecked(), true,
    "Unlimited route checkbox must reflect the row click");
  assert.equal(await performancePage.evaluate(() => {
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    return scope.settings.unlimitedRouteDistance;
  }), true, "Unlimited route length must be clickable in Trip settings");
  await performancePage.waitForFunction(() =>
    (window.__taxiEngineLuaCommands || []).some((value) =>
      value.includes("saveSettings") && value.includes('"unlimitedRouteDistance":true')
    )
  );
  await performancePage.evaluate(() => {
    const root = angular.element(document).injector().get("$rootScope");
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
      settings: Object.assign({}, scope.state.settings, { unlimitedRouteDistance: true }),
      hudEpoch: "race-epoch", hudRevision: 105,
    }));
  });
  const performanceCombinations = await performancePage.evaluate(() => {
    const root = angular.element(document).injector().get("$rootScope");
    const scope = angular.element(document.querySelector("taxi-driver-hud")).scope();
    let count = 0;
    for (const unlimitedRouteDistance of [false, true]) {
      for (const externalMapEnabled of [false, true]) {
        for (const externalTerrainEnabled of [false, true]) {
          for (const externalMapQuality of ["eco", "balanced", "smooth"]) {
            for (const godMode of [false, true]) {
              for (const debugLogging of [false, true]) {
                const settings = Object.assign({}, scope.state.settings, {
                  unlimitedRouteDistance, externalMapEnabled, externalTerrainEnabled,
                  externalMapQuality, godMode, debugLogging,
                });
                root.$broadcast("TaxiDriverHUDState", Object.assign({}, scope.state, {
                  settings, hudEpoch: "race-epoch", hudRevision: 106 + count,
                }));
                if (scope.settings.unlimitedRouteDistance !== unlimitedRouteDistance ||
                    scope.settings.externalMapEnabled !== externalMapEnabled ||
                    scope.settings.externalTerrainEnabled !== externalTerrainEnabled ||
                    scope.settings.externalMapQuality !== externalMapQuality ||
                    scope.settings.godMode !== godMode ||
                    scope.settings.debugLogging !== debugLogging) {
                  throw new Error("Trip, remote performance, and cheat combination was not preserved");
                }
                count += 1;
              }
            }
          }
        }
      }
    }
    return count;
  });
  assert.equal(performanceCombinations, 96,
    "All route limit, map, terrain, quality, God Mode, and debug logging combinations must remain valid");
  await assertVisualAudit(performancePage, "performance settings combinatorics");
  await performancePage.close();

  console.log(`TaxiDriverHUD: ${visualCount} responsive visual states passed, including locales and HiDPI.`);
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
