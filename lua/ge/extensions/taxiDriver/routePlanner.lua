local Route = require("gameplay/route/route")
local trafficUtils = require("gameplay/traffic/trafficUtils")
local offerGenerator = require("taxiDriver/offerGenerator")

local M = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function randomRange(minimum, maximum)
  return minimum + (maximum - minimum) * math.random()
end

local function tableHasValues(value)
  return type(value) == "table" and next(value) ~= nil
end

local function isFiniteNumber(value)
  value = tonumber(value)
  return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function isDistanceAllowed(distance, minimumDistance, maximumDistance)
  return distance ~= nil and distance >= minimumDistance and
    (maximumDistance == nil or distance <= maximumDistance)
end

M.isDistanceAllowed = isDistanceAllowed

function M.new(options)
  options = options or {}
  local service = {}
  local minimumDrivability = tonumber(options.minimumDrivability) or 0.25
  local config = options.offerConfig or {}
  local recentLimit = tonumber(config.recentStopLimit) or 20
  local recentSeparation = tonumber(config.recentStopSeparation) or 100
  local candidateCache = nil
  local candidateLevel = nil
  local roadEdgeCache = nil
  local roadEdgeLevel = nil
  local routePointCache = nil
  local routePointLevel = nil
  local recentPositions = {}
  local routeDistanceFailureLogged = false
  local semanticFailureLogged = false

  local function logSemanticFallback(message)
    if semanticFailureLogged then return end
    semanticFailureLogged = true
    log("W", "taxiDriver.routePlanner", message .. "; using road cache fallback")
  end

  local function getRoadLink(nodes, nodeA, nodeB)
    local firstNode = nodes and nodes[nodeA]
    local secondNode = nodes and nodes[nodeB]
    if not (firstNode and secondNode) then return nil end
    return (firstNode.links and firstNode.links[nodeB])
      or (secondNode.links and secondNode.links[nodeA])
  end

  local function isUsableRoad(nodes, nodeA, nodeB, allowPrivate)
    local ok, usable = pcall(function()
      local link = getRoadLink(nodes, nodeA, nodeB)
      if not link or (link.type == "private" and not allowPrivate) then return false end
      if (tonumber(link.drivability) or 0) < minimumDrivability then return false end
      local minimumRadius = allowPrivate and 1.8 or 2.4
      if math.min(
        tonumber(nodes[nodeA].radius) or 0,
        tonumber(nodes[nodeB].radius) or 0
      ) < minimumRadius then return false end
      return true
    end)
    return ok and usable == true
  end

  local function calculateGraphDistance(fromPos, toPos)
    local ok, result = pcall(function()
      if not (map and type(map.getMap) == "function" and
        type(map.getGraphpath) == "function" and
        type(map.findClosestRoad) == "function") then return nil end
      local mapData, graph = map.getMap(), map.getGraphpath()
      local nodes = mapData and mapData.nodes
      if not (tableHasValues(nodes) and graph and type(graph.getPath) == "function") then
        return nil
      end
      local fromA, fromB = map.findClosestRoad(fromPos)
      local toA, toB = map.findClosestRoad(toPos)
      fromA, fromB = fromA or fromB, fromB or fromA
      toA, toB = toA or toB, toB or toA
      local starts, targets = {fromA, fromB}, {toA, toB}
      local best = nil
      for _, startNode in ipairs(starts) do
        for _, targetNode in ipairs(targets) do
          if nodes[startNode] and nodes[targetNode] then
            local path = graph:getPath(startNode, targetNode)
            if type(path) == "table" then
              local routeDistance = fromPos:distance(nodes[startNode].pos)
              local previous = startNode
              for _, nodeId in ipairs(path) do
                if nodes[previous] and nodes[nodeId] and nodeId ~= previous then
                  routeDistance = routeDistance +
                    nodes[previous].pos:distance(nodes[nodeId].pos)
                end
                previous = nodeId
              end
              if previous == targetNode then
                routeDistance = routeDistance + nodes[targetNode].pos:distance(toPos)
                if best == nil or routeDistance < best then best = routeDistance end
              end
            end
          end
        end
      end
      return best
    end)
    return ok and result or nil
  end

  function service.calculateDistance(fromPos, toPos)
    local ok, result = pcall(function()
      local planner = Route()
      planner:setRouteParams(minimumDrivability)
      planner:setupPath(fromPos, toPos)
      if not (planner.path and planner.path[1] and planner.path[2]) then return nil end
      for _, pathPoint in ipairs(planner.path) do
        if pathPoint.wp then return planner.path[1].distToTarget end
      end
      return nil
    end)
    if ok and result then return result end
    local fallback = calculateGraphDistance(fromPos, toPos)
    if fallback then
      if not ok and not routeDistanceFailureLogged then
        routeDistanceFailureLogged = true
        log("W", "taxiDriver.routePlanner",
          "BeamNG Route failed; using graph-distance fallback: " .. tostring(result))
      end
      return fallback
    end
    if not ok and not routeDistanceFailureLogged then
      routeDistanceFailureLogged = true
      log("W", "taxiDriver.routePlanner",
        "BeamNG route-distance lookup failed: " .. tostring(result))
    end
    return nil
  end

  function service.getNearestRoadSpeedLimit(pos)
    if not pos then return nil end

    local ok, mapData = pcall(map.getMap)
    if not ok then return nil end
    if not (mapData and tableHasValues(mapData.nodes)) then return nil end

    local roadOk, nodeA, nodeB = pcall(map.findClosestRoad, pos)
    if not roadOk then return nil end
    local link = getRoadLink(mapData.nodes, nodeA, nodeB)
    local speedLimit = tonumber(link and link.speedLimit)
    if not speedLimit then return nil end

    speedLimit = speedLimit * 3.6
    if speedLimit < 5 or speedLimit > 250 then return nil end
    return speedLimit
  end

  local function isRecentlyUsed(pos)
    if not pos then return false end
    for _, recentPos in ipairs(recentPositions) do
      if pos:distance(recentPos) < recentSeparation then return true end
    end
    return false
  end

  local function remember(pos)
    if not pos then return end
    recentPositions[#recentPositions + 1] = vec3(pos)
    while #recentPositions > recentLimit do table.remove(recentPositions, 1) end
  end

  function service.rememberOfferStops(offer)
    if not offer then return end
    if offer.pickup then remember(offer.pickup.pos) end
    for _, stop in ipairs(offer.stops or {}) do remember(stop.pos) end
    if offer.destination then remember(offer.destination.pos) end
  end

  local function projectAnchorToRoadEdge(anchorPos, preferredNodeA, preferredNodeB, allowPrivate)
    local mapOk, mapData = pcall(map.getMap)
    if not mapOk then return nil end
    if not mapData or not tableHasValues(mapData.nodes) then return nil end
    local nodes = mapData.nodes
    local nodeA, nodeB = preferredNodeA, preferredNodeB
    if not (nodeA and nodeB and nodes[nodeA] and nodes[nodeB]) then
      local roadOk
      roadOk, nodeA, nodeB = pcall(map.findClosestRoad, anchorPos)
      if not roadOk then return nil end
    end
    if not (nodeA and nodeB and isUsableRoad(nodes, nodeA, nodeB, allowPrivate)) then return nil end

    local startPos = nodes[nodeA].pos
    local endPos = nodes[nodeB].pos
    local segment = endPos - startPos
    local segmentLengthSquared = segment:squaredLength()
    if segmentLengthSquared < 1 then return nil end
    local segmentLength = math.sqrt(segmentLengthSquared)
    local baseInterpolation = clamp((anchorPos - startPos):dot(segment) / segmentLengthSquared, 0, 1)
    local roadCenter = startPos + segment * baseInterpolation
    if anchorPos:distance(roadCenter) > 120 then return nil end

    local endpointMargin = math.min(0.25, 4 / segmentLength)
    local longitudinalJitter = math.min(config.semanticLongitudinalJitterMax, segmentLength * 0.38)
    local interpolation = clamp(
      baseInterpolation + randomRange(-longitudinalJitter, longitudinalJitter) / segmentLength,
      endpointMargin,
      1 - endpointMargin
    )
    roadCenter = startPos + segment * interpolation

    local roadDirection = vec3(segment.x, segment.y, 0)
    if roadDirection:length() < 0.1 then return nil end
    roadDirection:normalize()
    local roadSide = vec3(-roadDirection.y, roadDirection.x, 0)
    local sideDot = (anchorPos - roadCenter):dot(roadSide)
    local sideSign = sideDot < 0 and -1 or 1
    if math.abs(sideDot) < 0.5 and math.random() < 0.5 then sideSign = -sideSign end

    local radiusA = nodes[nodeA].radius or 2.4
    local radiusB = nodes[nodeB].radius or radiusA
    local roadRadius = radiusA + (radiusB - radiusA) * interpolation
    local edgeOffset = clamp(roadRadius - 0.75 + randomRange(-0.25, 0.55), 1.5, 14)
    local edgePos = roadCenter + roadSide * (edgeOffset * sideSign)
    local legalDirection = nil
    if trafficUtils and type(trafficUtils.finalizeSpawnPoint) == "function" then
      local finalizeOk, _, resultDirection = pcall(
        trafficUtils.finalizeSpawnPoint,
        edgePos,
        roadDirection,
        nodeA,
        nodeB,
        {legalDirection = true}
      )
      if finalizeOk then legalDirection = resultDirection end
    end
    return {
      pos = vec3(edgePos),
      dir = legalDirection and vec3(legalDirection) or roadDirection,
      nodeA = nodeA,
      nodeB = nodeB
    }
  end

  local function getRoadEdges()
    local level = getCurrentLevelIdentifier() or ""
    if roadEdgeCache and roadEdgeLevel == level then return roadEdgeCache end
    local mapOk, mapData = pcall(map.getMap)
    if not mapOk then mapData = nil end
    local nodes = mapData and mapData.nodes
    local edges = {}
    local seen = {}
    local scanned = 0
    if tableHasValues(nodes) then
      for nodeA, node in pairs(nodes) do
        for nodeB, _ in pairs(node.links or {}) do
          local firstKey = tostring(nodeA)
          local secondKey = tostring(nodeB)
          local edgeKey = firstKey < secondKey and
            (firstKey .. "\0" .. secondKey) or (secondKey .. "\0" .. firstKey)
          if not seen[edgeKey] then
            seen[edgeKey] = true
            if isUsableRoad(nodes, nodeA, nodeB) then
              edges[#edges + 1] = {nodeA = nodeA, nodeB = nodeB}
            end
          end
          scanned = scanned + 1
          if scanned % 64 == 0 then offerGenerator.yield() end
        end
      end
    end
    roadEdgeCache = edges
    roadEdgeLevel = level
    return edges
  end

  local function getRoutePoints()
    local level = getCurrentLevelIdentifier() or ""
    if routePointCache and routePointLevel == level then return routePointCache end
    local mapOk, mapData = pcall(map.getMap)
    local nodes = mapOk and mapData and mapData.nodes or nil
    local points, occupiedCells = {}, {}

    local function addPoint(stop)
      if not (stop and stop.pos and stop.nodeA and stop.nodeB) then return end
      local cellKey = string.format("%d:%d",
        math.floor(stop.pos.x / 20), math.floor(stop.pos.y / 20))
      if occupiedCells[cellKey] then return end
      occupiedCells[cellKey] = true
      stop.anchorKind = "routeCache"
      points[#points + 1] = stop
    end

    -- This in-memory fallback is rebuilt exclusively from the core road graph.
    -- Persistent /route_cache JSON is reserved for complete dispatcher offers
    -- that have actually reached the UI.
    for index, edge in ipairs(getRoadEdges()) do
      if index % 64 == 0 then offerGenerator.yield() end
      local nodeA, nodeB = nodes and nodes[edge.nodeA], nodes and nodes[edge.nodeB]
      if nodeA and nodeB and nodeA.pos and nodeB.pos then
        addPoint(projectAnchorToRoadEdge(
          nodeA.pos + (nodeB.pos - nodeA.pos) * 0.5,
          edge.nodeA,
          edge.nodeB,
          false
        ))
      end
    end

    routePointCache = points
    routePointLevel = level
    log("I", "taxiDriver.routePlanner", string.format(
      "Prepared %d in-memory road-graph route points for level '%s'",
      #points, level
    ))
    return points
  end

  local function getStopCandidates()
    local level = getCurrentLevelIdentifier() or ""
    if candidateCache and candidateLevel == level then return candidateCache end
    if candidateLevel ~= level then
      recentPositions = {}
      if type(options.onLevelChanged) == "function" then options.onLevelChanged(level) end
    end
    local candidates = {}
    local occupiedCells = {}
    local scanWork = 0
    local function addCandidate(pos, kind, name)
      if not pos then return end
      local ok, anchor = pcall(vec3, pos)
      if not ok or not anchor or not isFiniteNumber(anchor.x) or
        not isFiniteNumber(anchor.y) or not isFiniteNumber(anchor.z) then return end
      local cellKey = string.format("%d:%d", math.floor(anchor.x / 8), math.floor(anchor.y / 8))
      if occupiedCells[cellKey] then return end
      occupiedCells[cellKey] = true
      candidates[#candidates + 1] = {anchor = anchor, kind = kind, name = name or kind}
    end

    local triggerIds = {}
    if scenetree and type(scenetree.findClassObjects) == "function" then
      local ok, values = pcall(scenetree.findClassObjects, "BeamNGTrigger")
      if ok and type(values) == "table" then triggerIds = values
      else
        logSemanticFallback("Unable to enumerate bus-stop triggers")
      end
    end
    for _, objectId in ipairs(triggerIds) do
      scanWork = scanWork + 1
      if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
      local objectOk, object = pcall(scenetree.findObject, objectId)
      if objectOk and object then
        local dataOk, objectType, objectPos, stopName = pcall(function()
          return object.type, object:getPosition(), object.stopName
        end)
        if dataOk and objectType == "busstop" then
          addCandidate(objectPos, "busStop", stopName or objectId)
        end
      end
    end

    local sitesManager = gameplay_sites_sitesManager
    if sitesManager then
      local sitesFiles = {}
      local filesOk, values = pcall(sitesManager.getCurrentLevelSitesFiles)
      if filesOk and type(values) == "table" then sitesFiles = values
      else
        logSemanticFallback("Unable to enumerate level sites")
      end
      for _, sitesFile in ipairs(sitesFiles) do
        sitesFile = tostring(sitesFile or "")
        local lowerPath = string.lower(sitesFile)
        if not lowerPath:find("/missions/", 1, true) and
          not lowerPath:find("/quickrace/", 1, true) and
          not lowerPath:find("/scenarios/", 1, true) then
          local loaded, sites = pcall(sitesManager.loadSites, sitesFile)
          if not loaded then
            logSemanticFallback("Unable to read taxi stop anchors from '" .. sitesFile .. "'")
            sites = nil
          end
          local sortedOk, sortedSpots = pcall(function()
            return sites and sites.parkingSpots and sites.parkingSpots.sorted
          end)
          if sortedOk and type(sortedSpots) == "table" then
            for _, spot in ipairs(sortedSpots) do
              scanWork = scanWork + 1
              if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
              local spotOk, spotPos, spotKind, spotName, banned = pcall(function()
                local tags = spot.customFields and spot.customFields.tags or {}
                return spot.pos, tags.street and "streetParking" or "parking",
                  spot.name, tags.banned == true
              end)
              if spotOk and not banned then
                addCandidate(spotPos, spotKind, spotName)
              end
            end
          end
        end
      end
    end

    local poiIds = {}
    if scenetree and type(scenetree.findClassObjects) == "function" then
      local ok, values = pcall(scenetree.findClassObjects, "BeamNGPointOfInterest")
      if ok and type(values) == "table" then poiIds = values
      else
        logSemanticFallback("Unable to enumerate points of interest")
      end
    end
    for _, objectId in ipairs(poiIds) do
      scanWork = scanWork + 1
      if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
      local objectOk, object = pcall(scenetree.findObject, objectId)
      if objectOk and object then
        local positionOk, position = pcall(object.getPosition, object)
        if positionOk then addCandidate(position, "pointOfInterest", objectId) end
      end
    end
    candidateCache = candidates
    candidateLevel = level
    log("I", "taxiDriver.routePlanner", string.format(
      "Prepared %d semantic taxi stop anchors for level '%s'", #candidates, level
    ))
    return candidates
  end

  function service.getStopCandidateCount()
    return math.max(#getStopCandidates(), #getRoutePoints())
  end

  local function chooseSemanticStop(startPos, minimumDistance, maximumDistance)
    local candidates = getStopCandidates()
    if not candidates[1] then return nil end
    local order = {}
    for index = 1, #candidates do order[index] = index end
    for index = #order, 2, -1 do
      local swapIndex = math.random(index)
      order[index], order[swapIndex] = order[swapIndex], order[index]
    end
    local maximumAttempts = math.min(#order, config.semanticCandidateAttempts)
    local recentFallback = nil
    for attempt = 1, maximumAttempts do
      offerGenerator.yield()
      local candidate = candidates[order[attempt]]
      local directDistance = startPos:distance(candidate.anchor)
      if directDistance >= minimumDistance * 0.2 and
        (maximumDistance == nil or directDistance <= maximumDistance + 500) then
        local stop = projectAnchorToRoadEdge(candidate.anchor, nil, nil, true)
        if stop then
          local actualDistance = service.calculateDistance(startPos, stop.pos)
          if isDistanceAllowed(actualDistance, minimumDistance, maximumDistance) then
            stop.routeDistance = actualDistance
            stop.anchorKind = candidate.kind
            stop.anchorName = candidate.name
            if not isRecentlyUsed(stop.pos) then return stop end
            recentFallback = recentFallback or stop
          end
        end
      end
    end
    return nil, recentFallback
  end

  local function chooseGraphRoadStop(startPos, minimumDistance, maximumDistance)
    local points = getRoutePoints()
    if not points[1] then
      return nil, "No in-memory road-graph route points are available"
    end
    local order = {}
    for index = 1, #points do order[index] = index end
    for index = #order, 2, -1 do
      local swapIndex = math.random(index)
      order[index], order[swapIndex] = order[swapIndex], order[index]
    end

    local recentFallback = nil
    for _, pointIndex in ipairs(order) do
      offerGenerator.yield()
      local cached = points[pointIndex]
      local directDistance = startPos:distance(cached.pos)
      if directDistance >= minimumDistance * 0.2 and
        (maximumDistance == nil or directDistance <= maximumDistance + 1000) then
        local actualDistance = service.calculateDistance(startPos, cached.pos)
        if isDistanceAllowed(actualDistance, minimumDistance, maximumDistance) then
          local stop = {
            pos = vec3(cached.pos),
            dir = vec3(cached.dir),
            routeDistance = actualDistance,
            nodeA = cached.nodeA,
            nodeB = cached.nodeB,
            anchorKind = "routeCache"
          }
          if not isRecentlyUsed(stop.pos) then return stop end
          recentFallback = recentFallback or stop
        end
      end
    end
    if recentFallback then return recentFallback end
    return nil, string.format(
      "Road-graph fallback has no reachable point between %.0f and %s km",
      minimumDistance / 1000,
      maximumDistance and string.format("%.0f", maximumDistance / 1000) or "unlimited"
    )
  end

  local function buildRandomPath(nodes, startNode, startDirection, maximumDistance)
    local path = map.getGraphpath():getRandomPathG(
      startNode,
      startDirection,
      maximumDistance + 1000,
      0.35 + math.random() * 0.5,
      1,
      true
    )
    if not path or #path < 2 then return nil end
    local planner = Route()
    for _, nodeId in ipairs(path) do
      local node = nodes[nodeId]
      if node then
        planner.path[#planner.path + 1] = {pos = node.pos, wp = nodeId, linkCount = map.getNodeLinkCount(nodeId)}
      end
    end
    if #planner.path < 2 then return nil end
    planner:calcDistance()
    return planner
  end

  local function chooseRandomRoadStop(startPos, startDirection, minimumDistance, maximumDistance, maximumAttempts)
    local mapData = map.getMap()
    if not mapData or not tableHasValues(mapData.nodes) then
      return nil, "На этой карте отсутствует дорожный граф"
    end
    local nodes = mapData.nodes
    local nodeA, nodeB = map.findClosestRoad(startPos)
    if not (nodeA and nodeB and nodes[nodeA] and nodes[nodeB]) then
      return nil, "Не удалось найти дорогу рядом с автомобилем"
    end
    local forward = vec3(startDirection)
    forward.z = 0
    if forward:length() < 0.1 then forward:set(1, 0, 0) else forward:normalize() end
    local roadDirection = (nodes[nodeB].pos - nodes[nodeA].pos):normalized()
    if roadDirection:dot(forward) < 0 then nodeA, nodeB = nodeB, nodeA end

    local recentFallback = nil
    for attempt = 1, math.max(1, tonumber(maximumAttempts) or config.randomRouteAttempts) do
      offerGenerator.yield()
      local searchDirection = vec3(forward)
      if attempt % 4 == 0 then searchDirection:setScaled(-1) end
      local distanceRatio = math.random() ^ config.randomDistanceExponent
      local desiredDistance = minimumDistance + (maximumDistance - minimumDistance) * distanceRatio
      local planner = buildRandomPath(nodes, nodeA, searchDirection, maximumDistance)
      if planner and planner.path[1].distToTarget >= desiredDistance then
        local road = planner:stepAhead(desiredDistance, true)
        if road and road.n1 and road.n2 and isUsableRoad(nodes, road.n1, road.n2) then
          local direction = (nodes[road.n2].pos - nodes[road.n1].pos):normalized()
          local lanePos, laneDir = trafficUtils.finalizeSpawnPoint(
            road.pos,
            direction,
            road.n1,
            road.n2,
            {legalDirection = true}
          )
          local edgePoint = projectAnchorToRoadEdge(lanePos, road.n1, road.n2)
          local targetPos = edgePoint and edgePoint.pos or lanePos
          local targetDir = edgePoint and edgePoint.dir or laneDir
          local actualDistance = service.calculateDistance(startPos, targetPos)
          if isDistanceAllowed(actualDistance, minimumDistance, maximumDistance) then
            local stop = {
              pos = vec3(targetPos),
              dir = vec3(targetDir),
              routeDistance = actualDistance,
              nodeA = road.n1,
              nodeB = road.n2,
              anchorKind = "roadEdge"
            }
            if not isRecentlyUsed(stop.pos) then return stop end
            recentFallback = recentFallback or stop
          end
        end
      end
    end
    if recentFallback then return recentFallback end
    return nil, string.format(
      "Не удалось построить маршрут длиной от %.0f до %.0f км",
      minimumDistance / 1000,
      maximumDistance / 1000
    )
  end

  local function chooseUnboundedRoadStop(startPos, minimumDistance, maximumAttempts)
    local mapData = map.getMap()
    local nodes = mapData and mapData.nodes
    if not tableHasValues(nodes) then
      return nil, "На этой карте отсутствует дорожный граф"
    end
    local edges = getRoadEdges()
    if not edges[1] then return nil, "На этой карте отсутствуют доступные дороги" end

    local recentFallback = nil
    local attemptCount = math.max(1, tonumber(maximumAttempts) or config.unboundedRouteAttempts or 48)
    for _ = 1, attemptCount do
      offerGenerator.yield()
      local edge = edges[math.random(#edges)]
      local nodeA = nodes[edge.nodeA]
      local nodeB = nodes[edge.nodeB]
      if nodeA and nodeB then
        local interpolation = randomRange(0.2, 0.8)
        local anchor = nodeA.pos + (nodeB.pos - nodeA.pos) * interpolation
        local stop = projectAnchorToRoadEdge(anchor, edge.nodeA, edge.nodeB)
        if stop then
          local actualDistance = service.calculateDistance(startPos, stop.pos)
          if isDistanceAllowed(actualDistance, minimumDistance, nil) then
            stop.routeDistance = actualDistance
            stop.anchorKind = "roadEdge"
            if not isRecentlyUsed(stop.pos) then return stop end
            recentFallback = recentFallback or stop
          end
        end
      end
    end
    if recentFallback then return recentFallback end
    return nil, string.format(
      "Не удалось построить маршрут длиной от %.0f км без верхнего ограничения",
      minimumDistance / 1000
    )
  end

  function service.chooseStop(startPos, startDirection, minimumDistance, maximumDistance, maximumAttempts)
    -- Prepare the independent fallback before touching semantic map data. This
    -- ensures every playable road graph gets a persistent cache even on maps
    -- whose semantic anchors happen to satisfy the first generated order.
    getRoutePoints()
    local semanticStop, semanticFallback = chooseSemanticStop(startPos, minimumDistance, maximumDistance)
    if semanticStop then return semanticStop end
    local cachedStop, cachedError = chooseGraphRoadStop(
      startPos,
      minimumDistance,
      maximumDistance
    )
    if cachedStop then return cachedStop end
    local randomStop, randomError
    if maximumDistance == nil then
      randomStop, randomError = chooseUnboundedRoadStop(startPos, minimumDistance, maximumAttempts)
    else
      randomStop, randomError = chooseRandomRoadStop(
        startPos,
        startDirection,
        minimumDistance,
        maximumDistance,
        maximumAttempts
      )
    end
    if randomStop then return randomStop end
    if semanticFallback then return semanticFallback end
    return nil, randomError or cachedError
  end

  function service.reset()
    candidateCache = nil
    candidateLevel = nil
    roadEdgeCache = nil
    roadEdgeLevel = nil
    routePointCache = nil
    routePointLevel = nil
    recentPositions = {}
    routeDistanceFailureLogged = false
    semanticFailureLogged = false
  end

  function service.clearRecent()
    recentPositions = {}
  end

  return service
end

return M
