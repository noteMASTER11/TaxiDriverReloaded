local M = {}

M.dependencies = {
  "core_groundMarkers",
  "core_vehicleTriggers",
  "core_vehicle_manager",
  "gameplay_sites_sitesManager"
}

local Route = require("gameplay/route/route")
local trafficUtils = require("gameplay/traffic/trafficUtils")

local logTag = "taxiDriver"
local modVersion = "2.11.1"
local settingsSchemaVersion = 1
local profileSchemaVersion = 1
local progressSchemaVersion = 1
local settingsDirectoryPath = "/settings/TaxiDriver"
local settingsFilePath = settingsDirectoryPath .. "/settings.json"
local profileFilePath = settingsDirectoryPath .. "/profile.json"
local progressFilePath = settingsDirectoryPath .. "/progress.json"

local supportedLanguages = {
  en = true, de = true, fr = true, es = true,
  pl = true, uk = true, ru = true
}

local minRideDistance = 1000
local maxRideDistance = 25000
local minPickupDistance = 400
local maxPickupDistance = 3500
local arrivalRadius = 14
local maxArrivalSpeedKmh = 4
local averageCitySpeedKmh = 40
local minimumDrivability = 0.7
local hudUpdateInterval = 0.2
local boardingDuration = 3
local alightingDuration = 3
local completedDuration = 4
local stopWaitingDuration = 10
local forcedExitDuration = 5

local offerConfig = {
  initialDelay = 1.5,
  intervalMin = 1.2,
  intervalMax = 2.2,
  minVisible = 10,
  maxVisible = 12,
  nextOfferDuration = 5,
  nextOfferRetryMin = 5,
  nextOfferRetryMax = 10,
  pickupTimeMultiplier = 1.35,
  pickupTimeGraceSeconds = 60,
  pickupTimeMinSeconds = 120,
  pickupTimeMaxSeconds = 600,
  multiStopChance = 0.24,
  multiStopVisibleMin = 2,
  multiStopVisibleMax = 3,
  rushVisibleMin = 2,
  rushVisibleMax = 4,
  multiStopCountMin = 2,
  multiStopCountMax = 2,
  multiStopMinimumCandidates = 20,
  multiStopSegmentMin = 3000,
  multiStopSegmentMax = 7000,
  multiStopRouteAttempts = 18,
  generationFailureBackoffMin = 4,
  generationFailureBackoffMax = 7,
  rushChance = 0.28,
  rushBonusMin = 0.22,
  rushBonusMax = 0.42,
  rushTimeRatioMin = 0.72,
  rushTimeRatioMax = 0.86
}

local balanceConfig = {
  baseFare = 3.25,
  farePerKm = 1.55,
  farePerMinute = 0.20,
  ratingBonusThreshold = 3.99,
  maxRatingBonus = 0.15,
  maxTotalPenalty = 0.50,
  pickupLateBasePenalty = 0.05,
  pickupLatePenaltyPerSecond = 0.000333,
  maxPickupLatePenalty = 0.12,
  speedToleranceKmh = 8,
  speedToleranceRatio = 0.15,
  speedGraceSeconds = 3,
  speedPenaltyRate = 0.0008,
  maxSpeedPenalty = 0.15,
  collisionDamageScale = 12000,
  collisionDamageThreshold = 20,
  collisionDamagePenalty = 0.18,
  collisionEventPenalty = 0.01,
  collisionCooldownSeconds = 3,
  maxCollisionPenalty = 0.20,
  longitudinalGThreshold = 0.62,
  lateralGThreshold = 0.55,
  longitudinalGRelease = 0.40,
  lateralGRelease = 0.35,
  aggressionEventPenalty = 0.005,
  aggressionExtraRate = 0.015,
  aggressionExtraMax = 0.01,
  aggressionCooldownSeconds = 3,
  maxAggressionPenalty = 0.12,
  ratingPenaltyScale = 8,
  collisionRatingPenalty = 0.15,
  minimumRideRating = 1,
  calmPenaltyIgnoreMaximum = 0.70,
  calmPenaltyMultiplierThreshold = 50,
  passengerStressThresholdMinimum = 72,
  passengerStressThresholdCalmBonus = 23
}

local earlyExitRatingLoss = {
  elementary = 0.10,
  easy = 0.20,
  standard = 0.30,
  professional = 0.45
}

local driverAbandonmentExtraLoss = {
  elementary = 0.10,
  easy = 0.20,
  standard = 0.30,
  professional = 0.45
}

local driverAvatarOptions = {
  "🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔",
  "👨‍🦰", "👩‍🦰", "👨‍🦱", "👩‍🦱", "👨‍🦳", "👩‍🦳", "🧑‍✈️", "🧑‍💼",
  "🧑‍🔧", "🦸", "🥷", "🤠", "🧢", "🎩", "🚕", "🏁",
  "🐻", "🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐧"
}

local driverAvatarSet = {}
for _, avatar in ipairs(driverAvatarOptions) do driverAvatarSet[avatar] = true end

local difficultyPresets = {
  elementary = {
    speedToleranceKmh = 15, speedToleranceRatio = 0.25, speedGraceSeconds = 6,
    speedPenaltyRate = 0.00025, maxSpeedPenalty = 0.06,
    collisionDamageScale = 22000, collisionDamageThreshold = 60,
    collisionDamagePenalty = 0.10, collisionEventPenalty = 0.004, maxCollisionPenalty = 0.10,
    longitudinalGThreshold = 0.88, lateralGThreshold = 0.78,
    longitudinalGRelease = 0.55, lateralGRelease = 0.48,
    aggressionEventPenalty = 0.002, aggressionExtraRate = 0.006,
    aggressionExtraMax = 0.004, maxAggressionPenalty = 0.05
  },
  easy = {
    speedToleranceKmh = 11, speedToleranceRatio = 0.20, speedGraceSeconds = 4.5,
    speedPenaltyRate = 0.00045, maxSpeedPenalty = 0.10,
    collisionDamageScale = 17000, collisionDamageThreshold = 35,
    collisionDamagePenalty = 0.14, collisionEventPenalty = 0.007, maxCollisionPenalty = 0.14,
    longitudinalGThreshold = 0.74, lateralGThreshold = 0.66,
    longitudinalGRelease = 0.48, lateralGRelease = 0.42,
    aggressionEventPenalty = 0.0035, aggressionExtraRate = 0.01,
    aggressionExtraMax = 0.006, maxAggressionPenalty = 0.08
  },
  standard = {
    speedToleranceKmh = 8, speedToleranceRatio = 0.15, speedGraceSeconds = 3,
    speedPenaltyRate = 0.0008, maxSpeedPenalty = 0.15,
    collisionDamageScale = 12000, collisionDamageThreshold = 20,
    collisionDamagePenalty = 0.18, collisionEventPenalty = 0.01, maxCollisionPenalty = 0.20,
    longitudinalGThreshold = 0.62, lateralGThreshold = 0.55,
    longitudinalGRelease = 0.40, lateralGRelease = 0.35,
    aggressionEventPenalty = 0.005, aggressionExtraRate = 0.015,
    aggressionExtraMax = 0.01, maxAggressionPenalty = 0.12
  },
  professional = {
    speedToleranceKmh = 4, speedToleranceRatio = 0.08, speedGraceSeconds = 1.5,
    speedPenaltyRate = 0.0018, maxSpeedPenalty = 0.25,
    collisionDamageScale = 8000, collisionDamageThreshold = 10,
    collisionDamagePenalty = 0.24, collisionEventPenalty = 0.02, maxCollisionPenalty = 0.30,
    longitudinalGThreshold = 0.48, lateralGThreshold = 0.42,
    longitudinalGRelease = 0.32, lateralGRelease = 0.28,
    aggressionEventPenalty = 0.01, aggressionExtraRate = 0.025,
    aggressionExtraMax = 0.018, maxAggressionPenalty = 0.20
  }
}

local phases = {
  inactive = "inactive",
  searching = "searching",
  toPickup = "toPickup",
  boarding = "boarding",
  toStop = "toStop",
  stopWaiting = "stopWaiting",
  toDestination = "toDestination",
  passengerStopDemand = "passengerStopDemand",
  passengerForcedExit = "passengerForcedExit",
  driverAbandoning = "driverAbandoning",
  alighting = "alighting",
  complete = "complete",
  error = "error"
}

local phaseLabels = {
  inactive = "Режим такси выключен",
  searching = "Поиск заказов",
  toPickup = "Следуйте к пассажиру",
  boarding = "Пассажир садится",
  toStop = "Следуйте к промежуточной остановке",
  stopWaiting = "Ожидание на остановке",
  toDestination = "Доставьте пассажира",
  passengerStopDemand = "Пассажир требует немедленно остановиться",
  passengerForcedExit = "Пассажир досрочно покидает машину",
  driverAbandoning = "Водитель завершает поездку",
  alighting = "Пассажир выходит",
  complete = "Поездка завершена",
  error = "Заказ недоступен"
}

local passengerFirstNames = {
  "Aiden", "Alice", "Amelia", "Benjamin", "Charlotte", "Chloe", "Daniel", "Eleanor",
  "Emily", "Ethan", "Evelyn", "Grace", "Henry", "Isabella", "Jack", "James",
  "Liam", "Lily", "Lucas", "Mason", "Mia", "Noah", "Olivia", "Oscar",
  "Ruby", "Samuel", "Scarlett", "Sophia", "Thomas", "Victoria", "William", "Zoe"
}

local passengerLastNames = {
  "Adams", "Baker", "Bennett", "Brooks", "Brown", "Campbell", "Carter", "Clark",
  "Collins", "Cooper", "Davis", "Edwards", "Evans", "Foster", "Green", "Hall",
  "Harris", "Hayes", "Hill", "Howard", "Jackson", "Johnson", "Lewis", "Martin",
  "Miller", "Mitchell", "Morgan", "Parker", "Reed", "Roberts", "Scott", "Walker"
}

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
  message = ""
}

local function createDefaultUserSettings()
  return {
    schemaVersion = settingsSchemaVersion,
    modVersion = modVersion,
    language = "en",
    rememberLanguage = false,
    difficulty = "standard",
    fontBoost = 2,
    silentMode = false,
    showRouteGuidance = true
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
local offerGenerationFailures = 0
local multiStopUnavailableForPool = false
local nextOfferId = 1
local minimapOriginalMode = nil
local minimapOwned = false
local minimapOriginalDrawPlayer = nil
local minimapWrappedDrawPlayer = nil
local minimapZoomMultiplier = nil
local stopCandidateCache = nil
local stopCandidateLevel = nil
local recentTaxiStopPositions = {}
local recentTaxiStopLimit = 24
local recentTaxiStopSeparation = 90
local navigationVisualOverrideActive = false
local originalNavigationGroundmarkers = nil
local originalNavigationArrows = nil

local function clampValue(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function applyDifficulty(presetId)
  local preset = difficultyPresets[presetId]
  if not preset then return false end
  for key, value in pairs(preset) do
    balanceConfig[key] = value
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
  if difficultyPresets[tostring(source.difficulty or "")] then
    result.difficulty = tostring(source.difficulty)
  end

  local fontBoost = tonumber(source.fontBoost)
  if fontBoost then
    result.fontBoost = math.floor(clampValue(fontBoost, 0, 5) + 0.5)
  end
  result.silentMode = source.silentMode == true
  result.showRouteGuidance = source.showRouteGuidance ~= false
  return result, true
end

local function writeUserSettings()
  local ok, errorMessage = pcall(function()
    if not FS:directoryExists(settingsDirectoryPath) then
      FS:directoryCreate(settingsDirectoryPath)
    end
    jsonWriteFile(settingsFilePath, userSettings, true)
  end)
  if not ok then
    log("E", logTag, "Unable to write settings: " .. tostring(errorMessage))
  end
  return ok
end

local function loadUserSettings()
  local fileExists = FS:fileExists(settingsFilePath)
  local source = nil
  if fileExists then
    local ok, loaded = pcall(jsonReadFile, settingsFilePath)
    if ok then source = loaded end
  end

  userSettings = sanitizeUserSettings(source, true)
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

local function createPassengerName()
  return string.format(
    "%s %s",
    passengerFirstNames[math.random(#passengerFirstNames)],
    passengerLastNames[math.random(#passengerLastNames)]
  )
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
  local multiStopCount = 0
  if allowMultiStop then
    multiStopCount = math.min(
      targetCount,
      math.random(offerConfig.multiStopVisibleMin, offerConfig.multiStopVisibleMax)
    )
  end
  local rushCount = math.min(
    targetCount - multiStopCount,
    math.random(offerConfig.rushVisibleMin, offerConfig.rushVisibleMax)
  )

  for _ = 1, multiStopCount do table.insert(plan, "multiStop") end
  for _ = 1, rushCount do table.insert(plan, "rush") end
  while #plan < targetCount do table.insert(plan, "normal") end
  return shuffleArray(plan)
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

local function calculateEtaMinutes(distanceMeters)
  return math.max(0, distanceMeters or 0) / 1000 / averageCitySpeedKmh * 60
end

local function calculateFare(distanceMeters, waitingSeconds)
  local distanceKm = math.max(0, distanceMeters or 0) / 1000
  local etaMinutes = calculateEtaMinutes(distanceMeters) + math.max(0, waitingSeconds or 0) / 60
  return roundMoney(
    balanceConfig.baseFare +
    distanceKm * balanceConfig.farePerKm +
    etaMinutes * balanceConfig.farePerMinute
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
  return phase == phases.toStop or phase == phases.toDestination
end

local function isPassengerOnboardPhase(phase)
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
  return clampValue(
    (trip.speedPenalty or 0) +
    (trip.collisionPenalty or 0) +
    (trip.aggressionPenalty or 0) +
    (trip.pickupPenalty or 0),
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

local function buildHudOffer(offer)
  if not offer then return nil end
  return {
    id = offer.id,
    passengerName = offer.passengerName,
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
      peakG = event.peakG or 0,
      lateSeconds = event.lateSeconds or 0,
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
    offlinePenaltyExtraPercent = abandonmentPreview.extraPercent,
    offlinePenaltyRatingLoss = abandonmentPreview.ratingLoss,
    offlinePenaltyFinalRating = abandonmentPreview.finalRating,
    difficulty = state.difficulty,
    settings = userSettings,
    settingsNeedsLegacyImport = settingsNeedsLegacyImport,
    offers = buildHudOffers(),
    offerTargetCount = offerTargetCount,
    nextOffer = hudNextOffer,
    notification = phoneNotification,
    penaltyEvents = buildHudPenaltyEvents(),
    activeTripId = trip and trip.id or 0,
    passengerName = trip and trip.passengerName or "",
    passengerCalmness = trip and trip.passengerCalmness or 50,
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
      speedingEvents = trip and trip.speedingEvents or 0,
      collisions = trip and trip.collisionCount or 0,
      aggressionEvents = trip and trip.aggressionEvents or 0
    }
  }
end

local function notifyHud()
  guihooks.trigger("TaxiDriverHUDState", buildHudState())
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

local function recordProgressEvent(passengerName, emoji, quality, fare, outcome)
  if not userProgress then userProgress = createDefaultUserProgress() end
  userProgress.sequence = math.max(0, math.floor(tonumber(userProgress.sequence) or 0)) + 1
  local timestamp = os.time()
  table.insert(userProgress.reviews, {
    id = userProgress.sequence,
    passengerName = trimText(passengerName) ~= "" and trimText(passengerName) or "Passenger",
    emoji = reviewEmojiSet[emoji] and emoji or "😐",
    quality = clampValue(tonumber(quality) or 0, 0, 100),
    fare = roundMoney(math.max(0, tonumber(fare) or 0)),
    rating = clampValue(tonumber(state.rating) or 5, 0, 5),
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

local function togglePassengerDoor(vehicle, preferredTriggerId)
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

    if links and links.action0 and string.find(name, "door", 1, true) and
      not string.find(name, "int", 1, true) and
      not string.find(name, "interior", 1, true) then
      local score = 10
      if string.find(name, "rr", 1, true) or string.find(name, "rear right", 1, true) then
        score = 100
      elseif string.find(name, "rl", 1, true) or string.find(name, "rear left", 1, true) then
        score = 90
      elseif string.find(name, "fr", 1, true) or string.find(name, "front right", 1, true) then
        score = 70
      elseif string.find(name, "passenger", 1, true) then
        score = 60
      end
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
    local targetMultiplier = 0.66 + (1.62 - 0.66) * easedSpeed

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
  local longitudinalJitter = math.min(35, segmentLength * 0.32)
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
  if stopCandidateLevel ~= level then recentTaxiStopPositions = {} end

  local candidates = {}
  local occupiedCells = {}
  local function addCandidate(pos, kind, name)
    if not pos then return end
    local anchor = vec3(pos)
    local cellKey = string.format("%d:%d", math.floor(anchor.x / 8), math.floor(anchor.y / 8))
    if occupiedCells[cellKey] then return end
    occupiedCells[cellKey] = true
    table.insert(candidates, {anchor = anchor, kind = kind, name = name or kind})
  end

  for _, objectId in ipairs(scenetree.findClassObjects("BeamNGTrigger") or {}) do
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

  local maximumAttempts = math.min(#order, 80)
  local recentFallback = nil
  for attempt = 1, maximumAttempts do
    local candidate = candidates[order[attempt]]
    if startPos:distance(candidate.anchor) <= maximumDistance + 500 then
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
  return recentFallback
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
  for attempt = 1, math.max(1, tonumber(maximumAttempts) or 60) do
    local searchDirection = vec3(forward)
    if attempt % 4 == 0 then
      searchDirection:setScaled(-1)
    end

    local distanceRatio = math.random() ^ 1.65
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
  local semanticStop = chooseSemanticStopPoint(startPos, minimumDistance, maximumDistance)
  if semanticStop then return semanticStop end
  return chooseRandomRoadPoint(
    startPos,
    startDirection,
    minimumDistance,
    maximumDistance,
    maximumAttempts
  )
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
end

local function resetTripMetrics()
  if not trip then return end
  trip.speedPenalty = 0
  trip.collisionPenalty = 0
  trip.aggressionPenalty = 0
  trip.pickupPenalty = 0
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
  if trip and trip.passengerDoorTriggerId and
    (state.phase == phases.boarding or state.phase == phases.alighting or
      state.phase == phases.passengerForcedExit or state.phase == phases.driverAbandoning) then
    togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  end
  releaseForcedPassengerStop(vehicle)
  setTelemetryEnabled(vehicle, false)
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()

  state.active = false
  state.phase = phases.inactive
  state.activeVehicleId = nil
  state.message = message or ""
  trip = nil
  offers = {}
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

  local isMultiStop = requestedType == "multiStop" or
    (requestedType == nil and math.random() < offerConfig.multiStopChance)
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
      local segmentDistance = calculateRouteDistance(routeOrigin.pos, stop.pos)
      if not segmentDistance then return nil, "Не удалось построить участок маршрута с остановками" end
      stop.routeDistance = segmentDistance
      rideDistance = rideDistance + segmentDistance
      table.insert(stops, stop)
      routeOrigin = stop
    end
  end

  local multiStopRelaxation = math.min(3, math.max(0, tonumber(generationFailureCount) or 0))
  local destinationMinDistance = isMultiStop and
    math.max(1500, offerConfig.multiStopSegmentMin - multiStopRelaxation * 500) or minRideDistance
  local destinationMaxDistance = isMultiStop and offerConfig.multiStopSegmentMax or maxRideDistance
  local destination, destinationError = chooseTaxiStopPoint(
    routeOrigin.pos,
    routeOrigin.dir,
    destinationMinDistance,
    destinationMaxDistance,
    isMultiStop and offerConfig.multiStopRouteAttempts or nil
  )
  if not destination then return nil, destinationError end

  local destinationDistance = calculateRouteDistance(routeOrigin.pos, destination.pos)
  if not destinationDistance then
    return nil, "Полученный маршрут не прошёл проверку дистанции"
  end
  destination.routeDistance = destinationDistance
  rideDistance = rideDistance + destinationDistance

  if not isMultiStop and (rideDistance < minRideDistance or rideDistance > maxRideDistance) then
    return nil, "Полученный маршрут не прошёл проверку дистанции"
  end

  local waitingSeconds = #stops * stopWaitingDuration
  local baseFare = calculateFare(rideDistance, waitingSeconds)
  local ratingBonusRate = calculateRatingBonusRate(state.rating)
  local ratingAdjustedFare = roundMoney(baseFare * (1 + ratingBonusRate))
  local ratingBonusAmount = roundMoney(ratingAdjustedFare - baseFare)
  local isRush = not isMultiStop and (
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
  local offer = {
    id = nextOfferId,
    passengerName = createPassengerName(),
    passengerCalmness = math.random(0, 100),
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
    pickupWaitLimit = calculatePickupWaitSeconds(pickup.routeDistance),
    isRush = isRush,
    bonusPercent = bonusPercent,
    bonusAmount = roundMoney(estimatedFare - ratingAdjustedFare),
    rushTimeLimit = rushTimeLimit
  }
  nextOfferId = nextOfferId + 1
  return offer
end

local function scheduleNextOffer()
  offerTimer = randomRange(offerConfig.intervalMin, offerConfig.intervalMax)
end

local function beginSearching(message)
  hideNativeMinimap()
  clearNavigation()
  restoreNavigationVisualSettings()
  trip = nil
  offers = {}
  clearNextOffer()
  state.phase = phases.searching
  state.message = message or "Ищем пассажиров поблизости"
  phaseTimer = 0
  offerTargetCount = math.random(offerConfig.minVisible, offerConfig.maxVisible)
  local allowMultiStop = #getStopCandidates() >= offerConfig.multiStopMinimumCandidates
  offerTypePlan = buildOfferTypePlan(offerTargetCount, allowMultiStop)
  offerGenerationFailures = 0
  multiStopUnavailableForPool = not allowMultiStop
  offerTimer = offerConfig.initialDelay
  notifyHud()
end

local function addOffer()
  if #offers >= offerTargetCount then return end

  local plannedType = offerTypePlan[#offers + 1]
  local requestedType = plannedType
  if plannedType == "multiStop" and
    (offerGenerationFailures >= 1 or multiStopUnavailableForPool) then
    requestedType = "normal"
  end
  local offer, errorMessage = createOffer(requestedType, offerGenerationFailures)
  if offer then
    rememberOfferStops(offer)
    table.insert(offers, offer)
    offerGenerationFailures = 0
    state.message = string.format("Доступно заказов: %d", #offers)
    notifyHud()
  else
    if requestedType == "multiStop" then multiStopUnavailableForPool = true end
    offerGenerationFailures = offerGenerationFailures + 1
    log("W", logTag, errorMessage or "Unable to generate taxi offer")
    if offerGenerationFailures >= 2 then
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

  local pickupDistance = calculateRouteDistance(vehicle:getPosition(), selected.pickup.pos)
  if not pickupDistance then return false, "Не удалось построить маршрут к пассажиру" end
  selected.pickup.routeDistance = pickupDistance
  selected.pickupWaitLimit = calculatePickupWaitSeconds(pickupDistance)

  clearNextOffer()
  trip = selected
  offers = {}
  resetTripMetrics()
  trip.pickupTimeRemaining = trip.pickupWaitLimit
  trip.completedRideDistance = 0
  trip.currentLegDistance = 0
  trip.currentStopIndex = 0

  state.phase = phases.toPickup
  state.message = string.format("Пассажир: %s", trip.passengerName)
  phaseTimer = 0
  setNavigationTarget(trip.pickup)
  showPhoneNotification("notify_orderAccepted", {name = trip.passengerName}, "success")
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
    if progress <= 0.90 then return end
    trip.nextOfferPrompted = true
    trip.nextOfferRetryTimer = 0
  end

  trip.nextOfferRetryTimer = math.max(0, (trip.nextOfferRetryTimer or 0) - dtSim)
  if trip.nextOfferRetryTimer > 0 then return end

  local generatedOffer, errorMessage = createOffer()
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
  state.message = "Открываем пассажирскую дверь"
  if phoneNotification and phoneNotification.key == "notify_orderAccepted" then
    phoneNotification = nil
  end
  phaseTimer = boardingDuration
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  notifyHud()
end

local function updatePickupDeadline(dtSim)
  if not trip or state.phase ~= phases.toPickup then return end
  local previousRemaining = trip.pickupTimeRemaining or trip.pickupWaitLimit or 0
  local rawRemaining = previousRemaining - dtSim
  trip.pickupTimeRemaining = math.max(0, rawRemaining)
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
  togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
  preparePassengerRideMetrics()
  if trip.isRush then
    trip.rushTimeRemaining = trip.rushTimeLimit
    trip.rushBonusLost = false
  end
  trip.completedRideDistance = 0
  trip.currentStopIndex = 1
  state.message = trip.isRush and
    string.format("Срочный заказ: сохраните бонус $%.2f", trip.bonusAmount or 0) or
    string.format("%s в автомобиле", trip.passengerName)
  if trip.isMultiStop and trip.stops and trip.stops[1] then
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
  state.message = "Открываем пассажирскую дверь"
  phaseTimer = alightingDuration
  local vehicle = state.activeVehicleId and getObjectByID(state.activeVehicleId) or nil
  trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
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
  recordProgressEvent(trip.passengerName, "🤬", 0, 0, "driverAbandonment")
end

beginPassengerStopDemand = function()
  if not trip or not isPassengerDrivingPhase(state.phase) or trip.passengerStopRequested then return end
  trip.passengerStopRequested = true
  hideNativeMinimap()
  clearNavigation()
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
  trip.passengerDoorTriggerId = togglePassengerDoor(vehicle, trip.passengerDoorTriggerId)
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
  local rideRating = clampValue(
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
      trip.passengerName,
      getPassengerReviewEmoji(rideRating),
      rideRating / 5 * 100,
      fare,
      "completed"
    )
  else
    writeUserProgress()
  end
  state.phase = phases.complete
  state.message = string.format("Получено $%.2f", fare)
  phaseTimer = completedDuration

  showPhoneNotification("notify_rideComplete", {fare = string.format("$%.2f", fare)}, "success")
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
  if not trip or not isPassengerDrivingPhase(state.phase) then return end

  local speed = getVehicleSpeedKmh(vehicle)
  local speedLimit = getNearestRoadSpeedLimit(vehicle:getPosition())
  trip.currentSpeed = speed
  trip.speedLimit = speedLimit or 0

  if not speedLimit then
    trip.speedingEpisodeTime = 0
    trip.speedingEpisodeCounted = false
    trip.speedingEpisodeDisposition = nil
    trip.activeSpeedingEvent = nil
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
        addPassengerStress(5 + math.min(10, excess / 5))
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
  end
end

local function updateRushTimer(dtSim)
  if not trip or not trip.isRush or trip.rushBonusLost then return end
  if not isPassengerDrivingPhase(state.phase) and state.phase ~= phases.stopWaiting then return end

  trip.rushTimeRemaining = math.max(0, (trip.rushTimeRemaining or trip.rushTimeLimit or 0) - dtSim)
  if trip.rushTimeRemaining > 0 then return end

  trip.rushBonusLost = true
  local bonusEvent = addPenaltyEvent(
    "bonus",
    "Бонус за срочность отменён",
    0,
    "Истёк лимит времени заказа"
  )
  if bonusEvent then bonusEvent.fareAmount = trip.bonusAmount or 0 end
  state.message = "Время вышло: бонусная часть оплаты отменена"
  showPhoneNotification("notify_rushExpired", {}, "warning")
end

local function updateTripCooldowns(dtSim)
  if not trip then return end
  trip.collisionCooldown = math.max(0, (trip.collisionCooldown or 0) - dtSim)
  trip.aggressionCooldown = math.max(0, (trip.aggressionCooldown or 0) - dtSim)
  trip.damageGraceTimer = math.max(0, (trip.damageGraceTimer or 0) - dtSim)
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

  if state.phase == phases.searching then
    if #offers < offerTargetCount then
      offerTimer = offerTimer - dtSim
      if offerTimer <= 0 then addOffer() end
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
      togglePassengerDoor(vehicle, trip and trip.passengerDoorTriggerId or nil)
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
  state.message = ""
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
  userSettings = sanitizeUserSettings(incomingSettings, false)
  settingsNeedsLegacyImport = false
  applyDifficulty(userSettings.difficulty)
  writeUserSettings()

  restoreNavigationVisualSettings()
  if state.active and trip then
    if state.phase == phases.toPickup then
      setNavigationTarget(trip.pickup)
    elseif state.phase == phases.toStop and trip.stops then
      setNavigationTarget(trip.stops[trip.currentStopIndex or 0])
    elseif state.phase == phases.toDestination then
      setNavigationTarget(trip.destination)
    end
  end
  notifyHud()
end

local function canShowNativeMinimap()
  return state.active and (
    state.phase == phases.toPickup or
    state.phase == phases.toStop or
    state.phase == phases.toDestination
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

    if damageDelta >= balanceConfig.collisionDamageThreshold then
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
    addPassengerStress(6 + math.min(12, thresholdExcess * 18))
    trip.aggressionActive = true
    trip.aggressionCooldown = balanceConfig.aggressionCooldownSeconds
  elseif released then
    trip.aggressionActive = false
  end
end

local function onUpdate(dtReal, dtSim)
  if not state.active then return end
  dtReal = math.max(0, dtReal or 0)
  dtSim = math.max(0, dtSim or 0)
  updateActiveMode(dtSim)

  hudTimer = hudTimer + dtReal
  if hudTimer >= hudUpdateInterval then
    hudTimer = 0
    notifyHud()
  end
end

local function onVehicleSwitched(oldId, newId)
  if state.active and oldId == state.activeVehicleId and newId ~= oldId then
    stopModeInternal("Режим остановлен после смены автомобиля", true, "notify_vehicleChanged")
  end
end

local function handleVehicleReset(vehicleId)
  vehicleId = tonumber(vehicleId)
  if state.active and vehicleId and vehicleId == tonumber(state.activeVehicleId) then
    -- Clear the queued order before stopping the session. The explicit clear
    -- also guarantees an immediate HUD reset if the vehicle and GE reset hooks
    -- arrive in different frames.
    clearNextOffer()
    stopModeInternal("Режим остановлен после сброса автомобиля", true, "notify_vehicleReset")
  end
end

local function onVehicleResetted(vehicleId)
  handleVehicleReset(vehicleId)
end

function M.onTelemetryVehicleReset(vehicleId)
  handleVehicleReset(vehicleId)
end

local function onExtensionLoaded()
  loadUserSettings()
  loadDriverProfile()
  loadUserProgress()
  notifyHud()
end

local function onClientEndMission()
  hideNativeMinimap()
  stopCandidateCache = nil
  stopCandidateLevel = nil
  recentTaxiStopPositions = {}
  phoneNotification = nil
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
  restoreNavigationVisualSettings()
end

local function onExtensionUnloaded()
  hideNativeMinimap()
  recentTaxiStopPositions = {}
  if state.active then
    stopModeInternal(nil, false)
  end
  writeUserProgress()
  restoreNavigationVisualSettings()
end

local function onSerialize()
  return {
    balance = state.balance,
    rating = state.rating,
    ratingTotal = state.ratingTotal,
    ratingCount = state.ratingCount,
    completedRides = state.completedRides,
    difficulty = state.difficulty
  }
end

local function onDeserialized(data)
  data = data or {}
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
  trip = nil
  offers = {}
  clearNextOffer()
  offerTimer = 0
  phoneNotification = nil
  stopCandidateCache = nil
  stopCandidateLevel = nil
  recentTaxiStopPositions = {}
  notifyHud()
end

M.onUpdate = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleResetted = onVehicleResetted
M.onClientEndMission = onClientEndMission
M.onExtensionUnloaded = onExtensionUnloaded
M.onExtensionLoaded = onExtensionLoaded
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized

return M
