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

function M.new(options)
  options = options or {}
  local service = {}
  local minimumDrivability = tonumber(options.minimumDrivability) or 0.25
  local config = options.offerConfig or {}
  local recentLimit = tonumber(config.recentStopLimit) or 20
  local recentSeparation = tonumber(config.recentStopSeparation) or 100
  local candidateCache = nil
  local candidateLevel = nil
  local recentPositions = {}

  local function getRoadLink(nodes, nodeA, nodeB)
    local firstNode = nodes and nodes[nodeA]
    local secondNode = nodes and nodes[nodeB]
    if not (firstNode and secondNode) then return nil end
    return (firstNode.links and firstNode.links[nodeB])
      or (secondNode.links and secondNode.links[nodeA])
  end

  local function isUsableRoad(nodes, nodeA, nodeB, allowPrivate)
    local link = getRoadLink(nodes, nodeA, nodeB)
    if not link or (link.type == "private" and not allowPrivate) then return false end
    if (link.drivability or 0) < minimumDrivability then return false end
    local minimumRadius = allowPrivate and 1.8 or 2.4
    if math.min(nodes[nodeA].radius or 0, nodes[nodeB].radius or 0) < minimumRadius then return false end
    return true
  end

  function service.calculateDistance(fromPos, toPos)
    local planner = Route()
    planner:setRouteParams(minimumDrivability)
    planner:setupPath(fromPos, toPos)
    if not (planner.path and planner.path[1] and planner.path[2]) then return nil end
    for _, pathPoint in ipairs(planner.path) do
      if pathPoint.wp then return planner.path[1].distToTarget end
    end
    return nil
  end

  function service.getNearestRoadSpeedLimit(pos)
    if not pos then return nil end

    local mapData = map.getMap()
    if not (mapData and tableHasValues(mapData.nodes)) then return nil end

    local nodeA, nodeB = map.findClosestRoad(pos)
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
    local mapData = map.getMap()
    if not mapData or not tableHasValues(mapData.nodes) then return nil end
    local nodes = mapData.nodes
    local nodeA, nodeB = preferredNodeA, preferredNodeB
    if not (nodeA and nodeB and nodes[nodeA] and nodes[nodeB]) then
      nodeA, nodeB = map.findClosestRoad(anchorPos)
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
    local _, legalDirection = trafficUtils.finalizeSpawnPoint(
      edgePos,
      roadDirection,
      nodeA,
      nodeB,
      {legalDirection = true}
    )
    return {
      pos = vec3(edgePos),
      dir = legalDirection and vec3(legalDirection) or roadDirection,
      nodeA = nodeA,
      nodeB = nodeB
    }
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
      local anchor = vec3(pos)
      local cellKey = string.format("%d:%d", math.floor(anchor.x / 8), math.floor(anchor.y / 8))
      if occupiedCells[cellKey] then return end
      occupiedCells[cellKey] = true
      candidates[#candidates + 1] = {anchor = anchor, kind = kind, name = name or kind}
    end

    for _, objectId in ipairs(scenetree.findClassObjects("BeamNGTrigger") or {}) do
      scanWork = scanWork + 1
      if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
      local object = scenetree.findObject(objectId)
      if object and object.type == "busstop" then
        addCandidate(object:getPosition(), "busStop", object.stopName or objectId)
      end
    end

    local sitesManager = gameplay_sites_sitesManager
    if sitesManager then
      for _, sitesFile in ipairs(sitesManager.getCurrentLevelSitesFiles() or {}) do
        local lowerPath = string.lower(sitesFile)
        if not lowerPath:find("/missions/", 1, true) and
          not lowerPath:find("/quickrace/", 1, true) and
          not lowerPath:find("/scenarios/", 1, true) then
          local loaded, sites = pcall(sitesManager.loadSites, sitesFile)
          if not loaded then
            log("W", "taxiDriver.routePlanner", "Unable to read taxi stop anchors from '" .. sitesFile .. "'")
            sites = nil
          end
          if sites and sites.parkingSpots and sites.parkingSpots.sorted then
            for _, spot in ipairs(sites.parkingSpots.sorted) do
              scanWork = scanWork + 1
              if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
              local tags = spot.customFields and spot.customFields.tags or {}
              if not tags.banned then
                addCandidate(spot.pos, tags.street and "streetParking" or "parking", spot.name)
              end
            end
          end
        end
      end
    end

    for _, objectId in ipairs(scenetree.findClassObjects("BeamNGPointOfInterest") or {}) do
      scanWork = scanWork + 1
      if scanWork % config.semanticScanBatchSize == 0 then offerGenerator.yield() end
      local object = scenetree.findObject(objectId)
      if object then addCandidate(object:getPosition(), "pointOfInterest", objectId) end
    end
    candidateCache = candidates
    candidateLevel = level
    log("I", "taxiDriver.routePlanner", string.format(
      "Prepared %d semantic taxi stop anchors for level '%s'", #candidates, level
    ))
    return candidates
  end

  function service.getStopCandidateCount()
    return #getStopCandidates()
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
      if directDistance >= minimumDistance * 0.2 and directDistance <= maximumDistance + 500 then
        local stop = projectAnchorToRoadEdge(candidate.anchor, nil, nil, true)
        if stop then
          local actualDistance = service.calculateDistance(startPos, stop.pos)
          if actualDistance and actualDistance >= minimumDistance and actualDistance <= maximumDistance then
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
          if actualDistance and actualDistance >= minimumDistance and actualDistance <= maximumDistance then
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

  function service.chooseStop(startPos, startDirection, minimumDistance, maximumDistance, maximumAttempts)
    local semanticStop, semanticFallback = chooseSemanticStop(startPos, minimumDistance, maximumDistance)
    if semanticStop then return semanticStop end
    local randomStop, randomError = chooseRandomRoadStop(
      startPos,
      startDirection,
      minimumDistance,
      maximumDistance,
      maximumAttempts
    )
    if randomStop then return randomStop end
    if semanticFallback then return semanticFallback end
    return nil, randomError
  end

  function service.reset()
    candidateCache = nil
    candidateLevel = nil
    recentPositions = {}
  end

  function service.clearRecent()
    recentPositions = {}
  end

  return service
end

return M
