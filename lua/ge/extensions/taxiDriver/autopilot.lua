local M = {}
local logger = require("taxiDriver/logger")

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

local function orientedTargetEdge(target)
  if not target or not target.nodeA or not target.nodeB or not target.dir or
    not map or type(map.getMap) ~= "function" then return nil end
  local mapData = map.getMap()
  local nodes = mapData and mapData.nodes
  local nodeA, nodeB = nodes and nodes[target.nodeA], nodes and nodes[target.nodeB]
  if not (nodeA and nodeB and nodeA.pos and nodeB.pos) then return nil end
  local link = (nodeA.links and nodeA.links[target.nodeB]) or
    (nodeB.links and nodeB.links[target.nodeA])
  if not link then return nil end
  local edgeX = number(nodeB.pos.x, 0) - number(nodeA.pos.x, 0)
  local edgeY = number(nodeB.pos.y, 0) - number(nodeA.pos.y, 0)
  local directionX, directionY =
    number(target.dir.x, 0), number(target.dir.y, 0)
  if edgeX * directionX + edgeY * directionY >= 0 then
    return tostring(target.nodeA), tostring(target.nodeB)
  end
  return tostring(target.nodeB), tostring(target.nodeA)
end

local function nodeDistance(nodes, first, second)
  local a, b = nodes and nodes[first], nodes and nodes[second]
  if not (a and b and a.pos and b.pos) then return 1 end
  return math.max(0.1, distance(a.pos, b.pos))
end

local function heapPush(heap, entry)
  local index = #heap + 1
  heap[index] = entry
  while index > 1 do
    local parent = math.floor(index * 0.5)
    if heap[parent].cost <= entry.cost then break end
    heap[index] = heap[parent]
    index = parent
  end
  heap[index] = entry
end

local function heapPop(heap)
  local root = heap[1]
  if not root then return nil end
  local tail = table.remove(heap)
  if #heap == 0 then return root end
  local index = 1
  while true do
    local left, right = index * 2, index * 2 + 1
    if left > #heap then break end
    local child = right <= #heap and heap[right].cost < heap[left].cost and
      right or left
    if heap[child].cost >= tail.cost then break end
    heap[index] = heap[child]
    index = child
  end
  heap[index] = tail
  return root
end

local function edgeKey(previous, current)
  return tostring(previous) .. "\0" .. tostring(current)
end

local function edgeAllowsDirection(_, _, toNode, data)
  -- Match BeamNG graphpath's legal-direction test. Lane strings are often
  -- absent on otherwise valid bidirectional roads, so a zero lane count must
  -- not make the whole road unreachable.
  return not (data and data.oneWay and data.inNode == toNode)
end

local function currentRoadDirection(vehicle, nodes)
  if not vehicle or not map or type(map.findClosestRoad) ~= "function" then
    return nil
  end
  local first, second = map.findClosestRoad(vehicle:getPosition())
  first, second = tostring(first or ""), tostring(second or "")
  if first == "" or second == "" or not (nodes[first] and nodes[second]) then
    return nil
  end
  local direction = type(vehicle.getDirectionVector) == "function" and
    vehicle:getDirectionVector() or nil
  if not direction then
    local velocity = type(vehicle.getVelocity) == "function" and vehicle:getVelocity() or nil
    direction = velocity
  end
  local firstPos, secondPos = nodes[first].pos, nodes[second].pos
  if not (direction and firstPos and secondPos) then return first, second end
  local edgeX = number(secondPos.x, 0) - number(firstPos.x, 0)
  local edgeY = number(secondPos.y, 0) - number(firstPos.y, 0)
  local dot = edgeX * number(direction.x, 0) + edgeY * number(direction.y, 0)
  if dot >= 0 then return first, second end
  return second, first
end

-- Find the shortest legal path in directed-edge space. A node-only shortest
-- path may reach the target edge from its wrong end and make native AI perform
-- an immediate U-turn through opposing traffic. Tracking (previous,current)
-- lets a route revisit the same junction from another road while explicitly
-- forbidding a reversal on the edge it just traversed.
local function directedApproachRoute(vehicle, approachNode, departureNode)
  if not vehicle or not map or type(map.getMap) ~= "function" or
    type(map.getGraphpath) ~= "function" then return nil end
  local mapData, graph = map.getMap(), map.getGraphpath()
  local nodes = mapData and mapData.nodes
  local roads = graph and graph.graph
  if not (nodes and roads and roads[approachNode] and roads[departureNode]) then
    return nil
  end
  local behindNode, forwardNode = currentRoadDirection(vehicle, nodes)
  if not (behindNode and forwardNode and roads[forwardNode]) then return nil end

  local startKey = edgeKey(behindNode, forwardNode)
  local costs, parents, states = {[startKey] = 0}, {[startKey] = false}, {
    [startKey] = {previous = behindNode, current = forwardNode}
  }
  local heap, visited, goalKey = {}, {}, nil
  heapPush(heap, {cost = 0, key = startKey})
  local expanded, maximumExpanded = 0, 60000

  while #heap > 0 and expanded < maximumExpanded do
    local entry = heapPop(heap)
    if entry and not visited[entry.key] and entry.cost == costs[entry.key] then
      visited[entry.key] = true
      expanded = expanded + 1
      local state = states[entry.key]
      if state.current == approachNode and state.previous ~= departureNode then
        goalKey = entry.key
        break
      end
      for child, data in pairs(roads[state.current] or {}) do
        child = tostring(child)
        if child ~= state.previous and roads[child] and
          edgeAllowsDirection(graph, state.current, child, data) then
          local childKey = edgeKey(state.current, child)
          local edgeLength = number(data and data.len,
            nodeDistance(nodes, state.current, child))
          local newCost = entry.cost + math.max(0.1, edgeLength)
          if costs[childKey] == nil or newCost < costs[childKey] then
            costs[childKey] = newCost
            parents[childKey] = entry.key
            states[childKey] = {previous = state.current, current = child}
            heapPush(heap, {cost = newCost, key = childKey})
          end
        end
      end
    end
  end
  if not goalKey then return nil end

  local reversed, cursor = {}, goalKey
  while cursor do
    reversed[#reversed + 1] = states[cursor].current
    cursor = parents[cursor]
  end
  local result = {}
  for index = #reversed, 1, -1 do appendUnique(result, reversed[index]) end
  appendUnique(result, departureNode)
  if #result < 2 then return nil end
  return result, behindNode, forwardNode, expanded
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

function M.new(options)
  options = type(options) == "table" and options or {}
  local phases = options.phases or {}
  local trace = options.trace
  local service = {}
  local runtime = {
    enabled = false,
    suspended = false,
    status = "off",
    reason = "",
    target = nil,
    targetKey = "",
    routeNodes = {},
    routeDirty = false,
    routeDone = false,
    routeDoneDistance = nil,
    routeDoneRetryCount = 0,
    orientedApproach = false,
    approachNode = nil,
    departureNode = nil,
    targetDistance = nil,
    lastPosition = nil,
    movedDistance = 0,
    stationarySeconds = 0,
    elapsed = 0,
    commandCount = 0,
    profile = {
      aggression = 0.4,
      followingTimeGap = 2.3,
      minimumFollowingDistance = 4,
      brakingDeceleration = 3.5,
      trafficWaitSeconds = 3,
      obeySpeedLimits = true,
      laneDiscipline = true,
      strictGpsRoute = false
    }
  }

  local function isDrivingPhase(phase)
    return phase == phases.toPickup or phase == phases.toStop or
      phase == phases.toDestination or phase == phases.toFuelStation
  end

  local function targetKey(phase, target)
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

  local function isCurrentPlayerVehicle(vehicle)
    if not vehicle then return false end
    if type(options.isPlayerVehicle) == "function" then
      local ok, result = pcall(options.isPlayerVehicle, vehicle)
      if ok and result ~= nil then return result == true end
    end
    local vehicleId = type(vehicle.getID) == "function" and tonumber(vehicle:getID()) or nil
    local playerId = be and type(be.getPlayerVehicleID) == "function" and
      tonumber(be:getPlayerVehicleID(0)) or nil
    if vehicleId and playerId then return vehicleId == playerId end
    if type(vehicle.isPlayerControlled) == "function" then
      local ok, result = pcall(vehicle.isPlayerControlled, vehicle)
      if ok then return result == true end
    end
    -- Headless tests and older BeamNG builds may expose neither API. Identity
    -- is then guarded by the GE gameplay orchestrator before this module runs.
    return true
  end

  local function readNativeRoute(target)
    local result = {}
    local path = type(options.getRoutePath) == "function" and options.getRoutePath() or {}
    for _, entry in ipairs(type(path) == "table" and path or {}) do
      -- Ground-marker paths contain coordinate-only tables at both ends.
      -- Passing those tables through tostring produces "table: 0x..." node
      -- identifiers and crashes BeamNG's ai.lua with targetPos/egoSeg == nil.
      if type(entry) == "table" then
        appendUnique(result, entry.wp)
      elseif type(entry) == "string" or type(entry) == "number" then
        appendUnique(result, entry)
      end
    end
    if target then
      if #result == 0 then appendUnique(result, target.nodeA) end
      appendUnique(result, target.nodeB)
    end
    return result
  end

  local function routeForTarget(vehicle, target)
    local approachNode, departureNode = orientedTargetEdge(target)
    if runtime.profile.strictGpsRoute then
      local gpsRoute = readNativeRoute()
      if #gpsRoute >= 2 then
        return gpsRoute, approachNode ~= nil, approachNode, departureNode,
          nil, nil, nil, "gps"
      end
      logger.warn("autopilot", "strict_gps_route_unavailable", {
        approachNode = approachNode, departureNode = departureNode
      })
    end
    if approachNode and departureNode then
      local route, behindNode, forwardNode, expanded =
        directedApproachRoute(vehicle, approachNode, departureNode)
      if route then
        return route, true, approachNode, departureNode,
          behindNode, forwardNode, expanded, "autonomous"
      end
      logger.warn("autopilot", "legal_approach_route_unavailable", {
        approachNode = approachNode, departureNode = departureNode
      })
      return {}, true, approachNode, departureNode
    end
    return readNativeRoute(target), false, nil, nil
  end

  local function fallbackRoute(vehicle, target)
    local result = {}
    if not vehicle or not target or not target.pos or not map or
      type(map.findClosestRoad) ~= "function" or type(map.getGraphpath) ~= "function" then
      return result
    end
    local startA, startB = map.findClosestRoad(vehicle:getPosition())
    local destination = target.nodeB or target.nodeA
    local graph = map.getGraphpath()
    if not graph or type(graph.getPath) ~= "function" or not destination then return result end
    local ok, path = pcall(graph.getPath, graph, startB or startA, destination)
    if not ok or type(path) ~= "table" then return result end
    appendUnique(result, startB or startA)
    for _, node in ipairs(path) do appendUnique(result, node) end
    appendUnique(result, destination)
    return result
  end

  local function stopNative(vehicle)
    return queue(vehicle, table.concat({
      "if extensions.taxiDriverAutopilotRecovery then ",
      "extensions.taxiDriverAutopilotRecovery.stop();",
      "extensions.taxiDriverAutopilotRecovery.unwatchRouteDone();",
      "extensions.taxiDriverAutopilotRecovery.setGearboxOverride(false) end;",
      "if extensions and extensions.unload then ",
      "extensions.unload('taxiDriverAutopilotRecovery') end;",
      "if extensions.taxiDriverStockAiObserver then ",
      "extensions.taxiDriverStockAiObserver.unwatch() end;",
      "if extensions and extensions.unload then ",
      "extensions.unload('taxiDriverStockAiObserver') end;",
      "electrics.set_left_signal(false,false);",
      "electrics.set_right_signal(false,false);",
      "ai.setRecoverOnCrash(false);",
      "ai.setSpeed(nil); ai.setSpeedMode('off');",
      "ai.setAvoidCars('on'); ai.driveInLane('on'); ai.setMode('disabled')"
    }))
  end

  local function issueNativeRoute(vehicle, reason)
    if not runtime.enabled or runtime.suspended or not vehicle or not runtime.target then
      return false
    end
    if not isCurrentPlayerVehicle(vehicle) then
      runtime.status = "playerVehicleChanged"
      runtime.reason = "notCurrentPlayerVehicle"
      logger.warn("autopilot", "player_vehicle_guard_rejected_route")
      return false
    end
    local nodes, oriented, approachNode, departureNode,
      behindNode, forwardNode, expanded, routeSource =
      routeForTarget(vehicle, runtime.target)
    if #nodes < 2 and not oriented then nodes = fallbackRoute(vehicle, runtime.target) end
    if #nodes < 2 then
      runtime.status = "routeUnavailable"
      runtime.reason = "nativeRouteUnavailable"
      logger.warn("autopilot", "stock_route_unavailable")
      return false
    end
    local laneMode = oriented and "on" or (runtime.profile.laneDiscipline and "on" or "off")
    local command = table.concat({
      "if extensions.taxiDriverAutopilotRecovery then ",
      "extensions.taxiDriverAutopilotRecovery.stop();",
      "extensions.taxiDriverAutopilotRecovery.unwatchRouteDone();",
      "extensions.taxiDriverAutopilotRecovery.setGearboxOverride(false) end;",
      "if extensions and extensions.unload then ",
      "extensions.unload('taxiDriverAutopilotRecovery') end;",
      "extensions.load('taxiDriverStockAiObserver');",
      "if extensions.taxiDriverStockAiObserver then ",
      "extensions.taxiDriverStockAiObserver.watch({followingTimeGap=",
      string.format("%.2f", runtime.profile.followingTimeGap),
      ",minimumGap=", string.format("%.2f", runtime.profile.minimumFollowingDistance),
      ",brakingDeceleration=", string.format("%.2f", runtime.profile.brakingDeceleration),
      ",routeSpeedMode=", quote(runtime.profile.obeySpeedLimits and "legal" or "off"),
      ",targetX=", string.format("%.3f", number(runtime.target.pos.x, 0)),
      ",targetY=", string.format("%.3f", number(runtime.target.pos.y, 0)),
      ",targetZ=", string.format("%.3f", number(runtime.target.pos.z, 0)),
      ",targetDirX=", string.format("%.4f", number(runtime.target.dir and runtime.target.dir.x, 0)),
      ",targetDirY=", string.format("%.4f", number(runtime.target.dir and runtime.target.dir.y, 0)),
      ",arrivalRadius=", string.format("%.2f", number(options.arrivalRadius, 14)),
      ",maximumArrivalSpeed=", string.format("%.3f",
        number(options.maxArrivalSpeedKmh, 4) * 0.75 / 3.6),
      "}) end;",
      "electrics.set_left_signal(false,false);",
      "electrics.set_right_signal(false,false);",
      "ai.setMode('disabled');",
      -- Native traffic AI normally teleports a stuck/crashed NPC through
      -- map.safeTeleport. That recovery must never be enabled for the player's
      -- vehicle: stopping for boarding is otherwise mistaken for a crash.
      "ai.setRecoverOnCrash(false);",
      "ai.setAvoidCars('on'); ai.driveInLane('on');",
      "mapmgr.enableTracking();",
      "ai.setParameters({awarenessForceCoef=0.45,trafficWaitTime=",
      string.format("%.2f", runtime.profile.trafficWaitSeconds),
      ",edgeDist=0,enableElectrics=true});",
      "ai.driveUsingPath({",
      "path=", serializePath(nodes),
      ",noOfLaps=1,aggression=", string.format("%.2f", runtime.profile.aggression),
      ",avoidCars='on',driveInLane=",
      quote(laneMode),
      ",routeSpeedMode=", quote(runtime.profile.obeySpeedLimits and "legal" or "off"),
      "});",
      "ai.setRecoverOnCrash(false)"
    })
    if not queue(vehicle, command) then return false end
    runtime.routeNodes = nodes
    runtime.orientedApproach = oriented
    runtime.approachNode = approachNode
    runtime.departureNode = departureNode
    runtime.routeDirty = false
    runtime.routeDone = false
    runtime.routeDoneDistance = nil
    runtime.status = "driving"
    runtime.reason = tostring(reason or "")
    runtime.commandCount = runtime.commandCount + 1
    runtime.lastPosition = copyPosition(vehicle:getPosition())
    runtime.stationarySeconds = 0
    logger.info("autopilot", "stock_route_started", {
      nodes = #nodes, reason = reason, commandCount = runtime.commandCount,
      customPerception = false, customRecovery = false, trafficGuard = true,
      aggression = runtime.profile.aggression,
      followingTimeGap = runtime.profile.followingTimeGap,
      laneDiscipline = runtime.profile.laneDiscipline,
      strictGpsRoute = runtime.profile.strictGpsRoute,
      routeSource = routeSource or "fallback",
      legalApproach = oriented,
      orientedApproach = oriented,
      approachNode = approachNode,
      departureNode = departureNode,
      currentBehindNode = behindNode,
      currentForwardNode = forwardNode,
      routeSearchExpanded = expanded,
      routePreview = table.concat(nodes, " > "),
      routeDoneRetryCount = runtime.routeDoneRetryCount
    })
    return true
  end

  function service:configure(profile)
    profile = type(profile) == "table" and profile or {}
    runtime.profile = {
      aggression = clamp(number(profile.aggressionPercent, 40) / 100, 0.3, 1),
      followingTimeGap = clamp(number(profile.followingTimeGap, 2.3), 1, 4),
      minimumFollowingDistance = clamp(number(profile.minimumFollowingDistance, 4), 2, 10),
      brakingDeceleration = clamp(number(profile.brakingDeceleration, 3.5), 2, 8),
      trafficWaitSeconds = clamp(number(profile.trafficWaitSeconds, 3), 1, 10),
      obeySpeedLimits = profile.obeySpeedLimits ~= false,
      laneDiscipline = profile.laneDiscipline ~= false,
      strictGpsRoute = profile.strictGpsRoute == true
    }
  end

  function service:drawDebug()
  end

  function service:isEnabled()
    return runtime.enabled == true
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
    if runtime.enabled then return true end
    if not vehicle or not isCurrentPlayerVehicle(vehicle) or
      not isDrivingPhase(phase) or not target or not target.pos then
      runtime.reason = "unavailable"
      return false
    end
    runtime.enabled = true
    runtime.suspended = false
    runtime.status = "planning"
    runtime.reason = ""
    runtime.target = target
    runtime.targetKey = targetKey(phase, target)
    runtime.routeDirty = false
    runtime.routeDone = false
    runtime.routeDoneDistance = nil
    runtime.routeDoneRetryCount = 0
    runtime.elapsed = 0
    runtime.movedDistance = 0
    runtime.stationarySeconds = 0
    runtime.commandCount = 0
    if trace and type(trace.start) == "function" then trace:start(vehicle, phase, target) end
    if issueNativeRoute(vehicle, "enabled") then
      logger.info("autopilot", "stock_ai_enabled", {phase = phase})
      return true
    end
    runtime.enabled = false
    return false
  end

  function service:disable(vehicle, reason)
    local wasEnabled = runtime.enabled
    if wasEnabled then stopNative(vehicle) end
    runtime.enabled = false
    runtime.suspended = false
    runtime.status = "off"
    runtime.reason = tostring(reason or "")
    runtime.target = nil
    runtime.targetKey = ""
    runtime.routeNodes = {}
    runtime.routeDirty = false
    runtime.routeDone = false
    runtime.routeDoneDistance = nil
    runtime.routeDoneRetryCount = 0
    runtime.orientedApproach = false
    runtime.approachNode = nil
    runtime.departureNode = nil
    runtime.lastPosition = nil
    runtime.stationarySeconds = 0
    if wasEnabled then
      logger.info("autopilot", "stock_ai_disabled", {reason = runtime.reason})
      if trace and type(trace.stop) == "function" then trace:stop(runtime.reason) end
    end
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
      stopNative(vehicle)
    else
      runtime.status = "planning"
      issueNativeRoute(vehicle, "resumed")
    end
  end

  function service:markRouteDirty()
    if not runtime.enabled then return end
    runtime.routeDirty = true
    runtime.routeDone = false
    runtime.status = runtime.suspended and "paused" or "planning"
  end

  function service:update(vehicle, phase, target, dt)
    if not runtime.enabled or runtime.suspended then return false end
    if not vehicle or not isCurrentPlayerVehicle(vehicle) then
      self:disable(vehicle, "playerVehicleChanged")
      return false
    end
    if not target or not target.pos or not isDrivingPhase(phase) then
      return false
    end
    local key = targetKey(phase, target)
    if key ~= runtime.targetKey then
      runtime.target = target
      runtime.targetKey = key
      runtime.routeDirty = true
      runtime.routeDoneRetryCount = 0
    end
    if runtime.routeDirty then issueNativeRoute(vehicle, "routeChanged") end

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
    if runtime.routeDone then
      runtime.status = "routeDone"
    elseif runtime.status ~= "routeUnavailable" then
      runtime.status = "driving"
    end
    return false
  end

  function service:onRouteDone(vehicle, target)
    if not runtime.enabled or runtime.suspended then return false end
    runtime.routeDoneDistance = vehicle and target and target.pos and
      distance(vehicle:getPosition(), target.pos) or math.huge
    local arrivalRadius = math.max(1, number(options.arrivalRadius, 14))
    if runtime.routeDoneDistance > arrivalRadius and
      runtime.routeDoneRetryCount < 3 then
      runtime.routeDoneRetryCount = runtime.routeDoneRetryCount + 1
      runtime.routeDone = false
      runtime.status = "planning"
      runtime.reason = "prematureNativeRouteDone"
      logger.warn("autopilot", "stock_route_done_before_target", {
        targetDistance = runtime.routeDoneDistance,
        retry = runtime.routeDoneRetryCount,
        orientedApproach = runtime.orientedApproach,
        approachNode = runtime.approachNode,
        departureNode = runtime.departureNode
      })
      return issueNativeRoute(vehicle, "prematureRouteDone")
    end
    runtime.routeDone = true
    runtime.status = "routeDone"
    runtime.reason = "nativeRouteDone"
    logger.info("autopilot", "stock_route_done", {
      targetDistance = runtime.routeDoneDistance,
      reachedGameplayRadius = runtime.routeDoneDistance <= arrivalRadius
    })
    return true
  end

  function service:onBypassComplete()
    -- Stale callbacks from the removed custom controller are ignored.
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
      stockAi = true
    }
  end

  function service:getDiagnostics(vehicle, target, phase)
    local targetDistance = vehicle and target and target.pos and
      distance(vehicle:getPosition(), target.pos) or runtime.targetDistance
    local safety = type(options.getSafetyObservation) == "function" and
      options.getSafetyObservation() or nil
    safety = type(safety) == "table" and safety or {}
    return {
      status = runtime.status,
      reason = runtime.reason,
      phase = phase,
      targetDistance = targetDistance,
      routeNodeCount = #runtime.routeNodes,
      routeDone = runtime.routeDone == true,
      routeDoneDistance = runtime.routeDoneDistance,
      routeDoneRetryCount = runtime.routeDoneRetryCount,
      orientedApproach = runtime.orientedApproach,
      approachNode = runtime.approachNode,
      departureNode = runtime.departureNode,
      stationarySeconds = runtime.stationarySeconds,
      movedDistance = runtime.movedDistance,
      elapsed = runtime.elapsed,
      commandCount = runtime.commandCount,
      speedKmh = vehicleSpeedKmh(vehicle, options.getSpeedKmh),
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
      stockAi = true,
      trafficGuard = true,
      customPerception = false,
      customRecovery = false
    }
  end

  return service
end

return M
