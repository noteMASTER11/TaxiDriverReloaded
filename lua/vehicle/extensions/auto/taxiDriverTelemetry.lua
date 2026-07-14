local M = {}

local enabled = false
local forcedStop = false
local updateTimer = 0
local updateInterval = 0.2

local function setEnabled(value)
  enabled = value == true
  updateTimer = 0
end

local function releaseForcedStopInputs()
  input.event("throttle", 0, FILTER_DIRECT)
  input.event("brake", 0, FILTER_DIRECT)
  input.event("parkingbrake", 0, FILTER_DIRECT)
end

local function setForcedStop(value)
  forcedStop = value == true
  if not forcedStop then releaseForcedStopInputs() end
end

local function getGForces()
  local gravity = obj:getGravity()
  if gravity >= 0 then
    gravity = math.max(0.1, gravity)
  else
    gravity = math.min(-0.1, gravity)
  end

  return sensors.gy2 / -gravity, sensors.gx2 / -gravity
end

local function updateGFX(dt)
  if forcedStop then
    input.event("throttle", 0, FILTER_DIRECT)
    input.event("brake", 1, FILTER_DIRECT)
    local wheelSpeed = math.abs(tonumber(electrics.values.wheelspeed) or 0)
    input.event("parkingbrake", wheelSpeed < 1 and 1 or 0, FILTER_DIRECT)
  end
  if not enabled then return end

  updateTimer = updateTimer + (dt or 0)
  if updateTimer < updateInterval then return end
  updateTimer = updateTimer - updateInterval

  local longitudinalG, lateralG = getGForces()
  local data = {
    damage = beamstate.damage or 0,
    longitudinalG = longitudinalG,
    lateralG = lateralG
  }

  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onTelemetry(%d, %s) end",
    obj:getID(),
    serialize(data)
  ))
end

local function onReset()
  updateTimer = 0
  forcedStop = false
  releaseForcedStopInputs()
  if not enabled then return end

  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onTelemetryVehicleReset(%d) end",
    obj:getID()
  ))
end

M.setEnabled = setEnabled
M.setForcedStop = setForcedStop
M.updateGFX = updateGFX
M.onReset = onReset

return M
