-- Energy belongs to a stable vehicle identity, not a transient scene-object ID.
-- Keep a cached checkpoint so mission teardown never has to query a dying VM.
local M = {}
local directory = "/settings/TaxiDriver"
local filePath = directory .. "/fuel.json"
local records = {}
local dirty = false
local supported = {gasoline = true, diesel = true, kerosine = true,
  kerosene = true, electricEnergy = true}

local function finite(value)
  value = tonumber(value)
  if value and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function text(value)
  return type(value) == "string" and value or ""
end

local function sanitizeTanks(tanks)
  local result = {}
  for _, tank in ipairs(type(tanks) == "table" and tanks or {}) do
    if type(tank) == "table" then
      local name, energyType = text(tank.name), text(tank.energyType)
      local maximum, current = finite(tank.maxEnergy), finite(tank.currentEnergy)
      if name ~= "" and #name <= 128 and supported[energyType] and maximum and maximum > 0 and current then
        result[#result + 1] = {name = name, energyType = energyType,
          maxEnergy = maximum, currentEnergy = math.max(0, math.min(maximum, current))}
      end
    end
  end
  return result
end

function M.vehicleKey(vehicle)
  if not vehicle then return nil end
  if career_career and career_career.isActive and career_career.isActive() then
    local getProfile = career_saveSystem and
      (career_saveSystem.getCurrentProfile or career_saveSystem.getCurrentSaveSlot)
    local profile = getProfile and getProfile() or nil
    local inventoryId = career_modules_inventory and career_modules_inventory.getInventoryIdFromVehicleId and
      career_modules_inventory.getInventoryIdFromVehicleId(vehicle:getID()) or nil
    if type(profile) ~= "string" or profile == "" or not inventoryId then return nil end
    return "career:" .. #profile .. ":" .. profile .. ":" .. tostring(inventoryId)
  end
  local model = tostring(vehicle.jbeam or vehicle.JBeam or "")
  local config = tostring(vehicle.partConfig or "")
  if model == "" or config == "" or #config > 8192 then return nil end
  return "freeroam:" .. #model .. ":" .. model .. ":" .. config
end

function M.load()
  records, dirty = {}, false
  if not FS:fileExists(filePath) then return end
  local ok, data = pcall(jsonReadFile, filePath)
  if not ok or type(data) ~= "table" or data.schemaVersion ~= 1 then return end
  for key, tanks in pairs(type(data.vehicles) == "table" and data.vehicles or {}) do
    if type(key) == "string" and #key <= 16384 then
      local clean = sanitizeTanks(tanks)
      if #clean > 0 then records[key] = clean end
    end
  end
end

function M.plan(key, tanks, initialFuelPercent, electricInitialLevel)
  local saved = {}
  for _, tank in ipairs(records[key] or {}) do saved[tank.name .. "|" .. tank.energyType] = tank end
  local result = sanitizeTanks(tanks)
  local fuelLevel = math.max(5, math.min(30, finite(initialFuelPercent) or 5)) / 100
  for _, tank in ipairs(result) do
    local previous = saved[tank.name .. "|" .. tank.energyType]
    local level = tank.energyType == "electricEnergy" and
      math.max(0, math.min(1, finite(electricInitialLevel) or 0.3)) or fuelLevel
    tank.currentEnergy = previous and math.min(tank.maxEnergy, previous.currentEnergy) or tank.maxEnergy * level
  end
  return result
end

function M.capture(key, tanks)
  if type(key) ~= "string" or key == "" then return false end
  local clean = sanitizeTanks(tanks)
  if #clean == 0 then return false end
  records[key], dirty = clean, true
  return true
end

function M.applyUpdates(key, updates)
  local tanks = records[key]
  if not tanks then return false end
  for _, update in ipairs(updates or {}) do
    local energy = finite(update.energy)
    for _, tank in ipairs(tanks) do
      if tank.name == update.name and energy then
        tank.currentEnergy = math.max(0, math.min(tank.maxEnergy, energy))
        dirty = true
      end
    end
  end
  return true
end

function M.flush()
  if not dirty then return true end
  local ok, result = pcall(function()
    if not FS:directoryExists(directory) then FS:directoryCreate(directory) end
    return jsonWriteFile(filePath, {schemaVersion = 1, vehicles = records}, true)
  end)
  if ok and result ~= false then dirty = false; return true end
  log("E", "taxiDriver.fuelPersistence", "Unable to save fuel: " .. tostring(result))
  return false
end

return M
