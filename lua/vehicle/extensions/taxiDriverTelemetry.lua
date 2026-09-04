local M = {}

local enabled = false
local forcedStop = false
local forcedStopGearboxBehavior = nil
local updateTimer = 0
local updateInterval = 0.2
local lastDamageSnapshot = nil
local function setEnabled(value)
  enabled = value == true
  updateTimer = 0
end

local function releaseForcedStopInputs()
  input.event("throttle", 0, FILTER_DIRECT)
  input.event("brake", 0, FILTER_DIRECT)
  input.event("parkingbrake", 0, FILTER_DIRECT)
end

local function gearboxBehavior(main)
  local current = main and type(main.getState) == "function" and main.getState() or nil
  return (current and current.grb_bhv) or (main and main.gearboxBehavior)
end

local function holdForcedStopGearbox()
  local main = controller and controller.mainController or nil
  if gearboxBehavior(main) == "arcade" and type(main.setGearboxMode) == "function" then
    main.setGearboxMode("realistic")
  end
end

local function setForcedStop(value)
  value = value == true
  if forcedStop == value then return end
  forcedStop = value
  local main = controller and controller.mainController or nil
  if forcedStop then
    local observer = extensions and extensions.taxiDriverStockAiObserver
    forcedStopGearboxBehavior = observer and type(observer.getDriverGearboxBehavior) == "function" and
      observer.getDriverGearboxBehavior() or gearboxBehavior(main)
    -- Arcade interprets a held brake at zero speed as reverse throttle.
    -- Own Realistic only for this forced stop and retain the live Q-key mode.
    holdForcedStopGearbox()
  else
    releaseForcedStopInputs()
    if forcedStopGearboxBehavior and main and type(main.setGearboxMode) == "function" then
      main.setGearboxMode(forcedStopGearboxBehavior)
    end
    forcedStopGearboxBehavior = nil
  end
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

local function inputValue(name)
  local state = input.state and input.state[name]
  return tonumber(state and state.val) or 0
end

local function getAutopilotControllerState()
  local extension = extensions and
    (extensions.taxiDriverStockAiObserver or extensions.taxiDriverAutopilotRecovery) or nil
  if not extension or type(extension.getDebugState) ~= "function" then return nil end
  local ok, result = pcall(extension.getDebugState)
  return ok and type(result) == "table" and result or nil
end

local function updateGFX(dt)
  if forcedStop then
    holdForcedStopGearbox()
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
  local mainController = controller and controller.mainController or nil
  local rpm = tonumber(electrics.values.rpm) or tonumber(electrics.values.engineRPM) or 0
  local ignitionLevel = tonumber(electrics.values.ignitionLevel) or 0
  local data = {
    damage = beamstate.damage or 0,
    longitudinalG = longitudinalG,
    lateralG = lateralG,
    wheelSpeed = tonumber(electrics.values.wheelspeed) or 0,
    gearIndex = tonumber(electrics.values.gearIndex),
    gear = tostring(electrics.values.gear or electrics.values.gearName or ""),
    gearboxBehavior = mainController and tostring(mainController.gearboxBehavior or "") or "",
    engineRpm = rpm,
    ignitionLevel = ignitionLevel,
    engineRunning = electrics.values.engineRunning == 1 or rpm > 100 or ignitionLevel >= 2,
    throttle = inputValue("throttle"),
    brake = inputValue("brake"),
    clutch = inputValue("clutch"),
    parkingBrake = inputValue("parkingbrake"),
    horn = (tonumber(electrics.values.horn) or 0) > 0,
    leftSignal = electrics.values.signal_left_input == 1 or electrics.values.signal_L == 1,
    rightSignal = electrics.values.signal_right_input == 1 or electrics.values.signal_R == 1,
    autopilotController = getAutopilotControllerState()
  }
  if lastDamageSnapshot == nil or math.abs(data.damage - lastDamageSnapshot) > 0.01 then
    if type(beamstate.getPartDamageData) == "function" then
      local ok, partDamage = pcall(beamstate.getPartDamageData)
      if ok and type(partDamage) == "table" then data.partDamage = partDamage end
    end
    lastDamageSnapshot = data.damage
  end

  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onTelemetry(%d, %s) end",
    obj:getID(),
    serialize(data)
  ))
end

local function onReset()
  updateTimer = 0
  lastDamageSnapshot = nil
  enabled = false
  if forcedStop then releaseForcedStopInputs() end
  forcedStop = false
  forcedStopGearboxBehavior = nil
end

M.setEnabled = setEnabled
M.setForcedStop = setForcedStop
M.updateGFX = updateGFX
M.onReset = onReset

return M
