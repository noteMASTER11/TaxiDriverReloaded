local M = {}

local schemaVersion = 1
local settingsDirectoryPath = "/settings/TaxiDriver"
local filePath = settingsDirectoryPath .. "/vehicles.json"
local modVersion = "unknown"
local history = nil
local tracking = {
  vehicleId = nil,
  key = "",
  entry = nil,
  lastPosition = nil,
  dirtyDistance = 0,
  saveTimer = 0
}

local function trimText(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function sanitizePreview(value)
  local preview = trimText(value)
  if preview == "" or #preview > 320 or preview:sub(1, 1) ~= "/" or
    preview:find("..", 1, true) or not preview:lower():match("%.jpe?g$") and
      not preview:lower():match("%.png$") then
    return ""
  end
  return preview
end

local function roundMoney(value)
  return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

local function getCurrentPlayerVehicle()
  return be and be:getPlayerVehicle(0) or nil
end

local function createDefaultHistory()
  return {
    schemaVersion = schemaVersion,
    modVersion = modVersion,
    vehicles = {}
  }
end

local function sanitizeHistory(source, requireSchema)
  local result = createDefaultHistory()
  if type(source) ~= "table" then return result, false end
  if requireSchema and tonumber(source.schemaVersion) ~= schemaVersion then
    return result, false
  end

  local seen = {}
  for _, item in ipairs(type(source.vehicles) == "table" and source.vehicles or {}) do
    if type(item) == "table" then
      local key = trimText(item.key)
      local name = trimText(item.name)
      if key ~= "" and #key <= 320 and not seen[key] then
        if name == "" or #name > 240 then name = key end
        seen[key] = true
        local completedRides = math.max(0, math.floor(tonumber(item.completedRides) or 0))
        if completedRides > 0 then table.insert(result.vehicles, {
          key = key,
          modelKey = trimText(item.modelKey):sub(1, 120),
          configKey = trimText(item.configKey):sub(1, 160),
          name = name,
          preview = sanitizePreview(item.preview),
          distanceMeters = math.max(0, tonumber(item.distanceMeters) or 0),
          completedRides = completedRides,
          aiRides = math.max(0, math.min(completedRides, math.floor(tonumber(item.aiRides) or 0))),
          income = roundMoney(math.max(0, tonumber(item.income) or 0)),
          passengerRides = math.max(0, math.floor(tonumber(item.passengerRides) or completedRides)),
          deliveryRides = math.max(0, math.floor(tonumber(item.deliveryRides) or 0)),
          ratingTotal = math.max(0, tonumber(item.ratingTotal) or 0),
          ratingCount = math.max(0, math.floor(tonumber(item.ratingCount) or 0)),
          penaltyLoss = roundMoney(math.max(0, tonumber(item.penaltyLoss) or 0)),
          cargoDamageLoss = roundMoney(math.max(0, tonumber(item.cargoDamageLoss) or 0)),
          fuelConsumed = math.max(0, tonumber(item.fuelConsumed) or 0),
          fuelCost = roundMoney(math.max(0, tonumber(item.fuelCost) or 0)),
          rideDistanceMeters = math.max(0, tonumber(item.rideDistanceMeters) or 0),
          lastSeen = math.max(0, math.floor(tonumber(item.lastSeen) or 0))
        }) end
      end
    end
  end
  return result, true
end

local function ensureSettingsDirectory()
  if not FS:directoryExists(settingsDirectoryPath) then
    FS:directoryCreate(settingsDirectoryPath)
  end
end

local function writeHistory()
  if not history then history = createDefaultHistory() end
  history.schemaVersion = schemaVersion
  history.modVersion = modVersion
  local ok, errorMessage = pcall(function()
    ensureSettingsDirectory()
    jsonWriteFile(filePath, history, true)
  end)
  if not ok then
    log("E", "taxiDriver.vehicleHistory", "Unable to write vehicle history: " .. tostring(errorMessage))
  else
    tracking.dirtyDistance = 0
    tracking.saveTimer = 0
  end
  return ok
end

local function getVehicleIdentity(vehicle)
  if not vehicle then return nil end
  local modelKey = trimText(vehicle.jbeam or vehicle.JBeam)
  if modelKey == "" and type(vehicle.getJBeamFilename) == "function" then
    local ok, value = pcall(vehicle.getJBeamFilename, vehicle)
    if ok then modelKey = trimText(value) end
  end
  if modelKey == "" then return nil end

  local configPath = tostring(vehicle.partConfig or "")
  local configKey = configPath:match("([^/]+)%.pc$") or "custom"
  local modelData, configData = nil, nil
  if core_vehicles and type(core_vehicles.getVehicleDetails) == "function" then
    local ok, details = pcall(core_vehicles.getVehicleDetails, vehicle:getID())
    if ok and type(details) == "table" then
      modelData = type(details.model) == "table" and details.model or nil
      configData = type(details.configs) == "table" and details.configs or nil
      if details.current and trimText(details.current.config_key) ~= "" then
        configKey = trimText(details.current.config_key)
      end
    end
  end
  if not modelData and core_vehicles and type(core_vehicles.getModel) == "function" then
    local ok, details = pcall(core_vehicles.getModel, modelKey)
    if ok and type(details) == "table" then
      modelData = type(details.model) == "table" and details.model or nil
      configData = type(details.configs) == "table" and details.configs[configKey] or nil
    end
  end

  local brand = trimText(modelData and modelData.Brand or "")
  local modelName = trimText(modelData and modelData.Name or modelKey)
  local selectorName = trimText(configData and configData.Name or "")
  if selectorName == "" then
    local configuration = trimText(configData and configData.Configuration or "")
    selectorName = modelName
    if configuration ~= "" and configuration ~= modelName then
      selectorName = selectorName .. " " .. configuration
    end
  end
  local name = selectorName ~= "" and selectorName or modelName
  if brand ~= "" and not name:lower():find(brand:lower(), 1, true) then
    name = brand .. " " .. name
  end
  local preview = sanitizePreview(configData and configData.preview or "")
  if preview == "" then preview = sanitizePreview(modelData and modelData.preview or "") end

  return {
    key = modelKey .. "|" .. configKey,
    modelKey = modelKey,
    configKey = configKey,
    configPath = configPath,
    name = name,
    preview = preview
  }
end

local function findEntry(key)
  if not history then history = createDefaultHistory() end
  for _, entry in ipairs(history.vehicles) do
    if entry.key == key then return entry end
  end
  return nil
end

local function ensureEntry(identity)
  if not identity then return nil end
  local entry = findEntry(identity.key)
  if not entry then
    entry = {
      key = identity.key,
      modelKey = identity.modelKey,
      configKey = identity.configKey,
      configPath = identity.configPath,
      name = identity.name,
      preview = identity.preview,
      distanceMeters = 0,
      completedRides = 0,
      aiRides = 0,
      income = 0,
      passengerRides = 0,
      deliveryRides = 0,
      ratingTotal = 0,
      ratingCount = 0,
      penaltyLoss = 0,
      cargoDamageLoss = 0,
      fuelConsumed = 0,
      fuelCost = 0,
      rideDistanceMeters = 0,
      lastSeen = os.time()
    }
  else
    entry.modelKey = identity.modelKey
    entry.configKey = identity.configKey
    entry.configPath = identity.configPath
    entry.name = identity.name
    entry.preview = identity.preview
    entry.lastSeen = os.time()
  end
  return entry
end

local function trackVehicle(vehicle)
  if not vehicle then return false end
  local vehicleId = tonumber(vehicle:getID())
  local identity = getVehicleIdentity(vehicle)
  local entry = ensureEntry(identity)
  if not entry then return false end

  local changed = vehicleId ~= tracking.vehicleId or entry.key ~= tracking.key
  if changed and tracking.dirtyDistance > 0 then writeHistory() end

  tracking.vehicleId = vehicleId
  tracking.key = entry.key
  tracking.entry = entry
  local pos = vehicle:getPosition()
  tracking.lastPosition = pos and vec3(pos.x, pos.y, pos.z) or nil
  if changed then writeHistory() end
  return changed
end

function M.resetTracking()
  tracking.vehicleId = nil
  tracking.key = ""
  tracking.entry = nil
  tracking.lastPosition = nil
  tracking.dirtyDistance = 0
  tracking.saveTimer = 0
end

function M.write()
  return writeHistory()
end

function M.load(version)
  modVersion = tostring(version or modVersion)
  local source = nil
  if FS:fileExists(filePath) then
    local ok, loaded = pcall(jsonReadFile, filePath)
    if ok then source = loaded end
  end
  history = sanitizeHistory(source, true)
  writeHistory()
end

function M.refreshCurrentVehicle()
  local vehicle = getCurrentPlayerVehicle()
  if not vehicle then
    local changed = tracking.vehicleId ~= nil or tracking.entry ~= nil
    if tracking.dirtyDistance > 0 then writeHistory() end
    M.resetTracking()
    return changed
  end

  local vehicleId = tonumber(vehicle:getID())
  -- A live parts/configuration edit keeps the same BeamNG vehicle object.
  -- Treat its id as the lifetime identity so opening the parts selector cannot
  -- trigger expensive core_vehicles lookups, JSON writes, or a new profile row.
  if vehicleId == tracking.vehicleId and tracking.entry then
    return false
  end
  return trackVehicle(vehicle)
end

function M.selectVehicle(vehicleId)
  vehicleId = tonumber(vehicleId)
  if not vehicleId then return M.refreshCurrentVehicle() end
  if vehicleId == tracking.vehicleId and tracking.entry then return false end
  local vehicle = getObjectByID(vehicleId)
  if not vehicle then return false end
  return trackVehicle(vehicle)
end

function M.update(dtReal, dtSim)
  local vehicle = getCurrentPlayerVehicle()
  if not vehicle then
    M.resetTracking()
    return false
  end

  local vehicleId = tonumber(vehicle:getID())
  local identityChanged = vehicleId ~= tracking.vehicleId or tracking.entry == nil
  if identityChanged then
    return trackVehicle(vehicle)
  end

  local position = vehicle:getPosition()
  local previous = tracking.lastPosition
  tracking.lastPosition = position and vec3(position.x, position.y, position.z) or nil
  local entry = tracking.entry
  if not entry or not position or not previous or dtSim <= 0 then return false end

  local distance = position:distance(previous)
  local maximumPlausibleDistance = math.max(3, dtSim * 160 + 1)
  if distance > 0 and distance <= maximumPlausibleDistance then
    entry.distanceMeters = math.max(0, tonumber(entry.distanceMeters) or 0) + distance
    tracking.dirtyDistance = tracking.dirtyDistance + distance
  end
  tracking.saveTimer = tracking.saveTimer + math.max(0, dtReal or 0)
  if tracking.dirtyDistance >= 250 or
    (tracking.dirtyDistance > 0 and tracking.saveTimer >= 15) then
    writeHistory()
  end
  return false
end

function M.getCurrentHud()
  M.refreshCurrentVehicle()
  local entry = tracking.entry
  if not entry then return {available = false} end
  return {
    available = true,
    key = entry.key,
    name = entry.name,
    preview = entry.preview or "",
    distanceMeters = entry.distanceMeters or 0,
      completedRides = entry.completedRides or 0,
      aiRides = entry.aiRides or 0,
      income = roundMoney(entry.income or 0),
      passengerRides = entry.passengerRides or 0,
      deliveryRides = entry.deliveryRides or 0,
      ratingTotal = entry.ratingTotal or 0,
      ratingCount = entry.ratingCount or 0,
      penaltyLoss = roundMoney(entry.penaltyLoss or 0),
      cargoDamageLoss = roundMoney(entry.cargoDamageLoss or 0),
      fuelConsumed = entry.fuelConsumed or 0,
      fuelCost = roundMoney(entry.fuelCost or 0),
      rideDistanceMeters = entry.rideDistanceMeters or 0
  }
end

function M.getCurrentShiftVehicle()
  M.refreshCurrentVehicle()
  local entry = tracking.entry
  if not entry then return nil end
  return {
    key = entry.key,
    modelKey = entry.modelKey,
    configKey = entry.configKey,
    configPath = entry.configPath or
      ("/vehicles/" .. tostring(entry.modelKey) .. "/" .. tostring(entry.configKey) .. ".pc"),
    name = entry.name,
    preview = entry.preview or ""
  }
end

function M.buildHud()
  local result = {}
  for _, entry in ipairs(history and history.vehicles or {}) do
    if (entry.completedRides or 0) > 0 then
    table.insert(result, {
      key = entry.key,
      name = entry.name,
      preview = entry.preview or "",
      distanceMeters = entry.distanceMeters or 0,
      completedRides = entry.completedRides or 0,
      aiRides = entry.aiRides or 0,
      income = roundMoney(entry.income or 0),
      passengerRides = entry.passengerRides or 0,
      deliveryRides = entry.deliveryRides or 0,
      averageIncome = roundMoney((entry.income or 0) / math.max(1, entry.completedRides or 0)),
      averageRating = (entry.ratingTotal or 0) / math.max(1, entry.ratingCount or 0),
      penaltyLoss = roundMoney(entry.penaltyLoss or 0),
      cargoDamageLoss = roundMoney(entry.cargoDamageLoss or 0),
      fuelConsumed = entry.fuelConsumed or 0,
      fuelCost = roundMoney(entry.fuelCost or 0),
      rideDistanceMeters = entry.rideDistanceMeters or 0,
      profitPerKm = roundMoney((entry.income or 0) /
        math.max(0.001, (entry.rideDistanceMeters or 0) / 1000)),
      lastSeen = entry.lastSeen or 0
    })
    end
  end
  table.sort(result, function(a, b)
    if a.lastSeen == b.lastSeen then return a.name < b.name end
    return a.lastSeen > b.lastSeen
  end)
  return result
end

function M.buildFleetGarage()
  M.refreshCurrentVehicle()
  local result, seen = {}, {}
  local function add(entry)
    if not entry or seen[entry.key] or trimText(entry.modelKey) == "" or trimText(entry.configKey) == "" then return end
    seen[entry.key] = true
    result[#result + 1] = {
      key = entry.key, modelKey = entry.modelKey, configKey = entry.configKey,
      name = entry.name, preview = entry.preview or "", completedRides = entry.completedRides or 0,
      lastSeen = entry.lastSeen or os.time()
    }
  end
  add(tracking.entry)
  for _, entry in ipairs(history and history.vehicles or {}) do add(entry) end
  table.sort(result, function(a, b)
    if a.lastSeen == b.lastSeen then return a.name < b.name end
    return a.lastSeen > b.lastSeen
  end)
  return result
end

function M.recordRide(details)
  if type(details) ~= "table" then details = {fare = details} end
  local current = M.getCurrentHud()
  if not current.available then return end
  local entry = findEntry(current.key) or
    (tracking.entry and tracking.entry.key == current.key and tracking.entry or nil)
  if not entry then return end
  if not findEntry(entry.key) then table.insert(history.vehicles, entry) end
  entry.completedRides = math.max(0, math.floor(tonumber(entry.completedRides) or 0)) + 1
  if details.usedAutopilot == true then
    entry.aiRides = math.max(0, math.floor(tonumber(entry.aiRides) or 0)) + 1
  end
  entry.income = roundMoney(math.max(0, tonumber(entry.income) or 0) +
    math.max(0, tonumber(details.fare) or 0))
  if details.isDelivery == true then
    entry.deliveryRides = math.max(0, math.floor(tonumber(entry.deliveryRides) or 0)) + 1
  else
    entry.passengerRides = math.max(0, math.floor(tonumber(entry.passengerRides) or 0)) + 1
  end
  local rating = math.max(0, math.min(5, tonumber(details.rating) or 0))
  entry.ratingTotal = math.max(0, tonumber(entry.ratingTotal) or 0) + rating
  entry.ratingCount = math.max(0, math.floor(tonumber(entry.ratingCount) or 0)) + 1
  entry.penaltyLoss = roundMoney((entry.penaltyLoss or 0) + math.max(0, tonumber(details.penaltyLoss) or 0))
  entry.cargoDamageLoss = roundMoney((entry.cargoDamageLoss or 0) + math.max(0, tonumber(details.cargoDamageLoss) or 0))
  entry.fuelConsumed = math.max(0, tonumber(entry.fuelConsumed) or 0) + math.max(0, tonumber(details.fuelConsumed) or 0)
  entry.fuelCost = roundMoney((entry.fuelCost or 0) + math.max(0, tonumber(details.fuelCost) or 0))
  entry.rideDistanceMeters = math.max(0, tonumber(entry.rideDistanceMeters) or 0) +
    math.max(0, tonumber(details.rideDistanceMeters) or 0)
  entry.lastSeen = os.time()
  writeHistory()
end

function M.setAllRatings(value)
  local rating = math.max(0, math.min(5, tonumber(value) or 0))
  for _, entry in ipairs(history and history.vehicles or {}) do
    local rides = math.max(0, math.floor(tonumber(entry.completedRides) or 0))
    entry.ratingCount = rides
    entry.ratingTotal = rating * rides
  end
  writeHistory()
end

function M.reset()
  history = createDefaultHistory()
  M.resetTracking()
  M.update(0, 0)
  writeHistory()
end

function M.onVehicleReset(vehicleId)
  if tonumber(vehicleId) == tonumber(tracking.vehicleId) then
    if tracking.dirtyDistance > 0 then writeHistory() end
    -- BeamNG respawns the same vehicle object for every parts/tuning change.
    -- Keep its cached identity and history row; only discard the position so
    -- the respawn displacement cannot be counted as odometer distance.
    tracking.lastPosition = nil
    tracking.saveTimer = 0
  end
end

return M
