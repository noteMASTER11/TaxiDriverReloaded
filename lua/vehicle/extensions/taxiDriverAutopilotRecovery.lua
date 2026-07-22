local M = {}

local active = false
local points = {}
local pointIndex = 1
local pointBestDistance = math.huge
local pointNoProgress = 0
local elapsed = 0
local targetSpeed = 7
local timeout = 14
local stopAtEnd = false
local completionRadius = 4
local allowReverse = true
local routeWatchActive = false
local gearboxOverrideActive = false
local stationaryDriveHold = false
local safetyConfig = {timeGap = 2.2, comfortableDeceleration = 2.8}
local safetyTimer = 0
local safetyBrake = 0
local safetyHolding = false
local safetyObstacleDistance = math.huge
local safetyObstacleClosingSpeed = 0
local safetyObstacleId = nil
local safetyObstacleDetected = false
local preflightFrontClearance = nil
local preflightRearClearance = nil
local engineStartTimer = 0
local driveReady = false
local recoveryMode = "path"
local reverseStartPosition = nil
local reverseTargetDistance = 0
local reverseSteering = 0
local reverseRescanTimer = 0
local reverseStopReason = nil
local reverseStopSuccess = false
local reverseFanClearance = math.huge
local reverseTrajectoryClearance = math.huge
local reverseRayCount = 0

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function footprintOffsets(width, margin)
  local edge = math.max(0.65, number(width, 2) * 0.5 + number(margin, 0.28))
  return {-edge, -edge * 0.5, 0, edge * 0.5, edge}
end

local angleBetween

-- BeamNG's steering input is negative for a left turn and positive for a
-- right turn.  Geometry in this controller uses positive angles towards the
-- vehicle's left vector.  Reverse motion mirrors the steering response, so
-- keep the conversion in one place instead of silently mixing conventions.
local function steeringForTravelAngle(angle, travelDirection, gain, limit)
  local direction = travelDirection < 0 and -1 or 1
  return clamp(-number(angle, 0) * direction * number(gain, 1),
    -number(limit, 1), number(limit, 1))
end

local function planarUnit(value, fallbackX, fallbackY)
  local x, y = number(value and value.x, fallbackX or 1), number(value and value.y, fallbackY or 0)
  local length = math.sqrt(x * x + y * y)
  if length < 0.001 then return fallbackX or 1, fallbackY or 0 end
  return x / length, y / length
end

local function unit3(x, y, z, fallbackX, fallbackY, fallbackZ)
  local length = math.sqrt(x * x + y * y + z * z)
  if length < 0.001 then return fallbackX or 1, fallbackY or 0, fallbackZ or 0 end
  return x / length, y / length, z / length
end

local function vehicleBasis(travelDirection)
  local direction = obj:getDirectionVector()
  local forwardX, forwardY, forwardZ = unit3(number(direction.x, 1),
    number(direction.y, 0), number(direction.z, 0), 1, 0, 0)
  local rawUp = type(obj.getDirectionVectorUp) == "function" and
    obj:getDirectionVectorUp() or {x = 0, y = 0, z = 1}
  local upX, upY, upZ = unit3(number(rawUp.x, 0), number(rawUp.y, 0),
    number(rawUp.z, 1), 0, 0, 1)
  local leftX, leftY, leftZ = unit3(upY * forwardZ - upZ * forwardY,
    upZ * forwardX - upX * forwardZ, upX * forwardY - upY * forwardX,
    -forwardY, forwardX, 0)
  upX, upY, upZ = unit3(forwardY * leftZ - forwardZ * leftY,
    forwardZ * leftX - forwardX * leftZ, forwardX * leftY - forwardY * leftX,
    0, 0, 1)
  if travelDirection < 0 then
    forwardX, forwardY, forwardZ = -forwardX, -forwardY, -forwardZ
    leftX, leftY, leftZ = -leftX, -leftY, -leftZ
  end
  return forwardX, forwardY, forwardZ, leftX, leftY, leftZ, upX, upY, upZ
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

local function castTrajectoryRay(originX, originY, originZ, directionX, directionY, directionZ,
  distance, boxes)
  local closest, hit, blocked = distance, nil, false
  for _, box in ipairs(boxes) do
    local value = rayOrientedBox(originX, originY, directionX, directionY, closest, box)
    if value and value < closest then closest, hit, blocked = value, box, true end
  end
  if type(obj.castRayStatic) == "function" and type(vec3) == "function" then
    local rayOrigin = vec3(originX, originY, originZ)
    local rayDirection = vec3(directionX, directionY, directionZ)
    local staticDistance = number(obj:castRayStatic(rayOrigin, rayDirection, closest), closest)
    if staticDistance < closest then closest, hit, blocked = staticDistance, nil, true end
  end
  return closest, hit, blocked
end

local function scanPredictedTrajectory(speed, travelDirection, steeringOverride, horizonOverride)
  local position = obj:getPosition()
  travelDirection = travelDirection < 0 and -1 or 1
  local forwardX, forwardY, forwardZ, baseLeftX, baseLeftY, baseLeftZ,
    upX, upY, upZ = vehicleBasis(travelDirection)
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
  local centerZ = number(position.z, 0) + forwardZ * ownLength * 0.42 + upZ * 0.45
  -- Convert the BeamNG input sign back to the positive-left geometric angle
  -- used by the sampled trajectory.
  local curvature = -steering * 0.105 * travelDirection
  local traveled, closest, closestBox, closestBlocked = 0, horizon, nil, false
  local segmentLength = 2.25
  local turnAngle = 0
  while traveled < horizon do
    local currentLength = math.min(segmentLength, horizon - traveled)
    local cosine, sine = math.cos(turnAngle), math.sin(turnAngle)
    local directionX = forwardX * cosine + baseLeftX * sine
    local directionY = forwardY * cosine + baseLeftY * sine
    local directionZ = forwardZ * cosine + baseLeftZ * sine
    local leftX = -forwardX * sine + baseLeftX * cosine
    local leftY = -forwardY * sine + baseLeftY * cosine
    local leftZ = -forwardZ * sine + baseLeftZ * cosine
    for _, lateral in ipairs(footprintOffsets(ownWidth, 0.28)) do
      local rayDistance, box, blocked = castTrajectoryRay(centerX + leftX * lateral,
        centerY + leftY * lateral, centerZ + leftZ * lateral,
        directionX, directionY, directionZ, currentLength, boxes)
      if blocked and traveled + rayDistance < closest then
        closest, closestBox, closestBlocked = traveled + rayDistance, box, true
      end
    end
    centerX = centerX + directionX * currentLength
    centerY = centerY + directionY * currentLength
    centerZ = centerZ + directionZ * currentLength
    traveled = traveled + currentLength
    turnAngle = turnAngle + curvature * currentLength
    if closest <= traveled then break end
  end
  local obstacleSpeed = 0
  if closestBox then obstacleSpeed = closestBox.speedX * forwardX + closestBox.speedY * forwardY end
  return closest, math.max(0, speed - obstacleSpeed), closestBox and closestBox.id or nil,
    closestBlocked
end

local function scanDirectionalFan(travelDirection, maximumDistance)
  local position = obj:getPosition()
  travelDirection = travelDirection < 0 and -1 or 1
  local forwardX, forwardY, forwardZ, leftX, leftY, leftZ,
    upX, upY, upZ = vehicleBasis(travelDirection)
  local ownLength = math.max(3, number(type(obj.getInitialLength) == "function" and
    obj:getInitialLength(), 4.5))
  local ownWidth = math.max(1.2, number(type(obj.getInitialWidth) == "function" and
    obj:getInitialWidth(), 2))
  maximumDistance = clamp(number(maximumDistance, 7), 2, 18)
  local boxes = nearbyBoxes(maximumDistance + ownLength + 4)
  local bumperX = number(position.x, 0) + forwardX * ownLength * 0.42
  local bumperY = number(position.y, 0) + forwardY * ownLength * 0.42
  local bumperZ = number(position.z, 0) + forwardZ * ownLength * 0.42 + upZ * 0.45
  local result = {}
  -- Scan the full travel-facing hemisphere, including both exact side
  -- directions. Reversing the vehicle basis gives the rear the same field.
  for index = -6, 6 do
    local angle = index * math.pi / 12
    local cosine, sine = math.cos(angle), math.sin(angle)
    local rayX = forwardX * cosine + leftX * sine
    local rayY = forwardY * cosine + leftY * sine
    local rayZ = forwardZ * cosine + leftZ * sine
    local clearance = maximumDistance
    for _, lateral in ipairs(footprintOffsets(ownWidth, 0.28)) do
      local distance = castTrajectoryRay(bumperX + leftX * lateral,
        bumperY + leftY * lateral, bumperZ + leftZ * lateral,
        rayX, rayY, rayZ, maximumDistance, boxes)
      clearance = math.min(clearance, distance)
    end
    result[#result + 1] = {angle = angle, clearance = clearance,
      maximumDistance = maximumDistance}
  end
  return result
end

local function maximumFanClearance(fan)
  local result = 0
  for _, ray in ipairs(fan or {}) do result = math.max(result, number(ray.clearance, 0)) end
  return result
end

local function corridorFanClearance(fan, steering, travelDirection)
  local expected = travelDirection < 0 and steering * 0.78 or -steering * 0.62
  local clearance, nearest, nearestDelta = math.huge, nil, math.huge
  for _, ray in ipairs(fan or {}) do
    local delta = math.abs(number(ray.angle, 0) - expected)
    if delta < nearestDelta then nearest, nearestDelta = ray, delta end
    local value = number(ray.clearance, math.huge)
    if value >= number(ray.maximumDistance, value) - 0.05 then value = math.huge end
    if delta <= 0.14 then clearance = math.min(clearance, value) end
  end
  if clearance ~= math.huge then return clearance end
  local nearestValue = number(nearest and nearest.clearance, math.huge)
  return nearestValue < number(nearest and nearest.maximumDistance, nearestValue) - 0.05 and
    nearestValue or math.huge
end

local function bestFanSteering(fan, travelDirection, maximumDistance)
  local best
  for _, ray in ipairs(fan or {}) do
    local steering = steeringForTravelAngle(number(ray.angle, 0), travelDirection,
      (travelDirection < 0 and 0.9 or 1) / (math.pi * 0.5),
      travelDirection < 0 and 0.9 or 1)
    local trajectory = scanPredictedTrajectory(0, travelDirection, steering, maximumDistance)
    local clearance = math.min(number(ray.clearance, 0), trajectory)
    local score = clearance - math.abs(steering) * 0.38
    if not best or score > best.score then
      best = {steering = steering, clearance = clearance, trajectory = trajectory, score = score}
    end
  end
  return best
end

local function scanMotionSpace(speed, travelDirection, steering, horizon)
  horizon = clamp(number(horizon, speed * 1.8 + 7), 2, 48)
  local fan = scanDirectionalFan(travelDirection, math.min(18, horizon))
  local trajectory, closingSpeed, obstacleId, blocked =
    scanPredictedTrajectory(speed, travelDirection, steering, horizon)
  local fanClearance = corridorFanClearance(fan, steering, travelDirection)
  return math.min(trajectory, fanClearance), trajectory, fanClearance,
    closingSpeed, obstacleId, blocked, fan
end

local function findReverseEscapePlan(data)
  data = type(data) == "table" and data or {}
  local minimumDistance = clamp(number(data.minDistance, 3), 3, 6)
  local maximumDistance = clamp(number(data.maxDistance, 6), minimumDistance, 6)
  local frontFan = scanDirectionalFan(1, 4.5)
  if data.requireFrontBlocked == true and maximumFanClearance(frontFan) > 2.75 then
    return nil, "frontEscapeAvailable"
  end

  local fan = scanDirectionalFan(-1, maximumDistance + 1.5)
  local choice = bestFanSteering(fan, -1, maximumDistance + 1.5)
  local best = choice and {distance = clamp(choice.clearance - 1.15, 0, maximumDistance),
    steering = choice.steering, score = choice.score, clearance = choice.clearance} or nil
  if best and best.distance < minimumDistance then best = nil end
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
    safetyObstacleDistance = math.huge
    safetyObstacleClosingSpeed = 0
    safetyObstacleId = nil
    safetyObstacleDetected = false
    releaseSafetyInputs()
    return
  end
  safetyTimer = safetyTimer - math.max(0, number(dt, 0))
  if safetyTimer > 0 and safetyBrake <= 0 then return end
  safetyTimer = 0.05
  local signedSpeed = number(electrics.values.wheelspeed, 0)
  local speed = math.abs(signedSpeed)
  local gearIndex = number(electrics.values.gearIndex, 0)
  local travelDirection = (signedSpeed < -0.05 or (speed < 0.35 and gearIndex < 0)) and -1 or 1
  local distance, trajectory, fanClearance, closingSpeed, obstacleId, obstacleDetected, fan =
    scanMotionSpace(speed, travelDirection, number(input.state and input.state.steering and
      input.state.steering.val, 0), speed * 1.8 + 7)
  if travelDirection < 0 then
    reverseFanClearance, reverseTrajectoryClearance, reverseRayCount =
      fanClearance, trajectory, #fan
  end
  safetyObstacleDistance = distance
  safetyObstacleClosingSpeed = closingSpeed
  safetyObstacleId = obstacleId
  safetyObstacleDetected = obstacleDetected == true
  if speed < 0.35 then
    preflightFrontClearance = scanPredictedTrajectory(0, 1, 0, 8)
    preflightRearClearance = scanPredictedTrajectory(0, -1, 0, 8)
    local state = input.state or {}
    local throttle = number(state.throttle and state.throttle.val, 0)
    local brake = number(state.brake and state.brake.val, 0)
    local movingIntent = safetyHolding or travelDirection < 0 and brake > 0.08 or
      travelDirection > 0 and throttle > 0.08
    local blockedAtBumper = obstacleDetected and distance <= 1.5
    if not movingIntent or not blockedAtBumper then
      safetyBrake = math.max(0, safetyBrake - math.max(0, number(dt, 0)) * 2)
      if safetyBrake <= 0 then releaseSafetyInputs() end
      return
    end
  end
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
    if travelDirection < 0 then
      input.event("throttle", safetyBrake, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
      input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
    else
      input.event("throttle", 0, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
      input.event("brake", safetyBrake, "FILTER_AI", nil, nil, nil, "taxiDriverSafety")
    end
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
  reverseFanClearance = math.huge
  reverseTrajectoryClearance = math.huge
  reverseRayCount = 0
  safetyTimer = 0
  safetyObstacleDistance = math.huge
  safetyBrake = 0
  safetyHolding = false
  pointBestDistance = math.huge
  pointNoProgress = 0
  releaseInputs()
  setSignal(0)
end

local function start(data)
  stop()
  data = type(data) == "table" and data or {}
  points = type(data.points) == "table" and data.points or {}
  if #points < 1 then return false end
  pointIndex = 1
  pointBestDistance = math.huge
  pointNoProgress = 0
  elapsed = 0
  targetSpeed = clamp(tonumber(data.targetSpeed) or 7, 2, 12)
  timeout = clamp(tonumber(data.timeout) or 14, 5, 90)
  stopAtEnd = data.stopAtEnd == true
  completionRadius = clamp(tonumber(data.completionRadius) or 4, 0.65, 10)
  allowReverse = data.allowReverse ~= false
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
  reverseFanClearance = math.huge
  reverseTrajectoryClearance = math.huge
  reverseRayCount = 0
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
    reverseRescanTimer = 0.05
    local horizon = math.min(math.max(4, remaining + 1.5), 9)
    local rearClearance, trajectory, _, _, _, _, fan =
      scanMotionSpace(speed, -1, reverseSteering, horizon)
    reverseFanClearance = corridorFanClearance(fan, reverseSteering, -1)
    reverseTrajectoryClearance, reverseRayCount = trajectory, #fan
    local alternative = bestFanSteering(fan, -1, horizon)
    if alternative and alternative.clearance > rearClearance + 1.1 and
      math.abs(alternative.steering - reverseSteering) <= 0.85 then
      reverseSteering, rearClearance = alternative.steering, alternative.clearance
      reverseTrajectoryClearance = alternative.trajectory
    end
    local emergencyDistance = 0.72 + speed * 0.22 + speed * speed / 12
    if rearClearance <= emergencyDistance then
      safetyBrake, safetyHolding = 1, true
      reverseStopReason, reverseStopSuccess = "rearBecameBlocked", false
      input.event("steering", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      input.event("throttle", 1, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      input.event("brake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
      return
    end
  end

  local usableRear = math.min(reverseFanClearance, reverseTrajectoryClearance)
  local spaceSpeed = usableRear < math.huge and math.max(0, (usableRear - 0.8) * 0.55) or targetSpeed
  local desiredSpeed = math.min(targetSpeed, spaceSpeed, math.max(0.35, remaining * 0.62))
  local reverseDrive = clamp(0.22 + (desiredSpeed - speed) * 0.22, 0.14, 0.58)
  local reverseStop = speed > desiredSpeed + 0.35 and
    clamp((speed - desiredSpeed) * 0.28, 0, 0.5) or 0
  safetyBrake, safetyHolding = reverseStop, reverseStop > 0.01
  input.event("steering", reverseSteering, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
  input.event("throttle", reverseStop, "FILTER_AI", nil, nil, nil,
    "taxiDriverRecovery")
  input.event("brake", reverseStop > 0 and 0 or reverseDrive, "FILTER_AI", nil, nil, nil,
    "taxiDriverRecovery")
  input.event("parkingbrake", 0, "FILTER_AI", nil, nil, nil, "taxiDriverRecovery")
end

local function updateGFX(dt)
  ensureDriveReady(dt)
  if recoveryMode ~= "reverse" and not active then
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
    pointBestDistance, pointNoProgress = math.huge, 0
    target = points[pointIndex]
    dx = (tonumber(target.x) or 0) - position.x
    dy = (tonumber(target.y) or 0) - position.y
    dz = (tonumber(target.z) or 0) - position.z
    distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  if distance < pointBestDistance - 0.25 then
    pointBestDistance, pointNoProgress = distance, 0
  else
    pointNoProgress = pointNoProgress + math.max(0, number(dt, 0))
  end
  if pointNoProgress >= 3.5 then
    if pointIndex < #points then
      local nextPoint = points[pointIndex + 1]
      local nextDistance = math.sqrt((number(nextPoint.x, 0) - number(position.x, 0)) ^ 2 +
        (number(nextPoint.y, 0) - number(position.y, 0)) ^ 2 +
        (number(nextPoint.z, 0) - number(position.z, 0)) ^ 2)
      if nextDistance + 1 < distance or distance > pointBestDistance + 2 then
        pointIndex, pointBestDistance, pointNoProgress = pointIndex + 1, math.huge, 0
        target = points[pointIndex]
        dx, dy, dz = number(target.x, 0) - position.x, number(target.y, 0) - position.y,
          number(target.z, 0) - position.z
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)
      else finish(false, "waypointNoProgress"); return end
    else finish(false, "waypointNoProgress"); return end
  end
  if pointIndex == #points and distance < completionRadius and not stopAtEnd then
    finish(true, "complete"); return
  end

  local direction = obj:getDirectionVector()
  local planarLength = math.max(0.001, math.sqrt(dx * dx + dy * dy))
  local targetX, targetY = dx / planarLength, dy / planarLength
  local forwardDot = direction.x * targetX + direction.y * targetY
  local reversing = allowReverse and forwardDot < -0.25
  local angle = reversing and angleBetween(-direction.x * targetY + direction.y * targetX,
    -direction.x * targetX - direction.y * targetY) or
    angleBetween(direction.x * targetY - direction.y * targetX, forwardDot)
  local steering = steeringForTravelAngle(angle, reversing and -1 or 1, 1.7, 1)
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
  safetyTimer = safetyTimer - math.max(0, number(dt, 0))
  if safetyTimer <= 0 then
    safetyTimer = 0.05
    local clearance, trajectory, fanClearance, closingSpeed, obstacleId, blocked, fan =
      scanMotionSpace(speed, reversing and -1 or 1, steering, speed * 1.8 + 7)
    safetyObstacleDistance, safetyObstacleClosingSpeed = clearance, closingSpeed
    safetyObstacleId, safetyObstacleDetected = obstacleId, blocked == true
    if reversing then
      reverseFanClearance, reverseTrajectoryClearance, reverseRayCount = fanClearance, trajectory, #fan
    end
  end
  local deceleration = clamp(number(safetyConfig.comfortableDeceleration, 2.8), 1.5, 4.5)
  local clearance = safetyObstacleDistance
  local comfortableDistance = (reversing and 1.15 or 2.1) + speed *
    (reversing and 0.72 or math.min(1.1, number(safetyConfig.timeGap, 2.2) * 0.32)) +
    speed * speed / (2 * deceleration)
  local emergencyDistance = (reversing and 0.7 or 1.1) + speed * 0.15 + speed * speed / 13
  if clearance < comfortableDistance then
    desiredSpeed = math.min(desiredSpeed, math.max(0, (clearance - (reversing and 0.7 or 1.1)) * 0.48))
  end
  local throttle = clamp((desiredSpeed - speed) * 0.22, 0, 0.72)
  local brake = clamp((speed - desiredSpeed) * 0.28, 0, 0.8)
  if reversing then
    throttle = clamp((speed - desiredSpeed) * 0.28, 0, 0.7)
    brake = clamp((desiredSpeed - speed) * 0.22, 0.2, 0.65)
    if clearance <= emergencyDistance then throttle, brake = 1, 0 end
  elseif clearance <= emergencyDistance then
    throttle, brake = 0, 1
  end
  local spaceLimited = clearance < comfortableDistance
  safetyBrake = spaceLimited and (reversing and throttle or brake) or 0
  safetyHolding = safetyBrake > 0.01
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

local function getDebugState()
  local pointDistance = nil
  local target = points[pointIndex]
  if active and target then
    local current = obj:getPosition()
    local dx = number(target.x, 0) - number(current.x, 0)
    local dy = number(target.y, 0) - number(current.y, 0)
    local dz = number(target.z, 0) - number(current.z, 0)
    pointDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  local reverseRemaining = nil
  if active and recoveryMode == "reverse" and reverseStartPosition then
    local current = obj:getPosition()
    local dx = number(current.x, 0) - reverseStartPosition.x
    local dy = number(current.y, 0) - reverseStartPosition.y
    reverseRemaining = math.max(0, reverseTargetDistance - math.sqrt(dx * dx + dy * dy))
  end
  local state = input.state or {}
  return {
    active = active,
    mode = active and recoveryMode or (gearboxOverrideActive and "native" or "inactive"),
    elapsed = elapsed,
    timeout = timeout,
    pointIndex = pointIndex,
    pointCount = #points,
    pointDistance = pointDistance,
    pointBestDistance = pointBestDistance ~= math.huge and pointBestDistance or nil,
    pointNoProgress = pointNoProgress,
    targetSpeed = targetSpeed,
    reversing = active and recoveryMode == "reverse",
    reverseRemaining = reverseRemaining,
    reverseSteering = reverseSteering,
    reverseFanClearance = reverseFanClearance ~= math.huge and reverseFanClearance or nil,
    reverseTrajectoryClearance = reverseTrajectoryClearance ~= math.huge and
      reverseTrajectoryClearance or nil,
    reverseRayCount = reverseRayCount,
    gearboxOverrideActive = gearboxOverrideActive,
    stationaryDriveHold = stationaryDriveHold,
    driveReady = driveReady,
    safetyBrake = safetyBrake,
    safetyHolding = safetyHolding,
    obstacleDistance = safetyObstacleDistance ~= math.huge and safetyObstacleDistance or nil,
    obstacleClosingSpeed = safetyObstacleClosingSpeed,
    obstacleId = safetyObstacleId,
    obstacleDetected = safetyObstacleDetected,
    preflightFrontClearance = preflightFrontClearance,
    preflightRearClearance = preflightRearClearance,
    steering = number(state.steering and state.steering.val, 0),
    throttle = number(state.throttle and state.throttle.val, 0),
    brake = number(state.brake and state.brake.val, 0)
  }
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
M.getDebugState = getDebugState

return M
