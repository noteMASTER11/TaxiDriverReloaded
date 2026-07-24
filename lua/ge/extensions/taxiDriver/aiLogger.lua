local M = {}

local schemaVersion = 1
local snapshotInterval = 1
local flushInterval = 3

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function round(value, digits)
  local scale = 10 ^ (digits or 3)
  return math.floor(number(value, 0) * scale + 0.5) / scale
end

local function optionalRound(value, digits)
  value = tonumber(value)
  if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
  return round(value, digits)
end

local function gearKind(value)
  local text = string.lower(tostring(value or ""))
  local numeric = tonumber(value)
  if text == "n" or text == "neutral" or numeric == 0 then return "neutral" end
  if text == "r" or text == "reverse" or (numeric and numeric < 0) then return "reverse" end
  if text ~= "" then return "forward" end
  return "unknown"
end

local function position(value)
  if not value then return nil end
  return {x = round(value.x, 3), y = round(value.y, 3), z = round(value.z, 3)}
end

local function safeCopy(source, depth)
  depth = depth or 0
  if depth > 4 then return nil end
  local sourceType = type(source)
  if sourceType == "string" or sourceType == "number" or sourceType == "boolean" then return source end
  if sourceType ~= "table" then return nil end
  local result = {}
  for key, value in pairs(source) do
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
      result[key] = value
    elseif valueType == "table" then
      result[key] = safeCopy(value, depth + 1)
    end
  end
  return result
end

local function joinPath(root, name)
  root = tostring(root or "")
  if root == "" then return name end
  local last = root:sub(-1)
  if last ~= "/" and last ~= "\\" then root = root .. "/" end
  return root .. name
end

local function wallTimestamp()
  return os.date("%Y-%m-%dT%H:%M:%S%z")
end

function M.new(options)
  options = options or {}
  local service = {}
  local file = nil
  local filePath = nil
  local enabled = false
  local active = false
  local sequence = 0
  local elapsed = 0
  local snapshotTimer = 0
  local flushTimer = 0
  local lastTelemetry = {}
  local lastSnapshot = nil
  local lastPhase = nil
  local lastTargetKey = nil
  local lastControllerMode = nil
  local lastSafetyHolding = false
  local huntingChanges = {}
  local summary = {}
  local lastOpenFailureAt = -math.huge

  local function clock()
    if type(options.clock) == "function" then return number(options.clock(), 0) end
    if type(os.clockhp) == "function" then return os.clockhp() end
    return os.clock()
  end

  local sessionStartedAt = nil
  local sessionStamp = nil

  local function beginFileSession()
    if sessionStartedAt then return end
    sessionStartedAt = clock()
    sessionStamp = type(options.sessionStamp) == "string" and options.sessionStamp or
      os.date("%Y%m%d_%H%M%S")
    sequence = 0
  end

  local function encode(value)
    if type(options.encode) == "function" then return options.encode(value) end
    return jsonEncode(value)
  end

  local function userRoot()
    if type(options.userPath) == "function" then return options.userPath() end
    -- GE Lua's io.open resolves virtual paths through BeamNG's user VFS.
    -- An absolute Windows path is rejected even when FS:getUserPath() returns it.
    return "/"
  end

  local function openLog()
    if file then return true end
    beginFileSession()
    local baseName = "taxidriver_ailog_" .. sessionStamp
    filePath = joinPath(userRoot(), baseName .. ".jsonl")
    local opener = options.openFile or io.open
    local openError
    file, openError = opener(filePath, "a")
    if not file then
      local now = clock()
      if type(log) == "function" and now - lastOpenFailureAt >= 5 then
        lastOpenFailureAt = now
        log("E", "taxiDriver.aiLogger", "[TaxiDriver] Unable to open AI log: " ..
          tostring(filePath) .. " reason=" .. tostring(openError or "unknown"))
      end
      return false
    end
    lastOpenFailureAt = -math.huge
    return true
  end

  local function write(event, fields, forceFlush)
    if not openLog() then return false end
    sequence = sequence + 1
    local record = safeCopy(type(fields) == "table" and fields or {})
    record.schemaVersion = schemaVersion
    record.sequence = sequence
    record.event = tostring(event or "unknown")
    record.elapsedSeconds = round(clock() - number(sessionStartedAt, clock()), 3)
    record.wallTime = wallTimestamp()
    local ok, line = pcall(encode, record)
    if not ok or type(line) ~= "string" then return false end
    -- Keep the journal crash-readable: every record reaches the filesystem
    -- immediately instead of waiting for AI shutdown or the stdio buffer.
    local written = pcall(function()
      file:write(line, "\n")
      file:flush()
    end)
    if written then flushTimer = 0 end
    return written
  end

  local function context()
    if type(options.getContext) ~= "function" then return {} end
    local ok, result = pcall(options.getContext)
    return ok and type(result) == "table" and result or {}
  end

  local function withContext(fields)
    local result = safeCopy(context())
    for key, value in pairs(safeCopy(type(fields) == "table" and fields or {})) do result[key] = value end
    return result
  end

  local function resetSummary()
    summary = {
      enabledAt = clock(), routeStarts = 0, recoveries = 0, safetyInterventions = 0,
      gearChanges = 0, damageStart = number(lastTelemetry.damage, 0),
      damageMaximum = number(lastTelemetry.damage, 0), minimumTargetDistance = math.huge,
      minimumRouteRemaining = math.huge
    }
    lastSnapshot = nil
    lastPhase = nil
    lastTargetKey = nil
    lastControllerMode = nil
    lastSafetyHolding = false
    huntingChanges = {}
    snapshotTimer = 0
  end

  function service:start(vehicle, phase, target)
    if not enabled then return false end
    if active then return end
    beginFileSession()
    active = true
    resetSummary()
    write("ai_session_started", withContext({
      vehicleId = vehicle and type(vehicle.getID) == "function" and vehicle:getID() or nil,
      phase = phase,
      target = target and position(target.pos) or nil
    }), true)
    return true
  end

  function service:setEnabled(value)
    value = value == true
    if enabled == value then return end
    enabled = value
    if not enabled and active then self:stop("settingDisabled") end
  end

  function service:isEnabled() return enabled end

  function service:stop(reason)
    if not active then return end
    local duration = math.max(0, clock() - number(summary.enabledAt, clock()))
    write("ai_session_finished", withContext({
      reason = tostring(reason or ""), durationSeconds = round(duration, 3),
      routeStarts = summary.routeStarts or 0, recoveries = summary.recoveries or 0,
      safetyInterventions = summary.safetyInterventions or 0,
      gearChanges = summary.gearChanges or 0,
      damageDelta = round(number(summary.damageMaximum, 0) - number(summary.damageStart, 0), 3),
      minimumTargetDistance = summary.minimumTargetDistance ~= math.huge and
        round(summary.minimumTargetDistance, 3) or nil,
      minimumRouteRemaining = summary.minimumRouteRemaining ~= math.huge and
        round(summary.minimumRouteRemaining, 3) or nil
    }), true)
    active = false
    if file then
      pcall(function() file:flush(); file:close() end)
      file = nil
    end
    sessionStartedAt = nil
    sessionStamp = nil
  end

  function service:close(reason)
    if active then self:stop(reason or "loggerClosed") end
    if file then
      pcall(function() file:flush(); file:close() end)
      file = nil
    end
    sessionStartedAt = nil
    sessionStamp = nil
  end

  function service:isActive() return active end
  function service:getPath() return filePath end

  function service:onStructuredEvent(level, area, event, fields)
    if not active or area ~= "autopilot" then return end
    if event == "route_started" then summary.routeStarts = summary.routeStarts + 1 end
    if event == "adaptive_bypass_started" or event == "reverse_escape_requested" then
      summary.recoveries = summary.recoveries + 1
    end
    local record = withContext(fields)
    record.level = level
    write("autopilot_" .. tostring(event), record,
      level == "W" or level == "E" or event == "enabled" or event == "disabled")
  end

  function service:onVehicleTelemetry(data)
    if type(data) ~= "table" then return end
    local previous = lastTelemetry
    lastTelemetry = data
    if not active then return end

    local damage = number(data.damage, number(previous.damage, 0))
    local previousDamage = number(previous.damage, damage)
    summary.damageMaximum = math.max(number(summary.damageMaximum, damage), damage)
    if damage > previousDamage + 0.01 then
      write("vehicle_damage_increased", withContext({
        damage = round(damage, 3), delta = round(damage - previousDamage, 3),
        speedKmh = round(math.abs(number(data.wheelSpeed, 0)) * 3.6, 2),
        longitudinalG = round(data.longitudinalG, 3), lateralG = round(data.lateralG, 3),
        affectedParts = data.partDamage
      }), true)
    end

    local gear = tostring(data.gear or data.gearIndex or "")
    local previousGear = tostring(previous.gear or previous.gearIndex or "")
    if previousGear ~= "" and gear ~= previousGear then
      summary.gearChanges = summary.gearChanges + 1
      local now = clock()
      local speedKmh = math.abs(number(data.wheelSpeed, 0)) * 3.6
      write("gear_changed", withContext({
        from = previousGear, to = gear, gearIndex = data.gearIndex,
        gearboxBehavior = data.gearboxBehavior, speedKmh = round(speedKmh, 2)
      }), false)
      local fromKind, toKind = gearKind(previousGear), gearKind(gear)
      local huntingTransition = speedKmh <= 3 and
        ((fromKind == "neutral") ~= (toKind == "neutral") or
          (fromKind == "forward" and toKind == "reverse") or
          (fromKind == "reverse" and toKind == "forward"))
      if huntingTransition then
        huntingChanges[#huntingChanges + 1] = now
        while #huntingChanges > 0 and now - huntingChanges[1] > 6 do table.remove(huntingChanges, 1) end
      end
      if #huntingChanges == 5 then
        write("gear_hunting_detected", withContext({
          changes = #huntingChanges, windowSeconds = 6, speedKmh = round(speedKmh, 2),
          from = previousGear, to = gear
        }), true)
      end
    end
    if previous.gearboxBehavior ~= nil and data.gearboxBehavior ~= previous.gearboxBehavior then
      write("gearbox_mode_changed", withContext({
        from = previous.gearboxBehavior, to = data.gearboxBehavior
      }), true)
    end
    if data.gearboxBehavior and data.gearboxBehavior ~= "arcade" then
      if previous.gearboxBehavior == "arcade" or previous.gearboxBehavior == nil then
        write("gearbox_mode_drift", withContext({mode = data.gearboxBehavior}), true)
      end
    end
    if previous.ignitionLevel ~= nil and data.ignitionLevel ~= previous.ignitionLevel then
      write("ignition_changed", withContext({
        from = previous.ignitionLevel, to = data.ignitionLevel, engineRunning = data.engineRunning
      }), true)
    end

    local controller = type(data.autopilotController) == "table" and data.autopilotController or {}
    local mode = tostring(controller.mode or "inactive")
    if lastControllerMode and mode ~= lastControllerMode then
      write("controller_mode_changed", withContext({from = lastControllerMode, to = mode}), true)
    end
    lastControllerMode = mode
    local safety = controller.safetyHolding == true
    if safety ~= lastSafetyHolding then
      if safety then summary.safetyInterventions = summary.safetyInterventions + 1 end
      write(safety and "collision_safety_engaged" or "collision_safety_released", withContext({
        brake = optionalRound(controller.safetyBrake, 3), obstacleDistance = optionalRound(controller.obstacleDistance, 3),
        obstacleClosingSpeed = optionalRound(controller.obstacleClosingSpeed, 3), obstacleId = controller.obstacleId,
        curvedPathRisk = controller.curvedPathRisk == true,
        curvedPathRiskTime = optionalRound(controller.curvedPathRiskTime, 3),
        requestedDeceleration = optionalRound(controller.requestedDeceleration, 3),
        appliedDeceleration = optionalRound(controller.appliedDeceleration, 3),
        emergencyBraking = controller.emergencyBraking == true
      }), safety)
      lastSafetyHolding = safety
    end
  end

  function service:update(vehicle, phase, target, diagnostics, dt)
    if not active then return end
    dt = math.max(0, number(dt, 0))
    elapsed = elapsed + dt
    snapshotTimer = snapshotTimer + dt
    flushTimer = flushTimer + dt
    diagnostics = type(diagnostics) == "table" and diagnostics or {}
    local targetDistance = tonumber(diagnostics.targetDistance)
    if targetDistance == nil and vehicle and target and target.pos then
      local vehiclePosition = vehicle:getPosition()
      local dx = number(vehiclePosition.x, 0) - number(target.pos.x, 0)
      local dy = number(vehiclePosition.y, 0) - number(target.pos.y, 0)
      local dz = number(vehiclePosition.z, 0) - number(target.pos.z, 0)
      targetDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    if targetDistance then summary.minimumTargetDistance = math.min(summary.minimumTargetDistance, targetDistance) end
    local routeRemaining = tonumber(diagnostics.routeRemainingDistance)
    if routeRemaining then summary.minimumRouteRemaining = math.min(summary.minimumRouteRemaining, routeRemaining) end
    local key = tostring(diagnostics.targetKey or "")
    if phase ~= lastPhase or key ~= lastTargetKey then
      write("navigation_target_changed", withContext({
        previousPhase = lastPhase, phase = phase, targetKey = key,
        target = target and position(target.pos) or nil, targetDistance = optionalRound(targetDistance, 3),
        exactApproach = target and target.exactApproach == true or false
      }), true)
      lastPhase, lastTargetKey = phase, key
    end
    if snapshotTimer < snapshotInterval then return end
    snapshotTimer = snapshotTimer - snapshotInterval

    local vehiclePosition = vehicle and type(vehicle.getPosition) == "function" and vehicle:getPosition() or nil
    local record = withContext({
      phase = phase, status = diagnostics.status, reason = diagnostics.reason,
      vehicleId = vehicle and type(vehicle.getID) == "function" and vehicle:getID() or nil,
      position = position(vehiclePosition), target = target and position(target.pos) or nil,
      targetDistance = optionalRound(targetDistance, 3), targetDistanceDelta =
        lastSnapshot and targetDistance and lastSnapshot.targetDistance and
          round(targetDistance - lastSnapshot.targetDistance, 3) or nil,
      speedKmh = round(diagnostics.speedKmh, 2), routeNodeCount = diagnostics.routeNodeCount,
      routePending = diagnostics.routePending, approachStage = diagnostics.approachStage,
      stuckSeconds = round(diagnostics.stuckSeconds, 2), recoveryAttempt = diagnostics.recoveryAttempt,
      controllerMode = diagnostics.controllerMode, leadVehicleId = diagnostics.leadVehicleId,
      leadGap = optionalRound(diagnostics.leadGap, 2), leadSpeed = optionalRound(diagnostics.leadSpeed, 2),
      leadClosingSpeed = optionalRound(diagnostics.leadClosingSpeed, 2),
      leadTtc = optionalRound(diagnostics.leadTtc, 2), leadConfirmed = diagnostics.leadConfirmed,
      leadRayConfirmed = diagnostics.leadRayConfirmed,
      curvedPathRisk = diagnostics.curvedPathRisk == true,
      curvedPathRiskTime = optionalRound(diagnostics.curvedPathRiskTime, 2),
      leadCandidateSeconds = optionalRound(diagnostics.leadCandidateSeconds, 2),
      followSpeedCap = diagnostics.followSpeedCap and round(diagnostics.followSpeedCap, 2) or nil,
      signalId = diagnostics.signalId, signalState = diagnostics.signalState,
      signalAction = diagnostics.signalAction,
      signalDistance = optionalRound(diagnostics.signalDistance, 2),
      signalGreenSeconds = optionalRound(diagnostics.signalGreenSeconds, 2),
      signalMissingSeconds = optionalRound(diagnostics.signalMissingSeconds, 2),
      signalSpeedCap = optionalRound(diagnostics.signalSpeedCap, 2),
      routeSpeedCap = optionalRound(diagnostics.routeSpeedCap, 2),
      appliedSpeedCap = optionalRound(diagnostics.appliedSpeedCap, 2),
      requestedDeceleration = optionalRound(diagnostics.requestedDeceleration, 3),
      appliedDeceleration = optionalRound(diagnostics.appliedDeceleration, 3),
      emergencyBraking = diagnostics.emergencyBraking == true,
      targetApproachActive = diagnostics.targetApproachActive == true,
      targetApproachDistance = optionalRound(diagnostics.targetApproachDistance, 2),
      targetApproachSpeedCap = optionalRound(diagnostics.targetApproachSpeedCap, 2),
      routeDoneRetryCount = diagnostics.routeDoneRetryCount,
      orientedApproach = diagnostics.orientedApproach == true,
      approachNode = diagnostics.approachNode,
      departureNode = diagnostics.departureNode,
      routeRemainingDistance = optionalRound(routeRemaining, 2),
      routeSegmentIndex = diagnostics.routeSegmentIndex,
      routeCrossTrack = optionalRound(diagnostics.routeCrossTrack, 2),
      recoverySignature = diagnostics.recoverySignature,
      recoveryRepeatCount = diagnostics.recoveryRepeatCount,
      recoveryEscalation = diagnostics.recoveryEscalation,
      preflightPending = diagnostics.preflightPending,
      preflightSeconds = optionalRound(diagnostics.preflightSeconds, 2),
      damage = round(lastTelemetry.damage, 3), gear = lastTelemetry.gear,
      gearIndex = lastTelemetry.gearIndex, gearboxBehavior = lastTelemetry.gearboxBehavior,
      wheelSpeed = round(lastTelemetry.wheelSpeed, 3), engineRpm = round(lastTelemetry.engineRpm, 1),
      ignitionLevel = lastTelemetry.ignitionLevel, engineRunning = lastTelemetry.engineRunning,
      throttle = round(lastTelemetry.throttle, 3), brake = round(lastTelemetry.brake, 3),
      clutch = round(lastTelemetry.clutch, 3), parkingBrake = round(lastTelemetry.parkingBrake, 3),
      longitudinalG = round(lastTelemetry.longitudinalG, 3), lateralG = round(lastTelemetry.lateralG, 3)
    })
    local controller = type(lastTelemetry.autopilotController) == "table" and lastTelemetry.autopilotController or nil
    if controller then
      record.controllerActive = controller.active
      record.controllerElapsed = round(controller.elapsed, 2)
      record.controllerPointIndex = controller.pointIndex
      record.controllerPointCount = controller.pointCount
      record.controllerPointDistance = optionalRound(controller.pointDistance, 3)
      record.controllerPointBestDistance = optionalRound(controller.pointBestDistance, 3)
      record.controllerPointNoProgress = optionalRound(controller.pointNoProgress, 3)
      record.controllerTargetSpeed = optionalRound(controller.targetSpeed, 2)
      record.controllerSteering = optionalRound(controller.steering, 3)
      record.controllerThrottle = optionalRound(controller.throttle, 3)
      record.controllerBrake = optionalRound(controller.brake, 3)
      record.controllerReversing = controller.reversing
      record.reverseRemaining = optionalRound(controller.reverseRemaining, 3)
      record.reverseSteering = optionalRound(controller.reverseSteering, 3)
      record.reverseFanClearance = optionalRound(controller.reverseFanClearance, 3)
      record.reverseTrajectoryClearance = optionalRound(controller.reverseTrajectoryClearance, 3)
      record.reverseRayCount = controller.reverseRayCount
      record.driveReady = controller.driveReady
      record.safetyBrake = optionalRound(controller.safetyBrake, 3)
      record.obstacleDistance = optionalRound(controller.obstacleDistance, 3)
      record.obstacleClosingSpeed = optionalRound(controller.obstacleClosingSpeed, 3)
      record.obstacleId = controller.obstacleId
      record.obstacleDetected = controller.obstacleDetected
      record.curvedPathRisk = controller.curvedPathRisk == true
      record.curvedPathRiskTime = optionalRound(controller.curvedPathRiskTime, 2)
      record.requestedDeceleration = optionalRound(controller.requestedDeceleration, 3)
      record.appliedDeceleration = optionalRound(controller.appliedDeceleration, 3)
      record.emergencyBraking = controller.emergencyBraking == true
      record.preflightFrontClearance = optionalRound(controller.preflightFrontClearance, 2)
      record.preflightRearClearance = optionalRound(controller.preflightRearClearance, 2)
    end
    if map and type(map.findClosestRoad) == "function" and vehiclePosition then
      local ok, nodeA, nodeB = pcall(map.findClosestRoad, vehiclePosition)
      if ok then record.currentRoadNodeA, record.currentRoadNodeB = nodeA, nodeB end
    end
    write("navigation_snapshot", record, flushTimer >= flushInterval)
    lastSnapshot = {targetDistance = targetDistance, position = position(vehiclePosition)}

    if lastSnapshot and record.targetDistanceDelta and record.targetDistanceDelta >= 12 then
      write("target_distance_increased", withContext({
        delta = record.targetDistanceDelta, distance = record.targetDistance,
        status = record.status, controllerMode = record.controllerMode
      }), true)
    end
  end

  return service
end

return M
