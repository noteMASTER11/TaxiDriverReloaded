local M = {}

M.dependencies = {
  "core_groundMarkers",
  "core_vehicleTriggers",
  "core_vehicle_manager",
  "freeroam_gasStations",
  "gameplay_sites_sitesManager"
}

local Route = require("gameplay/route/route")
local trafficUtils = require("gameplay/traffic/trafficUtils")
local offerGenerator = require("taxiDriver/offerGenerator")
local taxiConfig = require("taxiDriver/config")
local identity = require("taxiDriver/identity")
local passengerMood = require("taxiDriver/passengerMood")
local routeDiversity = require("taxiDriver/routeDiversity")
local delivery = require("taxiDriver/delivery")
local lanBridge = require("taxiDriver/lanBridge")

local logTag = "taxiDriver"
local modVersion = "2.24.0"
local settingsSchemaVersion = 1
local profileSchemaVersion = 1
local progressSchemaVersion = 1
local settingsDirectoryPath = "/settings/TaxiDriver"
local settingsFilePath = settingsDirectoryPath .. "/settings.json"
local profileFilePath = settingsDirectoryPath .. "/profile.json"
local progressFilePath = settingsDirectoryPath .. "/progress.json"

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

-- These factors mirror BeamNG's career refueling conversion from joules to
-- litres, kilograms, or kilowatt-hours.
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
  dashboardEnergyPending = false,
  dashboardEnergyTimer = 0,
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
  return {
    schemaVersion = settingsSchemaVersion,
    modVersion = modVersion,
    language = "en",
    rememberLanguage = false,
    difficulty = "standard",
    customDifficulty = taxiConfig.sanitizeCustomDifficulty(nil),
    uiScalePercent = 100,
    appVolume = 0.65,
    unitSystem = "metric",
    timeFormat = "12h",
    penaltyToggles = {
      speeding = true,
      collision = true,
      aggression = true,
      pickupDelay = true,
      fuelStop = true,
      rushBonus = true,
      cargoDamage = true
    },
    soundToggles = {
      click = true,
      newRide = true,
      offline = true,
      online = true,
      violation = true,
      message = true,
      overspeed = true
    },
    dynamicZoomIntensity = 100,
    overspeedWarningKmh = 10,
    economyMultiplier = 1,
    deliveryOrderSharePercent = 50,
    lanEnabled = false,
    silentMode = false,
    showRouteGuidance = true,
    realisticMode = false
  }
end

local userSettings = createDefaultUserSettings()
local settingsNeedsLegacyImport = false
local driverProfile = nil
local userProgress = nil
local progressNeedsLegacyImport = false

local trip = nil
local offers = {}
local nextOffer = nil
local nextOfferTimer = 0
local nextOfferAccepted = false
local phoneNotification = nil
local nextPhoneNotificationId = 0
local telemetry = {
  damage = 0,
  longitudinalG = 0,
  lateralG = 0
}

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
local minimapOriginalDrawPlayer = nil
local minimapWrappedDrawPlayer = nil
local minimapZoomMultiplier = nil
local stopCandidateCache = nil
local stopCandidateLevel = nil
local recentTaxiStopPositions = {}
local recentTaxiStopLimit = offerConfig.recentStopLimit
local recentTaxiStopSeparation = offerConfig.recentStopSeparation
local navigationVisualOverrideActive = false
local originalNavigationGroundmarkers = nil
local originalNavigationArrows = nil
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

local function sanitizeUserSettings(source, requireSchema)
  local result = createDefaultUserSettings()
  if type(source) ~= "table" then return result, false end
  if requireSchema and tonumber(source.schemaVersion) ~= settingsSchemaVersion then
    return result, false
  end

  if supportedLanguages[tostring(source.language or "")] then
    result.language = tostring(source.language)
  end
  result.rememberLanguage = source.rememberLanguage == true
  if difficultyPresets[tostring(source.difficulty or "")] or
    tostring(source.difficulty or "") == "custom" then
    result.difficulty = tostring(source.difficulty)
  end
  result.customDifficulty = taxiConfig.sanitizeCustomDifficulty(source.customDifficulty)

  local uiScalePercent = tonumber(source.uiScalePercent)
  if not uiScalePercent then
    local legacyFontBoost = tonumber(source.fontBoost)
    if legacyFontBoost then
      uiScalePercent = 100 + (clampValue(legacyFontBoost, 0, 5) - 2) * 10
    end
  end
  if uiScalePercent then
    result.uiScalePercent = math.floor(
      clampValue(uiScalePercent, 80, 180) / 10 + 0.5
    ) * 10
  end
  local appVolume = tonumber(source.appVolume)
  if appVolume then result.appVolume = clampValue(appVolume, 0, 1) end
  if source.unitSystem == "imperial" then result.unitSystem = "imperial" end
  if source.timeFormat == "24h" then result.timeFormat = "24h" end
  local penaltySource = type(source.penaltyToggles) == "table" and
    source.penaltyToggles or {}
  result.penaltyToggles.speeding = penaltySource.speeding ~= false
  result.penaltyToggles.collision = penaltySource.collision ~= false
  result.penaltyToggles.aggression = penaltySource.aggression ~= false
  result.penaltyToggles.pickupDelay = penaltySource.pickupDelay ~= false
  result.penaltyToggles.fuelStop = penaltySource.fuelStop ~= false
  result.penaltyToggles.rushBonus = penaltySource.rushBonus ~= false
  result.penaltyToggles.cargoDamage = penaltySource.cargoDamage ~= false
  local soundSource = type(source.soundToggles) == "table" and
    source.soundToggles or {}
  result.soundToggles.click = soundSource.click ~= false
  result.soundToggles.newRide = soundSource.newRide ~= false
  result.soundToggles.offline = soundSource.offline ~= false
  result.soundToggles.online = soundSource.online ~= false
  result.soundToggles.violation = soundSource.violation ~= false
  result.soundToggles.message = soundSource.message ~= false
  result.soundToggles.overspeed = soundSource.overspeed ~= false
  result.dynamicZoomIntensity = clampValue(
    tonumber(source.dynamicZoomIntensity) or result.dynamicZoomIntensity,
    0,
    200
  )
  result.overspeedWarningKmh = clampValue(
    tonumber(source.overspeedWarningKmh) or result.overspeedWarningKmh,
    0,
    30
  )
  result.economyMultiplier = clampValue(
    tonumber(source.economyMultiplier) or result.economyMultiplier,
    0.25,
    5
  )
  result.deliveryOrderSharePercent = clampValue(
    tonumber(source.deliveryOrderSharePercent) or result.deliveryOrderSharePercent,
    0,
    100
  )
  -- External phone sharing is deliberately session-only. Never restore it
  -- from settings.json when the mod or UI App starts.
  result.lanEnabled = false
  result.silentMode = source.silentMode == true
  result.showRouteGuidance = source.showRouteGuidance ~= false
  result.realisticMode = source.realisticMode == true
  return result, true
end

function M.writeDifficultySettings()
  local ok, errorMessage = pcall(function()
    if not FS:directoryExists(settingsDirectoryPath) then
      FS:directoryCreate(settingsDirectoryPath)
    end
    jsonWriteFile(settingsDirectoryPath .. "/difficulty.json", {
      schemaVersion = 1,
      modVersion = modVersion,
      customDifficulty = taxiConfig.sanitizeCustomDifficulty(userSettings.customDifficulty),
      penaltyToggles = {
        speeding = userSettings.penaltyToggles.speeding ~= false,
        collision = userSettings.penaltyToggles.collision ~= false,
        aggression = userSettings.penaltyToggles.aggression ~= false,
        pickupDelay = userSettings.penaltyToggles.pickupDelay ~= false,
        fuelStop = userSettings.penaltyToggles.fuelStop ~= false,
        rushBonus = userSettings.penaltyToggles.rushBonus ~= false,
        cargoDamage = userSettings.penaltyToggles.cargoDamage ~= false
      }
    }, true)
  end)
  if not ok then
    log("E", logTag, "Unable to write difficulty settings: " .. tostring(errorMessage))
  end
  return ok
end

local function writeUserSettings()
  local ok, errorMessage = pcall(function()
    if not FS:directoryExists(settingsDirectoryPath) then
      FS:directoryCreate(settingsDirectoryPath)
    end
    local settingsData = {}
    for key, value in pairs(userSettings) do
      if key ~= "customDifficulty" and key ~= "penaltyToggles" and
        key ~= "lanEnabled" then
        settingsData[key] = value
      end
    end
    jsonWriteFile(settingsFilePath, settingsData, true)
  end)
  if not ok then
    log("E", logTag, "Unable to write settings: " .. tostring(errorMessage))
  end
  return M.writeDifficultySettings() and ok
end

local function loadUserSettings()
  local fileExists = FS:fileExists(settingsFilePath)
  local source = nil
  if fileExists then
    local ok, loaded = pcall(jsonReadFile, settingsFilePath)
    if ok then source = loaded end
  end

  userSettings = sanitizeUserSettings(source, true)
  local difficultyPath = settingsDirectoryPath .. "/difficulty.json"
  local difficultyExists = FS:fileExists(difficultyPath)
  if difficultyExists then
    local difficultyOk, difficultySource = pcall(jsonReadFile, difficultyPath)
    if difficultyOk and type(difficultySource) == "table" and
      tonumber(difficultySource.schemaVersion) == 1 then
      userSettings.customDifficulty = taxiConfig.sanitizeCustomDifficulty(
        difficultySource.customDifficulty
      )
      local penaltySource = type(difficultySource.penaltyToggles) == "table" and
        difficultySource.penaltyToggles or {}
      userSettings.penaltyToggles.speeding = penaltySource.speeding ~= false
      userSettings.penaltyToggles.collision = penaltySource.collision ~= false
      userSettings.penaltyToggles.aggression = penaltySource.aggression ~= false
      userSettings.penaltyToggles.pickupDelay = penaltySource.pickupDelay ~= false
      userSettings.penaltyToggles.fuelStop = penaltySource.fuelStop ~= false
      userSettings.penaltyToggles.rushBonus = penaltySource.rushBonus ~= false
      userSettings.penaltyToggles.cargoDamage = penaltySource.cargoDamage ~= false
    else
      local defaults = createDefaultUserSettings()
      userSettings.customDifficulty = defaults.customDifficulty
      userSettings.penaltyToggles = defaults.penaltyToggles
    end
  end
  settingsNeedsLegacyImport = not fileExists
  applyDifficulty(userSettings.difficulty)

  -- Always rewrite a canonical file. This repairs invalid fields and replaces
  -- unsupported schemas with the defaults understood by this mod version.
  writeUserSettings()
end

local function roundMoney(value)
  return math.floor(value * 100 + 0.5) / 100
end

local function ensureSettingsDirectory()
  if not FS:directoryExists(settingsDirectoryPath) then
    FS:directoryCreate(settingsDirectoryPath)
  end
end

local function trimText(value)
  local text = tostring(value or "")
  text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
  return text
end

local function sanitizeBirthDate(value)
  local text = trimText(value)
  if text == "" then return "" end
  local year, month, day = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  local currentYear = tonumber(os.date("%Y")) or 2026
  if not year or year < 1900 or year > currentYear or
    not month or month < 1 or month > 12 or not day or day < 1 or day > 31 then
    return ""
  end
  local timestamp = os.time({year = year, month = month, day = day, hour = 12})
  local verified = timestamp and os.date("*t", timestamp) or nil
  if not verified or verified.year ~= year or verified.month ~= month or verified.day ~= day then
    return ""
  end
  return string.format("%04d-%02d-%02d", year, month, day)
end

local function createDefaultDriverProfile()
  return {
    schemaVersion = profileSchemaVersion,
    modVersion = modVersion,
    fullName = "John Doe",
    birthDate = "",
    avatar = "🙂"
  }
end

local function sanitizeDriverProfile(source, requireSchema)
  local result = createDefaultDriverProfile()
  if type(source) ~= "table" then return result, false end
  if requireSchema and tonumber(source.schemaVersion) ~= profileSchemaVersion then
    return result, false
  end

  local fullName = trimText(source.fullName)
  if fullName ~= "" and #fullName <= 160 then result.fullName = fullName end
  result.birthDate = sanitizeBirthDate(source.birthDate)
  local avatar = tostring(source.avatar or "")
  if driverAvatarSet[avatar] then result.avatar = avatar end
  return result, true
end

local function createDefaultUserProgress()
  local now = os.time()
  return {
    schemaVersion = progressSchemaVersion,
    modVersion = modVersion,
    balance = 0,
    rating = 5,
    ratingTotal = 0,
    ratingCount = 0,
    completedRides = 0,
    sequence = 0,
    reviews = {},
    ratingHistory = {{index = 0, value = 5, timestamp = now}},
    balanceHistory = {{index = 0, value = 0, timestamp = now}}
  }
end

local reviewEmojiSet = {
  ["🤩"] = true, ["😍"] = true, ["😄"] = true, ["😊"] = true,
  ["🙂"] = true, ["😐"] = true, ["😕"] = true, ["😠"] = true,
  ["😡"] = true, ["🤬"] = true
}

local function sanitizeProgressHistory(source, minimum, maximum)
  local result = {}
  if type(source) ~= "table" then return result end
  for _, item in ipairs(source) do
    if type(item) == "table" then
      local index = math.max(0, math.floor(tonumber(item.index) or 0))
      local value = tonumber(item.value)
      if value then
        table.insert(result, {
          index = index,
          value = roundMoney(clampValue(value, minimum, maximum)),
          timestamp = math.max(0, math.floor(tonumber(item.timestamp) or 0))
        })
      end
    end
  end
  return result
end

local function sanitizeUserProgress(source, requireSchema)
  local result = createDefaultUserProgress()
  if type(source) ~= "table" then return result, false end
  if requireSchema and tonumber(source.schemaVersion) ~= progressSchemaVersion then
    return result, false
  end

  result.balance = roundMoney(math.max(0, tonumber(source.balance) or 0))
  result.ratingCount = math.max(0, math.floor(tonumber(source.ratingCount) or 0))
  result.completedRides = math.max(0, math.floor(tonumber(source.completedRides) or result.ratingCount))
  result.rating = clampValue(tonumber(source.rating) or 5, 0, 5)
  result.ratingTotal = math.max(0, tonumber(source.ratingTotal) or 0)
  if result.ratingCount > 0 then
    if result.ratingTotal <= 0 then result.ratingTotal = result.rating * result.ratingCount end
    result.rating = clampValue(result.ratingTotal / result.ratingCount, 0, 5)
  end

  result.sequence = math.max(0, math.floor(tonumber(source.sequence) or result.completedRides))
  result.reviews = {}
  if type(source.reviews) == "table" then
    for _, review in ipairs(source.reviews) do
      if type(review) == "table" then
        local id = math.max(1, math.floor(tonumber(review.id) or (#result.reviews + 1)))
        local passengerName = trimText(review.passengerName)
        if passengerName == "" or #passengerName > 160 then passengerName = "Passenger" end
        local emoji = tostring(review.emoji or "😐")
        if not reviewEmojiSet[emoji] then emoji = "😐" end
        table.insert(result.reviews, {
          id = id,
          passengerName = passengerName,
          emoji = emoji,
          quality = clampValue(tonumber(review.quality) or 0, 0, 100),
          fare = roundMoney(math.max(0, tonumber(review.fare) or 0)),
          rating = clampValue(tonumber(review.rating) or result.rating, 0, 5),
          timestamp = math.max(0, math.floor(tonumber(review.timestamp) or 0)),
          outcome = tostring(review.outcome or "completed")
        })
        result.sequence = math.max(result.sequence, id)
      end
    end
  end

  result.ratingHistory = sanitizeProgressHistory(source.ratingHistory, 0, 5)
  result.balanceHistory = sanitizeProgressHistory(source.balanceHistory, 0, 1000000000)
  if #result.ratingHistory == 0 then
    result.ratingHistory = {{index = result.sequence, value = roundMoney(result.rating), timestamp = os.time()}}
  end
  if #result.balanceHistory == 0 then
    result.balanceHistory = {{index = result.sequence, value = result.balance, timestamp = os.time()}}
  end
  return result, true
end

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
  userProgress.schemaVersion = progressSchemaVersion
  userProgress.modVersion = modVersion
  userProgress.balance = roundMoney(math.max(0, tonumber(state.balance) or 0))
  userProgress.rating = clampValue(tonumber(state.rating) or 5, 0, 5)
  userProgress.ratingTotal = math.max(0, tonumber(state.ratingTotal) or 0)
  userProgress.ratingCount = math.max(0, math.floor(tonumber(state.ratingCount) or 0))
  userProgress.completedRides = math.max(0, math.floor(tonumber(state.completedRides) or 0))
end

local function writeDriverProfile()
  local ok, errorMessage = pcall(function()
    ensureSettingsDirectory()
    jsonWriteFile(profileFilePath, driverProfile, true)
  end)
  if not ok then log("E", logTag, "Unable to write driver profile: " .. tostring(errorMessage)) end
  return ok
end

local function writeUserProgress()
  syncUserProgressFromState()
  local ok, errorMessage = pcall(function()
    ensureSettingsDirectory()
    jsonWriteFile(progressFilePath, userProgress, true)
  end)
  if not ok then log("E", logTag, "Unable to write driver progress: " .. tostring(errorMessage)) end
  return ok
end

local function loadDriverProfile()
  local source = nil
  if FS:fileExists(profileFilePath) then
    local ok, loaded = pcall(jsonReadFile, profileFilePath)
    if ok then source = loaded end
  end
  driverProfile = sanitizeDriverProfile(source, true)
  writeDriverProfile()
end

local function loadUserProgress()
  local fileExists = FS:fileExists(progressFilePath)
  local source = nil
  if fileExists then
    local ok, loaded = pcall(jsonReadFile, progressFilePath)
    if ok then source = loaded end
  end
  userProgress = sanitizeUserProgress(source, true)
  progressNeedsLegacyImport = not fileExists
  applyUserProgressToState()
  writeUserProgress()
end

local function randomRange(minimum, maximum)
  return minimum + (maximum - minimum) * math.random()
end

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

local function getVehicleSpeedKmh(vehicle)
  return vehicle and vehicle:getVelocity():length() * 3.6 or 0
end

function delivery.applyVehicleMass(vehicle, massKg)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format(
    "if extensions.taxiDriverCargo then extensions.taxiDriverCargo.setCargoMass(%.3f) end",
    math.max(0, tonumber(massKg) or 0)
  ))
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
  local available = state.active and state.realisticMode and realisticFuel.station ~= nil and
    vehicle ~= nil and (getVehicleSpeedKmh(vehicle) <= 2 or refueling.active)
  if available and realisticFuel.station.center then
    available = vehicle:getPosition():distance(realisticFuel.station.center) <=
      realisticFuel.station.radius
  end
  return {
    available = available == true,
    id = realisticFuel.station and realisticFuel.station.id or "",
    name = realisticFuel.station and realisticFuel.station.name or "",
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
    settings = userSettings,
    settingsNeedsLegacyImport = settingsNeedsLegacyImport,
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
  guihooks.trigger("TaxiDriverHUDState", hudState)
end

local function notifyProfile()
  syncUserProgressFromState()
  guihooks.trigger("TaxiDriverProfileData", {
    profile = driverProfile or createDefaultDriverProfile(),
    progress = userProgress or createDefaultUserProgress(),
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

local function recordProgressEvent(passengerName, emoji, quality, fare, outcome, reviewRating)
  if not userProgress then userProgress = createDefaultUserProgress() end
  userProgress.sequence = math.max(0, math.floor(tonumber(userProgress.sequence) or 0)) + 1
  local timestamp = os.time()
  table.insert(userProgress.reviews, {
    id = userProgress.sequence,
    passengerName = trimText(passengerName) ~= "" and trimText(passengerName) or "Passenger",
    emoji = reviewEmojiSet[emoji] and emoji or "😐",
    quality = clampValue(tonumber(quality) or 0, 0, 100),
    fare = roundMoney(math.max(0, tonumber(fare) or 0)),
    rating = clampValue(tonumber(reviewRating) or tonumber(state.rating) or 5, 0, 5),
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

function realisticFuel.refreshDashboardEnergy()
  if realisticFuel.dashboardEnergyPending or not state.active then return end
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  if not vehicle then
    realisticFuel.resetDashboardEnergy()
    return
  end

  realisticFuel.dashboardEnergyPending = true
  local vehicleId = vehicle:getID()
  core_vehicleBridge.requestValue(vehicle, function(data)
    realisticFuel.dashboardEnergyPending = false
    if not state.active or tonumber(state.activeVehicleId) ~= tonumber(vehicleId) then return end

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
    notifyHud()
  end, "energyStorage")
end

function realisticFuel.updateDashboardEnergy(dtSim)
  if not state.active then return end
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
    radius = math.max(15, radius + 12)
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
    session.hudTimer = 0.1
    notifyHud()
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

function realisticFuel.initializeVehicle(vehicle)
  if not vehicle then return end
  local vehicleId = vehicle:getID()
  if realisticFuel.initializedVehicles[vehicleId] or
    realisticFuel.initializationPending[vehicleId] then return end
  realisticFuel.initializationPending[vehicleId] = true

  core_vehicleBridge.requestValue(vehicle, function(data)
    realisticFuel.initializationPending[vehicleId] = nil
    local tanks = type(data) == "table" and data[1] or nil
    if type(tanks) ~= "table" then
      if state.active and state.realisticMode then
        showPhoneNotification("notify_realisticFuelUnsupported", {}, "warning")
      end
      return
    end

    local initialized = false
    for _, tank in ipairs(tanks) do
      local energyType = tostring(tank.energyType or "")
      if energyType == "gasoline" or energyType == "diesel" or
        energyType == "kerosine" or energyType == "electricEnergy" then
        local maxEnergy = math.max(0, tonumber(tank.maxEnergy) or 0)
        if maxEnergy > 0 then
          core_vehicleBridge.executeAction(
            vehicle,
            "setEnergyStorageEnergy",
            tank.name,
            maxEnergy * (energyType == "electricEnergy" and
              realisticFuel.config.electricInitialLevel or
              realisticFuel.config.fuelInitialLevel)
          )
          initialized = true
        end
      end
    end

    if initialized then
      realisticFuel.initializedVehicles[vehicleId] = true
      if state.active and state.realisticMode and
        tonumber(state.activeVehicleId) == tonumber(vehicleId) then
        showPhoneNotification("notify_realisticFuelSet", {}, "success")
      end
    elseif state.active and state.realisticMode then
      showPhoneNotification("notify_realisticFuelUnsupported", {}, "warning")
    end
  end, "energyStorage")
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

local function setTelemetryEnabled(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format(
    "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry.setEnabled(%s) end",
    enabled and "true" or "false"
  ))
end

local function setVehicleForcedStop(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format(
    "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry.setForcedStop(%s) end",
    enabled and "true" or "false"
  ))
end

local function setVehicleFrozen(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format("controller.setFreeze(%d)", enabled and 1 or 0))
end

local function releaseForcedPassengerStop(vehicle)
  setVehicleFrozen(vehicle, false)
  setVehicleForcedStop(vehicle, false)
end

local function toggleVehicleAccess(vehicle, preferredTriggerId, accessType)
  if not vehicle or not extensions.core_vehicle_manager or not core_vehicleTriggers then return nil end

  local vehicleId = vehicle:getID()
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehicleId)
  local vdata = vehicleData and vehicleData.vdata or nil
  if not vdata or type(vdata.triggers) ~= "table" or
    type(vdata.triggerEventLinksDict) ~= "table" then return nil end

  local selectedId = nil
  local selectedScore = -1
  for _, trigger in pairs(vdata.triggers) do
    local triggerId = trigger.abid
    local links = triggerId and vdata.triggerEventLinksDict[triggerId] or nil
    local name = string.lower(tostring(trigger.name or trigger.id or ""))

    if preferredTriggerId and triggerId == preferredTriggerId and links and links.action0 then
      selectedId = triggerId
      break
    end

    local score = -1
    if links and links.action0 and accessType == "cargo" then
      if string.find(name, "trunk", 1, true) then score = 130
      elseif string.find(name, "tailgate", 1, true) then score = 125
      elseif string.find(name, "liftgate", 1, true) then score = 120
      elseif string.find(name, "hatch", 1, true) then score = 115
      elseif string.find(name, "boot", 1, true) then score = 110
      elseif string.find(name, "frunk", 1, true) then score = 105
      elseif string.find(name, "cargo door", 1, true) then score = 100
      elseif string.find(name, "rear gate", 1, true) then score = 95
      elseif string.find(name, "rear door", 1, true) then score = 70
      end
    elseif links and links.action0 and string.find(name, "door", 1, true) and
      not string.find(name, "int", 1, true) and
      not string.find(name, "interior", 1, true) and
      not string.find(name, "cargo", 1, true) then
      score = 10
      if string.find(name, "rr", 1, true) or string.find(name, "rear right", 1, true) then
        score = 100
      elseif string.find(name, "rl", 1, true) or string.find(name, "rear left", 1, true) then
        score = 90
      elseif string.find(name, "fr", 1, true) or string.find(name, "front right", 1, true) then
        score = 70
      elseif string.find(name, "passenger", 1, true) then
        score = 60
      end
    end
    if score >= 0 then
      if score > selectedScore then
        selectedScore = score
        selectedId = triggerId
      end
    end
  end

  if not selectedId then return nil end
  local success = pcall(function()
    core_vehicleTriggers.triggerEvent("action0", 1, selectedId, vehicleId, vdata)
    core_vehicleTriggers.triggerEvent("action0", 0, selectedId, vehicleId, vdata)
  end)
  return success and selectedId or nil
end

local function togglePassengerDoor(vehicle, preferredTriggerId)
  return toggleVehicleAccess(vehicle, preferredTriggerId, "passenger")
end

local function toggleCargoAccess(vehicle, preferredTriggerId)
  return toggleVehicleAccess(vehicle, preferredTriggerId, "cargo")
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
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverRouteInfo")
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverSpeedLimit")
    ui_apps_minimap_minimap.resetOcclusionTransform("taxiDriverNotification")
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
end

local function getRoadLink(nodes, nodeA, nodeB)
  if not (nodes[nodeA] and nodes[nodeB]) then return nil end
  return nodes[nodeA].links[nodeB] or nodes[nodeB].links[nodeA]
end

local function isUsableRoad(nodes, nodeA, nodeB, allowPrivate)
  local link = getRoadLink(nodes, nodeA, nodeB)
  if not link or (link.type == "private" and not allowPrivate) then return false end
  if (link.drivability or 0) < minimumDrivability then return false end
  local minimumRadius = allowPrivate and 1.8 or 2.4
  if math.min(nodes[nodeA].radius or 0, nodes[nodeB].radius or 0) < minimumRadius then return false end
  return true
end

local function calculateRouteDistance(fromPos, toPos)
  local planner = Route()
  planner:setRouteParams(minimumDrivability)
  planner:setupPath(fromPos, toPos)

  if not (planner.path and planner.path[1] and planner.path[2]) then return nil end

  local hasRoadNode = false
  for _, pathPoint in ipairs(planner.path) do
    if pathPoint.wp then
      hasRoadNode = true
      break
    end
  end

  if not hasRoadNode then return nil end
  return planner.path[1].distToTarget
end

local function isRecentlyUsedTaxiStop(pos)
  if not pos then return false end
  for _, recentPos in ipairs(recentTaxiStopPositions) do
    if pos:distance(recentPos) < recentTaxiStopSeparation then return true end
  end
  return false
end

local function rememberTaxiStop(pos)
  if not pos then return end
  table.insert(recentTaxiStopPositions, vec3(pos))
  while #recentTaxiStopPositions > recentTaxiStopLimit do
    table.remove(recentTaxiStopPositions, 1)
  end
end

local function rememberOfferStops(offer)
  if not offer then return end
  if offer.pickup then rememberTaxiStop(offer.pickup.pos) end
  for _, stop in ipairs(offer.stops or {}) do rememberTaxiStop(stop.pos) end
  if offer.destination then rememberTaxiStop(offer.destination.pos) end
end

local function projectAnchorToRoadEdge(anchorPos, preferredNodeA, preferredNodeB, allowPrivate)
  local mapData = map.getMap()
  if not mapData or not tableHasValues(mapData.nodes) then return nil end

  local nodes = mapData.nodes
  local nodeA, nodeB = preferredNodeA, preferredNodeB
  if not (nodeA and nodeB and nodes[nodeA] and nodes[nodeB]) then
    nodeA, nodeB = map.findClosestRoad(anchorPos)
  end
  if not (nodeA and nodeB and isUsableRoad(nodes, nodeA, nodeB, allowPrivate)) then return nil end

  local startPos = nodes[nodeA].pos
  local endPos = nodes[nodeB].pos
  local segment = endPos - startPos
  local segmentLengthSquared = segment:squaredLength()
  if segmentLengthSquared < 1 then return nil end

  local segmentLength = math.sqrt(segmentLengthSquared)
  local baseInterpolation = clampValue((anchorPos - startPos):dot(segment) / segmentLengthSquared, 0, 1)
  local interpolation = baseInterpolation
  local roadCenter = startPos + segment * interpolation
  if anchorPos:distance(roadCenter) > 120 then return nil end

  -- Keep the stop at the road edge, but vary its longitudinal position so a
  -- single building, parking area, or bus stop does not always yield the exact
  -- same pickup coordinate.
  local endpointMargin = math.min(0.25, 4 / segmentLength)
  local longitudinalJitter = math.min(
    offerConfig.semanticLongitudinalJitterMax,
    segmentLength * 0.38
  )
  interpolation = clampValue(
    baseInterpolation + randomRange(-longitudinalJitter, longitudinalJitter) / segmentLength,
    endpointMargin,
    1 - endpointMargin
  )
  roadCenter = startPos + segment * interpolation

  local roadDirection = vec3(segment.x, segment.y, 0)
  if roadDirection:length() < 0.1 then return nil end
  roadDirection:normalize()
  local roadSide = vec3(-roadDirection.y, roadDirection.x, 0)
  local sideDot = (anchorPos - roadCenter):dot(roadSide)
  local sideSign = sideDot < 0 and -1 or 1
  if math.abs(sideDot) < 0.5 and math.random() < 0.5 then sideSign = -sideSign end

  local radiusA = nodes[nodeA].radius or 2.4
  local radiusB = nodes[nodeB].radius or radiusA
  local roadRadius = radiusA + (radiusB - radiusA) * interpolation
  local edgeOffset = clampValue(roadRadius - 0.75 + randomRange(-0.25, 0.55), 1.5, 14)
  local edgePos = roadCenter + roadSide * (edgeOffset * sideSign)

  local _, legalDirection = trafficUtils.finalizeSpawnPoint(
    edgePos,
    roadDirection,
    nodeA,
    nodeB,
    {legalDirection = true}
  )

  return {
    pos = vec3(edgePos),
    dir = legalDirection and vec3(legalDirection) or roadDirection,
    nodeA = nodeA,
    nodeB = nodeB
  }
end

local function getStopCandidates()
  local level = getCurrentLevelIdentifier() or ""
  if stopCandidateCache and stopCandidateLevel == level then return stopCandidateCache end
  if stopCandidateLevel ~= level then
    recentTaxiStopPositions = {}
    offerGeneration.recentRoutes = {}
  end

  local candidates = {}
  local occupiedCells = {}
  local scanWork = 0
  local function addCandidate(pos, kind, name)
    if not pos then return end
    local anchor = vec3(pos)
    local cellKey = string.format("%d:%d", math.floor(anchor.x / 8), math.floor(anchor.y / 8))
    if occupiedCells[cellKey] then return end
    occupiedCells[cellKey] = true
    table.insert(candidates, {anchor = anchor, kind = kind, name = name or kind})
  end

  for _, objectId in ipairs(scenetree.findClassObjects("BeamNGTrigger") or {}) do
    scanWork = scanWork + 1
    if scanWork % offerConfig.semanticScanBatchSize == 0 then offerGenerator.yield() end
    local object = scenetree.findObject(objectId)
    if object and object.type == "busstop" then
      addCandidate(object:getPosition(), "busStop", object.stopName or objectId)
    end
  end

  local sitesManager = gameplay_sites_sitesManager
  if sitesManager then
    for _, sitesFile in ipairs(sitesManager.getCurrentLevelSitesFiles() or {}) do
      local lowerPath = string.lower(sitesFile)
      if not lowerPath:find("/missions/", 1, true) and
        not lowerPath:find("/quickrace/", 1, true) and
        not lowerPath:find("/scenarios/", 1, true) then
        local loaded, sites = pcall(sitesManager.loadSites, sitesFile)
        if not loaded then
          log("W", logTag, string.format("Unable to read taxi stop anchors from '%s'", sitesFile))
          sites = nil
        end
        if sites and sites.parkingSpots and sites.parkingSpots.sorted then
          for _, spot in ipairs(sites.parkingSpots.sorted) do
            scanWork = scanWork + 1
            if scanWork % offerConfig.semanticScanBatchSize == 0 then offerGenerator.yield() end
            local tags = spot.customFields and spot.customFields.tags or {}
            if not tags.banned then
              addCandidate(spot.pos, tags.street and "streetParking" or "parking", spot.name)
            end
          end
        end
      end
    end
  end

  for _, objectId in ipairs(scenetree.findClassObjects("BeamNGPointOfInterest") or {}) do
    scanWork = scanWork + 1
    if scanWork % offerConfig.semanticScanBatchSize == 0 then offerGenerator.yield() end
    local object = scenetree.findObject(objectId)
    if object then addCandidate(object:getPosition(), "pointOfInterest", objectId) end
  end

  stopCandidateCache = candidates
  stopCandidateLevel = level
  log("I", logTag, string.format("Prepared %d semantic taxi stop anchors for level '%s'", #candidates, level))
  return candidates
end

local function chooseSemanticStopPoint(startPos, minimumDistance, maximumDistance)
  local candidates = getStopCandidates()
  if not candidates[1] then return nil end

  local order = {}
  for index = 1, #candidates do order[index] = index end
  for index = #order, 2, -1 do
    local swapIndex = math.random(index)
    order[index], order[swapIndex] = order[swapIndex], order[index]
  end

  local maximumAttempts = math.min(#order, offerConfig.semanticCandidateAttempts)
  local recentFallback = nil
  for attempt = 1, maximumAttempts do
    offerGenerator.yield()
    local candidate = candidates[order[attempt]]
    local directDistance = startPos:distance(candidate.anchor)
    if directDistance >= minimumDistance * 0.2 and
      directDistance <= maximumDistance + 500 then
      local stop = projectAnchorToRoadEdge(candidate.anchor, nil, nil, true)
      if stop then
        local actualDistance = calculateRouteDistance(startPos, stop.pos)
        if actualDistance and actualDistance >= minimumDistance and actualDistance <= maximumDistance then
          stop.routeDistance = actualDistance
          stop.anchorKind = candidate.kind
          stop.anchorName = candidate.name
          if not isRecentlyUsedTaxiStop(stop.pos) then return stop end
          recentFallback = recentFallback or stop
        end
      end
    end
  end
  -- Keep a recently used semantic point only as a last resort. Returning it
  -- separately lets the caller try a fresh graph-derived road edge first.
  return nil, recentFallback
end

local function buildRandomPath(nodes, startNode, startDirection, maximumDistance)
  local path = map.getGraphpath():getRandomPathG(
    startNode,
    startDirection,
    maximumDistance + 1000,
    0.35 + math.random() * 0.5,
    1,
    true
  )

  if not path or #path < 2 then return nil end

  local planner = Route()
  for _, nodeId in ipairs(path) do
    local node = nodes[nodeId]
    if node then
      table.insert(planner.path, {
        pos = node.pos,
        wp = nodeId,
        linkCount = map.getNodeLinkCount(nodeId)
      })
    end
  end

  if #planner.path < 2 then return nil end
  planner:calcDistance()
  return planner
end

local function chooseRandomRoadPoint(startPos, startDirection, minimumDistance, maximumDistance, maximumAttempts)
  local mapData = map.getMap()
  if not mapData or not tableHasValues(mapData.nodes) then
    return nil, "На этой карте отсутствует дорожный граф"
  end

  local nodes = mapData.nodes
  local nodeA, nodeB = map.findClosestRoad(startPos)
  if not (nodeA and nodeB and nodes[nodeA] and nodes[nodeB]) then
    return nil, "Не удалось найти дорогу рядом с автомобилем"
  end

  local forward = vec3(startDirection)
  forward.z = 0
  if forward:length() < 0.1 then
    forward:set(1, 0, 0)
  else
    forward:normalize()
  end

  local roadDirection = (nodes[nodeB].pos - nodes[nodeA].pos):normalized()
  if roadDirection:dot(forward) < 0 then
    nodeA, nodeB = nodeB, nodeA
  end

  local recentFallback = nil
  for attempt = 1, math.max(
    1,
    tonumber(maximumAttempts) or offerConfig.randomRouteAttempts
  ) do
    offerGenerator.yield()
    local searchDirection = vec3(forward)
    if attempt % 4 == 0 then
      searchDirection:setScaled(-1)
    end

    local distanceRatio = math.random() ^ offerConfig.randomDistanceExponent
    local desiredDistance = minimumDistance + (maximumDistance - minimumDistance) * distanceRatio
    local planner = buildRandomPath(nodes, nodeA, searchDirection, maximumDistance)

    if planner and planner.path[1].distToTarget >= desiredDistance then
      local road = planner:stepAhead(desiredDistance, true)
      if road and road.n1 and road.n2 and isUsableRoad(nodes, road.n1, road.n2) then
        local direction = (nodes[road.n2].pos - nodes[road.n1].pos):normalized()
        local lanePos, laneDir = trafficUtils.finalizeSpawnPoint(
          road.pos,
          direction,
          road.n1,
          road.n2,
          {legalDirection = true}
        )

        local edgePoint = projectAnchorToRoadEdge(lanePos, road.n1, road.n2)
        local targetPos = edgePoint and edgePoint.pos or lanePos
        local targetDir = edgePoint and edgePoint.dir or laneDir
        local actualDistance = calculateRouteDistance(startPos, targetPos)
        if actualDistance and actualDistance >= minimumDistance and actualDistance <= maximumDistance then
          local stop = {
            pos = vec3(targetPos),
            dir = vec3(targetDir),
            routeDistance = actualDistance,
            nodeA = road.n1,
            nodeB = road.n2,
            anchorKind = "roadEdge"
          }
          if not isRecentlyUsedTaxiStop(stop.pos) then return stop end
          recentFallback = recentFallback or stop
        end
      end
    end
  end

  if recentFallback then return recentFallback end

  return nil, string.format(
    "Не удалось построить маршрут длиной от %.0f до %.0f км",
    minimumDistance / 1000,
    maximumDistance / 1000
  )
end

local function chooseTaxiStopPoint(startPos, startDirection, minimumDistance, maximumDistance, maximumAttempts)
  local semanticStop, semanticFallback = chooseSemanticStopPoint(
    startPos,
    minimumDistance,
    maximumDistance
  )
  if semanticStop then return semanticStop end
  local randomStop, randomError = chooseRandomRoadPoint(
    startPos,
    startDirection,
    minimumDistance,
    maximumDistance,
    maximumAttempts
  )
  if randomStop then return randomStop end
  if semanticFallback then return semanticFallback end
  return nil, randomError
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
    #getStopCandidates() >= offerConfig.multiStopMinimumCandidates
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
  local destinationMinDistance = isDelivery and taxiConfig.delivery.minimumDistance or
    (isMultiStop and math.max(
      1500,
      offerConfig.multiStopSegmentMin - multiStopRelaxation * 500
    ) or minRideDistance)
  local destinationMaxDistance = isDelivery and taxiConfig.delivery.maximumDistance or
    (isMultiStop and offerConfig.multiStopSegmentMax or maxRideDistance)
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

  if not isMultiStop and (rideDistance < minRideDistance or rideDistance > maxRideDistance) then
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
    rushTimeLimit = rushTimeLimit
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

local function updateNextOfferOpportunity(dtSim)
  if not trip or state.phase ~= phases.toDestination then return end

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
    errorMessage = generatedOffer
    generatedOffer = nil
  end
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
  local fare = getAdjustedFare()
  local rideRating = trip.isDelivery and
    delivery.calculateRating(trip.cargoDamagePercent or 0, taxiConfig.delivery) or
    clampValue(
      5 - penalty * balanceConfig.ratingPenaltyScale -
      (trip.ratingCollisionCount or 0) * balanceConfig.collisionRatingPenalty,
      balanceConfig.minimumRideRating,
      5
    )

  trip.finalFare = fare
  trip.rideRating = rideRating
  state.balance = state.balance + fare
  state.ratingTotal = state.ratingTotal + rideRating
  state.ratingCount = state.ratingCount + 1
  state.rating = state.ratingTotal / state.ratingCount
  state.completedRides = state.completedRides + 1
  if not trip.reviewRecorded then
    trip.reviewRecorded = true
    recordProgressEvent(
      trip.isDelivery and "Delivery" or trip.passengerName,
      getPassengerReviewEmoji(rideRating),
      rideRating / 5 * 100,
      fare,
      trip.isDelivery and "delivery" or "completed"
    )
  else
    writeUserProgress()
  end
  state.phase = phases.complete
  state.message = string.format("Получено $%.2f", fare)
  phaseTimer = completedDuration

  delivery.applyVehicleMass(
    state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil,
    0
  )
  showPhoneNotification(
    trip.isDelivery and "notify_deliveryComplete" or "notify_rideComplete",
    {fare = string.format("$%.2f", fare)},
    "success"
  )
  notifyHud()
end

local function getNearestRoadSpeedLimit(pos)
  if not pos then return nil end
  local nodeA, nodeB = map.findClosestRoad(pos)
  if not (nodeA and nodeB) then return nil end

  local nodes = map.getMap().nodes
  local link = getRoadLink(nodes, nodeA, nodeB)
  if not link or not link.speedLimit then return nil end

  local speedLimit = link.speedLimit * 3.6
  if speedLimit < 5 or speedLimit > 250 then return nil end
  return speedLimit
end

local function updateSpeedPenalty(vehicle, dtSim)
  if not trip or trip.isDelivery or not isPassengerDrivingPhase(state.phase) then return end

  local speed = getVehicleSpeedKmh(vehicle)
  local speedLimit = getNearestRoadSpeedLimit(vehicle:getPosition())
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
    stationName = "Gas Station",
    pos = position,
    routeDistance = math.max(0, tonumber(routeDistance) or 0),
    previousRemainingDistance = getRemainingDistance(),
    penaltyPercent = penaltyPercent,
    penaltyApplied = false,
    arrived = arrived == true
  }
  if arrived and passengerOnboard then
    realisticFuel.applyPassengerWaitPenalty(facility.id, "Gas Station")
    realisticFuel.detour.penaltyApplied = true
  end
  state.phase = phases.toFuelStation
  state.message = "Следуйте к заправке"
  phaseTimer = 0
  if arrived then clearNavigation() else setNavigationTarget({pos = position}) end
  showPhoneNotification("notify_fuelRouteSet", {
    station = realisticFuel.detour.stationName
  }, "info")
  notifyHud()
  return true
end

function realisticFuel.resumeRoute()
  if not realisticFuel.detour.active then return end
  local previousPhase = realisticFuel.detour.previousPhase
  local previousRemainingDistance = realisticFuel.detour.previousRemainingDistance or 0
  realisticFuel.resetDetour()
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

function realisticFuel.requestRoute()
  if not state.active or not state.realisticMode then return end
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
  core_vehicleBridge.requestValue(vehicle, function(data)
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
      showPhoneNotification("notify_noFuelStation", {}, "warning")
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
  realisticFuel.updateDashboardEnergy(dtSim)
  realisticFuel.updateStation(dtSim)
  realisticFuel.updatePassengerMood(dtSim)

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
    updateNextOfferOpportunity(dtSim)
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

function M.startMode()
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
    realisticFuel.initializeVehicle(vehicle)
  else
    realisticFuel.restoreEconomy()
  end
  setTelemetryEnabled(vehicle, true)
  beginSearching("Подключение к линии заказов")
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
  notifyHud()
end

function M.requestProfileData()
  notifyProfile()
end

function M.requestRealisticFuelData()
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
  local sessionLanEnabled = type(incomingSettings) == "table" and
    incomingSettings.lanEnabled == true
  userSettings = sanitizeUserSettings(incomingSettings, false)
  userSettings.lanEnabled = sessionLanEnabled
  settingsNeedsLegacyImport = false
  applyDifficulty(userSettings.difficulty)
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
function M.externalPhoneHeartbeat(token)
  return lanBridge.externalHeartbeat(token)
end

function M.requestExternalMapData()
  lanBridge.requestExternalMap()
end

function M.cheatSetRating(value)
  local requestedRating = tonumber(value)
  if not requestedRating then
    log("W", logTag, "Cheat rating ignored: invalid value " .. tostring(value))
    return state.rating
  end
  local rating = clampValue(requestedRating, 0, 5)
  if not userProgress then userProgress = createDefaultUserProgress() end
  state.ratingCount = math.max(1, math.floor(tonumber(state.ratingCount) or 0))
  state.rating = rating
  state.ratingTotal = rating * state.ratingCount
  userProgress.rating = rating
  userProgress.ratingCount = state.ratingCount
  userProgress.ratingTotal = state.ratingTotal
  userProgress.sequence = math.max(0, math.floor(tonumber(userProgress.sequence) or 0)) + 1
  table.insert(userProgress.ratingHistory, {
    index = userProgress.sequence,
    value = roundMoney(rating),
    timestamp = os.time()
  })
  writeUserProgress()
  notifyProfile()
  notifyHud()
  log("I", logTag, string.format("Cheat rating applied: %.2f", rating))
  return rating
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
    rating
  )
  notifyProfile()
  notifyHud()
end

function M.cheatResetProgress()
  userProgress = createDefaultUserProgress()
  applyUserProgressToState()
  writeUserProgress()
  notifyProfile()
  notifyHud()
end

local function canShowNativeMinimap()
  return state.active and (
    state.phase == phases.toPickup or
    state.phase == phases.toStop or
    state.phase == phases.toDestination or
    state.phase == phases.toFuelStation
  )
end

function M.setMinimapTransform(x, y, width, height)
  if not canShowNativeMinimap() then
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
  notificationX, notificationY, notificationWidth, notificationHeight
)
  if not canShowNativeMinimap() then return end
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
  updateOcclusion(
    "taxiDriverNotification",
    notificationX,
    notificationY,
    notificationWidth,
    notificationHeight
  )
end

function M.hideMinimap()
  hideNativeMinimap()
end

function M.onTelemetry(vehicleId, data)
  if vehicleId ~= state.activeVehicleId or type(data) ~= "table" then return end

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
  dtReal = math.max(0, dtReal or 0)
  dtSim = math.max(0, dtSim or 0)
  lanBridge.update(dtReal)
  if lanBridge.consumeStatusChanged() then notifyHud() end
  if not state.active then return end
  updateActiveMode(dtSim)

  hudTimer = hudTimer + dtReal
  if hudTimer >= hudUpdateInterval then
    hudTimer = 0
    notifyHud()
  end
end

function M.onVehicleSwitched(oldId, newId)
  if state.active and oldId == state.activeVehicleId and newId ~= oldId then
    stopModeInternal("Режим остановлен после смены автомобиля", true, "notify_vehicleChanged")
  end
end

local function handleVehicleReset(vehicleId)
  vehicleId = tonumber(vehicleId)
  if vehicleId then
    realisticFuel.initializedVehicles[vehicleId] = nil
    realisticFuel.initializationPending[vehicleId] = nil
  end
  if state.active and vehicleId and vehicleId == tonumber(state.activeVehicleId) then
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

function M.onExtensionLoaded()
  loadUserSettings()
  loadDriverProfile()
  loadUserProgress()
  lanBridge.setCommandHandler(function(action, args)
    args = type(args) == "table" and args or {}
    if action == "start" then
      M.startMode()
      return state.active == true
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
    end
    return false, "unsupported_command"
  end)
  lanBridge.setEnabled(userSettings.lanEnabled)
  delivery.applyVehicleMass(getPlayerVehicle(), 0)
  notifyHud()
end

function M.onClientEndMission()
  hideNativeMinimap()
  realisticFuel.restoreEconomy()
  realisticFuel.initializedVehicles = {}
  realisticFuel.initializationPending = {}
  stopCandidateCache = nil
  stopCandidateLevel = nil
  recentTaxiStopPositions = {}
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  phoneNotification = nil
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
  restoreNavigationVisualSettings()
end

function M.onExtensionUnloaded()
  lanBridge.stop()
  hideNativeMinimap()
  delivery.applyVehicleMass(getPlayerVehicle(), 0)
  realisticFuel.restoreEconomy()
  recentTaxiStopPositions = {}
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
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
  trip = nil
  offers = {}
  clearNextOffer()
  offerTimer = 0
  phoneNotification = nil
  stopCandidateCache = nil
  stopCandidateLevel = nil
  recentTaxiStopPositions = {}
  offerGeneration.recentRoutes = {}
  realisticFuel.resetDashboardEnergy()
  notifyHud()
end

return M
