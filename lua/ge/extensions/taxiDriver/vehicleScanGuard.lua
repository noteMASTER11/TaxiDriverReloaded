local M = {}
local logger = require("taxiDriver/logger")

local configurationPrefixes = {"menu.vehicleconfig", "menu.vehicles", "menu.vehiclesnew",
  "garage.vehicles", "garage.mycars", "garage.vehicle"}
local defaultSettleSeconds = 1.5
local configurationOpen = false
local settleRemaining = 0
local generation = 0

local function debugLog(message)
  logger.debug("vehicle", "scan_guard", {message = message})
end

local function isConfigurationState(value)
  local name = tostring(value or "")
  for _, prefix in ipairs(configurationPrefixes) do
    if name == prefix or string.sub(name, 1, #prefix + 1) == prefix .. "." then
      return true
    end
  end
  return false
end

local function invalidate(settleSeconds)
  generation = generation + 1
  settleRemaining = math.max(
    settleRemaining,
    math.max(0, tonumber(settleSeconds) or defaultSettleSeconds)
  )
end

function M.onUiChangedState(to, from)
  local nextOpen = isConfigurationState(to)
  local previousOpen = configurationOpen or isConfigurationState(from)
  if nextOpen == configurationOpen then return false end

  configurationOpen = nextOpen
  if nextOpen then
    -- Entering the vehicle selector/parts screen is the earliest signal. Stop
    -- bridge requests before BeamNG tears down the current vehicle VM.
    invalidate(0)
    debugLog("Vehicle menu opened; vehicle-side work suspended")
  elseif previousOpen then
    -- A short quiet period lets the replacement VM, controllers, and energy
    -- storages finish registering before TaxiDriver asks them for data again.
    invalidate(defaultSettleSeconds)
    debugLog("Vehicle menu closed; waiting for stable vehicle VM")
  end
  return true
end

function M.onVehicleLifecycle(vehicleId, currentVehicleId)
  vehicleId = tonumber(vehicleId)
  currentVehicleId = tonumber(currentVehicleId)
  if not vehicleId or not currentVehicleId or vehicleId ~= currentVehicleId then
    return false
  end
  invalidate(defaultSettleSeconds)
  debugLog(string.format("Vehicle %d lifecycle event; settle timer restarted", vehicleId))
  return true
end

function M.onVehicleSwitched(oldId, newId)
  newId = tonumber(newId)
  if not newId or newId < 0 then return false end
  -- Spawn hooks can precede the change of player focus and therefore fail the
  -- lifecycle id check above. Focus is authoritative, including reused ids.
  invalidate(defaultSettleSeconds)
  debugLog(string.format("Player vehicle changed from %s to %d; waiting for stable VM",
    tostring(oldId), newId))
  return true
end

function M.update(dtReal)
  if configurationOpen or settleRemaining <= 0 then return false end
  local wasSuspended = settleRemaining > 0
  settleRemaining = math.max(0, settleRemaining - math.max(0, tonumber(dtReal) or 0))
  if wasSuspended and settleRemaining <= 0 then
    debugLog("Vehicle VM stable; lazy vehicle-side work resumed")
  end
  return wasSuspended and settleRemaining <= 0
end

function M.isSuspended()
  return configurationOpen or settleRemaining > 0
end

function M.isConfigurationOpen()
  return configurationOpen
end

function M.getGeneration()
  return generation
end

function M.isRequestCurrent(requestGeneration)
  return tonumber(requestGeneration) == generation and not M.isSuspended()
end

function M.reset()
  configurationOpen = false
  settleRemaining = 0
  generation = generation + 1
end

return M
