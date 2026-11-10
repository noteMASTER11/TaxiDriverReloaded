package.path = "lua/ge/extensions/?.lua;" .. package.path

local file = assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local config = require("taxiDriver/config")
local delivery = require("taxiDriver/delivery")
local function noop() end
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}; for key, item in pairs(value) do result[key] = copy(item) end
  return result
end
local function extract(first, following)
  local start = assert(source:find(first, 1, true), first)
  local finish = assert(source:find(following, start + #first, true), following)
  return source:sub(start, finish - 1)
end
local function execute(text, env)
  if setfenv then
    local chunk = assert(loadstring(text)); setfenv(chunk, env); return chunk()
  end
  return assert(load(text, "@homeDifficulty-production", "t", env))()
end
local functions = {
  applyDifficulty = {"local function applyDifficulty", "function M.writeDifficultySettings"},
  getDriverAbandonmentPreview = {"local function getDriverAbandonmentPreview", "local beginPassengerStopDemand"},
  applyPassengerPenalty = {"local function applyPassengerPenalty", "local function getPassengerStressThreshold"},
  getPenaltyTotal = {"local function getPenaltyTotal", "local function getAdjustedFare"},
  getAdjustedFare = {"local function getAdjustedFare", "local function chargeDirectPenalty"},
  chargeDirectPenalty = {"local function chargeDirectPenalty", "local function getRemainingDistance"},
  updatePickupDeadline = {"local function updatePickupDeadline", "local function startPassengerLeg"},
  applyEarlyExitRatingLoss = {"local function applyEarlyExitRatingLoss", "local function applyDriverAbandonmentRatingLoss"},
  applyDriverAbandonmentRatingLoss = {"local function applyDriverAbandonmentRatingLoss", "beginPassengerStopDemand = function"},
  finishRide = {"local function finishRide", "local function updateSpeedPenalty"},
  updateSpeedPenalty = {"local function updateSpeedPenalty", "local function updateRushTimer"},
  updateRushTimer = {"local function updateRushTimer", "local function updateTripCooldowns"},
  addPenaltyEvent = {"local function addPenaltyEvent", "local policeCheckCallbacks ="}
}
functions.failPassengerHit = {"local function failPassengerHit", "local function addOffer"}
local function fixture(id, isDelivery)
  local trip = {isDelivery = isDelivery, estimatedFare = 100, passengerCalmness = 0,
    pickupTimeRemaining = 1, speedPenalty = 0, collisionPenalty = 0, aggressionPenalty = 0,
    collisionDamage = 0, collisionCount = 0, collisionCooldown = 0, lastDamage = 0,
    aggressionCooldown = 0, aggressionEvents = 0, speedingEpisodeTime = 0, speedingEvents = 0}
  local env = setmetatable({
    M = {}, taxiConfig = config, difficultyPresets = config.difficultyPresets,
    balanceConfig = copy(config.balance), earlyExitRatingLoss = copy(config.earlyExitRatingLoss),
    driverAbandonmentExtraLoss = copy(config.driverAbandonmentExtraLoss),
    state = {difficulty = id, phase = "toDestination", activeVehicleId = 42,
      rating = 4, ratingTotal = 8, ratingCount = 2, balance = 20, completedRides = 0},
    userSettings = {difficulty = id, customDifficulty = copy(config.customDifficultyDefaults),
      penaltyToggles = {speeding = true, collision = true, aggression = true,
        pickupDelay = true, fuelStop = true, cargoDamage = true, rushBonus = false}},
    trip = trip, phases = config.phases, runtimeConfig = {completedDuration = 1},
    realisticFuel = {detour = {penaltyPercent = 3}, repairDamageProbe = {},
      dashboardEnergy = {}, adjustPassengerMood = noop, recordBalanceHistory = noop},
    rideRules = require("taxiDriver/rideRules").new({phases = config.phases}),
    telemetry = {}, aiLogger = {onVehicleTelemetry = noop}, passengerMood = require("taxiDriver/passengerMood"),
    clampValue = function(value, lo, hi) return math.max(lo, math.min(hi, value)) end,
    roundMoney = function(value) return math.floor(value * 100 + 0.5) / 100 end,
    createPassengerPenaltyDisposition = function() return {ignored = false, multiplier = 2} end,
    getPassengerCalmness = function() return 0 end,
    addPenaltyEvent = function() return {} end,
    addPassengerStress = function(value) trip.passengerStress = (trip.passengerStress or 0) + value end,
    getVehicleSpeedKmh = function() return 200 end,
    getObjectByID = noop,
    routePlanning = {getNearestRoadSpeedLimit = function() return 50 end},
    showPhoneNotification = noop, notifyHud = noop, notifyProfile = noop,
    writeUserProgress = noop, recordProgressEvent = noop, beginSearching = noop,
    clearNavigation = noop, getPassengerReviewEmoji = function() return "review" end,
    tripEvents = {calculateTip = function() return 0 end, history = noop},
    delivery = delivery, vehicleHistory = {recordRide = noop},
    shiftTracking = {recordRide = noop}
  }, {__index = _G})
  for name, boundaries in pairs(functions) do
    env[name] = execute(extract(boundaries[1], boundaries[2]) .. "\nreturn " .. name, env)
  end
  execute(extract("function realisticFuel.calculatePassengerWaitPenalty", "function realisticFuel.beginDetour"), env)
  execute(extract("function M.onTelemetry", "function M.onUpdate"), env)
  env.policeCheckCallbacks = execute(extract("local policeCheckCallbacks =", "local function clearNextOffer") ..
    "\nreturn policeCheckCallbacks", env)
  assert(env.applyDifficulty(id))
  return env
end

local failures, passed = {}, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failures[#failures + 1] = name .. ": " .. tostring(err) end
end

-- These exercise the live penalty producers with old saves whose toggles remain true.
test("relaxed pickup countdown continues without fines", function()
  local env = fixture("elementary"); env.state.phase = "toPickup"
  env.updatePickupDeadline(60)
  assert(env.trip.pickupTimeRemaining == 0 and not env.trip.pickupLate and
    (env.trip.pickupPenalty or 0) == 0, "relaxed pickup charged a penalty")
end)
test("relaxed speeding never records a fine", function()
  local env = fixture("elementary")
  env.updateSpeedPenalty({getPosition = noop}, 60)
  assert(env.trip.speedPenalty == 0 and env.trip.speedingEvents == 0, "relaxed speeding charged a penalty")
end)
test("relaxed collision and aggression never charge", function()
  local env = fixture("elementary")
  env.M.onTelemetry(42, {damage = 9000, longitudinalG = 2, lateralG = 2})
  assert(env.trip.collisionPenalty == 0 and env.trip.aggressionPenalty == 0 and
    (env.trip.ratingCollisionCount or 0) == 0 and (env.trip.passengerStress or 0) == 0,
    "relaxed telemetry charged a fine, rating deduction or forced-exit stress")
end)
test("relaxed police fine preserves balance", function()
  local env = fixture("elementary"); env.policeCheckCallbacks.fine(60)
  assert(env.state.balance == 20, "relaxed police event deducted money")
end)
test("relaxed pedestrian collision preserves balance and rating", function()
  local env = fixture("elementary"); env.failPassengerHit()
  assert(env.state.balance == 20 and env.state.rating == 4 and env.state.ratingCount == 2,
    "relaxed passenger collision deducted money or rating")
end)
test("relaxed cargo damage never reduces fare or rating", function()
  local env = fixture("elementary", true)
  env.M.onTelemetry(42, {damage = 9000})
  assert((env.trip.cargoDamagePercent or 0) == 0 and env.trip.collisionPenalty == 0,
    "relaxed delivery charged cargo damage")
end)
test("relaxed fuel detour ignores a stale queued fine", function()
  local env = fixture("elementary")
  assert(env.realisticFuel.calculatePassengerWaitPenalty("fuel") == 0, "relaxed fuel preview charged a fine")
  assert(env.realisticFuel.applyPassengerWaitPenalty("fuel", "Station") == 0 and
    (env.trip.fuelStopPenalty or 0) == 0, "relaxed fuel stop charged a queued fine")
end)

test("relaxed rush expiry keeps bonus and mood without recording a fine", function()
  for _, phase in ipairs({"toDestination", "toStop", "stopWaiting"}) do
    local env = fixture("elementary"); env.state.phase = phase
    env.userSettings.penaltyToggles.rushBonus = true
    env.trip.isRush = true; env.trip.rushTimeRemaining = 1
    env.trip.baseFare = 60; env.trip.ratingAdjustedFare = 70; env.trip.bonusAmount = 30
    env.trip.passengerCalmness = 50; env.getPassengerCalmness = function() return env.trip.passengerCalmness end
    execute(extract("function realisticFuel.adjustPassengerMood", "function realisticFuel.updatePassengerMood"), env)
    env.updateRushTimer(60)
    assert(env.trip.rushTimeRemaining == 0, "relaxed rush countdown stopped")
    assert(not env.trip.rushBonusLost and env.getAdjustedFare() == 100,
      "relaxed rush expiry removed the bonus")
    assert(#(env.trip.penaltyEvents or {}) == 0 and env.trip.passengerCalmness == 50,
      "relaxed rush expiry recorded a fine or reduced mood")
  end
end)

test("relaxed stale rush loss preserves full payment and quick tip", function()
  local env = fixture("elementary")
  env.trip.isRush = true; env.trip.rushBonusLost = true
  env.trip.rushTimeRemaining = 15
  env.trip.baseFare = 60; env.trip.ratingAdjustedFare = 70; env.trip.bonusAmount = 30
  env.trip.randomEvent = {kind = "tip", condition = "quick", rate = 0.10}
  env.tripEvents = require("taxiDriver/tripEvents")
  assert(env.getAdjustedFare() == 100, "relaxed stale rush loss reduced fare")
  env.updateRushTimer(5)
  assert(env.trip.rushTimeRemaining == 10, "relaxed stale rush loss stopped the countdown")
  env.finishRide()
  assert(env.trip.finalFare == 110 and env.trip.tipAmount == 10 and env.state.balance == 130,
    "relaxed stale rush loss reduced completed payment or quick tip")
end)

test("other presets retain rush bonus expiry", function()
  for _, id in ipairs({"easy", "standard", "professional", "custom"}) do
    local env = fixture(id); env.userSettings.penaltyToggles.rushBonus = true
    env.trip.isRush = true; env.trip.rushTimeRemaining = 1
    env.trip.ratingAdjustedFare = 70; env.trip.bonusAmount = 30
    env.updateRushTimer(60)
    assert(env.trip.rushBonusLost and env.getAdjustedFare() == 70 and
      #env.trip.penaltyEvents == 1 and env.trip.penaltyEvents[1].fareAmount == 30,
      id .. " rush expiry changed")
  end
end)
test("relaxed early exit keeps existing rating", function()
  local env = fixture("elementary"); env.applyEarlyExitRatingLoss()
  assert(env.state.rating == 4 and env.state.ratingTotal == 8 and env.state.ratingCount == 2,
    "relaxed early exit reduced rating")
end)
test("relaxed abandonment preview and action keep rating", function()
  local env = fixture("elementary"); local preview = env.getDriverAbandonmentPreview()
  assert(preview.ratingLoss == 0 and preview.extraPercent == 0 and preview.finalRating == 4,
    "relaxed abandonment preview reduced rating")
  env.applyDriverAbandonmentRatingLoss()
  assert(env.state.rating == 4 and env.state.ratingTotal == 8, "relaxed abandonment reduced rating")
end)
for _, isDelivery in ipairs({false, true}) do
  test("relaxed ignores stale " .. (isDelivery and "cargo" or "passenger") .. " fare/rating fines", function()
    local env = fixture("elementary", isDelivery)
    env.trip.speedPenalty = 0.5; env.trip.collisionPenalty = 0.5; env.trip.aggressionPenalty = 0.5
    env.trip.pickupPenalty = 0.5; env.trip.fuelStopPenalty = 0.5
    env.trip.ratingCollisionCount = 10; env.trip.cargoDamagePercent = 100
    assert(env.getPenaltyTotal() == 0 and env.getAdjustedFare() == 100, "relaxed stale fines reduced fare")
    env.finishRide()
    assert(env.trip.rideRating == 5 and env.state.balance == 120, "relaxed completion reduced fare or review")
  end)
end
test("light passenger and delivery total fare loss is capped at ten percent", function()
  for _, isDelivery in ipairs({false, true}) do
    local env = fixture("easy", isDelivery)
    env.trip.speedPenalty = 1; env.trip.collisionPenalty = 1; env.trip.aggressionPenalty = 1
    env.trip.pickupPenalty = 1; env.trip.fuelStopPenalty = 1; env.trip.cargoDamagePercent = 100
    assert(env.getAdjustedFare() == 90, "light penalties exceeded ten percent")
  end
end)
test("light early exit and abandonment lose five percent rating", function()
  local env = fixture("easy"); env.applyEarlyExitRatingLoss()
  assert(math.abs(env.state.rating - 3.8) < 0.0001, "light early exit penalty is too large")
  env = fixture("easy"); env.applyDriverAbandonmentRatingLoss()
  assert(math.abs(env.state.rating - 3.8) < 0.0001, "light abandonment penalty is too large")
end)
test("light passenger and cargo completion lose at most five percent review rating", function()
  for _, isDelivery in ipairs({false, true}) do
    local env = fixture("easy", isDelivery)
    env.trip.speedPenalty = 1; env.trip.ratingCollisionCount = 100
    env.trip.cargoDamagePercent = 100; env.finishRide()
    assert(env.trip.rideRating == 4.75, "light completion review lost more than five percent")
  end
end)
test("light direct fines share the ten percent budget before and after fare penalties", function()
  for _, fineFirst in ipairs({false, true}) do
    local env = fixture("easy"); env.state.balance = 100
    if fineFirst then env.policeCheckCallbacks.fine(60) end
    env.trip.speedPenalty = 0.04
    if not fineFirst then env.policeCheckCallbacks.fine(60) end
    env.trip.collisionPenalty = 0.5
    env.policeCheckCallbacks.fine(60)
    local directLoss = 100 - env.state.balance
    local fareLoss = 100 - env.getAdjustedFare()
    assert(directLoss + fareLoss <= 10.00001 and directLoss > 0,
      "light combined direct and fare fines exceeded ten percent")
  end
end)
test("light passenger collision stays within money and rating budget", function()
  local env = fixture("easy"); env.state.balance = 100
  env.trip.speedPenalty = 0.04; env.failPassengerHit()
  assert(env.state.balance == 94, "light passenger hit exceeded remaining six dollar budget")
  assert(math.abs(env.state.rating - 3.8) < 0.0001, "light passenger hit dropped more than five percent rating")
end)
test("light cent rounding cannot exceed the ten percent money budget", function()
  local env = fixture("easy"); env.trip.estimatedFare = 2.06; env.trip.speedPenalty = 1
  assert(env.getAdjustedFare() == 1.86, "cent rounding pushed the fare loss above ten percent")
end)
test("standard direct fines remain unchanged", function()
  local env = fixture("standard"); env.state.balance = 100
  env.policeCheckCallbacks.fine(60)
  assert(env.state.balance == 40, "standard police fine changed")
end)
test("standard keeps legacy fare and abandonment", function()
  local env = fixture("standard"); env.trip.speedPenalty = 0.9
  assert(env.getAdjustedFare() == 50, "standard fare cap changed")
  env.applyDriverAbandonmentRatingLoss()
  assert(math.abs(env.state.rating - 1.8) < 0.0001, "standard abandonment changed")
end)
test("relaxed switches back to standard and custom without changing saved toggles", function()
  local env = fixture("elementary")
  assert(env.userSettings.penaltyToggles.speeding and env.userSettings.penaltyToggles.cargoDamage and
    env.userSettings.penaltyToggles.rushBonus == false, "loading a preset rewrote saved toggles")
  assert(env.applyDifficulty("standard")); env.trip.speedPenalty = 0.5
  assert(env.getAdjustedFare() == 50 and env.balanceConfig.speedPenaltyRate == 0.0008,
    "relaxed values leaked into standard")
  env.applyDifficulty("elementary"); env.userSettings.customDifficulty.maxFareReductionPercent = 25
  assert(env.applyDifficulty("custom"))
  assert(env.getAdjustedFare() == 75 and env.balanceConfig.speedPenaltyRate == 0.0008,
    "relaxed values leaked into custom")
end)
test("settings save and reload preserve preset IDs custom values and individual toggles", function()
  local saved = {}
  FS = {fileExists = function(_, path) return saved[path] ~= nil end,
    directoryExists = function() return true end}
  jsonReadFile = function(path) return copy(saved[path]) end
  jsonWriteFile = function(path, value) saved[path] = copy(value) end
  local store = require("taxiDriver/persistence").new({taxiConfig = config,
    difficultyPresets = config.difficultyPresets, supportedLanguages = config.supportedLanguages})
  for _, id in ipairs({"elementary", "easy", "standard", "professional", "custom"}) do
    local settings = store:createDefaultSettings()
    settings.difficulty = id; settings.customDifficulty.maxFareReductionPercent = 25
    settings.penaltyToggles.collision = false; settings.penaltyToggles.rushBonus = false
    assert(store:writeSettings(settings))
    local loaded = store:loadSettings()
    assert(loaded.difficulty == id and loaded.customDifficulty.maxFareReductionPercent == 25 and
      loaded.penaltyToggles.speeding and not loaded.penaltyToggles.collision and
      not loaded.penaltyToggles.rushBonus, "save/load rewrote difficulty, custom values or toggles")
    local env = fixture(id); env.userSettings = loaded; env.applyDifficulty(loaded.difficulty)
    assert(env.userSettings.penaltyToggles.speeding and not env.userSettings.penaltyToggles.collision,
      "applying a loaded preset rewrote its stored toggles")
  end
end)
test("relaxed retains normal fuel and repair purchase costs", function()
  local env = fixture("elementary"); env.state.balance = 100
  local vehicle = {getID = function() return 42 end}
  env.getObjectByID = function() return vehicle end
  env.vehicleBridgeGuard = {execute = noop}
  env.shiftTracking.recordFuelCost = noop; env.shiftTracking.recordRepairCost = noop
  local fuel = env.realisticFuel
  fuel.station = {id = "fuel"}; fuel.repairStation = {id = "repair"}
  fuel.initializedVehicles = {}; fuel.refuelingCompletionId = 0
  fuel.readableUnit = {gasoline = "L"}; fuel.deferDashboardEnergy = noop
  execute(extract("function realisticFuel.resetRefueling", "function realisticFuel.clearStation"), env)
  execute(extract("function realisticFuel.resetRepairing", "function realisticFuel.clearRepairStation"), env)
  execute(extract("function realisticFuel.finishPurchase", "function realisticFuel.updateRefueling"), env)
  execute(extract("function realisticFuel.finishRepair", "function realisticFuel.updateRepairing"), env)
  fuel.refueling = {active = true, vehicleId = 42, stationId = "fuel", cost = 20,
    quantity = 5, energyType = "gasoline", updates = {}}
  fuel.finishPurchase()
  assert(env.state.balance == 80 and env.trip.fuelCost == 20, "relaxed fuel purchase became free")
  fuel.repairVehiclePhysically = function(_, callback, authorize)
    assert(authorize()); callback(true)
  end
  fuel.repairing = {active = true, vehicleId = 42, stationId = "repair", cost = 30}
  fuel.finishRepair()
  assert(env.state.balance == 50, "relaxed repair purchase became free")
end)

test("relaxed rating and payment survive real history recording and progress reload", function()
  local saved = {}
  FS = {fileExists = function(_, path) return saved[path] ~= nil end,
    directoryExists = function() return true end}
  jsonReadFile = function(path) return copy(saved[path]) end
  jsonWriteFile = function(path, value) saved[path] = copy(value) end
  local store = require("taxiDriver/persistence").new({taxiConfig = config,
    difficultyPresets = config.difficultyPresets, supportedLanguages = config.supportedLanguages})
  for _, action in ipairs({"passenger", "cargo", "earlyExit", "abandonment", "passengerHit"}) do
    local env = fixture("elementary", action == "cargo")
    env.tripHistory = require("taxiDriver/tripHistory"); env.dataStore = store
    env.createDefaultUserProgress = function() return store:createDefaultProgress() end
    env.userProgress = env.createDefaultUserProgress()
    env.shiftTracking.getHud = function() return {} end
    env.syncUserProgressFromState = execute(extract("local function syncUserProgressFromState",
      "local function writeDriverProfile") .. "\nreturn syncUserProgressFromState", env)
    env.writeUserProgress = execute(extract("local function writeUserProgress()",
      "local function loadDriverProfile") .. "\nreturn writeUserProgress", env)
    env.recordProgressEvent = execute(extract("local function recordProgressEvent",
      "local function showPhoneNotification") .. "\nreturn recordProgressEvent", env)
    env.applyUserProgressToState = execute(extract("local function applyUserProgressToState",
      "local function syncUserProgressFromState") .. "\nreturn applyUserProgressToState", env)
    env.trip.cargoDamagePercent = 100; env.trip.ratingCollisionCount = 100
    env.trip.speedPenalty = 1; env.trip.pickupPenalty = 1; env.trip.collisionPenalty = 1
    if action == "passenger" or action == "cargo" then env.finishRide()
    elseif action == "earlyExit" then env.applyEarlyExitRatingLoss()
    elseif action == "abandonment" then env.applyDriverAbandonmentRatingLoss()
    else env.failPassengerHit() end
    local expectedRating = (action == "passenger" or action == "cargo") and 13 / 3 or 4
    local expectedBalance = (action == "passenger" or action == "cargo") and 120 or 20
    env.userProgress = store:loadProgress()
    env.state.rating = 0; env.state.balance = 0; env.applyUserProgressToState()
    assert(math.abs(env.state.rating - expectedRating) < 0.000001 and
      env.state.balance == expectedBalance, action .. " history reload reduced rating or payment")
    assert(#env.userProgress.reviews == 1 and #env.userProgress.reviews[1].penalties == 0,
      action .. " recorded a penalty in history")
  end
end)

test("acceptance resets persisted cargo damage before relaxed delivery telemetry", function()
  local env = fixture("elementary", true)
  env.trip.cargoDamagePercent = 100; env.trip.collisionPenalty = 1
  env.trip.ratingCollisionCount = 100; env.trip.penaltyEvents = {{kind = "cargoDamage", penalty = 1}}
  env.resetTripMetrics = execute(extract("local function resetTripMetrics",
    "local function preparePassengerRideMetrics") .. "\nreturn resetTripMetrics", env)
  local vehicle = {getPosition = function() return {} end, queueLuaCommand = noop}
  env.getObjectByID = function() return vehicle end
  env.calculateRouteDistance = function() return 100 end
  env.offerGeneration = {recentRoutes = {}}
  env.routeDiversity = {remember = noop}; env.offerConfig = {}
  env.physicalPickup = {start = noop}; env.clearNextOffer = noop; env.setNavigationTarget = noop
  env.trip.pickup = {pos = {}}; env.trip.cachedRoute = true
  local accept = execute(extract("local function startAcceptedOffer",
    "local function acceptOffer") .. "\nreturn startAcceptedOffer", env)
  assert(accept(env.trip), "persisted delivery offer was not accepted")
  env.state.phase = "toDestination"
  env.M.onTelemetry(42, {damage = 10000})
  env.finishRide()
  assert(env.trip.cargoDamagePercent == 0 and #env.trip.penaltyEvents == 0 and
    env.trip.rideRating == 5 and env.trip.finalFare == 100,
    "persisted cargo damage survived acceptance or new damage reduced relaxed delivery")
end)

test("HUD reports effective relaxed cargo and rush state while retaining underlying trip data", function()
  for _, id in ipairs({"elementary", "easy", "standard", "professional", "custom"}) do
    for _, isDelivery in ipairs({false, true}) do
      local env = fixture(id, isDelivery)
      env.trip.cargoDamagePercent = isDelivery and 85 or 0
      env.trip.isRush = not isDelivery; env.trip.rushBonusLost = not isDelivery
      env.getRemainingDistance = function() return 0 end
      env.getRouteProgress = function() return 0, "route" end
      env.buildHudOffer = noop; env.getAutopilotTarget = noop
      env.createDefaultDriverProfile = function() return {} end
      env.phaseLabels = {inactive = "inactive"}; env.vehicleHistory.getCurrentHud = noop
      env.realisticFuel.buildHud = noop; env.realisticFuel.buildRepairHud = noop
      env.lanBridge = {getStatus = noop}; env.autopilot = {getHud = noop}
      env.shiftTracking.getHud = noop; env.buildHudPenaltyEvents = function() return {} end
      env.getPassengerStressThreshold = function() return 100 end
      env.buildStopProgressMarkers = function() return {} end
      local build = execute(extract("local function buildHudState",
        "local function notifyHud") .. "\nreturn buildHudState", env)
      local hud = build(false)
      assert(hud.cargoDamagePercent == (id ~= "elementary" and isDelivery and 85 or 0),
        id .. " HUD cargo damage did not match effective penalty rules")
      assert(hud.rushBonusActive == (id == "elementary" and not isDelivery) and
        hud.rushBonusLost == (id ~= "elementary" and not isDelivery),
        id .. " HUD rush bonus did not match effective penalty rules")
      assert(env.trip.cargoDamagePercent == (isDelivery and 85 or 0) and
        env.trip.rushBonusLost == not isDelivery, "HUD erased underlying trip data")
    end
  end
end)

for _, message in ipairs(failures) do print("FAIL " .. message) end
assert(#failures == 0, tostring(#failures) .. " home difficulty regressions failed; " .. passed .. " passed")
print("TaxiDriver home difficulty regressions passed (" .. passed .. ")")
