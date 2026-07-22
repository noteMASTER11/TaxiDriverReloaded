local M = {}
M.dependencies = {
  "core_groundMarkers", "core_trafficSignals",
  "core_vehicleTriggers",
  "core_vehicle_manager",
  "freeroam_gasStations",
  "gameplay_sites_sitesManager"
}
local offerGenerator = require("taxiDriver/offerGenerator")
local taxiConfig = require("taxiDriver/config")
local identity = require("taxiDriver/identity")
local passengerMood = require("taxiDriver/passengerMood")
local routeDiversity = require("taxiDriver/routeDiversity")
local delivery = require("taxiDriver/delivery")
local lanBridge = require("taxiDriver/lanBridge")
local vehicleHistory = require("taxiDriver/vehicleHistory")
local vehicleScanGuard = require("taxiDriver/vehicleScanGuard")
local persistence = require("taxiDriver/persistence")
local vehicleControl = require("taxiDriver/vehicleControl")
local routePlanner = require("taxiDriver/routePlanner")
local shiftTracker = require("taxiDriver/shiftTracker")
local shiftHistory = require("taxiDriver/shiftHistory")
local tripEvents = require("taxiDriver/tripEvents")
local hudPublisher = require("taxiDriver/hudPublisher")
local logger = require("taxiDriver/logger")
local aiLoggerModule = require("taxiDriver/aiLogger")
local modVersion = "3.2.1-beta"
local fleet = require("taxiDriver/fleetManager").new({modVersion = modVersion})
local logTag = "taxiDriver"
local supportedLanguages = taxiConfig.supportedLanguages
local minRideDistance = taxiConfig.runtime.minRideDistance
local maxRideDistance = taxiConfig.runtime.maxRideDistance
local minPickupDistance = taxiConfig.runtime.minPickupDistance
local maxPickupDistance = taxiConfig.runtime.maxPickupDistance
local arrivalRadius = taxiConfig.runtime.arrivalRadius
local maxArrivalSpeedKmh = taxiConfig.runtime.maxArrivalSpeedKmh
local averageCitySpeedKmh = taxiConfig.runtime.averageCitySpeedKmh
local minimumDrivability = taxiConfig.runtime.minimumDrivability
local hudUpdateInterval = taxiConfig.runtime.hudUpdateInterval
local boardingDuration = taxiConfig.runtime.boardingDuration
local alightingDuration = taxiConfig.runtime.alightingDuration
local completedDuration = taxiConfig.runtime.completedDuration
local stopWaitingDuration = taxiConfig.runtime.stopWaitingDuration
local forcedExitDuration = taxiConfig.runtime.forcedExitDuration
local offerConfig = taxiConfig.offer
local balanceConfig = taxiConfig.balance
local earlyExitRatingLoss = taxiConfig.earlyExitRatingLoss
local driverAbandonmentExtraLoss = taxiConfig.driverAbandonmentExtraLoss
local realisticFuel = {
  config = taxiConfig.realisticFuel,
  energyMJPerUnit = {
    gasoline = 31.125,
    diesel = 36.112,
    kerosine = 34.4,
    n2o = 8.3,
    electricEnergy = 3.6
  },
  readableUnit = {
    gasoline = "L",
    diesel = "L",
    kerosine = "L",
    n2o = "kg",
    electricEnergy = "kWh"
  },
  originalRefuelCar = nil,
  originalActivityGather = nil,
  economyInstalled = false,
  initializedVehicles = {},
  initializationPending = {},
  station = nil,
  stationFuelTypes = nil,
  options = {},
  dataPending = false,
  dataTimer = 0,
  routeRequestPending = false,
  dashboardEnergyPending = false,
  dashboardEnergyTimer = 0,
  dashboardEnergyRequestGeneration = 0,
  dashboardEnergy = {
    available = false,
    energyType = "",
    quantity = 0,
    maxQuantity = 0,
    percent = 0,
    unit = "",
    estimatedRangeKm = 0
  },
  refuelingCompletionId = 0,
  refueling = {
    active = false,
    completing = false,
    stationId = "",
    vehicleId = 0,
    energyType = "",
    quantity = 0,
    cost = 0,
    duration = 0,
    elapsed = 0,
    hudTimer = 0,
    updates = {}
  },
  detour = {
    active = false,
    previousPhase = nil,
    hadTrip = false,
    passengerOnboard = false,
    stationId = "",
    stationName = "",
    pos = nil,
    routeDistance = 0,
    previousRemainingDistance = 0,
    penaltyPercent = 0,
    penaltyApplied = false,
    arrived = false
  }
}
local driverAvatarOptions = identity.driverAvatarOptions
local driverAvatarSet = identity.driverAvatarSet
local difficultyPresets = taxiConfig.difficultyPresets
local phases = taxiConfig.phases
local phaseLabels = taxiConfig.phaseLabels
local dataStore = persistence.new({
  modVersion = modVersion,
  taxiConfig = taxiConfig,
  supportedLanguages = supportedLanguages,
  difficultyPresets = difficultyPresets,
  driverAvatarSet = driverAvatarSet
})
local getVehicleSpeedKmh = vehicleControl.getSpeedKmh
local setTelemetryEnabled = vehicleControl.setTelemetryEnabled
local setVehicleForcedStop = vehicleControl.setForcedStop
local setVehicleFrozen = vehicleControl.setFrozen
local releaseForcedPassengerStop = vehicleControl.releaseForcedStop
local togglePassengerDoor = vehicleControl.togglePassengerDoor
local toggleCargoAccess = vehicleControl.toggleCargoAccess
local state = {
  active = false,
  phase = phases.inactive,
  activeVehicleId = nil,
  balance = 0,
  rating = 5,
  ratingTotal = 0,
  ratingCount = 0,
  completedRides = 0,
  difficulty = "standard",
  realisticMode = false,
  message = ""
}
local function createDefaultUserSettings()
  return dataStore:createDefaultSettings()
end
local userSettings = createDefaultUserSettings()
logger.setEnabledProvider(function() return userSettings.debugLogging ~= false end)
local settingsNeedsLegacyImport = false
local driverProfile = nil
local userProgress = nil
local progressNeedsLegacyImport = false
local shiftTracking = shiftTracker.new(nil)
local trip = nil
local offers = {}
local nextOffer = nil
local nextOfferTimer = 0
local nextOfferAccepted = false
local phoneNotification = nil
local nextPhoneNotificationId = 0
local telemetry = {damage = 0, longitudinalG = 0, lateralG = 0, autopilotController = nil, vehicleId = nil}
local phaseTimer = 0
local hudTimer = 0
local offerTimer = 0
local offerTargetCount = offerConfig.minVisible
local offerTypePlan = {}
local offerGeneration = {
  failures = 0,
  multiStopUnavailableForPool = false,
  poolJob = nil,
  poolRequestedType = nil,
  nextJob = nil,
  recentRoutes = {}
}
local nextOfferId = 1
local minimapOriginalMode = nil
local minimapOwned = false
local minimapAppVisible = true
local minimapUiBlocked = false
local minimapOriginalDrawPlayer = nil
local minimapWrappedDrawPlayer = nil
local minimapZoomMultiplier = nil
local navigationVisualOverrideActive = false
local originalNavigationGroundmarkers = nil
local originalNavigationArrows = nil
local routePlanning = routePlanner.new({
  minimumDrivability = minimumDrivability,
  offerConfig = offerConfig,
  onLevelChanged = function()
    offerGeneration.recentRoutes = {}
  end
})
local aiLogger = aiLoggerModule.new({getContext = function()
  local currentVehicle = vehicleHistory.getCurrentHud()
  return {modVersion = modVersion, phase = state.phase, vehicleId = state.activeVehicleId, tripId = trip and trip.id or nil,
    tripType = trip and (trip.isDelivery and "delivery" or "passenger") or nil, vehicleKey = currentVehicle and currentVehicle.key or nil,
    vehicleName = currentVehicle and currentVehicle.name or nil}
end}); logger.setEventSink(function(level, area, event, fields) aiLogger:onStructuredEvent(level, area, event, fields) end)
local autopilot = require("taxiDriver/autopilot").new({
  config = taxiConfig.autopilot,
  phases = phases,
  trace = aiLogger,
  getSpeedKmh = getVehicleSpeedKmh,
  getSafetyObservation = function() return telemetry.vehicleId == state.activeVehicleId and telemetry.autopilotController or nil end,
  getRoutePath = function()
    local planner = core_groundMarkers and core_groundMarkers.routePlanner or nil
    return planner and planner.path or {}
  end
})
local calculateRouteDistance = routePlanning.calculateDistance
local rememberOfferStops = routePlanning.rememberOfferStops
local chooseTaxiStopPoint = routePlanning.chooseStop
local function clampValue(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end
local function applyDifficulty(presetId)
  local preset = presetId == "custom" and
    taxiConfig.buildCustomDifficulty(userSettings.customDifficulty) or
    difficultyPresets[presetId]
  if not preset then return false end
  for key, value in pairs(preset) do
    balanceConfig[key] = value
  end
  if presetId == "custom" then
    local ratingLoss = clampValue(
      tonumber(userSettings.customDifficulty.earlyExitRatingLossPercent) or 30,
      0,
      60
    ) / 100
    earlyExitRatingLoss.custom = ratingLoss
    driverAbandonmentExtraLoss.custom = ratingLoss
  end
  state.difficulty = presetId
  return true
end
function M.writeDifficultySettings() return dataStore:writeDifficulty(userSettings) end
local function writeUserSettings() return dataStore:writeSettings(userSettings) end
local function loadUserSettings()
  userSettings, settingsNeedsLegacyImport = dataStore:loadSettings(); applyDifficulty(userSettings.difficulty); aiLogger:setEnabled(userSettings.aiDebugLogging == true)
  autopilot:configure(userSettings.aiDriver)
  fleet:configure(userSettings.fleet, userSettings.language)
  lanBridge.setPerformanceOptions(userSettings)
end
local function roundMoney(value) return math.floor(value * 100 + 0.5) / 100 end
local function trimText(value) return dataStore:trimText(value) end
local function createDefaultDriverProfile() return dataStore:createDefaultProfile() end
local function sanitizeDriverProfile(source, requireSchema) return dataStore:sanitizeProfile(source, requireSchema) end
local function createDefaultUserProgress() return dataStore:createDefaultProgress() end
local function applyUserProgressToState()
  if not userProgress then return end
  state.balance = userProgress.balance or 0
  state.rating = userProgress.rating or 5
  state.ratingTotal = userProgress.ratingTotal or 0
  state.ratingCount = userProgress.ratingCount or 0
  state.completedRides = userProgress.completedRides or 0
end
local function syncUserProgressFromState()
  if not userProgress then userProgress = createDefaultUserProgress() end
  userProgress.schemaVersion = 1
  userProgress.modVersion = modVersion
  userProgress.balance = roundMoney(math.max(0, tonumber(state.balance) or 0))
  userProgress.rating = clampValue(tonumber(state.rating) or 5, 0, 5)
  userProgress.ratingTotal = math.max(0, tonumber(state.ratingTotal) or 0)
  userProgress.ratingCount = math.max(0, math.floor(tonumber(state.ratingCount) or 0))
  userProgress.completedRides = math.max(0, math.floor(tonumber(state.completedRides) or 0))
  userProgress.lastShift = shiftTracking:getHud().last
end
local function writeDriverProfile() return dataStore:writeProfile(driverProfile) end
local function writeUserProgress()
  syncUserProgressFromState()
  return dataStore:writeProgress(userProgress)
end
local function loadDriverProfile()
  driverProfile = dataStore:loadProfile()
end
local function loadUserProgress()
  userProgress, progressNeedsLegacyImport = dataStore:loadProgress()
  shiftTracking = shiftTracker.new(userProgress.lastShift)
  applyUserProgressToState()
  writeUserProgress()
end
local function randomRange(minimum, maximum) return minimum + (maximum - minimum) * math.random() end
local function shuffleArray(values)
  for index = #values, 2, -1 do
    local swapIndex = math.random(index)
    values[index], values[swapIndex] = values[swapIndex], values[index]
  end
  return values
end
local function buildOfferTypePlan(targetCount, allowMultiStop)
  local plan = {}
  local requestedDeliveryCount = targetCount *
    clampValue(tonumber(userSettings.deliveryOrderSharePercent) or 50, 0, 100) / 100
  local deliveryCount = math.floor(requestedDeliveryCount)
  if math.random() < requestedDeliveryCount - deliveryCount then
    deliveryCount = deliveryCount + 1
  end
  deliveryCount = math.min(targetCount, math.max(0, deliveryCount))
  local multiStopCount = 0
  if allowMultiStop then
    multiStopCount = math.min(
      math.max(0, targetCount - deliveryCount - 2),
      math.random(offerConfig.multiStopVisibleMin, offerConfig.multiStopVisibleMax)
    )
  end
  local rushCount = math.min(
    math.max(0, targetCount - deliveryCount - multiStopCount - 1),
    math.random(offerConfig.rushVisibleMin, offerConfig.rushVisibleMax)
  )

  for _ = 1, deliveryCount do table.insert(plan, "delivery") end
  for _ = 1, multiStopCount do table.insert(plan, "multiStop") end
  for _ = 1, rushCount do table.insert(plan, "rush") end
  while #plan < targetCount do table.insert(plan, "normal") end
  shuffleArray(plan)

  -- Never let a long-distance or multi-stop graph search block the first
  -- visible card. Specialized orders remain mixed throughout the rest of the
  -- pool, while dispatch can show a regular order promptly.
  if plan[1] ~= "normal" then
    for index = 2, #plan do
      if plan[index] == "normal" then
        plan[1], plan[index] = plan[index], plan[1]
        break
      end
    end
  end
  return plan
end

local function tableHasValues(value)
  return type(value) == "table" and next(value) ~= nil
end

local function getPlayerVehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function calculateEtaMinutes(distanceMeters)
  return math.max(0, distanceMeters or 0) / 1000 / averageCitySpeedKmh * 60
end

local function calculateFare(distanceMeters, waitingSeconds)
  local distanceKm = math.max(0, distanceMeters or 0) / 1000
  local etaMinutes = calculateEtaMinutes(distanceMeters) + math.max(0, waitingSeconds or 0) / 60
  return roundMoney(
    (balanceConfig.baseFare +
    distanceKm * balanceConfig.farePerKm +
    etaMinutes * balanceConfig.farePerMinute) *
    clampValue(tonumber(userSettings.economyMultiplier) or 1, 0.25, 5)
  )
end

local function calculateRatingBonusRate(rating)
  local threshold = balanceConfig.ratingBonusThreshold
  local progress = clampValue((tonumber(rating) or 0) - threshold, 0, 5 - threshold) /
    math.max(0.01, 5 - threshold)
  return progress * balanceConfig.maxRatingBonus
end

local function calculatePickupWaitSeconds(pickupDistance)
  return clampValue(
    calculateEtaMinutes(pickupDistance) * 60 * offerConfig.pickupTimeMultiplier +
      offerConfig.pickupTimeGraceSeconds,
    offerConfig.pickupTimeMinSeconds,
    offerConfig.pickupTimeMaxSeconds
  )
end

local function isPassengerDrivingPhase(phase)
  if phase == phases.toFuelStation and realisticFuel.detour.active then
    phase = realisticFuel.detour.previousPhase
  end
  return phase == phases.toStop or phase == phases.toDestination
end

local function isPassengerOnboardPhase(phase)
  if phase == phases.toFuelStation and realisticFuel.detour.active then
    phase = realisticFuel.detour.previousPhase
  end
  return phase == phases.boarding or phase == phases.toStop or
    phase == phases.stopWaiting or phase == phases.toDestination or
    phase == phases.passengerStopDemand or phase == phases.passengerForcedExit or
    phase == phases.driverAbandoning or phase == phases.alighting
end

local function getDriverAbandonmentPreview()
  local currentRating = clampValue(tonumber(state.rating) or 5, 0, 5)
  local extraLoss = driverAbandonmentExtraLoss[state.difficulty] or
    driverAbandonmentExtraLoss.standard
  local finalRating = clampValue(currentRating - 1 - currentRating * extraLoss, 0, 5)
  return {
    extraPercent = extraLoss * 100,
    ratingLoss = currentRating - finalRating,
    finalRating = finalRating
  }
end

local beginPassengerStopDemand

local function getPassengerCalmness()
  return clampValue(tonumber(trip and trip.passengerCalmness) or 50, 0, 100)
end

local function createPassengerPenaltyDisposition()
  local calmness = getPassengerCalmness()
  local calmRatio = calmness / 100
  local ignoreChance = balanceConfig.calmPenaltyIgnoreMaximum * math.pow(calmRatio, 1.15)
  local multiplier = 1
  if calmness < balanceConfig.calmPenaltyMultiplierThreshold then
    local sensitivity =
      (balanceConfig.calmPenaltyMultiplierThreshold - calmness) /
      balanceConfig.calmPenaltyMultiplierThreshold
    multiplier = 1 + math.pow(sensitivity, 1.25)
  end
  return {
    ignored = math.random() < ignoreChance,
    multiplier = multiplier
  }
end

local function applyPassengerPenalty(basePenalty, disposition)
  if not disposition or disposition.ignored then return 0 end
  return math.max(0, basePenalty or 0) * (disposition.multiplier or 1)
end

local function getPassengerStressThreshold()
  return balanceConfig.passengerStressThresholdMinimum +
    getPassengerCalmness() / 100 * balanceConfig.passengerStressThresholdCalmBonus
end

local function addPassengerStress(baseStress)
  if not trip or not isPassengerDrivingPhase(state.phase) or trip.passengerStopRequested then return end
  local calmRatio = getPassengerCalmness() / 100
  local sensitivity = 1.35 - calmRatio * 0.70
  trip.passengerStress = math.max(0, (trip.passengerStress or 0) +
    math.max(0, baseStress or 0) * sensitivity)
  if trip.passengerStress >= getPassengerStressThreshold() and beginPassengerStopDemand then
    beginPassengerStopDemand()
  end
end

local function getPenaltyTotal()
  if not trip then return 0 end
  if trip.isDelivery then
    return clampValue((trip.cargoDamagePercent or 0) / 100, 0, 1)
  end
  return clampValue(
    (trip.speedPenalty or 0) +
    (trip.collisionPenalty or 0) +
    (trip.aggressionPenalty or 0) +
    (trip.pickupPenalty or 0) +
    (trip.fuelStopPenalty or 0),
    0,
    balanceConfig.maxTotalPenalty
  )
end

local function getAdjustedFare()
  if not trip then return 0 end
  if trip.finalFare then return trip.finalFare end
  local eligibleFare = trip.estimatedFare or 0
  if trip.isRush and trip.rushBonusLost then
    eligibleFare = trip.ratingAdjustedFare or trip.baseFare or eligibleFare
  end
  return roundMoney(eligibleFare * (1 - getPenaltyTotal()))
end

local function getRemainingDistance()
  if not state.active or not core_groundMarkers then return 0 end
  return math.max(0, core_groundMarkers.getPathLength() or 0)
end

local function getRouteProgress(remainingDistance)
  if state.phase == phases.toFuelStation and realisticFuel.detour.active then
    local total = math.max(1, realisticFuel.detour.routeDistance or remainingDistance)
    return clampValue(1 - remainingDistance / total, 0, 1), "До заправки"
  end
  if not trip then return 0, "Маршрут" end
  if state.phase == phases.toPickup then
    local total = math.max(1, trip.pickup.routeDistance or remainingDistance)
    return clampValue(1 - remainingDistance / total, 0, 1), "До пассажира"
  elseif state.phase == phases.boarding then
    return 1, "Посадка пассажира"
  elseif state.phase == phases.toStop or state.phase == phases.toDestination then
    local total = math.max(1, trip.rideDistance or remainingDistance)
    local completed = math.max(0, trip.completedRideDistance or 0)
    local legDistance = math.max(0, trip.currentLegDistance or remainingDistance)
    local traveledOnLeg = clampValue(legDistance - remainingDistance, 0, legDistance)
    return clampValue((completed + traveledOnLeg) / total, 0, 1),
      state.phase == phases.toStop and "До остановки" or "Прогресс поездки"
  elseif state.phase == phases.stopWaiting then
    local total = math.max(1, trip.rideDistance or 1)
    return clampValue(
      ((trip.completedRideDistance or 0) + (trip.currentLegDistance or 0)) / total,
      0,
      1
    ), "Ожидание на остановке"
  elseif state.phase == phases.alighting then
    return 1, "Высадка пассажира"
  elseif state.phase == phases.complete then
    return 1, "Поездка завершена"
  end
  return 0, "Маршрут"
end

function realisticFuel.adjustPassengerMood(delta, blockSeconds)
  if not trip then return 0 end
  delta = tonumber(delta) or 0
  if math.abs(delta) < 0.01 then return 0 end
  local currentMood = getPassengerCalmness()
  local initialMood = clampValue(
    tonumber(trip.passengerInitialCalmness) or currentMood,
    0,
    100
  )
  local nextMood, applied = passengerMood.apply(
    currentMood,
    initialMood,
    delta,
    balanceConfig.passengerMoodMaximumGain
  )
  if math.abs(applied) < 0.01 then return 0 end

  trip.passengerCalmness = nextMood
  trip.passengerMoodChangeId = (trip.passengerMoodChangeId or 0) + 1
  trip.passengerMoodChangeDirection = applied > 0 and "up" or "down"
  trip.passengerMoodChangeAmount = math.abs(applied)
  if applied > 0 then
    trip.passengerStress = math.max(
      0,
      (trip.passengerStress or 0) -
        applied * balanceConfig.passengerMoodStressRecovery
    )
  else
    trip.passengerMoodGoodDrivingBlockedTimer = math.max(
      trip.passengerMoodGoodDrivingBlockedTimer or 0,
      math.max(0, tonumber(blockSeconds) or 0)
    )
  end
  return applied
end

function realisticFuel.updatePassengerMood(dtSim)
  if not trip or trip.isDelivery then return end
  trip.passengerMoodGoodDrivingBlockedTimer = math.max(
    0,
    (trip.passengerMoodGoodDrivingBlockedTimer or 0) - math.max(0, dtSim or 0)
  )
  if state.phase ~= phases.toStop and state.phase ~= phases.toDestination then return end

  local progress = getRouteProgress(getRemainingDistance())
  local previousProgress = clampValue(
    tonumber(trip.passengerMoodLastProgress) or progress,
    0,
    1
  )
  trip.passengerMoodLastProgress = progress
  local progressDelta = math.max(0, progress - previousProgress)
  if progressDelta <= 0 or trip.passengerMoodGoodDrivingBlockedTimer > 0 then return end

  local accumulator, gain = passengerMood.consumeProgress(
    previousProgress,
    progress,
    trip.passengerMoodGainAccumulator,
    balanceConfig.passengerMoodPerfectRideGain
  )
  trip.passengerMoodGainAccumulator = accumulator
  if gain <= 0 then return end
  realisticFuel.adjustPassengerMood(gain, 0)
end

local function buildHudOffer(offer)
  if not offer then return nil end
  return {
    id = offer.id,
    passengerName = offer.passengerName,
    isDelivery = offer.isDelivery == true,
    cargoWeightKg = offer.cargoWeightKg or 0,
    cargoWeightBonusPercent = (offer.cargoWeightBonusRate or 0) * 100,
    cargoWeightBonusAmount = offer.cargoWeightBonusAmount or 0,
    cargoDamagePercent = offer.cargoDamagePercent or 0,
    passengerCalmness = offer.passengerCalmness or 50,
    pickupDistance = offer.pickup.routeDistance or 0,
    pickupEtaMinutes = calculateEtaMinutes(offer.pickup.routeDistance),
    rideDistance = offer.rideDistance,
    etaMinutes = offer.totalEtaMinutes or calculateEtaMinutes(offer.rideDistance),
    estimatedFare = offer.estimatedFare,
    baseFare = offer.baseFare,
    ratingAdjustedFare = offer.ratingAdjustedFare or offer.baseFare,
    ratingBonusPercent = (offer.ratingBonusRate or 0) * 100,
    ratingBonusAmount = offer.ratingBonusAmount or 0,
    pickupWaitSeconds = offer.pickupWaitLimit or 0,
    isMultiStop = offer.isMultiStop == true,
    stopCount = #(offer.stops or {}),
    stopWaitSeconds = stopWaitingDuration,
    isRush = offer.isRush,
    bonusPercent = offer.bonusPercent or 0,
    bonusAmount = offer.bonusAmount or 0,
    timeLimitMinutes = (offer.rushTimeLimit or 0) / 60
  }
end

local function buildHudOffers()
  local result = {}
  for _, offer in ipairs(offers) do
    table.insert(result, buildHudOffer(offer))
  end
  return result
end

local function buildHudPenaltyEvents()
  local result = {}
  for _, event in ipairs(trip and trip.penaltyEvents or {}) do
    table.insert(result, {
      id = event.id,
      kind = event.kind,
      label = event.label,
      detail = event.detail,
      fareAmount = event.fareAmount or 0,
      speedExcess = event.speedExcess or 0,
      duration = event.duration or 0,
      damage = event.damage or 0,
      cargoDamagePercent = event.cargoDamagePercent or 0,
      peakG = event.peakG or 0,
      lateSeconds = event.lateSeconds or 0,
      stationName = event.stationName or "",
      penaltyPercent = (event.penalty or 0) * 100
    })
  end
  return result
end

local function buildStopProgressMarkers()
  local result = {}
  if not trip or not trip.isMultiStop or not trip.stops then return result end

  local totalDistance = math.max(1, trip.rideDistance or 0)
  local cumulativeDistance = 0
  local currentStopIndex = trip.currentStopIndex or 0
  local allStopsCompleted = state.phase == phases.toDestination or
    state.phase == phases.alighting or state.phase == phases.complete

  for index, stop in ipairs(trip.stops) do
    cumulativeDistance = cumulativeDistance + math.max(0, stop.routeDistance or 0)
    table.insert(result, {
      index = index,
      progressPercent = clampValue(cumulativeDistance / totalDistance * 100, 0, 100),
      active = (state.phase == phases.toStop or state.phase == phases.stopWaiting) and
        currentStopIndex == index,
      completed = allStopsCompleted or currentStopIndex > index
    })
  end
  return result
end

function realisticFuel.buildHud()
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  local refueling = realisticFuel.refueling
  local vehicleStopped = vehicle ~= nil and getVehicleSpeedKmh(vehicle) <= 2
  local magic = realisticFuel.station and realisticFuel.station.magic == true
  local available = state.active and state.realisticMode and realisticFuel.station ~= nil and
    vehicle ~= nil and (magic or vehicleStopped or refueling.active)
  if available and realisticFuel.station.center then
    available = vehicle:getPosition():distance(realisticFuel.station.center) <=
      realisticFuel.station.radius
  end
  return {
    available = available == true,
    id = realisticFuel.station and realisticFuel.station.id or "",
    name = realisticFuel.station and realisticFuel.station.name or "",
    magic = magic == true,
    vehicleStopped = vehicleStopped == true,
    options = realisticFuel.options,
    balance = roundMoney(state.balance),
    refueling = {
      active = refueling.active == true,
      completing = refueling.completing == true,
      energyType = refueling.energyType or "",
      quantity = refueling.quantity or 0,
      cost = refueling.cost or 0,
      duration = refueling.duration or 0,
      elapsed = refueling.elapsed or 0,
      completionId = realisticFuel.refuelingCompletionId or 0,
      progress = refueling.duration > 0 and
        clampValue(refueling.elapsed / refueling.duration, 0, 1) or 0,
      remainingSeconds = math.max(0, (refueling.duration or 0) - (refueling.elapsed or 0))
    }
  }
end

local function getAutopilotTarget()
  if state.phase == phases.toFuelStation and realisticFuel.detour.active then return {pos = realisticFuel.detour.pos, exactApproach = true} end
  if state.phase == phases.toPickup and trip then return trip.pickup end
  if state.phase == phases.toStop and trip and trip.stops then
    return trip.stops[trip.currentStopIndex or 0]
  end
  if state.phase == phases.toDestination and trip then return trip.destination end
  return nil
end
local function buildHudState()
  local remainingDistance = getRemainingDistance()
  local rideRemainingDistance = 0
  local remainingStopWaitSeconds = 0
  local routeProgress, progressLabel = getRouteProgress(remainingDistance)

  if trip then
    if isPassengerDrivingPhase(state.phase) or state.phase == phases.stopWaiting then
      rideRemainingDistance = math.max(0, (trip.rideDistance or 0) * (1 - routeProgress))
      if trip.isMultiStop then
        local totalStops = #(trip.stops or {})
        local currentStop = trip.currentStopIndex or 1
        if state.phase == phases.toStop then
          remainingStopWaitSeconds = math.max(0, totalStops - currentStop + 1) * stopWaitingDuration
        elseif state.phase == phases.stopWaiting then
          remainingStopWaitSeconds = math.max(0, phaseTimer) +
            math.max(0, totalStops - currentStop) * stopWaitingDuration
        end
      end
    elseif state.phase == phases.toPickup or state.phase == phases.boarding then
      rideRemainingDistance = trip.rideDistance or 0
      remainingStopWaitSeconds = #(trip.stops or {}) * stopWaitingDuration
    end
  end

  local hudNextOffer = buildHudOffer(nextOffer)
  if hudNextOffer then
    hudNextOffer.timeRemaining = math.max(0, nextOfferTimer)
    hudNextOffer.duration = offerConfig.nextOfferDuration
    hudNextOffer.accepted = nextOfferAccepted
  end
  local abandonmentPreview = getDriverAbandonmentPreview()
  local profile = driverProfile or createDefaultDriverProfile()
  local autopilotTarget = getAutopilotTarget()

  return {
    active = state.active,
    phase = state.phase,
    phaseLabel = phaseLabels[state.phase] or phaseLabels.inactive,
    message = state.message,
    balance = roundMoney(state.balance),
    rating = state.rating,
    ratingCount = state.ratingCount,
    completedRides = state.completedRides,
    driverProfile = {fullName = profile.fullName, avatar = profile.avatar},
    currentVehicle = vehicleHistory.getCurrentHud(),
    passengerOnboard = trip ~= nil and isPassengerOnboardPhase(state.phase),
    deliveryOnboard = trip ~= nil and trip.isDelivery == true and
      isPassengerOnboardPhase(state.phase),
    offlinePenaltyExtraPercent = abandonmentPreview.extraPercent,
    offlinePenaltyRatingLoss = abandonmentPreview.ratingLoss,
    offlinePenaltyFinalRating = abandonmentPreview.finalRating,
    difficulty = state.difficulty,
    realisticMode = state.realisticMode == true,
    vehicleEnergy = realisticFuel.dashboardEnergy,
    fuelStation = realisticFuel.buildHud(),
    fuelDetour = {
      active = realisticFuel.detour.active == true,
      hadTrip = realisticFuel.detour.hadTrip == true,
      passengerOnboard = realisticFuel.detour.passengerOnboard == true,
      stationName = realisticFuel.detour.stationName or "",
      routeDistance = realisticFuel.detour.routeDistance or 0,
      penaltyPercent = realisticFuel.detour.penaltyPercent or 0,
      arrived = realisticFuel.detour.arrived == true
    },
    lan = lanBridge.getStatus(),
    autopilot = autopilot:getHud(
      state.active and autopilotTarget ~= nil,
      state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
    ),
    settings = userSettings,
    settingsNeedsLegacyImport = settingsNeedsLegacyImport,
    shift = shiftTracking:getHud(),
    shiftHistory = shiftHistory.buildHud(not state.active),
    fleet = fleet:getHud(state.balance, vehicleHistory.buildFleetGarage()),
    offers = buildHudOffers(),
    offerTargetCount = offerTargetCount,
    nextOffer = hudNextOffer,
    notification = phoneNotification,
    penaltyEvents = buildHudPenaltyEvents(),
    activeTripId = trip and trip.id or 0,
    passengerName = trip and trip.passengerName or "",
    isDelivery = trip and trip.isDelivery == true or false,
    cargoWeightKg = trip and trip.cargoWeightKg or 0,
    cargoWeightBonusPercent = trip and (trip.cargoWeightBonusRate or 0) * 100 or 0,
    cargoWeightBonusAmount = trip and trip.cargoWeightBonusAmount or 0,
    cargoDamagePercent = trip and trip.cargoDamagePercent or 0,
    passengerCalmness = trip and trip.passengerCalmness or 50,
    passengerInitialCalmness = trip and trip.passengerInitialCalmness or 50,
    passengerMoodMaximum = trip and math.min(
      100,
      (trip.passengerInitialCalmness or trip.passengerCalmness or 50) +
        balanceConfig.passengerMoodMaximumGain
    ) or 90,
    passengerMoodChangeId = trip and trip.passengerMoodChangeId or 0,
    passengerMoodChangeDirection = trip and trip.passengerMoodChangeDirection or "",
    passengerMoodChangeAmount = trip and trip.passengerMoodChangeAmount or 0,
    passengerStressPercent = trip and clampValue(
      (trip.passengerStress or 0) / math.max(1, getPassengerStressThreshold()) * 100,
      0,
      100
    ) or 0,
    forcedExitDuration = forcedExitDuration,
    forcedExitRemaining = (state.phase == phases.passengerForcedExit or
      state.phase == phases.driverAbandoning) and math.max(0, phaseTimer) or 0,
    earlyExitRatingLossPercent = trip and (trip.earlyExitRatingLoss or 0) * 100 or 0,
    driverAbandonmentRatingLoss = trip and (trip.driverAbandonmentRatingLoss or 0) or 0,
    driverAbandonmentExtraPercent = trip and (trip.driverAbandonmentExtraLoss or 0) * 100 or 0,
    estimatedFare = trip and trip.estimatedFare or 0,
    adjustedFare = getAdjustedFare(),
    tipAmount = trip and trip.tipAmount or 0,
    finalFare = trip and trip.finalFare or 0,
    rideRating = trip and trip.rideRating or 0,
    rideDistance = trip and trip.rideDistance or 0,
    distanceToTarget = remainingDistance,
    etaMinutes = calculateEtaMinutes(remainingDistance),
    rideEtaMinutes = calculateEtaMinutes(rideRemainingDistance) + remainingStopWaitSeconds / 60,
    routeProgress = routeProgress,
    progressLabel = progressLabel,
    pickupWaitLimit = trip and trip.pickupWaitLimit or 0,
    pickupTimeRemaining = trip and math.max(0, trip.pickupTimeRemaining or 0) or 0,
    pickupLate = trip and trip.pickupLate == true or false,
    pickupLateSeconds = trip and trip.pickupLateSeconds or 0,
    ratingBonusPercent = trip and (trip.ratingBonusRate or 0) * 100 or 0,
    ratingBonusAmount = trip and trip.ratingBonusAmount or 0,
    isMultiStop = trip and trip.isMultiStop == true or false,
    stopCount = trip and #(trip.stops or {}) or 0,
    currentStopIndex = trip and trip.currentStopIndex or 0,
    nextStopDistance = trip and trip.isMultiStop and state.phase ~= phases.toDestination and
      remainingDistance or 0,
    tripEvent = trip and trip.randomEvent and {
      kind = trip.randomEvent.kind or "none",
      active = trip.randomEvent.active == true,
      triggered = trip.randomEvent.triggered == true,
      condition = trip.randomEvent.condition or "",
      tipAmount = trip.tipAmount or 0
    } or {kind = "none"},
    stopProgressMarkers = buildStopProgressMarkers(),
    stopWaitDuration = stopWaitingDuration,
    stopWaitRemaining = state.phase == phases.stopWaiting and math.max(0, phaseTimer) or 0,
    rushOrder = trip and trip.isRush or false,
    rushBonusActive = trip and trip.isRush and not trip.rushBonusLost or false,
    rushBonusLost = trip and trip.rushBonusLost or false,
    rushBonusAmount = trip and trip.bonusAmount or 0,
    rushTimeLimit = trip and trip.rushTimeLimit or 0,
    rushTimeRemaining = trip and trip.isRush and
      (trip.rushTimeRemaining or trip.rushTimeLimit or 0) or 0,
    penaltyPercent = getPenaltyTotal() * 100,
    fuelEnoughForTrip = realisticFuel.dashboardEnergy.available == true and
      realisticFuel.dashboardEnergy.estimatedRangeKm * 1000 >=
        math.max(remainingDistance, rideRemainingDistance),
    speedLimit = trip and trip.speedLimit or 0,
    currentSpeed = trip and trip.currentSpeed or 0,
    penalties = {
      speedingPercent = (trip and trip.speedPenalty or 0) * 100,
      collisionPercent = (trip and trip.collisionPenalty or 0) * 100,
      aggressionPercent = (trip and trip.aggressionPenalty or 0) * 100,
      pickupPercent = (trip and trip.pickupPenalty or 0) * 100,
      fuelStopPercent = (trip and trip.fuelStopPenalty or 0) * 100,
      speedingEvents = trip and trip.speedingEvents or 0,
      collisions = trip and trip.collisionCount or 0,
      aggressionEvents = trip and trip.aggressionEvents or 0
    }
  }
end
local function notifyHud()
  local hudState = buildHudState()
  lanBridge.setState(hudState)
  hudPublisher.publishFull(hudState, guihooks.trigger, jsonEncode)
end
local function notifyHudPatch()
  local hudState = buildHudState()
  lanBridge.setState(hudState)
  if lanBridge.isConnected() then
    hudPublisher.publishPatch(hudState, guihooks.trigger, jsonEncode)
  else
    -- Keep the in-game UI App on simple authoritative full snapshots. Delta
    -- traffic is only enabled while the battery-sensitive phone client is
    -- actually connected.
    hudPublisher.publishFull(hudState, guihooks.trigger, jsonEncode)
  end
end
local function notifyProfile()
  syncUserProgressFromState()
  guihooks.trigger("TaxiDriverProfileData", {
    profile = driverProfile or createDefaultDriverProfile(),
    progress = userProgress or createDefaultUserProgress(),
    vehicles = vehicleHistory.buildHud(),
    avatarOptions = driverAvatarOptions
  })
end
local function getPassengerReviewEmoji(rideRating)
  local rating = clampValue(tonumber(rideRating) or 0, 0, 5)
  if rating >= 4.85 then return "🤩" end
  if rating >= 4.50 then return "😍" end
  if rating >= 4.05 then return "😄" end
  if rating >= 3.60 then return "😊" end
  if rating >= 3.10 then return "🙂" end
  if rating >= 2.60 then return "😐" end
  if rating >= 2.10 then return "😕" end
  if rating >= 1.55 then return "😠" end
  return "😡"
end
local function recordProgressEvent(passengerName, emoji, quality, fare, outcome, profileRating, orderRating, usedAutopilot)
  if not userProgress then userProgress = createDefaultUserProgress() end
  userProgress.sequence = math.max(0, math.floor(tonumber(userProgress.sequence) or 0)) + 1
  local timestamp = os.time()
  table.insert(userProgress.reviews, {
    id = userProgress.sequence,
    passengerName = trimText(passengerName) ~= "" and trimText(passengerName) or "Passenger",
    emoji = dataStore:isValidReviewEmoji(emoji) and emoji or "😐",
    quality = clampValue(tonumber(quality) or 0, 0, 100),
    fare = roundMoney(math.max(0, tonumber(fare) or 0)),
    rating = clampValue(tonumber(profileRating) or tonumber(state.rating) or 5, 0, 5),
    orderRating = clampValue(tonumber(orderRating) or tonumber(profileRating) or 0, 0, 5),
    usedAutopilot = usedAutopilot == true,
    timestamp = timestamp,
    outcome = tostring(outcome or "completed")
  })
  table.insert(userProgress.ratingHistory, {
    index = userProgress.sequence,
    value = roundMoney(clampValue(tonumber(state.rating) or 5, 0, 5)),
    timestamp = timestamp
  })
  table.insert(userProgress.balanceHistory, {
    index = userProgress.sequence,
    value = roundMoney(math.max(0, tonumber(state.balance) or 0)),
    timestamp = timestamp
  })
  if outcome == "completed" or outcome == "delivery" then
    if usedAutopilot == true then userProgress.aiRideCount = (userProgress.aiRideCount or 0) + 1 end
    table.insert(userProgress.aiRideHistory, {index = userProgress.sequence, value = userProgress.aiRideCount or 0, timestamp = timestamp})
  end
  writeUserProgress()
end

local function showPhoneNotification(key, values, severity)
  nextPhoneNotificationId = nextPhoneNotificationId + 1
  phoneNotification = {
    id = nextPhoneNotificationId,
    key = key,
    values = values or {},
    severity = severity or "info"
  }
  notifyHud()
end

function realisticFuel.recordBalanceHistory()
  if not userProgress then userProgress = createDefaultUserProgress() end
  userProgress.sequence = math.max(0, math.floor(tonumber(userProgress.sequence) or 0)) + 1
  table.insert(userProgress.balanceHistory, {
    index = userProgress.sequence,
    value = roundMoney(math.max(0, tonumber(state.balance) or 0)),
    timestamp = os.time()
  })
  writeUserProgress()
end

function realisticFuel.energyToReadableUnit(energy, energyType)
  local factor = realisticFuel.energyMJPerUnit[energyType]
  if not factor then return 0 end
  return math.max(0, tonumber(energy) or 0) / 1000000 / factor
end

function realisticFuel.readableUnitToEnergy(quantity, energyType)
  local factor = realisticFuel.energyMJPerUnit[energyType]
  if not factor then return 0 end
  return math.max(0, tonumber(quantity) or 0) * 1000000 * factor
end

function realisticFuel.resetDashboardEnergy()
  realisticFuel.dashboardEnergyRequestGeneration =
    realisticFuel.dashboardEnergyRequestGeneration + 1
  realisticFuel.dashboardEnergyPending = false
  realisticFuel.dashboardEnergyTimer = 0
  realisticFuel.dashboardEnergy = {
    available = false,
    energyType = "",
    quantity = 0,
    maxQuantity = 0,
    percent = 0,
    unit = "",
    estimatedRangeKm = 0
  }
end

function realisticFuel.deferDashboardEnergy()
  -- A callback belonging to the old vehicle VM may still arrive later. Its
  -- generation check prevents it from overwriting the stable vehicle state.
  realisticFuel.dashboardEnergyRequestGeneration =
    realisticFuel.dashboardEnergyRequestGeneration + 1
  realisticFuel.dashboardEnergyPending = false
  realisticFuel.dashboardEnergyTimer = 0
end

function realisticFuel.refreshDashboardEnergy()
  if realisticFuel.dashboardEnergyPending or vehicleScanGuard.isSuspended() then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
  if not vehicle then
    realisticFuel.resetDashboardEnergy()
    return
  end

  realisticFuel.dashboardEnergyPending = true
  local vehicleId = vehicle:getID()
  local requestGeneration = realisticFuel.dashboardEnergyRequestGeneration
  local scanGeneration = vehicleScanGuard.getGeneration()
  core_vehicleBridge.requestValue(vehicle, function(data)
    if requestGeneration ~= realisticFuel.dashboardEnergyRequestGeneration or
      scanGeneration ~= vehicleScanGuard.getGeneration() or
      not vehicleScanGuard.isRequestCurrent(scanGeneration) then
      return
    end
    realisticFuel.dashboardEnergyPending = false
    local currentVehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
    if not currentVehicle or tonumber(currentVehicle:getID()) ~= tonumber(vehicleId) then return end

    local tanks = type(data) == "table" and data[1] or nil
    local aggregated = {}
    for _, tank in ipairs(type(tanks) == "table" and tanks or {}) do
      local energyType = tostring(tank.energyType or "")
      local consumption = realisticFuel.config.estimatedConsumptionPer100Km[energyType]
      if consumption and consumption > 0 then
        local totals = aggregated[energyType] or {quantity = 0, maxQuantity = 0}
        totals.quantity = totals.quantity +
          realisticFuel.energyToReadableUnit(tank.currentEnergy, energyType)
        totals.maxQuantity = totals.maxQuantity +
          realisticFuel.energyToReadableUnit(tank.maxEnergy, energyType)
        aggregated[energyType] = totals
      end
    end

    local selected = nil
    for energyType, totals in pairs(aggregated) do
      local consumption = realisticFuel.config.estimatedConsumptionPer100Km[energyType]
      local estimatedRangeKm = totals.quantity / consumption * 100
      if not selected or estimatedRangeKm > selected.estimatedRangeKm then
        selected = {
          available = true,
          energyType = energyType,
          quantity = totals.quantity,
          maxQuantity = totals.maxQuantity,
          percent = totals.maxQuantity > 0 and
            clampValue(totals.quantity / totals.maxQuantity * 100, 0, 100) or 0,
          unit = realisticFuel.readableUnit[energyType] or "unit",
          estimatedRangeKm = estimatedRangeKm
        }
      end
    end

    realisticFuel.dashboardEnergy = selected or {
      available = false,
      energyType = "",
      quantity = 0,
      maxQuantity = 0,
      percent = 0,
      unit = "",
      estimatedRangeKm = 0
    }
    notifyHudPatch()
  end, "energyStorage")
end

function realisticFuel.updateDashboardEnergy(dtSim)
  if vehicleScanGuard.isSuspended() then return end
  realisticFuel.dashboardEnergyTimer = math.max(
    0,
    realisticFuel.dashboardEnergyTimer - math.max(0, dtSim or 0)
  )
  if realisticFuel.dashboardEnergyTimer <= 0 then
    realisticFuel.dashboardEnergyTimer = realisticFuel.config.dashboardRefreshInterval
    realisticFuel.refreshDashboardEnergy()
  end
end

function realisticFuel.getPrice(gasStation, energyType)
  local fixedPrice = realisticFuel.config.priceByEnergyType[tostring(energyType or "")]
  if fixedPrice then return fixedPrice end
  local facility = gasStation and (gasStation.facility or gasStation) or nil
  local stationId = facility and facility.id or nil
  if stationId and freeroam_facilities_fuelPrice and
    type(freeroam_facilities_fuelPrice.getFuelPrice) == "function" then
    local ok, price = pcall(
      freeroam_facilities_fuelPrice.getFuelPrice,
      stationId,
      energyType
    )
    if ok and tonumber(price) and tonumber(price) > 0 then return tonumber(price) end
  end
  return realisticFuel.config.fallbackPricePerUnit
end

function realisticFuel.isTypeAvailable(fuelTypes, energyType)
  if type(fuelTypes) ~= "table" then return true end
  return fuelTypes.any == true or fuelTypes[energyType] == true
end

function realisticFuel.buildTypeLookup(facility)
  local result = {}
  local values = facility and facility.energyTypes or {"any"}
  for _, energyType in ipairs(values or {}) do result[tostring(energyType)] = true end
  if not next(result) then result.any = true end
  return result
end

function realisticFuel.resetRefueling()
  realisticFuel.refueling = {
    active = false,
    completing = false,
    stationId = "",
    vehicleId = 0,
    energyType = "",
    quantity = 0,
    cost = 0,
    duration = 0,
    elapsed = 0,
    hudTimer = 0,
    updates = {}
  }
end

function realisticFuel.clearStation()
  realisticFuel.resetRefueling()
  realisticFuel.station = nil
  realisticFuel.stationFuelTypes = nil
  realisticFuel.options = {}
  realisticFuel.dataPending = false
  realisticFuel.dataTimer = 0
end

function realisticFuel.resetDetour()
  realisticFuel.routeRequestPending = false
  realisticFuel.detour = {
    active = false,
    previousPhase = nil,
    hadTrip = false,
    passengerOnboard = false,
    stationId = "",
    stationName = "",
    pos = nil,
    routeDistance = 0,
    previousRemainingDistance = 0,
    penaltyPercent = 0,
    penaltyApplied = false,
    arrived = false
  }
end

function realisticFuel.setStation(element)
  if not element or not element.facility then return end
  local facility = element.facility
  -- Raw POI ids may include marker-specific prefixes, while route targets use
  -- the stable facility id. Keep both trigger arrival and detour matching on
  -- the facility id so closing the fuel overlay always restores the route.
  local stationId = tostring(facility.id or element.id or "fuelStation")
  if realisticFuel.station and realisticFuel.station.id == stationId then return end

  local center, radius = nil, 0
  if freeroam_gasStations and type(freeroam_gasStations.gasStationCenterRadius) == "function" then
    local ok, stationCenter, stationRadius = pcall(
      freeroam_gasStations.gasStationCenterRadius,
      facility
    )
    if ok then
      center = stationCenter
      radius = tonumber(stationRadius) or 0
    end
  end

  realisticFuel.station = {
    id = stationId,
    name = "Gas Station",
    facility = facility,
    center = center,
    radius = math.max(15, radius + 12),
    magic = false
  }
  realisticFuel.stationFuelTypes = realisticFuel.buildTypeLookup(facility)
  realisticFuel.options = {}
  realisticFuel.dataTimer = 0
  if realisticFuel.detour.active and realisticFuel.detour.stationId == stationId then
    realisticFuel.detour.arrived = true
  end
  notifyHud()
end

function realisticFuel.refreshOptions()
  if realisticFuel.dataPending or not state.active or not state.realisticMode or
    not realisticFuel.station then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle then return end

  realisticFuel.dataPending = true
  local stationAtRequest = realisticFuel.station
  core_vehicleBridge.requestValue(vehicle, function(data)
    realisticFuel.dataPending = false
    if not state.active or not state.realisticMode or
      realisticFuel.station ~= stationAtRequest then return end
    local tanks = type(data) == "table" and data[1] or nil
    if type(tanks) ~= "table" then
      realisticFuel.options = {}
      return
    end

    local aggregated = {}
    for _, tank in ipairs(tanks) do
      local energyType = tostring(tank.energyType or "")
      if realisticFuel.energyMJPerUnit[energyType] and
        realisticFuel.isTypeAvailable(realisticFuel.stationFuelTypes, energyType) then
        local option = aggregated[energyType]
        if not option then
          option = {
            energyType = energyType,
            unit = realisticFuel.readableUnit[energyType] or "unit",
            currentQuantity = 0,
            maxQuantity = 0
          }
          aggregated[energyType] = option
        end
        option.currentQuantity = option.currentQuantity +
          realisticFuel.energyToReadableUnit(tank.currentEnergy, energyType)
        option.maxQuantity = option.maxQuantity +
          realisticFuel.energyToReadableUnit(tank.maxEnergy, energyType)
      end
    end

    local order = {gasoline = 1, diesel = 2, kerosine = 3, electricEnergy = 4, n2o = 5}
    local options = {}
    for energyType, option in pairs(aggregated) do
      option.pricePerUnit = realisticFuel.getPrice(stationAtRequest, energyType)
      option.consumptionPer100Km = realisticFuel.config.estimatedConsumptionPer100Km[energyType] or 0
      option.missingQuantity = math.max(0, option.maxQuantity - option.currentQuantity)
      option.affordableQuantity = math.min(
        option.missingQuantity,
        option.pricePerUnit > 0 and math.max(0, state.balance) / option.pricePerUnit or 0
      )
      option.currentPercent = option.maxQuantity > 0 and
        clampValue(option.currentQuantity / option.maxQuantity * 100, 0, 100) or 0
      option.maxCost = roundMoney(option.affordableQuantity * option.pricePerUnit)
      table.insert(options, option)
    end
    table.sort(options, function(a, b)
      return (order[a.energyType] or 99) < (order[b.energyType] or 99)
    end)
    realisticFuel.options = options
    notifyHud()
  end, "energyStorage")
end

function realisticFuel.purchase(energyType, requestedQuantity)
  if not state.active or not state.realisticMode or not realisticFuel.station or
    realisticFuel.refueling.active then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle or getVehicleSpeedKmh(vehicle) > 2 then return end

  energyType = tostring(energyType or "")
  requestedQuantity = math.max(0, tonumber(requestedQuantity) or 0)
  if not realisticFuel.energyMJPerUnit[energyType] or requestedQuantity <= 0 or
    not realisticFuel.isTypeAvailable(realisticFuel.stationFuelTypes, energyType) then return end

  local stationAtRequest = realisticFuel.station
  local vehicleId = vehicle:getID()
  core_vehicleBridge.requestValue(vehicle, function(data)
    if not state.active or not state.realisticMode or realisticFuel.refueling.active or
      realisticFuel.station ~= stationAtRequest or
      tonumber(state.activeVehicleId) ~= tonumber(vehicleId) then return end

    local tanks = type(data) == "table" and data[1] or nil
    if type(tanks) ~= "table" then return end
    local pricePerUnit = realisticFuel.getPrice(stationAtRequest, energyType)
    local availableBalance = roundMoney(math.max(0, tonumber(state.balance) or 0))
    local remainingRequested = math.min(
      requestedQuantity,
      pricePerUnit > 0 and availableBalance / pricePerUnit or 0
    )
    local purchasedQuantity = 0
    local maximumQuantity = 0
    local updates = {}

    for _, tank in ipairs(tanks) do
      if tostring(tank.energyType or "") == energyType then
        local currentEnergy = math.max(0, tonumber(tank.currentEnergy) or 0)
        local maxEnergy = math.max(currentEnergy, tonumber(tank.maxEnergy) or currentEnergy)
        maximumQuantity = maximumQuantity +
          realisticFuel.energyToReadableUnit(maxEnergy, energyType)
        if remainingRequested > 0 then
          local missingQuantity = realisticFuel.energyToReadableUnit(
            maxEnergy - currentEnergy,
            energyType
          )
          local quantity = math.min(missingQuantity, remainingRequested)
          if quantity > 0.0001 then
            table.insert(updates, {
              name = tank.name,
              energy = math.min(
                maxEnergy,
                currentEnergy + realisticFuel.readableUnitToEnergy(quantity, energyType)
              )
            })
            purchasedQuantity = purchasedQuantity + quantity
            remainingRequested = remainingRequested - quantity
          end
        end
      end
    end

    local chargedAmount = math.min(
      availableBalance,
      roundMoney(purchasedQuantity * pricePerUnit)
    )
    if purchasedQuantity <= 0.0001 or chargedAmount <= 0 then
      showPhoneNotification("notify_realisticNoMoney", {}, "warning")
      return
    end

    local duration = purchasedQuantity / realisticFuel.config.fuelRatePerSecond
    if energyType == "electricEnergy" then
      local percentagePoints = maximumQuantity > 0 and
        purchasedQuantity / maximumQuantity * 100 or 0
      duration = percentagePoints / realisticFuel.config.electricPercentRatePerSecond
    end
    realisticFuel.refueling = {
      active = true,
      completing = false,
      stationId = stationAtRequest.id,
      vehicleId = vehicleId,
      energyType = energyType,
      quantity = purchasedQuantity,
      cost = chargedAmount,
      duration = math.max(0.1, duration),
      elapsed = 0,
      hudTimer = 0,
      updates = updates
    }

    local soundEvent = energyType == "electricEnergy" and
      "event:>UI>Career>Fueling_Electric_Simple" or
      "event:>UI>Career>Fueling_Petrol_Simple"
    local vehiclePos = vehicle:getPosition()
    Engine.Audio.playOnce("AudioGui", soundEvent, {
      position = vec3(vehiclePos.x, vehiclePos.y, vehiclePos.z)
    })
    notifyHud()
  end, "energyStorage")
end

function realisticFuel.finishPurchase()
  local session = realisticFuel.refueling
  if not session.active or session.completing then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle or tonumber(vehicle:getID()) ~= tonumber(session.vehicleId) or
    not realisticFuel.station or realisticFuel.station.id ~= session.stationId then
    realisticFuel.resetRefueling()
    notifyHud()
    return
  end

  session.completing = true
  for _, update in ipairs(session.updates or {}) do
    core_vehicleBridge.executeAction(
      vehicle,
      "setEnergyStorageEnergy",
      update.name,
      update.energy
    )
  end
  state.balance = roundMoney(math.max(0, (tonumber(state.balance) or 0) - session.cost))
  shiftTracking:recordFuelCost(session.cost)
  if trip then
    trip.fuelCost = roundMoney((trip.fuelCost or 0) + session.cost)
    trip.refueledQuantity = (trip.refueledQuantity or 0) + session.quantity
  end
  realisticFuel.recordBalanceHistory()
  local completed = {
    energyType = session.energyType,
    quantity = session.quantity,
    cost = session.cost
  }
  realisticFuel.resetRefueling()
  realisticFuel.refuelingCompletionId = realisticFuel.refuelingCompletionId + 1
  realisticFuel.dashboardEnergyTimer = 0
  showPhoneNotification("notify_realisticRefueled", {
    quantity = string.format("%.1f", completed.quantity),
    unit = realisticFuel.readableUnit[completed.energyType] or "unit",
    cost = string.format("$%.2f", completed.cost),
    balance = string.format("$%.2f", state.balance)
  }, "success")
  realisticFuel.dataTimer = 0.15
  notifyHud()
end

function realisticFuel.updateRefueling(dtSim)
  local session = realisticFuel.refueling
  if not session.active or session.completing then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  local withinStation = realisticFuel.station and
    (not realisticFuel.station.center or vehicle and
      vehicle:getPosition():distance(realisticFuel.station.center) <= realisticFuel.station.radius)
  local valid = state.active and state.realisticMode and vehicle and realisticFuel.station and
    withinStation and
    tonumber(vehicle:getID()) == tonumber(session.vehicleId) and
    realisticFuel.station.id == session.stationId and getVehicleSpeedKmh(vehicle) <= 2
  if not valid then
    realisticFuel.resetRefueling()
    showPhoneNotification("notify_realisticFuelInterrupted", {}, "warning")
    notifyHud()
    return
  end

  session.elapsed = math.min(session.duration, session.elapsed + math.max(0, dtSim or 0))
  session.hudTimer = math.max(0, (session.hudTimer or 0) - math.max(0, dtSim or 0))
  if session.elapsed >= session.duration then
    realisticFuel.finishPurchase()
  elseif session.hudTimer <= 0 then
    session.hudTimer = hudUpdateInterval
    notifyHudPatch()
  end
end

function realisticFuel.refuelCarWrapper(gasStation, fuelTypes, vehicle)
  if not state.active or not state.realisticMode then
    if type(realisticFuel.originalRefuelCar) == "function" then
      return realisticFuel.originalRefuelCar(gasStation, fuelTypes, vehicle)
    end
    return
  end
  realisticFuel.setStation(gasStation)
end

function realisticFuel.activityGatherWrapper(elementData, activityData)
  if not state.active or not state.realisticMode then
    if type(realisticFuel.originalActivityGather) == "function" then
      return realisticFuel.originalActivityGather(elementData, activityData)
    end
    return
  end

  for _, element in ipairs(elementData or {}) do
    if element.type == "gasStation" then
      realisticFuel.setStation(element)
      -- Do not add the stock free-roam refueling action. TaxiDriver renders its
      -- own purchase UI and validates the amount against the driver balance.
      return
    end
  end
end

function realisticFuel.installEconomy()
  if realisticFuel.economyInstalled then return true end
  if not freeroam_gasStations or
    type(freeroam_gasStations.refuelCar) ~= "function" or
    type(freeroam_gasStations.onActivityAcceptGatherData) ~= "function" then
    return false
  end
  realisticFuel.originalRefuelCar = freeroam_gasStations.refuelCar
  realisticFuel.originalActivityGather = freeroam_gasStations.onActivityAcceptGatherData
  freeroam_gasStations.refuelCar = realisticFuel.refuelCarWrapper
  freeroam_gasStations.onActivityAcceptGatherData = realisticFuel.activityGatherWrapper
  realisticFuel.economyInstalled = true
  if settings.getValue("enableGasStationsInFreeroam") == false and gameplay_rawPois then
    gameplay_rawPois.clear()
  end
  if gameplay_markerInteraction and
    type(gameplay_markerInteraction.setForceReevaluateOpenPrompt) == "function" then
    gameplay_markerInteraction.setForceReevaluateOpenPrompt()
  end
  return true
end

function realisticFuel.restoreEconomy()
  if realisticFuel.economyInstalled and freeroam_gasStations then
    if freeroam_gasStations.refuelCar == realisticFuel.refuelCarWrapper and
      type(realisticFuel.originalRefuelCar) == "function" then
      freeroam_gasStations.refuelCar = realisticFuel.originalRefuelCar
    end
    if freeroam_gasStations.onActivityAcceptGatherData == realisticFuel.activityGatherWrapper and
      type(realisticFuel.originalActivityGather) == "function" then
      freeroam_gasStations.onActivityAcceptGatherData = realisticFuel.originalActivityGather
    end
  end
  realisticFuel.economyInstalled = false
  realisticFuel.originalRefuelCar = nil
  realisticFuel.originalActivityGather = nil
  realisticFuel.clearStation()
  if settings.getValue("enableGasStationsInFreeroam") == false and gameplay_rawPois then
    gameplay_rawPois.clear()
  end
  if gameplay_markerInteraction and
    type(gameplay_markerInteraction.setForceReevaluateOpenPrompt) == "function" then
    gameplay_markerInteraction.setForceReevaluateOpenPrompt()
  end
end

function realisticFuel.setVehicleEnergyLevels(vehicle, fuelLevel, electricLevel, callback)
  if not vehicle then return false end
  core_vehicleBridge.requestValue(vehicle, function(data)
    local tanks = type(data) == "table" and data[1] or nil
    local changedCount = 0
    for _, tank in ipairs(type(tanks) == "table" and tanks or {}) do
      local energyType = tostring(tank.energyType or "")
      if energyType == "gasoline" or energyType == "diesel" or
        energyType == "kerosine" or energyType == "kerosene" or
        energyType == "electricEnergy" then
        local maxEnergy = math.max(0, tonumber(tank.maxEnergy) or 0)
        if maxEnergy > 0 then
          local level = energyType == "electricEnergy" and electricLevel or fuelLevel
          core_vehicleBridge.executeAction(
            vehicle,
            "setEnergyStorageEnergy",
            tank.name,
            maxEnergy * clampValue(tonumber(level) or 0, 0, 1)
          )
          changedCount = changedCount + 1
        end
      end
    end
    if type(callback) == "function" then callback(changedCount > 0, changedCount) end
  end, "energyStorage")
  return true
end

function realisticFuel.initializeVehicle(vehicle)
  if not vehicle then return end
  local vehicleId = vehicle:getID()
  if realisticFuel.initializedVehicles[vehicleId] or
    realisticFuel.initializationPending[vehicleId] then return end
  realisticFuel.initializationPending[vehicleId] = true

  realisticFuel.setVehicleEnergyLevels(
    vehicle,
    realisticFuel.config.fuelInitialLevel,
    realisticFuel.config.electricInitialLevel,
    function(initialized)
      realisticFuel.initializationPending[vehicleId] = nil
      if initialized then
        realisticFuel.initializedVehicles[vehicleId] = true
        if state.active and state.realisticMode and
          tonumber(state.activeVehicleId) == tonumber(vehicleId) then
          showPhoneNotification("notify_realisticFuelSet", {}, "success")
        end
      elseif state.active and state.realisticMode then
        showPhoneNotification("notify_realisticFuelUnsupported", {}, "warning")
      end
    end
  )
end

function realisticFuel.updateStation(dtSim)
  if not state.active or not state.realisticMode or not realisticFuel.station then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle then
    realisticFuel.clearStation()
    notifyHud()
    return
  end

  realisticFuel.updateRefueling(dtSim)

  if realisticFuel.station.center and
    vehicle:getPosition():distance(realisticFuel.station.center) > realisticFuel.station.radius then
    local shouldResume = realisticFuel.detour.active and realisticFuel.detour.arrived
    realisticFuel.clearStation()
    if shouldResume and type(realisticFuel.resumeRoute) == "function" then
      realisticFuel.resumeRoute()
    end
    notifyHud()
    return
  end

  if realisticFuel.detour.active and realisticFuel.detour.arrived and
    realisticFuel.detour.passengerOnboard and not realisticFuel.detour.penaltyApplied and
    getVehicleSpeedKmh(vehicle) <= 2 then
    realisticFuel.applyPassengerWaitPenalty(
      realisticFuel.detour.stationId,
      realisticFuel.detour.stationName
    )
    realisticFuel.detour.penaltyApplied = true
    notifyHud()
  end

  realisticFuel.dataTimer = math.max(0, realisticFuel.dataTimer - math.max(0, dtSim or 0))
  if realisticFuel.dataTimer <= 0 then
    realisticFuel.dataTimer = 0.75
    realisticFuel.refreshOptions()
  end
end

local function clearNavigation()
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

local function restoreNavigationVisualSettings()
  if not navigationVisualOverrideActive then return end
  settings.setValue("showNavigationGroundmarkers", originalNavigationGroundmarkers)
  settings.setValue("showNavigationArrows", originalNavigationArrows)
  navigationVisualOverrideActive = false
  originalNavigationGroundmarkers = nil
  originalNavigationArrows = nil
end

local function applyNavigationVisualSettings()
  if userSettings.showRouteGuidance ~= false then
    restoreNavigationVisualSettings()
    return
  end

  if not navigationVisualOverrideActive then
    originalNavigationGroundmarkers = settings.getValue("showNavigationGroundmarkers") ~= false
    originalNavigationArrows = settings.getValue("showNavigationArrows") ~= false
    navigationVisualOverrideActive = true
  end
  settings.setValue("showNavigationGroundmarkers", false)
  settings.setValue("showNavigationArrows", false)
  if core_groundMarkerArrows then
    core_groundMarkerArrows.clearArrows()
  end
end

local function restoreMinimapDynamicZoom()
  if ui_apps_minimap_vehicles and minimapOriginalDrawPlayer and
    ui_apps_minimap_vehicles.drawPlayer == minimapWrappedDrawPlayer then
    ui_apps_minimap_vehicles.drawPlayer = minimapOriginalDrawPlayer
    minimapOriginalDrawPlayer = nil
    minimapWrappedDrawPlayer = nil
  end
  minimapZoomMultiplier = nil
end

local function installMinimapDynamicZoom()
  if minimapWrappedDrawPlayer then return end
  if not ui_apps_minimap_vehicles then
    extensions.load("ui_apps_minimap_vehicles")
  end
  if not ui_apps_minimap_vehicles or type(ui_apps_minimap_vehicles.drawPlayer) ~= "function" then
    return
  end

  minimapOriginalDrawPlayer = ui_apps_minimap_vehicles.drawPlayer
  local originalDrawPlayer = minimapOriginalDrawPlayer
  minimapWrappedDrawPlayer = function(dtReal, dtSim)
    local baseScale = originalDrawPlayer(dtReal, dtSim)
    if type(baseScale) ~= "number" or not state.active or not minimapOwned then
      return baseScale
    end

    local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
    local speedKmh = vehicle and getVehicleSpeedKmh(vehicle) or 0
    local speedRatio = clampValue(speedKmh / 120, 0, 1)
    local easedSpeed = speedRatio * speedRatio * (3 - 2 * speedRatio)
    local rawTargetMultiplier = 0.66 + (1.62 - 0.66) * easedSpeed
    local zoomIntensity = clampValue(
      tonumber(userSettings.dynamicZoomIntensity) or 100,
      0,
      200
    ) / 100
    local targetMultiplier = clampValue(
      1 + (rawTargetMultiplier - 1) * zoomIntensity,
      0.35,
      2.30
    )

    if not minimapZoomMultiplier then
      minimapZoomMultiplier = targetMultiplier
    else
      local frameTime = clampValue(tonumber(dtReal) or 0.016, 0, 0.1)
      local blend = 1 - math.exp(-frameTime * 2.4)
      minimapZoomMultiplier = minimapZoomMultiplier +
        (targetMultiplier - minimapZoomMultiplier) * blend
    end
    return baseScale * minimapZoomMultiplier
  end
  ui_apps_minimap_vehicles.drawPlayer = minimapWrappedDrawPlayer
end

local function hideNativeMinimap()
  restoreMinimapDynamicZoom()
  if ui_apps_minimap_minimap then
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverRouteInfo"); ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverSpeedLimit")
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverNotification"); ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverAutopilot")
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverFleetStatus")
    if minimapOwned then
      ui_apps_minimap_minimap.hide()
    end
  end
  if minimapOwned and minimapOriginalMode and minimapOriginalMode ~= "rect" then
    settings.setValue("minimapMode", minimapOriginalMode)
    if ui_apps_minimap_minimap then
      ui_apps_minimap_minimap.onMinimapSettingsChanged()
    end
  end
  minimapOriginalMode = nil
  minimapOwned = false
end

local function setNavigationTarget(target)
  if not core_groundMarkers or not target or not target.pos then return end
  applyNavigationVisualSettings()
  core_groundMarkers.setPath(target.pos, {
    clearPathOnReachingTarget = false,
    cutOffDrivability = minimumDrivability
  })
  autopilot:markRouteDirty()
end

local function addPenaltyEvent(kind, label, penalty, detail)
  if not trip then return nil end
  trip.penaltyEvents = trip.penaltyEvents or {}
  trip.nextPenaltyEventId = (trip.nextPenaltyEventId or 0) + 1
  local event = {
    id = trip.nextPenaltyEventId,
    kind = kind,
    label = label,
    detail = detail or "",
    penalty = math.max(0, penalty or 0)
  }
  table.insert(trip.penaltyEvents, 1, event)
  while #trip.penaltyEvents > 8 do table.remove(trip.penaltyEvents) end
  return event
end

local function clearNextOffer()
  nextOffer = nil
  nextOfferTimer = 0
  nextOfferAccepted = false
  offerGeneration.nextJob = nil
end

local function resetTripMetrics()
  if not trip then return end
  trip.speedPenalty = 0
  trip.collisionPenalty = 0
  trip.aggressionPenalty = 0
  trip.pickupPenalty = 0
  trip.fuelStopPenalty = 0
  trip.fuelVisitedStations = {}
  trip.pickupLate = false
  trip.pickupLateSeconds = 0
  trip.pickupPenaltyEvent = nil
  trip.pickupPenaltyDisposition = nil
  trip.speedingEvents = 0
  trip.collisionCount = 0
  trip.aggressionEvents = 0
  trip.speedingEpisodeTime = 0
  trip.speedingEpisodeCounted = false
  trip.speedingEpisodeDisposition = nil
  trip.activeSpeedingEvent = nil
  trip.collisionDamage = 0
  trip.collisionCooldown = 0
  trip.activeCollisionEvent = nil
  trip.activeCollisionDisposition = nil
  trip.activeDeliveryImpactDamage = 0
  trip.activeDeliveryImpactPercent = 0
  trip.cargoDamagePercent = 0
  trip.ratingCollisionCount = 0
  trip.aggressionCooldown = 0
  trip.aggressionActive = false
  trip.currentSpeed = 0
  trip.speedLimit = 0
  trip.lastDamage = telemetry.damage or 0
  trip.damageGraceTimer = 1.5
  trip.penaltyEvents = {}
  trip.nextPenaltyEventId = 0
  trip.nextOfferPrompted = false
  trip.nextOfferRetryTimer = 0
  trip.nextOfferFailureCount = 0
  trip.nextOfferDisabled = false
  trip.passengerStress = 0
  trip.passengerInitialCalmness = clampValue(
    tonumber(trip.passengerInitialCalmness) or tonumber(trip.passengerCalmness) or 50,
    0,
    100
  )
  trip.passengerMoodChangeId = 0
  trip.passengerMoodChangeDirection = ""
  trip.passengerMoodChangeAmount = 0
  trip.passengerMoodLastProgress = 0
  trip.passengerMoodGainAccumulator = 0
  trip.passengerMoodGoodDrivingBlockedTimer = 0
  trip.pickupMoodPenaltySteps = 0
  trip.speedMoodPenaltySteps = 0
  trip.passengerStopRequested = false
  trip.earlyExitRatingLoss = 0
end

local function preparePassengerRideMetrics()
  if not trip then return end
  trip.currentSpeed = 0
  trip.speedLimit = 0
  trip.lastDamage = telemetry.damage or 0
  trip.damageGraceTimer = 1.5
  trip.collisionCooldown = 0
  trip.activeCollisionEvent = nil
  trip.activeCollisionDisposition = nil
  trip.aggressionCooldown = 0
  trip.aggressionActive = false
  trip.activeSpeedingEvent = nil
  trip.speedingEpisodeTime = 0
  trip.speedingEpisodeCounted = false
  trip.speedingEpisodeDisposition = nil
end

local function stopModeInternal(message, showNotification, notificationKey)
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
  autopilot:disable(vehicle, "shiftStopped")
  if shiftTracking:getHud().active then
    local completedShift = shiftTracking:finish()
    shiftHistory.finishActive(vehicle, vehicleHistory.getCurrentShiftVehicle(),
      realisticFuel.dashboardEnergy, completedShift)
    writeUserProgress()
  end
  if trip and (trip.passengerDoorTriggerId or trip.cargoDoorTriggerId) and
    (state.phase == phases.boarding or state.phase == phases.alighting or
      state.phase == phases.passengerForcedExit or state.phase == phases.driverAbandoning) then
    if trip.isDelivery then toggleCargoAccess(vehicle, trip.cargoDoorTriggerId)
    else togglePassengerDoor(vehicle, trip.passengerDoorTriggerId) end
  end
  releaseForcedPassengerStop(vehicle)
  setTelemetryEnabled(vehicle, false)
  delivery.applyVehicleMass(vehicle, 0)
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  realisticFuel.restoreEconomy()
  realisticFuel.resetDetour()
  realisticFuel.resetDashboardEnergy()

  state.active = false
  state.phase = phases.inactive
  state.activeVehicleId = nil
  state.realisticMode = false
  state.message = message or ""
  trip = nil
  offers = {}
  offerGeneration.poolJob = nil
  offerGeneration.poolRequestedType = nil
  clearNextOffer()
  phaseTimer = 0
  offerTimer = 0

  if showNotification and message then
    showPhoneNotification(notificationKey or "notify_modeStopped", {}, "info")
  end
  notifyHud()
end

local function createOffer(requestedType, generationFailureCount)
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
  if not vehicle then
    return nil, "Сначала выберите автомобиль"
  end

  local vehiclePos = vehicle:getPosition()
  local vehicleDir = vehicle:getDirectionVector()
  local pickup, pickupError = chooseTaxiStopPoint(
    vehiclePos,
    vehicleDir,
    minPickupDistance,
    maxPickupDistance
  )
  if not pickup then return nil, pickupError end

  local isDelivery = requestedType == "delivery" or
    (requestedType == nil and math.random() <
      clampValue(tonumber(userSettings.deliveryOrderSharePercent) or 50, 0, 100) / 100)
  local wantsMultiStop = not isDelivery and (
    requestedType == "multiStop" or
    (requestedType == nil and math.random() < offerConfig.multiStopChance)
  )
  local isMultiStop = wantsMultiStop and
    routePlanning.getStopCandidateCount() >= offerConfig.multiStopMinimumCandidates
  local stops = {}
  local routeOrigin = pickup
  local rideDistance = 0

  if isMultiStop then
    local relaxation = math.min(3, math.max(0, tonumber(generationFailureCount) or 0))
    local segmentMinimum = math.max(1500, offerConfig.multiStopSegmentMin - relaxation * 500)
    local stopCount = math.random(offerConfig.multiStopCountMin, offerConfig.multiStopCountMax)
    for _ = 1, stopCount do
      local stop, stopError = chooseTaxiStopPoint(
        routeOrigin.pos,
        routeOrigin.dir,
        segmentMinimum,
        offerConfig.multiStopSegmentMax,
        offerConfig.multiStopRouteAttempts
      )
      if not stop then return nil, stopError end
      local segmentDistance = stop.routeDistance
      if not segmentDistance then return nil, "Не удалось построить участок маршрута с остановками" end
      stop.routeDistance = segmentDistance
      rideDistance = rideDistance + segmentDistance
      table.insert(stops, stop)
      routeOrigin = stop
    end
  end

  local multiStopRelaxation = math.min(3, math.max(0, tonumber(generationFailureCount) or 0))
  local unlimitedRouteDistance = userSettings.unlimitedRouteDistance == true
  local destinationMinDistance = isDelivery and taxiConfig.delivery.minimumDistance or
    (isMultiStop and math.max(
      1500,
      offerConfig.multiStopSegmentMin - multiStopRelaxation * 500
    ) or minRideDistance)
  local destinationMaxDistance = nil
  if isMultiStop then
    destinationMaxDistance = offerConfig.multiStopSegmentMax
  elseif not unlimitedRouteDistance then
    destinationMaxDistance = isDelivery and taxiConfig.delivery.maximumDistance or maxRideDistance
  end
  local destination, destinationError = chooseTaxiStopPoint(
    routeOrigin.pos,
    routeOrigin.dir,
    destinationMinDistance,
    destinationMaxDistance,
    isDelivery and taxiConfig.delivery.routeAttempts or
      (isMultiStop and offerConfig.multiStopRouteAttempts or nil)
  )
  if not destination then return nil, destinationError end

  local destinationDistance = destination.routeDistance
  if not destinationDistance then
    return nil, "Полученный маршрут не прошёл проверку дистанции"
  end
  destination.routeDistance = destinationDistance
  rideDistance = rideDistance + destinationDistance

  if not isMultiStop and (rideDistance < minRideDistance or
    (not unlimitedRouteDistance and rideDistance > maxRideDistance)) then
    return nil, "Полученный маршрут не прошёл проверку дистанции"
  end

  local waitingSeconds = #stops * stopWaitingDuration
  local cargoWeightKg = isDelivery and delivery.generateWeight(taxiConfig.delivery) or 0
  local cargoWeightBonusRate = 0
  local cargoWeightBonusAmount = 0
  local baseFare = calculateFare(rideDistance, waitingSeconds)
  if isDelivery then
    local deliveryFare
    deliveryFare, cargoWeightBonusRate, cargoWeightBonusAmount = delivery.calculateFare(
      baseFare,
      cargoWeightKg,
      taxiConfig.delivery
    )
    baseFare = roundMoney(deliveryFare)
    cargoWeightBonusAmount = roundMoney(cargoWeightBonusAmount)
  end
  local ratingBonusRate = calculateRatingBonusRate(state.rating)
  local ratingAdjustedFare = roundMoney(baseFare * (1 + ratingBonusRate))
  local ratingBonusAmount = roundMoney(ratingAdjustedFare - baseFare)
  local isRush = not isDelivery and not isMultiStop and (
    requestedType == "rush" or
    (requestedType == nil and math.random() < offerConfig.rushChance)
  )
  local bonusPercent = 0
  local rushTimeLimit = 0
  if isRush then
    bonusPercent = math.floor(randomRange(
      offerConfig.rushBonusMin,
      offerConfig.rushBonusMax
    ) * 100 + 0.5)
    rushTimeLimit = math.max(75, (calculateEtaMinutes(rideDistance) * 60 + waitingSeconds) * randomRange(
      offerConfig.rushTimeRatioMin,
      offerConfig.rushTimeRatioMax
    ))
  end

  local estimatedFare = roundMoney(ratingAdjustedFare * (1 + bonusPercent / 100))
  local passengerCalmness = math.random(0, 100)
  local randomEvent = userSettings.randomEventsEnabled == true and
    tripEvents.create(isDelivery, isRush, isMultiStop) or {kind = "none"}
  if tripEvents.needsTarget(randomEvent) then
    local eventTarget = chooseTaxiStopPoint(
      destination.pos,
      destination.dir,
      1000,
      3500,
      12
    )
    if eventTarget then randomEvent.target = eventTarget else randomEvent = {kind = "none"} end
  end
  local offer = {
    id = nextOfferId,
    passengerName = isDelivery and "Delivery" or identity.createPassengerName(),
    isDelivery = isDelivery,
    cargoWeightKg = cargoWeightKg,
    cargoWeightBonusRate = cargoWeightBonusRate,
    cargoWeightBonusAmount = cargoWeightBonusAmount,
    cargoDamagePercent = 0,
    passengerCalmness = passengerCalmness,
    passengerInitialCalmness = passengerCalmness,
    pickup = pickup,
    destination = destination,
    stops = stops,
    isMultiStop = isMultiStop,
    rideDistance = rideDistance,
    totalEtaMinutes = calculateEtaMinutes(rideDistance) + waitingSeconds / 60,
    baseFare = baseFare,
    ratingAdjustedFare = ratingAdjustedFare,
    ratingBonusRate = ratingBonusRate,
    ratingBonusAmount = ratingBonusAmount,
    estimatedFare = estimatedFare,
    pickupWaitLimit = isDelivery and 0 or calculatePickupWaitSeconds(pickup.routeDistance),
    isRush = isRush,
    bonusPercent = bonusPercent,
    bonusAmount = roundMoney(estimatedFare - ratingAdjustedFare),
    rushTimeLimit = rushTimeLimit,
    randomEvent = randomEvent
  }
  nextOfferId = nextOfferId + 1
  return offer
end

local function createDiverseOffer(requestedType, generationFailureCount, strictEndpoints)
  local references = {}
  for _, offer in ipairs(offers) do table.insert(references, offer) end
  if trip then table.insert(references, trip) end
  if nextOffer then table.insert(references, nextOffer) end

  local fallback, fallbackError = nil, nil
  local diversityAttempts = requestedType == "delivery" and
    taxiConfig.delivery.diversityAttempts or offerConfig.routeDiversityAttempts
  for attempt = 1, diversityAttempts do
    local candidate, errorMessage = createOffer(
      requestedType,
      (generationFailureCount or 0) + attempt - 1
    )
    if candidate then
      fallback = fallback or candidate
      if routeDiversity.isDiverse(
        candidate,
        references,
        offerGeneration.recentRoutes,
        offerConfig,
        strictEndpoints
      ) then
        return candidate
      end
    else
      fallbackError = errorMessage or fallbackError
    end
    if attempt < diversityAttempts then offerGenerator.yield() end
  end

  -- Sparse maps must remain playable even when the requested spatial separation
  -- cannot be achieved after several incremental generation attempts.
  return fallback, fallbackError
end

local function scheduleNextOffer()
  offerTimer = randomRange(offerConfig.intervalMin, offerConfig.intervalMax)
end

local function beginSearching(message)
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  realisticFuel.resetDetour()
  trip = nil
  offers = {}
  clearNextOffer()
  state.phase = phases.searching
  state.message = message or "Ищем пассажиров поблизости"
  phaseTimer = 0
  offerTargetCount = math.random(offerConfig.minVisible, offerConfig.maxVisible)
  offerTypePlan = buildOfferTypePlan(offerTargetCount, true)
  offerGeneration.failures = 0
  offerGeneration.multiStopUnavailableForPool = false
  offerGeneration.poolJob = nil
  offerGeneration.poolRequestedType = nil
  offerGeneration.nextJob = nil
  offerTimer = offerConfig.initialDelay
  notifyHud()
end

local function addOffer(dtSim)
  if #offers >= offerTargetCount then return end

  if not offerGeneration.poolJob then
    local plannedType = offerTypePlan[#offers + 1]
    local requestedType = plannedType
    if plannedType == "multiStop" and
      (offerGeneration.failures >= 1 or offerGeneration.multiStopUnavailableForPool) then
      requestedType = "normal"
    end
    offerGeneration.poolRequestedType = requestedType
    local strictDiversity = #offers < math.ceil(
      offerTargetCount * offerConfig.routeDiversityMinimumShare
    )
    offerGeneration.poolJob = offerGenerator.create(function()
      return createDiverseOffer(requestedType, offerGeneration.failures, strictDiversity)
    end, offerConfig.generationStepInterval)
  end

  local status, offer, errorMessage = offerGenerator.step(offerGeneration.poolJob, dtSim)
  if status == "pending" then return end
  local requestedType = offerGeneration.poolRequestedType
  offerGeneration.poolJob = nil
  offerGeneration.poolRequestedType = nil
  if status == "error" then
    errorMessage = offer
    offer = nil
  end

  if offer then
    if requestedType == "multiStop" and not offer.isMultiStop then
      offerGeneration.multiStopUnavailableForPool = true
    end
    rememberOfferStops(offer)
    table.insert(offers, offer)
    offerGeneration.failures = 0
    state.message = string.format("Доступно заказов: %d", #offers)
    notifyHud()
  else
    if requestedType == "multiStop" then
      offerGeneration.multiStopUnavailableForPool = true
    end
    offerGeneration.failures = offerGeneration.failures + 1
    log("W", logTag, errorMessage or "Unable to generate taxi offer")
    if offerGeneration.failures >= 2 then
      offerTimer = randomRange(
        offerConfig.generationFailureBackoffMin,
        offerConfig.generationFailureBackoffMax
      )
      return
    end
  end
  scheduleNextOffer()
end

local function startAcceptedOffer(selected)
  if not selected then return false, "Заказ больше недоступен" end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle then return false, "Активный автомобиль недоступен" end
  offerGeneration.poolJob = nil
  offerGeneration.poolRequestedType = nil

  local pickupDistance = calculateRouteDistance(vehicle:getPosition(), selected.pickup.pos)
  if not pickupDistance then return false, "Не удалось построить маршрут к пассажиру" end
  selected.pickup.routeDistance = pickupDistance
  selected.pickupWaitLimit = selected.isDelivery and 0 or calculatePickupWaitSeconds(pickupDistance)

  clearNextOffer()
  routeDiversity.remember(
    offerGeneration.recentRoutes,
    selected,
    offerConfig.recentRouteLimit,
    offerConfig.routeDiversityCellSize
  )
  trip = selected
  offers = {}
  resetTripMetrics()
  trip.pickupTimeRemaining = trip.pickupWaitLimit
  trip.completedRideDistance = 0
  trip.currentLegDistance = 0
  trip.currentStopIndex = 0
  trip.startFuelQuantity = realisticFuel.dashboardEnergy.available and
    realisticFuel.dashboardEnergy.quantity or nil
  trip.startFuelType = realisticFuel.dashboardEnergy.energyType
  trip.refueledQuantity = 0
  trip.fuelCost = 0
  trip.usedAutopilot = false

  state.phase = phases.toPickup
  state.message = trip.isDelivery and "Drive to the cargo" or
    string.format("Пассажир: %s", trip.passengerName)
  phaseTimer = 0
  setNavigationTarget(trip.pickup)
  if trip.isDelivery then
    showPhoneNotification("notify_deliveryAccepted", {}, "success")
  else
    showPhoneNotification("notify_orderAccepted", {name = trip.passengerName}, "success")
  end
  notifyHud()
  return true
end

local function acceptOffer(offerId)
  if not state.active or state.phase ~= phases.searching then
    return false, "Сейчас нельзя принять заказ"
  end

  local selected = nil
  for _, offer in ipairs(offers) do
    if offer.id == offerId then
      selected = offer
      break
    end
  end
  return startAcceptedOffer(selected)
end

local function scheduleNextOfferRetry()
  if not trip then return end
  trip.nextOfferRetryTimer = randomRange(
    offerConfig.nextOfferRetryMin,
    offerConfig.nextOfferRetryMax
  )
end

local function recordNextOfferError(errorMessage)
  if not trip then return end
  offerGeneration.nextJob = nil
  trip.nextOfferFailureCount = (trip.nextOfferFailureCount or 0) + 1
  local errorLimit = math.max(1, tonumber(offerConfig.nextOfferErrorLimit) or 3)
  if trip.nextOfferFailureCount >= errorLimit then
    trip.nextOfferDisabled = true
    log("E", logTag, string.format(
      "Next-offer generation disabled for the current trip after %d errors: %s",
      trip.nextOfferFailureCount,
      tostring(errorMessage or "unknown error")
    ))
    return
  end

  scheduleNextOfferRetry()
  log("W", logTag, string.format(
    "Next-offer generation error %d/%d: %s",
    trip.nextOfferFailureCount,
    errorLimit,
    tostring(errorMessage or "unknown error")
  ))
end

local function updateNextOfferOpportunity(dtSim)
  if not trip or state.phase ~= phases.toDestination or trip.nextOfferDisabled then return end

  if nextOffer then
    if not nextOfferAccepted then
      nextOfferTimer = math.max(0, nextOfferTimer - dtSim)
      if nextOfferTimer <= 0 then
        clearNextOffer()
        scheduleNextOfferRetry()
        notifyHud()
      end
    end
    return
  end

  if not trip.nextOfferPrompted then
    local progress = getRouteProgress(getRemainingDistance())
    if progress <= offerConfig.nextOfferProgressThreshold then return end
    trip.nextOfferPrompted = true
    trip.nextOfferRetryTimer = 0
  end

  trip.nextOfferRetryTimer = math.max(0, (trip.nextOfferRetryTimer or 0) - dtSim)
  if trip.nextOfferRetryTimer > 0 then return end

  if not offerGeneration.nextJob then
    offerGeneration.nextJob = offerGenerator.create(function()
      return createDiverseOffer(nil, 0, true)
    end, offerConfig.generationStepInterval)
  end
  local status, generatedOffer, errorMessage = offerGenerator.step(offerGeneration.nextJob, dtSim)
  if status == "pending" then return end
  offerGeneration.nextJob = nil
  if status == "error" then
    recordNextOfferError(generatedOffer)
    return
  end
  trip.nextOfferFailureCount = 0
  if generatedOffer then
    rememberOfferStops(generatedOffer)
    nextOffer = generatedOffer
    nextOfferTimer = offerConfig.nextOfferDuration
    nextOfferAccepted = false
    notifyHud()
  else
    scheduleNextOfferRetry()
    log("W", logTag, errorMessage or "Unable to generate next taxi offer")
  end
end

local function updateNextOfferOpportunitySafely(dtSim)
  local ok, errorMessage = xpcall(function()
    updateNextOfferOpportunity(dtSim)
  end, debug.traceback)
  if not ok then recordNextOfferError(errorMessage) end
end

local function failOrder(message, notificationKey)
  log("W", logTag, message or "Unable to create taxi order")
  clearNavigation()
  state.active = false
  state.phase = phases.error
  state.message = message or "Не удалось создать заказ"
  setTelemetryEnabled(getPlayerVehicle(), false)
  showPhoneNotification(notificationKey or "notify_orderUnavailable", {}, "warning")
  notifyHud()
end

local function beginBoarding()
  if not trip then return end
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  state.phase = phases.boarding
  state.message = trip.isDelivery and "Loading cargo" or
    "Открываем пассажирскую дверь"
  if phoneNotification and (phoneNotification.key == "notify_orderAccepted" or
    phoneNotification.key == "notify_deliveryAccepted") then
    phoneNotification = nil
  end
  phaseTimer = boardingDuration
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if trip.isDelivery then
    trip.cargoDoorTriggerId = toggleCargoAccess(vehicle, trip.cargoDoorTriggerId)
  else
    trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  end
  notifyHud()
end

local function updatePickupDeadline(dtSim)
  if not trip or trip.isDelivery or state.phase ~= phases.toPickup then return end
  local previousRemaining = trip.pickupTimeRemaining or trip.pickupWaitLimit or 0
  local rawRemaining = previousRemaining - dtSim
  trip.pickupTimeRemaining = math.max(0, rawRemaining)
  if userSettings.penaltyToggles.pickupDelay == false then return end
  if rawRemaining > 0 then return end

  local lateIncrement = dtSim
  if previousRemaining > 0 then lateIncrement = math.max(0, dtSim - previousRemaining) end
  trip.pickupLateSeconds = (trip.pickupLateSeconds or 0) + lateIncrement
  local targetPenalty = clampValue(
    balanceConfig.pickupLateBasePenalty +
      trip.pickupLateSeconds * balanceConfig.pickupLatePenaltyPerSecond,
    0,
    balanceConfig.maxPickupLatePenalty
  )

  if not trip.pickupLate then
    trip.pickupLate = true
    trip.pickupPenaltyDisposition = createPassengerPenaltyDisposition()
    trip.pickupMoodPenaltySteps = 1
    realisticFuel.adjustPassengerMood(
      -balanceConfig.passengerMoodPickupLateLoss,
      4
    )
    if not trip.pickupPenaltyDisposition.ignored then
      trip.pickupPenaltyEvent = addPenaltyEvent(
        "pickupDelay",
        "Опоздание к пассажиру",
        applyPassengerPenalty(targetPenalty, trip.pickupPenaltyDisposition),
        "Истёк срок подачи автомобиля"
      )
      showPhoneNotification("notify_pickupLate", {}, "warning")
    end
  end

  local moodPenaltySteps = 1 + math.floor(trip.pickupLateSeconds / 20)
  if moodPenaltySteps > (trip.pickupMoodPenaltySteps or 0) then
    realisticFuel.adjustPassengerMood(
      -(moodPenaltySteps - (trip.pickupMoodPenaltySteps or 0)) *
        balanceConfig.passengerMoodPickupLateStepLoss,
      4
    )
    trip.pickupMoodPenaltySteps = moodPenaltySteps
  end

  trip.pickupPenalty = applyPassengerPenalty(targetPenalty, trip.pickupPenaltyDisposition)
  if trip.pickupPenaltyEvent then
    trip.pickupPenaltyEvent.penalty = trip.pickupPenalty
    trip.pickupPenaltyEvent.lateSeconds = trip.pickupLateSeconds
    trip.pickupPenaltyEvent.detail = string.format("Опоздание %.0f с", trip.pickupLateSeconds)
  end
end

local function startPassengerLeg(target, phase)
  if not trip or not target then return end
  trip.currentLegDistance = math.max(0, target.routeDistance or 0)
  state.phase = phase
  phaseTimer = 0
  setNavigationTarget(target)
end

local function beginRide()
  if not trip then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if trip.isDelivery then
    toggleCargoAccess(vehicle, trip.cargoDoorTriggerId)
    delivery.applyVehicleMass(vehicle, trip.cargoWeightKg or 0)
  else
    togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  end
  preparePassengerRideMetrics()
  if trip.isRush then
    trip.rushTimeRemaining = trip.rushTimeLimit
    trip.rushBonusLost = false
  end
  trip.completedRideDistance = 0
  trip.currentStopIndex = 1
  state.message = trip.isDelivery and
    string.format("Cargo loaded: %.0f kg", trip.cargoWeightKg or 0) or trip.isRush and
    string.format("Срочный заказ: сохраните бонус $%.2f", trip.bonusAmount or 0) or
    string.format("%s в автомобиле", trip.passengerName)
  if trip.isDelivery then
    startPassengerLeg(trip.destination, phases.toDestination)
    showPhoneNotification("notify_deliveryLoaded", {
      weight = string.format("%.0f", trip.cargoWeightKg or 0)
    }, "success")
  elseif trip.isMultiStop and trip.stops and trip.stops[1] then
    startPassengerLeg(trip.stops[1], phases.toStop)
    showPhoneNotification("notify_multiStopStarted", {count = #trip.stops}, "success")
  else
    startPassengerLeg(trip.destination, phases.toDestination)
    showPhoneNotification("notify_passengerAboard", {}, "success")
  end
  if trip.randomEvent and trip.randomEvent.kind == "fragileCargo" then
    showPhoneNotification("notify_fragileCargo", {}, "warning")
  end
  notifyHud()
end

local function beginStopWaiting()
  if not trip or not trip.stops or not trip.stops[trip.currentStopIndex or 0] then return end
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  state.phase = phases.stopWaiting
  state.message = "Ожидание на промежуточной остановке"
  phaseTimer = stopWaitingDuration
  notifyHud()
end

local function resumeCurrentStop()
  if not trip or not trip.stops then return end
  local stop = trip.stops[trip.currentStopIndex or 0]
  if not stop then return end
  phaseTimer = 0
  state.message = "Вернитесь к промежуточной остановке"
  startPassengerLeg(stop, phases.toStop)
  notifyHud()
end

local function completeStopWaiting()
  if not trip then return end
  trip.completedRideDistance = math.min(
    trip.rideDistance or math.huge,
    (trip.completedRideDistance or 0) + (trip.currentLegDistance or 0)
  )

  local nextStopIndex = (trip.currentStopIndex or 1) + 1
  if trip.stops and trip.stops[nextStopIndex] then
    trip.currentStopIndex = nextStopIndex
    state.message = string.format("Следующая остановка: %d из %d", nextStopIndex, #trip.stops)
    startPassengerLeg(trip.stops[nextStopIndex], phases.toStop)
  else
    trip.currentStopIndex = #(trip.stops or {})
    state.message = "Все остановки завершены. Следуйте к месту назначения"
    startPassengerLeg(trip.destination, phases.toDestination)
  end
  showPhoneNotification("notify_stopComplete", {}, "success")
  notifyHud()
end

local function beginAlighting()
  if not trip then return end
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  state.phase = phases.alighting
  state.message = trip.isDelivery and "Unloading cargo" or
    "Открываем пассажирскую дверь"
  phaseTimer = alightingDuration
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if trip.isDelivery then
    trip.cargoDoorTriggerId = toggleCargoAccess(vehicle, trip.cargoDoorTriggerId)
  else
    trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  end
  notifyHud()
end
local function applyEarlyExitRatingLoss()
  if not trip or trip.earlyExitRatingApplied then return end
  local loss = earlyExitRatingLoss[state.difficulty] or earlyExitRatingLoss.standard
  trip.earlyExitRatingLoss = loss
  trip.earlyExitRatingApplied = true

  local currentRating = clampValue(tonumber(state.rating) or 5, 0, 5)
  state.rating = clampValue(currentRating * (1 - loss), 0, 5)
  if state.ratingCount <= 0 then state.ratingCount = 1 end
  state.ratingTotal = state.rating * state.ratingCount
  if not trip.reviewRecorded then
    trip.reviewRecorded = true
    recordProgressEvent(trip.passengerName, "😡", 0, 0, "passengerExit")
  else
    writeUserProgress()
  end
end
local function applyDriverAbandonmentRatingLoss()
  if not trip or trip.driverAbandonmentApplied then return end
  local preview = getDriverAbandonmentPreview()
  trip.driverAbandonmentApplied = true
  trip.driverAbandonmentExtraLoss = preview.extraPercent / 100
  trip.driverAbandonmentRatingLoss = preview.ratingLoss
  state.rating = preview.finalRating
  if state.ratingCount <= 0 then state.ratingCount = 1 end
  state.ratingTotal = state.rating * state.ratingCount
  trip.reviewRecorded = true
  recordProgressEvent(
    trip.isDelivery and "Delivery" or trip.passengerName,
    "🤬",
    0,
    0,
    trip.isDelivery and "deliveryAbandonment" or "driverAbandonment"
  )
end
beginPassengerStopDemand = function()
  if not trip or trip.isDelivery or not isPassengerDrivingPhase(state.phase) or
    trip.passengerStopRequested then return end
  trip.passengerStopRequested = true
  hideNativeMinimap()
  clearNavigation()
  realisticFuel.resetDetour()
  restoreNavigationVisualSettings()
  state.phase = phases.passengerStopDemand
  state.message = "Пассажир требует немедленно остановить автомобиль"
  phaseTimer = 0
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  setVehicleForcedStop(vehicle, true)
  notifyHud()
end

local function beginPassengerForcedExit(vehicle)
  if not trip then return end
  setVehicleForcedStop(vehicle, true)
  setVehicleFrozen(vehicle, true)
  applyEarlyExitRatingLoss()
  state.phase = phases.passengerForcedExit
  state.message = "Пассажир покидает автомобиль до завершения поездки"
  phaseTimer = forcedExitDuration
  trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  notifyHud()
end

local function completePassengerForcedExit(vehicle)
  if not trip then
    releaseForcedPassengerStop(vehicle)
    return
  end

  togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  releaseForcedPassengerStop(vehicle)
  trip.finalFare = 0

  if nextOfferAccepted and nextOffer then
    local acceptedOffer = nextOffer
    local success = startAcceptedOffer(acceptedOffer)
    if not success then
      clearNextOffer()
      beginSearching("Поиск следующего заказа")
    end
  else
    beginSearching("Поиск следующего заказа")
  end
end

local function beginDriverAbandonment()
  if not trip or not isPassengerOnboardPhase(state.phase) or state.phase == phases.driverAbandoning then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  clearNextOffer()
  trip.finalFare = 0
  applyDriverAbandonmentRatingLoss()
  state.phase = phases.driverAbandoning
  state.message = "Водитель досрочно завершает поездку"
  phaseTimer = forcedExitDuration
  setVehicleForcedStop(vehicle, true)
  setVehicleFrozen(vehicle, true)
  if not trip.isDelivery then
    trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  end
  notifyHud()
end
local function completeDriverAbandonment()
  stopModeInternal("Поездка отменена водителем", false)
end
local function finishRide()
  if not trip then return end

  clearNavigation()
  local penalty = getPenaltyTotal()
  local fareBeforeTip = getAdjustedFare()
  local tipAmount = tripEvents.calculateTip(
    trip.randomEvent,
    fareBeforeTip,
    penalty,
    trip.isRush and not trip.rushBonusLost
  )
  local fare = roundMoney(fareBeforeTip + tipAmount)
  local rideRating = trip.isDelivery and
    delivery.calculateRating(trip.cargoDamagePercent or 0, taxiConfig.delivery) or
    clampValue(
      5 - penalty * balanceConfig.ratingPenaltyScale -
      (trip.ratingCollisionCount or 0) * balanceConfig.collisionRatingPenalty,
      balanceConfig.minimumRideRating,
      5
    )

  trip.finalFare = fare
  trip.tipAmount = tipAmount
  trip.rideRating = rideRating
  state.balance = state.balance + fare
  state.ratingTotal = state.ratingTotal + rideRating
  state.ratingCount = state.ratingCount + 1
  state.rating = state.ratingTotal / state.ratingCount
  state.completedRides = state.completedRides + 1
  local penaltyLoss = math.max(0, (trip.estimatedFare or fareBeforeTip) - fareBeforeTip)
  local currentEnergy = realisticFuel.dashboardEnergy
  local fuelConsumed = 0
  if trip.startFuelQuantity and currentEnergy.available and
    currentEnergy.energyType == trip.startFuelType then
    fuelConsumed = math.max(0,
      trip.startFuelQuantity + (trip.refueledQuantity or 0) - currentEnergy.quantity
    )
  end
  vehicleHistory.recordRide({
    fare = fare,
    rating = rideRating,
    isDelivery = trip.isDelivery,
    penaltyLoss = penaltyLoss,
    cargoDamageLoss = trip.isDelivery and penaltyLoss or 0,
    fuelConsumed = fuelConsumed,
    fuelCost = trip.fuelCost or 0,
    rideDistanceMeters = trip.rideDistance or 0,
    usedAutopilot = trip.usedAutopilot == true
  })
  shiftTracking:recordRide(fare, rideRating, penaltyLoss, trip.usedAutopilot)
  if not trip.reviewRecorded then
    trip.reviewRecorded = true
    recordProgressEvent(
      trip.isDelivery and "Delivery" or trip.passengerName,
      getPassengerReviewEmoji(rideRating),
      rideRating / 5 * 100,
      fare,
      trip.isDelivery and "delivery" or "completed",
      state.rating,
      rideRating,
      trip.usedAutopilot
    )
  else
    writeUserProgress()
  end
  notifyProfile()
  state.phase = phases.complete
  state.message = string.format("Получено $%.2f", fare)
  phaseTimer = completedDuration

  delivery.applyVehicleMass(
    state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil,
    0
  )
  showPhoneNotification(
    trip.isDelivery and "notify_deliveryComplete" or "notify_rideComplete",
    {fare = string.format("$%.2f", fare), tip = string.format("$%.2f", tipAmount)},
    "success"
  )
  notifyHud()
end

local function updateSpeedPenalty(vehicle, dtSim)
  if not trip or trip.isDelivery or not isPassengerDrivingPhase(state.phase) then return end

  local speed = getVehicleSpeedKmh(vehicle)
  local speedLimit = routePlanning.getNearestRoadSpeedLimit(vehicle:getPosition())
  trip.currentSpeed = speed
  trip.speedLimit = speedLimit or 0

  if userSettings.penaltyToggles.speeding == false then
    trip.speedingEpisodeTime = 0
    trip.speedingEpisodeCounted = false
    trip.speedingEpisodeDisposition = nil
    trip.activeSpeedingEvent = nil
    trip.speedMoodPenaltySteps = 0
    return
  end

  if not speedLimit then
    trip.speedingEpisodeTime = 0
    trip.speedingEpisodeCounted = false
    trip.speedingEpisodeDisposition = nil
    trip.activeSpeedingEvent = nil
    trip.speedMoodPenaltySteps = 0
    return
  end

  local tolerance = math.max(
    balanceConfig.speedToleranceKmh,
    speedLimit * balanceConfig.speedToleranceRatio
  )
  local excess = speed - speedLimit - tolerance
  if excess > 0 then
    trip.speedingEpisodeTime = trip.speedingEpisodeTime + dtSim
    if trip.speedingEpisodeTime >= balanceConfig.speedGraceSeconds then
      if not trip.speedingEpisodeCounted then
        trip.speedingEpisodeStartPenalty = trip.speedPenalty
        trip.speedingEpisodeDisposition = createPassengerPenaltyDisposition()
        if not trip.speedingEpisodeDisposition.ignored then
          trip.activeSpeedingEvent = addPenaltyEvent(
            "speeding",
            "Превышение скорости",
            0,
            "Длительное превышение допустимого порога"
          )
        end
        realisticFuel.adjustPassengerMood(
          -passengerMood.speedingLoss(
            balanceConfig.passengerMoodSpeedingBaseLoss,
            excess
          ),
          6
        )
        trip.speedMoodPenaltySteps = 0
        addPassengerStress(5 + math.min(10, excess / 5))
      end

      local moodPenaltySteps = math.floor(math.max(
        0,
        trip.speedingEpisodeTime - balanceConfig.speedGraceSeconds
      ) / 8)
      if moodPenaltySteps > (trip.speedMoodPenaltySteps or 0) then
        realisticFuel.adjustPassengerMood(
          -(moodPenaltySteps - (trip.speedMoodPenaltySteps or 0)),
          6
        )
        trip.speedMoodPenaltySteps = moodPenaltySteps
      end

      local severity = excess / math.max(speedLimit, 30)
      trip.speedPenalty = clampValue(
        trip.speedPenalty + applyPassengerPenalty(
          severity * dtSim * balanceConfig.speedPenaltyRate,
          trip.speedingEpisodeDisposition
        ),
        0,
        balanceConfig.maxSpeedPenalty * 2
      )
      addPassengerStress(severity * dtSim * 1.4)

      if trip.activeSpeedingEvent then
        trip.activeSpeedingEvent.penalty = math.max(
          0,
          trip.speedPenalty - (trip.speedingEpisodeStartPenalty or 0)
        )
        trip.activeSpeedingEvent.detail = string.format(
          "+%.0f км/ч · %.1f с",
          speed - speedLimit,
          trip.speedingEpisodeTime
        )
        trip.activeSpeedingEvent.speedExcess = speed - speedLimit
        trip.activeSpeedingEvent.duration = trip.speedingEpisodeTime
      end
    end

    if trip.speedingEpisodeTime >= balanceConfig.speedGraceSeconds and not trip.speedingEpisodeCounted then
      trip.speedingEvents = trip.speedingEvents + 1
      trip.speedingEpisodeCounted = true
    end
  else
    trip.speedingEpisodeTime = 0
    trip.speedingEpisodeCounted = false
    trip.speedingEpisodeDisposition = nil
    trip.activeSpeedingEvent = nil
    trip.speedMoodPenaltySteps = 0
  end
end

local function updateRushTimer(dtSim)
  if not trip or not trip.isRush or trip.rushBonusLost then return end
  if not isPassengerDrivingPhase(state.phase) and state.phase ~= phases.stopWaiting then return end

  trip.rushTimeRemaining = math.max(0, (trip.rushTimeRemaining or trip.rushTimeLimit or 0) - dtSim)
  if trip.rushTimeRemaining > 0 then return end
  if userSettings.penaltyToggles.rushBonus == false then return end

  trip.rushBonusLost = true
  local bonusEvent = addPenaltyEvent(
    "bonus",
    "Бонус за срочность отменён",
    0,
    "Истёк лимит времени заказа"
  )
  if bonusEvent then bonusEvent.fareAmount = trip.bonusAmount or 0 end
  realisticFuel.adjustPassengerMood(
    -balanceConfig.passengerMoodRushExpiredLoss,
    8
  )
  state.message = "Время вышло: бонусная часть оплаты отменена"
  showPhoneNotification("notify_rushExpired", {}, "warning")
end

local function updateTripCooldowns(dtSim)
  if not trip then return end
  trip.collisionCooldown = math.max(0, (trip.collisionCooldown or 0) - dtSim)
  trip.aggressionCooldown = math.max(0, (trip.aggressionCooldown or 0) - dtSim)
  trip.damageGraceTimer = math.max(0, (trip.damageGraceTimer or 0) - dtSim)
end

local function updateRandomTripEvent(vehicle, dtSim)
  local event = trip and trip.randomEvent or nil
  if not event or event.kind == "none" then return false end

  if state.phase == phases.toPickup and tripEvents.updateBeforePickup(event, dtSim) then
    logger.info("autopilot", "trip_cancelled_by_passenger", {tripId = trip and trip.id or nil,
      elapsed = event.elapsed, triggerSeconds = event.triggerSeconds})
    beginSearching("Passenger cancelled the order")
    showPhoneNotification("notify_passengerCancelled", {}, "warning")
    return true
  end

  if state.phase ~= phases.toDestination or not vehicle or
    not tripEvents.shouldTriggerOnRoute(event, getRouteProgress(getRemainingDistance())) then
    return false
  end

  local target = event.target
  local extraDistance = math.max(0, tonumber(target and target.routeDistance) or 0)
  local incrementalFare = math.max(0, calculateFare(extraDistance, 0) - calculateFare(0, 0))
  local adjustedIncrement = roundMoney(incrementalFare * (1 + (trip.ratingBonusRate or 0)))
  trip.baseFare = roundMoney((trip.baseFare or 0) + incrementalFare)
  trip.ratingAdjustedFare = roundMoney((trip.ratingAdjustedFare or 0) + adjustedIncrement)
  trip.ratingBonusAmount = roundMoney((trip.ratingBonusAmount or 0) + adjustedIncrement - incrementalFare)
  trip.estimatedFare = roundMoney((trip.estimatedFare or 0) + adjustedIncrement)
  trip.rideDistance = math.max(0, trip.rideDistance or 0) + extraDistance
  trip.totalEtaMinutes = calculateEtaMinutes(trip.rideDistance) +
    #(trip.stops or {}) * stopWaitingDuration / 60

  if event.kind == "destinationChange" then
    local distance = calculateRouteDistance(vehicle:getPosition(), target.pos)
    if distance then target.routeDistance = distance end
    trip.destination = target
    startPassengerLeg(target, phases.toDestination)
    showPhoneNotification("notify_destinationChanged", {}, "info")
  elseif event.kind == "additionalStop" then
    local oldDestination = trip.destination
    trip.stops = {oldDestination}
    trip.isMultiStop = true
    trip.currentStopIndex = 1
    trip.destination = target
    trip.currentLegDistance = getRemainingDistance()
    state.phase = phases.toStop
    showPhoneNotification("notify_additionalStop", {}, "info")
  end
  notifyHud()
  return false
end

function realisticFuel.calculatePassengerWaitPenalty(stationId)
  if not trip or trip.isDelivery or not isPassengerOnboardPhase(state.phase) then return 0 end
  if userSettings.penaltyToggles.fuelStop == false then return 0 end
  if trip.fuelVisitedStations and trip.fuelVisitedStations[tostring(stationId or "")] then return 0 end
  local baseByDifficulty = {
    elementary = 0.006,
    easy = 0.009,
    standard = 0.012,
    professional = 0.018
  }
  local basePenalty = baseByDifficulty[state.difficulty] or baseByDifficulty.standard
  local calmRatio = getPassengerCalmness() / 100
  local calmMultiplier = 1.35 - calmRatio * 0.70
  local ratingRatio = clampValue(tonumber(state.rating) or 5, 0, 5) / 5
  local ratingMultiplier = 1.15 - ratingRatio * 0.35
  local calculated = clampValue(basePenalty * calmMultiplier * ratingMultiplier, 0.003, 0.03)
  return math.min(calculated, math.max(0, 0.06 - (trip.fuelStopPenalty or 0))) * 100
end

function realisticFuel.applyPassengerWaitPenalty(stationId, stationName)
  if not trip then return 0 end
  if userSettings.penaltyToggles.fuelStop == false then return 0 end
  local penalty = math.max(0, realisticFuel.detour.penaltyPercent or 0) / 100
  if penalty <= 0 then return 0 end
  trip.fuelVisitedStations = trip.fuelVisitedStations or {}
  trip.fuelVisitedStations[tostring(stationId or "")] = true
  trip.fuelStopPenalty = clampValue((trip.fuelStopPenalty or 0) + penalty, 0, 0.06)
  local event = addPenaltyEvent(
    "fuelStop",
    "Остановка на заправке",
    penalty,
    tostring(stationName or "")
  )
  if event then event.stationName = tostring(stationName or "") end
  realisticFuel.adjustPassengerMood(
    -math.ceil(clampValue(penalty * 200, 2, 6)),
    8
  )
  return realisticFuel.detour.penaltyPercent
end

function realisticFuel.beginDetour(facility, position, routeDistance, arrived)
  if not facility or not position or realisticFuel.detour.active then return false end
  local previousPhase = state.phase
  local passengerOnboard = trip ~= nil and not trip.isDelivery and
    isPassengerOnboardPhase(previousPhase)
  local penaltyPercent = passengerOnboard and
    realisticFuel.calculatePassengerWaitPenalty(facility.id) or 0
  realisticFuel.detour = {
    active = true,
    previousPhase = previousPhase,
    hadTrip = trip ~= nil,
    passengerOnboard = passengerOnboard,
    stationId = tostring(facility.id or "fuelStation"),
    stationName = tostring(facility.taxiDriverName or "Gas Station"),
    pos = position,
    routeDistance = math.max(0, tonumber(routeDistance) or 0),
    previousRemainingDistance = getRemainingDistance(),
    penaltyPercent = penaltyPercent,
    penaltyApplied = false,
    arrived = arrived == true
  }
  local activeVehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if activeVehicle and autopilot:isEnabled() then
    autopilot:disable(activeVehicle, "fuelStopRequested")
  end
  if arrived and passengerOnboard and activeVehicle and getVehicleSpeedKmh(activeVehicle) <= 2 then
    realisticFuel.applyPassengerWaitPenalty(
      facility.id,
      tostring(facility.taxiDriverName or "Gas Station")
    )
    realisticFuel.detour.penaltyApplied = true
  end
  state.phase = phases.toFuelStation
  state.message = "Следуйте к заправке"
  phaseTimer = 0
  if arrived then clearNavigation() else setNavigationTarget({pos = position}) end
  if facility.taxiDriverMagic == true then
    showPhoneNotification("notify_magicFuelAvailable", {}, "info")
  else
    showPhoneNotification("notify_fuelRouteSet", {
      station = realisticFuel.detour.stationName
    }, "info")
  end
  notifyHud()
  return true
end

function realisticFuel.resumeRoute()
  if not realisticFuel.detour.active then return end
  local previousPhase = realisticFuel.detour.previousPhase
  local previousRemainingDistance = realisticFuel.detour.previousRemainingDistance or 0
  local closeMagicStation = realisticFuel.station and realisticFuel.station.magic == true
  realisticFuel.resetDetour()
  if closeMagicStation then realisticFuel.clearStation() end
  clearNavigation()

  if previousPhase == phases.searching then
    state.phase = phases.searching
    state.message = #offers > 0 and
      string.format("Доступно заказов: %d", #offers) or
      "Поиск заказов"
  elseif previousPhase == phases.toPickup and trip then
    state.phase = phases.toPickup
    state.message = string.format("Пассажир: %s", trip.passengerName)
    local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
    local newDistance = vehicle and
      calculateRouteDistance(vehicle:getPosition(), trip.pickup.pos) or nil
    if newDistance then
      local traveled = math.max(0, (trip.pickup.routeDistance or previousRemainingDistance) - previousRemainingDistance)
      trip.pickup.routeDistance = traveled + newDistance
    end
    setNavigationTarget(trip.pickup)
  elseif previousPhase == phases.toStop and trip and trip.stops then
    state.phase = phases.toStop
    local target = trip.stops[trip.currentStopIndex or 0]
    local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
    local newDistance = vehicle and target and calculateRouteDistance(vehicle:getPosition(), target.pos) or nil
    if newDistance then
      local traveled = math.max(0, (trip.currentLegDistance or previousRemainingDistance) - previousRemainingDistance)
      trip.currentLegDistance = traveled + newDistance
    end
    setNavigationTarget(target)
  elseif previousPhase == phases.toDestination and trip then
    state.phase = phases.toDestination
    local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or getPlayerVehicle()
    local newDistance = vehicle and calculateRouteDistance(vehicle:getPosition(), trip.destination.pos) or nil
    if newDistance then
      local traveled = math.max(0, (trip.currentLegDistance or previousRemainingDistance) - previousRemainingDistance)
      trip.currentLegDistance = traveled + newDistance
    end
    setNavigationTarget(trip.destination)
  else
    beginSearching("Поиск заказов")
    return
  end
  notifyHud()
end

function realisticFuel.openMagicStation(vehicle)
  if not vehicle or realisticFuel.detour.active then return false end
  local facility = {
    id = "taxiDriverMagicFuel",
    energyTypes = {"any"},
    taxiDriverMagic = true,
    taxiDriverName = "Magic Fuel"
  }
  realisticFuel.station = {
    id = facility.id,
    name = facility.taxiDriverName,
    facility = facility,
    center = nil,
    radius = 0,
    magic = true
  }
  realisticFuel.stationFuelTypes = {any = true}
  realisticFuel.options = {}
  realisticFuel.dataTimer = 0
  local opened = realisticFuel.beginDetour(facility, vehicle:getPosition(), 0, true)
  if opened then realisticFuel.refreshOptions() end
  return opened
end

function realisticFuel.requestRoute()
  if not state.active or not state.realisticMode or realisticFuel.routeRequestPending then return end
  if realisticFuel.detour.active then
    if realisticFuel.station and realisticFuel.detour.arrived then notifyHud() end
    return
  end
  if state.phase ~= phases.searching and state.phase ~= phases.toPickup and
    state.phase ~= phases.toStop and state.phase ~= phases.toDestination then
    showPhoneNotification("notify_fuelRouteUnavailable", {}, "warning")
    return
  end

  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle then return end
  if realisticFuel.station and getVehicleSpeedKmh(vehicle) <= 2 then
    local facility = realisticFuel.station.facility
    realisticFuel.beginDetour(
      facility,
      realisticFuel.station.center or vehicle:getPosition(),
      0,
      true
    )
    return
  end

  local requestedPhase = state.phase
  local requestedVehicleId = vehicle:getID()
  realisticFuel.routeRequestPending = true
  core_vehicleBridge.requestValue(vehicle, function(data)
    realisticFuel.routeRequestPending = false
    if not state.active or not state.realisticMode or realisticFuel.detour.active or
      state.phase ~= requestedPhase or
      tonumber(state.activeVehicleId) ~= tonumber(requestedVehicleId) then return end
    local tanks = type(data) == "table" and data[1] or nil
    if type(tanks) ~= "table" then
      showPhoneNotification("notify_realisticFuelUnsupported", {}, "warning")
      return
    end

    local vehicleFuelTypes = {}
    for _, tank in ipairs(tanks) do
      local energyType = tostring(tank.energyType or "")
      if realisticFuel.energyMJPerUnit[energyType] then vehicleFuelTypes[energyType] = true end
    end

    local bestFacility, bestPosition, bestDistance = nil, nil, math.huge
    local facilities = freeroam_facilities and
      freeroam_facilities.getFacilitiesByType("gasStation") or {}
    for _, facility in ipairs(facilities or {}) do
      local stationTypes = realisticFuel.buildTypeLookup(facility)
      local compatible = stationTypes.any == true
      if not compatible then
        for energyType in pairs(vehicleFuelTypes) do
          if stationTypes[energyType] then compatible = true break end
        end
      end
      if compatible then
        local ok, center = pcall(freeroam_gasStations.gasStationCenterRadius, facility)
        if ok and center then
          local distance = calculateRouteDistance(vehicle:getPosition(), center)
          if distance and distance < bestDistance then
            bestFacility, bestPosition, bestDistance = facility, center, distance
          end
        end
      end
    end

    if not bestFacility then
      realisticFuel.openMagicStation(vehicle)
      return
    end
    realisticFuel.beginDetour(bestFacility, bestPosition, bestDistance, false)
  end, "energyStorage")
end

local function updateActiveMode(dtSim)
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle or be:getPlayerVehicleID(0) ~= state.activeVehicleId then
    stopModeInternal("Режим остановлен: активный автомобиль изменился", true, "notify_vehicleChanged")
    return
  end

  -- Taxi deadlines use simulation time. A zero simulation delta means that
  -- BeamNG is paused, so no offer, fare, boarding or passenger timer may move.
  if dtSim <= 0 then return end

  updateTripCooldowns(dtSim)
  if updateRandomTripEvent(vehicle, dtSim) then return end
  realisticFuel.updateStation(dtSim)
  realisticFuel.updatePassengerMood(dtSim)
  autopilot:suspend(vehicle, state.phase == phases.toFuelStation and realisticFuel.detour.arrived == true)
  local autopilotTarget = getAutopilotTarget()
  autopilot:update(vehicle, state.phase, autopilotTarget, dtSim)
  aiLogger:update(vehicle, state.phase, autopilotTarget,
    autopilot:getDiagnostics(vehicle, autopilotTarget, state.phase), dtSim)
  if trip and autopilot:isEnabled() then trip.usedAutopilot = true end

  if state.phase == phases.toFuelStation and realisticFuel.detour.active then
    local previousPhase = realisticFuel.detour.previousPhase
    if previousPhase == phases.searching and #offers < offerTargetCount then
      offerTimer = offerTimer - dtSim
      if offerTimer <= 0 then addOffer(dtSim) end
    elseif previousPhase == phases.toPickup and trip then
      updatePickupDeadline(dtSim)
    elseif (previousPhase == phases.toStop or previousPhase == phases.toDestination) and trip then
      updateRushTimer(dtSim)
      updateSpeedPenalty(vehicle, dtSim)
    end
  elseif state.phase == phases.searching then
    if #offers < offerTargetCount then
      offerTimer = offerTimer - dtSim
      if offerTimer <= 0 then addOffer(dtSim) end
    end
  elseif state.phase == phases.toPickup and trip then
    updatePickupDeadline(dtSim)
    if vehicle:getPosition():distance(trip.pickup.pos) <= arrivalRadius and getVehicleSpeedKmh(vehicle) <= maxArrivalSpeedKmh then
      beginBoarding()
    end
  elseif state.phase == phases.boarding then
    phaseTimer = phaseTimer - dtSim
    if phaseTimer <= 0 then beginRide() end
  elseif state.phase == phases.toStop and trip then
    updateRushTimer(dtSim)
    updateSpeedPenalty(vehicle, dtSim)
    if state.phase ~= phases.toStop then return end
    local stop = trip.stops and trip.stops[trip.currentStopIndex or 0] or nil
    if stop and vehicle:getPosition():distance(stop.pos) <= arrivalRadius and
      getVehicleSpeedKmh(vehicle) <= maxArrivalSpeedKmh then
      beginStopWaiting()
    end
  elseif state.phase == phases.stopWaiting and trip then
    updateRushTimer(dtSim)
    local stop = trip.stops and trip.stops[trip.currentStopIndex or 0] or nil
    if not stop or vehicle:getPosition():distance(stop.pos) > arrivalRadius or
      getVehicleSpeedKmh(vehicle) > maxArrivalSpeedKmh then
      resumeCurrentStop()
    else
      phaseTimer = math.max(0, phaseTimer - dtSim)
      if phaseTimer <= 0 then completeStopWaiting() end
    end
  elseif state.phase == phases.toDestination and trip then
    updateRushTimer(dtSim)
    updateSpeedPenalty(vehicle, dtSim)
    if state.phase ~= phases.toDestination then return end
    updateNextOfferOpportunitySafely(dtSim)
    if vehicle:getPosition():distance(trip.destination.pos) <= arrivalRadius and getVehicleSpeedKmh(vehicle) <= maxArrivalSpeedKmh then
      beginAlighting()
    end
  elseif state.phase == phases.passengerStopDemand and trip then
    setVehicleForcedStop(vehicle, true)
    if getVehicleSpeedKmh(vehicle) <= 2 then beginPassengerForcedExit(vehicle) end
  elseif state.phase == phases.passengerForcedExit and trip then
    setVehicleForcedStop(vehicle, true)
    phaseTimer = math.max(0, phaseTimer - dtSim)
    if phaseTimer <= 0 then completePassengerForcedExit(vehicle) end
  elseif state.phase == phases.driverAbandoning and trip then
    setVehicleForcedStop(vehicle, true)
    setVehicleFrozen(vehicle, true)
    phaseTimer = math.max(0, phaseTimer - dtSim)
    if phaseTimer <= 0 then completeDriverAbandonment() end
  elseif state.phase == phases.alighting then
    phaseTimer = phaseTimer - dtSim
    if phaseTimer <= 0 then
      if trip then
        if trip.isDelivery then toggleCargoAccess(vehicle, trip.cargoDoorTriggerId)
        else togglePassengerDoor(vehicle, trip.passengerDoorTriggerId) end
      end
      finishRide()
    end
  elseif state.phase == phases.complete then
    phaseTimer = phaseTimer - dtSim
    if phaseTimer <= 0 then
      if nextOfferAccepted and nextOffer then
        local acceptedOffer = nextOffer
        local success, errorMessage = startAcceptedOffer(acceptedOffer)
        if not success then
          clearNextOffer()
          showPhoneNotification("notify_nextUnavailable", {}, "warning")
          beginSearching("Поиск следующего заказа")
        end
      else
        beginSearching("Поиск следующего заказа")
      end
    end
  end
end

function M.startMode(restoredEnergy)
  if state.active then
    notifyHud()
    return
  end

  local vehicle = getPlayerVehicle()
  if not vehicle then
    failOrder("Сначала выберите автомобиль", "notify_noVehicle")
    return
  end

  local mapData = map.getMap()
  if not mapData or not tableHasValues(mapData.nodes) then
    failOrder("На текущей карте отсутствует дорожный граф", "notify_noRoadGraph")
    return
  end

  state.active = true
  state.activeVehicleId = vehicle:getID()
  state.realisticMode = userSettings.realisticMode == true
  state.message = ""
  realisticFuel.resetDashboardEnergy()
  if state.realisticMode then
    if not realisticFuel.installEconomy() then
      state.active = false
      state.activeVehicleId = nil
      state.realisticMode = false
      showPhoneNotification("notify_realisticFuelUnavailable", {}, "warning")
      return
    end
    if type(restoredEnergy) == "table" then
      realisticFuel.initializedVehicles[vehicle:getID()] = true
    else
      realisticFuel.initializeVehicle(vehicle)
    end
  else
    realisticFuel.restoreEconomy()
  end
  shiftTracking:start()
  local shiftVehicle = vehicleHistory.getCurrentShiftVehicle()
  shiftHistory.begin(
    shiftVehicle,
    type(restoredEnergy) == "table" and restoredEnergy or
      shiftHistory.dashboardEnergy(realisticFuel.dashboardEnergy),
    shiftTracking:getHud().current
  )
  setTelemetryEnabled(vehicle, true)
  beginSearching("Подключение к линии заказов")
end
function M.openVehicleSelector()
  -- Open BeamNG's native vehicle selection state. This also works when the
  -- command comes from the external Web UI through the game's UI bridge.
  minimapUiBlocked = true
  hideNativeMinimap()
  guihooks.trigger("ChangeState", {state = "menu.vehicles"})
end

function M.toggleAutopilot()
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  local wasEnabled = autopilot:isEnabled()
  local enabled = autopilot:toggle(vehicle, state.phase, getAutopilotTarget())
  if enabled and trip then trip.usedAutopilot = true end
  if not wasEnabled and not enabled then
    showPhoneNotification("notify_autopilotUnavailable", {}, "warning")
  end
  notifyHud()
  return enabled
end
function M.onAutopilotBypassComplete(vehicleId, success, reason)
  if tonumber(vehicleId) ~= tonumber(state.activeVehicleId) then return fleet:onBypassComplete(vehicleId, success, reason) end
  return autopilot:onBypassComplete(getObjectByID(vehicleId), success == true, getAutopilotTarget(), reason)
end
function M.onAutopilotRouteDone(vehicleId) return tonumber(vehicleId) == tonumber(state.activeVehicleId) and autopilot:onRouteDone(getObjectByID(vehicleId), getAutopilotTarget()) or fleet:onRouteDone(vehicleId) end
function M.resumeShift(shiftId)
  if state.active then return false end
  local restored = shiftHistory.restore(shiftId, function(result, energy)
    if result == "restored" then
      vehicleHistory.resetTracking(); vehicleHistory.refreshCurrentVehicle()
      realisticFuel.resetDashboardEnergy(); realisticFuel.dashboardEnergyTimer = 0; M.startMode(energy)
    else showPhoneNotification(result == "unavailable" and
      "notify_shiftUnavailable" or "notify_shiftRestoreFailed", {}, "warning") end
  end)
  notifyHud()
  return restored
end

function M.acceptOrder(offerId)
  local id = math.floor(tonumber(offerId) or -1)
  local success, errorMessage = acceptOffer(id)
  if not success then
    state.message = errorMessage
    showPhoneNotification("notify_orderUnavailable", {}, "warning")
    notifyHud()
  end
end

function M.acceptNextOffer(offerId)
  local id = math.floor(tonumber(offerId) or -1)
  if state.active and state.phase == phases.toDestination and nextOffer and
    nextOffer.id == id and nextOfferTimer > 0 then
    nextOfferAccepted = true
    notifyHud()
  end
end

function M.expireNextOffer(offerId)
  local id = math.floor(tonumber(offerId) or -1)
  if not state.active or not nextOffer or nextOfferAccepted or nextOffer.id ~= id then return end
  clearNextOffer()
  if trip then scheduleNextOfferRetry() end
  notifyHud()
end

function M.stopMode()
  if not state.active then
    state.phase = phases.inactive
    state.message = ""
    notifyHud()
    return
  end
  if trip and isPassengerOnboardPhase(state.phase) then
    showPhoneNotification("notify_offlinePassengerBlocked", {}, "warning")
    return
  end
  stopModeInternal("Режим такси завершён", true, "notify_modeStopped")
end

function M.confirmDriverAbandonment()
  if not state.active or not trip or not isPassengerOnboardPhase(state.phase) then return end
  beginDriverAbandonment()
end

function M.requestHudState()
  if vehicleScanGuard.isConfigurationOpen() then return end
  notifyHud()
end

function M.requestProfileData()
  if vehicleScanGuard.isConfigurationOpen() then return end
  notifyProfile()
end

function M.requestRealisticFuelData()
  if vehicleScanGuard.isConfigurationOpen() then return end
  realisticFuel.dataTimer = 0
  realisticFuel.refreshOptions()
end

function M.purchaseRealisticFuel(energyType, quantity)
  realisticFuel.purchase(energyType, quantity)
end

function M.requestFuelStop()
  realisticFuel.requestRoute()
end

function M.completeFuelStop()
  if not realisticFuel.refueling.active and realisticFuel.detour.active and
    realisticFuel.detour.arrived then
    realisticFuel.resumeRoute()
  end
end

function M.cancelFuelStop()
  if not realisticFuel.refueling.active then realisticFuel.resumeRoute() end
end

function M.onActivityAcceptGatherData(elementData, activityData)
  if not state.active or not state.realisticMode then return end
  local foundStation = false
  for _, element in ipairs(elementData or {}) do
    if element.type == "gasStation" then
      foundStation = true
      realisticFuel.setStation(element)
      break
    end
  end
  if not foundStation or type(activityData) ~= "table" then return end

  -- The dependency normally lets our wrapped handler suppress the stock
  -- action before it is built. Removing an already-collected action as well
  -- keeps this compatible with extension hook implementations that cache the
  -- original handler reference.
  for index = #activityData, 1, -1 do
    local activity = activityData[index]
    if activity and activity.sorting and activity.sorting.type == "gasStation" then
      table.remove(activityData, index)
    end
  end
end

function M.onGetRawPoiListForLevel(levelIdentifier, elements)
  if not state.active or not state.realisticMode or
    settings.getValue("enableGasStationsInFreeroam") ~= false then return end
  local facilities = freeroam_facilities and
    freeroam_facilities.getFacilities(levelIdentifier) or nil
  for _, facility in ipairs(facilities and facilities.gasStations or {}) do
    table.insert(elements, freeroam_gasStations.formatGasStationPoi(facility))
  end
end

function M.saveDriverProfile(incomingProfile)
  driverProfile = sanitizeDriverProfile(incomingProfile, false)
  writeDriverProfile()
  notifyProfile()
  notifyHud()
end

function M.setDifficulty(presetId)
  if applyDifficulty(tostring(presetId or "")) then
    userSettings.difficulty = state.difficulty
    writeUserSettings()
    notifyHud()
  end
end

function M.saveSettings(incomingSettings)
  local routeGuidanceChanged = userSettings.showRouteGuidance ~=
    (type(incomingSettings) ~= "table" or incomingSettings.showRouteGuidance ~= false)
  local previousDeliveryShare = userSettings.deliveryOrderSharePercent
  local previousUnlimitedRouteDistance = userSettings.unlimitedRouteDistance == true
  local sessionLanEnabled = type(incomingSettings) == "table" and
    incomingSettings.lanEnabled == true
  userSettings = dataStore:sanitizeSettings(incomingSettings, false)
  userSettings.lanEnabled = sessionLanEnabled
  settingsNeedsLegacyImport = false
  applyDifficulty(userSettings.difficulty); aiLogger:setEnabled(userSettings.aiDebugLogging == true)
  if userSettings.aiDebugLogging == true and autopilot:isEnabled() then aiLogger:start(state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil, state.phase, getAutopilotTarget()) end
  autopilot:configure(userSettings.aiDriver); autopilot:markRouteDirty(); fleet:configure(userSettings.fleet, userSettings.language)
  lanBridge.setPerformanceOptions(userSettings)
  lanBridge.setEnabled(userSettings.lanEnabled)
  writeUserSettings()

  if routeGuidanceChanged then
    restoreNavigationVisualSettings()
    if state.active then
      if state.phase == phases.toFuelStation and realisticFuel.detour.active then
        setNavigationTarget({pos = realisticFuel.detour.pos})
      elseif state.phase == phases.toPickup and trip then
        setNavigationTarget(trip.pickup)
      elseif state.phase == phases.toStop and trip.stops then
        setNavigationTarget(trip.stops[trip.currentStopIndex or 0])
      elseif state.phase == phases.toDestination then
        setNavigationTarget(trip.destination)
      end
    end
  end
  if state.phase == phases.searching and
    math.abs((previousDeliveryShare or 50) - userSettings.deliveryOrderSharePercent) > 0.001 then
    local rebuiltPlan = {}
    for _, offer in ipairs(offers) do
      table.insert(rebuiltPlan, offer.isDelivery and "delivery" or
        (offer.isMultiStop and "multiStop" or (offer.isRush and "rush" or "normal")))
    end
    local remainingPlan = buildOfferTypePlan(
      math.max(0, offerTargetCount - #rebuiltPlan),
      not offerGeneration.multiStopUnavailableForPool
    )
    for _, orderType in ipairs(remainingPlan) do table.insert(rebuiltPlan, orderType) end
    offerTypePlan = rebuiltPlan
    offerGeneration.poolJob = nil
    offerGeneration.poolRequestedType = nil
    offerTimer = math.min(offerTimer, 0.25)
  end
  if state.active and state.phase == phases.searching and
    previousUnlimitedRouteDistance ~= (userSettings.unlimitedRouteDistance == true) then
    beginSearching()
  end
  notifyHud()
end

function M.disableExternalPhone()
  userSettings.lanEnabled = false
  lanBridge.setEnabled(false)
  notifyHud()
end

-- Called only by a TaxiDriverHUD instance running through BeamNG's native
-- External UI bridge. A short heartbeat lets the in-game instance collapse
-- while the remote phone is actually connected.
function M.externalPhoneHeartbeat(token, view, visible, clientEpoch, clientRevision)
  local accepted = lanBridge.externalHeartbeat(token, view, visible)
  if vehicleScanGuard.isConfigurationOpen() then return accepted end
  if accepted and clientEpoch ~= nil and clientRevision ~= nil and
    hudPublisher.clientNeedsSync(clientEpoch, clientRevision) then
    notifyHud()
  end
  return accepted
end

function M.hudClientHeartbeat(clientEpoch, clientRevision)
  if vehicleScanGuard.isConfigurationOpen() then return false end
  if clientEpoch ~= nil and clientRevision ~= nil and
    hudPublisher.clientNeedsSync(clientEpoch, clientRevision) then
    notifyHud()
    return true
  end
  return false
end

function M.requestExternalMapData()
  if vehicleScanGuard.isConfigurationOpen() then return end
  lanBridge.requestExternalMap()
end

function M.requestExternalHudState()
  if vehicleScanGuard.isConfigurationOpen() then return end
  notifyHud()
end

function M.setExternalPhoneView(view, visible, token)
  return lanBridge.setExternalView(view, visible, token)
end

function M.cheatSetRating(value)
  local requestedRating = tonumber(value)
  if not requestedRating then
    log("W", logTag, "Cheat rating ignored: invalid value " .. tostring(value))
    return state.rating
  end
  local rating = clampValue(requestedRating, 0, 5)
  if not userProgress then userProgress = createDefaultUserProgress() end
  state.ratingCount = math.max(0, math.floor(tonumber(state.completedRides) or 0))
  state.rating = rating
  state.ratingTotal = rating * state.ratingCount
  userProgress.rating = rating
  userProgress.ratingCount = state.ratingCount
  userProgress.ratingTotal = state.ratingTotal
  for _, review in ipairs(userProgress.reviews or {}) do
    review.rating = rating
    review.orderRating = rating
    review.quality = rating / 5 * 100
    review.emoji = getPassengerReviewEmoji(rating)
  end
  for _, point in ipairs(userProgress.ratingHistory or {}) do
    point.value = roundMoney(rating)
  end
  vehicleHistory.setAllRatings(rating)
  shiftTracking:setAllRatings(rating)
  userProgress.lastShift = shiftTracking:getHud().last
  writeUserProgress()
  notifyProfile()
  notifyHud()
  log("I", logTag, string.format("Cheat rating applied: %.2f", rating))
  return rating
end

function M.cheatSetEnergyPercent(value)
  local percent = clampValue(tonumber(value) or 0, 0, 100)
  local vehicle = getPlayerVehicle()
  if not vehicle then return false end
  local vehicleId = vehicle:getID()
  return realisticFuel.setVehicleEnergyLevels(vehicle, percent / 100, percent / 100,
    function(changed, storageCount)
      logger.info("cheat", "energy_percent_applied", {
        percent = percent,
        storageCount = storageCount,
        vehicleId = vehicleId
      })
      if not changed then return end
      if realisticFuel.dashboardEnergy.available then
        realisticFuel.dashboardEnergy.quantity =
          realisticFuel.dashboardEnergy.maxQuantity * percent / 100
        realisticFuel.dashboardEnergy.percent = percent
      end
      realisticFuel.deferDashboardEnergy()
      notifyHud()
    end
  )
end

function M.cheatAddMoney(value)
  local amount = tonumber(value) or 0
  if amount ~= 1 and amount ~= 5 and amount ~= 10 and amount ~= 50 then return end
  state.balance = roundMoney(math.max(0, state.balance + amount))
  realisticFuel.recordBalanceHistory()
  notifyProfile()
  notifyHud()
end

function M.cheatAddRandomReview()
  local rating = math.random(100, 500) / 100
  recordProgressEvent(
    identity.createPassengerName(),
    getPassengerReviewEmoji(rating),
    rating / 5 * 100,
    0,
    "cheatReview",
    state.rating,
    rating,
    false
  )
  notifyProfile()
  notifyHud()
end

function M.cheatResetProgress()
  userProgress = createDefaultUserProgress()
  vehicleHistory.reset()
  applyUserProgressToState()
  writeUserProgress()
  notifyProfile()
  notifyHud()
end

local function canShowNativeMinimap(allowFleet)
  return minimapAppVisible and not minimapUiBlocked and ((state.active and (
    state.phase == phases.toPickup or
    state.phase == phases.toStop or
    state.phase == phases.toDestination or
    state.phase == phases.toFuelStation
  )) or allowFleet == true)
end

function M.setMinimapAppVisibility(visible)
  minimapAppVisible = visible == true
  if not minimapAppVisible then
    hideNativeMinimap()
  elseif not minimapUiBlocked then
    guihooks.trigger("TaxiDriverMinimapInvalidated")
  end
end

function M.setMinimapTransform(x, y, width, height, allowFleet)
  if not canShowNativeMinimap(allowFleet) then
    hideNativeMinimap()
    return
  end
  x, y = tonumber(x), tonumber(y)
  width, height = tonumber(width), tonumber(height)
  if not x or not y or not width or not height then return end
  if width <= 0 or height <= 0 then return end

  if not ui_apps_minimap_minimap then
    extensions.load("ui_apps_minimap_minimap")
  end
  if not ui_apps_minimap_minimap then return end

  if not minimapOwned then
    minimapOriginalMode = settings.getValue("minimapMode") or "circle"
    if minimapOriginalMode ~= "rect" then
      settings.setValue("minimapMode", "rect")
    end
    ui_apps_minimap_minimap.onMinimapSettingsChanged()
    minimapOwned = true
  end

  installMinimapDynamicZoom()

  ui_apps_minimap_minimap.setDrawTransform(
    clampValue(x, 0, 1),
    clampValue(y, 0, 1),
    clampValue(width, 0, 1),
    clampValue(height, 0, 1)
  )
end

function M.setMinimapOcclusions(
  routeX, routeY, routeWidth, routeHeight,
  speedX, speedY, speedWidth, speedHeight,
  notificationX, notificationY, notificationWidth, notificationHeight,
  autopilotX, autopilotY, autopilotWidth, autopilotHeight, fleetX, fleetY, fleetWidth, fleetHeight, allowFleet
)
  if not canShowNativeMinimap(allowFleet) then return end
  if not ui_apps_minimap_minimap then
    extensions.load("ui_apps_minimap_minimap")
  end
  if not ui_apps_minimap_minimap then return end

  local function updateOcclusion(id, x, y, width, height)
    x, y = tonumber(x), tonumber(y)
    width, height = tonumber(width), tonumber(height)
    if not x or not y or not width or not height or width <= 0 or height <= 0 then
      ui_apps_minimap_minimap.resetOcclusionTransform(id)
      return
    end

    x = clampValue(x, 0, 1)
    y = clampValue(y, 0, 1)
    width = clampValue(width, 0, 1 - x)
    height = clampValue(height, 0, 1 - y)
    if width <= 0 or height <= 0 then
      ui_apps_minimap_minimap.resetOcclusionTransform(id)
      return
    end

    ui_apps_minimap_minimap.setOcclusionTransform(id, x, y, width, height)
  end

  updateOcclusion("taxiDriverRouteInfo", routeX, routeY, routeWidth, routeHeight)
  updateOcclusion("taxiDriverSpeedLimit", speedX, speedY, speedWidth, speedHeight)
  updateOcclusion("taxiDriverNotification", notificationX, notificationY, notificationWidth, notificationHeight)
  updateOcclusion("taxiDriverAutopilot", autopilotX, autopilotY, autopilotWidth, autopilotHeight)
  updateOcclusion("taxiDriverFleetStatus", fleetX, fleetY, fleetWidth, fleetHeight)
end

function M.hideMinimap()
  hideNativeMinimap()
end

function M.onTelemetry(vehicleId, data)
  if vehicleId ~= state.activeVehicleId or type(data) ~= "table" then return end

  aiLogger:onVehicleTelemetry(data)
  telemetry.vehicleId = vehicleId
  telemetry.autopilotController = type(data.autopilotController) == "table" and data.autopilotController or telemetry.autopilotController
  telemetry.damage = tonumber(data.damage) or telemetry.damage
  telemetry.longitudinalG = tonumber(data.longitudinalG) or 0
  telemetry.lateralG = math.abs(tonumber(data.lateralG) or 0)

  if not trip or not isPassengerDrivingPhase(state.phase) then return end

  local damage = telemetry.damage
  local lastDamage = trip.lastDamage or damage
  if (trip.damageGraceTimer or 0) > 0 then
    trip.lastDamage = damage
  elseif damage < lastDamage then
    trip.lastDamage = damage
  elseif damage > lastDamage then
    local damageDelta = damage - lastDamage
    trip.lastDamage = damage

    if userSettings.penaltyToggles.cargoDamage ~= false and trip.isDelivery and
      (damageDelta >= taxiConfig.delivery.collisionDamageThreshold or
      ((trip.collisionCooldown or 0) > 0 and trip.activeCollisionEvent)) then
      local isNewImpact = (trip.collisionCooldown or 0) <= 0 or not trip.activeCollisionEvent
      if isNewImpact then
        trip.collisionCount = (trip.collisionCount or 0) + 1
        trip.activeDeliveryImpactDamage = 0
        trip.activeDeliveryImpactPercent = 0
        trip.activeCollisionEvent = addPenaltyEvent(
          "cargoDamage",
          "Package damage",
          0,
          "Package damaged"
        )
      end

      trip.activeDeliveryImpactDamage = (trip.activeDeliveryImpactDamage or 0) + damageDelta
      local impactPercent = delivery.calculateImpactDamage(
        trip.activeDeliveryImpactDamage,
        taxiConfig.delivery
      )
      if trip.randomEvent and trip.randomEvent.kind == "fragileCargo" then
        impactPercent = clampValue(
          impactPercent * (trip.randomEvent.damageMultiplier or 1.4),
          0,
          100
        )
      end
      local addedPercent = math.max(0, impactPercent - (trip.activeDeliveryImpactPercent or 0))
      trip.activeDeliveryImpactPercent = impactPercent
      trip.cargoDamagePercent = clampValue(
        (trip.cargoDamagePercent or 0) + addedPercent,
        0,
        100
      )
      trip.collisionDamage = (trip.collisionDamage or 0) + damageDelta
      trip.collisionPenalty = trip.cargoDamagePercent / 100
      if trip.activeCollisionEvent then
        trip.activeCollisionEvent.penalty = impactPercent / 100
        trip.activeCollisionEvent.damage = trip.activeDeliveryImpactDamage
        trip.activeCollisionEvent.cargoDamagePercent = impactPercent
        trip.activeCollisionEvent.detail = string.format("Package damaged by %.1f%%", impactPercent)
      end
      trip.collisionCooldown = balanceConfig.collisionCooldownSeconds
    elseif userSettings.penaltyToggles.collision ~= false and not trip.isDelivery and
      damageDelta >= balanceConfig.collisionDamageThreshold then
      local previousPenalty = trip.collisionPenalty
      local isNewCollision = trip.collisionCooldown <= 0
      trip.collisionDamage = trip.collisionDamage + damageDelta
      if isNewCollision then
        trip.collisionCount = trip.collisionCount + 1
        trip.activeCollisionDisposition = createPassengerPenaltyDisposition()
      end
      local basePenaltyDelta =
        damageDelta / balanceConfig.collisionDamageScale * balanceConfig.collisionDamagePenalty +
        (isNewCollision and balanceConfig.collisionEventPenalty or 0)
      local penaltyDelta = applyPassengerPenalty(basePenaltyDelta, trip.activeCollisionDisposition)
      trip.collisionPenalty = clampValue(
        trip.collisionPenalty + penaltyDelta,
        0,
        balanceConfig.maxCollisionPenalty * 2
      )

      penaltyDelta = math.max(0, trip.collisionPenalty - previousPenalty)
      if isNewCollision then
        if not trip.activeCollisionDisposition.ignored then
          trip.ratingCollisionCount = (trip.ratingCollisionCount or 0) + 1
          trip.activeCollisionEvent = addPenaltyEvent(
            "collision",
            "Столкновение",
            penaltyDelta,
            string.format("Повреждение +%.0f", damageDelta)
          )
          if trip.activeCollisionEvent then trip.activeCollisionEvent.damage = damageDelta end
        else
          trip.activeCollisionEvent = nil
        end
        realisticFuel.adjustPassengerMood(
          -passengerMood.collisionLoss(
            balanceConfig.passengerMoodCollisionBaseLoss,
            damageDelta
          ),
          12
        )
        addPassengerStress(22 + math.min(24, damageDelta / 200))
      elseif trip.activeCollisionEvent then
        trip.activeCollisionEvent.penalty = trip.activeCollisionEvent.penalty + penaltyDelta
        trip.activeCollisionEvent.detail = string.format(
          "Суммарное повреждение +%.0f",
          trip.collisionDamage
        )
        trip.activeCollisionEvent.damage = (trip.activeCollisionEvent.damage or 0) + damageDelta
      end
      if not isNewCollision then addPassengerStress(math.min(8, damageDelta / 500)) end
      trip.collisionCooldown = balanceConfig.collisionCooldownSeconds
    end
  end

  if trip.isDelivery then return end
  if userSettings.penaltyToggles.aggression == false then
    trip.aggressionActive = false
    trip.aggressionCooldown = 0
    return
  end

  local longitudinal = math.abs(telemetry.longitudinalG)
  local lateral = telemetry.lateralG
  local aggressive = longitudinal >= balanceConfig.longitudinalGThreshold or
    lateral >= balanceConfig.lateralGThreshold
  local released = longitudinal <= balanceConfig.longitudinalGRelease and
    lateral <= balanceConfig.lateralGRelease

  if aggressive and not trip.aggressionActive and trip.aggressionCooldown <= 0 then
    local peak = math.max(longitudinal, lateral)
    local thresholdExcess = math.max(
      longitudinal - balanceConfig.longitudinalGThreshold,
      lateral - balanceConfig.lateralGThreshold,
      0
    )
    local previousPenalty = trip.aggressionPenalty
    local disposition = createPassengerPenaltyDisposition()
    local basePenalty = balanceConfig.aggressionEventPenalty +
      clampValue(
        thresholdExcess * balanceConfig.aggressionExtraRate,
        0,
        balanceConfig.aggressionExtraMax
      )
    trip.aggressionEvents = trip.aggressionEvents + 1
    trip.aggressionPenalty = clampValue(
      trip.aggressionPenalty + applyPassengerPenalty(basePenalty, disposition),
      0,
      balanceConfig.maxAggressionPenalty * 2
    )
    if not disposition.ignored then
      local aggressionEvent = addPenaltyEvent(
        "aggression",
        "Резкий манёвр",
        math.max(0, trip.aggressionPenalty - previousPenalty),
        string.format("Пиковая нагрузка %.2f g", peak)
      )
      if aggressionEvent then aggressionEvent.peakG = peak end
    end
    realisticFuel.adjustPassengerMood(
      -passengerMood.aggressionLoss(
        balanceConfig.passengerMoodAggressionBaseLoss,
        thresholdExcess
      ),
      7
    )
    addPassengerStress(6 + math.min(12, thresholdExcess * 18))
    trip.aggressionActive = true
    trip.aggressionCooldown = balanceConfig.aggressionCooldownSeconds
  elseif released then
    trip.aggressionActive = false
  end
end
function M.onUpdate(dtReal, dtSim)
  if vehicleScanGuard.isConfigurationOpen() then return end
  logger.observeRuntime(state, trip, #offers)
  dtReal = math.max(0, dtReal or 0)
  dtSim = math.max(0, dtSim or 0)
  local scannerBecameReady = vehicleScanGuard.update(dtReal)
  local vehicleChanged = false
  if not vehicleScanGuard.isSuspended() then vehicleChanged = vehicleHistory.update(dtReal, dtSim) end
  if shiftHistory.updateValidation(dtReal) then
    if shiftHistory.pruneUnavailable() then notifyHud() end
  end
  if scannerBecameReady then
    realisticFuel.dashboardEnergyTimer = 0
    local stableVehicle = state.active and state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
    setTelemetryEnabled(stableVehicle, state.active == true)
    if stableVehicle and trip and trip.isDelivery then delivery.applyVehicleMass(stableVehicle, trip.cargoWeightKg or 0) end
    autopilot:suspend(stableVehicle, false)
  end
  realisticFuel.updateDashboardEnergy(dtSim)
  shiftHistory.updateRestore(dtReal)
  lanBridge.update(dtReal)
  if lanBridge.consumeStatusChanged() then notifyHud() end
  if vehicleScanGuard.isSuspended() then return end
  local fleetDelta = fleet:update(dtReal, dtSim, state.balance)
  if fleetDelta ~= 0 then state.balance = roundMoney(math.max(0, state.balance + fleetDelta)); realisticFuel.recordBalanceHistory() end
  hudTimer = hudTimer + dtReal
  if not state.active then
    if vehicleChanged or hudTimer >= 0.5 then
      hudTimer = 0
      notifyHudPatch()
    end
    return
  end
  if shiftHistory.update(dtReal, shiftTracking:getHud().current) then
    shiftHistory.captureActive(getObjectByID(state.activeVehicleId),
      vehicleHistory.getCurrentShiftVehicle(), realisticFuel.dashboardEnergy,
      shiftTracking:getHud().current)
  end
  updateActiveMode(dtSim)
  if hudTimer >= hudUpdateInterval then
    hudTimer = 0
    notifyHudPatch()
  end
end
function M.fleetCommand(action, args)
  local ok, reason, delta = fleet:command(tostring(action or ""), args, state.balance)
  if delta ~= 0 then state.balance = roundMoney(math.max(0, state.balance + delta)); realisticFuel.recordBalanceHistory() end
  notifyHud(); return ok, reason
end
function M.onVehicleSwitched(oldId, newId)
  if vehicleScanGuard.isConfigurationOpen() then return end
  if state.active and oldId == state.activeVehicleId and newId ~= oldId then
    stopModeInternal("Режим остановлен после смены автомобиля", true, "notify_vehicleChanged")
  end
  vehicleHistory.selectVehicle(newId)
  notifyHud()
end
local function deferVehicleScan(vehicleId)
  if vehicleScanGuard.isConfigurationOpen() then return end
  local currentVehicle = getPlayerVehicle()
  local currentVehicleId = currentVehicle and currentVehicle:getID() or nil
  if vehicleScanGuard.onVehicleLifecycle(vehicleId, currentVehicleId) then realisticFuel.deferDashboardEnergy() end
end

local function handleVehicleReset(vehicleId)
  if vehicleScanGuard.isConfigurationOpen() then return end
  vehicleId = tonumber(vehicleId)
  if vehicleId then
    deferVehicleScan(vehicleId)
    realisticFuel.initializedVehicles[vehicleId] = nil
    realisticFuel.initializationPending[vehicleId] = nil
    vehicleHistory.onVehicleReset(vehicleId)
  end
  if state.active and vehicleId and vehicleId == tonumber(state.activeVehicleId) then
    if userSettings.godMode == true then
      realisticFuel.dashboardEnergyTimer = 0
      if trip and trip.isDelivery then
        delivery.applyVehicleMass(getObjectByID(vehicleId), trip.cargoWeightKg or 0)
      end
      autopilot:markRouteDirty()
      notifyHud()
      return
    end
    -- Clear the queued order before stopping the session. The explicit clear
    -- also guarantees an immediate HUD reset if the vehicle and GE reset hooks
    -- arrive in different frames.
    clearNextOffer()
    stopModeInternal("Режим остановлен после сброса автомобиля", true, "notify_vehicleReset")
  end
end

function M.onVehicleResetted(vehicleId)
  handleVehicleReset(vehicleId)
end

function M.onTelemetryVehicleReset(vehicleId)
  handleVehicleReset(vehicleId)
end
M.onPreVehicleSpawned = deferVehicleScan
M.onVehicleSpawned = deferVehicleScan

function M.onClientStartMission()
  minimapAppVisible = true
  minimapUiBlocked = false
  vehicleHistory.resetTracking()
  vehicleHistory.refreshCurrentVehicle()
  notifyHud()
end
function M.onUiChangedState(to, from)
  if vehicleScanGuard.onUiChangedState(to, from) then
    local configurationOpen = vehicleScanGuard.isConfigurationOpen()
    guihooks.trigger("TaxiDriverUiSuspended", {suspended = configurationOpen})
    realisticFuel.deferDashboardEnergy()
    local activeVehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
    if configurationOpen and state.active then
      setTelemetryEnabled(activeVehicle, false)
      delivery.applyVehicleMass(activeVehicle, 0)
      autopilot:suspend(activeVehicle, true)
    end
  end
  -- BeamNG uses several intermediate states while the UI App itself remains
  -- visible. Blocking every state except the literal "play" permanently hid
  -- the native map after app editing and vehicle selection. Only states known
  -- to cover the gameplay UI are treated as blockers; CEF visibility remains
  -- the primary source of truth through setMinimapAppVisibility().
  local blockingPrefixes = {
    "menu.mainmenu", "menu.photomode", "menu.options", "menu.vehicles",
    "menu.vehiclesnew", "menu.appedit", "menu.levels", "menu.mods",
    "menu.appselect"
  }
  local function isBlocking(value)
    local name = tostring(value or "")
    for _, prefix in ipairs(blockingPrefixes) do
      if string.sub(name, 1, string.len(prefix)) == prefix then return true end
    end
    return false
  end
  if isBlocking(to) then
    minimapUiBlocked = true
    hideNativeMinimap()
    autopilot:suspend(state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil, true)
  elseif isBlocking(from) then
    minimapUiBlocked = false
    if not vehicleScanGuard.isSuspended() then
      autopilot:suspend(state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil, false)
    end
    if minimapAppVisible then guihooks.trigger("TaxiDriverMinimapInvalidated") end
  end
end

function M.onExtensionLoaded()
  vehicleScanGuard.reset()
  loadUserSettings()
  loadDriverProfile()
  loadUserProgress()
  vehicleHistory.load(modVersion)
  shiftHistory.load(modVersion)
  fleet:load()
  vehicleHistory.refreshCurrentVehicle()
  lanBridge.setCommandHandler(function(action, args)
    args = type(args) == "table" and args or {}
    if action == "start" then
      M.startMode()
      return state.active == true
    elseif action == "resumeShift" then
      return M.resumeShift(args.id)
    elseif action == "stop" then
      if trip and isPassengerOnboardPhase(state.phase) then
        if args.force == true then
          M.confirmDriverAbandonment()
          return true
        end
        return false, "confirmation_required"
      end
      M.stopMode()
      return state.active == false
    elseif action == "openVehicleSelector" then
      M.openVehicleSelector()
      return true
    elseif action == "toggleAutopilot" then
      return M.toggleAutopilot()
    elseif action == "acceptOffer" then
      local id = math.floor(tonumber(args.id) or -1)
      local beforeTripId = trip and trip.id or 0
      M.acceptOrder(id)
      return trip ~= nil and (trip.id or 0) ~= beforeTripId
    elseif action == "acceptNextOffer" then
      M.acceptNextOffer(args.id)
      return nextOfferAccepted == true
    elseif action == "requestFuelStop" then
      if not state.realisticMode then return false, "realistic_mode_required" end
      M.requestFuelStop()
      return true
    elseif action == "cancelFuelStop" then
      M.cancelFuelStop()
      return true
    elseif action == "completeFuelStop" then
      M.completeFuelStop()
      return true
    elseif action == "purchaseFuel" then
      M.purchaseRealisticFuel(tostring(args.energyType or ""), tonumber(args.quantity) or 0)
      return true
    elseif action == "fleetCommand" then
      return M.fleetCommand(args.action, args.args)
    end
    return false, "unsupported_command"
  end)
  lanBridge.setEnabled(userSettings.lanEnabled)
  delivery.applyVehicleMass(getPlayerVehicle(), 0)
  notifyHud()
end

function M.onClientEndMission()
  shiftHistory.setRestoring(nil)
  fleet:endSession()
  autopilot:disable(state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil, "missionEnded")
  aiLogger:close("missionEnded")
  hideNativeMinimap()
  realisticFuel.restoreEconomy()
  realisticFuel.initializedVehicles = {}
  realisticFuel.initializationPending = {}
  routePlanning.reset()
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  phoneNotification = nil
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
  vehicleHistory.write()
  shiftHistory.write()
  vehicleHistory.resetTracking()
  restoreNavigationVisualSettings()
end function M.onPreRender() if minimapAppVisible and not minimapUiBlocked then fleet:drawWorldLabels() end end

function M.onExtensionUnloaded()
  shiftHistory.setRestoring(nil)
  fleet:shutdown()
  autopilot:disable(state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil, "extensionUnloaded")
  aiLogger:close("extensionUnloaded")
  vehicleScanGuard.reset()
  lanBridge.stop()
  hideNativeMinimap()
  delivery.applyVehicleMass(getPlayerVehicle(), 0)
  realisticFuel.restoreEconomy()
  routePlanning.clearRecent()
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
  vehicleHistory.write()
  shiftHistory.write()
  vehicleHistory.resetTracking()
  restoreNavigationVisualSettings()
end

function M.onSerialize()
  return {
    balance = state.balance,
    rating = state.rating,
    ratingTotal = state.ratingTotal,
    ratingCount = state.ratingCount,
    completedRides = state.completedRides,
    difficulty = state.difficulty
  }
end

function M.onDeserialized(data)
  data = data or {}
  if shiftTracking:getHud().active then
    local completedShift = shiftTracking:finish()
    shiftHistory.finishActive(getPlayerVehicle(), vehicleHistory.getCurrentShiftVehicle(),
      realisticFuel.dashboardEnergy, completedShift)
  end
  realisticFuel.restoreEconomy()
  delivery.applyVehicleMass(getPlayerVehicle(), 0)
  if progressNeedsLegacyImport then
    state.balance = math.max(0, tonumber(data.balance) or 0)
    state.ratingTotal = math.max(0, tonumber(data.ratingTotal) or 0)
    state.ratingCount = math.max(0, math.floor(tonumber(data.ratingCount) or 0))
    state.completedRides = math.max(0, math.floor(tonumber(data.completedRides) or state.ratingCount))
    state.rating = state.ratingCount > 0 and
      clampValue(state.ratingTotal / state.ratingCount, 0, 5) or
      clampValue(tonumber(data.rating) or 5, 0, 5)
    progressNeedsLegacyImport = false
    writeUserProgress()
  else
    applyUserProgressToState()
  end
  applyDifficulty(userSettings.difficulty or "standard")
  state.active = false
  state.phase = phases.inactive
  state.activeVehicleId = nil
  state.realisticMode = false
  autopilot:disable(nil, "deserialized")
  shiftHistory.setRestoring(nil)
  trip = nil
  offers = {}
  clearNextOffer()
  offerTimer = 0
  phoneNotification = nil
  routePlanning.reset()
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  vehicleHistory.resetTracking()
  vehicleHistory.refreshCurrentVehicle()
  notifyHud()
end
logger.attachOperations(M)
return M
