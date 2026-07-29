local M = {}

-- BeamNG 0.39 route-planning adapter.
--
-- Public contract:
--   local service = M.new(options)
--   service:request(vehicle, target, routeRevision, callback)
--   service:cancel()
--   service:getStatus()
--
-- callback is invoked as callback(success, result, error). On success,
-- result.path contains graph node ids only; coordinate-only Route markers are
-- deliberately excluded because vehicle ai.driveUsingPath cannot consume them.
-- A request superseded by cancel() or a newer request is stale and never calls
-- its callback.

local routeModuleAvailable, DefaultRoute = pcall(require, "gameplay/route/route")
if not routeModuleAvailable then DefaultRoute = nil end

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function finite(value)
  value = tonumber(value)
  return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function positionDistance(first, second)
  if not first or not second then return math.huge end
  if type(first.distance) == "function" then
    local ok, value = pcall(first.distance, first, second)
    if ok and finite(value) then return value end
  end
  local dx = number(first.x, 0) - number(second.x, 0)
  local dy = number(first.y, 0) - number(second.y, 0)
  local dz = number(first.z, 0) - number(second.z, 0)
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function copyPosition(value)
  if not value or not finite(value.x) or not finite(value.y) or not finite(value.z) then
    return nil
  end
  if type(vec3) == "function" then
    return vec3(number(value.x, 0), number(value.y, 0), number(value.z, 0))
  end
  return {x = number(value.x, 0), y = number(value.y, 0), z = number(value.z, 0)}
end

local function safeLog(level, message)
  if type(log) == "function" then
    log(level, "taxiDriver.aiDriverRoute", tostring(message))
  end
end

local function safeCallback(callback, success, result, err)
  if type(callback) ~= "function" then return end
  local ok, callbackError = pcall(callback, success == true, result, err)
  if not ok then safeLog("E", "Route callback failed: " .. tostring(callbackError)) end
end

local function appendUnique(path, nodeId)
  if nodeId == nil then return end
  local value = tostring(nodeId)
  if value == "" then return end
  if path[#path] ~= value then path[#path + 1] = value end
end

local function filterGraphNodes(markers, graphNodes)
  local path = {}
  for _, marker in ipairs(type(markers) == "table" and markers or {}) do
    local nodeId
    if type(marker) == "table" then
      nodeId = marker.wp
    elseif type(marker) == "string" or type(marker) == "number" then
      nodeId = marker
    end
    if nodeId ~= nil then
      local key = graphNodes and (graphNodes[nodeId] and nodeId or tostring(nodeId)) or nodeId
      if not graphNodes or graphNodes[key] then appendUnique(path, key) end
    end
  end
  return path
end

local resolveNodeId

local function copyPath(path)
  local result = {}
  for index, nodeId in ipairs(type(path) == "table" and path or {}) do
    result[index] = nodeId
  end
  return result
end

local function nodeProjection(node, position, direction)
  if not node or not node.pos or not position or not direction then return nil end
  local directionX, directionY = number(direction.x, 0), number(direction.y, 0)
  local directionLength = math.sqrt(directionX * directionX + directionY * directionY)
  if directionLength < 0.001 then return nil end
  directionX, directionY = directionX / directionLength, directionY / directionLength
  local offsetX = number(node.pos.x, 0) - number(position.x, 0)
  local offsetY = number(node.pos.y, 0) - number(position.y, 0)
  local horizontalDistance = math.sqrt(offsetX * offsetX + offsetY * offsetY)
  if horizontalDistance < 0.001 then
    return {longitudinal = 0, directionDot = 0, distance = 0}
  end
  local longitudinal = offsetX * directionX + offsetY * directionY
  return {
    longitudinal = longitudinal,
    directionDot = longitudinal / horizontalDistance,
    distance = horizontalDistance
  }
end

-- BeamNG's stock taxi mode removes route nodes behind the cab before handing
-- the path to vehicle AI. Keep the useful idea, but bound it: the stock local
-- maximum search can otherwise skip a long straight section up to its first
-- bend. This normalizer only removes an unambiguous, short prefix and never
-- consumes the protected target approach/departure suffix.
local function trimStartPath(path, context, vehicle, approachNode, departureNode)
  local result = copyPath(path)
  local diagnostics = {
    originalCount = #result,
    trimmedCount = 0,
    remainingCount = #result,
    removedNodes = {},
    reason = "unchanged",
    skippedPrefixMeters = 0
  }
  if #result < 3 or not context or not context.nodes or not vehicle then
    diagnostics.reason = #result < 3 and "pathTooShort" or "poseUnavailable"
    return result, diagnostics
  end

  local okPosition, rawPosition = pcall(vehicle.getPosition, vehicle)
  local okDirection, rawDirection = pcall(vehicle.getDirectionVector, vehicle)
  local position = okPosition and copyPosition(rawPosition) or nil
  local direction = okDirection and copyPosition(rawDirection) or nil
  if not position or not direction then
    diagnostics.reason = "poseUnavailable"
    return result, diagnostics
  end

  local protectedStart = #result + 1
  local approachValue = approachNode and tostring(approachNode) or nil
  local departureValue = departureNode and tostring(departureNode) or nil
  for index, nodeId in ipairs(result) do
    local value = tostring(nodeId)
    if value == approachValue or value == departureValue then
      protectedStart = math.min(protectedStart, index)
    end
  end
  local maximumRemoval = math.min(3, #result - 2, protectedStart - 1)
  if maximumRemoval < 1 then
    diagnostics.reason = "targetSuffixProtected"
    return result, diagnostics
  end

  local function projection(index)
    local nodeId = resolveNodeId(context.nodes, result[index])
    return nodeId and nodeProjection(context.nodes[nodeId], position, direction) or nil
  end
  local function clearlyBehind(value)
    return value and value.longitudinal <= -2 and value.directionDot <= -0.15
  end
  local function clearlyForward(value)
    return value and value.longitudinal >= 2 and value.directionDot >= 0.15
  end

  local removeCount, reason = 0, nil
  if map and type(map.findBestRoad) == "function" and maximumRemoval >= 1 then
    local okRoad, firstRoadNode, secondRoadNode = pcall(map.findBestRoad,
      position, direction)
    firstRoadNode = okRoad and resolveNodeId(context.nodes, firstRoadNode) or nil
    secondRoadNode = okRoad and resolveNodeId(context.nodes, secondRoadNode) or nil
    local pathFirst = resolveNodeId(context.nodes, result[1])
    local pathSecond = resolveNodeId(context.nodes, result[2])
    local currentEdge = firstRoadNode and secondRoadNode and
      ((pathFirst == firstRoadNode and pathSecond == secondRoadNode) or
       (pathFirst == secondRoadNode and pathSecond == firstRoadNode))
    if currentEdge and clearlyBehind(projection(1)) and
      clearlyForward(projection(2)) then
      removeCount, reason = 1, "currentRoadEdgeBehindEndpoint"
    end
  end

  if removeCount == 0 then
    local previousPosition = position
    local cumulativeDistance = 0
    local scanLimit = math.min(4, #result, maximumRemoval + 1)
    local behindCount = 0
    for index = 1, scanLimit do
      local nodeId = resolveNodeId(context.nodes, result[index])
      local node = nodeId and context.nodes[nodeId] or nil
      if not node or not node.pos then break end
      cumulativeDistance = cumulativeDistance + positionDistance(previousPosition,
        node.pos)
      if cumulativeDistance > 30 then break end
      local value = projection(index)
      if index <= maximumRemoval and clearlyBehind(value) then
        behindCount = behindCount + 1
        previousPosition = node.pos
      elseif behindCount > 0 and clearlyForward(value) then
        removeCount, reason = behindCount, "shortBehindPrefix"
        break
      else
        break
      end
    end
  end

  if removeCount == 0 then
    diagnostics.reason = "ambiguousOrUnboundedPrefix"
    return result, diagnostics
  end

  local previousPosition = position
  for _ = 1, removeCount do
    local nodeId = table.remove(result, 1)
    diagnostics.removedNodes[#diagnostics.removedNodes + 1] = tostring(nodeId)
    local resolved = resolveNodeId(context.nodes, nodeId)
    local node = resolved and context.nodes[resolved] or nil
    if node and node.pos then
      diagnostics.skippedPrefixMeters = diagnostics.skippedPrefixMeters +
        positionDistance(previousPosition, node.pos)
      previousPosition = node.pos
    end
  end
  diagnostics.trimmedCount = removeCount
  diagnostics.remainingCount = #result
  diagnostics.reason = reason
  return result, diagnostics
end

resolveNodeId = function(nodes, value)
  if not nodes or value == nil then return nil end
  if nodes[value] then return value end
  value = tostring(value)
  return nodes[value] and value or nil
end

local function mapContext()
  if not map or type(map.getMap) ~= "function" or
    type(map.getGraphpath) ~= "function" then return nil end
  local okMap, mapData = pcall(map.getMap)
  local okGraph, graphPath = pcall(map.getGraphpath)
  if not okMap or not okGraph or not mapData or not graphPath then return nil end
  local nodes = mapData.nodes
  local roads = graphPath.graph
  if type(nodes) ~= "table" or type(roads) ~= "table" then return nil end
  return {mapData = mapData, graphPath = graphPath, nodes = nodes, roads = roads}
end

local function orientedTargetEdge(target, context)
  if type(target) ~= "table" or not target.dir or not context then return nil, nil end
  local nodeA = resolveNodeId(context.nodes, target.nodeA)
  local nodeB = resolveNodeId(context.nodes, target.nodeB)
  if not nodeA or not nodeB then return nil, nil end
  local first, second = context.nodes[nodeA], context.nodes[nodeB]
  local edge = context.roads[nodeA] and context.roads[nodeA][nodeB]
  if not edge or not first.pos or not second.pos then return nil, nil end
  local edgeX = number(second.pos.x, 0) - number(first.pos.x, 0)
  local edgeY = number(second.pos.y, 0) - number(first.pos.y, 0)
  local targetX = number(target.dir.x, 0)
  local targetY = number(target.dir.y, 0)
  if edgeX * targetX + edgeY * targetY >= 0 then return nodeA, nodeB end
  return nodeB, nodeA
end

local function legalIntoNode(edge, toNode)
  return edge and not (edge.oneWay and edge.inNode == toNode)
end

local function alternativeApproachPredecessor(context, approachNode, departureNode,
  startPosition, minimumDrivability)
  local best, bestCost
  for candidate, edge in pairs(context.roads[approachNode] or {}) do
    if candidate ~= departureNode and context.nodes[candidate] and
      context.nodes[candidate].pos and legalIntoNode(edge, approachNode) and
      number(edge.drivability, 0) >= minimumDrivability then
      local cost = positionDistance(startPosition, context.nodes[candidate].pos)
      if not bestCost or cost < bestCost then best, bestCost = candidate, cost end
    end
  end
  return best
end

local function routeDistanceFromNodes(path, context, startPosition, targetPosition)
  if not context or #path == 0 then return nil end
  local total, previousPosition = 0, startPosition
  for _, nodeId in ipairs(path) do
    local node = context.nodes[nodeId]
    if not node or not node.pos then return nil end
    total = total + positionDistance(previousPosition, node.pos)
    previousPosition = node.pos
  end
  if targetPosition then total = total + positionDistance(previousPosition, targetPosition) end
  return total
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local service = {}
  local routeFactory = options.routeFactory or DefaultRoute
  local minimumDrivability = math.max(0, number(options.minimumDrivability, 0.25))
  local directionPenalty = math.max(1, number(options.directionPenalty, 1e4))
  local penaltyAboveCutoff = math.max(0.01, number(options.penaltyAboveCutoff, 1))
  local penaltyBelowCutoff = math.max(1, number(options.penaltyBelowCutoff, 10000))
  local verticalWeight = math.max(1, number(options.verticalWeight, 4))
  local maximumFallbackNodes = math.max(100, number(options.maximumFallbackNodes, 12000))
  local maximumFallbackDistance = math.max(100, number(options.maximumFallbackDistance, 6000))

  local runtime = {
    generation = 0,
    status = "idle",
    source = nil,
    routeRevision = nil,
    error = nil,
    pathCount = 0,
    asyncAvailable = false,
    planner = nil
  }

  local function newPlanner()
    if type(routeFactory) ~= "function" then return nil end
    local ok, planner = pcall(routeFactory)
    if not ok or type(planner) ~= "table" then return nil end
    return planner
  end

  local function configurePlanner(planner)
    if type(planner.setRouteParams) == "function" then
      local ok, err = pcall(planner.setRouteParams, planner,
        minimumDrivability, directionPenalty, penaltyAboveCutoff,
        penaltyBelowCutoff, nil, verticalWeight)
      if not ok then return false, err end
    end
    return true
  end

  local function cancelPlanner()
    local planner = runtime.planner
    runtime.planner = nil
    if planner and type(planner.clear) == "function" then
      local ok, err = pcall(planner.clear, planner)
      if not ok then safeLog("W", "Unable to cancel route job: " .. tostring(err)) end
    end
  end

  local function setFailure(generation, revision, callback, err)
    if generation ~= runtime.generation then return end
    runtime.planner = nil
    runtime.status = "failed"
    runtime.error = tostring(err or "routeUnavailable")
    runtime.pathCount = 0
    safeCallback(callback, false, nil, runtime.error)
  end

  local function setSuccess(generation, revision, callback, path, source,
    approachNode, departureNode, distance, diagnostics)
    if generation ~= runtime.generation then return end
    runtime.planner = nil
    runtime.status = "ready"
    runtime.source = source
    runtime.error = nil
    runtime.pathCount = #path
    local result = {
      path = path,
      -- nodes is retained for the first integration revision; new callers
      -- should consume path, which is the stable public field.
      nodes = path,
      source = source,
      routeRevision = revision,
      approachNode = approachNode and tostring(approachNode) or nil,
      departureNode = departureNode and tostring(departureNode) or nil,
      distance = distance,
      diagnostics = diagnostics
    }
    safeCallback(callback, true, result, nil)
  end

  local function countGraphNodes(roads, limit)
    local count = 0
    for _ in pairs(roads or {}) do
      count = count + 1
      if count > limit then return count end
    end
    return count
  end

  local function startRoadNode(vehicle, context, startPosition)
    if not map or type(map.findBestRoad) ~= "function" or
      type(map.findClosestRoad) ~= "function" then return nil end
    local direction
    if type(vehicle.getDirectionVector) == "function" then
      local ok, value = pcall(vehicle.getDirectionVector, vehicle)
      if ok then direction = value end
    end
    local first, second
    if direction then
      local ok, valueA, valueB = pcall(map.findBestRoad, startPosition, direction)
      if ok then first, second = valueA, valueB end
    end
    if not first then
      local ok, valueA, valueB = pcall(map.findClosestRoad, startPosition)
      if ok then first, second = valueA, valueB end
    end
    first = resolveNodeId(context.nodes, first)
    second = resolveNodeId(context.nodes, second)
    if not first then return second end
    if not second or not direction then return first end
    local firstPos, secondPos = context.nodes[first].pos, context.nodes[second].pos
    if not firstPos or not secondPos then return first end
    local dot = (number(secondPos.x, 0) - number(firstPos.x, 0)) * number(direction.x, 0) +
      (number(secondPos.y, 0) - number(firstPos.y, 0)) * number(direction.y, 0)
    return dot >= 0 and second or first
  end

  local function synchronousFallback(generation, vehicle, target, revision, callback,
    context, startPosition, targetPosition, approachNode, departureNode)
    runtime.source = "graphpathFallback"
    if positionDistance(startPosition, targetPosition) > maximumFallbackDistance then
      return setFailure(generation, revision, callback, "fallbackDistanceLimit")
    end
    if countGraphNodes(context.roads, maximumFallbackNodes) > maximumFallbackNodes then
      return setFailure(generation, revision, callback, "fallbackGraphSizeLimit")
    end
    local graphPath = context.graphPath
    if type(graphPath.getFilteredPath) ~= "function" then
      return setFailure(generation, revision, callback, "filteredGraphpathUnavailable")
    end
    local startNode = startRoadNode(vehicle, context, startPosition)
    local destinationNode = approachNode
    if not destinationNode and map and type(map.findClosestRoad) == "function" then
      local ok, first, second = pcall(map.findClosestRoad, targetPosition)
      if ok then
        destinationNode = resolveNodeId(context.nodes, second) or
          resolveNodeId(context.nodes, first)
      end
    end
    if not startNode or not destinationNode then
      return setFailure(generation, revision, callback, "fallbackEndpointUnavailable")
    end
    local ok, rawPath = pcall(graphPath.getFilteredPath, graphPath, startNode,
      destinationNode, minimumDrivability, directionPenalty,
      penaltyAboveCutoff, penaltyBelowCutoff)
    if not ok or type(rawPath) ~= "table" then
      return setFailure(generation, revision, callback, "fallbackPathFailed")
    end
    local path = filterGraphNodes(rawPath, context.nodes)
    if approachNode and departureNode then
      if path[#path - 1] == tostring(departureNode) and
        path[#path] == tostring(approachNode) then
        return setFailure(generation, revision, callback, "orientedApproachWouldReverse")
      end
      appendUnique(path, approachNode)
      appendUnique(path, departureNode)
    end
    local trimDiagnostics
    path, trimDiagnostics = trimStartPath(path, context, vehicle, approachNode,
      departureNode)
    if #path < 2 then
      return setFailure(generation, revision, callback, "fallbackPathTooShort")
    end
    local distance = routeDistanceFromNodes(path, context, startPosition, nil)
    if approachNode and targetPosition and context.nodes[approachNode] then
      -- Trip distance ends at the gameplay target, not at the overshoot node.
      local throughTarget = {}
      for _, nodeId in ipairs(path) do
        if nodeId == tostring(departureNode) then break end
        throughTarget[#throughTarget + 1] = nodeId
      end
      distance = routeDistanceFromNodes(throughTarget, context, startPosition,
        targetPosition)
    end
    setSuccess(generation, revision, callback, path, "graphpathFallback",
      approachNode, departureNode, distance, {
        async = false,
        startPathTrim = trimDiagnostics
      })
    return true
  end

  function service:cancel()
    runtime.generation = runtime.generation + 1
    cancelPlanner()
    runtime.status = "cancelled"
    runtime.source = nil
    runtime.routeRevision = nil
    runtime.error = nil
    runtime.pathCount = 0
  end

  function service:request(vehicle, target, revision, callback)
    runtime.generation = runtime.generation + 1
    local generation = runtime.generation
    cancelPlanner()
    runtime.status = "planning"
    runtime.source = nil
    runtime.routeRevision = revision
    runtime.error = nil
    runtime.pathCount = 0

    if not vehicle or type(vehicle.getPosition) ~= "function" or
      type(target) ~= "table" then
      setFailure(generation, revision, callback, "invalidRouteRequest")
      return false
    end
    local positionOk, rawStartPosition = pcall(vehicle.getPosition, vehicle)
    local startPosition = positionOk and copyPosition(rawStartPosition) or nil
    local targetPosition = copyPosition(target.pos)
    if not startPosition or not targetPosition then
      setFailure(generation, revision, callback, "invalidRoutePosition")
      return false
    end
    local context = mapContext()
    if not context then
      setFailure(generation, revision, callback, "roadGraphUnavailable")
      return false
    end
    local approachNode, departureNode = orientedTargetEdge(target, context)
    local planningTarget = approachNode and context.nodes[approachNode] and
      copyPosition(context.nodes[approachNode].pos) or targetPosition

    local probe = newPlanner()
    runtime.asyncAvailable = probe ~= nil and
      type(probe.setupPathMultiJob) == "function"
    if not runtime.asyncAvailable then
      return synchronousFallback(generation, vehicle, target, revision, callback,
        context, startPosition, targetPosition, approachNode, departureNode)
    end

    local function launchAsync(viaNode, orientedRetry)
      if generation ~= runtime.generation then return false end
      local planner = orientedRetry and newPlanner() or probe
      if not planner or type(planner.setupPathMultiJob) ~= "function" then
        setFailure(generation, revision, callback, "asyncPlannerUnavailable")
        return false
      end
      local configured, configurationError = configurePlanner(planner)
      if not configured then
        setFailure(generation, revision, callback,
          "asyncPlannerConfigurationFailed: " .. tostring(configurationError))
        return false
      end
      runtime.planner = planner
      runtime.status = orientedRetry and "planningOrientedApproach" or "planning"
      runtime.source = orientedRetry and "beamngRouteAsyncOriented" or
        "beamngRouteAsync"
      local positions = {startPosition}
      if viaNode and context.nodes[viaNode] and context.nodes[viaNode].pos then
        positions[#positions + 1] = copyPosition(context.nodes[viaNode].pos)
      end
      positions[#positions + 1] = planningTarget

      local ok, err = pcall(planner.setupPathMultiJob, planner, positions,
        function(completedPlanner)
          if generation ~= runtime.generation then return end
          local path = filterGraphNodes(completedPlanner and completedPlanner.path,
            context.nodes)
          local usedBidirectionalPass = false
          if approachNode and departureNode then
            local reverseApproach = path[#path - 1] == tostring(departureNode) and
              path[#path] == tostring(approachNode)
            if reverseApproach and not orientedRetry then
              local targetEdge = context.roads[approachNode] and
                context.roads[approachNode][departureNode] or nil
              if targetEdge and targetEdge.oneWay == true then
                local predecessor = alternativeApproachPredecessor(context,
                  approachNode, departureNode, startPosition, minimumDrivability)
                if predecessor then
                  launchAsync(predecessor, true)
                  return
                end
                setFailure(generation, revision, callback,
                  "oneWayApproachWouldReverse")
                return
              end
              -- On a bidirectional target edge the shortest native route has
              -- already crossed the gameplay point between departureNode and
              -- approachNode. Keep that route instead of appending a U-turn.
              usedBidirectionalPass = true
            elseif reverseApproach then
              local targetEdge = context.roads[approachNode] and
                context.roads[approachNode][departureNode] or nil
              if targetEdge and targetEdge.oneWay == true then
                setFailure(generation, revision, callback,
                  "oneWayApproachWouldReverse")
                return
              end
              usedBidirectionalPass = true
            end
            if not usedBidirectionalPass then
              appendUnique(path, approachNode)
              appendUnique(path, departureNode)
            end
          end
          local trimDiagnostics
          path, trimDiagnostics = trimStartPath(path, context, vehicle,
            approachNode, departureNode)
          if #path < 2 then
            setFailure(generation, revision, callback, "asyncPathTooShort")
            return
          end
          local routeDistance = number(completedPlanner and completedPlanner.distance,
            nil)
          if routeDistance and approachNode and context.nodes[approachNode] then
            routeDistance = routeDistance + positionDistance(
              context.nodes[approachNode].pos, targetPosition)
          end
          setSuccess(generation, revision, callback, path,
            orientedRetry and "beamngRouteAsyncOriented" or "beamngRouteAsync",
            approachNode, departureNode, routeDistance, {
              async = true,
              orientedRetry = orientedRetry == true,
              bidirectionalPass = usedBidirectionalPass,
              viaNode = viaNode and tostring(viaNode) or nil,
              startPathTrim = trimDiagnostics
            })
        end)
      if not ok then
        setFailure(generation, revision, callback,
          "asyncRouteStartFailed: " .. tostring(err))
        return false
      end
      return true
    end

    return launchAsync(nil, false)
  end

  function service:getStatus()
    return {
      status = runtime.status,
      source = runtime.source,
      routeRevision = runtime.routeRevision,
      error = runtime.error,
      pathCount = runtime.pathCount,
      asyncAvailable = runtime.asyncAvailable,
      generation = runtime.generation
    }
  end

  return service
end

return M
