-- TaxiDriver safety supervisor for BeamNG 0.39 stock AI.
--
-- Stock ai.lua remains the sole owner of steering, throttle and braking. This
-- extension only supplies bounded speed caps and invokes native high-level
-- manoeuvres after conservative safety gates have passed.

local M = {}

local watching = false
local updateTimer = 0
local staticTimer = 0
local elapsed = 0
local clearSeconds = 0
local currentInterval = 0.1
local routeDoneNotified = false
local speedLimited = false
local smoothedSpeedLimit = nil
local currentDeceleration = 0
local dimensionCache = {}
local timingSamples = {}
local timingCursor = 0
local lastTimingPercentileAt = 0
local lastThreatId = nil
local lastThreatKind = nil
local stableThreatScans = 0
local staticCandidateDistance = nil
local staticStableScans = 0
local leadCandidateId = nil
local leadCandidateSeconds = 0
local racingStartedAt = -math.huge
local racingCooldownUntil = -math.huge
local lastEvasionAt = -math.huge
local parkingRequested = false
local parkingConfirmed = false
local parkingCommitRequested = false
local parkingStableChecks = 0
local parkingGearTarget = nil
local parkingGearboxBehavior = nil

local capabilities = {}
local settings = {
  followingTimeGap = 2.3,
  minimumGap = 4,
  brakingDeceleration = 3.5,
  predictiveWarningScale = 1,
  emergencyDeceleration = 8,
  routeSpeedMode = "legal",
  targetPos = nil,
  targetDir = nil,
  arrivalRadius = 14,
  maximumArrivalSpeed = 0,
  broadPhaseRange = 100,
  maximumTrackedVehicles = 16,
  predictionHorizon = 5,
  overtakeLeadHold = 1.5,
  overtakeMaximumSeconds = 6,
  overtakeCooldownSeconds = 12,
  overtakeMinimumTargetDistance = 80,
  evasionCooldownSeconds = 3,
  allowOvertaking = false
}

local state = {
  active = false,
  sessionId = 0,
  routeRevision = 0,
  sequence = 0,
  mode = "inactive",
  supervisorMode = "inactive",
  selectedManeuver = "none",
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
  scanVehicleCount = 0,
  curvedPathRisk = false,
  curvedPathRiskTime = nil,
  threatId = nil,
  threatKind = nil,
  threatConfidence = 0,
  confidence = 0,
  ttc = nil,
  tCPA = nil,
  dCPA = nil,
  threatLateral = nil,
  threatPredictedLateral = nil,
  threatLateralClearance = nil,
  requiredDeceleration = 0,
  speedCap = nil,
  speedCapSource = nil,
  staticClearance = nil,
  staticMaxDistance = nil,
  staticHitCount = 0,
  staticCenterClearance = nil,
  overtaking = false,
  overtakeState = "idle",
  overtakeReason = "inactive",
  nativeRacing = false,
  parked = false,
  parkingConfirmed = false,
  parkingRequested = false,
  parkingGearTarget = nil,
  parkingGearActual = nil,
  parkingGearConfirmed = false,
  parkingBrakeConfirmed = false,
  parkingGearboxBehavior = nil,
  status = "inactive",
  updateInterval = 0.1,
  updateTimeUs = 0,
  updateAverageUs = 0,
  updateP95Us = 0,
  capabilities = capabilities
}

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function clock()
  if type(os.clockhp) == "function" then return os.clockhp() end
  return os.clock()
end

local function length2(x, y)
  return math.sqrt(x * x + y * y)
end

local function planarUnit(value, fallbackX, fallbackY)
  local x = number(value and value.x, fallbackX or 1)
  local y = number(value and value.y, fallbackY or 0)
  local length = length2(x, y)
  if length < 0.001 then return fallbackX or 1, fallbackY or 0 end
  return x / length, y / length
end

local function smoothStep(value)
  value = clamp(value, 0, 1)
  return value * value * (3 - 2 * value)
end

local function detectCapabilities()
  capabilities.setSpeed = ai and type(ai.setSpeed) == "function" or false
  capabilities.setSpeedMode = ai and type(ai.setSpeedMode) == "function" or false
  capabilities.setRacing = ai and type(ai.setRacing) == "function" or false
  capabilities.laneChange = ai and type(ai.laneChange) == "function" or false
  capabilities.getEdgeLaneConfig = ai and type(ai.getEdgeLaneConfig) == "function" or false
  capabilities.setStopPoint = ai and type(ai.setStopPoint) == "function" or false
  capabilities.staticRay = obj and type(obj.castRayStatic) == "function" and
    type(vec3) == "function" or false
  capabilities.mapObjects = mapmgr and type(mapmgr.getObjects) == "function" or false
end

local function safeAiCall(name, ...)
  local fn = ai and ai[name]
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, ...)
  return ok == true
end

local function setNativeRacing(value, force)
  value = value == true
  if not force and state.nativeRacing == value then return true end
  if not capabilities.setRacing then
    state.nativeRacing = false
    return false
  end
  local ok = safeAiCall("setRacing", value)
  if ok then state.nativeRacing = value end
  return ok
end

local function parkingInput(name, value)
  if not input or type(input.event) ~= "function" then return false end
  -- Pedals must stay on BeamNG's AI channel. FILTER_DIRECT brake input is an
  -- Arcade-mode reverse command once native AI is disabled. The parking brake
  -- uses smartParkingBrake/FILTER_DIRECT separately below.
  local filter = FILTER_AI or "FILTER_AI"
  return pcall(input.event, name, value, filter, nil, nil, nil,
    "taxiDriverAiParking")
end

local function mainController()
  return controller and controller.mainController or nil
end

local function controllerState()
  local main = mainController()
  if not main or type(main.getState) ~= "function" then return nil end
  local ok, result = pcall(main.getState)
  return ok and type(result) == "table" and result or nil
end

local function setParkingBrake(value)
  local main = mainController()
  local filter = FILTER_DIRECT or "FILTER_DIRECT"
  if main and type(main.smartParkingBrake) == "function" then
    local ok = pcall(main.smartParkingBrake, value, filter, true)
    if ok then return true end
  end
  return parkingInput("parkingbrake", value)
end

local function restoreParkingGearboxBehavior()
  local main = mainController()
  if parkingGearboxBehavior and parkingGearboxBehavior ~= "" and main and
    type(main.setGearboxMode) == "function" and
    tostring(main.gearboxBehavior or "") ~= parkingGearboxBehavior then
    pcall(main.setGearboxMode, parkingGearboxBehavior)
  end
  parkingGearboxBehavior = nil
end

local function releaseParkingInputs()
  parkingInput("throttle", 0)
  parkingInput("brake", 0)
  setParkingBrake(0)
end

local function holdParkingGearboxBehavior()
  local main = mainController()
  local current = controllerState()
  if not main or not current then return current end
  if parkingGearboxBehavior == nil then
    parkingGearboxBehavior = tostring(main.gearboxBehavior or current.grb_bhv or "")
  end
  -- In Arcade, the brake input becomes reverse throttle around zero speed.
  -- Parking therefore owns Realistic behavior from the first braking frame,
  -- not only after the vehicle has already stopped.
  if tostring(main.gearboxBehavior or current.grb_bhv or "") == "arcade" and
    type(main.setGearboxMode) == "function" then
    pcall(main.setGearboxMode, "realistic")
    current = controllerState() or current
  end
  state.parkingGearboxBehavior = parkingGearboxBehavior
  return current
end

local function parkingBrakeValue()
  local inputValue = number(input and input.state and input.state.parkingbrake and
    input.state.parkingbrake.val, 0)
  local electricsValue = number(electrics and electrics.values and
    electrics.values.parkingbrake, 0)
  return math.max(inputValue, electricsValue)
end

local function selectParkingGear()
  local main = mainController()
  if not main or type(main.setState) ~= "function" then
    parkingGearTarget = nil
    state.parkingGearTarget = nil
    state.status = "parkingTransmissionUnavailable"
    return false
  end
  local current = holdParkingGearboxBehavior()
  if not current then
    parkingGearTarget = nil
    state.parkingGearTarget = nil
    state.status = "parkingTransmissionUnknown"
    return false
  end
  -- BeamNG 0.39 Arcade forcibly changes a stationary running automatic from
  -- P to N and may auto-select a direction for manuals from pedal input. The
  -- explicit parking selection remains in Realistic until the next AI route.
  local command
  if current.grb_mde ~= nil then
    parkingGearTarget = "P"
    command = {grb_mde = "P"}
  elseif current.grb_idx ~= nil then
    parkingGearTarget = "N"
    command = {grb_idx = 0}
  else
    parkingGearTarget = nil
    state.parkingGearTarget = nil
    state.status = "parkingTransmissionUnsupported"
    return false
  end
  local ok = pcall(main.setState, command)
  state.parkingGearTarget = parkingGearTarget
  state.parkingGearboxBehavior = parkingGearboxBehavior
  return ok == true
end

local function readParkingGear()
  local current = controllerState()
  local values = electrics and electrics.values or {}
  local rawGear = values.gear
  local actual = string.upper(tostring(
    rawGear ~= nil and rawGear or values.gearName or ""))
  -- Manual gearboxes in BeamNG 0.39 expose neutral as numeric gear=0 and
  -- gearIndex=0 rather than the display string "N" used by some controllers.
  if number(rawGear, math.huge) == 0 and
    number(values.gearIndex, math.huge) == 0 then
    actual = "N"
  end
  local confirmed = false
  if parkingGearTarget == "P" then
    confirmed = current and tostring(current.grb_mde) == "P" and actual == "P"
  elseif parkingGearTarget == "N" then
    confirmed = current and number(current.grb_idx, math.huge) == 0 and
      number(values.gearIndex, math.huge) == 0 and actual == "N"
  end
  return actual, confirmed == true
end

local function updateParkingConfirmation()
  local speed = math.abs(number(electrics and electrics.values and
    electrics.values.wheelspeed, math.huge))
  local actual, gearConfirmed = readParkingGear()
  local brakeConfirmed = parkingBrakeValue() >= 0.9
  state.parkingGearActual = actual
  state.parkingGearConfirmed = gearConfirmed
  state.parkingBrakeConfirmed = brakeConfirmed
  if parkingCommitRequested and speed <= 0.15 and gearConfirmed and brakeConfirmed then
    parkingStableChecks = parkingStableChecks + 1
  else
    parkingStableChecks = 0
  end
  if parkingStableChecks < 2 then return false end
  parkingConfirmed = true
  state.parkingRequested = true
  state.parkingConfirmed = true
  state.parked = true
  state.selectedManeuver = "parked"
  state.supervisorMode = "parked"
  state.mode = "parked"
  state.status = "parked"
  state.emergencyBraking = false
  state.safetyHolding = true
  state.safetyBrake = 1
  return true
end

local function controlMatches(data)
  data = type(data) == "table" and data or {}
  if data.sessionId ~= nil and tostring(data.sessionId) ~= tostring(state.sessionId) then
    return false
  end
  if data.routeRevision ~= nil and
    number(data.routeRevision, -1) ~= number(state.routeRevision, -2) then return false end
  if data.sequence ~= nil then
    state.sequence = math.max(number(state.sequence, 0), number(data.sequence, 0))
  end
  return true
end

local function restoreRouteSpeed()
  if capabilities.setSpeed then safeAiCall("setSpeed", nil) end
  if capabilities.setSpeedMode then
    safeAiCall("setSpeedMode", settings.routeSpeedMode)
  end
  speedLimited = false
  smoothedSpeedLimit = nil
  currentDeceleration = 0
  state.targetSpeed = nil
  state.speedCap = nil
  state.speedCapSource = nil
end

local function resetTransientState()
  state.mode = watching and "cruise" or "inactive"
  state.supervisorMode = state.mode
  state.selectedManeuver = "none"
  state.obstacleDetected = false
  state.safetyHolding = false
  state.safetyBrake = 0
  state.obstacleDistance = nil
  state.obstacleClosingSpeed = nil
  state.obstacleId = nil
  state.leadSpeed = nil
  state.timeToCollision = nil
  state.requestedDeceleration = 0
  state.appliedDeceleration = 0
  state.emergencyBraking = false
  state.targetApproachActive = false
  state.targetDistance = nil
  state.targetSpeedCap = nil
  state.trackedVehicleCount = 0
  state.scanVehicleCount = 0
  state.curvedPathRisk = false
  state.curvedPathRiskTime = nil
  state.threatId = nil
  state.threatKind = nil
  state.threatConfidence = 0
  state.confidence = 0
  state.ttc = nil
  state.tCPA = nil
  state.dCPA = nil
  state.threatLateral = nil
  state.threatPredictedLateral = nil
  state.threatLateralClearance = nil
  state.requiredDeceleration = 0
  state.staticClearance = nil
  state.staticMaxDistance = nil
  state.staticHitCount = 0
  state.staticCenterClearance = nil
  state.overtaking = false
  state.overtakeState = "idle"
  state.overtakeReason = watching and "noLead" or "inactive"
  state.parked = parkingConfirmed == true
  state.parkingConfirmed = parkingConfirmed == true
  state.parkingRequested = parkingRequested == true
  state.parkingGearTarget = parkingGearTarget
  state.parkingGearActual = nil
  state.parkingGearConfirmed = false
  state.parkingBrakeConfirmed = false
  state.parkingGearboxBehavior = parkingGearboxBehavior
  state.status = state.supervisorMode
end

local function objectDimensions(id)
  local key = tostring(id)
  local cached = dimensionCache[key]
  if cached then return cached.length, cached.width end
  local length, width = 4.5, 2
  if obj and type(obj.getObjectInitialLength) == "function" then
    local ok, value = pcall(obj.getObjectInitialLength, obj, id)
    if ok and number(value, 0) > 0 then length = number(value, length) end
  end
  if obj and type(obj.getObjectInitialWidth) == "function" then
    local ok, value = pcall(obj.getObjectInitialWidth, obj, id)
    if ok and number(value, 0) > 0 then width = number(value, width) end
  end
  dimensionCache[key] = {length = length, width = width}
  return length, width
end

local function ownDimensions()
  local length, width = 4.5, 2
  if obj and type(obj.getInitialLength) == "function" then
    local ok, value = pcall(obj.getInitialLength, obj)
    if ok and number(value, 0) > 0 then length = number(value, length) end
  end
  if obj and type(obj.getInitialWidth) == "function" then
    local ok, value = pcall(obj.getInitialWidth, obj)
    if ok and number(value, 0) > 0 then width = number(value, width) end
  end
  return length, width
end

local function vehicleContext()
  if not obj then return nil end
  local position = obj:getPosition()
  local velocity = obj:getVelocity()
  local direction = obj:getDirectionVector()
  local forwardX, forwardY = planarUnit(direction, 1, 0)
  local rightX, rightY = forwardY, -forwardX
  local velocityX, velocityY = number(velocity and velocity.x, 0),
    number(velocity and velocity.y, 0)
  local speed = math.max(0, velocityX * forwardX + velocityY * forwardY)
  local absoluteSpeed = length2(velocityX, velocityY)
  local length, width = ownDimensions()
  return {
    x = number(position and position.x, 0),
    y = number(position and position.y, 0),
    z = number(position and position.z, 0),
    velocityX = velocityX,
    velocityY = velocityY,
    forwardX = forwardX,
    forwardY = forwardY,
    rightX = rightX,
    rightY = rightY,
    speed = math.max(speed, absoluteSpeed * 0.25),
    absoluteSpeed = absoluteSpeed,
    length = length,
    width = width
  }
end

local function objectDirection(id, data)
  local direction = data and (data.dirVec or data.dir)
  if not direction and obj and type(obj.getObjectDirectionVector) == "function" then
    local ok, value = pcall(obj.getObjectDirectionVector, obj, id)
    if ok then direction = value end
  end
  return planarUnit(direction, 1, 0)
end

local function collectNearby(context)
  local result = {}
  if not capabilities.mapObjects then return result end
  local ownId = obj:getID()
  local rangeSq = settings.broadPhaseRange * settings.broadPhaseRange
  local objects = mapmgr.getObjects() or {}
  for id, data in pairs(objects) do
    if id ~= ownId and data and data.pos and data.vel then
      local dx = number(data.pos.x, 0) - context.x
      local dy = number(data.pos.y, 0) - context.y
      local dz = number(data.pos.z, 0) - context.z
      local distSq = dx * dx + dy * dy
      -- The CPA model is planar. Exclude traffic on overpasses/underpasses so
      -- vertically separated roads cannot produce a phantom collision.
      if distSq <= rangeSq and math.abs(dz) <= 4 then
        local length, width = objectDimensions(id)
        local dirX, dirY = objectDirection(id, data)
        local velocityX = number(data.vel.x, 0)
        local velocityY = number(data.vel.y, 0)
        result[#result + 1] = {
          id = id,
          distSq = distSq,
          dx = dx,
          dy = dy,
          dz = dz,
          longitudinal = dx * context.forwardX + dy * context.forwardY,
          lateral = dx * context.rightX + dy * context.rightY,
          velocityX = velocityX,
          velocityY = velocityY,
          longitudinalSpeed = velocityX * context.forwardX + velocityY * context.forwardY,
          lateralSpeed = velocityX * context.rightX + velocityY * context.rightY,
          directionX = dirX,
          directionY = dirY,
          alignment = dirX * context.forwardX + dirY * context.forwardY,
          length = length,
          width = width
        }
      end
    end
  end
  table.sort(result, function(a, b) return a.distSq < b.distSq end)
  while #result > settings.maximumTrackedVehicles do table.remove(result) end
  return result
end

local function evaluateTraffic(context, objects)
  local lead, threat = nil, nil
  local horizon = settings.predictionHorizon
  local egoLateralSpeed = context.velocityX * context.rightX +
    context.velocityY * context.rightY
  for _, candidate in ipairs(objects) do
    local relVelocityX = candidate.velocityX - context.velocityX
    local relVelocityY = candidate.velocityY - context.velocityY
    local relativeSpeedSq = relVelocityX * relVelocityX + relVelocityY * relVelocityY
    local tCPA = 0
    if relativeSpeedSq > 0.01 then
      tCPA = clamp(-(candidate.dx * relVelocityX + candidate.dy * relVelocityY) /
        relativeSpeedSq, 0, horizon)
    end
    local cpaX = candidate.dx + relVelocityX * tCPA
    local cpaY = candidate.dy + relVelocityY * tCPA
    local cpaLong = cpaX * context.forwardX + cpaY * context.forwardY
    local cpaLat = cpaX * context.rightX + cpaY * context.rightY
    local requiredLong = (context.length + candidate.length) * 0.45 + 0.6
    local requiredLat = (context.width + candidate.width) * 0.5 + 0.35
    local normalized = math.sqrt((cpaLong / requiredLong) ^ 2 +
      (cpaLat / requiredLat) ^ 2)
    local dCPA = length2(cpaX, cpaY) - math.min(requiredLong, requiredLat)
    local closingSpeed = context.speed - candidate.longitudinalSpeed
    local gap = candidate.longitudinal - requiredLong
    local ttc = nil
    if candidate.longitudinal > -requiredLong and closingSpeed > 0.1 then
      local longitudinalTtc = math.max(0, gap) / closingSpeed
      local predictedLateral = candidate.lateral +
        (candidate.lateralSpeed -
          (context.velocityX * context.rightX + context.velocityY * context.rightY)) *
        longitudinalTtc
      if longitudinalTtc <= horizon and math.abs(predictedLateral) <= requiredLat then
        ttc = longitudinalTtc
      end
    end
    if not ttc and tCPA > 0 and tCPA <= horizon and normalized <= 1 then ttc = tCPA end

    local sameDirection = candidate.alignment > 0.7
    local inLane = math.abs(candidate.lateral) <= requiredLat
    if sameDirection and candidate.longitudinal > 0 and inLane and
      (not lead or candidate.longitudinal < lead.longitudinal) then
      lead = candidate
      lead.gap = math.max(0, gap)
      lead.closingSpeed = math.max(0, closingSpeed)
      lead.ttc = lead.closingSpeed > 0.1 and lead.gap / lead.closingSpeed or nil
    end

    if ttc and candidate.longitudinal > -context.length then
      local kind = candidate.alignment < -0.7 and "oncoming" or
        candidate.alignment > 0.7 and "lead" or "crossing"
      local relativeLateralSpeed = candidate.lateralSpeed - egoLateralSpeed
      local predictedLateral = candidate.lateral + relativeLateralSpeed * ttc
      local relativeSpeed = math.sqrt(relativeSpeedSq)
      local collisionCorridor =
        (context.width + candidate.width) * 0.5 + 0.15
      local lateralClearance = math.abs(candidate.lateral) - collisionCorridor

      -- Two vehicles following their own lanes through a bend look as if
      -- their constant-velocity vectors will intersect. Treat an oncoming car
      -- as a collision threat only after its centre enters the physical ego
      -- corridor. A genuinely head-on car is still detected several seconds
      -- ahead, while normal traffic in the opposing lane no longer triggers
      -- predictive braking on every curve.
      if kind == "oncoming" then
        if math.abs(candidate.lateral) > collisionCorridor then ttc = nil end
      elseif kind == "crossing" and relativeSpeed < 1 then
        ttc = nil
      end

      if ttc then
        local entry = {
          id = candidate.id,
          kind = kind,
          ttc = ttc,
          tCPA = tCPA,
          dCPA = dCPA,
          gap = math.max(0.1, gap),
          closingSpeed = math.max(0, closingSpeed),
          longitudinal = candidate.longitudinal,
          lateral = candidate.lateral,
          longitudinalSpeed = candidate.longitudinalSpeed,
          predictedLateral = predictedLateral,
          lateralClearance = lateralClearance,
          relativeSpeed = relativeSpeed,
          candidate = candidate
        }
        if not threat or entry.ttc < threat.ttc or
          (entry.ttc == threat.ttc and entry.dCPA < threat.dCPA) then
          threat = entry
        end
      end
    end
  end
  return lead, threat
end

local function updateThreatConfidence(threat)
  if threat and tostring(threat.id) == tostring(lastThreatId) and
    threat.kind == lastThreatKind then
    stableThreatScans = stableThreatScans + 1
  elseif threat then
    lastThreatId, lastThreatKind, stableThreatScans = threat.id, threat.kind, 1
  else
    lastThreatId, lastThreatKind, stableThreatScans = nil, nil, 0
  end
  local confidence = clamp(stableThreatScans / 3, 0, 1)
  local imminentOncomingOverlap = threat and threat.kind == "oncoming" and
    threat.ttc <= 1.1 and number(threat.lateralClearance, math.huge) <= 0.1 and
    number(threat.dCPA, math.huge) <= 0.1
  if threat and (threat.ttc <= 0.75 or imminentOncomingOverlap) then
    confidence = 1
  end
  state.threatConfidence = confidence
  state.confidence = confidence
  return confidence
end

local function targetApproach(context)
  if not settings.targetPos then return nil end
  local dx = number(settings.targetPos.x, 0) - context.x
  local dy = number(settings.targetPos.y, 0) - context.y
  local dz = number(settings.targetPos.z, 0) - context.z
  local targetDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
  state.targetDistance = targetDistance
  local ahead = dx * context.forwardX + dy * context.forwardY
  local lateral = math.abs(dx * context.rightX + dy * context.rightY)
  if ahead < -settings.arrivalRadius or lateral > settings.arrivalRadius + 10 then return nil end
  local deceleration = math.max(0.1, settings.brakingDeceleration)
  local brakingRange = math.max(0,
    (context.speed * context.speed - settings.maximumArrivalSpeed ^ 2) /
    (2 * deceleration))
  if targetDistance > math.max(50, brakingRange + settings.arrivalRadius + 12) then return nil end
  local remaining = math.max(0, targetDistance - settings.arrivalRadius)
  -- Arrival is a full stop, not a rolling gameplay trigger. A non-zero floor
  -- lets an automatic transmission creep past the pickup while still being
  -- considered "arrived" by the order state machine.
  local cap = math.sqrt(2 * deceleration * remaining)
  local required = math.max(0,
    (context.speed * context.speed - cap * cap) / (2 * math.max(1, remaining)))
  return {distance = targetDistance, cap = cap,
    requestedDeceleration = clamp(required, 0, deceleration)}
end

local function scanStatic(context, road)
  if not capabilities.staticRay or not road or road.radius <= 0 or
    math.abs(road.alignment) < 0.985 then return nil end
  local direction = obj:getDirectionVector()
  local up = type(obj.getDirectionVectorUp) == "function" and
    obj:getDirectionVectorUp() or vec3(0, 0, 1)
  local right = vec3(context.rightX, context.rightY, 0)
  local maximumDistance = clamp(12 + context.speed * 1.25, 12, 38)
  if road.remainingEdgeDistance < maximumDistance + 4 then return nil end
  local freeHalfWidth = road.radius - math.abs(road.lateral) - context.width * 0.5
  if freeHalfWidth < 0.65 then return nil end
  local front = obj:getFrontPosition()
  local originBase = vec3(front.x, front.y, front.z) + up * 0.45
  local half = math.min(context.width * 0.22, freeHalfWidth * 0.5)
  local closest, centerClearance, hitCount = nil, nil, 0
  for _, ray in ipairs({
    {offset = -half, center = false},
    {offset = 0, center = true},
    {offset = half, center = false}
  }) do
    local origin = originBase + right * ray.offset
    local ok, rayDistance = pcall(obj.castRayStatic, obj, origin, direction, maximumDistance)
    rayDistance = ok and number(rayDistance, maximumDistance) or maximumDistance
    -- castRayStatic returns the requested length when nothing was hit. The
    -- previous implementation interpreted that clear result as an obstacle;
    -- above roughly 40 km/h the comfortable braking distance exceeded the ray
    -- length, so an empty road generated a speed cap every few seconds.
    if rayDistance > 0.1 and rayDistance < maximumDistance - 0.25 then
      hitCount = hitCount + 1
      closest = closest and math.min(closest, rayDistance) or rayDistance
      if ray.center then centerClearance = rayDistance end
    end
  end
  if not centerClearance and hitCount < 2 then closest = nil end
  return closest, maximumDistance, hitCount, centerClearance
end

local function currentRoadContext(context)
  if not mapmgr or not mapmgr.mapData or type(mapmgr.findClosestRoad) ~= "function" then
    return nil
  end
  local ok, first, second = pcall(mapmgr.findClosestRoad, obj:getPosition())
  if not ok or first == nil or second == nil then return nil end
  local data = mapmgr.mapData
  local positions, graph = data.positions, data.graph
  if not (positions and graph and positions[first] and positions[second] and
    graph[first] and graph[first][second]) then return nil end
  local firstPos, secondPos = positions[first], positions[second]
  local edgeX = number(secondPos.x, 0) - number(firstPos.x, 0)
  local edgeY = number(secondPos.y, 0) - number(firstPos.y, 0)
  if edgeX * context.forwardX + edgeY * context.forwardY < 0 then
    first, second, firstPos, secondPos = second, first, secondPos, firstPos
  end
  local edge = graph[first] and graph[first][second]
  if not edge then return nil end
  local edgeLength = math.max(0.01, length2(number(secondPos.x, 0) - number(firstPos.x, 0),
    number(secondPos.y, 0) - number(firstPos.y, 0)))
  local edgeDirX = (number(secondPos.x, 0) - number(firstPos.x, 0)) / edgeLength
  local edgeDirY = (number(secondPos.y, 0) - number(firstPos.y, 0)) / edgeLength
  local along = clamp(((context.x - number(firstPos.x, 0)) * edgeDirX +
    (context.y - number(firstPos.y, 0)) * edgeDirY), 0, edgeLength)
  local centerX = number(firstPos.x, 0) + edgeDirX * along
  local centerY = number(firstPos.y, 0) + edgeDirY * along
  local roadRightX, roadRightY = edgeDirY, -edgeDirX
  local lateral = (context.x - centerX) * roadRightX +
    (context.y - centerY) * roadRightY
  local radius = 0
  if data.radius then
    radius = math.min(number(data.radius[first], 0), number(data.radius[second], 0))
  end
  local lanes = nil
  if edge.lanes and capabilities.getEdgeLaneConfig then
    local laneOk, laneValue = pcall(ai.getEdgeLaneConfig, first, second)
    if laneOk and type(laneValue) == "string" then lanes = laneValue end
  end
  local plusCount, minusCount = 0, 0
  for index = 1, #(lanes or "") do
    local lane = string.sub(lanes, index, index)
    if lane == "+" then plusCount = plusCount + 1
    elseif lane == "-" then minusCount = minusCount + 1 end
  end
  local degree = 0
  for _ in pairs(graph[second] or {}) do degree = degree + 1 end
  return {from = first, to = second, edge = edge, lanes = lanes,
    plusCount = plusCount, minusCount = minusCount,
    radius = radius, lateral = lateral,
    alignment = edgeDirX * context.forwardX + edgeDirY * context.forwardY,
    remainingEdgeDistance = math.max(0, edgeLength - along),
    nextNodeDegree = degree}
end

local function corridorGaps(objects, sideOffset, context)
  local frontGap, rearGap, rearTtc = math.huge, math.huge, math.huge
  local corridor = context.width * 0.6 + 1.25
  for _, candidate in ipairs(objects) do
    if math.abs(candidate.lateral - sideOffset) <= corridor then
      if candidate.alignment < -0.5 and candidate.longitudinal > -5 then
        return false, frontGap, rearGap, 0, "oncomingInPassingLane"
      end
      if candidate.longitudinal >= 0 then
        frontGap = math.min(frontGap, candidate.longitudinal -
          (context.length + candidate.length) * 0.45)
      else
        local gap = -candidate.longitudinal -
          (context.length + candidate.length) * 0.45
        rearGap = math.min(rearGap, gap)
        local rearClosing = candidate.longitudinalSpeed - context.speed
        if rearClosing > 0.1 then rearTtc = math.min(rearTtc, gap / rearClosing) end
      end
    end
  end
  local minimumFront = math.max(25, context.speed * 2)
  local minimumRear = 15
  if frontGap < minimumFront then return false, frontGap, rearGap, rearTtc, "frontGap" end
  if rearGap < minimumRear then return false, frontGap, rearGap, rearTtc, "rearGap" end
  if rearTtc < 4 then return false, frontGap, rearGap, rearTtc, "rearTtc" end
  return true, frontGap, rearGap, rearTtc, "clear"
end

local function staticCandidateClear(context, sideOffset, distance)
  if not capabilities.staticRay then return true, math.huge end
  local front = obj:getFrontPosition()
  local up = type(obj.getDirectionVectorUp) == "function" and
    obj:getDirectionVectorUp() or vec3(0, 0, 1)
  local right = vec3(context.rightX, context.rightY, 0)
  local forward = vec3(context.forwardX, context.forwardY, 0)
  local originBase = vec3(front.x, front.y, front.z) + up * 0.45
  local path = forward * distance + right * sideOffset
  local pathLength = path:length()
  if pathLength < 0.1 then return false, 0 end
  path:normalize()
  local closest = pathLength
  local half = context.width * 0.5 + 0.2
  for _, offset in ipairs({-half, 0, half}) do
    local origin = originBase + right * offset
    local ok, value = pcall(obj.castRayStatic, obj, origin, path, pathLength)
    if ok then closest = math.min(closest, number(value, pathLength)) end
  end
  return closest >= pathLength - 0.5, closest
end

local function dynamicCandidateClear(context, objects, sideOffset, maneuverDistance)
  local duration = clamp(maneuverDistance / math.max(3, context.speed), 1.5, 4)
  for sample = 1, 6 do
    local time = duration * sample / 6
    local progress = smoothStep(sample / 6)
    local stopTime = context.speed / settings.emergencyDeceleration
    local egoLong
    if time < stopTime then
      egoLong = context.speed * time -
        0.5 * settings.emergencyDeceleration * time * time
    else
      egoLong = context.speed * context.speed /
        (2 * settings.emergencyDeceleration)
    end
    local egoLat = sideOffset * progress
    for _, candidate in ipairs(objects) do
      local relLong = candidate.longitudinal + candidate.longitudinalSpeed * time - egoLong
      local relLat = candidate.lateral + candidate.lateralSpeed * time - egoLat
      local requiredLong = (context.length + candidate.length) * 0.45 + 0.8
      local requiredLat = (context.width + candidate.width) * 0.5 + 0.45
      if math.abs(relLong) <= requiredLong and math.abs(relLat) <= requiredLat then
        return false
      end
    end
  end
  return true
end

local function tryEmergencyEvasion(context, objects, road, threat)
  if not (capabilities.laneChange and threat and threat.kind == "oncoming") then
    return false, "unsupported"
  end
  if elapsed - lastEvasionAt < settings.evasionCooldownSeconds then
    return false, "cooldown"
  end
  if not road or road.radius <= 0 or math.abs(road.alignment) < 0.9 then
    return false, "roadUnavailable"
  end
  local obstacleApproach = math.max(0, -threat.longitudinalSpeed)
  local reaction = 0.2
  local stopTime = context.speed / settings.emergencyDeceleration
  local closureBeforeStop = context.speed * reaction +
    context.speed * context.speed / (2 * settings.emergencyDeceleration) +
    obstacleApproach * (reaction + stopTime)
  if closureBeforeStop + context.length * 0.5 < threat.gap then
    return false, "brakingSufficient"
  end
  local offsetMagnitude = clamp(context.width * 1.25, 2.4, 3.8)
  local distance = clamp(context.speed * 2.2, 18, 55)
  local best = nil
  for _, side in ipairs({-1, 1}) do
    local offset = side * offsetMagnitude
    local withinRoad = math.abs(road.lateral + offset) + context.width * 0.5 + 0.4 <=
      road.radius
    if withinRoad then
      local staticClear, staticDistance = staticCandidateClear(context, offset, distance)
      local dynamicClear = staticClear and
        dynamicCandidateClear(context, objects, offset, distance)
      if dynamicClear and (not best or staticDistance > best.clearance) then
        best = {offset = offset, distance = distance, clearance = staticDistance}
      end
    end
  end
  if not best then return false, "noClearCorridor" end
  if safeAiCall("laneChange", nil, best.distance, best.offset) then
    lastEvasionAt = elapsed
    return true, best.offset < 0 and "evadeLeft" or "evadeRight"
  end
  return false, "nativeLaneChangeFailed"
end

local function updateOvertaking(context, objects, lead, threat, road, scanDt)
  local blockingThreat = threat and
    (threat.kind ~= "lead" or threat.ttc < 2.5) or nil
  if state.nativeRacing then
    if elapsed - racingStartedAt >= settings.overtakeMaximumSeconds or
      blockingThreat or not lead then
      setNativeRacing(false)
      racingCooldownUntil = elapsed + settings.overtakeCooldownSeconds
      state.overtakeState = "cooldown"
      state.overtakeReason = blockingThreat and "threat" or
        not lead and "leadCleared" or "timeout"
    else
      state.overtaking = true
      state.overtakeState = "passing"
      state.overtakeReason = "nativeRacing"
      return
    end
  end
  state.overtaking = false
  if not capabilities.setRacing then state.overtakeReason = "unsupported"; return end
  if settings.allowOvertaking ~= true then state.overtakeReason = "disabled"; return end
  if elapsed < racingCooldownUntil then state.overtakeState = "cooldown"; state.overtakeReason = "cooldown"; return end
  if blockingThreat then state.overtakeReason = "threat"; return end
  if not lead then
    leadCandidateId, leadCandidateSeconds = nil, 0
    state.overtakeReason = "noLead"
    return
  end
  if tostring(lead.id) == tostring(leadCandidateId) then
    leadCandidateSeconds = leadCandidateSeconds + scanDt
  else
    leadCandidateId, leadCandidateSeconds = lead.id, 0
  end
  if context.speed - lead.longitudinalSpeed < 3 then state.overtakeReason = "leadNotSlow"; return end
  if lead.gap < 8 or lead.gap > 35 then state.overtakeReason = "leadGap"; return end
  if leadCandidateSeconds < settings.overtakeLeadHold then state.overtakeState = "observing"; state.overtakeReason = "leadHold"; return end
  if state.targetDistance and state.targetDistance < settings.overtakeMinimumTargetDistance then
    state.overtakeReason = "targetNear"; return
  end
  if not road or road.lanes == nil or road.plusCount < 2 or
    road.minusCount > 0 or road.edge.oneWay ~= true then
    state.overtakeReason = "explicitPassingLaneUnavailable"; return
  end
  if road.nextNodeDegree > 2 and road.remainingEdgeDistance < 70 then
    state.overtakeReason = "junctionNear"; return
  end
  if math.abs(road.alignment) < 0.96 then state.overtakeReason = "roadNotStraight"; return end
  local passSide = mapmgr and mapmgr.rules and mapmgr.rules.rightHandDrive and -1 or 1
  local laneWidth = clamp((road.radius * 2) / math.max(2, #(road.lanes or "")), 3, 4.2)
  local sideOffset = passSide * laneWidth
  if math.abs(road.lateral + sideOffset) + context.width * 0.5 + 0.25 > road.radius then
    state.overtakeReason = "laneOutsideRoad"; return
  end
  local gapsClear, _, _, _, gapReason = corridorGaps(objects, sideOffset, context)
  if not gapsClear then state.overtakeReason = gapReason; return end
  local staticClear = staticCandidateClear(context, sideOffset,
    clamp(context.speed * 3, 25, 70))
  if not staticClear then state.overtakeReason = "staticInPassingLane"; return end
  if setNativeRacing(true) then
    racingStartedAt = elapsed
    state.overtaking = true
    state.overtakeState = "passing"
    state.overtakeReason = "safeGatePassed"
  else
    state.overtakeReason = "nativeRacingFailed"
  end
end

local function addCap(caps, source, value, requestedDeceleration, emergency)
  if value == nil then return end
  value = math.max(0, number(value, 0))
  caps[#caps + 1] = {source = source, value = value,
    requestedDeceleration = math.max(0, number(requestedDeceleration, 0)),
    emergency = emergency == true}
end

local function applySpeedCaps(caps, context, scanDt)
  local winner = nil
  for _, cap in ipairs(caps) do
    if not winner or cap.value < winner.value or
      (cap.value == winner.value and cap.emergency and not winner.emergency) then winner = cap end
  end
  if not winner then
    clearSeconds = clearSeconds + scanDt
    currentDeceleration = math.max(0, currentDeceleration - 5 * scanDt)
    state.appliedDeceleration = currentDeceleration
    if speedLimited and smoothedSpeedLimit then
      smoothedSpeedLimit = math.max(context.speed,
        smoothedSpeedLimit + 4.5 * scanDt)
      safeAiCall("setSpeed", smoothedSpeedLimit)
      safeAiCall("setSpeedMode", "limit")
      state.targetSpeed = smoothedSpeedLimit
      state.speedCap = smoothedSpeedLimit
      state.speedCapSource = "release"
    end
    if clearSeconds >= 0.35 then restoreRouteSpeed() end
    return
  end
  clearSeconds = 0
  if winner.emergency then
    smoothedSpeedLimit = 0
    currentDeceleration = settings.emergencyDeceleration
  else
    if not smoothedSpeedLimit then smoothedSpeedLimit = context.speed end
    if winner.value < smoothedSpeedLimit then
      local jerk = 1.8
      currentDeceleration = math.min(math.max(winner.requestedDeceleration, 0.5),
        currentDeceleration + jerk * scanDt)
      smoothedSpeedLimit = math.max(winner.value,
        smoothedSpeedLimit - currentDeceleration * scanDt)
    else
      currentDeceleration = math.max(0, currentDeceleration - 2.5 * scanDt)
      smoothedSpeedLimit = math.min(winner.value,
        smoothedSpeedLimit + 1.5 * scanDt)
    end
  end
  if capabilities.setSpeed then safeAiCall("setSpeed", smoothedSpeedLimit) end
  if capabilities.setSpeedMode then safeAiCall("setSpeedMode", "limit") end
  speedLimited = true
  state.targetSpeed = smoothedSpeedLimit
  state.speedCap = smoothedSpeedLimit
  state.speedCapSource = winner.source
  state.requestedDeceleration = winner.requestedDeceleration
  state.appliedDeceleration = currentDeceleration
  state.emergencyBraking = winner.emergency
  local materiallyLimiting = winner.emergency or
    smoothedSpeedLimit < context.speed - 0.3
  state.safetyHolding = winner.source ~= "arrival" and materiallyLimiting
  state.safetyBrake = state.safetyHolding and (winner.emergency and 1 or
    clamp(winner.requestedDeceleration / settings.emergencyDeceleration, 0, 1)) or 0
end

local function notifyRouteDoneIfReached(context)
  if routeDoneNotified or not settings.targetPos then return end
  local dx = number(settings.targetPos.x, 0) - context.x
  local dy = number(settings.targetPos.y, 0) - context.y
  local dz = number(settings.targetPos.z, 0) - context.z
  local targetDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
  local parkingHandoffSpeed = math.max(2, settings.maximumArrivalSpeed * 1.8)
  if targetDistance <= settings.arrivalRadius and
    context.absoluteSpeed <= parkingHandoffSpeed then
    routeDoneNotified = true
    obj:queueGameEngineLua(string.format(
      "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.onAutopilotRouteDone(%d,%q,%d) end",
      obj:getID(), tostring(state.sessionId or ""),
      number(state.routeRevision, 0)))
  end
end

local function updateTiming(startedAt)
  local duration = math.max(0, (clock() - startedAt) * 1000000)
  state.updateTimeUs = duration
  if state.updateAverageUs == 0 then state.updateAverageUs = duration
  else state.updateAverageUs = state.updateAverageUs * 0.9 + duration * 0.1 end
  timingCursor = timingCursor % 32 + 1
  timingSamples[timingCursor] = duration
  if elapsed - lastTimingPercentileAt >= 1 then
    lastTimingPercentileAt = elapsed
    local values = {}
    for _, value in pairs(timingSamples) do values[#values + 1] = value end
    table.sort(values)
    if #values > 0 then
      state.updateP95Us = values[math.max(1, math.ceil(#values * 0.95))]
    end
  end
end

local function supervisorStep(scanDt)
  local startedAt = clock()
  state.sequence = state.sequence + 1
  -- Re-evaluate the supervisor mode on every scan. Emergency modes describe
  -- the current decision; keeping the previous value made a cleared threat
  -- look active for the rest of the route.
  state.supervisorMode = "cruise"
  state.selectedManeuver = "none"
  state.emergencyBraking = false
  state.safetyHolding = false
  state.safetyBrake = 0
  state.requestedDeceleration = 0
  state.appliedDeceleration = currentDeceleration
  local context = vehicleContext()
  if not context then updateTiming(startedAt); return end
  local objects = collectNearby(context)
  state.trackedVehicleCount = #objects
  state.scanVehicleCount = #objects
  local lead, threat = evaluateTraffic(context, objects)
  local confidence = updateThreatConfidence(threat)
  local approach = targetApproach(context)
  local road = currentRoadContext(context)

  state.obstacleDetected = lead ~= nil or threat ~= nil
  state.obstacleId = lead and lead.id or threat and threat.id or nil
  state.obstacleDistance = lead and lead.gap or threat and threat.gap or nil
  state.obstacleClosingSpeed = lead and lead.closingSpeed or
    threat and threat.closingSpeed or nil
  state.leadSpeed = lead and lead.longitudinalSpeed or nil
  state.timeToCollision = threat and threat.ttc or lead and lead.ttc or nil
  state.threatId = threat and threat.id or nil
  state.threatKind = threat and threat.kind or nil
  state.ttc = threat and threat.ttc or nil
  state.tCPA = threat and threat.tCPA or nil
  state.dCPA = threat and threat.dCPA or nil
  state.threatLateral = threat and threat.lateral or nil
  state.threatPredictedLateral = threat and threat.predictedLateral or nil
  state.threatLateralClearance = threat and threat.lateralClearance or nil

  state.targetApproachActive = approach ~= nil
  state.targetSpeedCap = approach and approach.cap or nil
  if approach then state.targetDistance = approach.distance end

  staticTimer = staticTimer + scanDt
  if staticTimer >= 0.2 then
    staticTimer = staticTimer % 0.2
    local clearance, maximumDistance, hitCount, centerClearance =
      scanStatic(context, road)
    state.staticMaxDistance = maximumDistance
    state.staticHitCount = hitCount or 0
    state.staticCenterClearance = centerClearance
    if clearance and staticCandidateDistance and
      math.abs(clearance - staticCandidateDistance) <= 3 then
      staticStableScans = staticStableScans + 1
    elseif clearance then
      staticStableScans = 1
    else
      staticStableScans = 0
    end
    staticCandidateDistance = clearance
    state.staticClearance = staticStableScans >= 2 and clearance or nil
  end

  updateOvertaking(context, objects, lead, threat, road, scanDt)

  local caps = {}
  if lead and not state.nativeRacing then
    local brakingDistance = lead.closingSpeed * lead.closingSpeed /
      (2 * math.max(0.1, settings.brakingDeceleration))
    local desiredGap = settings.minimumGap +
      context.speed * settings.followingTimeGap + brakingDistance
    if lead.gap < desiredGap or (lead.ttc and lead.ttc < 4.5) then
      local progress = clamp((lead.gap - settings.minimumGap) /
        math.max(1, desiredGap - settings.minimumGap), 0, 1)
      local cap = math.max(0, lead.longitudinalSpeed +
        lead.closingSpeed * math.sqrt(progress))
      local required = lead.closingSpeed * lead.closingSpeed /
        (2 * math.max(0.5, lead.gap - settings.minimumGap * 0.5))
      addCap(caps, "follow", cap,
        clamp(required, 0, settings.brakingDeceleration), false)
    end
  end
  if approach then addCap(caps, "arrival", approach.cap,
    approach.requestedDeceleration, false) end
  if state.staticClearance then
    local clearance = state.staticClearance
    local comfortable = 2.8 + context.speed * 0.8 +
      context.speed * context.speed / (2 * settings.brakingDeceleration)
    local emergencyDistance = 1.2 + context.speed * 0.2 +
      context.speed * context.speed / (2 * settings.emergencyDeceleration)
    if clearance < comfortable then
      local cap = math.sqrt(math.max(0,
        2 * settings.brakingDeceleration * math.max(0, clearance - 2.2)))
      addCap(caps, clearance <= emergencyDistance and "staticEmergency" or "static",
        clearance <= emergencyDistance and 0 or cap,
        clearance <= emergencyDistance and settings.emergencyDeceleration or
          settings.brakingDeceleration,
        clearance <= emergencyDistance)
    end
  end

  if threat then
    local required = threat.closingSpeed * threat.closingSpeed /
      (2 * math.max(0.5, threat.gap))
    state.requiredDeceleration = required
    -- Presets only shift the early, comfortable warning window. The emergency
    -- thresholds below are invariant so aggressive driving never weakens the
    -- final collision barrier.
    local warningTtc = (threat.kind == "crossing" and 2 or 2.5) *
      settings.predictiveWarningScale
    local emergencyTtc = threat.kind == "crossing" and 1 or
      threat.kind == "oncoming" and 1.4 or 1.2
    local emergency = threat.ttc <= emergencyTtc or
      required >= settings.emergencyDeceleration
    if confidence >= 1 and threat.ttc < warningTtc then
      local cap = emergency and 0 or math.max(0,
        context.speed * clamp((threat.ttc - 1.2) / 2.8, 0, 1))
      addCap(caps, emergency and "emergency" or "predictiveThreat", cap,
        clamp(required, 0, settings.emergencyDeceleration), emergency)
    end
    if confidence >= 1 and emergency and threat.kind == "oncoming" and
      threat.ttc <= 2.4 then
      local evaded, reason = tryEmergencyEvasion(context, objects, road, threat)
      if evaded then
        state.selectedManeuver = reason
        state.supervisorMode = "emergencyEvade"
        setNativeRacing(false)
      elseif emergency then
        state.selectedManeuver = "emergencyBrake"
        state.supervisorMode = "emergencyBrake"
      else
        state.selectedManeuver = "brakeOnly:" .. tostring(reason)
      end
    elseif confidence >= 1 and emergency then
      state.selectedManeuver = "emergencyBrake"
      state.supervisorMode = "emergencyBrake"
      setNativeRacing(false)
    end
  end

  applySpeedCaps(caps, context, scanDt)
  if state.emergencyBraking and state.supervisorMode ~= "emergencyEvade" then
    state.supervisorMode = "emergencyBrake"
    if state.selectedManeuver == "none" then
      state.selectedManeuver = "emergencyBrake"
    end
  end
  if state.supervisorMode ~= "emergencyEvade" and
    state.supervisorMode ~= "emergencyBrake" then
    if state.nativeRacing then state.supervisorMode = "overtaking"
    elseif state.speedCapSource == "follow" then state.supervisorMode = "following"
    elseif state.speedCapSource == "arrival" then state.supervisorMode = "arrival"
    elseif state.speedCapSource then state.supervisorMode = "caution"
    else state.supervisorMode = "cruise" end
  end
  state.mode = state.supervisorMode
  state.status = state.supervisorMode
  notifyRouteDoneIfReached(context)
  updateTiming(startedAt)
end

local function requestPark(data)
  if not controlMatches(data) then return false end
  parkingRequested = true
  parkingConfirmed = false
  parkingCommitRequested = false
  parkingStableChecks = 0
  parkingGearTarget = nil
  parkingGearboxBehavior = nil
  routeDoneNotified = true
  setNativeRacing(false, true)
  restoreRouteSpeed()
  state.parkingRequested = true
  state.parkingConfirmed = false
  state.parked = false
  state.overtaking = false
  state.selectedManeuver = "park"
  state.supervisorMode = "parking"
  state.mode = "parking"
  state.status = "parking"
  state.parkingGearTarget = nil
  state.parkingGearActual = nil
  state.parkingGearConfirmed = false
  state.parkingBrakeConfirmed = false
  state.parkingGearboxBehavior = nil
  -- Keep native stop steering while applying a deterministic service brake.
  -- Realistic gearbox behavior prevents the brake input from becoming reverse
  -- throttle in Arcade and remains held until parking is acknowledged.
  safeAiCall("setMode", "stop")
  holdParkingGearboxBehavior()
  parkingInput("throttle", 0)
  parkingInput("brake", 1)
  setParkingBrake(0)
  return true
end

local function commitPark(data)
  if not controlMatches(data) or not parkingRequested then return false end
  local speed = math.abs(number(electrics and electrics.values and
    electrics.values.wheelspeed, math.huge))
  if speed > 0.3 then
    state.status = "parkingMoving"
    return false
  end
  setNativeRacing(false, true)
  restoreRouteSpeed()
  -- Disable stock AI before selecting the deterministic parked gear. Arcade
  -- can overwrite a stationary P/N choice, so selectParkingGear temporarily
  -- holds Realistic behavior until the next route starts.
  safeAiCall("setMode", "disabled")
  parkingInput("throttle", 0)
  parkingInput("brake", 1)
  setParkingBrake(1)
  parkingCommitRequested = true
  parkingStableChecks = 0
  selectParkingGear()
  state.parkingRequested = true
  state.parkingConfirmed = false
  state.parked = false
  state.selectedManeuver = "parkingGear"
  state.supervisorMode = "parking"
  state.mode = "parking"
  state.status = "parkingConfirming"
  state.emergencyBraking = false
  state.safetyHolding = true
  state.safetyBrake = 1
  updateParkingConfirmation()
  return parkingGearTarget ~= nil
end

local function onParkFinalized(data)
  if not controlMatches(data) then return false end
  if not parkingConfirmed then return false end
  safeAiCall("setMode", "disabled")
  selectParkingGear()
  parkingInput("throttle", 0)
  parkingInput("brake", 0)
  setParkingBrake(1)
  state.parkingRequested = true
  state.parkingConfirmed = true
  state.parked = true
  state.supervisorMode = "parked"
  state.mode = "parked"
  state.status = "parked"
  return true
end

local function pause(data)
  if not controlMatches(data) then return false end
  parkingRequested, parkingConfirmed = false, false
  parkingCommitRequested, parkingStableChecks = false, 0
  parkingGearTarget, parkingGearboxBehavior = nil, nil
  setNativeRacing(false, true)
  restoreRouteSpeed()
  state.parkingRequested = false
  state.parkingConfirmed = false
  state.parked = false
  state.selectedManeuver = "pause"
  state.supervisorMode = "paused"
  state.mode = "paused"
  state.status = "paused"
  return true
end

local function fail(config, reason)
  config = type(config) == "table" and config or {}
  if config.sessionId ~= nil then state.sessionId = config.sessionId end
  if config.routeRevision ~= nil then
    state.routeRevision = number(config.routeRevision, state.routeRevision)
  end
  if config.sequence ~= nil then state.sequence = number(config.sequence, state.sequence) end
  setNativeRacing(false, true)
  restoreRouteSpeed()
  state.active = false
  state.selectedManeuver = "none"
  state.supervisorMode = "fault"
  state.mode = "fault"
  state.status = tostring(reason or "nativeAiUnavailable")
  return false
end

local function watch(config)
  config = type(config) == "table" and config or {}
  restoreParkingGearboxBehavior()
  if watching then
    setNativeRacing(false)
    restoreRouteSpeed()
  end
  detectCapabilities()
  settings.followingTimeGap = clamp(number(config.followingTimeGap, 2.3), 1, 4)
  settings.minimumGap = clamp(number(config.minimumGap, 4), 2, 10)
  settings.brakingDeceleration = clamp(number(config.brakingDeceleration, 3.5), 2, 8)
  settings.predictiveWarningScale = clamp(
    number(config.predictiveWarningScale, 1), 0.8, 1.2)
  settings.emergencyDeceleration = clamp(number(config.emergencyDeceleration, 8), 6, 10)
  settings.routeSpeedMode = config.routeSpeedMode == "off" and "off" or "legal"
  settings.targetPos = config.targetX ~= nil and
    {x = number(config.targetX, 0), y = number(config.targetY, 0),
      z = number(config.targetZ, 0)} or nil
  settings.targetDir = config.targetDirX ~= nil and
    {x = number(config.targetDirX, 0), y = number(config.targetDirY, 0)} or nil
  settings.arrivalRadius = clamp(number(config.arrivalRadius, 14), 4, 30)
  settings.maximumArrivalSpeed = clamp(number(config.maximumArrivalSpeed, 0), 0, 3)
  settings.broadPhaseRange = clamp(number(config.broadPhaseRange, 100), 40, 100)
  settings.maximumTrackedVehicles = math.floor(clamp(
    number(config.maximumTrackedVehicles, 16), 4, 16))
  settings.predictionHorizon = clamp(number(config.predictionHorizon, 5), 3, 6)
  settings.allowOvertaking = config.allowOvertaking == true
  watching = true
  state.active = true
  state.sessionId = config.sessionId ~= nil and config.sessionId or ""
  state.routeRevision = number(config.routeRevision, state.routeRevision + 1)
  state.sequence = number(config.sequence, 0)
  state.capabilities = capabilities
  updateTimer, staticTimer, elapsed, clearSeconds = 0, 0, 0, 0
  currentInterval = clamp(number(config.updateInterval, 0.1), 0.05, 0.2)
  routeDoneNotified = false
  speedLimited, smoothedSpeedLimit, currentDeceleration = false, nil, 0
  dimensionCache = {}
  timingSamples, timingCursor, lastTimingPercentileAt = {}, 0, 0
  lastThreatId, lastThreatKind, stableThreatScans = nil, nil, 0
  staticCandidateDistance, staticStableScans = nil, 0
  leadCandidateId, leadCandidateSeconds = nil, 0
  racingStartedAt, racingCooldownUntil, lastEvasionAt = -math.huge, -math.huge, -math.huge
  state.nativeRacing = false
  parkingRequested, parkingConfirmed = false, false
  parkingCommitRequested, parkingStableChecks = false, 0
  parkingGearTarget, parkingGearboxBehavior = nil, nil
  releaseParkingInputs()
  state.updateTimeUs, state.updateAverageUs, state.updateP95Us = 0, 0, 0
  resetTransientState()
  setNativeRacing(false, true)
  if mapmgr and type(mapmgr.enableTracking) == "function" then mapmgr.enableTracking() end
  return capabilities.setSpeed and capabilities.setSpeedMode and capabilities.mapObjects
end

local function unwatch()
  restoreParkingGearboxBehavior()
  watching = false
  state.active = false
  setNativeRacing(false, true)
  if capabilities.setStopPoint then safeAiCall("setStopPoint", nil, nil) end
  restoreRouteSpeed()
  resetTransientState()
  state.nativeRacing = false
  state.overtaking = false
  state.mode = "inactive"
  state.supervisorMode = "inactive"
  updateTimer, staticTimer, clearSeconds = 0, 0, 0
end

local function updateGFX(dt)
  if not watching then return end
  dt = math.max(0, number(dt, 0))
  if parkingRequested then
    holdParkingGearboxBehavior()
    parkingInput("throttle", 0)
    parkingInput("brake", 1)
    local speed = math.abs(number(electrics and electrics.values and
      electrics.values.wheelspeed, math.huge))
    if not parkingCommitRequested and speed <= 0.15 then
      -- Do not leave an automatic idling in D while the slower GE telemetry
      -- handshake catches up. Commit in vehicle Lua on the first stationary
      -- frame; the GE command remains an idempotent acknowledgement/retry.
      commitPark({})
    end
    if parkingCommitRequested then
      setParkingBrake(1)
      local _, gearConfirmed = readParkingGear()
      if not gearConfirmed then selectParkingGear() end
      updateParkingConfirmation()
    end
    return
  end
  elapsed = elapsed + dt
  updateTimer = updateTimer + dt
  local speed = math.abs(number(electrics and electrics.values and
    electrics.values.wheelspeed, 0))
  local adaptiveInterval
  if state.emergencyBraking or state.threatConfidence >= 0.5 or
    state.nativeRacing then adaptiveInterval = 0.05
  elseif speed < 1 and not state.targetApproachActive then adaptiveInterval = 0.2
  else adaptiveInterval = currentInterval end
  adaptiveInterval = clamp(adaptiveInterval, 0.05, 0.2)
  state.updateInterval = adaptiveInterval
  if updateTimer < adaptiveInterval then return end
  local scanDt = updateTimer
  updateTimer = 0
  supervisorStep(scanDt)
end

local function getDebugState()
  local result = {}
  for key, value in pairs(state) do result[key] = value end
  local capabilityCopy = {}
  for key, value in pairs(capabilities) do capabilityCopy[key] = value end
  result.capabilities = capabilityCopy
  result.followingTimeGap = settings.followingTimeGap
  result.predictiveWarningScale = settings.predictiveWarningScale
  result.minimumGap = settings.minimumGap
  result.maximumTrackedVehicles = settings.maximumTrackedVehicles
  result.broadPhaseRange = settings.broadPhaseRange
  result.allowOvertaking = settings.allowOvertaking
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
M.requestPark = requestPark
M.commitPark = commitPark
M.onParkFinalized = onParkFinalized
M.pause = pause
M.fail = fail

return M
