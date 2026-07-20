local M = {}

local active = false
local points = {}
local pointIndex = 1
local elapsed = 0
local targetSpeed = 7
local timeout = 14
local stopAtEnd = false
local completionRadius = 4
local routeWatchActive = false
local gearboxOverrideActive = false
local stationaryDriveHold = false
local safetyConfig = {timeGap = 2.2, comfortableDeceleration = 2.8}
local safetyTimer = 0
local safetyBrake = 0
local safetyHolding = false
local engineStartTimer = 0
local driveReady = false
local recoveryMode = "path"
local reverseStartPosition = nil
local reverseTargetDistance = 0
local reverseSteering = 0
local reverseRescanTimer = 0
local reverseStopReason = nil
local reverseStopSuccess = false

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local angleBetween

local function planarUnit(value, fallbackX, fallbackY)
  local x, y = number(value and value.x, fallbackX or 1), number(value and value.y, fallbackY or 0)
  local length = math.sqrt(x * x + y * y)
  if length < 0.001 then return fallbackX or 1, fallbackY or 0 end
  return x / length, y / length
end

local function rayOrientedBox(originX, originY, dirX, dirY, maximumDistance, box)
  local relativeX, relativeY = originX - box.x, originY - box.y
  local localOriginX = relativeX * box.forwardX + relativeY * box.forwardY
  local localOriginY = relativeX * box.leftX + relativeY * box.leftY
  local localDirectionX = dirX * box.forwardX + dirY * box.forwardY
  local localDirectionY = dirX * box.leftX + dirY * box.leftY
  local minimum, maximum = 0, maximumDistance
  local function clip(origin, direction, extent)
    if math.abs(direction) < 0.0001 then return math.abs(origin) <= extent end
    local first, second = (-extent - origin) / direction, (extent - origin) / direction
    if first > second then first, second = second, first end
    minimum, maximum = math.max(minimum, first), math.min(maximum, second)
    return minimum <= maximum
  end
  if not clip(localOriginX, localDirectionX, box.halfLength) or
    not clip(localOriginY, localDirectionY, box.halfWidth) or maximum < 0 then return nil end
  return clamp(minimum, 0, maximumDistance)
end

local function nearbyBoxes(range)
  local result = {}
  if not mapmgr or type(mapmgr.getObjects) ~= "function" then return result end
  local ownId = obj:getID()
  local position = obj:getPosition()
  for id, data in pairs(mapmgr.getObjects() or {}) do
    if id ~= ownId then
      local center = type(obj.getObjectCenterPosition) == "function" and obj:getObjectCenterPosition(id) or
        data and data.pos
      if center then
        local dx, dy = number(center.x, 0) - number(position.x, 0),
          number(center.y, 0) - number(position.y, 0)
        if dx * dx + dy * dy <= range * range then
          local direction = type(obj.getObjectDirectionVector) == "function" and
            obj:getObjectDirectionVector(id) or data and (data.dirVec or data.dir)
          local forwardX, forwardY = planarUnit(direction, 1, 0)
          local velocity = data and data.vel
          result[#result + 1] = {
            id = id, x = number(center.x, 0), y = number(center.y, 0),
            forwardX = forwardX, forwardY = forwardY,
            leftX = -forwardY, leftY = forwardX,
            halfLength = math.max(1, number(type(obj.getObjectInitialLength) == "function" and
              obj:getObjectInitialLength(id), 4.5) * 0.5),
            halfWidth = math.max(0.5, number(type(obj.getObjectInitialWidth) == "function" and
              obj:getObjectInitialWidth(id), 2) * 0.5),
            speedX = number(velocity and velocity.x, 0), speedY = number(velocity and velocity.y, 0)
          }
        end
      end
    end
  end
  return result
end

local function castTrajectoryRay(originX, originY, directionX, directionY, distance, boxes)
  local closest, hit, blocked = distance, nil, false
  for _, box in ipairs(boxes) do
    local value = rayOrientedBox(originX, originY, directionX, directionY, closest, box)
    if value and value < closest then closest, hit, blocked = value, box, true end
  end
  if type(obj.castRayStatic) == "function" and type(vec3) == "function" then
    local position = obj:getPosition()
    local rayOrigin = vec3(originX, originY, number(position.z, 0) + 0.45)
    local rayDirection = vec3(directionX, directionY, 0)
    local staticDistance = number(obj:castRayStatic(rayOrigin, rayDirection, closest), closest)
    if staticDistance < closest then closest, hit, blocked = staticDistance, nil, true end
  end
  return closest, hit, blocked
end

local function scanPredictedTrajectory(speed, travelDirection, steeringOverride, horizonOverride)
  local position = obj:getPosition()
  local forwardX, forwardY = planarUnit(obj:getDirectionVector(), 1, 0)
  travelDirection = travelDirection < 0 and -1 or 1
  forwardX, forwardY = forwardX * travelDirection, forwardY * travelDirection
  local steeringState = input.state and input.state.steering
  local steering = clamp(number(steeringOverride,
    number(steeringState and steeringState.val, 0)), -1, 1)
  local ownLength = math.max(3, number(type(obj.getInitialLength) == "function" and
    obj:getInitialLength(), 4.5))
  local ownWidth = math.max(1.2, number(type(obj.getInitialWidth) == "function" and
    obj:getInitialWidth(), 2))
  local horizon = horizonOverride and clamp(number(horizonOverride, 10), 2, 48) or
    clamp(speed * 1.8 + 7, 10, 48)
  local boxes = nearbyBoxes(horizon + 10)
  local centerX = number(position.x, 0) + forwardX * ownLength * 0.42
  local centerY = number(position.y, 0) + forwardY * ownLength * 0.42
  local heading = angleBetween(forwardY, forwardX)
  local curvature = steering * 0.105 * travelDirection
  local traveled, closest, closestBox = 0, horizon, nil
  local segmentLength = 2.25
  while traveled < horizon do
    local currentLength = math.min(segmentLength, horizon - traveled)
    local directionX, directionY = math.cos(heading), math.sin(heading)
    local leftX, leftY = -directionY, directionX
    for _, lateral in ipairs({-ownWidth * 0.38, 0, ownWidth * 0.38}) do
      local rayDistance, box, blocked = castTrajectoryRay(centerX + leftX * lateral,
        centerY + leftY * lateral, directionX, directionY, currentLength, boxes)
      if blocked and traveled + rayDistance < closest then
        closest, closestBox = traveled + rayDistance, box
      end
    end
    centerX = centerX + directionX * currentLength
    centerY = centerY + directionY * currentLength
    traveled = traveled + currentLength
    heading = heading + curvature * currentLength
    if closest <= traveled then break end
  end
  local obstacleSpeed = 0
  if closestBox then obstacleSpeed = closestBox.speedX * forwardX + closestBox.speedY * forwardY end
  return closest, math.max(0, speed - obstacleSpeed), closestBox and closestBox.id or nil
end

local function scanDirectionalFan(travelDirection, maximumDistance)
  local position = obj:getPosition()
  local forwardX, forwardY = planarUnit(obj:getDirectionVector(), 1, 0)
  travelDirection = travelDirection < 0 and -1 or 1
  forwardX, forwardY = forwardX * travelDirection, forwardY * travelDirection
  local ownLength = math.max(3, number(type(obj.getInitialLength) == "function" and
    obj:getInitialLength(), 4.5))
  local ownWidth = math.max(1.2, number(type(obj.getInitialWidth) == "function" and
    obj:getInitialWidth(), 2))
  maximumDistance = clamp(number(maximumDistance, 7), 2, 12)
  local boxes = nearbyBoxes(maximumDistance + ownLength + 4)
  local bumperX = number(position.x, 0) + forwardX * ownLength * 0.42
  local bumperY = number(position.y, 0) + forwardY * ownLength * 0.42
  local leftX, leftY = -forwardY, forwardX
  local result = {}
  for _, angle in ipairs({-0.56, -0.28, 0, 0.28, 0.56}) do
    local cosine, sine = math.cos(angle), math.sin(angle)
    local rayX = forwardX * cosine + leftX * sine
    local rayY = forwardY * cosine + leftY * sine
    local clearance = maximumDistance
    for _, lateral in ipairs({-ownWidth * 0.38, 0, ownWidth * 0.38}) do
      local distance = castTrajectoryRay(bumperX + leftX * lateral,
        bumperY + leftY * lateral, rayX, rayY, maximumDistance, boxes)
      clearance = math.min(clearance, distance)
    end
    result[#result + 1] = {angle = angle, clearance = clearance}
  end
  return result
end

local function maximumFanClearance(fan)
  local result = 0
  for _, ray in ipairs(fan or {}) do result = math.max(result, number(ray.clearance, 0)) end
  return result
end

local function findReverseEscapePlan(data)
  data = type(data) == "table" and data or {}
  local minimumDistance = clamp(number(data.minDistance, 3), 3, 6)
  local maximumDistance = clamp(number(data.maxDistance, 6), minimumDistance, 6)
  local frontFan = scanDirectionalFan(1, 4.5)
  if data.requireFrontBlocked == true and maximumFanClearance(frontFan) > 2.75 then
    return nil, "frontEscapeAvailable"
  end

  local best = nil
  for _, ray in ipairs(scanDirectionalFan(-1, maximumDistance + 1.5)) do
    local steering = clamp(-ray.angle / 0.56 * 0.72, -0.72, 0.72)
    local trajectoryClearance = scanPredictedTrajectory(0, -1, steering, maximumDistance + 1.5)
    local clearance = math.min(ray.clearance, trajectoryClearance)
    local distance = clamp(clearance - 1.15, 0, maximumDistance)
    local score = distance - math.abs(steering) * 0.45
    if distance >= minimumDistance and (not best or score > best.score) then
      best = {distance = distance, steering = steering, score = score,
        clearance = clearance, angle = ray.angle}
    end
  end
  if not best then return nil, "rearBlocked" end
  return best
end

local function releaseSafetyInputs()
  if not safetyHolding then return end
  input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
  input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
  safetyHolding = false
end

local function updateCollisionSafety(dt)
  if not gearboxOverrideActive then
    safetyBrake = 0
    releaseSafetyInputs()
    return
  end
  safetyTimer = safetyTimer - math.max(0, number(dt, 0))
  if safetyTimer > 0 and safetyBrake <= 0 then return end
  safetyTimer = 0.05
  local signedSpeed = number(electrics.values.wheelspeed, 0)
  local speed = math.abs(signedSpeed)
  if speed < 0.35 then
    safetyBrake = math.max(0, safetyBrake - math.max(0, number(dt, 0)) * 2)
    if safetyBrake <= 0 then releaseSafetyInputs() end
    return
  end
  local distance, closingSpeed = scanPredictedTrajectory(speed, signedSpeed < 0 and -1 or 1)
  local deceleration = clamp(number(safetyConfig.comfortableDeceleration, 2.8), 1.5, 4.5)
  local comfortableDistance = 2.5 + speed * math.min(1.1, number(safetyConfig.timeGap, 2.2) * 0.32) +
    closingSpeed * closingSpeed / (2 * deceleration)
  local emergencyDistance = 1.2 + speed * 0.12 + closingSpeed * closingSpeed / 15
  local rawBrake = 0
  if distance <= emergencyDistance or (closingSpeed > 1 and distance / closingSpeed < 0.65) then
    rawBrake = 1
  elseif distance < comfortableDistance then
    rawBrake = clamp(0.16 + 0.74 * (comfortableDistance - distance) /
      math.max(0.5, comfortableDistance - emergencyDistance), 0.16, 0.9)
  end
  local frame = math.max(0.016, number(dt, 0))
  if rawBrake >= 1 then safetyBrake = 1
  elseif rawBrake > safetyBrake then safetyBrake = math.min(rawBrake, safetyBrake + frame * 2.5)
  else safetyBrake = math.max(rawBrake, safetyBrake - frame * 0.9) end
  if safetyBrake > 0.01 then
    safetyHolding = true
    input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
    input.event("brake", safetyBrake, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
  else
    safetyBrake = 0
    releaseSafetyInputs()
  end
end

angleBetween = function(y, x)
  if type(atan2) == "function" then return atan2(y, x) end
  if type(math.atan2) == "function" then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi * 0.5 end
  if y < 0 then return -math.pi * 0.5 end
  return 0
end

local function releaseInputs()
  input.event("steering", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
end

local function combustionEngines()
  if not powertrain or type(powertrain.getDevicesByType) ~= "function" then return {} end
  local ok, result = pcall(powertrain.getDevicesByType, "combustionEngine")
  return ok and type(result) == "table" and result or {}
end

local function engineIsRunning(engines)
  if #engines == 0 then return true end
  for _, engine in ipairs(engines) do
    local starterSpeed = number(engine.starterMaxAV, 0)
    if starterSpeed <= 0 or number(engine.outputAV1, 0) > starterSpeed * 0.8 then return true end
  end
  return false
end

local function ensureDriveReady(dt)
  if not gearboxOverrideActive or driveReady then return end
  local engines = combustionEngines()
  local ignition = number(electrics.values.ignitionLevel, 0)
  if engineIsRunning(engines) and ignition >= 2 then
    driveReady = true
    engineStartTimer = 0
    if ignition == 3 and type(electrics.setIgnitionLevel) == "function" then electrics.setIgnitionLevel(2) end
    if type(log) == "function" then log("I", "taxiDriverAutopilotRecovery", "[TaxiDriver] AI powertrain ready") end
    return
  end
  engineStartTimer = engineStartTimer - math.max(0, number(dt, 0))
  if engineStartTimer > 0 then return end
  engineStartTimer = 1.25
  if type(electrics.setIgnitionLevel) == "function" then
    electrics.setIgnitionLevel(#engines > 0 and 3 or 2)
  end
  local main = controller and controller.mainController or nil
  if main then
    if type(main.setEngineIgnition) == "function" then main.setEngineIgnition(true) end
    if #engines > 0 and type(main.setStarter) == "function" then main.setStarter(true) end
  end
  if type(log) == "function" then log("I", "taxiDriverAutopilotRecovery", "[TaxiDriver] AI powertrain start requested") end
end

local function ensureArcadeMode()
  local main = controller and controller.mainController or nil
  if main and main.gearboxBehavior ~= "arcade" and type(main.setGearboxMode) == "function" then
    main.setGearboxMode("arcade")
    if type(log) == "function" then
      log("I", "taxiDriverAutopilotRecovery", "[TaxiDriver] AI gearbox mode set to Arcade")
    end
  end
end

local function setGearboxOverride(enabled)
  enabled = enabled == true
  if enabled == gearboxOverrideActive then return end
  gearboxOverrideActive = enabled
  engineStartTimer = 0
  driveReady = false
  if enabled then
    ensureArcadeMode()
  else
    local main = controller and controller.mainController or nil
    if main and type(main.setStarter) == "function" then main.setStarter(false) end
    if number(electrics.values.ignitionLevel, 0) == 3 and
      type(electrics.setIgnitionLevel) == "function" then electrics.setIgnitionLevel(2) end
    input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    stationaryDriveHold = false
  end
end

local function releaseStationaryDriveHold()
  if not stationaryDriveHold then return end
  input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
  input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
  input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
  stationaryDriveHold = false
end

local function updateStationaryDriveHold()
  if not gearboxOverrideActive or active or recoveryMode == "reverse" then
    releaseStationaryDriveHold()
    return
  end
  local speed = math.abs(number(electrics.values.wheelspeed, 0))
  local gearIndex = number(electrics.values.gearIndex, 0)
  local state = input.state or {}
  local throttle = number(state.throttle and state.throttle.val, 0)
  local brake = number(state.brake and state.brake.val, 0)
  local parkingbrake = number(state.parkingbrake and state.parkingbrake.val, 0)
  local stopped = speed < 0.2
  local braking = brake > 0.2 or parkingbrake > 0.2
  local departing = gearIndex > 0 and throttle > 0.08 and brake < 0.1
  if not stopped or departing or (not stationaryDriveHold and not braking) then
    releaseStationaryDriveHold()
    return
  end

  stationaryDriveHold = true
  if gearIndex > 0 then
    -- A tiny throttle value prevents Arcade from selecting N. The service
    -- brake still holds the car in D and BeamNG remains responsible for the clutch.
    input.event("throttle", 0.03, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("brake", 1, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
  else
    -- Arcade selects a forward gear from N/R through forward pedal input.
    -- Hold the parking brake during that short hand-off to prevent rollback.
    input.event("throttle", 0.12, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
    input.event("parkingbrake", 1, "FILTER_AI", nil, nil, nil, "taxiDriverGearbox")
  end
end

local function setSignal(direction)
  electrics.set_left_signal(direction < 0, false)
  electrics.set_right_signal(direction > 0, false)
end

local function notifyRouteDone()
  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onAutopilotRouteDone(%d) end",
    obj:getID()
  ))
end

local function installRouteObserver()
  if not guihooks or type(guihooks.trigger) ~= "function" then return false end
  if guihooks._taxiDriverRouteDoneObserverInstalled ~= true then
    local previousTrigger = guihooks.trigger
    guihooks.trigger = function(hookName, ...)
      local sink = guihooks._taxiDriverRouteDoneSink
      if type(sink) == "function" then sink(hookName, ...) end
      return previousTrigger(hookName, ...)
    end
    guihooks._taxiDriverRouteDoneObserverInstalled = true
  end
  guihooks._taxiDriverRouteDoneSink = function(hookName, data)
    if routeWatchActive and hookName == "AIStatusChange" and type(data) == "table" and
      data.category == "route" and string.lower(tostring(data.status or "")) == "route done" then
      notifyRouteDone()
    end
  end
  return true
end

local function watchRouteDone()
  routeWatchActive = true
  return installRouteObserver()
end

local function unwatchRouteDone()
  routeWatchActive = false
  if guihooks then guihooks._taxiDriverRouteDoneSink = nil end
end

local function notifyCompletion(success, reason)
  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onAutopilotBypassComplete(%d,%s,%q) end",
    obj:getID(), success and "true" or "false", tostring(reason or "")
  ))
end

local function finish(success, reason)
  if not active then return end
  active = false
  releaseInputs()
  setSignal(0)
  notifyCompletion(success, reason)
end

local function stop()
  active = false
  recoveryMode = "path"
  reverseStartPosition = nil
  reverseTargetDistance = 0
  reverseSteering = 0
  reverseRescanTimer = 0
  reverseStopReason = nil
  reverseStopSuccess = false
  releaseInputs()
  setSignal(0)
end

local function start(data)
  stop()
  data = type(data) == "table" and data or {}
  points = type(data.points) == "table" and data.points or {}
  if #points < 1 then return false end
  pointIndex = 1
  elapsed = 0
  targetSpeed = clamp(tonumber(data.targetSpeed) or 7, 2, 12)
  timeout = clamp(tonumber(data.timeout) or 14, 5, 30)
  stopAtEnd = data.stopAtEnd == true
  completionRadius = clamp(tonumber(data.completionRadius) or 4, 2, 10)
  recoveryMode = "path"
  ensureArcadeMode()
  active = true
  setSignal(tonumber(data.signal) or 0)
  return true
end

local function startReverseEscape(data)
  stop()
  data = type(data) == "table" and data or {}
  local plan, reason = findReverseEscapePlan(data)
  if not plan then
    notifyCompletion(false, reason)
    return false
  end
  elapsed = 0
  timeout = clamp(number(data.timeout, 10), 5, 15)
  targetSpeed = clamp(number(data.targetSpeed, 2.2), 1.2, 3)
  recoveryMode = "reverse"
  reverseStartPosition = obj:getPosition()
  reverseStartPosition = {x = number(reverseStartPosition.x, 0),
    y = number(reverseStartPosition.y, 0), z = number(reverseStartPosition.z, 0)}
  reverseTargetDistance = plan.distance
  reverseSteering = plan.steering
  reverseRescanTimer = 0
  reverseStopReason = nil
  reverseStopSuccess = false
  ensureArcadeMode()
  active = true
  setSignal(0)
  if type(log) == "function" then
    log("I", "taxiDriverAutopilotRecovery", string.format(
      "[TaxiDriver] AI reverse escape started distance=%.2f steering=%.2f clearance=%.2f",
      plan.distance, plan.steering, plan.clearance))
  end
  return true
end

local function updateReverseEscape(dt)
  local position = obj:getPosition()
  local dx = number(position.x, 0) - reverseStartPosition.x
  local dy = number(position.y, 0) - reverseStartPosition.y
  local traveled = math.sqrt(dx * dx + dy * dy)
  local remaining = reverseTargetDistance - traveled
  local speed = math.abs(number(electrics.values.wheelspeed, 0))
  if elapsed >= timeout and not reverseStopReason then
    reverseStopReason, reverseStopSuccess = "timeout", false
  elseif remaining <= 0.15 and not reverseStopReason then
    reverseStopReason, reverseStopSuccess = "reverseComplete", true
  end
  if reverseStopReason then
    input.event("steering", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
    input.event("throttle", speed > 0.35 and 0.75 or 0, "FILTER_AI", nil, nil, nil,
      "taxiDriverRecovery")
    input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
    if speed <= 0.35 then finish(reverseStopSuccess, reverseStopReason) end
    return
  end

  reverseRescanTimer = reverseRescanTimer - math.max(0, number(dt, 0))
  if reverseRescanTimer <= 0 then
    reverseRescanTimer = 0.08
    local rearClearance = scanPredictedTrajectory(speed, -1, reverseSteering,
      math.min(remaining + 1.25, 7.25))
    if rearClearance <= math.min(1.15, remaining + 0.25) then
      reverseStopReason, reverseStopSuccess = "rearBecameBlocked", false
      input.event("steering", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      input.event("throttle", 0.75, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      return
    end
  end

  local desiredSpeed = math.min(targetSpeed, math.max(0.45, remaining * 0.7))
  local reverseDrive = clamp(0.22 + (desiredSpeed - speed) * 0.22, 0.14, 0.58)
  local reverseStop = speed > desiredSpeed + 0.35 and
    clamp((speed - desiredSpeed) * 0.28, 0, 0.5) or 0
  input.event("steering", reverseSteering, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("throttle", reverseStop, "FILTER_AI", nil, nil, nil,
    "taxiDriverRecovery")
  input.event("brake", reverseStop > 0 and 0 or reverseDrive, "FILTER_AI", nil, nil, nil,
    "taxiDriverRecovery")
  input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
end

local function updateGFX(dt)
  ensureDriveReady(dt)
  if recoveryMode ~= "reverse" then
    updateCollisionSafety(dt)
    updateStationaryDriveHold()
  end
  if not active then return end
  if not driveReady then
    input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
    input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
    input.event("parkingbrake", 1, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
    return
  end
  elapsed = elapsed + math.max(0, tonumber(dt) or 0)
  if recoveryMode == "reverse" then
    updateReverseEscape(dt)
    return
  end
  if elapsed >= timeout then finish(false, "timeout"); return end

  local position = obj:getPosition()
  local target = points[pointIndex]
  if not target then finish(true, "complete"); return end
  local dx = (tonumber(target.x) or 0) - position.x
  local dy = (tonumber(target.y) or 0) - position.y
  local dz = (tonumber(target.z) or 0) - position.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  while distance < 3.5 and pointIndex < #points do
    pointIndex = pointIndex + 1
    target = points[pointIndex]
    dx = (tonumber(target.x) or 0) - position.x
    dy = (tonumber(target.y) or 0) - position.y
    dz = (tonumber(target.z) or 0) - position.z
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  if pointIndex == #points and distance < completionRadius and not stopAtEnd then
    finish(true, "complete"); return
  end

  local direction = obj:getDirectionVector()
  local planarLength = math.max(0.001, math.sqrt(dx * dx + dy * dy))
  local targetX, targetY = dx / planarLength, dy / planarLength
  local forwardDot = direction.x * targetX + direction.y * targetY
  local reversing = forwardDot < -0.25
  local angle = reversing and angleBetween(-direction.x * targetY + direction.y * targetX,
    -direction.x * targetX - direction.y * targetY) or
    angleBetween(direction.x * targetY - direction.y * targetX, forwardDot)
  local steering = clamp(angle * (reversing and -1.7 or 1.7), -1, 1)
  local speed = math.abs(tonumber(electrics.values.wheelspeed) or 0)
  local desiredSpeed = targetSpeed * clamp(1 - math.abs(angle) * 0.55, 0.42, 1)
  if mapmgr and type(mapmgr.getObjects) == "function" then
    local closestObstacle = math.huge
    for id, data in pairs(mapmgr.getObjects() or {}) do
      if id ~= obj:getID() and data and data.pos then
        local ox = (tonumber(data.pos.x) or 0) - position.x
        local oy = (tonumber(data.pos.y) or 0) - position.y
        local longitudinal = ox * targetX + oy * targetY
        local lateral = math.abs(-ox * targetY + oy * targetX)
        if longitudinal > 0 and longitudinal < closestObstacle and lateral <= 2.5 then
          closestObstacle = longitudinal
        end
      end
    end
    if closestObstacle < 14 then
      desiredSpeed = math.min(desiredSpeed, math.max(0, (closestObstacle - 5) * 0.45))
    end
  end
  if stopAtEnd and pointIndex == #points then
    desiredSpeed = math.min(desiredSpeed, math.max(0, (distance - completionRadius * 0.45) * 0.55))
  end
  local throttle = clamp((desiredSpeed - speed) * 0.22, 0, 0.72)
  local brake = clamp((speed - desiredSpeed) * 0.28, 0, 0.8)
  if reversing then
    throttle = clamp((speed - desiredSpeed) * 0.28, 0, 0.7)
    brake = clamp((desiredSpeed - speed) * 0.22, 0.2, 0.65)
  end
  if stopAtEnd and pointIndex == #points and distance <= completionRadius then
    steering, throttle, brake = 0, 0, speed > 0.65 and 0.72 or 1
  end

  input.event("steering", steering, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("throttle", throttle, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("brake", brake, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  if stopAtEnd and pointIndex == #points and distance <= completionRadius and speed <= 0.65 then
    finish(true, "complete")
  end
end

local function onReset()
  stop()
  setGearboxOverride(false)
end

local function setSafetyConfig(data)
  data = type(data) == "table" and data or {}
  safetyConfig.timeGap = clamp(number(data.timeGap, safetyConfig.timeGap), 1.2, 3.5)
  safetyConfig.comfortableDeceleration = clamp(number(data.comfortableDeceleration,
    safetyConfig.comfortableDeceleration), 1.5, 4.5)
end

M.start = start
M.startReverseEscape = startReverseEscape
M.stop = stop
M.updateGFX = updateGFX
M.onReset = onReset
M.watchRouteDone = watchRouteDone
M.unwatchRouteDone = unwatchRouteDone
M.setGearboxOverride = setGearboxOverride
M.setSafetyConfig = setSafetyConfig
M.findReverseEscapePlan = findReverseEscapePlan

return M
