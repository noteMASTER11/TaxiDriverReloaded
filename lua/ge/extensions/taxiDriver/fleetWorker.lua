local M = {}

local defaults = {
  monitorInterval = 0.25,
  arrivalRadius = 12,
  routeDoneRadius = 22,
  arrivalSpeedKmh = 5,
  routeDoneRetryDelay = 1,
  minimumStuckSeconds = 45,
  maximumReplans = 3
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function distance(first, second)
  if not first or not second then return math.huge end
  if type(first.distance) == "function" then return first:distance(second) end
  local dx = (tonumber(first.x) or 0) - (tonumber(second.x) or 0)
  local dy = (tonumber(first.y) or 0) - (tonumber(second.y) or 0)
  local dz = (tonumber(first.z) or 0) - (tonumber(second.z) or 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copyPosition(value)
  if not value then return nil end
  return {x = tonumber(value.x) or 0, y = tonumber(value.y) or 0, z = tonumber(value.z) or 0}
end

local function speedKmh(vehicle)
  if not vehicle then return 0 end
  local id = type(vehicle.getID) == "function" and vehicle:getID() or nil
  local tracked = id and map and type(map.objects) == "table" and map.objects[id] or nil
  local velocity = tracked and tracked.vel or
    (type(vehicle.getVelocity) == "function" and vehicle:getVelocity() or nil)
  if not velocity then return 0 end
  if type(velocity.length) == "function" then return velocity:length() * 3.6 end
  local x, y, z = tonumber(velocity.x) or 0, tonumber(velocity.y) or 0,
    tonumber(velocity.z) or 0
  return math.sqrt(x * x + y * y + z * z) * 3.6
end

local function queue(vehicle, command)
  if not vehicle or type(vehicle.queueLuaCommand) ~= "function" then return false end
  vehicle:queueLuaCommand(command)
  return true
end

local function quote(value)
  return string.format("%q", tostring(value))
end

local function appendUnique(result, value)
  if value == nil or value == "" then return end
  value = tostring(value)
  if result[#result] ~= value then result[#result + 1] = value end
end

local function serializePath(nodes)
  local values = {}
  for _, node in ipairs(nodes) do values[#values + 1] = quote(node) end
  return "{" .. table.concat(values, ",") .. "}"
end

local function logEvent(level, message)
  if type(log) == "function" then
    log(level, "taxiDriver.fleetWorker", "[TaxiDriver] " .. tostring(message))
  end
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local service = {}
  local config = {
    aggression = 0.3,
    obeySpeedLimits = true,
    stuckSeconds = defaults.minimumStuckSeconds,
    maximumReplans = defaults.maximumReplans
  }
  local runtime = {
    enabled = false,
    suspended = false,
    arrived = false,
    failed = false,
    status = "off",
    reason = "",
    target = nil,
    route = {},
    routeIndex = 1,
    monitorTimer = clamp(options.updateOffset or 0, 0, defaults.monitorInterval),
    monitorElapsed = 0,
    lastPosition = nil,
    bestDistance = math.huge,
    targetDistance = math.huge,
    stuckSeconds = 0,
    replanCount = 0,
    routeDonePending = false,
    routeDoneRetryTimer = 0
  }

  local function resetMotion(vehicle)
    local position = vehicle and vehicle:getPosition() or nil
    runtime.lastPosition = copyPosition(position)
    runtime.targetDistance = runtime.target and runtime.target.pos and
      distance(position, runtime.target.pos) or math.huge
    runtime.bestDistance = runtime.targetDistance
    runtime.stuckSeconds = 0
  end

  local function routeProgress(position)
    if not position or #runtime.route < 2 then return nil end
    local firstIndex = math.max(1, math.min(#runtime.route - 1,
      math.floor(tonumber(runtime.routeIndex) or 1) - 1))
    local best = nil
    for index = firstIndex, #runtime.route - 1 do
      local first, second = runtime.route[index], runtime.route[index + 1]
      local a, b = first and first.pos, second and second.pos
      if a and b then
        local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
        local dy = (tonumber(b.y) or 0) - (tonumber(a.y) or 0)
        local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
        local lengthSquared = dx * dx + dy * dy + dz * dz
        if lengthSquared > 0.01 then
          local px = (tonumber(position.x) or 0) - (tonumber(a.x) or 0)
          local py = (tonumber(position.y) or 0) - (tonumber(a.y) or 0)
          local pz = (tonumber(position.z) or 0) - (tonumber(a.z) or 0)
          local along = clamp((px * dx + py * dy + pz * dz) / lengthSquared, 0, 1)
          local projected = {
            x = (tonumber(a.x) or 0) + dx * along,
            y = (tonumber(a.y) or 0) + dy * along,
            z = (tonumber(a.z) or 0) + dz * along
          }
          local crossTrack = distance(position, projected)
          if not best or crossTrack < best.crossTrack - 0.25 or
            (math.abs(crossTrack - best.crossTrack) <= 0.25 and index > best.index) then
            best = {index = index, along = along, crossTrack = crossTrack}
          end
        end
      end
    end
    if best then runtime.routeIndex = math.max(runtime.routeIndex, best.index) end
    return best
  end

  local function remainingOriginalNodes(vehicle)
    local progress = routeProgress(vehicle and vehicle:getPosition() or nil)
    local startIndex = progress and progress.index or runtime.routeIndex
    if progress and progress.along > 0.2 then startIndex = startIndex + 1 end
    startIndex = math.max(1, math.min(#runtime.route, startIndex))
    local nodes = {}
    for index = startIndex, #runtime.route do
      appendUnique(nodes, runtime.route[index] and runtime.route[index].wp)
    end
    if #nodes < 2 and #runtime.route >= 2 then
      nodes = {}
      appendUnique(nodes, runtime.route[#runtime.route - 1].wp)
      appendUnique(nodes, runtime.route[#runtime.route].wp)
    end
    return nodes
  end

  local function freshGraphNodes(vehicle)
    if not vehicle or not runtime.target or not runtime.target.pos or not map or
      type(map.findClosestRoad) ~= "function" or type(map.getMap) ~= "function" or
      type(map.getGraphpath) ~= "function" then return {} end
    local startA, startB = map.findClosestRoad(vehicle:getPosition())
    local mapData = map.getMap()
    local mapNodes = mapData and mapData.nodes
    if not (startA and startB and mapNodes and mapNodes[startA] and mapNodes[startB]) then return {} end

    local direction = type(vehicle.getDirectionVector) == "function" and
      vehicle:getDirectionVector() or nil
    local road = mapNodes[startB].pos - mapNodes[startA].pos
    if direction and type(road.dot) == "function" and road:dot(direction) < 0 then
      startA, startB = startB, startA
    end
    local graph = map.getGraphpath()
    if not graph or type(graph.getPath) ~= "function" then return {} end

    local destinations = {runtime.target.nodeB, runtime.target.nodeA}
    for _, destination in ipairs(destinations) do
      if destination ~= nil then
        local ok, path = pcall(function() return graph:getPath(startB or startA, destination) end)
        if ok and type(path) == "table" then
          local nodes = {}
          appendUnique(nodes, startB or startA)
          for _, node in ipairs(path) do appendUnique(nodes, node) end
          appendUnique(nodes, destination)
          if #nodes >= 2 then return nodes end
        end
      end
    end
    return {}
  end

  local function nativeCommand(nodes)
    return table.concat({
      "extensions.load('taxiDriverAutopilotRecovery');",
      "if extensions.taxiDriverAutopilotRecovery then ",
      "extensions.taxiDriverAutopilotRecovery.stop();",
      "extensions.taxiDriverAutopilotRecovery.setGearboxOverride(false);",
      "extensions.taxiDriverAutopilotRecovery.watchRouteDone() end;",
      "electrics.set_left_signal(false,false); electrics.set_right_signal(false,false);",
      "ai.setMode('disabled'); ai.setRecoverOnCrash(true);",
      "ai.setParameters({awarenessForceCoef=0.35,trafficWaitTime=8,edgeDist=0,enableElectrics=true});",
      "ai.driveUsingPath({path=", serializePath(nodes),
      ",noOfLaps=1,aggression=", tostring(config.aggression),
      ",avoidCars=\"on\",driveInLane=\"on\",routeSpeedMode=\"",
      config.obeySpeedLimits and "legal" or "off", "\"})"
    })
  end

  local function stopNative(vehicle, unwatch)
    return queue(vehicle, table.concat({
      "if extensions.taxiDriverAutopilotRecovery then ",
      "extensions.taxiDriverAutopilotRecovery.stop();",
      unwatch and "extensions.taxiDriverAutopilotRecovery.unwatchRouteDone();" or "",
      "extensions.taxiDriverAutopilotRecovery.setGearboxOverride(false) end;",
      "electrics.set_left_signal(false,false); electrics.set_right_signal(false,false);",
      "ai.setRecoverOnCrash(false); ai.setAvoidCars(\"on\"); ai.driveInLane(\"on\");",
      "ai.setSpeed(nil); ai.setSpeedMode(\"off\"); ai.setMode(\"disabled\")"
    }))
  end

  local function markFailed(vehicle, reason)
    runtime.failed = true
    runtime.status = "failed"
    runtime.reason = tostring(reason or "routeFailed")
    runtime.routeDonePending = false
    stopNative(vehicle, true)
    logEvent("W", string.format("Fleet route abandoned after %d replans: %s",
      runtime.replanCount, runtime.reason))
  end

  local function issueRoute(vehicle, reason, fresh)
    if not runtime.enabled or runtime.suspended or not vehicle then return false end
    local currentDistance = runtime.target and runtime.target.pos and
      distance(vehicle:getPosition(), runtime.target.pos) or math.huge
    if currentDistance <= defaults.arrivalRadius then
      runtime.arrived = true
      runtime.status = "arrived"
      runtime.targetDistance = currentDistance
      stopNative(vehicle, false)
      return true
    end
    local nodes = fresh and freshGraphNodes(vehicle) or {}
    if #nodes < 2 then nodes = remainingOriginalNodes(vehicle) end
    if #nodes < 2 or not queue(vehicle, nativeCommand(nodes)) then return false end
    runtime.status = "driving"
    runtime.reason = tostring(reason or "")
    runtime.routeDonePending = false
    runtime.routeDoneRetryTimer = 0
    resetMotion(vehicle)
    logEvent("I", string.format("Fleet native route issued (%d nodes, reason=%s, replan=%d)",
      #nodes, tostring(reason or "start"), runtime.replanCount))
    return true
  end

  function service:configure(settings)
    settings = type(settings) == "table" and settings or {}
    config.aggression = clamp((tonumber(settings.aggressionPercent) or 30) / 100, 0.1, 0.8)
    config.obeySpeedLimits = settings.obeySpeedLimits ~= false and
      settings.obeyTrafficRules ~= false
    config.stuckSeconds = math.max(defaults.minimumStuckSeconds,
      (tonumber(settings.stuckDelaySeconds) or 15) * 2)
    config.maximumReplans = math.max(1, math.min(defaults.maximumReplans,
      math.floor((tonumber(settings.recoveryMaxAttempts) or defaults.maximumReplans) + 0.5)))
  end

  function service:start(vehicle, target, route, settings)
    if not vehicle or not target or not target.pos or type(route) ~= "table" then return false end
    if runtime.enabled then self:stop(vehicle, "routeChanged") end
    self:configure(settings)
    runtime.enabled = true
    runtime.suspended = false
    runtime.arrived = false
    runtime.failed = false
    runtime.status = "planning"
    runtime.reason = ""
    runtime.target = target
    runtime.route = route
    runtime.routeIndex = 1
    runtime.replanCount = 0
    runtime.routeDonePending = false
    runtime.routeDoneRetryTimer = 0
    resetMotion(vehicle)
    if issueRoute(vehicle, "start", false) then return true end
    markFailed(vehicle, "routeUnavailable")
    return false
  end

  function service:update(vehicle, dt)
    if not runtime.enabled or runtime.suspended or runtime.arrived or runtime.failed then return false end
    dt = math.max(0, tonumber(dt) or 0)
    runtime.monitorTimer = runtime.monitorTimer - dt
    runtime.monitorElapsed = runtime.monitorElapsed + dt
    if runtime.monitorTimer > 0 then return false end
    local elapsed = math.max(defaults.monitorInterval, runtime.monitorElapsed)
    runtime.monitorTimer = defaults.monitorInterval
    runtime.monitorElapsed = 0

    if not vehicle or not runtime.target or not runtime.target.pos then
      markFailed(vehicle, "vehicleUnavailable")
      return true
    end
    local position = vehicle:getPosition()
    local targetDistance = distance(position, runtime.target.pos)
    local currentSpeed = speedKmh(vehicle)
    runtime.targetDistance = targetDistance
    routeProgress(position)

    if targetDistance <= defaults.arrivalRadius and currentSpeed <= defaults.arrivalSpeedKmh then
      runtime.arrived = true
      runtime.status = "arrived"
      stopNative(vehicle, false)
      return true
    end

    if runtime.routeDonePending then
      runtime.routeDoneRetryTimer = runtime.routeDoneRetryTimer - elapsed
      if targetDistance <= defaults.routeDoneRadius then
        runtime.arrived = true
        runtime.status = "arrived"
        stopNative(vehicle, false)
      elseif runtime.routeDoneRetryTimer <= 0 then
        if runtime.replanCount >= config.maximumReplans then
          markFailed(vehicle, "routeDoneFarFromTarget")
        else
          runtime.replanCount = runtime.replanCount + 1
          if not issueRoute(vehicle, "routeDoneRetry", true) then
            markFailed(vehicle, "routeReplanUnavailable")
          end
        end
      end
      return true
    end

    local moved = runtime.lastPosition and distance(position, runtime.lastPosition) or 0
    runtime.lastPosition = copyPosition(position)
    if targetDistance < runtime.bestDistance - 1.5 then
      runtime.bestDistance = targetDistance
      runtime.stuckSeconds = 0
    elseif currentSpeed > 2 or moved > 0.35 then
      runtime.stuckSeconds = math.max(0, runtime.stuckSeconds - elapsed)
    else
      runtime.stuckSeconds = runtime.stuckSeconds + elapsed
    end

    if runtime.stuckSeconds >= config.stuckSeconds then
      if runtime.replanCount >= config.maximumReplans then
        markFailed(vehicle, "stuck")
      else
        runtime.replanCount = runtime.replanCount + 1
        runtime.status = "planning"
        if not issueRoute(vehicle, "stuckReplan", true) then
          markFailed(vehicle, "routeReplanUnavailable")
        end
      end
      return true
    end
    runtime.status = "driving"
    return false
  end

  function service:hasArrived(vehicle)
    if runtime.arrived then return true end
    if not runtime.enabled or not vehicle or not runtime.target or not runtime.target.pos then return false end
    return distance(vehicle:getPosition(), runtime.target.pos) <= defaults.arrivalRadius and
      speedKmh(vehicle) <= defaults.arrivalSpeedKmh
  end

  function service:hasFailed()
    return runtime.failed == true
  end

  function service:stop(vehicle, reason)
    if runtime.enabled then stopNative(vehicle, true) end
    runtime.enabled = false
    runtime.suspended = false
    runtime.arrived = false
    runtime.failed = false
    runtime.status = "off"
    runtime.reason = tostring(reason or "")
    runtime.target = nil
    runtime.route = {}
    runtime.routeIndex = 1
    runtime.routeDonePending = false
    runtime.routeDoneRetryTimer = 0
    runtime.lastPosition = nil
    runtime.bestDistance = math.huge
    runtime.targetDistance = math.huge
    runtime.stuckSeconds = 0
    runtime.replanCount = 0
  end

  function service:suspend(vehicle, value)
    value = value == true
    if not runtime.enabled or runtime.suspended == value then return end
    runtime.suspended = value
    if value then
      runtime.status = "suspended"
      stopNative(vehicle, true)
    else
      runtime.status = "planning"
      if not issueRoute(vehicle, "resume", true) then markFailed(vehicle, "resumeFailed") end
    end
  end

  function service:onRouteDone(vehicle)
    if not runtime.enabled or runtime.suspended or runtime.failed then return false end
    local targetDistance = vehicle and runtime.target and runtime.target.pos and
      distance(vehicle:getPosition(), runtime.target.pos) or math.huge
    runtime.targetDistance = targetDistance
    stopNative(vehicle, false)
    if targetDistance <= defaults.routeDoneRadius then
      runtime.arrived = true
      runtime.status = "arrived"
    else
      runtime.routeDonePending = true
      runtime.routeDoneRetryTimer = defaults.routeDoneRetryDelay
      runtime.status = "planning"
      runtime.reason = "routeDoneFarFromTarget"
    end
    return true
  end

  function service:onBypassComplete()
    return false
  end

  function service:getHud(vehicle)
    local targetDistance = vehicle and runtime.target and runtime.target.pos and
      distance(vehicle:getPosition(), runtime.target.pos) or runtime.targetDistance
    return {
      available = runtime.target ~= nil and vehicle ~= nil,
      enabled = runtime.enabled == true,
      suspended = runtime.suspended == true,
      status = runtime.status,
      reason = runtime.reason,
      stuckSeconds = runtime.stuckSeconds,
      recoveryAttempt = runtime.replanCount,
      targetDistance = targetDistance ~= math.huge and targetDistance or nil,
      lightweight = true
    }
  end

  function service:isEnabled()
    return runtime.enabled == true
  end

  return service
end

return M
