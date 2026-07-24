local M = {}

local watching = false
local originalTrigger = nil
local triggerWrapper = nil
local updateTimer = 0
local updateInterval = 0.1
local clearSeconds = 0
local speedLimited = false
local smoothedSpeedLimit = nil
local currentDeceleration = 0
local settings = {
  followingTimeGap = 2.3,
  minimumGap = 4,
  brakingDeceleration = 3.5,
  trajectorySamples = 12,
  routeSpeedMode = "legal",
  targetPos = nil,
  targetDir = nil,
  arrivalRadius = 14,
  maximumArrivalSpeed = 4 / 3.6
}
local state = {
  active = false,
  mode = "stockTrafficGuard",
  obstacleDetected = false,
  safetyHolding = false,
  safetyBrake = 0,
  obstacleDistance = nil,
  obstacleClosingSpeed = nil,
  obstacleId = nil,
  leadSpeed = nil,
  timeToCollision = nil,
  targetSpeed = nil,
  requestedDeceleration = 0,
  appliedDeceleration = 0,
  emergencyBraking = false,
  targetApproachActive = false,
  targetDistance = nil,
  targetSpeedCap = nil,
  trackedVehicleCount = 0,
  curvedPathRisk = false,
  curvedPathRiskTime = nil
}

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function notifyRouteDone()
  obj:queueGameEngineLua(string.format(
    "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onAutopilotRouteDone(%d) end",
    obj:getID()
  ))
end

local function install()
  if not guihooks or type(guihooks.trigger) ~= "function" then return false end
  if triggerWrapper then return true end
  originalTrigger = guihooks.trigger
  triggerWrapper = function(hookName, ...)
    if watching and hookName == "AIStatusChange" then
      local data = select(1, ...)
      if type(data) == "table" and data.category == "route" and
        string.lower(tostring(data.status or "")) == "route done" then
        pcall(notifyRouteDone)
      end
    end
    return originalTrigger(hookName, ...)
  end
  guihooks.trigger = triggerWrapper
  return true
end

local function resetLeadState()
  state.obstacleDetected = false
  state.safetyHolding = false
  state.safetyBrake = 0
  state.obstacleDistance = nil
  state.obstacleClosingSpeed = nil
  state.obstacleId = nil
  state.leadSpeed = nil
  state.timeToCollision = nil
  state.targetSpeed = nil
  state.requestedDeceleration = 0
  state.appliedDeceleration = 0
  state.emergencyBraking = false
  state.curvedPathRisk = false
  state.curvedPathRiskTime = nil
end

local function restoreRouteSpeed()
  if not speedLimited then return end
  ai.setSpeed(nil)
  ai.setSpeedMode(settings.routeSpeedMode)
  speedLimited = false
  smoothedSpeedLimit = nil
  currentDeceleration = 0
end

local function findLeadVehicle()
  if not mapmgr or type(mapmgr.getObjects) ~= "function" then return nil end
  local objects = mapmgr.getObjects() or {}
  local ownData = objects[obj:getID()]
  local position = ownData and ownData.pos or obj:getPosition()
  local velocity = ownData and ownData.vel or obj:getVelocity()
  local direction = obj:getDirectionVector()
  direction:normalize()
  local right = vec3(direction.y, -direction.x, 0)
  right:normalize()
  local egoSpeed = math.max(0, velocity:dot(direction))
  local egoLength = math.max(1, number(obj:getInitialLength(), 4))
  local egoWidth = math.max(1, number(obj:getInitialWidth(), 2))
  local steeringState = input and input.state and input.state.steering
  local steering = clamp(number(steeringState and steeringState.val,
    electrics and electrics.values and electrics.values.steering_input or 0), -1, 1)
  local best
  local tracked = 0

  for id, data in pairs(objects) do
    if id ~= obj:getID() and data and data.pos and data.vel then
      tracked = tracked + 1
      local relative = data.pos - position
      local ahead = relative:dot(direction)
      if ahead > 0 then
        local otherWidth = math.max(1, number(obj:getObjectInitialWidth(id), 2))
        local otherLength = math.max(1, number(obj:getObjectInitialLength(id), 4))
        local corridor = (egoWidth + otherWidth) * 0.5 + 0.25
        local lateral = math.abs(relative:dot(right))
        if lateral <= corridor then
          local gap = math.max(0, ahead - (egoLength + otherLength) * 0.5)
          if not best or gap < best.gap then
            local leadSpeed = math.max(0, data.vel:dot(direction))
            local closingSpeed = math.max(0, egoSpeed - leadSpeed)
            best = {
              id = id,
              gap = gap,
              leadSpeed = leadSpeed,
              closingSpeed = closingSpeed,
              egoSpeed = egoSpeed,
              curvedPathRisk = false
            }
          end
        end

        -- A straight longitudinal corridor misses vehicles swept by the
        -- outside/front corner during a turn. Predict the ego centre along the
        -- current steering arc and compare it with every tracked vehicle's
        -- short-term motion. This remains lightweight: at most twelve scalar
        -- samples per nearby traffic object at the configured observer rate.
        if math.abs(steering) >= 0.08 and ahead <= math.max(45, egoSpeed * 3.5) then
          local wheelbase = egoLength * 0.65
          local steeringAngle = math.abs(steering) * 0.55
          local turnRadius = math.max(egoLength * 0.85,
            wheelbase / math.max(0.08, math.tan(steeringAngle)))
          local turnSide = steering > 0 and -1 or 1
          local relativeForward, relativeLateral =
            relative:dot(direction), relative:dot(right)
          local otherForwardSpeed, otherLateralSpeed =
            data.vel:dot(direction), data.vel:dot(right)
          local horizon = clamp(1.2 + egoSpeed * 0.1, 1.5, 3.5)
          local collisionRadius =
            math.sqrt((egoLength * 0.34) ^ 2 + (egoWidth * 0.5) ^ 2) +
            math.sqrt((otherLength * 0.34) ^ 2 + (otherWidth * 0.5) ^ 2)
          local initialSeparation = math.sqrt(
            relativeForward ^ 2 + relativeLateral ^ 2)
          local minimumSeparation, closestTime = math.huge, nil
          for sample = 1, settings.trajectorySamples do
            local time = horizon * sample / settings.trajectorySamples
            local yaw = math.min(1.45, egoSpeed * time / turnRadius)
            local egoForward = math.sin(yaw) * turnRadius
            local egoLateral = turnSide * (1 - math.cos(yaw)) * turnRadius
            local deltaForward =
              relativeForward + otherForwardSpeed * time - egoForward
            local deltaLateral =
              relativeLateral + otherLateralSpeed * time - egoLateral
            local separation = math.sqrt(
              deltaForward * deltaForward + deltaLateral * deltaLateral)
            if separation < minimumSeparation then
              minimumSeparation, closestTime = separation, time
            end
          end
          local clearance = minimumSeparation - collisionRadius
          local predictionMargin = math.max(2.5, egoSpeed * 0.35)
          if closestTime and clearance <= predictionMargin then
            local closingSpeed = math.max(0,
              (initialSeparation - minimumSeparation) / closestTime)
            local candidate = {
              id = id,
              gap = math.max(0, clearance),
              leadSpeed = math.max(0, egoSpeed - closingSpeed),
              closingSpeed = closingSpeed,
              egoSpeed = egoSpeed,
              curvedPathRisk = true,
              curvedPathRiskTime = closestTime
            }
            if not best or candidate.gap < best.gap then best = candidate end
          end
        end
      end
    end
  end
  state.trackedVehicleCount = tracked
  return best
end

local function findTargetApproach()
  if not settings.targetPos or not settings.targetDir then return nil end
  local position = obj:getPosition()
  local velocity = obj:getVelocity()
  local direction = obj:getDirectionVector()
  direction:normalize()
  local targetDirection = vec3(settings.targetDir)
  targetDirection.z = 0
  if targetDirection:length() < 0.1 then return nil end
  targetDirection:normalize()
  local alignment = direction:dot(targetDirection)
  local relative = settings.targetPos - position
  local distance = relative:length()
  state.targetDistance = distance
  if alignment < 0.45 then return nil end
  local right = vec3(direction.y, -direction.x, 0)
  right:normalize()
  local ahead = relative:dot(direction)
  local lateral = math.abs(relative:dot(right))
  if ahead < -settings.arrivalRadius or
    lateral > settings.arrivalRadius + 8 then return nil end
  local egoSpeed = math.max(0, velocity:dot(direction))
  local deceleration = math.max(0.1, settings.brakingDeceleration)
  local brakingRange = math.max(0,
    (egoSpeed * egoSpeed - settings.maximumArrivalSpeed ^ 2) /
    (2 * deceleration))
  local approachRange = math.max(45,
    brakingRange + settings.arrivalRadius + 10)
  if distance > approachRange then return nil end
  local remaining = math.max(0, distance - settings.arrivalRadius)
  local desiredSpeed = math.sqrt(
    settings.maximumArrivalSpeed ^ 2 + 2 * deceleration * remaining)
  desiredSpeed = math.min(egoSpeed, desiredSpeed)
  local requestedDeceleration = math.max(0,
    (egoSpeed * egoSpeed - desiredSpeed * desiredSpeed) /
    (2 * math.max(1, remaining)))
  return {
    distance = distance,
    egoSpeed = egoSpeed,
    desiredSpeed = desiredSpeed,
    requestedDeceleration = clamp(
      requestedDeceleration, 0, settings.brakingDeceleration)
  }
end

local function applySmoothedLimit(desiredSpeed, requestedDeceleration,
    emergency, egoSpeed)
  if not smoothedSpeedLimit then smoothedSpeedLimit = egoSpeed end
  if emergency then
    smoothedSpeedLimit = 0
    currentDeceleration = 8.5
  elseif desiredSpeed < smoothedSpeedLimit then
    local jerkLimit = 2.5
    local decelerationDelta = jerkLimit * updateInterval
    if currentDeceleration < requestedDeceleration then
      currentDeceleration = math.min(
        requestedDeceleration, currentDeceleration + decelerationDelta)
    else
      currentDeceleration = math.max(
        requestedDeceleration, currentDeceleration - decelerationDelta)
    end
    smoothedSpeedLimit = math.max(desiredSpeed,
      smoothedSpeedLimit - currentDeceleration * updateInterval)
  else
    currentDeceleration = math.max(0, currentDeceleration - 3 * updateInterval)
    smoothedSpeedLimit = math.min(desiredSpeed,
      smoothedSpeedLimit + 1.5 * updateInterval)
  end
  ai.setSpeed(smoothedSpeedLimit)
  ai.setSpeedMode("limit")
  speedLimited = true
  state.targetSpeed = smoothedSpeedLimit
  state.requestedDeceleration = requestedDeceleration
  state.appliedDeceleration = emergency and 8.5 or currentDeceleration
  state.emergencyBraking = emergency
end

local function applyTrafficGuard()
  state.targetDistance = nil
  local lead = findLeadVehicle()
  local targetApproach = findTargetApproach()
  state.targetApproachActive = targetApproach ~= nil
  state.targetSpeedCap = targetApproach and targetApproach.desiredSpeed or nil
  if not lead then
    clearSeconds = clearSeconds + updateInterval
    resetLeadState()
    if targetApproach then
      clearSeconds = 0
      applySmoothedLimit(targetApproach.desiredSpeed,
        targetApproach.requestedDeceleration, false, targetApproach.egoSpeed)
      state.targetApproachActive = true
      state.targetDistance = targetApproach.distance
      state.targetSpeedCap = targetApproach.desiredSpeed
      return
    end
    if speedLimited and smoothedSpeedLimit then
      currentDeceleration = math.max(0, currentDeceleration - 3 * updateInterval)
      smoothedSpeedLimit = smoothedSpeedLimit + 1.5 * updateInterval
      ai.setSpeed(smoothedSpeedLimit)
      ai.setSpeedMode("limit")
      state.targetSpeed = smoothedSpeedLimit
    end
    if clearSeconds >= 1 then restoreRouteSpeed() end
    return
  end

  local brakingDistance = lead.closingSpeed * lead.closingSpeed /
    (2 * math.max(0.1, settings.brakingDeceleration))
  local desiredGap = settings.minimumGap +
    lead.egoSpeed * settings.followingTimeGap + brakingDistance
  local gapDeficit = desiredGap - lead.gap
  local timeToCollision = lead.closingSpeed > 0.1 and
    lead.gap / lead.closingSpeed or math.huge
  local shouldLimit = gapDeficit > 0 or timeToCollision < 4.5

  state.obstacleDetected = true
  state.obstacleDistance = lead.gap
  state.obstacleClosingSpeed = lead.closingSpeed
  state.obstacleId = lead.id
  state.leadSpeed = lead.leadSpeed
  state.timeToCollision = timeToCollision < math.huge and timeToCollision or nil
  state.curvedPathRisk = lead.curvedPathRisk == true
  state.curvedPathRiskTime = lead.curvedPathRiskTime

  if not shouldLimit then
    clearSeconds = clearSeconds + updateInterval
    state.safetyHolding = false
    state.safetyBrake = 0
    state.requestedDeceleration = 0
    state.appliedDeceleration = 0
    state.emergencyBraking = false
    if targetApproach then
      clearSeconds = 0
      applySmoothedLimit(targetApproach.desiredSpeed,
        targetApproach.requestedDeceleration, false, targetApproach.egoSpeed)
      return
    end
    currentDeceleration = math.max(0, currentDeceleration - 3 * updateInterval)
    if speedLimited and smoothedSpeedLimit then
      smoothedSpeedLimit = smoothedSpeedLimit + 1.5 * updateInterval
      ai.setSpeed(smoothedSpeedLimit)
      ai.setSpeedMode("limit")
      state.targetSpeed = smoothedSpeedLimit
    else
      state.targetSpeed = nil
    end
    if clearSeconds >= 1 then restoreRouteSpeed() end
    return
  end

  clearSeconds = 0
  local severity = clamp(gapDeficit / math.max(1, desiredGap), 0, 1)
  local usableGap = math.max(0.25, lead.gap - settings.minimumGap * 0.5)
  local requiredDeceleration = lead.closingSpeed * lead.closingSpeed /
    (2 * usableGap)
  local emergency = lead.closingSpeed > 0.5 and
    (timeToCollision < 0.55 or requiredDeceleration >= 8.5)
  local gapRange = math.max(1, desiredGap - settings.minimumGap)
  local gapProgress = clamp(
    (lead.gap - settings.minimumGap) / gapRange, 0, 1)
  local desiredSpeed = math.max(0, lead.leadSpeed +
    lead.closingSpeed * math.sqrt(gapProgress))
  local requestedDeceleration = clamp(math.max(
    requiredDeceleration,
    settings.brakingDeceleration * severity
  ), 0, settings.brakingDeceleration)
  if emergency then
    desiredSpeed, severity, requestedDeceleration = 0, 1, 8.5
  end
  if targetApproach and targetApproach.desiredSpeed < desiredSpeed then
    desiredSpeed = targetApproach.desiredSpeed
    requestedDeceleration = math.max(
      requestedDeceleration, targetApproach.requestedDeceleration)
  end
  applySmoothedLimit(desiredSpeed, requestedDeceleration,
    emergency, lead.egoSpeed)
  state.safetyHolding = true
  state.safetyBrake = severity
end

local function watch(config)
  config = type(config) == "table" and config or {}
  restoreRouteSpeed()
  updateInterval = clamp(number(config.updateInterval, 0.1), 0.08, 0.25)
  settings.followingTimeGap = clamp(number(config.followingTimeGap, 2.3), 1, 4)
  settings.minimumGap = clamp(number(config.minimumGap, 4), 2, 10)
  settings.brakingDeceleration = clamp(number(config.brakingDeceleration, 3.5), 2, 8)
  settings.trajectorySamples = math.floor(
    clamp(number(config.trajectorySamples, 12), 4, 12) + 0.5)
  settings.routeSpeedMode = config.routeSpeedMode == "off" and "off" or "legal"
  settings.targetPos = config.targetX ~= nil and
    vec3(number(config.targetX, 0), number(config.targetY, 0),
      number(config.targetZ, 0)) or nil
  settings.targetDir = config.targetDirX ~= nil and
    vec3(number(config.targetDirX, 0), number(config.targetDirY, 0), 0) or nil
  settings.arrivalRadius = clamp(number(config.arrivalRadius, 14), 4, 30)
  settings.maximumArrivalSpeed =
    clamp(number(config.maximumArrivalSpeed, 4 / 3.6), 0.5, 3)
  watching = true
  state.active = true
  updateTimer, clearSeconds, smoothedSpeedLimit = 0, 0, nil
  speedLimited, currentDeceleration = false, 0
  resetLeadState()
  state.targetApproachActive = false
  state.targetDistance = nil
  state.targetSpeedCap = nil
  if mapmgr and type(mapmgr.enableTracking) == "function" then mapmgr.enableTracking() end
  return install()
end

local function unwatch()
  watching = false
  state.active = false
  restoreRouteSpeed()
  resetLeadState()
  state.targetApproachActive = false
  state.targetDistance = nil
  state.targetSpeedCap = nil
  if guihooks and triggerWrapper and guihooks.trigger == triggerWrapper then
    guihooks.trigger = originalTrigger
  end
  originalTrigger = nil
  triggerWrapper = nil
end

local function updateGFX(dt)
  if not watching then return end
  updateTimer = updateTimer + math.max(0, number(dt, 0))
  if updateTimer < updateInterval then return end
  updateTimer = updateTimer - updateInterval
  applyTrafficGuard()
end

local function getDebugState()
  local result = {}
  for key, value in pairs(state) do result[key] = value end
  result.followingTimeGap = settings.followingTimeGap
  result.minimumGap = settings.minimumGap
  result.updateInterval = updateInterval
  result.trajectorySamples = settings.trajectorySamples
  return result
end

local function onExtensionUnloaded()
  unwatch()
end

M.watch = watch
M.unwatch = unwatch
M.updateGFX = updateGFX
M.getDebugState = getDebugState
M.onExtensionUnloaded = onExtensionUnloaded

return M
