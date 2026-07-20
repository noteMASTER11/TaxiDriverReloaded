local M = {}

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function length2(x, y)
  return math.sqrt(x * x + y * y)
end

local function dimension(object, method, fallback)
  if object and type(object[method]) == "function" then
    local ok, value = pcall(object[method], object)
    if ok and number(value, 0) > 0 then return number(value, fallback) end
  end
  return fallback
end

local function vehicleObject(id)
  if type(getObjectByID) ~= "function" then return nil end
  local ok, result = pcall(getObjectByID, id)
  return ok and result or nil
end

local function velocity(data, forwardX, forwardY)
  local value = data and data.vel
  if not value then return 0 end
  return number(value.x, 0) * forwardX + number(value.y, 0) * forwardY
end

local function smoothStep(value)
  value = math.max(0, math.min(1, value))
  return value * value * (3 - 2 * value)
end

local function roadContext(vehicle)
  if not map or type(map.getMap) ~= "function" or type(map.findClosestRoad) ~= "function" then
    return nil, "mapUnavailable"
  end
  local position = vehicle:getPosition()
  local nodeA, nodeB = map.findClosestRoad(position)
  local mapData = map.getMap()
  local nodes = mapData and mapData.nodes
  local first, second = nodes and nodes[nodeA], nodes and nodes[nodeB]
  local link = first and second and ((first.links and first.links[nodeB]) or
    (second.links and second.links[nodeA])) or nil
  if not link or not first.pos or not second.pos then return nil, "roadUnavailable" end

  local roadX = number(second.pos.x, 0) - number(first.pos.x, 0)
  local roadY = number(second.pos.y, 0) - number(first.pos.y, 0)
  local roadSlope = (number(second.pos.z, 0) - number(first.pos.z, 0)) /
    math.max(1, length2(roadX, roadY))
  local roadLength = length2(roadX, roadY)
  if roadLength < 1 then return nil, "roadUnavailable" end
  roadX, roadY = roadX / roadLength, roadY / roadLength
  if type(vehicle.getDirectionVector) ~= "function" then return nil, "directionUnavailable" end
  local direction = vehicle:getDirectionVector()
  local directionLength = length2(number(direction.x, 0), number(direction.y, 0))
  if directionLength < 0.1 then return nil, "directionUnavailable" end
  local forwardX, forwardY = number(direction.x, 0) / directionLength,
    number(direction.y, 0) / directionLength
  local baseNode = first
  if roadX * forwardX + roadY * forwardY < 0 then
    roadX, roadY, roadSlope = -roadX, -roadY, -roadSlope
    baseNode = second
  end
  local baseX, baseY = number(baseNode.pos.x, 0), number(baseNode.pos.y, 0)
  local along = math.max(0, math.min(roadLength,
    (number(position.x, 0) - baseX) * roadX + (number(position.y, 0) - baseY) * roadY))
  local centerX, centerY = baseX + roadX * along, baseY + roadY * along
  local roadLeftX, roadLeftY = -roadY, roadX
  return {
    position = {x = number(position.x, 0), y = number(position.y, 0), z = number(position.z, 0)},
    forwardX = forwardX, forwardY = forwardY,
    leftX = -forwardY, leftY = forwardX,
    roadLeftX = roadLeftX, roadLeftY = roadLeftY,
    roadAlignment = (-forwardY) * roadLeftX + forwardX * roadLeftY,
    roadSlope = roadSlope,
    roadLateral = (number(position.x, 0) - centerX) * roadLeftX +
      (number(position.y, 0) - centerY) * roadLeftY,
    halfWidth = math.min(number(first.radius, 0), number(second.radius, 0)),
    oneWay = link.oneWay == true
  }
end

local function closestStationaryObstacle(vehicle, context, preferredId, scanDistance)
  if not map or type(map.objects) ~= "table" then return nil end
  local ownId = type(vehicle.getID) == "function" and vehicle:getID() or nil
  local best
  for id, data in pairs(map.objects) do
    if id ~= ownId and data and data.pos and (preferredId == nil or id == preferredId) then
      local dx = number(data.pos.x, 0) - context.position.x
      local dy = number(data.pos.y, 0) - context.position.y
      local longitudinal = dx * context.forwardX + dy * context.forwardY
      local lateral = dx * context.leftX + dy * context.leftY
      local object = vehicleObject(id)
      local combinedHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5 +
        dimension(object, "getInitialWidth", 2) * 0.5 + 0.8
      if longitudinal > 0 and longitudinal <= scanDistance and math.abs(lateral) <= combinedHalfWidth and
        math.abs(velocity(data, context.forwardX, context.forwardY)) <= 1.5 then
        if not best or longitudinal < best.longitudinal then
          local physicalLength = dimension(object, "getInitialLength", 4.5)
          local physicalWidth = dimension(object, "getInitialWidth", 2)
          local objectDirection = data.dirVec or data.dir
          if not objectDirection and object and type(object.getDirectionVector) == "function" then
            local ok, value = pcall(object.getDirectionVector, object)
            if ok then objectDirection = value end
          end
          local objectDirectionLength = length2(number(objectDirection and objectDirection.x, 1),
            number(objectDirection and objectDirection.y, 0))
          local objectForwardX = number(objectDirection and objectDirection.x, 1) / math.max(0.001, objectDirectionLength)
          local objectForwardY = number(objectDirection and objectDirection.y, 0) / math.max(0.001, objectDirectionLength)
          local forwardAlignment = math.abs(objectForwardX * context.forwardX +
            objectForwardY * context.forwardY)
          local sideAlignment = math.abs(-objectForwardY * context.forwardX +
            objectForwardX * context.forwardY)
          best = {
            id = id, data = data, object = object, longitudinal = longitudinal, lateral = lateral,
            length = physicalLength * forwardAlignment + physicalWidth * sideAlignment,
            width = physicalWidth * forwardAlignment + physicalLength * sideAlignment
          }
        end
      end
    end
  end
  if not best and preferredId ~= nil then
    return closestStationaryObstacle(vehicle, context, nil, scanDistance)
  end
  return best
end

local function localLateralAt(x, entryEnd, exitStart, exitEnd, offset)
  if x <= entryEnd then return offset * smoothStep(x / math.max(0.1, entryEnd)) end
  if x <= exitStart then return offset end
  return offset * (1 - smoothStep((x - exitStart) / math.max(0.1, exitEnd - exitStart)))
end

local function corridorIsClear(vehicle, context, obstacle, candidate, config)
  local ownId = type(vehicle.getID) == "function" and vehicle:getID() or nil
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local speed = math.max(3, number(config.bypassControllerSpeed, 7))
  for x = 1.5, candidate.exitEnd, 1.5 do
    local pathY = localLateralAt(x, candidate.entryEnd, candidate.exitStart,
      candidate.exitEnd, candidate.offset)
    local roadY = context.roadLateral + pathY * context.roadAlignment
    if math.abs(roadY) + ownHalfWidth + 0.25 > context.halfWidth then return false, "roadBoundary" end
    for id, data in pairs(type(map.objects) == "table" and map.objects or {}) do
      if id ~= ownId and data and data.pos then
        local dx = number(data.pos.x, 0) - context.position.x
        local dy = number(data.pos.y, 0) - context.position.y
        local object = id == obstacle.id and obstacle.object or vehicleObject(id)
        local objectLength = dimension(object, "getInitialLength", 4.5)
        local objectWidth = dimension(object, "getInitialWidth", 2)
        local time = x / speed
        local projectedX = dx * context.forwardX + dy * context.forwardY +
          velocity(data, context.forwardX, context.forwardY) * time
        local projectedY = dx * context.leftX + dy * context.leftY
        local longitudinalClearance = ownHalfLength + objectLength * 0.5 + 0.6
        local lateralClearance = ownHalfWidth + objectWidth * 0.5 + 0.45
        if math.abs(projectedX - x) < longitudinalClearance and
          math.abs(projectedY - pathY) < lateralClearance then
          return false, id == obstacle.id and "insufficientClearance" or "trafficConflict"
        end
      end
    end
  end
  return true
end

local function buildCandidate(vehicle, context, obstacle, side, config)
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local required = ownHalfWidth + obstacle.width * 0.5 + number(config.bypassClearance, 0.7)
  local offset = obstacle.lateral + side * required
  local obstacleRear = obstacle.longitudinal - obstacle.length * 0.5
  local obstacleFront = obstacle.longitudinal + obstacle.length * 0.5
  local entryEnd = obstacleRear - ownHalfLength - 0.7
  if entryEnd < math.max(3.5, math.abs(offset) * 1.15) then return nil, "tooClose" end
  local exitStart = obstacleFront + ownHalfLength + 0.8
  local exitEnd = exitStart + math.max(7, math.abs(offset) * 2)
  local candidate = {offset = offset, entryEnd = entryEnd, exitStart = exitStart, exitEnd = exitEnd}
  local clear, reason = corridorIsClear(vehicle, context, obstacle, candidate, config)
  if not clear then return nil, reason end
  return candidate
end

function M.new(sourceConfig)
  local config = sourceConfig or {}
  local service = {}

  function service:planLocalBypass(vehicle, preferredObstacleId)
    if not vehicle then return nil, "vehicleUnavailable" end
    local context, contextReason = roadContext(vehicle)
    if not context then return nil, contextReason end
    if context.halfWidth < dimension(vehicle, "getInitialWidth", 2) + 0.8 then
      return nil, "roadTooNarrow"
    end
    local obstacle = closestStationaryObstacle(vehicle, context, preferredObstacleId,
      number(config.followScanDistance, 160))
    if not obstacle then return nil, "noStationaryObstacle" end

    local candidates, lastReason = {}
    for _, side in ipairs({1, -1}) do
      local candidate, reason = buildCandidate(vehicle, context, obstacle, side, config)
      if candidate then candidates[#candidates + 1] = candidate else lastReason = reason end
    end
    if #candidates == 0 then return nil, lastReason or "noSafeCorridor" end
    table.sort(candidates, function(first, second) return math.abs(first.offset) < math.abs(second.offset) end)
    local chosen = candidates[1]
    local sampleX = {math.min(2, chosen.entryEnd * 0.35), chosen.entryEnd * 0.55,
      chosen.entryEnd, (chosen.entryEnd + chosen.exitStart) * 0.5,
      chosen.exitStart, chosen.exitStart + (chosen.exitEnd - chosen.exitStart) * 0.5, chosen.exitEnd}
    local points = {}
    for _, x in ipairs(sampleX) do
      local y = localLateralAt(x, chosen.entryEnd, chosen.exitStart, chosen.exitEnd, chosen.offset)
      points[#points + 1] = {
        x = context.position.x + context.forwardX * x + context.leftX * y,
        y = context.position.y + context.forwardY * x + context.leftY * y,
        z = context.position.z + context.roadSlope * x
      }
    end
    return {
      points = points,
      signal = chosen.offset > 0 and -1 or 1,
      obstacleId = obstacle.id,
      offset = chosen.offset,
      distance = chosen.exitEnd
    }
  end

  return service
end

return M
