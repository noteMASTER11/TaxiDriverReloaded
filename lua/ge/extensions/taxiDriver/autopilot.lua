local M = {}
local logger = require("taxiDriver/logger")
local perceptionModule = require("taxiDriver/autopilotPerception")

local defaults = {
  obeySpeedLimits = true,
  obeyTrafficSignals = true,
  allowOvertaking = true,
  allowOncomingRecovery = true,
  allowReverseRecovery = true,
  maxRecoveryAttempts = 3,
  normalAggression = 0.3,
  stuckDelay = 15,
  recoveryRetryInterval = 8,
  recoverySuccessDistance = 8,
  signalHoldDistance = 120,
  approachDistance = 45,
  finalApproachDistance = 20,
  stopDistance = 8,
  approachSpeed = 8,
  finalApproachSpeed = 3.5,
  stoppedSpeedKmh = 1.5,
  movingSpeedKmh = 4,
  oncomingRetryInterval = 2,
  signalQueueReleaseDelay = 4,
  signalQueueDistanceMargin = 35,
  reverseEscapeMinDistance = 3,
  reverseEscapeMaxDistance = 6,
  reverseEscapeSpeed = 2.2,
  reverseEscapeTimeout = 10,
  bypassControllerSpeed = 7,
  bypassControllerTimeout = 14,
  bypassClearance = 0.7,
  followTimeGap = 2.2,
  followMinimumGap = 7,
  followEmergencyGap = 3.5,
  followComfortableDeceleration = 2.8,
  followGapResponseTime = 4,
  followScanDistance = 160,
  followScanInterval = 0.2,
  followLaneMargin = 0.9,
  signalLookAhead = 160,
  signalLaneHalfWidth = 12,
  signalStopBuffer = 5,
  signalComfortableDeceleration = 3,
  yellowDecisionDeceleration = 3.5,
  intersectionClearDistance = 30,
  directApproachDistance = 48,
  directApproachDelay = 0.4,
  directApproachSpeed = 3.5,
  directApproachTimeout = 20,
  laneChangeLeadDistance = 35,
  laneChangeLeadHold = 2,
  laneChangeRoadAlignment = 0.96,
  laneChangeIntersectionDistance = 65,
  laneChangeWidth = 3.6,
  laneChangeDistance = 35,
  laneChangeDuration = 5,
  laneChangeCooldown = 20,
  laneChangeFreeAhead = 55,
  laneChangeFreeBehind = 22
}

local function copyConfig(source)
  local result = {}
  for key, value in pairs(defaults) do result[key] = value end
  for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
  return result
end

local function quote(value)
  return string.format("%q", tostring(value))
end

local function vectorDistance(first, second)
  if not first or not second then return math.huge end
  if type(first.distance) == "function" then return first:distance(second) end
  local dx = (tonumber(first.x) or 0) - (tonumber(second.x) or 0)
  local dy = (tonumber(first.y) or 0) - (tonumber(second.y) or 0)
  local dz = (tonumber(first.z) or 0) - (tonumber(second.z) or 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copyPosition(pos)
  if not pos then return nil end
  return {x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0, z = tonumber(pos.z) or 0}
end

local function targetKey(phase, target)
  local pos = target and target.pos
  return table.concat({
    tostring(phase or ""), tostring(target and target.nodeA or ""),
    tostring(target and target.nodeB or ""),
    string.format("%.1f", pos and tonumber(pos.x) or 0),
    string.format("%.1f", pos and tonumber(pos.y) or 0),
    string.format("%.1f", pos and tonumber(pos.z) or 0)
  }, "|")
end

local function appendUnique(nodes, value)
  if value == nil or value == "" then return end
  value = tostring(value)
  if nodes[#nodes] ~= value then nodes[#nodes + 1] = value end
end

local function serializePath(nodes)
  local values = {}
  for _, node in ipairs(nodes) do values[#values + 1] = quote(node) end
  return "{" .. table.concat(values, ",") .. "}"
end

function M.new(options)
  options = options or {}
  local config = copyConfig(options.config)
  local baseLaneChangeFreeAhead = config.laneChangeFreeAhead
  local baseLaneChangeFreeBehind = config.laneChangeFreeBehind
  local perception = perceptionModule.new(config)
  local phases = options.phases or {}
  local service = {}
  local runtime = {
    enabled = false,
    suspended = false,
    status = "off",
    reason = "",
    targetKey = "",
    routeNodes = {},
    routePending = false,
    routeRetryTimer = 0,
    stopIssued = false,
    approachStage = 0,
    stuckSeconds = 0,
    recoveryAttempt = 0,
    recoveryExhausted = false,
    recoverySeconds = 0,
    recoveryStartPos = nil,
    recoveryStartDir = nil,
    recoveryStartDistance = math.huge,
    recoveryController = false,
    controllerMode = nil,
    recoveryTrafficWait = 0,
    recoveryClearTimer = 0,
    reverseSourceReason = nil,
    followScanTimer = 0,
    followSpeedCap = nil,
    followLeadId = nil,
    signalSpeedCap = nil,
    activeSignalId = nil,
    upcomingSignal = nil,
    intersectionActive = false,
    intersectionTravel = 0,
    intersectionLastPos = nil,
    laneChangeTimer = 0,
    laneChangeCooldown = 0,
    laneChangeLeadTimer = 0,
    routeDonePending = false,
    routeDoneRetryTimer = 0,
    appliedSpeedCap = nil,
    bestDistance = math.huge
  }

  local function isDrivingPhase(phase)
    return phase == phases.toPickup or phase == phases.toStop or
      phase == phases.toDestination or phase == phases.toFuelStation
  end

  local function isPausePhase(phase)
    return phase == phases.boarding or phase == phases.stopWaiting
  end

  local function queue(vehicle, command)
    if not vehicle or type(vehicle.queueLuaCommand) ~= "function" then return false end
    vehicle:queueLuaCommand(command)
    return true
  end

  local function vehicleSupported(vehicle)
    if not vehicle then return false end
    if type(vehicle.getWheelCount) == "function" then
      return (tonumber(vehicle:getWheelCount()) or 0) > 0
    end
    return true
  end

  local function vectorLength(value)
    if not value then return 0 end
    if type(value.length) == "function" then return value:length() end
    local x, y, z = tonumber(value.x) or 0, tonumber(value.y) or 0, tonumber(value.z) or 0
    return math.sqrt(x * x + y * y + z * z)
  end

  local function vehicleDimension(vehicle, method, fallback)
    if vehicle and type(vehicle[method]) == "function" then
      local ok, value = pcall(vehicle[method], vehicle)
      if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
    end
    return fallback
  end

  local function findLeadVehicle(vehicle)
    if not map or type(map.objects) ~= "table" or not vehicle then return nil end
    local position = vehicle:getPosition()
    local direction = type(vehicle.getDirectionVector) == "function" and vehicle:getDirectionVector() or nil
    if not position or not direction then return nil end
    local planarLength = math.sqrt((tonumber(direction.x) or 0) ^ 2 + (tonumber(direction.y) or 0) ^ 2)
    if planarLength < 0.1 then return nil end
    local forwardX, forwardY = (tonumber(direction.x) or 0) / planarLength,
      (tonumber(direction.y) or 0) / planarLength
    local ownId = type(vehicle.getID) == "function" and vehicle:getID() or nil
    local ownLength = vehicleDimension(vehicle, "getInitialLength", 4.5)
    local ownWidth = vehicleDimension(vehicle, "getInitialWidth", 2)
    local best = nil
    for id, data in pairs(map.objects) do
      if id ~= ownId and data and data.pos then
        local dx = (tonumber(data.pos.x) or 0) - (tonumber(position.x) or 0)
        local dy = (tonumber(data.pos.y) or 0) - (tonumber(position.y) or 0)
        local longitudinal = dx * forwardX + dy * forwardY
        if longitudinal > 0 and longitudinal <= config.followScanDistance then
          local lateral = math.abs(-dx * forwardY + dy * forwardX)
          local other = type(getObjectByID) == "function" and getObjectByID(id) or nil
          local otherWidth = vehicleDimension(other, "getInitialWidth", 2)
          if lateral <= (ownWidth + otherWidth) * 0.5 + config.followLaneMargin then
            local otherDir = data.dirVec or data.dir
            local aligned = true
            if otherDir then
              local otherDirLength = math.sqrt((tonumber(otherDir.x) or 0) ^ 2 +
                (tonumber(otherDir.y) or 0) ^ 2)
              aligned = otherDirLength < 0.1 or
                ((tonumber(otherDir.x) or 0) * forwardX + (tonumber(otherDir.y) or 0) * forwardY) /
                  otherDirLength > 0.5
            end
            if aligned then
              local otherLength = vehicleDimension(other, "getInitialLength", 4.5)
              local gap = math.max(0, longitudinal - (ownLength + otherLength) * 0.5)
              if not best or gap < best.gap then
                local velocity = data.vel
                local leadSpeed = velocity and math.max(0,
                  (tonumber(velocity.x) or 0) * forwardX + (tonumber(velocity.y) or 0) * forwardY) or 0
                best = {gap = gap, speed = leadSpeed, rawSpeed = vectorLength(velocity), id = id}
              end
            end
          end
        end
      end
    end
    return best
  end

  local function laneChangeCandidate(vehicle)
    if not map or type(map.getMap) ~= "function" or type(map.findClosestRoad) ~= "function" or
      type(map.objects) ~= "table" then return nil end
    local position = vehicle:getPosition()
    local direction = vehicle:getDirectionVector()
    local mapData = map.getMap()
    local nodes = mapData and mapData.nodes
    local nodeA, nodeB = map.findClosestRoad(position)
    local first, second = nodes and nodes[nodeA], nodes and nodes[nodeB]
    if not first or not second or not first.pos or not second.pos then return nil end
    local link = (first.links and first.links[nodeB]) or (second.links and second.links[nodeA])
    if not link then return nil end

    local fromNode, toNode = nodeA, nodeB
    local roadX = (tonumber(second.pos.x) or 0) - (tonumber(first.pos.x) or 0)
    local roadY = (tonumber(second.pos.y) or 0) - (tonumber(first.pos.y) or 0)
    local roadLength = math.sqrt(roadX * roadX + roadY * roadY)
    if roadLength < 1 then return nil end
    roadX, roadY = roadX / roadLength, roadY / roadLength
    local directionLength = math.sqrt((tonumber(direction.x) or 0) ^ 2 +
      (tonumber(direction.y) or 0) ^ 2)
    if directionLength < 0.1 then return nil end
    local roadAlignment = (roadX * (tonumber(direction.x) or 0) +
      roadY * (tonumber(direction.y) or 0)) / directionLength
    if roadAlignment < 0 then
      fromNode, toNode, first, second = toNode, fromNode, second, first
      roadX, roadY = -roadX, -roadY
      roadAlignment = -roadAlignment
    end
    if roadAlignment < config.laneChangeRoadAlignment then return nil end

    local forwardLanes = 0
    if type(link.lanes) == "string" and #link.lanes > 0 then
      local sameOrientation = link.inNode == nil or tostring(link.inNode) == tostring(fromNode)
      local wanted = sameOrientation and "+" or "-"
      for index = 1, #link.lanes do
        if link.lanes:sub(index, index) == wanted then forwardLanes = forwardLanes + 1 end
      end
    else
      local totalLanes = math.max(1, math.floor(math.min(tonumber(first.radius) or 0,
        tonumber(second.radius) or 0) * 2 / 3.61 + 0.5))
      forwardLanes = link.oneWay and totalLanes or math.max(1, math.floor(totalLanes * 0.5))
    end
    if forwardLanes < 2 then return nil end

    local baseX, baseY = tonumber(first.pos.x) or 0, tonumber(first.pos.y) or 0
    local along = ((tonumber(position.x) or 0) - baseX) * roadX +
      ((tonumber(position.y) or 0) - baseY) * roadY
    along = math.max(0, math.min(roadLength, along))
    local centerX, centerY = baseX + roadX * along, baseY + roadY * along
    local leftX, leftY = -roadY, roadX
    local currentLateral = ((tonumber(position.x) or 0) - centerX) * leftX +
      ((tonumber(position.y) or 0) - centerY) * leftY
    if not link.oneWay and math.abs(currentLateral) < 0.8 then return nil end
    local roadHalfWidth = math.min(tonumber(first.radius) or 0, tonumber(second.radius) or 0)
    if math.abs(currentLateral) < config.laneChangeWidth + 0.5 then return nil end
    local candidates = {currentLateral > 0 and -config.laneChangeWidth or config.laneChangeWidth}
    local ownId = type(vehicle.getID) == "function" and vehicle:getID() or nil
    for _, shift in ipairs(candidates) do
      local targetLateral = currentLateral + shift
      local sameDirection = link.oneWay or currentLateral * targetLateral > 0
      if sameDirection and math.abs(targetLateral) <= roadHalfWidth - 1.4 then
        local clear = true
        for id, data in pairs(map.objects) do
          if id ~= ownId and data and data.pos then
            local dx = (tonumber(data.pos.x) or 0) - (tonumber(position.x) or 0)
            local dy = (tonumber(data.pos.y) or 0) - (tonumber(position.y) or 0)
            local longitudinal = dx * roadX + dy * roadY
            local lateral = dx * leftX + dy * leftY
            if longitudinal >= -config.laneChangeFreeBehind and
              longitudinal <= config.laneChangeFreeAhead and math.abs(lateral - shift) <= 2.4 then
              clear = false
              break
            end
          end
        end
        if clear then return shift, forwardLanes end
      end
    end
    return nil
  end

  local function tryLaneChange(vehicle, lead, speedKmh, signal)
    if not config.allowOvertaking or runtime.laneChangeTimer > 0 or runtime.laneChangeCooldown > 0 or
      not lead or lead.gap > config.laneChangeLeadDistance or
      runtime.laneChangeLeadTimer < config.laneChangeLeadHold or
      (signal and signal.distance < config.laneChangeIntersectionDistance) then return false end
    local egoSpeed = math.max(0, (tonumber(speedKmh) or 0) / 3.6)
    if lead.speed > math.max(8, egoSpeed - 1) and lead.gap > config.followMinimumGap then return false end
    local shift, lanes = laneChangeCandidate(vehicle)
    if not shift then return false end
    runtime.laneChangeTimer = config.laneChangeDuration
    local signalCommand = shift > 0 and
      "electrics.set_left_signal(true,false); electrics.set_right_signal(false,false); " or
      "electrics.set_right_signal(true,false); electrics.set_left_signal(false,false); "
    queue(vehicle, signalCommand .. 'ai.setAvoidCars("on"); ai.driveInLane("off"); ai.laneChange(nil,' ..
      tostring(config.laneChangeDistance) .. ',' .. tostring(-shift) .. ')')
    logger.info("autopilot", "overtake_lane_change_started", {lanes = lanes, lead = lead.id, shift = shift})
    return true
  end

  local function updateLaneChange(vehicle, dt)
    runtime.laneChangeCooldown = math.max(0, runtime.laneChangeCooldown - dt)
    if runtime.laneChangeTimer <= 0 then return end
    runtime.laneChangeTimer = math.max(0, runtime.laneChangeTimer - dt)
    if runtime.laneChangeTimer == 0 then
      runtime.laneChangeCooldown = config.laneChangeCooldown
      queue(vehicle, 'electrics.set_left_signal(false,false); electrics.set_right_signal(false,false); ai.driveInLane("on")')
      logger.info("autopilot", "overtake_lane_change_completed")
    end
  end

  local function applySpeedCap(vehicle, cap)
    cap = cap and math.max(0, tonumber(cap) or 0) or nil
    local previous = runtime.appliedSpeedCap
    if cap == nil and previous == nil then return end
    if cap ~= nil and previous ~= nil and math.abs(cap - previous) < 0.35 then return end
    runtime.appliedSpeedCap = cap
    if cap == nil then queue(vehicle, 'ai.setSpeed(nil); ai.setSpeedMode("' ..
      (config.obeySpeedLimits and 'legal' or 'off') .. '")')
    else queue(vehicle, 'ai.setSpeed(' .. string.format("%.3f", cap) .. '); ai.setSpeedMode("limit")') end
  end

  local findUpcomingSignal

  local function updateFollowing(vehicle, distance, speedKmh, dt)
    runtime.followScanTimer = runtime.followScanTimer - dt
    if runtime.followScanTimer <= 0 then
      runtime.followScanTimer = config.followScanInterval
      local lead = findLeadVehicle(vehicle)
      if lead and lead.id ~= runtime.followLeadId then
        logger.info("autopilot", "lead_vehicle_acquired", {id = lead.id, gap = lead.gap})
      elseif not lead and runtime.followLeadId ~= nil then
        logger.info("autopilot", "lead_vehicle_released", {id = runtime.followLeadId})
      end
      runtime.followLeadId = lead and lead.id or nil
      if lead and lead.gap <= config.laneChangeLeadDistance then
        runtime.laneChangeLeadTimer = runtime.laneChangeLeadTimer + config.followScanInterval
      else
        runtime.laneChangeLeadTimer = 0
      end
      runtime.followSpeedCap = nil
      if lead then
        local egoSpeed = math.max(0, speedKmh / 3.6)
        local desiredGap = config.followMinimumGap + egoSpeed * config.followTimeGap
        local closingSpeed = math.max(0, egoSpeed - lead.speed)
        local ttc = lead.gap / math.max(0.01, closingSpeed)
        local cap
        if lead.gap <= config.followEmergencyGap or (closingSpeed > 2 and ttc < 1.25) then
          cap = 0
        elseif closingSpeed > 2 then
          cap = math.sqrt(math.max(0, lead.speed * lead.speed +
            2 * config.followComfortableDeceleration * math.max(0, lead.gap - config.followMinimumGap)))
        else
          cap = lead.speed + (lead.gap - desiredGap) / config.followGapResponseTime
        end
        cap = math.max(0, cap)
        if cap < egoSpeed + 0.5 or lead.gap < desiredGap then runtime.followSpeedCap = cap end
      end

      local signal = findUpcomingSignal(vehicle)
      if signal and signal.id ~= runtime.activeSignalId then
        logger.info("autopilot", "traffic_signal_acquired", {
          id = signal.id, state = signal.state, action = signal.action, distance = signal.distance
        })
      elseif not signal and runtime.activeSignalId ~= nil then
        logger.info("autopilot", "traffic_signal_released", {id = runtime.activeSignalId})
      end
      runtime.activeSignalId = signal and signal.id or nil
      runtime.upcomingSignal = signal
      runtime.signalSpeedCap = nil
      if signal and (signal.action == 1 or signal.action == 2) then
        local egoSpeed = math.max(0, speedKmh / 3.6)
        local gap = math.max(0, signal.distance - config.signalStopBuffer)
        local yellowStoppingDistance = egoSpeed * egoSpeed /
          (2 * config.yellowDecisionDeceleration) + config.signalStopBuffer
        local shouldStop = signal.action == 2 or signal.distance >= yellowStoppingDistance * 0.55
        if shouldStop then
          local cap = math.sqrt(math.max(0, 2 * config.signalComfortableDeceleration * gap))
          if gap <= 1.5 then cap = 0 end
          if cap < egoSpeed + 0.5 then runtime.signalSpeedCap = cap end
        end
      end
      if runtime.laneChangeTimer > 0 or tryLaneChange(vehicle, lead, speedKmh, signal) then
        runtime.laneChangeLeadTimer = 0
      end
    end

    local approachCap = nil
    if distance <= config.finalApproachDistance then approachCap = config.finalApproachSpeed
    elseif distance <= config.approachDistance then approachCap = config.approachSpeed end
    local cap = runtime.followSpeedCap
    if runtime.signalSpeedCap ~= nil then
      cap = cap and math.min(cap, runtime.signalSpeedCap) or runtime.signalSpeedCap
    end
    if approachCap ~= nil then cap = cap and math.min(cap, approachCap) or approachCap end
    applySpeedCap(vehicle, cap)
    return runtime.followLeadId, runtime.upcomingSignal
  end

  local function getRoutePath()
    if type(options.getRoutePath) == "function" then
      local ok, path = pcall(options.getRoutePath)
      if ok and type(path) == "table" then return path end
    end
    local planner = core_groundMarkers and core_groundMarkers.routePlanner or nil
    return planner and type(planner.path) == "table" and planner.path or {}
  end

  local function buildRouteNodes(vehicle, target)
    local nodes = {}
    for _, entry in ipairs(getRoutePath()) do
      if type(entry) == "table" then appendUnique(nodes, entry.wp) end
    end

    if #nodes < 2 and map and type(map.findClosestRoad) == "function" and
      map.getGraphpath and vehicle and target and target.pos then
      local startA, startB = map.findClosestRoad(vehicle:getPosition())
      local targetA, targetB = target.nodeA, target.nodeB
      if not targetA or not targetB then targetA, targetB = map.findClosestRoad(target.pos) end
      local graph = map.getGraphpath()
      if graph and type(graph.getPath) == "function" then
        local ok, fallback = pcall(function()
          return graph:getPath(startB or startA, targetA or targetB)
        end)
        if ok and type(fallback) == "table" then
          nodes = {}
          appendUnique(nodes, startA)
          for _, node in ipairs(fallback) do appendUnique(nodes, node) end
        end
      end
    end

    if target then
      if #nodes == 0 then appendUnique(nodes, target.nodeA) end
      appendUnique(nodes, target.nodeB)
    end
    return nodes
  end

  local function normalCommand(nodes)
    return table.concat({
      "extensions.load('taxiDriverAutopilotRecovery');",
      "if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.watchRouteDone(); extensions.taxiDriverAutopilotRecovery.setSafetyConfig({timeGap=",
      tostring(config.followTimeGap), ",comfortableDeceleration=",
      tostring(config.followComfortableDeceleration), "}); extensions.taxiDriverAutopilotRecovery.setGearboxOverride(true) end;",
      "ai.setRecoverOnCrash(false);",
      "ai.setParameters({awarenessForceCoef=0.25,trafficWaitTime=2,edgeDist=0,enableElectrics=true});",
      "ai.driveUsingPath({path=", serializePath(nodes),
      ",noOfLaps=1,aggression=", tostring(config.normalAggression),
      ",avoidCars=\"on\",driveInLane=\"on\",routeSpeedMode=\"",
      config.obeySpeedLimits and "legal" or "off", "\"})"
    })
  end

  local function issueRoute(vehicle, target)
    local nodes = buildRouteNodes(vehicle, target)
    if #nodes < 2 then return false end
    if not queue(vehicle, normalCommand(nodes)) then return false end
    runtime.routeNodes = nodes
    runtime.routePending = false
    runtime.routeRetryTimer = 0
    runtime.stopIssued = false
    runtime.approachStage = 0
    runtime.followScanTimer = 0
    runtime.followSpeedCap = nil
    runtime.followLeadId = nil
    runtime.signalSpeedCap = nil
    runtime.activeSignalId = nil
    runtime.upcomingSignal = nil
    runtime.appliedSpeedCap = nil
    runtime.recoveryController = false
    runtime.controllerMode = nil
    runtime.status = "driving"
    runtime.reason = ""
    logger.info("autopilot", "route_started", {nodes = #nodes})
    return true
  end

  local function stopAi(vehicle)
    queue(vehicle,
      'electrics.set_left_signal(false,false); electrics.set_right_signal(false,false); ai.setRecoverOnCrash(false); ai.setAvoidCars("on"); ai.driveInLane("on"); ai.setMode("stop")')
  end

  findUpcomingSignal = function(vehicle)
    if not config.obeyTrafficSignals or not core_trafficSignals or type(core_trafficSignals.getMapNodeSignals) ~= "function" or
      not vehicle or runtime.intersectionActive then return nil end
    local signals = core_trafficSignals.getMapNodeSignals()
    local vehiclePos = vehicle:getPosition()
    local vehicleDir = type(vehicle.getDirectionVector) == "function" and vehicle:getDirectionVector() or nil
    if not signals or not vehiclePos or not vehicleDir then return nil end
    local dirLength = math.sqrt((tonumber(vehicleDir.x) or 0) ^ 2 + (tonumber(vehicleDir.y) or 0) ^ 2)
    if dirLength < 0.1 then return nil end
    local dirX, dirY = (tonumber(vehicleDir.x) or 0) / dirLength,
      (tonumber(vehicleDir.y) or 0) / dirLength
    local routeEdges = {}
    for index = 1, #runtime.routeNodes - 1 do
      routeEdges[tostring(runtime.routeNodes[index]) .. "\0" .. tostring(runtime.routeNodes[index + 1])] = true
    end
    local best = nil
    for fromNode, outbound in pairs(signals) do
      for toNode, entries in pairs(type(outbound) == "table" and outbound or {}) do
        local routeMatch = routeEdges[tostring(fromNode) .. "\0" .. tostring(toNode)] == true
        for _, signal in ipairs(type(entries) == "table" and entries or {}) do
          if signal.pos then
            local dx = (tonumber(signal.pos.x) or 0) - (tonumber(vehiclePos.x) or 0)
            local dy = (tonumber(signal.pos.y) or 0) - (tonumber(vehiclePos.y) or 0)
            local projection = dx * dirX + dy * dirY
            local lateral = math.abs(-dx * dirY + dy * dirX)
            local directionMatch = false
            local signalFlowX, signalFlowY = dirX, dirY
            if type(core_trafficSignals.getSignalByName) == "function" and signal.instance then
              local instance = core_trafficSignals.getSignalByName(signal.instance)
              local signalDir = instance and instance.dir
              if signalDir then
                local signalDirLength = math.sqrt((tonumber(signalDir.x) or 0) ^ 2 +
                  (tonumber(signalDir.y) or 0) ^ 2)
                directionMatch = signalDirLength > 0.1 and
                  ((tonumber(signalDir.x) or 0) * dirX + (tonumber(signalDir.y) or 0) * dirY) /
                    signalDirLength > 0.45
                if signalDirLength > 0.1 then
                  signalFlowX = (tonumber(signalDir.x) or 0) / signalDirLength
                  signalFlowY = (tonumber(signalDir.y) or 0) / signalDirLength
                end
              end
            end
            if projection >= -2 and projection <= config.signalLookAhead and
              lateral <= config.signalLaneHalfWidth and (routeMatch or directionMatch) and
              (not best or projection < best.distance) then
              best = {
                id = tostring(signal.instance or fromNode) .. ":" .. tostring(toNode),
                action = tonumber(signal.action) or 0,
                state = tostring(signal.state or ""),
                distance = math.max(0, projection),
                pos = signal.pos,
                dirX = signalFlowX,
                dirY = signalFlowY
              }
            end
          end
        end
      end
    end
    return best
  end

  local function updateIntersectionState(vehicle, speedKmh)
    local position = vehicle and vehicle:getPosition() or nil
    if not position then return end
    if runtime.intersectionActive then
      if runtime.intersectionLastPos then
        runtime.intersectionTravel = runtime.intersectionTravel +
          vectorDistance(runtime.intersectionLastPos, position)
      end
      runtime.intersectionLastPos = copyPosition(position)
      if runtime.intersectionTravel >= config.intersectionClearDistance then
        runtime.intersectionActive = false
        runtime.intersectionTravel = 0
        runtime.intersectionLastPos = nil
        logger.info("autopilot", "intersection_cleared")
      end
      return
    end
    local signal = runtime.upcomingSignal
    if not signal or not signal.pos or (tonumber(speedKmh) or 0) <= 2 then return end
    local dx = (tonumber(signal.pos.x) or 0) - (tonumber(position.x) or 0)
    local dy = (tonumber(signal.pos.y) or 0) - (tonumber(position.y) or 0)
    local signedDistance = dx * (tonumber(signal.dirX) or 0) + dy * (tonumber(signal.dirY) or 0)
    if signedDistance <= 0.75 then
      runtime.intersectionActive = true
      runtime.intersectionTravel = 0
      runtime.intersectionLastPos = copyPosition(position)
      runtime.signalSpeedCap = nil
      runtime.activeSignalId = nil
      runtime.upcomingSignal = nil
      logger.info("autopilot", "intersection_committed", {signal = signal.id})
    end
  end

  local function signalRequiresStop(vehicle)
    local signal = findUpcomingSignal(vehicle)
    return signal ~= nil and (signal.action == 1 or signal.action == 2) and
      signal.distance <= config.signalHoldDistance
  end

  local function isSignalQueue(lead, signal, includeGreen)
    if not lead or not signal or signal.distance < 0 or signal.distance > config.signalHoldDistance then
      return false
    end
    if signal.action ~= 1 and signal.action ~= 2 and not (includeGreen and signal.action == 0) then
      return false
    end
    return lead.gap <= signal.distance + 12 and
      signal.distance - lead.gap <= config.signalQueueDistanceMargin
  end

  local function serializeBypassPoints(points)
    local result = {}
    for _, point in ipairs(points or {}) do
      result[#result + 1] = string.format("{x=%.4f,y=%.4f,z=%.4f}", point.x, point.y, point.z)
    end
    return "{" .. table.concat(result, ",") .. "}"
  end

  local restoreNormal

  local function beginReverseEscape(vehicle, reason)
    runtime.recoveryAttempt = runtime.recoveryAttempt + 1
    runtime.recoverySeconds = 0
    runtime.recoveryController = true
    runtime.controllerMode = "reverse"
    runtime.reverseSourceReason = tostring(reason or "unknown")
    runtime.status = "recovering"
    runtime.stuckSeconds = 0
    applySpeedCap(vehicle, 0)
    local obstacleConfirmed = reason == "tooClose" or reason == "insufficientClearance" or
      reason == "trafficConflict" or reason == "roadBoundary" or reason == "noSafeCorridor"
    local requireFrontBlocked = not obstacleConfirmed
    local command = string.format(
      "ai.setMode('disabled'); extensions.load('taxiDriverAutopilotRecovery'); " ..
      "if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.startReverseEscape(" ..
      "{minDistance=%.2f,maxDistance=%.2f,targetSpeed=%.2f,timeout=%.2f,requireFrontBlocked=%s}) end",
      config.reverseEscapeMinDistance, config.reverseEscapeMaxDistance,
      config.reverseEscapeSpeed, config.reverseEscapeTimeout,
      requireFrontBlocked and "true" or "false"
    )
    queue(vehicle, command)
    logger.warn("autopilot", "reverse_escape_requested", {
      attempt = runtime.recoveryAttempt, reason = runtime.reverseSourceReason,
      minimum = config.reverseEscapeMinDistance, maximum = config.reverseEscapeMaxDistance
    })
  end

  local function beginRecovery(vehicle, target, distance)
    if runtime.recoveryAttempt >= config.maxRecoveryAttempts then
      runtime.recoveryExhausted = true
      runtime.status = "waitingTraffic"
      runtime.recoveryController = false
      runtime.controllerMode = nil
      runtime.stuckSeconds = 0
      applySpeedCap(vehicle, 0)
      stopAi(vehicle)
      logger.warn("autopilot", "recovery_attempts_exhausted", {
        attempts = runtime.recoveryAttempt, maximum = config.maxRecoveryAttempts
      })
      return
    end
    runtime.recoverySeconds = 0
    runtime.recoveryStartPos = copyPosition(vehicle:getPosition())
    runtime.recoveryStartDir = type(vehicle.getDirectionVector) == "function" and
      copyPosition(vehicle:getDirectionVector()) or nil
    runtime.recoveryStartDistance = distance
    local bypass, reason = perception:planLocalBypass(vehicle, runtime.followLeadId)
    if not bypass then
      if config.allowReverseRecovery then
        beginReverseEscape(vehicle, reason)
      else
        runtime.status = "waitingTraffic"
        runtime.recoveryController = false
        runtime.controllerMode = nil
        runtime.stuckSeconds = 0
        applySpeedCap(vehicle, 0)
        logger.info("autopilot", "reverse_recovery_disabled", {reason = reason})
      end
      return
    end
    if not config.allowOncomingRecovery then
      runtime.status = "driving"
      runtime.stuckSeconds = 0
      runtime.recoveryTrafficWait = 0
      runtime.recoveryClearTimer = 0
      queue(vehicle, 'ai.setAvoidCars("on"); ai.driveInLane("on")')
      logger.info("autopilot", "unsafe_recovery_disabled")
      return
    end

    runtime.recoveryAttempt = runtime.recoveryAttempt + 1
    runtime.recoveryController = true
    runtime.controllerMode = "bypass"
    runtime.status = "recovering"
    local command = string.format(
      "ai.setMode('disabled'); extensions.load('taxiDriverAutopilotRecovery'); " ..
      "if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.start(" ..
      "{points=%s,targetSpeed=%.3f,timeout=%.3f,signal=%d}) end",
      serializeBypassPoints(bypass.points), config.bypassControllerSpeed,
      config.bypassControllerTimeout, bypass.signal
    )
    queue(vehicle, command)
    logger.warn("autopilot", "adaptive_bypass_started", {
      attempt = runtime.recoveryAttempt, signal = bypass.signal,
      obstacle = bypass.obstacleId, offset = bypass.offset, distance = bypass.distance
    })
  end

  local function beginDirectApproach(vehicle, target, distance)
    if not target or not target.pos then return false end
    runtime.recoverySeconds = 0
    runtime.recoveryStartDistance = distance
    runtime.recoveryController = true
    runtime.controllerMode = "approach"
    runtime.status = "approaching"
    runtime.stuckSeconds = 0
    local completionRadius = target.exactApproach == true and 1.25 or 2.5
    local command = string.format(
      "ai.setMode('disabled'); extensions.load('taxiDriverAutopilotRecovery'); " ..
      "if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.start(" ..
      "{points=%s,targetSpeed=%.3f,timeout=%.3f,signal=0,stopAtEnd=true,completionRadius=%.2f}) end",
      serializeBypassPoints({target.pos}), config.directApproachSpeed,
      config.directApproachTimeout, completionRadius
    )
    if not queue(vehicle, command) then
      runtime.recoveryController = false
      runtime.controllerMode = nil
      return false
    end
    logger.info("autopilot", "direct_approach_started", {distance = distance})
    return true
  end

  local function resetProgress(distance)
    runtime.stuckSeconds = 0
    runtime.bestDistance = distance or math.huge
  end

  restoreNormal = function(vehicle, target, distance)
    runtime.recoveryAttempt = 0
    runtime.recoveryExhausted = false
    runtime.recoverySeconds = 0
    runtime.recoveryStartPos = nil
    runtime.recoveryStartDir = nil
    runtime.recoveryStartDistance = math.huge
    runtime.recoveryController = false
    runtime.controllerMode = nil
    runtime.recoveryTrafficWait = 0
    runtime.recoveryClearTimer = 0
    runtime.reverseSourceReason = nil
    runtime.routePending = true
    runtime.status = "planning"
    resetProgress(distance)
    queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end; electrics.set_left_signal(false,false); electrics.set_right_signal(false,false)')
    issueRoute(vehicle, target)
    logger.info("autopilot", "aggressive_bypass_completed")
  end

  function service:getHud(available, vehicle)
    return {
      available = available == true and vehicleSupported(vehicle),
      enabled = runtime.enabled == true,
      suspended = runtime.suspended == true,
      status = runtime.status,
      reason = runtime.reason,
      stuckSeconds = runtime.stuckSeconds,
      recoveryAttempt = runtime.recoveryAttempt
    }
  end

  function service:configure(settings)
    settings = type(settings) == "table" and settings or {}
    if settings.obeySpeedLimits == nil then
      config.obeySpeedLimits = settings.obeyTrafficRules ~= false
    else
      config.obeySpeedLimits = settings.obeySpeedLimits ~= false
    end
    if settings.obeyTrafficSignals == nil then
      config.obeyTrafficSignals = settings.obeyTrafficRules ~= false
    else
      config.obeyTrafficSignals = settings.obeyTrafficSignals ~= false
    end
    config.allowOvertaking = settings.allowOvertaking ~= false
    config.allowOncomingRecovery = settings.allowOncomingRecovery ~= false
    config.allowReverseRecovery = settings.allowReverseRecovery ~= false
    config.maxRecoveryAttempts = math.max(1, math.min(5,
      math.floor((tonumber(settings.recoveryMaxAttempts) or 3) + 0.5)))
    config.normalAggression = math.max(0.1, math.min(0.8,
      (tonumber(settings.aggressionPercent) or 30) / 100))
    config.followTimeGap = math.max(1.2, math.min(3.5,
      tonumber(settings.followingTimeGap) or 2.2))
    config.followComfortableDeceleration = math.max(1.5, math.min(4.5,
      tonumber(settings.brakingDeceleration) or 2.8))
    config.stuckDelay = math.max(8, math.min(30,
      tonumber(settings.stuckDelaySeconds) or 15))
    local clearanceScale = math.max(0.5, math.min(1.75,
      (tonumber(settings.laneChangeClearancePercent) or 100) / 100))
    config.laneChangeFreeAhead = baseLaneChangeFreeAhead * clearanceScale
    config.laneChangeFreeBehind = baseLaneChangeFreeBehind * clearanceScale
    local approachSpeed = math.max(5, math.min(20,
      tonumber(settings.finalApproachSpeedKmh) or 12)) / 3.6
    config.finalApproachSpeed = approachSpeed
    config.directApproachSpeed = approachSpeed
  end

  function service:isEnabled()
    return runtime.enabled == true
  end

  function service:enable(vehicle, phase, target)
    if runtime.enabled then return true end
    if not vehicleSupported(vehicle) or not isDrivingPhase(phase) or not target or not target.pos then
      runtime.reason = "unavailable"
      return false
    end
    runtime.enabled = true
    runtime.suspended = false
    runtime.status = "planning"
    runtime.reason = ""
    runtime.targetKey = targetKey(phase, target)
    runtime.routePending = true
    runtime.routeRetryTimer = 0
    runtime.stopIssued = false
    runtime.approachStage = 0
    runtime.recoveryAttempt = 0
    runtime.recoveryExhausted = false
    runtime.recoveryController = false
    runtime.controllerMode = nil
    runtime.recoveryTrafficWait = 0
    runtime.recoveryClearTimer = 0
    runtime.reverseSourceReason = nil
    runtime.intersectionActive = false
    runtime.intersectionTravel = 0
    runtime.intersectionLastPos = nil
    runtime.routeDonePending = false
    runtime.laneChangeTimer = 0
    runtime.laneChangeCooldown = 0
    runtime.laneChangeLeadTimer = 0
    resetProgress(vectorDistance(vehicle:getPosition(), target.pos))
    issueRoute(vehicle, target)
    logger.info("autopilot", "enabled", {phase = phase})
    return true
  end

  function service:disable(vehicle, reason)
    local wasEnabled = runtime.enabled
    if wasEnabled then
      queue(vehicle,
        'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop(); extensions.taxiDriverAutopilotRecovery.unwatchRouteDone() end; electrics.set_left_signal(false,false); electrics.set_right_signal(false,false); ai.setRecoverOnCrash(false); ai.setParameters({awarenessForceCoef=0.25,trafficWaitTime=2,edgeDist=0,enableElectrics=true}); ai.setAvoidCars("on"); ai.driveInLane("on"); ai.setAggression(0.3); ai.setSpeed(nil); ai.setSpeedMode("off"); ai.setMode("disabled"); if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.setGearboxOverride(false) end')
    end
    runtime.enabled = false
    runtime.suspended = false
    runtime.status = "off"
    runtime.reason = tostring(reason or "")
    runtime.targetKey = ""
    runtime.routeNodes = {}
    runtime.routePending = false
    runtime.stopIssued = false
    runtime.approachStage = 0
    runtime.recoveryAttempt = 0
    runtime.recoveryExhausted = false
    runtime.recoverySeconds = 0
    runtime.recoveryController = false
    runtime.controllerMode = nil
    runtime.recoveryTrafficWait = 0
    runtime.recoveryClearTimer = 0
    runtime.reverseSourceReason = nil
    runtime.intersectionActive = false
    runtime.intersectionTravel = 0
    runtime.intersectionLastPos = nil
    runtime.routeDonePending = false
    runtime.laneChangeTimer = 0
    runtime.laneChangeCooldown = 0
    runtime.laneChangeLeadTimer = 0
    resetProgress()
    if wasEnabled then logger.info("autopilot", "disabled", {reason = runtime.reason}) end
  end

  function service:toggle(vehicle, phase, target)
    if runtime.enabled then
      self:disable(vehicle, "driver")
      return false
    end
    return self:enable(vehicle, phase, target)
  end

  function service:suspend(vehicle, value)
    value = value == true
    if not runtime.enabled or runtime.suspended == value then return end
    runtime.suspended = value
    if value then
      runtime.status = "paused"
      queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
      runtime.recoveryController = false
      runtime.controllerMode = nil
      stopAi(vehicle)
    else
      runtime.status = "planning"
      runtime.routePending = true
      runtime.routeRetryTimer = 0
    end
  end

  function service:markRouteDirty()
    if not runtime.enabled then return end
    runtime.routePending = true
    runtime.routeRetryTimer = 0
    runtime.stopIssued = false
    runtime.approachStage = 0
    runtime.status = runtime.suspended and "paused" or "planning"
  end

  function service:onRouteDone(vehicle, target)
    if not runtime.enabled or runtime.suspended or not vehicle or not target or not target.pos then
      return false
    end
    local distance = vectorDistance(vehicle:getPosition(), target.pos)
    if distance <= config.stopDistance and target.exactApproach ~= true then return true end
    if distance <= config.directApproachDistance then
      runtime.routeDonePending = false
      logger.info("autopilot", "route_done_before_target", {distance = distance})
      beginDirectApproach(vehicle, target, distance)
    else
      runtime.routePending = true
      runtime.routeRetryTimer = 0
      runtime.status = "planning"
      logger.warn("autopilot", "route_done_far_from_target", {distance = distance})
    end
    return true
  end

  function service:update(vehicle, phase, target, dt)
    if not runtime.enabled then return false end
    dt = math.max(0, tonumber(dt) or 0)
    if not vehicle then self:disable(nil, "vehicle"); return true end
    if runtime.suspended then return false end

    if not isDrivingPhase(phase) then
      if isPausePhase(phase) then
        runtime.status = "paused"
        runtime.stuckSeconds = 0
        return false
      end
      self:disable(vehicle, "phase")
      return true
    end
    if not target or not target.pos then
      runtime.status = "unavailable"
      runtime.reason = "target"
      return false
    end

    local key = targetKey(phase, target)
    if runtime.targetKey ~= key then
      if runtime.recoveryController then
        queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
        runtime.recoveryController = false
        runtime.controllerMode = nil
        runtime.reverseSourceReason = nil
      end
      runtime.targetKey = key
      runtime.routePending = true
      runtime.routeRetryTimer = 0
      runtime.stopIssued = false
      runtime.approachStage = 0
      runtime.recoveryAttempt = 0
      runtime.recoveryExhausted = false
      resetProgress(vectorDistance(vehicle:getPosition(), target.pos))
    end

    if runtime.routePending then
      if runtime.recoveryController then
        queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
        runtime.recoveryController = false
        runtime.controllerMode = nil
      end
      runtime.routeRetryTimer = runtime.routeRetryTimer - dt
      if runtime.routeRetryTimer <= 0 then
        if not issueRoute(vehicle, target) then
          runtime.status = "planning"
          runtime.routeRetryTimer = 0.35
        end
      end
      if runtime.routePending then return false end
    end

    local vehiclePos = vehicle:getPosition()
    local distance = vectorDistance(vehiclePos, target.pos)
    local speed = type(options.getSpeedKmh) == "function" and
      math.max(0, tonumber(options.getSpeedKmh(vehicle)) or 0) or 0
    updateIntersectionState(vehicle, speed)
    updateLaneChange(vehicle, dt)

    local stopDistance = target.exactApproach == true and 1.25 or config.stopDistance
    if distance <= stopDistance then
      if not runtime.stopIssued then
        runtime.stopIssued = true
        runtime.status = "stopping"
        stopAi(vehicle)
      end
      return false
    elseif target.exactApproach == true and distance <= config.stopDistance and
      not runtime.recoveryController then
      beginDirectApproach(vehicle, target, distance)
      return false
    elseif distance <= config.finalApproachDistance and runtime.approachStage < 2 then
      runtime.approachStage = 2
    elseif distance <= config.approachDistance and runtime.approachStage < 1 then
      runtime.approachStage = 1
    end

    if runtime.routeDonePending then
      runtime.routeDoneRetryTimer = math.max(0, runtime.routeDoneRetryTimer - dt)
      local signal = findUpcomingSignal(vehicle)
      if signal and (signal.action == 1 or signal.action == 2) then
        runtime.status = "waitingSignal"
        stopAi(vehicle)
      elseif runtime.routeDoneRetryTimer <= 0 then
        runtime.routeDonePending = false
        beginDirectApproach(vehicle, target, distance)
      end
      return false
    end

    if runtime.status == "waitingTraffic" then
      runtime.recoverySeconds = runtime.recoverySeconds + dt
      runtime.recoveryTrafficWait = runtime.recoveryTrafficWait + dt
      local currentLead = findLeadVehicle(vehicle)
      local currentSignal = findUpcomingSignal(vehicle)
      runtime.followLeadId = currentLead and currentLead.id or nil
      runtime.upcomingSignal = currentSignal
      if runtime.recoveryExhausted then
        applySpeedCap(vehicle, 0)
      elseif speed >= config.movingSpeedKmh or not currentLead or currentLead.rawSpeed > 2 then
        logger.info("autopilot", "waiting_traffic_cleared", {
          lead = currentLead and currentLead.id or nil, leadSpeed = currentLead and currentLead.rawSpeed or nil
        })
        restoreNormal(vehicle, target, distance)
      elseif isSignalQueue(currentLead, currentSignal, false) then
        runtime.status = "waitingSignal"
        runtime.stuckSeconds = 0
        runtime.recoverySeconds = 0
        runtime.recoveryClearTimer = 0
        logger.info("autopilot", "traffic_queue_waiting_for_signal", {
          lead = currentLead.id, signal = currentSignal.id, distance = currentSignal.distance
        })
      elseif isSignalQueue(currentLead, currentSignal, true) and
        runtime.recoveryClearTimer < config.signalQueueReleaseDelay then
        runtime.recoveryClearTimer = runtime.recoveryClearTimer + dt
      elseif runtime.recoverySeconds >= config.oncomingRetryInterval then
        runtime.recoveryClearTimer = 0
        beginRecovery(vehicle, target, distance)
      end
      return false
    end

    if runtime.status == "recovering" then
      runtime.recoverySeconds = runtime.recoverySeconds + dt
      if runtime.recoveryController then
        if runtime.recoverySeconds >= config.bypassControllerTimeout + 1 then
          queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
          runtime.recoveryController = false
          beginRecovery(vehicle, target, distance)
        end
        return false
      end
      local moved = vectorDistance(runtime.recoveryStartPos, vehiclePos)
      local progressed = runtime.recoveryStartDistance - distance
      local forwardMovement = 0
      if runtime.recoveryStartPos and runtime.recoveryStartDir then
        forwardMovement = ((tonumber(vehiclePos.x) or 0) - runtime.recoveryStartPos.x) * runtime.recoveryStartDir.x +
          ((tonumber(vehiclePos.y) or 0) - runtime.recoveryStartPos.y) * runtime.recoveryStartDir.y +
          ((tonumber(vehiclePos.z) or 0) - runtime.recoveryStartPos.z) * runtime.recoveryStartDir.z
      end
      if progressed >= config.recoverySuccessDistance or
        (moved >= config.recoverySuccessDistance and forwardMovement >= config.recoverySuccessDistance * 0.75) then
        restoreNormal(vehicle, target, distance)
      elseif runtime.recoverySeconds >= config.recoveryRetryInterval then
        beginRecovery(vehicle, target, distance)
      end
      return false
    end

    if runtime.status == "approaching" then
      runtime.recoverySeconds = runtime.recoverySeconds + dt
      local signal = findUpcomingSignal(vehicle)
      if signal and (signal.action == 1 or signal.action == 2) and
        signal.distance <= config.directApproachDistance then
        queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
        runtime.recoveryController = false
        runtime.controllerMode = nil
        runtime.routePending = true
        runtime.routeRetryTimer = 0
        runtime.status = "planning"
        stopAi(vehicle)
        logger.info("autopilot", "direct_approach_paused_for_signal", {
          action = signal.action, distance = signal.distance
        })
      elseif runtime.recoverySeconds >= config.directApproachTimeout + 1 then
        queue(vehicle, 'if extensions.taxiDriverAutopilotRecovery then extensions.taxiDriverAutopilotRecovery.stop() end')
        runtime.recoveryController = false
        runtime.controllerMode = nil
        runtime.routePending = true
        runtime.routeRetryTimer = 0
        runtime.status = "planning"
        logger.warn("autopilot", "direct_approach_timeout", {distance = distance})
      end
      return false
    end

    local leadId, upcomingSignal = updateFollowing(vehicle, distance, speed, dt)

    if distance + 2 < runtime.bestDistance then
      runtime.bestDistance = distance
      runtime.stuckSeconds = 0
      runtime.status = "driving"
    elseif speed >= config.movingSpeedKmh then
      runtime.stuckSeconds = math.max(0, runtime.stuckSeconds - dt * 2)
      runtime.bestDistance = math.min(runtime.bestDistance, distance)
      runtime.status = "driving"
    elseif speed <= config.stoppedSpeedKmh and distance > config.stopDistance + 2 then
      if signalRequiresStop(vehicle) then
        runtime.status = "waitingSignal"
        runtime.stuckSeconds = 0
      else
        runtime.status = "driving"
        runtime.stuckSeconds = runtime.stuckSeconds + dt
        if distance <= config.directApproachDistance and
          runtime.stuckSeconds >= config.directApproachDelay and leadId == nil and
          (not upcomingSignal or upcomingSignal.distance > config.directApproachDistance or
            (upcomingSignal.action ~= 1 and upcomingSignal.action ~= 2)) then
          beginDirectApproach(vehicle, target, distance)
          return false
        end
        if runtime.stuckSeconds >= config.stuckDelay then
          local queueLead = leadId and findLeadVehicle(vehicle) or nil
          if isSignalQueue(queueLead, upcomingSignal, true) then
            runtime.status = "waitingSignal"
            runtime.stuckSeconds = 0
            logger.info("autopilot", "stationary_queue_detected_at_signal", {
              lead = queueLead and queueLead.id or nil,
              signal = upcomingSignal and upcomingSignal.id or nil
            })
          else
            beginRecovery(vehicle, target, distance)
          end
        end
      end
    else
      runtime.status = "driving"
      runtime.stuckSeconds = math.max(0, runtime.stuckSeconds - dt * 2)
    end
    return false
  end

  function service:onBypassComplete(vehicle, succeeded, target, reason)
    if not runtime.enabled or not runtime.recoveryController then return false end
    local controllerMode = runtime.controllerMode
    local reverseSourceReason = runtime.reverseSourceReason
    runtime.recoveryController = false
    runtime.controllerMode = nil
    runtime.reverseSourceReason = nil
    local distance = target and target.pos and vectorDistance(vehicle:getPosition(), target.pos) or math.huge
    if controllerMode == "reverse" then
      if succeeded then
        logger.info("autopilot", "reverse_escape_completed", {
          source = reverseSourceReason, distance = distance
        })
        if reverseSourceReason == "noStationaryObstacle" or reverseSourceReason == "mapUnavailable" or
          reverseSourceReason == "roadUnavailable" or reverseSourceReason == "directionUnavailable" then
          restoreNormal(vehicle, target, distance)
        else
          beginRecovery(vehicle, target, distance)
        end
      elseif reason == "frontEscapeAvailable" then
        logger.info("autopilot", "reverse_escape_not_required", {reason = reason})
        restoreNormal(vehicle, target, distance)
      else
        runtime.status = "waitingTraffic"
        runtime.recoverySeconds = 0
        runtime.recoveryTrafficWait = 0
        runtime.stuckSeconds = 0
        applySpeedCap(vehicle, 0)
        logger.warn("autopilot", "reverse_escape_blocked", {
          source = reverseSourceReason, reason = reason
        })
      end
    elseif controllerMode == "approach" then
      if succeeded then
        runtime.status = "stopping"
        runtime.stopIssued = true
        resetProgress(distance)
        stopAi(vehicle)
        logger.info("autopilot", "direct_approach_completed", {distance = distance})
      else
        runtime.routeDonePending = distance <= config.directApproachDistance
        runtime.routeDoneRetryTimer = 1
        runtime.status = runtime.routeDonePending and "routeDone" or "planning"
        if not runtime.routeDonePending then
          runtime.routePending = true
          runtime.routeRetryTimer = 0
        end
        logger.warn("autopilot", "direct_approach_failed", {distance = distance, reason = reason})
      end
    elseif succeeded then restoreNormal(vehicle, target, distance)
    else beginRecovery(vehicle, target, distance) end
    return true
  end

  return service
end

return M
