local autopilotModule = require("taxiDriver/autopilot")

local M = {}
local phases = {
  toPickup = "fleetDriving", toStop = "fleetDriving", toDestination = "fleetDriving",
  toFuelStation = "fleetDriving", boarding = "fleetWaiting", stopWaiting = "fleetWaiting"
}

local function speedKmh(vehicle)
  if not vehicle then return 0 end
  if map and map.objects and map.objects[vehicle:getID()] and map.objects[vehicle:getID()].vel then
    return map.objects[vehicle:getID()].vel:length() * 3.6
  end
  local velocity = vehicle.getVelocity and vehicle:getVelocity() or nil
  return velocity and velocity:length() * 3.6 or 0
end

local function distance(first, second)
  if not first or not second then return math.huge end
  return first:distance(second)
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local service = {}
  local routePath, target = {}, nil
  local autopilot = autopilotModule.new({
    config = options.config,
    phases = phases,
    getSpeedKmh = speedKmh,
    getRoutePath = function() return routePath end
  })

  function service:configure(settings)
    autopilot:configure(settings)
  end

  function service:start(vehicle, nextTarget, nextPath, settings)
    if not vehicle or not nextTarget or not nextTarget.pos then return false end
    if autopilot:isEnabled() then autopilot:disable(vehicle, "fleetRouteChanged") end
    target = nextTarget
    routePath = type(nextPath) == "table" and nextPath or {}
    autopilot:configure(settings)
    return autopilot:enable(vehicle, phases.toDestination, target)
  end

  function service:update(vehicle, dtSim)
    if not target then return false end
    autopilot:update(vehicle, phases.toDestination, target, dtSim)
    return true
  end

  function service:hasArrived(vehicle)
    return vehicle and target and distance(vehicle:getPosition(), target.pos) <= 9 and speedKmh(vehicle) <= 3
  end

  function service:stop(vehicle, reason)
    autopilot:disable(vehicle, reason or "fleetStopped")
    target, routePath = nil, {}
  end

  function service:suspend(vehicle, value)
    autopilot:suspend(vehicle, value)
  end

  function service:onRouteDone(vehicle)
    return autopilot:onRouteDone(vehicle, target)
  end

  function service:onBypassComplete(vehicle, success, reason)
    return autopilot:onBypassComplete(vehicle, success == true, target, reason)
  end

  function service:getHud(vehicle)
    local hud = autopilot:getHud(target ~= nil, vehicle)
    hud.targetDistance = vehicle and target and distance(vehicle:getPosition(), target.pos) or 0
    return hud
  end

  function service:isEnabled() return autopilot:isEnabled() end
  return service
end

return M
