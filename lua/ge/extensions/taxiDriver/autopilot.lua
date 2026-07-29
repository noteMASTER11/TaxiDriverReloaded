local M = {}
local logger = require("taxiDriver/logger")
local aiDriverRoute = require("taxiDriver/aiDriverRoute")

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function distance(first, second)
  if not first or not second then return math.huge end
  if type(first.distance) == "function" then return first:distance(second) end
  local dx = number(first.x, 0) - number(second.x, 0)
  local dy = number(first.y, 0) - number(second.y, 0)
  local dz = number(first.z, 0) - number(second.z, 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copyPosition(value)
  if not value then return nil end
  return {x = number(value.x, 0), y = number(value.y, 0), z = number(value.z, 0)}
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

local function vehicleSpeedKmh(vehicle, callback)
  if type(callback) == "function" then
    local ok, value = pcall(callback, vehicle)
    if ok then return math.max(0, number(value, 0)) end
  end
  local velocity = vehicle and type(vehicle.getVelocity) == "function" and
    vehicle:getVelocity() or nil
  if not velocity then return 0 end
  local x, y, z = number(velocity.x, 0), number(velocity.y, 0), number(velocity.z, 0)
  return math.sqrt(x * x + y * y + z * z) * 3.6
end

local sessionCounter = 0

local function nextSessionId(vehicle)
  sessionCounter = sessionCounter + 1
  local vehicleId = vehicle and type(vehicle.getID) == "function" and
    number(vehicle:getID(), 0) or 0
  local stamp = type(os.clockhp) == "function" and os.clockhp() or os.clock()
  return string.format("%d-%d-%d", vehicleId,
    math.floor(math.max(0, number(stamp, 0)) * 1000), sessionCounter)
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local phases = options.phases or {}
  local trace = options.trace
  local route = aiDriverRoute.new({
    minimumDrivability = options.minimumDrivability,
    getRoutePath = options.getRoutePath
  })
  local service = {}
  local runtime = {
    enabled = false,
    suspended = false,
    status = "off",
    reason = "",
    sessionId = "",
    sequence = 0,
    routeRevision = 0,
    routeRequestPending = false,
    routeDirty = false,
    routeDone = false,
    routeDoneDistance = nil,
    routeDoneRetryCount = 0,
    routeNodes = {},
    routeSource = "",
    routeDiagnostics = nil,
    target = nil,
    targetKey = "",
    phase = nil,
    vehicleId = nil,
    targetDistance = nil,
    lastPosition = nil,
    movedDistance = 0,
    stationarySeconds = 0,
    stuckRecoveryAttempt = 0,
    stuckRecoveryPosition = nil,
    elapsed = 0,
    commandCount = 0,
    parking = nil,
    traceActive = false,
    profile = {
      aggression = 0.4,
      followingTimeGap = 2.3,
      minimumFollowingDistance = 4,
      brakingDeceleration = 3.5,
      predictiveWarningScale = 1,
      trafficWaitSeconds = 3,
      obeySpeedLimits = true,
      laneDiscipline = true,
      strictGpsRoute = false,
      allowOvertaking = true
    }
  }

  local function isDrivingPhase(phase)
    return phase == phases.toPickup or phase == phases.toStop or
      phase == phases.toDestination or phase == phases.toFuelStation
  end

  local function makeTargetKey(phase, target)
    local pos = target and target.pos
    return table.concat({
      tostring(phase or ""), tostring(target and target.nodeA or ""),
      tostring(target and target.nodeB or ""),
      string.format("%.1f", pos and number(pos.x, 0) or 0),
      string.format("%.1f", pos and number(pos.y, 0) or 0),
      string.format("%.1f", pos and number(pos.z, 0) or 0)
    }, "|")
  end

  local function queue(vehicle, command)
    if not vehicle or type(vehicle.queueLuaCommand) ~= "function" then return false end
    vehicle:queueLuaCommand(command)
    return true
  end

  local function resolveVehicle(vehicle)
    local sessionOwnsVehicle = runtime.vehicleId ~= nil and
      (runtime.enabled or runtime.parking ~= nil or runtime.status == "planning" or
        runtime.status == "driving" or runtime.status == "paused" or
        runtime.status == "parking")
    if sessionOwnsVehicle and vehicle and type(vehicle.getID) == "function" then
      local ok, id = pcall(vehicle.getID, vehicle)
      if ok and tonumber(id) == runtime.vehicleId then return vehicle end
    end
    if runtime.vehicleId and type(getObjectByID) == "function" then
      local ok, result = pcall(getObjectByID, runtime.vehicleId)
      if ok then return result end
    end
    -- Never transfer an active AI session to a newly supplied vehicle. If the
    -- original object disappeared, the caller must enter the parking fault
    -- path instead of sending commands to the replacement player vehicle.
    return sessionOwnsVehicle and nil or vehicle
  end

  local function vehicleId(vehicle)
    return vehicle and type(vehicle.getID) == "function" and
      tonumber(vehicle:getID()) or nil
  end

  local function isCurrentPlayerVehicle(vehicle)
    if not vehicle then return false end
    if type(options.isPlayerVehicle) == "function" then
      local ok, result = pcall(options.isPlayerVehicle, vehicle)
      if ok and result ~= nil then return result == true end
    end
    local id = vehicleId(vehicle)
    local playerId = be and type(be.getPlayerVehicleID) == "function" and
      tonumber(be:getPlayerVehicleID(0)) or nil
    if id and playerId then return id == playerId end
    if type(vehicle.isPlayerControlled) == "function" then
      local ok, result = pcall(vehicle.isPlayerControlled, vehicle)
      if ok then return result == true end
    end
    -- Headless tests do not expose BeamNG's player APIs. The gameplay
    -- orchestrator owns the identity guard in that environment.
    return true
  end

  local function nextSequence()
    runtime.sequence = runtime.sequence + 1
    return runtime.sequence
  end

  local function cancelRouteRequest(reason)
    if runtime.routeRequestPending and route and type(route.cancel) == "function" then
      local ok, errorMessage = pcall(route.cancel, route)
      if not ok then
        logger.warn("autopilot", "route_cancel_failed", {
          sessionId = runtime.sessionId,
          routeRevision = runtime.routeRevision,
          reason = reason,
          error = tostring(errorMessage)
        })
      end
    end
    runtime.routeRequestPending = false
  end

  local function routeStatus()
    if not route or type(route.getStatus) ~= "function" then return nil end
    local ok, result = pcall(route.getStatus, route)
    return ok and type(result) == "table" and result or nil
  end

  local function normalizedPath(result, target)
    local source = type(result) == "table" and
      (result.path or result.nodes or result.wpTargetList) or nil
    local nodes = {}
    for _, entry in ipairs(type(source) == "table" and source or {}) do
      if type(entry) == "table" then
        appendUnique(nodes, entry.wp or entry.node or entry.id)
      elseif type(entry) == "string" or type(entry) == "number" then
        appendUnique(nodes, entry)
      end
    end
    -- Capability fallback for sparse or community map planners. The dedicated
    -- route service remains authoritative; this only preserves a valid target
    -- edge when it reports success without an expanded waypoint list.
    if #nodes < 2 and target then
      appendUnique(nodes, target.nodeA)
      appendUnique(nodes, target.nodeB)
    end
    return nodes
  end

  local function observerConfig(sequence)
    local target = runtime.target or {}
    local pos, dir = target.pos or {}, target.dir or {}
    return table.concat({
      "{sessionId=", quote(runtime.sessionId),
      ",routeRevision=", tostring(runtime.routeRevision),
      ",sequence=", tostring(sequence),
      ",followingTimeGap=", string.format("%.2f", runtime.profile.followingTimeGap),
      ",minimumGap=", string.format("%.2f", runtime.profile.minimumFollowingDistance),
      ",brakingDeceleration=", string.format("%.2f", runtime.profile.brakingDeceleration),
      ",predictiveWarningScale=", string.format("%.2f", runtime.profile.predictiveWarningScale),
      ",routeSpeedMode=", quote(runtime.profile.obeySpeedLimits and "legal" or "off"),
      ",allowOvertaking=", runtime.profile.allowOvertaking and "true" or "false",
      ",targetX=", string.format("%.3f", number(pos.x, 0)),
      ",targetY=", string.format("%.3f", number(pos.y, 0)),
      ",targetZ=", string.format("%.3f", number(pos.z, 0)),
      ",targetDirX=", string.format("%.4f", number(dir.x, 0)),
      ",targetDirY=", string.format("%.4f", number(dir.y, 0)),
      ",arrivalRadius=", string.format("%.2f", number(options.arrivalRadius, 14)),
      -- The order state machine may tolerate a small sensor epsilon, but the
      -- AI speed target itself must be a complete stop.
      ",maximumArrivalSpeed=0",
      "}"
    })
  end

  local function issueNativeRoute(vehicle, nodes, result, reason)
    vehicle = resolveVehicle(vehicle)
    if not runtime.enabled or runtime.suspended or not vehicle or
      not isCurrentPlayerVehicle(vehicle) or #nodes < 2 then return false end

    local sequence = nextSequence()
    local laneMode = runtime.profile.laneDiscipline and "on" or "off"
    local command = table.concat({
      "extensions.load('taxiDriverStockAiObserver');",
      "local taxiObserver=extensions.taxiDriverStockAiObserver;",
      "if taxiObserver and type(taxiObserver.unwatch)=='function' then taxiObserver.unwatch() end;",
      "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry.setForcedStop(false) end;",
      "electrics.set_left_signal(false,false);electrics.set_right_signal(false,false);",
      "if ai and type(ai.driveUsingPath)=='function' then ",
      "ai.driveUsingPath({wpTargetList=", serializePath(nodes),
      ",noOfLaps=1,aggression=", string.format("%.2f", runtime.profile.aggression),
      ",avoidCars='on',driveInLane=", quote(laneMode),
      ",routeSpeedMode=", quote(runtime.profile.obeySpeedLimits and "legal" or "off"),
      ",targetSpeedSmootherRate=7,lookAheadKv=0.65,",
      "understeerThrottleControl='on',oversteerThrottleControl='on',",
      "throttleTcs='on',abBrakeControl='on',underSteerBrakeControl='on'});",
      -- BeamNG 0.39 applies these reliably after driveUsingPath initializes the
      -- native route. Every optional call is capability-gated for older builds.
      "if type(ai.setParameters)=='function' then ai.setParameters({",
      "awarenessForceCoef=0.35,trafficWaitTime=",
      string.format("%.2f", runtime.profile.trafficWaitSeconds),
      ",edgeDist=0,enableElectrics=true,targetSpeedSmootherRate=7}) end;",
      "if type(ai.setRacing)=='function' then ai.setRacing(false) end;",
      "if type(ai.setRecoverOnCrash)=='function' then ai.setRecoverOnCrash(false) end;",
      "if taxiObserver and type(taxiObserver.watch)=='function' then taxiObserver.watch(",
      observerConfig(sequence), ") end;",
      "else if taxiObserver and type(taxiObserver.fail)=='function' then taxiObserver.fail(",
      observerConfig(sequence), ",'nativeAiUnavailable') end end"
    })
    if not queue(vehicle, command) then return false end

    runtime.routeNodes = nodes
    runtime.routeSource = type(result) == "table" and
      tostring(result.source or "beamngRoute") or "beamngRoute"
    runtime.routeDiagnostics = type(result) == "table" and result.diagnostics or nil
    runtime.routeDirty = false
    runtime.routeDone = false
    runtime.routeDoneDistance = nil
    runtime.status = "driving"
    runtime.reason = tostring(reason or "")
    runtime.commandCount = runtime.commandCount + 1
    runtime.lastPosition = copyPosition(vehicle:getPosition())
    runtime.stationarySeconds = 0
    logger.info("autopilot", "route_started", {
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      sequence = sequence,
      nodes = #nodes,
      source = runtime.routeSource,
      reason = reason,
      commandCount = runtime.commandCount,
      aggression = runtime.profile.aggression,
      laneDiscipline = runtime.profile.laneDiscipline,
      allowOvertaking = runtime.profile.allowOvertaking
    })
    return true
  end

  local function completeTrace(reason)
    if not runtime.traceActive then return end
    runtime.traceActive = false
    if trace and type(trace.stop) == "function" then trace:stop(reason) end
  end

  local function commitPark(vehicle)
    vehicle = resolveVehicle(vehicle)
    if not vehicle or not runtime.parking or runtime.parking.commitSent then return false end
    local sequence = nextSequence()
    local command = table.concat({
      "local taxiObserver=extensions.taxiDriverStockAiObserver;",
      "if taxiObserver and type(taxiObserver.commitPark)=='function' then ",
      "taxiObserver.commitPark({sessionId=", quote(runtime.sessionId),
      ",routeRevision=", tostring(runtime.routeRevision),
      ",sequence=", tostring(sequence), "});",
      "else ",
      "if input and type(input.event)=='function' then ",
      "input.event('throttle',0,FILTER_AI,nil,nil,nil,'taxiDriverAiParking');",
      "input.event('brake',1,FILTER_AI,nil,nil,nil,'taxiDriverAiParking');",
      "input.event('parkingbrake',1,FILTER_AI,nil,nil,nil,'taxiDriverAiParking') end;",
      "if ai and type(ai.setMode)=='function' then ai.setMode('disabled') end end"
    })
    if not queue(vehicle, command) then return false end
    runtime.parking.commitSent = true
    runtime.parking.commitSequence = sequence
    logger.info("autopilot", "parking_commit_requested", {
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      sequence = sequence,
      reason = runtime.parking.reason
    })
    return true
  end

  local function finalizePark(vehicle, confirmation)
    if not runtime.parking then return end
    vehicle = resolveVehicle(vehicle)
    local sequence = nextSequence()
    if vehicle then
      queue(vehicle, table.concat({
        "if ai then ",
        "if type(ai.setRacing)=='function' then ai.setRacing(false) end;",
        "if type(ai.setPullOver)=='function' then ai.setPullOver(false) end;",
        "if type(ai.setRecoverOnCrash)=='function' then ai.setRecoverOnCrash(false) end;",
        "if type(ai.setSpeed)=='function' then ai.setSpeed(nil) end;",
        "if type(ai.setSpeedMode)=='function' then ai.setSpeedMode('off') end;",
        "if type(ai.setMode)=='function' then ai.setMode('disabled') end end;",
        "local taxiObserver=extensions.taxiDriverStockAiObserver;",
        "if taxiObserver and type(taxiObserver.onParkFinalized)=='function' then ",
        "taxiObserver.onParkFinalized({sessionId=", quote(runtime.sessionId),
        ",routeRevision=", tostring(runtime.routeRevision),
        ",sequence=", tostring(sequence), "}) end"
      }))
    end
    local reason = runtime.parking.reason
    runtime.parking = nil
    runtime.enabled = false
    runtime.suspended = false
    runtime.status = "parked"
    runtime.reason = reason
    runtime.routeRequestPending = false
    runtime.routeDirty = false
    runtime.routeDone = true
    logger.info("autopilot", "parked", {
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      sequence = sequence,
      reason = reason,
      confirmation = confirmation
    })
    completeTrace(reason)
  end

  local function requestPark(vehicle, reason)
    vehicle = resolveVehicle(vehicle)
    if runtime.parking then return true end
    cancelRouteRequest("parking")
    runtime.enabled = false
    runtime.suspended = false
    runtime.status = "parking"
    runtime.reason = tostring(reason or "requested")
    runtime.routeDirty = false
    runtime.parking = {
      reason = runtime.reason,
      elapsed = 0,
      stationarySeconds = 0,
      commandElapsed = 0,
      commitSent = false
    }
    if not vehicle then
      runtime.status = "fault"
      runtime.reason = "parkingVehicleMissing"
      logger.error("autopilot", "parking_vehicle_missing", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        reason = reason,
        vehicleId = runtime.vehicleId
      })
      completeTrace(runtime.reason)
      return false
    end
    local sequence = nextSequence()
    local command = table.concat({
      "local taxiObserver=extensions.taxiDriverStockAiObserver;",
      "if taxiObserver and type(taxiObserver.requestPark)=='function' then ",
      "taxiObserver.requestPark({sessionId=", quote(runtime.sessionId),
      ",routeRevision=", tostring(runtime.routeRevision),
      ",sequence=", tostring(sequence), ",reason=", quote(runtime.reason), "}) end;",
      "if ai then ",
      "if type(ai.setRacing)=='function' then ai.setRacing(false) end;",
      "if type(ai.setPullOver)=='function' then ai.setPullOver(false) end;",
      "if type(ai.setRecoverOnCrash)=='function' then ai.setRecoverOnCrash(false) end;",
      -- Never release native control while the vehicle may still be moving.
      "if type(ai.setMode)=='function' then ai.setMode('stop') end end"
    })
    if not queue(vehicle, command) then
      runtime.status = "fault"
      runtime.reason = "parkingCommandRejected"
      logger.error("autopilot", "parking_command_rejected", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        sequence = sequence
      })
      completeTrace(runtime.reason)
      return false
    end
    logger.info("autopilot", "parking_requested", {
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      sequence = sequence,
      reason = runtime.reason,
      speedKmh = vehicleSpeedKmh(vehicle, options.getSpeedKmh)
    })
    return true
  end

  local function routeFailure(vehicle, reason, fields)
    runtime.routeRequestPending = false
    runtime.status = "routeUnavailable"
    runtime.reason = tostring(reason or "routeUnavailable")
    fields = type(fields) == "table" and fields or {}
    fields.sessionId = runtime.sessionId
    fields.routeRevision = runtime.routeRevision
    fields.reason = runtime.reason
    logger.error("autopilot", "route_failed", fields)
    requestPark(vehicle, runtime.reason)
  end

  local function requestRoute(vehicle, reason)
    vehicle = resolveVehicle(vehicle)
    if not runtime.enabled or runtime.suspended then return false end
    if not vehicle or not isCurrentPlayerVehicle(vehicle) then
      requestPark(vehicle, "routeVehicleUnavailable")
      return false
    end
    if not runtime.target or not runtime.target.pos then
      requestPark(vehicle, "routeTargetUnavailable")
      return false
    end

    cancelRouteRequest("superseded")
    runtime.routeRevision = runtime.routeRevision + 1
    local requestedRevision = runtime.routeRevision
    local requestedSession = runtime.sessionId
    local requestedVehicleId = vehicleId(vehicle)
    local requestedTarget = runtime.target
    local requestedTargetKey = runtime.targetKey
    runtime.routeRequestPending = true
    runtime.routeDirty = false
    runtime.status = "planning"
    runtime.reason = tostring(reason or "")
    logger.info("autopilot", "route_requested", {
      sessionId = requestedSession,
      routeRevision = requestedRevision,
      reason = reason,
      vehicleId = requestedVehicleId
    })

    local callbackCalled = false
    local function onRoute(success, result, errorMessage)
      callbackCalled = true
      if requestedSession ~= runtime.sessionId or
        requestedRevision ~= runtime.routeRevision or
        requestedVehicleId ~= runtime.vehicleId then
        logger.warn("autopilot", "stale_route_callback_ignored", {
          sessionId = requestedSession,
          activeSessionId = runtime.sessionId,
          routeRevision = requestedRevision,
          activeRouteRevision = runtime.routeRevision
        })
        return false
      end
      runtime.routeRequestPending = false
      if success ~= true or type(result) ~= "table" then
        routeFailure(resolveVehicle(nil), errorMessage or
          (type(result) == "string" and result or "routePlannerRejected"), {
            plannerStatus = routeStatus()
          })
        return false
      end
      if result.routeRevision ~= nil and
        tonumber(result.routeRevision) ~= requestedRevision then
        logger.warn("autopilot", "route_result_revision_mismatch", {
          sessionId = requestedSession,
          routeRevision = requestedRevision,
          resultRouteRevision = result.routeRevision
        })
        routeFailure(resolveVehicle(nil), "routeResultRevisionMismatch", {
          resultRouteRevision = result.routeRevision
        })
        return false
      end
      if runtime.targetKey ~= requestedTargetKey then
        logger.warn("autopilot", "stale_route_target_ignored", {
          sessionId = requestedSession,
          routeRevision = requestedRevision,
          requestedTargetKey = requestedTargetKey,
          activeTargetKey = runtime.targetKey
        })
        return false
      end
      local nodes = normalizedPath(result, requestedTarget)
      if #nodes < 2 then
        routeFailure(resolveVehicle(nil), "routePathEmpty", {
          source = result.source,
          plannerStatus = routeStatus()
        })
        return false
      end
      local activeVehicle = resolveVehicle(nil)
      if not activeVehicle or not isCurrentPlayerVehicle(activeVehicle) or
        not runtime.enabled or runtime.suspended then
        logger.warn("autopilot", "route_result_no_longer_applicable", {
          sessionId = requestedSession,
          routeRevision = requestedRevision,
          vehiclePresent = activeVehicle ~= nil,
          enabled = runtime.enabled,
          suspended = runtime.suspended
        })
        if runtime.enabled and not runtime.suspended and not runtime.parking then
          requestPark(activeVehicle, "routeResultNoLongerApplicable")
        end
        return false
      end
      if not issueNativeRoute(activeVehicle, nodes, result, reason) then
        routeFailure(activeVehicle, "nativeRouteCommandRejected", {
          source = result.source,
          nodes = #nodes
        })
        return false
      end
      return true
    end

    local ok, accepted = pcall(route.request, route, vehicle, requestedTarget,
      requestedRevision, onRoute)
    if not ok or accepted == false then
      runtime.routeRequestPending = false
      routeFailure(vehicle, ok and "routeRequestRejected" or tostring(accepted), {
        requestError = ok and nil or tostring(accepted)
      })
      return false
    end
    -- Synchronous route services are permitted. If their callback already
    -- rejected the route, expose that failure to enable/resume immediately.
    return not callbackCalled or runtime.status == "driving"
  end

  function service:configure(profile)
    profile = type(profile) == "table" and profile or {}
    local aggression = clamp(number(profile.aggressionPercent, 40) / 100, 0.3, 0.85)
    local predictiveWarningScale = aggression <= 0.35 and 1.15 or
      aggression <= 0.45 and 1 or 0.9
    runtime.profile = {
      aggression = aggression,
      predictiveWarningScale = predictiveWarningScale,
      followingTimeGap = clamp(number(profile.followingTimeGap, 2.3), 1, 4),
      minimumFollowingDistance = clamp(number(profile.minimumFollowingDistance, 4), 2, 10),
      brakingDeceleration = clamp(number(profile.brakingDeceleration, 3.5), 2, 8),
      trafficWaitSeconds = clamp(number(profile.trafficWaitSeconds, 3), 1, 10),
      obeySpeedLimits = profile.obeySpeedLimits ~= false,
      laneDiscipline = profile.laneDiscipline ~= false,
      strictGpsRoute = profile.strictGpsRoute == true,
      allowOvertaking = profile.allowOvertaking ~= false
    }
  end

  function service:drawDebug()
  end

  function service:isEnabled()
    return runtime.enabled == true
  end

  function service:isParked()
    return runtime.enabled ~= true and runtime.parking == nil and
      runtime.status == "parked"
  end

  function service:isTargetAligned(vehicle, target)
    if not vehicle or not target or not target.dir or
      type(vehicle.getDirectionVector) ~= "function" then return false end
    local direction = vehicle:getDirectionVector()
    local targetX, targetY = number(target.dir.x, 0), number(target.dir.y, 0)
    local vehicleX, vehicleY = number(direction and direction.x, 0),
      number(direction and direction.y, 0)
    local targetLength = math.sqrt(targetX * targetX + targetY * targetY)
    local vehicleLength = math.sqrt(vehicleX * vehicleX + vehicleY * vehicleY)
    if targetLength < 0.01 or vehicleLength < 0.01 then return false end
    return (targetX * vehicleX + targetY * vehicleY) /
      (targetLength * vehicleLength) >= 0.45
  end

  function service:enable(vehicle, phase, target)
    vehicle = resolveVehicle(vehicle)
    if runtime.enabled and not runtime.parking then return true end
    if not vehicle or not isCurrentPlayerVehicle(vehicle) or
      not isDrivingPhase(phase) or not target or not target.pos then
      runtime.reason = "unavailable"
      return false
    end

    cancelRouteRequest("newSession")
    runtime.enabled = true
    runtime.suspended = false
    runtime.status = "planning"
    runtime.reason = ""
    runtime.sessionId = nextSessionId(vehicle)
    runtime.sequence = 0
    runtime.routeRevision = 0
    runtime.routeRequestPending = false
    runtime.routeDirty = false
    runtime.routeDone = false
    runtime.routeDoneDistance = nil
    runtime.routeDoneRetryCount = 0
    runtime.routeNodes = {}
    runtime.routeSource = ""
    runtime.routeDiagnostics = nil
    runtime.target = target
    runtime.phase = phase
    runtime.targetKey = makeTargetKey(phase, target)
    runtime.vehicleId = vehicleId(vehicle)
    runtime.targetDistance = distance(vehicle:getPosition(), target.pos)
    runtime.lastPosition = copyPosition(vehicle:getPosition())
    runtime.movedDistance = 0
    runtime.stationarySeconds = 0
    runtime.stuckRecoveryAttempt = 0
    runtime.stuckRecoveryPosition = nil
    runtime.elapsed = 0
    runtime.commandCount = 0
    runtime.parking = nil
    runtime.traceActive = false
    if trace and type(trace.start) == "function" then
      runtime.traceActive = trace:start(vehicle, phase, target) == true
    end
    logger.info("autopilot", "session_started", {
      sessionId = runtime.sessionId,
      vehicleId = runtime.vehicleId,
      phase = phase
    })
    if requestRoute(vehicle, "enabled") then return true end
    runtime.enabled = false
    return false
  end

  function service:disable(vehicle, reason, park)
    vehicle = resolveVehicle(vehicle)
    local wasActive = runtime.enabled or runtime.parking ~= nil or
      runtime.status == "planning" or runtime.status == "driving" or
      runtime.status == "paused"
    if not wasActive then
      runtime.enabled = false
      runtime.suspended = false
      runtime.reason = tostring(reason or runtime.reason or "")
      return false
    end
    -- Disabling while moving is always a controlled stop. The legacy park
    -- argument is retained for API compatibility but no longer permits a
    -- direct transition to native disabled mode.
    return requestPark(vehicle, reason or (park and "parkRequested" or "disabled"))
  end

  function service:park(vehicle, reason)
    return requestPark(resolveVehicle(vehicle), reason or "routeCompleted")
  end

  function service:toggle(vehicle, phase, target)
    if runtime.enabled or runtime.parking then
      self:disable(vehicle, "driver")
      return false
    end
    return self:enable(vehicle, phase, target)
  end

  function service:suspend(vehicle, value)
    value = value == true
    vehicle = resolveVehicle(vehicle)
    if not runtime.enabled or runtime.parking or runtime.suspended == value then return end
    runtime.suspended = value
    if value then
      cancelRouteRequest("suspended")
      runtime.status = "paused"
      runtime.reason = "suspended"
      local sequence = nextSequence()
      queue(vehicle, table.concat({
        "local taxiObserver=extensions.taxiDriverStockAiObserver;",
        "if taxiObserver and type(taxiObserver.pause)=='function' then taxiObserver.pause({sessionId=",
        quote(runtime.sessionId), ",routeRevision=", tostring(runtime.routeRevision),
        ",sequence=", tostring(sequence), "}) end;",
        "if ai and type(ai.setMode)=='function' then ai.setMode('stop') end"
      }))
      logger.info("autopilot", "suspended", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        sequence = sequence
      })
    else
      runtime.status = "planning"
      runtime.reason = "resumed"
      requestRoute(vehicle, "resumed")
    end
  end

  function service:markRouteDirty()
    if not runtime.enabled or runtime.parking then return end
    cancelRouteRequest("routeDirty")
    runtime.routeDirty = true
    runtime.routeDone = false
    runtime.status = runtime.suspended and "paused" or "planning"
  end

  local function parkingConfirmed(observation)
    if type(observation) ~= "table" then return false end
    return observation.parked == true or observation.parkingConfirmed == true or
      observation.mode == "parked" or observation.status == "parked"
  end

  local function updateParking(vehicle, dt)
    if not runtime.parking then return false end
    vehicle = resolveVehicle(vehicle)
    if not vehicle then
      runtime.status = "fault"
      runtime.reason = "parkingVehicleLost"
      logger.error("autopilot", "parking_vehicle_lost", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        vehicleId = runtime.vehicleId
      })
      completeTrace(runtime.reason)
      return false
    end

    dt = math.max(0, number(dt, 0))
    runtime.parking.elapsed = runtime.parking.elapsed + dt
    runtime.parking.commandElapsed = runtime.parking.commandElapsed + dt
    local speed = vehicleSpeedKmh(vehicle, options.getSpeedKmh)
    if speed <= 0.5 then
      runtime.parking.stationarySeconds = runtime.parking.stationarySeconds + dt
    else
      runtime.parking.stationarySeconds = 0
    end

    local observation = type(options.getSafetyObservation) == "function" and
      options.getSafetyObservation() or nil
    if parkingConfirmed(observation) then
      finalizePark(vehicle, "telemetry")
      return true
    end
    if runtime.parking.stationarySeconds >= 0.6 and
      not runtime.parking.commitSent then
      commitPark(vehicle)
    end
    if runtime.parking.commitSent and
      runtime.parking.stationarySeconds >= 1.5 and
      runtime.parking.commandElapsed >= 2 then
      -- Never report success from elapsed time alone. Reissue the idempotent
      -- parking transaction until telemetry confirms P/N and the handbrake.
      runtime.parking.commandElapsed = 0
      runtime.parking.commitSent = false
      logger.warn("autopilot", "parking_ack_pending", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        speedKmh = speed,
        elapsed = runtime.parking.elapsed
      })
      commitPark(vehicle)
    end
    if speed > 0.5 and runtime.parking.commandElapsed >= 2 then
      runtime.parking.commandElapsed = 0
      local sequence = nextSequence()
      queue(vehicle, table.concat({
        "local taxiObserver=extensions.taxiDriverStockAiObserver;",
        "if taxiObserver and type(taxiObserver.requestPark)=='function' then taxiObserver.requestPark({sessionId=",
        quote(runtime.sessionId), ",routeRevision=", tostring(runtime.routeRevision),
        ",sequence=", tostring(sequence), ",reason=", quote(runtime.parking.reason), "}) end;",
        "if ai and type(ai.setMode)=='function' then ai.setMode('stop') end"
      }))
      logger.warn("autopilot", "parking_stop_reasserted", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        sequence = sequence,
        speedKmh = speed
      })
    end
    return false
  end

  function service:update(vehicle, phase, target, dt)
    vehicle = resolveVehicle(vehicle)
    if runtime.parking then return updateParking(vehicle, dt) end
    if not runtime.enabled then return false end
    if not vehicle or not isCurrentPlayerVehicle(vehicle) then
      requestPark(vehicle, "playerVehicleChanged")
      return false
    end
    if not target or not target.pos or not isDrivingPhase(phase) then
      requestPark(vehicle, not target and "targetLost" or "phaseLost")
      return false
    end
    if runtime.vehicleId ~= vehicleId(vehicle) then
      requestPark(vehicle, "vehicleIdentityChanged")
      return false
    end
    if runtime.suspended then return false end

    local key = makeTargetKey(phase, target)
    if key ~= runtime.targetKey then
      cancelRouteRequest("targetChanged")
      runtime.target = target
      runtime.phase = phase
      runtime.targetKey = key
      runtime.routeDirty = true
      runtime.routeDoneRetryCount = 0
    end
    if runtime.routeDirty and not runtime.routeRequestPending then
      requestRoute(vehicle, "routeChanged")
    end

    dt = math.max(0, number(dt, 0))
    runtime.elapsed = runtime.elapsed + dt
    local position = vehicle:getPosition()
    local moved = runtime.lastPosition and distance(position, runtime.lastPosition) or 0
    runtime.lastPosition = copyPosition(position)
    runtime.movedDistance = runtime.movedDistance + moved
    runtime.targetDistance = distance(position, target.pos)
    local speed = vehicleSpeedKmh(vehicle, options.getSpeedKmh)
    if speed <= 1 and moved <= 0.1 then
      runtime.stationarySeconds = runtime.stationarySeconds + dt
    else
      runtime.stationarySeconds = 0
    end
    if runtime.stuckRecoveryAttempt > 0 and runtime.stuckRecoveryPosition and
      distance(position, runtime.stuckRecoveryPosition) >= 3 then
      logger.info("autopilot", "stuck_recovery_succeeded", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        attempt = runtime.stuckRecoveryAttempt
      })
      runtime.stuckRecoveryAttempt = 0
      runtime.stuckRecoveryPosition = nil
    end
    if runtime.status ~= "routeUnavailable" and not runtime.routeRequestPending then
      runtime.status = runtime.routeDone and "routeDone" or "driving"
    end

    -- Proximity is authoritative when the native route callback is absent.
    -- Eight metres keeps passenger pickups inside their stricter 10 m trigger.
    local completionRadius = math.min(8, math.max(2, number(options.arrivalRadius, 14)))
    if runtime.targetDistance <= completionRadius and
      speed <= math.max(0.5, number(options.maxArrivalSpeedKmh, 4)) then
      runtime.routeDone = true
      requestPark(vehicle, "targetReached")
    end

    -- Stock BeamNG taxi replans after making less than three metres of
    -- progress for ten seconds. Use the same inexpensive watchdog, with a
    -- longer grace period for ordinary traffic and a single recovery attempt.
    -- It also clears native AI's stale parking brake after an intermediate
    -- stop, which otherwise leaves some automatic/CVT vehicles in N forever.
    local safety = type(options.getSafetyObservation) == "function" and
      options.getSafetyObservation() or nil
    local closeLead = type(safety) == "table" and
      safety.leadConfirmed == true and
      number(safety.leadGap, math.huge) <=
        math.max(12, runtime.profile.minimumFollowingDistance * 2)
    local safetyHold = type(safety) == "table" and
      (safety.emergencyBraking == true or safety.safetyHolding == true or
        closeLead)
    local trafficAhead = type(safety) == "table" and
      (safety.leadConfirmed == true or safety.obstacleDetected == true)
    local stuckDelay = trafficAhead and 25 or
      math.max(15, runtime.profile.trafficWaitSeconds + 12)
    if closeLead and runtime.stationarySeconds >=
      runtime.profile.trafficWaitSeconds then
      runtime.status = "waitingTraffic"
    end
    if runtime.enabled and not runtime.parking and not runtime.routeRequestPending and
      runtime.status == "driving" and not safetyHold and
      runtime.targetDistance > completionRadius and
      runtime.stationarySeconds >= stuckDelay then
      runtime.stationarySeconds = 0
      if runtime.stuckRecoveryAttempt < 1 then
        runtime.stuckRecoveryAttempt = runtime.stuckRecoveryAttempt + 1
        runtime.stuckRecoveryPosition = copyPosition(position)
        logger.warn("autopilot", "stuck_recovery_requested", {
          sessionId = runtime.sessionId,
          routeRevision = runtime.routeRevision,
          attempt = runtime.stuckRecoveryAttempt,
          trafficAhead = trafficAhead,
          targetDistance = runtime.targetDistance
        })
        return requestRoute(vehicle, "stuckRecovery")
      end
      logger.error("autopilot", "stuck_recovery_exhausted", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        attempts = runtime.stuckRecoveryAttempt,
        targetDistance = runtime.targetDistance
      })
      requestPark(vehicle, "stuckAfterRecovery")
    end
    return false
  end

  function service:onRouteDone(vehicle, target, sessionId, routeRevision)
    vehicle = resolveVehicle(vehicle)
    if not runtime.enabled or runtime.suspended or runtime.parking then return false end
    if sessionId ~= nil and tostring(sessionId) ~= runtime.sessionId then
      logger.warn("autopilot", "stale_route_done_session_ignored", {
        sessionId = sessionId,
        activeSessionId = runtime.sessionId
      })
      return false
    end
    if routeRevision ~= nil and tonumber(routeRevision) ~= runtime.routeRevision then
      logger.warn("autopilot", "stale_route_done_revision_ignored", {
        sessionId = runtime.sessionId,
        routeRevision = routeRevision,
        activeRouteRevision = runtime.routeRevision
      })
      return false
    end
    target = target or runtime.target
    runtime.routeDoneDistance = vehicle and target and target.pos and
      distance(vehicle:getPosition(), target.pos) or math.huge
    local completionRadius = math.min(8,
      math.max(2, number(options.arrivalRadius, 14)))
    if runtime.routeDoneDistance > completionRadius and
      runtime.routeDoneRetryCount < 3 then
      runtime.routeDoneRetryCount = runtime.routeDoneRetryCount + 1
      runtime.routeDone = false
      runtime.status = "planning"
      runtime.reason = "prematureNativeRouteDone"
      logger.warn("autopilot", "route_done_before_target", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        targetDistance = runtime.routeDoneDistance,
        retry = runtime.routeDoneRetryCount
      })
      return requestRoute(vehicle, "prematureRouteDone")
    end
    if runtime.routeDoneDistance > completionRadius then
      runtime.routeDone = false
      runtime.status = "routeUnavailable"
      runtime.reason = "routeDoneOutsideTarget"
      logger.error("autopilot", "route_done_recovery_exhausted", {
        sessionId = runtime.sessionId,
        routeRevision = runtime.routeRevision,
        targetDistance = runtime.routeDoneDistance,
        completionRadius = completionRadius,
        retries = runtime.routeDoneRetryCount
      })
      requestPark(vehicle, "routeDoneOutsideTarget")
      return false
    end
    runtime.routeDone = true
    runtime.status = "routeDone"
    runtime.reason = "nativeRouteDone"
    logger.info("autopilot", "route_done", {
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      targetDistance = runtime.routeDoneDistance,
      reachedGameplayRadius = runtime.routeDoneDistance <= completionRadius
    })
    requestPark(vehicle, "nativeRouteDone")
    return true
  end

  function service:onBypassComplete()
    -- Retained for callers from older savegames and Fleet callback routing.
    return false
  end

  function service:getHud(available, vehicle)
    return {
      available = available == true and vehicle ~= nil,
      enabled = runtime.enabled == true,
      suspended = runtime.suspended == true,
      status = runtime.status,
      reason = runtime.reason,
      stuckSeconds = runtime.stationarySeconds,
      recoveryAttempt = 0,
      stockAi = true,
      sessionId = runtime.sessionId,
      routeRevision = runtime.routeRevision,
      parking = runtime.parking ~= nil
    }
  end

  function service:getDiagnostics(vehicle, target, phase)
    vehicle = resolveVehicle(vehicle)
    target = target or runtime.target
    local targetDistance = vehicle and target and target.pos and
      distance(vehicle:getPosition(), target.pos) or runtime.targetDistance
    local safety = type(options.getSafetyObservation) == "function" and
      options.getSafetyObservation() or nil
    safety = type(safety) == "table" and safety or {}
    local planner = routeStatus() or {}
    return {
      status = runtime.status,
      reason = runtime.reason,
      phase = phase or runtime.phase,
      sessionId = runtime.sessionId,
      sequence = runtime.sequence,
      routeRevision = runtime.routeRevision,
      routePending = runtime.routeRequestPending,
      routeSource = runtime.routeSource,
      routePlannerStatus = planner.status,
      routePlannerReason = planner.error or planner.reason,
      routeDiagnostics = runtime.routeDiagnostics,
      targetKey = runtime.targetKey,
      targetDistance = targetDistance,
      routeNodeCount = #runtime.routeNodes,
      routeDone = runtime.routeDone == true,
      routeDoneDistance = runtime.routeDoneDistance,
      routeDoneRetryCount = runtime.routeDoneRetryCount,
      stationarySeconds = runtime.stationarySeconds,
      stuckRecoveryAttempt = runtime.stuckRecoveryAttempt,
      movedDistance = runtime.movedDistance,
      elapsed = runtime.elapsed,
      commandCount = runtime.commandCount,
      speedKmh = vehicleSpeedKmh(vehicle, options.getSpeedKmh),
      parking = runtime.parking ~= nil,
      parkingElapsed = runtime.parking and runtime.parking.elapsed or nil,
      parkingStationarySeconds = runtime.parking and
        runtime.parking.stationarySeconds or nil,
      parkingCommitSent = runtime.parking and runtime.parking.commitSent or false,
      leadVehicleId = safety.obstacleId,
      leadGap = safety.obstacleDistance,
      leadSpeed = safety.leadSpeed,
      leadClosingSpeed = safety.obstacleClosingSpeed,
      leadTtc = safety.timeToCollision,
      leadConfirmed = safety.obstacleDetected == true,
      curvedPathRisk = safety.curvedPathRisk == true,
      curvedPathRiskTime = safety.curvedPathRiskTime,
      followSpeedCap = safety.targetSpeed,
      appliedSpeedCap = safety.targetSpeed,
      requestedDeceleration = safety.requestedDeceleration,
      appliedDeceleration = safety.appliedDeceleration,
      emergencyBraking = safety.emergencyBraking == true,
      targetApproachActive = safety.targetApproachActive == true,
      targetApproachDistance = safety.targetDistance,
      targetApproachSpeedCap = safety.targetSpeedCap,
      controllerMode = safety.mode or safety.status,
      controllerAge = safety.age,
      stockAi = true,
      trafficGuard = true,
      customPerception = false,
      customRecovery = false
    }
  end

  return service
end

return M
