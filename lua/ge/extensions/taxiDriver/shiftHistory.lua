local M = {}
local vehicleScanGuard = require("taxiDriver/vehicleScanGuard")
local vehicleBridgeGuard = require("taxiDriver/vehicleBridgeGuard")

local schemaVersion = 1
local settingsDirectoryPath = "/settings/TaxiDriver"
local filePath = settingsDirectoryPath .. "/shiftshistory.json"
local maximumEntries = 50
local snapshotInterval = 60
local modVersion = "unknown"
local history = nil
local activeId = nil
local snapshotTimer = 0
local validationTimer = 2
local validationComplete = false
local restoringId = nil
local restorePending = nil

local function trimText(value, maximumLength)
  local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if maximumLength and #text > maximumLength then return text:sub(1, maximumLength) end
  return text
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function money(value)
  return math.floor(math.max(0, tonumber(value) or 0) * 100 + 0.5) / 100
end

local function sanitizePreview(value)
  local preview = trimText(value, 320)
  if preview == "" or preview:sub(1, 1) ~= "/" or preview:find("..", 1, true) or
    not preview:lower():match("%.jpe?g$") and not preview:lower():match("%.png$") then
    return ""
  end
  return preview
end

local function sanitizeEnergy(source)
  source = type(source) == "table" and source or {}
  local result = {
    energyType = trimText(source.energyType, 64),
    percent = clamp(source.percent, 0, 100)
  }
  if tonumber(source.fuelPercent) then
    result.fuelPercent = clamp(source.fuelPercent, 0, 100)
  end
  if tonumber(source.electricPercent) then
    result.electricPercent = clamp(source.electricPercent, 0, 100)
  end
  return result
end

local function sanitizeSummary(source)
  source = type(source) == "table" and source or {}
  return {
    rides = math.max(0, math.floor(tonumber(source.rides) or 0)),
    aiRides = math.max(0, math.floor(tonumber(source.aiRides) or 0)),
    grossIncome = money(source.grossIncome),
    fuelCost = money(source.fuelCost),
    penaltyLoss = money(source.penaltyLoss),
    netIncome = money(source.netIncome),
    averageRating = clamp(source.averageRating, 0, 5)
  }
end

local function sanitizeVehicle(source)
  source = type(source) == "table" and source or {}
  local modelKey = trimText(source.modelKey, 120)
  local configKey = trimText(source.configKey, 160)
  local configPath = trimText(source.configPath, 320)
  if configPath == "" and modelKey ~= "" and configKey ~= "" then
    configPath = "/vehicles/" .. modelKey .. "/" .. configKey .. ".pc"
  end
  local name = trimText(source.name, 240)
  if name == "" then name = modelKey .. (configKey ~= "" and " " .. configKey or "") end
  return {
    modelKey = modelKey,
    configKey = configKey,
    configPath = configPath,
    name = name,
    preview = sanitizePreview(source.preview)
  }
end

local function sanitizeEntry(source)
  if type(source) ~= "table" then return nil end
  local id = math.max(1, math.floor(tonumber(source.id) or 0))
  local vehicle = sanitizeVehicle(source.vehicle)
  if vehicle.modelKey == "" or vehicle.configKey == "" then return nil end
  return {
    id = id,
    startedAt = math.max(0, math.floor(tonumber(source.startedAt) or 0)),
    endedAt = math.max(0, math.floor(tonumber(source.endedAt) or 0)),
    lastSavedAt = math.max(0, math.floor(tonumber(source.lastSavedAt) or 0)),
    vehicle = vehicle,
    energy = sanitizeEnergy(source.energy),
    summary = sanitizeSummary(source.summary)
  }
end

local function createDefaultHistory()
  return {schemaVersion = schemaVersion, modVersion = modVersion, nextId = 1, shifts = {}}
end

local function sanitizeHistory(source, requireSchema)
  local result = createDefaultHistory()
  if type(source) ~= "table" then return result end
  if requireSchema and tonumber(source.schemaVersion) ~= schemaVersion then return result end
  local seen = {}
  for _, value in ipairs(type(source.shifts) == "table" and source.shifts or {}) do
    local entry = sanitizeEntry(value)
    if entry and entry.summary.rides > 0 and not seen[entry.id] then
      seen[entry.id] = true
      result.shifts[#result.shifts + 1] = entry
      result.nextId = math.max(result.nextId, entry.id + 1)
      if #result.shifts >= maximumEntries then break end
    end
  end
  result.nextId = math.max(result.nextId, math.floor(tonumber(source.nextId) or 1))
  return result
end

local function ensureDirectory()
  if not FS:directoryExists(settingsDirectoryPath) then FS:directoryCreate(settingsDirectoryPath) end
end

local function writeHistory()
  if not history then history = createDefaultHistory() end
  history.schemaVersion = schemaVersion
  history.modVersion = modVersion
  local ok, errorMessage = pcall(function()
    ensureDirectory()
    local persisted = createDefaultHistory()
    persisted.nextId = history.nextId
    for _, entry in ipairs(history.shifts) do
      if entry.summary.rides > 0 then persisted.shifts[#persisted.shifts + 1] = entry end
    end
    jsonWriteFile(filePath, persisted, true)
  end)
  if not ok then
    log("E", "taxiDriver.shiftHistory", "Unable to write shift history: " .. tostring(errorMessage))
  end
  return ok
end

local function findEntry(id)
  id = math.floor(tonumber(id) or -1)
  for _, entry in ipairs(history and history.shifts or {}) do
    if entry.id == id then return entry end
  end
  return nil
end

local function applySnapshot(entry, vehicle, energy, summary)
  if not entry then return false end
  if type(vehicle) == "table" then entry.vehicle = sanitizeVehicle(vehicle) end
  if type(energy) == "table" then entry.energy = sanitizeEnergy(energy) end
  if type(summary) == "table" then entry.summary = sanitizeSummary(summary) end
  entry.lastSavedAt = os.time()
  return true
end

local function dashboardEnergy(source)
  source = type(source) == "table" and source or {}
  local result = {
    energyType = tostring(source.energyType or ""),
    percent = clamp(source.percent, 0, 100)
  }
  if result.energyType == "electricEnergy" then result.electricPercent = result.percent
  elseif result.energyType ~= "" then result.fuelPercent = result.percent end
  return result
end

local function isVehicleAvailable(vehicleData)
  if type(vehicleData) ~= "table" or not core_vehicles then return false end
  local modelKey = tostring(vehicleData.modelKey or "")
  local configKey = tostring(vehicleData.configKey or "")
  if modelKey == "" or configKey == "" then return false end
  local ok, model = pcall(core_vehicles.getModel, modelKey)
  if not ok or type(model) ~= "table" or type(model.model) ~= "table" then return false end
  if type(model.configs) == "table" and type(model.configs[configKey]) == "table" then return true end
  local configPath = tostring(vehicleData.configPath or "")
  return configPath ~= "" and FS:fileExists(configPath)
end

local function isVehicleRegistryReady()
  if not core_vehicles or type(core_vehicles.getModelList) ~= "function" then return false end
  local ok, result = pcall(core_vehicles.getModelList, false)
  return ok and type(result) == "table" and type(result.models) == "table" and
    next(result.models) ~= nil
end

local function captureVehicleEnergy(vehicle, callback)
  if not vehicle or type(callback) ~= "function" then return false end
  return vehicleBridgeGuard.request(vehicle, "energyStorage", function(data)
    local tanks = type(data) == "table" and data[1] or nil
    local fuelEnergy, fuelCapacity = 0, 0
    local electricEnergy, electricCapacity = 0, 0
    local primaryType, primaryRatio, primaryCapacity = "", 0, 0
    for _, tank in ipairs(type(tanks) == "table" and tanks or {}) do
      local energyType = tostring(tank.energyType or "")
      local currentEnergy = math.max(0, tonumber(tank.currentEnergy) or 0)
      local maxEnergy = math.max(0, tonumber(tank.maxEnergy) or 0)
      local tracked = energyType == "electricEnergy" or energyType == "gasoline" or
        energyType == "diesel" or energyType == "kerosine" or energyType == "kerosene"
      if tracked and maxEnergy > 0 then
        if energyType == "electricEnergy" then
          electricEnergy = electricEnergy + currentEnergy
          electricCapacity = electricCapacity + maxEnergy
        elseif energyType == "gasoline" or energyType == "diesel" or
          energyType == "kerosine" or energyType == "kerosene" then
          fuelEnergy = fuelEnergy + currentEnergy
          fuelCapacity = fuelCapacity + maxEnergy
        end
        if maxEnergy > primaryCapacity then
          primaryType = energyType
          primaryRatio = currentEnergy / maxEnergy
          primaryCapacity = maxEnergy
        end
      end
    end
    local snapshot = {energyType = primaryType, percent = clamp(primaryRatio * 100, 0, 100)}
    if fuelCapacity > 0 then snapshot.fuelPercent = clamp(fuelEnergy / fuelCapacity * 100, 0, 100) end
    if electricCapacity > 0 then
      snapshot.electricPercent = clamp(electricEnergy / electricCapacity * 100, 0, 100)
    end
    callback(snapshot)
  end)
end

local function applyVehicleEnergy(vehicle, snapshot, callback)
  if not vehicle then return false end
  snapshot = type(snapshot) == "table" and snapshot or {}
  local fuelPercent = tonumber(snapshot.fuelPercent)
  local electricPercent = tonumber(snapshot.electricPercent)
  if not fuelPercent and tostring(snapshot.energyType or "") == "electricEnergy" then
    electricPercent = tonumber(snapshot.percent)
  elseif not fuelPercent then
    fuelPercent = tonumber(snapshot.percent)
  end
  return vehicleBridgeGuard.request(vehicle, "energyStorage", function(data, currentVehicle)
    local tanks = type(data) == "table" and data[1] or nil
    local changedCount = 0
    for _, tank in ipairs(type(tanks) == "table" and tanks or {}) do
      local energyType = tostring(tank.energyType or "")
      local percent = energyType == "electricEnergy" and electricPercent or fuelPercent
      local supported = energyType == "electricEnergy" or energyType == "gasoline" or
        energyType == "diesel" or energyType == "kerosine" or energyType == "kerosene"
      local maxEnergy = math.max(0, tonumber(tank.maxEnergy) or 0)
      if supported and percent and maxEnergy > 0 then
        if vehicleBridgeGuard.execute(currentVehicle, "setEnergyStorageEnergy", tank.name,
          maxEnergy * clamp(percent, 0, 100) / 100) then
          changedCount = changedCount + 1
        end
      end
    end
    if type(callback) == "function" then callback(changedCount > 0, changedCount) end
  end, function()
    if type(callback) == "function" then callback(false, 0) end
  end)
end

function M.load(version)
  modVersion = tostring(version or modVersion)
  local source = nil
  if FS:fileExists(filePath) then
    local ok, value = pcall(jsonReadFile, filePath)
    if ok then source = value end
  end
  history = sanitizeHistory(source, true)
  activeId = nil
  restoringId = nil
  restorePending = nil
  snapshotTimer = 0
  validationTimer = 2
  validationComplete = false
  writeHistory()
end

function M.begin(vehicle, energy, summary)
  if not history then history = createDefaultHistory() end
  local sanitizedVehicle = sanitizeVehicle(vehicle)
  if sanitizedVehicle.modelKey == "" or sanitizedVehicle.configKey == "" then return nil end
  local id = history.nextId
  history.nextId = id + 1
  local now = os.time()
  local entry = {
    id = id,
    startedAt = now,
    endedAt = 0,
    lastSavedAt = now,
    vehicle = sanitizedVehicle,
    energy = sanitizeEnergy(energy),
    summary = sanitizeSummary(summary)
  }
  table.insert(history.shifts, 1, entry)
  while #history.shifts > maximumEntries do table.remove(history.shifts) end
  activeId = id
  snapshotTimer = 0
  writeHistory()
  return id
end

function M.update(dtReal, summary)
  local entry = findEntry(activeId)
  if not entry then return false end
  local previousRides = entry.summary.rides
  if type(summary) == "table" then entry.summary = sanitizeSummary(summary) end
  if previousRides == 0 and entry.summary.rides > 0 then writeHistory() end
  snapshotTimer = snapshotTimer + math.max(0, tonumber(dtReal) or 0)
  if snapshotTimer < snapshotInterval then return false end
  snapshotTimer = 0
  return true
end

function M.saveSnapshot(id, vehicle, energy, summary)
  local entry = findEntry(id)
  if not applySnapshot(entry, vehicle, energy, summary) then return false end
  return writeHistory()
end

function M.captureSnapshot(id, vehicle, vehicleData, fallbackEnergy, summary)
  id = tonumber(id) or activeId
  if not id or not vehicle or not vehicleData then return false end
  M.saveSnapshot(id, vehicleData, fallbackEnergy, summary)
  return captureVehicleEnergy(vehicle, function(energy)
    M.saveSnapshot(id, vehicleData, energy, summary)
  end)
end

function M.captureActive(vehicle, vehicleData, liveEnergy, summary)
  return M.captureSnapshot(activeId, vehicle, vehicleData, dashboardEnergy(liveEnergy), summary)
end

function M.finishActive(vehicle, vehicleData, liveEnergy, summary)
  local id = activeId
  if not id then return nil end
  M.captureSnapshot(id, vehicle, vehicleData, dashboardEnergy(liveEnergy), summary)
  return M.finish(vehicleData, dashboardEnergy(liveEnergy), summary)
end

function M.finish(vehicle, energy, summary)
  local entry = findEntry(activeId)
  if not entry then return nil end
  applySnapshot(entry, vehicle, energy, summary)
  entry.endedAt = os.time()
  if entry.summary.rides <= 0 then
    for index, candidate in ipairs(history.shifts) do
      if candidate.id == entry.id then table.remove(history.shifts, index); break end
    end
  end
  activeId = nil
  snapshotTimer = 0
  writeHistory()
  return entry.id
end

function M.get(id)
  local entry = findEntry(id)
  return entry and sanitizeEntry(entry) or nil
end

function M.getActiveId()
  return activeId
end

function M.setRestoring(id)
  restoringId = tonumber(id) and math.floor(tonumber(id)) or nil
  if not restoringId then restorePending = nil end
end

function M.updateValidation(dtReal)
  if validationComplete then return false end
  validationTimer = validationTimer - math.max(0, tonumber(dtReal) or 0)
  return validationTimer <= 0
end

function M.pruneUnavailable()
  if validationComplete then return false end
  if not isVehicleRegistryReady() then
    validationTimer = 2
    return false
  end
  local changed = false
  local availability = {}
  for index = #(history and history.shifts or {}), 1, -1 do
    local entry = history.shifts[index]
    local key = entry.vehicle.modelKey .. "|" .. entry.vehicle.configKey
    local available = availability[key]
    local ok = true
    if available == nil then
      ok, available = pcall(isVehicleAvailable, entry.vehicle)
      if ok then availability[key] = available end
    end
    if ok and available == false then
      if activeId == entry.id then activeId = nil end
      if restoringId == entry.id then restoringId = nil end
      table.remove(history.shifts, index)
      changed = true
    end
  end
  validationComplete = true
  if changed then writeHistory() end
  return changed
end


function M.restore(id, onComplete)
  if restorePending then return false end
  local entry = findEntry(id)
  if not entry then return false end
  if not isVehicleRegistryReady() then
    if type(onComplete) == "function" then onComplete("failed") end
    return false
  end
  if not isVehicleAvailable(entry.vehicle) then
    M.remove(entry.id)
    if type(onComplete) == "function" then onComplete("unavailable") end
    return false
  end
  restoringId = entry.id
  restorePending = {
    entry = sanitizeEntry(entry), vehicleId = nil, elapsed = 0, stableElapsed = 0,
    applying = false, onComplete = onComplete
  }
  local options = {config = entry.vehicle.configPath ~= "" and
    entry.vehicle.configPath or entry.vehicle.configKey}
  local ok, spawned = pcall(function()
    if be and be:getPlayerVehicle(0) then return core_vehicles.replaceVehicle(entry.vehicle.modelKey, options) end
    return core_vehicles.spawnNewVehicle(entry.vehicle.modelKey, options)
  end)
  if not ok or not spawned then
    restorePending = nil
    restoringId = nil
    if type(onComplete) == "function" then onComplete("failed") end
    return false
  end
  restorePending.vehicleId = spawned:getID()
  return true
end

function M.updateRestore(dtReal)
  local pending = restorePending
  if not pending then return false end
  pending.elapsed = pending.elapsed + math.max(0, tonumber(dtReal) or 0)
  if pending.elapsed > 15 then
    restorePending = nil
    restoringId = nil
    if type(pending.onComplete) == "function" then pending.onComplete("failed") end
    return false
  end
  if pending.applying or vehicleScanGuard.isSuspended() then return false end
  local vehicle = pending.vehicleId and getObjectByID(pending.vehicleId) or
    (be and be:getPlayerVehicle(0) or nil)
  if not vehicle or tonumber(be:getPlayerVehicleID(0)) ~= tonumber(vehicle:getID()) then return false end
  pending.stableElapsed = pending.stableElapsed + math.max(0, tonumber(dtReal) or 0)
  if pending.stableElapsed < 0.5 then return false end
  pending.applying = true
  return applyVehicleEnergy(vehicle, pending.entry.energy, function()
    if restorePending ~= pending then return end
    restorePending = nil
    restoringId = nil
    if type(pending.onComplete) == "function" then pending.onComplete("restored", pending.entry.energy) end
  end)
end

function M.remove(id)
  id = math.floor(tonumber(id) or -1)
  for index, entry in ipairs(history and history.shifts or {}) do
    if entry.id == id then
      if activeId == id then activeId = nil end
      if restoringId == id then restoringId = nil end
      table.remove(history.shifts, index)
      writeHistory()
      return true
    end
  end
  return false
end

function M.buildHud(includeItems)
  local items = {}
  for _, entry in ipairs(includeItems ~= false and history and history.shifts or {}) do
    if entry.summary.rides > 0 then items[#items + 1] = {
      id = entry.id,
      startedAt = entry.startedAt,
      endedAt = entry.endedAt,
      lastSavedAt = entry.lastSavedAt,
      vehicleName = entry.vehicle.name,
      preview = entry.vehicle.preview,
      energyType = entry.energy.energyType,
      energyPercent = entry.energy.percent,
      rides = entry.summary.rides,
      aiRides = entry.summary.aiRides,
      netIncome = entry.summary.netIncome,
      averageRating = entry.summary.averageRating
    } end
  end
  return {items = items, restoring = restoringId ~= nil, restoringId = restoringId or 0}
end

function M.write()
  return writeHistory()
end

M.sanitizeHistory = sanitizeHistory
M.dashboardEnergy = dashboardEnergy
return M
