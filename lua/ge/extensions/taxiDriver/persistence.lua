local M = {}
local shiftTracker = require("taxiDriver/shiftTracker")

local settingsDirectoryPath = "/settings/TaxiDriver"
local settingsFilePath = settingsDirectoryPath .. "/settings.json"
local difficultyFilePath = settingsDirectoryPath .. "/difficulty.json"
local profileFilePath = settingsDirectoryPath .. "/profile.json"
local progressFilePath = settingsDirectoryPath .. "/progress.json"
local schemaVersion = 1

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function roundMoney(value)
  return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

local function trimText(value)
  local text = tostring(value or "")
  return text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
end

local function ensureDirectory()
  if not FS:directoryExists(settingsDirectoryPath) then
    FS:directoryCreate(settingsDirectoryPath)
  end
end

local function readJson(path)
  if not FS:fileExists(path) then return nil, false end
  local ok, value = pcall(jsonReadFile, path)
  return ok and value or nil, true
end

local function writeJson(path, value, label)
  local ok, errorMessage = pcall(function()
    ensureDirectory()
    jsonWriteFile(path, value, true)
  end)
  if not ok then
    log("E", "taxiDriver.persistence", "Unable to write " .. label .. ": " .. tostring(errorMessage))
  end
  return ok
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

function M.new(options)
  options = options or {}
  local store = {}
  local version = tostring(options.modVersion or "unknown")
  local taxiConfig = options.taxiConfig
  local supportedLanguages = options.supportedLanguages or {}
  local difficultyPresets = options.difficultyPresets or {}
  local driverAvatarSet = options.driverAvatarSet or {}
  local validReviewEmoji = {
    ["🤩"] = true, ["😍"] = true, ["😄"] = true, ["😊"] = true,
    ["🙂"] = true, ["😐"] = true, ["😕"] = true, ["😠"] = true,
    ["😡"] = true, ["🤬"] = true
  }

  function store:createDefaultSettings()
    return {
      schemaVersion = schemaVersion,
      modVersion = version,
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
      unlimitedRouteDistance = false,
      lanEnabled = false,
      externalMapEnabled = true,
      externalTerrainEnabled = true,
      externalMapQuality = "balanced",
      silentMode = false,
      showRouteGuidance = true,
      realisticMode = false,
      randomEventsEnabled = false,
      aiDriver = {
        obeyTrafficRules = true,
        allowOvertaking = true,
        allowOncomingRecovery = true,
        aggressionPercent = 30,
        followingTimeGap = 2.2,
        brakingDeceleration = 2.8,
        stuckDelaySeconds = 15
      },
      godMode = false,
      debugLogging = true
    }
  end

  function store:sanitizeSettings(source, requireSchema)
    local result = self:createDefaultSettings()
    if type(source) ~= "table" then return result, false end
    if requireSchema and tonumber(source.schemaVersion) ~= schemaVersion then
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
      if legacyFontBoost then uiScalePercent = 100 + (clamp(legacyFontBoost, 0, 5) - 2) * 10 end
    end
    if uiScalePercent then
      result.uiScalePercent = math.floor(clamp(uiScalePercent, 80, 180) / 10 + 0.5) * 10
    end
    local appVolume = tonumber(source.appVolume)
    if appVolume then result.appVolume = clamp(appVolume, 0, 1) end
    if source.unitSystem == "imperial" then result.unitSystem = "imperial" end
    if source.timeFormat == "24h" then result.timeFormat = "24h" end

    local penaltySource = type(source.penaltyToggles) == "table" and source.penaltyToggles or {}
    for _, key in ipairs({"speeding", "collision", "aggression", "pickupDelay", "fuelStop", "rushBonus", "cargoDamage"}) do
      result.penaltyToggles[key] = penaltySource[key] ~= false
    end
    local soundSource = type(source.soundToggles) == "table" and source.soundToggles or {}
    for _, key in ipairs({"click", "newRide", "offline", "online", "violation", "message", "overspeed"}) do
      result.soundToggles[key] = soundSource[key] ~= false
    end
    result.dynamicZoomIntensity = clamp(tonumber(source.dynamicZoomIntensity) or result.dynamicZoomIntensity, 0, 200)
    result.overspeedWarningKmh = clamp(tonumber(source.overspeedWarningKmh) or result.overspeedWarningKmh, 0, 30)
    result.economyMultiplier = clamp(tonumber(source.economyMultiplier) or result.economyMultiplier, 0.25, 5)
    result.deliveryOrderSharePercent = clamp(tonumber(source.deliveryOrderSharePercent) or result.deliveryOrderSharePercent, 0, 100)
    result.unlimitedRouteDistance = source.unlimitedRouteDistance == true
    result.lanEnabled = false
    result.externalMapEnabled = source.externalMapEnabled ~= false
    result.externalTerrainEnabled = source.externalTerrainEnabled ~= false
    local externalMapQuality = tostring(source.externalMapQuality or "balanced")
    if externalMapQuality ~= "eco" and externalMapQuality ~= "smooth" then
      externalMapQuality = "balanced"
    end
    result.externalMapQuality = externalMapQuality
    result.silentMode = source.silentMode == true
    result.showRouteGuidance = source.showRouteGuidance ~= false
    result.realisticMode = source.realisticMode == true
    result.randomEventsEnabled = source.randomEventsEnabled == true
    local aiSource = type(source.aiDriver) == "table" and source.aiDriver or {}
    result.aiDriver.obeyTrafficRules = aiSource.obeyTrafficRules ~= false
    result.aiDriver.allowOvertaking = aiSource.allowOvertaking ~= false
    result.aiDriver.allowOncomingRecovery = aiSource.allowOncomingRecovery ~= false
    result.aiDriver.aggressionPercent = clamp(tonumber(aiSource.aggressionPercent) or 30, 10, 80)
    result.aiDriver.followingTimeGap = clamp(tonumber(aiSource.followingTimeGap) or 2.2, 1.2, 3.5)
    result.aiDriver.brakingDeceleration = clamp(tonumber(aiSource.brakingDeceleration) or 2.8, 1.5, 4.5)
    result.aiDriver.stuckDelaySeconds = clamp(tonumber(aiSource.stuckDelaySeconds) or 15, 8, 30)
    result.godMode = source.godMode == true
    result.debugLogging = source.debugLogging ~= false
    return result, true
  end

  function store:writeDifficulty(settings)
    return writeJson(difficultyFilePath, {
      schemaVersion = schemaVersion,
      modVersion = version,
      customDifficulty = taxiConfig.sanitizeCustomDifficulty(settings.customDifficulty),
      penaltyToggles = {
        speeding = settings.penaltyToggles.speeding ~= false,
        collision = settings.penaltyToggles.collision ~= false,
        aggression = settings.penaltyToggles.aggression ~= false,
        pickupDelay = settings.penaltyToggles.pickupDelay ~= false,
        fuelStop = settings.penaltyToggles.fuelStop ~= false,
        rushBonus = settings.penaltyToggles.rushBonus ~= false,
        cargoDamage = settings.penaltyToggles.cargoDamage ~= false
      }
    }, "difficulty settings")
  end

  function store:writeSettings(settings)
    local data = {}
    for key, value in pairs(settings) do
      if key ~= "customDifficulty" and key ~= "penaltyToggles" and key ~= "lanEnabled" then
        data[key] = value
      end
    end
    local settingsOk = writeJson(settingsFilePath, data, "settings")
    local difficultyOk = self:writeDifficulty(settings)
    return settingsOk and difficultyOk
  end

  function store:loadSettings()
    local source, fileExists = readJson(settingsFilePath)
    local settings = self:sanitizeSettings(source, true)
    local difficultySource, difficultyExists = readJson(difficultyFilePath)
    if difficultyExists then
      if type(difficultySource) == "table" and tonumber(difficultySource.schemaVersion) == schemaVersion then
        settings.customDifficulty = taxiConfig.sanitizeCustomDifficulty(difficultySource.customDifficulty)
        local penalties = type(difficultySource.penaltyToggles) == "table" and difficultySource.penaltyToggles or {}
        for _, key in ipairs({"speeding", "collision", "aggression", "pickupDelay", "fuelStop", "rushBonus", "cargoDamage"}) do
          settings.penaltyToggles[key] = penalties[key] ~= false
        end
      else
        local defaults = self:createDefaultSettings()
        settings.customDifficulty = defaults.customDifficulty
        settings.penaltyToggles = defaults.penaltyToggles
      end
    end
    self:writeSettings(settings)
    return settings, not fileExists
  end

  function store:createDefaultProfile()
    return {schemaVersion = schemaVersion, modVersion = version, fullName = "John Doe", birthDate = "", avatar = "🙂"}
  end

  function store:sanitizeProfile(source, requireSchema)
    local result = self:createDefaultProfile()
    if type(source) ~= "table" then return result, false end
    if requireSchema and tonumber(source.schemaVersion) ~= schemaVersion then return result, false end
    local fullName = trimText(source.fullName)
    if fullName ~= "" and #fullName <= 160 then result.fullName = fullName end
    result.birthDate = sanitizeBirthDate(source.birthDate)
    local avatar = tostring(source.avatar or "")
    if driverAvatarSet[avatar] then result.avatar = avatar end
    return result, true
  end

  function store:loadProfile()
    local source = readJson(profileFilePath)
    local profile = self:sanitizeProfile(source, true)
    self:writeProfile(profile)
    return profile
  end

  function store:writeProfile(profile)
    return writeJson(profileFilePath, profile, "driver profile")
  end

  function store:createDefaultProgress()
    local now = os.time()
    return {
      schemaVersion = schemaVersion,
      modVersion = version,
      balance = 0,
      rating = 5,
      ratingTotal = 0,
      ratingCount = 0,
      completedRides = 0,
      aiRideCount = 0,
      sequence = 0,
      lastShift = shiftTracker.sanitize(nil),
      reviews = {},
      ratingHistory = {{index = 0, value = 5, timestamp = now}},
      balanceHistory = {{index = 0, value = 0, timestamp = now}},
      aiRideHistory = {{index = 0, value = 0, timestamp = now}}
    }
  end

  local function sanitizeHistory(source, minimum, maximum)
    local result = {}
    if type(source) ~= "table" then return result end
    for _, item in ipairs(source) do
      if type(item) == "table" then
        local value = tonumber(item.value)
        if value then
          result[#result + 1] = {
            index = math.max(0, math.floor(tonumber(item.index) or 0)),
            value = roundMoney(clamp(value, minimum, maximum)),
            timestamp = math.max(0, math.floor(tonumber(item.timestamp) or 0))
          }
        end
      end
    end
    return result
  end

  function store:sanitizeProgress(source, requireSchema)
    local result = self:createDefaultProgress()
    if type(source) ~= "table" then return result, false end
    if requireSchema and tonumber(source.schemaVersion) ~= schemaVersion then return result, false end
    result.balance = roundMoney(math.max(0, tonumber(source.balance) or 0))
    result.ratingCount = math.max(0, math.floor(tonumber(source.ratingCount) or 0))
    result.completedRides = math.max(0, math.floor(tonumber(source.completedRides) or result.ratingCount))
    result.aiRideCount = math.max(0, math.min(result.completedRides,
      math.floor(tonumber(source.aiRideCount) or 0)))
    result.rating = clamp(tonumber(source.rating) or 5, 0, 5)
    result.ratingTotal = math.max(0, tonumber(source.ratingTotal) or 0)
    if result.ratingCount > 0 then
      if result.ratingTotal <= 0 then result.ratingTotal = result.rating * result.ratingCount end
      result.rating = clamp(result.ratingTotal / result.ratingCount, 0, 5)
    end
    result.sequence = math.max(0, math.floor(tonumber(source.sequence) or result.completedRides))
    result.lastShift = shiftTracker.sanitize(source.lastShift)
    result.reviews = {}
    if type(source.reviews) == "table" then
      for _, review in ipairs(source.reviews) do
        if type(review) == "table" then
          local id = math.max(1, math.floor(tonumber(review.id) or (#result.reviews + 1)))
          local passengerName = trimText(review.passengerName)
          if passengerName == "" or #passengerName > 160 then passengerName = "Passenger" end
          local emoji = tostring(review.emoji or "😐")
          if not validReviewEmoji[emoji] then emoji = "😐" end
          result.reviews[#result.reviews + 1] = {
            id = id,
            passengerName = passengerName,
            emoji = emoji,
            quality = clamp(tonumber(review.quality) or 0, 0, 100),
            fare = roundMoney(math.max(0, tonumber(review.fare) or 0)),
            rating = clamp(tonumber(review.rating) or result.rating, 0, 5),
            orderRating = clamp(tonumber(review.orderRating) or
              (tonumber(review.quality) or 0) / 20, 0, 5),
            usedAutopilot = review.usedAutopilot == true,
            timestamp = math.max(0, math.floor(tonumber(review.timestamp) or 0)),
            outcome = tostring(review.outcome or "completed")
          }
          result.sequence = math.max(result.sequence, id)
        end
      end
    end
    result.ratingHistory = sanitizeHistory(source.ratingHistory, 0, 5)
    result.balanceHistory = sanitizeHistory(source.balanceHistory, 0, 1000000000)
    result.aiRideHistory = sanitizeHistory(source.aiRideHistory, 0, 1000000000)
    if #result.ratingHistory == 0 then
      result.ratingHistory = {{index = result.sequence, value = roundMoney(result.rating), timestamp = os.time()}}
    end
    if #result.balanceHistory == 0 then
      result.balanceHistory = {{index = result.sequence, value = result.balance, timestamp = os.time()}}
    end
    if #result.aiRideHistory == 0 then
      result.aiRideHistory = {{index = result.sequence, value = result.aiRideCount, timestamp = os.time()}}
    end
    return result, true
  end

  function store:loadProgress()
    local source, fileExists = readJson(progressFilePath)
    return self:sanitizeProgress(source, true), not fileExists
  end

  function store:writeProgress(progress)
    return writeJson(progressFilePath, progress, "driver progress")
  end

  function store:isValidReviewEmoji(value)
    return validReviewEmoji[tostring(value or "")] == true
  end

  function store:trimText(value)
    return trimText(value)
  end

  return store
end

return M
