local M = {}

local function number(value, fallback)
  value = tonumber(value)
  return value ~= nil and value or fallback
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function length2(x, y)
  return math.sqrt(x * x + y * y)
end

local function smoothStep(value)
  value = clamp(value, 0, 1)
  return value * value * (3 - 2 * value)
end

local function angleBetween(y, x)
  if type(math.atan2) == "function" then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi * 0.5 end
  if y < 0 then return -math.pi * 0.5 end
  return 0
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

local function callVector(object, method)
  if not object or type(object[method]) ~= "function" then return nil end
  local ok, value = pcall(object[method], object)
  return ok and value or nil
end

local function objectId(object)
  if not object then return nil end
  for _, method in ipairs({"getID", "getId"}) do
    if type(object[method]) == "function" then
      local ok, value = pcall(object[method], object)
      if ok and value ~= nil then return value end
    end
  end
  return nil
end

local function objectCenter(object)
  if not object or type(object.getSpawnWorldOOBB) ~= "function" then return nil end
  local ok, box = pcall(object.getSpawnWorldOOBB, object)
  if not ok or not box or type(box.getCenter) ~= "function" then return nil end
  local centerOk, center = pcall(box.getCenter, box)
  return centerOk and center or nil
end

local function sceneVehicleSources()
  local sources = {}
  for id, data in pairs(map and type(map.objects) == "table" and map.objects or {}) do
    sources[tostring(id)] = {id = id, data = data, object = vehicleObject(id)}
  end

  -- Non-street parked vehicles deliberately disable mapmgr tracking in
  -- BeamNG's parking system. They therefore disappear from map.objects even
  -- though their physics object remains in the world. getAllVehicles() is the
  -- authoritative GE list and must supplement, rather than replace, map data.
  if type(getAllVehicles) == "function" then
    local ok, vehicles = pcall(getAllVehicles)
    if ok and type(vehicles) == "table" then
      for _, object in ipairs(vehicles) do
        local id = objectId(object)
        if id ~= nil then
          local key = tostring(id)
          local source = sources[key] or {id = id, data = {}}
          source.object = object
          sources[key] = source
        end
      end
    end
  end
  return sources
end

local function unit3(x, y, z, fallbackX, fallbackY, fallbackZ)
  local length = math.sqrt(x * x + y * y + z * z)
  if length < 0.001 then return fallbackX or 1, fallbackY or 0, fallbackZ or 0 end
  return x / length, y / length, z / length
end

local function contextFor(vehicle)
  if not vehicle or type(vehicle.getPosition) ~= "function" or
    type(vehicle.getDirectionVector) ~= "function" then return nil, "vehicleUnavailable" end
  local position = vehicle:getPosition()
  local direction = vehicle:getDirectionVector()
  local directionX, directionY, directionZ = unit3(number(direction.x, 0),
    number(direction.y, 0), number(direction.z, 0), 1, 0, 0)
  local directionLength = length2(directionX, directionY)
  if directionLength < 0.1 then return nil, "directionUnavailable" end
  local forwardX, forwardY = directionX / directionLength, directionY / directionLength
  local rawUp = type(vehicle.getDirectionVectorUp) == "function" and
    vehicle:getDirectionVectorUp() or {x = 0, y = 0, z = 1}
  local upX, upY, upZ = unit3(number(rawUp.x, 0), number(rawUp.y, 0),
    number(rawUp.z, 1), 0, 0, 1)
  local leftX, leftY, leftZ = unit3(
    upY * directionZ - upZ * directionY,
    upZ * directionX - upX * directionZ,
    upX * directionY - upY * directionX, -forwardY, forwardX, 0)
  upX, upY, upZ = unit3(
    directionY * leftZ - directionZ * leftY,
    directionZ * leftX - directionX * leftZ,
    directionX * leftY - directionY * leftX, 0, 0, 1)
  local context = {
    position = {x = number(position.x, 0), y = number(position.y, 0), z = number(position.z, 0)},
    forwardX = forwardX, forwardY = forwardY,
    leftX = -forwardY, leftY = forwardX,
    sensorForwardX = directionX, sensorForwardY = directionY, sensorForwardZ = directionZ,
    sensorLeftX = leftX, sensorLeftY = leftY, sensorLeftZ = leftZ,
    sensorUpX = upX, sensorUpY = upY, sensorUpZ = upZ,
    roadAvailable = false, roadAlignment = 1, roadLateral = 0,
    halfWidth = math.huge, roadSlope = 0
  }

  if not map or type(map.getMap) ~= "function" or type(map.findClosestRoad) ~= "function" then
    return context
  end
  local nodeA, nodeB = map.findClosestRoad(position)
  local mapData = map.getMap()
  local nodes = mapData and mapData.nodes
  local first, second = nodes and nodes[nodeA], nodes and nodes[nodeB]
  local link = first and second and ((first.links and first.links[nodeB]) or
    (second.links and second.links[nodeA])) or nil
  if not first or not second or not first.pos or not second.pos then return context end
  local roadX = number(second.pos.x, 0) - number(first.pos.x, 0)
  local roadY = number(second.pos.y, 0) - number(first.pos.y, 0)
  local roadLength = length2(roadX, roadY)
  if roadLength < 1 then return context end
  local roadSlope = (number(second.pos.z, 0) - number(first.pos.z, 0)) / roadLength
  roadX, roadY = roadX / roadLength, roadY / roadLength
  local baseNode = first
  if roadX * forwardX + roadY * forwardY < 0 then
    roadX, roadY, roadSlope, baseNode = -roadX, -roadY, -roadSlope, second
  end
  local baseX, baseY = number(baseNode.pos.x, 0), number(baseNode.pos.y, 0)
  local along = clamp((context.position.x - baseX) * roadX +
    (context.position.y - baseY) * roadY, 0, roadLength)
  local centerX, centerY = baseX + roadX * along, baseY + roadY * along
  local roadLeftX, roadLeftY = -roadY, roadX
  context.roadAvailable = true
  context.roadAlignment = context.leftX * roadLeftX + context.leftY * roadLeftY
  context.roadLateral = (context.position.x - centerX) * roadLeftX +
    (context.position.y - centerY) * roadLeftY
  context.halfWidth = math.max(2, math.min(number(first.radius, 4), number(second.radius, 4)))
  context.roadSlope = roadSlope
  context.oneWay = link and link.oneWay == true or false
  return context
end

local function localPoint(context, longitudinal, lateral)
  return {
    x = context.position.x + context.forwardX * longitudinal + context.leftX * lateral,
    y = context.position.y + context.forwardY * longitudinal + context.leftY * lateral,
    z = context.position.z + context.roadSlope * longitudinal
  }
end

local function localLateralAt(x, entryEnd, exitStart, exitEnd, offset, rejoinOffset)
  if x <= entryEnd then
    return offset * smoothStep(x / math.max(0.1, entryEnd))
  end
  if x <= exitStart then return offset end
  local blend = smoothStep((x - exitStart) / math.max(0.1, exitEnd - exitStart))
  return offset + (rejoinOffset - offset) * blend
end

local function nearbyObjects(vehicle, context, range)
  local result = {}
  local ownId = type(vehicle.getID) == "function" and vehicle:getID() or nil
  for _, source in pairs(sceneVehicleSources()) do
    local id, object = source.id, source.object
    local mapData = type(source.data) == "table" and source.data or {}
    local position = objectCenter(object) or mapData.pos or callVector(object, "getPosition")
    if tostring(id) ~= tostring(ownId) and position and
      (not object or object.taxiDriverIgnoreObstacle ~= true) then
      local data = {
        pos = position,
        vel = mapData.vel or callVector(object, "getVelocity"),
        dirVec = mapData.dirVec or mapData.dir or callVector(object, "getDirectionVector")
      }
      local dx = number(position.x, 0) - context.position.x
      local dy = number(position.y, 0) - context.position.y
      local longitudinal = dx * context.forwardX + dy * context.forwardY
      local lateral = dx * context.leftX + dy * context.leftY
      if dx * dx + dy * dy <= range * range then
        local objectDirection = data.dirVec or data.dir
        if not objectDirection and object and type(object.getDirectionVector) == "function" then
          local ok, value = pcall(object.getDirectionVector, object)
          if ok then objectDirection = value end
        end
        local objectDirectionLength = length2(number(objectDirection and objectDirection.x, 1),
          number(objectDirection and objectDirection.y, 0))
        local objectForwardX = number(objectDirection and objectDirection.x, 1) /
          math.max(0.001, objectDirectionLength)
        local objectForwardY = number(objectDirection and objectDirection.y, 0) /
          math.max(0.001, objectDirectionLength)
        local forwardAlignment = math.abs(objectForwardX * context.forwardX +
          objectForwardY * context.forwardY)
        local sideAlignment = math.abs(-objectForwardY * context.forwardX +
          objectForwardX * context.forwardY)
        local physicalLength = dimension(object, "getInitialLength", 4.5)
        local physicalWidth = dimension(object, "getInitialWidth", 2)
        result[#result + 1] = {
          id = id, data = data, object = object,
          longitudinal = longitudinal, lateral = lateral,
          length = physicalLength * forwardAlignment + physicalWidth * sideAlignment,
          width = physicalWidth * forwardAlignment + physicalLength * sideAlignment,
          speed = velocity(data, context.forwardX, context.forwardY)
        }
      end
    end
  end
  return result
end

local function raySphereDistance(origin, directionX, directionY, directionZ, maximumDistance,
  center, radius)
  local dx, dy, dz = center.x - origin.x, center.y - origin.y, center.z - origin.z
  local projection = dx * directionX + dy * directionY + dz * directionZ
  if projection < 0 or projection > maximumDistance + radius then return nil end
  local perpendicularSquared = dx * dx + dy * dy + dz * dz - projection * projection
  if perpendicularSquared > radius * radius then return nil end
  local entry = projection - math.sqrt(math.max(0, radius * radius - perpendicularSquared))
  return clamp(entry, 0, maximumDistance)
end

local function staticRayDistance(context, origin, directionX, directionY, directionZ, maximumDistance)
  if type(castRayStatic) ~= "function" or type(vec3) ~= "function" then return maximumDistance end
  local liftX, liftY, liftZ = 0, 0, 0.65
  if context then
    liftX, liftY, liftZ = context.sensorUpX * 0.65,
      context.sensorUpY * 0.65, context.sensorUpZ * 0.65
  end
  local start = vec3(origin.x + liftX, origin.y + liftY, origin.z + liftZ)
  local direction = vec3(directionX, directionY, directionZ or 0)
  local ok, distance = pcall(castRayStatic, start, direction, maximumDistance)
  return ok and clamp(number(distance, maximumDistance), 0, maximumDistance) or maximumDistance
end

local function scanSpaceFan(vehicle, context, objects, maximumDistance, travelDirection)
  travelDirection = travelDirection == -1 and -1 or 1
  local ownLength = dimension(vehicle, "getInitialLength", 4.5)
  local ownWidth = dimension(vehicle, "getInitialWidth", 2)
  local forwardX, forwardY, forwardZ = context.sensorForwardX * travelDirection,
    context.sensorForwardY * travelDirection, context.sensorForwardZ * travelDirection
  local leftX, leftY, leftZ = context.sensorLeftX * travelDirection,
    context.sensorLeftY * travelDirection, context.sensorLeftZ * travelDirection
  local origin = {
    x = context.position.x + forwardX * ownLength * 0.45,
    y = context.position.y + forwardY * ownLength * 0.45,
    z = context.position.z + forwardZ * ownLength * 0.45
  }
  local rays = {}
  -- A complete forward/reverse hemisphere is intentional here. Narrow fans
  -- make an entrance disappear as soon as the nearest diagonal ray touches a
  -- fence, even though a viable path still exists directly beside the car.
  for index = -9, 9 do
    local angle = index * math.rad(10)
    local cosine, sine = math.cos(angle), math.sin(angle)
    local directionX = forwardX * cosine + leftX * sine
    local directionY = forwardY * cosine + leftY * sine
    local directionZ = forwardZ * cosine + leftZ * sine
    directionX, directionY, directionZ = unit3(directionX, directionY, directionZ, 1, 0, 0)
    local distance = maximumDistance
    local edge = ownWidth * 0.5 + 0.3
    for _, lateral in ipairs({-edge, -edge * 0.5, 0, edge * 0.5, edge}) do
      local shiftedOrigin = {x = origin.x + leftX * lateral,
        y = origin.y + leftY * lateral, z = origin.z + leftZ * lateral}
      distance = math.min(distance, staticRayDistance(context, shiftedOrigin,
        directionX, directionY, directionZ, maximumDistance))
    end
    local hitKind = distance < maximumDistance - 0.05 and "static" or nil
    for _, object in ipairs(objects) do
      local radius = math.sqrt((object.length * 0.5) ^ 2 +
        (object.width * 0.5 + ownWidth * 0.35) ^ 2)
      local center = {x = number(object.data and object.data.pos and object.data.pos.x, 0),
        y = number(object.data and object.data.pos and object.data.pos.y, 0),
        z = number(object.data and object.data.pos and object.data.pos.z, context.position.z)}
      local hit = raySphereDistance(origin, directionX, directionY, directionZ,
        distance, center, radius)
      if hit and hit < distance then distance, hitKind = hit, "vehicle" end
    end
    rays[#rays + 1] = {
      angle = angle, distance = distance, maximumDistance = maximumDistance,
      blocked = distance < maximumDistance - 0.05, hitKind = hitKind,
      start = origin, travelDirection = travelDirection,
      finish = {x = origin.x + directionX * distance,
        y = origin.y + directionY * distance, z = origin.z + directionZ * distance}
    }
  end
  return rays
end

local function closestObstacle(vehicle, context, objects, preferredId, scanDistance, rays)
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local best
  for _, object in ipairs(objects) do
    if preferredId == nil or tonumber(object.id) == tonumber(preferredId) then
      local corridor = ownHalfWidth + object.width * 0.5 + 0.8
      if object.longitudinal > 0 and object.longitudinal <= scanDistance and
        math.abs(object.lateral) <= corridor and math.abs(object.speed) <= 1.5 and
        (not best or object.longitudinal < best.longitudinal) then best = object end
    end
  end
  if not best and preferredId ~= nil then
    return closestObstacle(vehicle, context, objects, nil, scanDistance, rays)
  end
  if best then return best end

  local centerRay = rays and rays[math.floor(#rays * 0.5) + 1]
  if centerRay and centerRay.blocked and centerRay.distance <= scanDistance then
    return {
      id = "static", data = nil, object = nil, speed = 0,
      longitudinal = dimension(vehicle, "getInitialLength", 4.5) * 0.45 + centerRay.distance,
      lateral = 0, length = 1.2,
      width = math.max(2.4, dimension(vehicle, "getInitialWidth", 2) * 1.2)
    }
  end
  return nil
end

local function buildPoints(context, candidate, step)
  local points = {}
  for x = math.min(2, candidate.entryEnd * 0.35), candidate.exitEnd, step or 2 do
    local lateral = localLateralAt(x, candidate.entryEnd, candidate.exitStart,
      candidate.exitEnd, candidate.offset, candidate.rejoinOffset)
    points[#points + 1] = localPoint(context, x, lateral)
  end
  local finalLateral = localLateralAt(candidate.exitEnd, candidate.entryEnd,
    candidate.exitStart, candidate.exitEnd, candidate.offset, candidate.rejoinOffset)
  local finalPoint = localPoint(context, candidate.exitEnd, finalLateral)
  if #points == 0 or length2(finalPoint.x - points[#points].x,
    finalPoint.y - points[#points].y) > 0.25 then points[#points + 1] = finalPoint end
  return points
end

local function groundHeight(point)
  if type(castRayStatic) ~= "function" or type(vec3) ~= "function" then return point.z, false end
  local lift, depth = 3, 9
  local origin = vec3(point.x, point.y, point.z + lift)
  local ok, distance = pcall(castRayStatic, origin, vec3(0, 0, -1), depth)
  distance = ok and number(distance, depth) or depth
  if distance >= depth - 0.05 then return nil, true end
  return point.z + lift - distance, true
end

local function evaluateSurface(vehicle, points)
  local height = dimension(vehicle, "getInitialHeight", 1.55)
  local width = dimension(vehicle, "getInitialWidth", 2)
  -- BeamNG does not expose suspension travel to GE Lua for every vehicle. The
  -- body height gives a conservative proxy: low cars reject normal kerbs while
  -- SUVs and off-road vehicles may use a climbable pavement or shoulder.
  local climbableStep = clamp(height * 0.115, 0.12, 0.28)
  local maximumGrade = math.rad(clamp(16 + (height - 1.2) * 7, 16, 25))
  local maximumCrossSlope = math.rad(clamp(11 + (height - 1.2) * 5, 11, 18))
  local previous, risk, sampled = nil, 0, false
  local surfaceSamples = {}
  for index, point in ipairs(points) do
    local centerHeight, available = groundHeight(point)
    sampled = sampled or available
    if available and centerHeight == nil then return false, "unsupportedSurface", risk, surfaceSamples end
    if centerHeight then
      point.z = centerHeight
      local sample = {x = point.x, y = point.y, z = centerHeight, risk = 0}
      if previous then
        local horizontal = math.max(0.1, length2(point.x - previous.x, point.y - previous.y))
        local rise = centerHeight - previous.z
        local grade = math.abs(math.atan(rise / horizontal))
        local stepRisk = math.abs(rise) / math.max(0.01, climbableStep)
        if math.abs(rise) > climbableStep and horizontal <= 2.1 then
          return false, "stepTooHigh", risk + stepRisk, surfaceSamples
        end
        if grade > maximumGrade then return false, "slopeTooSteep", risk + grade, surfaceSamples end
        sample.risk = math.max(sample.risk, stepRisk * 0.7, grade / maximumGrade * 0.45)
      end
      if available and type(vec3) == "function" then
        local tangentX, tangentY = 1, 0
        if previous then
          local tangentLength = math.max(0.001, length2(point.x - previous.x, point.y - previous.y))
          tangentX, tangentY = (point.x - previous.x) / tangentLength,
            (point.y - previous.y) / tangentLength
        elseif points[index + 1] then
          local tangentLength = math.max(0.001,
            length2(points[index + 1].x - point.x, points[index + 1].y - point.y))
          tangentX, tangentY = (points[index + 1].x - point.x) / tangentLength,
            (points[index + 1].y - point.y) / tangentLength
        end
        local leftX, leftY = -tangentY, tangentX
        local halfProbe = width * 0.38
        local leftHeight = groundHeight({x = point.x + leftX * halfProbe,
          y = point.y + leftY * halfProbe, z = centerHeight})
        local rightHeight = groundHeight({x = point.x - leftX * halfProbe,
          y = point.y - leftY * halfProbe, z = centerHeight})
        if leftHeight and rightHeight then
          local crossSlope = math.abs(math.atan((leftHeight - rightHeight) /
            math.max(0.1, halfProbe * 2)))
          if crossSlope > maximumCrossSlope then
            return false, "crossSlopeTooSteep", risk + crossSlope, surfaceSamples
          end
          sample.risk = math.max(sample.risk, crossSlope / maximumCrossSlope * 0.55)
        end
      end
      risk = risk + sample.risk
      surfaceSamples[#surfaceSamples + 1] = sample
      previous = {x = point.x, y = point.y, z = centerHeight}
    end
  end
  return true, sampled and "surfaceClear" or "surfaceUnknown", risk, surfaceSamples
end

local function pathStaticClear(vehicle, points, context)
  if type(castRayStatic) ~= "function" or type(vec3) ~= "function" then return true, math.huge end
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local minimumClearance = math.huge
  for index = 1, #points - 1 do
    local first, second = points[index], points[index + 1]
    local dx, dy = second.x - first.x, second.y - first.y
    local length = length2(dx, dy)
    if length > 0.05 then
      local dz = second.z - first.z
      local directionX, directionY, directionZ = unit3(dx, dy, dz, dx / length, dy / length, 0)
      local rayLength = math.sqrt(dx * dx + dy * dy + dz * dz)
      local leftX, leftY = -directionY, directionX
      local edge = ownHalfWidth + 0.3
      for _, lateral in ipairs({-edge, -edge * 0.5, 0, edge * 0.5, edge}) do
        local origin = {x = first.x + leftX * lateral, y = first.y + leftY * lateral, z = first.z}
        local clearance = staticRayDistance(context, origin, directionX, directionY,
          directionZ, rayLength)
        minimumClearance = math.min(minimumClearance, clearance)
        if clearance < rayLength - 0.18 then return false, clearance end
      end
    end
  end
  return true, minimumClearance
end

local function evaluateCandidate(vehicle, context, obstacle, objects, candidate, config)
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local speed = math.max(3, number(config.bypassControllerSpeed, 7))
  local minimumClearance, roadOutside, curvatureCost = math.huge, 0, 0
  local previousLateral = 0
  local points = buildPoints(context, candidate, 1.5)
  for index, point in ipairs(points) do
    local x = (point.x - context.position.x) * context.forwardX +
      (point.y - context.position.y) * context.forwardY
    local pathY = (point.x - context.position.x) * context.leftX +
      (point.y - context.position.y) * context.leftY
    local roadY = context.roadLateral + pathY * context.roadAlignment
    if context.roadAvailable then
      roadOutside = roadOutside + math.max(0, math.abs(roadY) + ownHalfWidth - context.halfWidth)
    end
    if index > 1 then curvatureCost = curvatureCost + math.abs(pathY - previousLateral) end
    previousLateral = pathY
    for _, object in ipairs(objects) do
      local projectedX = object.longitudinal + object.speed * (x / speed)
      local longitudinalClearance = ownHalfLength + object.length * 0.5 + 0.65
      local lateralClearance = ownHalfWidth + object.width * 0.5 + 0.5
      local separationX = math.abs(projectedX - x) - longitudinalClearance
      local separationY = math.abs(object.lateral - pathY) - lateralClearance
      if separationX < 0 and separationY < 0 then
        candidate.points, candidate.reason = points,
          object.id == obstacle.id and "insufficientClearance" or "trafficConflict"
        candidate.minimumClearance = math.min(-separationX, -separationY)
        return false
      end
      local clearance = math.sqrt(math.max(0, separationX) ^ 2 + math.max(0, separationY) ^ 2)
      minimumClearance = math.min(minimumClearance, clearance)
    end
  end
  local surfaceClear, surfaceReason, surfaceRisk, surfaceSamples = evaluateSurface(vehicle, points)
  candidate.surfaceRisk, candidate.surfaceSamples = surfaceRisk, surfaceSamples
  if not surfaceClear then
    candidate.points, candidate.reason, candidate.minimumClearance = points, surfaceReason, 0
    return false
  end
  local staticClear, staticClearance = pathStaticClear(vehicle, points, context)
  if not staticClear then
    candidate.points, candidate.reason, candidate.minimumClearance = points, "staticObstacle", staticClearance
    return false
  end
  candidate.points = points
  candidate.minimumClearance = minimumClearance == math.huge and 25 or minimumClearance
  candidate.roadOutside = roadOutside
  candidate.score = 100 + math.min(20, candidate.minimumClearance * 2.5) -
    math.abs(candidate.offset) * 1.6 - curvatureCost * 0.45 - roadOutside * 2.5 -
    math.abs(candidate.rejoinOffset) * 0.7 - number(surfaceRisk, 0) * 3.5
  candidate.reason = "clear"
  return true
end

local function buildCandidate(vehicle, context, obstacle, side, extraClearance, config)
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local required = ownHalfWidth + obstacle.width * 0.5 +
    number(config.bypassClearance, 0.7) + extraClearance
  local offset = obstacle.lateral + side * required
  local obstacleRear = obstacle.longitudinal - obstacle.length * 0.5
  local obstacleFront = obstacle.longitudinal + obstacle.length * 0.5
  local entryEnd = obstacleRear - ownHalfLength - 0.65
  local minimumEntry = math.max(3.5, math.abs(offset) * 0.9)
  if entryEnd < minimumEntry then
    return {offset = offset, reason = "tooClose", points = {}, feasible = false}
  end
  local exitStart = obstacleFront + ownHalfLength + 1
  local exitEnd = exitStart + math.max(8, math.abs(offset) * 1.7)
  local rejoinOffset = 0
  if context.roadAvailable and math.abs(context.roadAlignment) > 0.25 then
    rejoinOffset = clamp(-context.roadLateral / context.roadAlignment, -3.5, 3.5)
  end
  return {
    side = side, offset = offset, rejoinOffset = rejoinOffset,
    entryEnd = entryEnd, exitStart = exitStart, exitEnd = exitEnd,
    reason = "pending", feasible = false
  }
end

local function buildApproachPoints(context, endpoint, lateralOffset)
  local dx, dy = endpoint.x - context.position.x, endpoint.y - context.position.y
  local distance = math.max(0.01, length2(dx, dy))
  local directionX, directionY = dx / distance, dy / distance
  local leftX, leftY = -directionY, directionX
  local count = math.max(3, math.ceil(distance / 1.25))
  local points = {}
  for index = 0, count do
    local t = index / count
    local bow = math.sin(math.pi * t) * lateralOffset
    points[#points + 1] = {
      x = context.position.x + dx * t + leftX * bow,
      y = context.position.y + dy * t + leftY * bow,
      z = context.position.z + (number(endpoint.z, context.position.z) - context.position.z) * t
    }
  end
  return points
end

local function evaluateApproachCandidate(vehicle, context, objects, candidate)
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local ownHalfWidth = dimension(vehicle, "getInitialWidth", 2) * 0.5
  local minimumClearance, pathLength = math.huge, 0
  for index, point in ipairs(candidate.points) do
    local localX = (point.x - context.position.x) * context.forwardX +
      (point.y - context.position.y) * context.forwardY
    local localY = (point.x - context.position.x) * context.leftX +
      (point.y - context.position.y) * context.leftY
    if index > 1 then
      local previous = candidate.points[index - 1]
      pathLength = pathLength + length2(point.x - previous.x, point.y - previous.y)
    end
    for _, object in ipairs(objects) do
      local separationX = math.abs(object.longitudinal - localX) -
        (ownHalfLength + object.length * 0.5 + 0.35)
      local separationY = math.abs(object.lateral - localY) -
        (ownHalfWidth + object.width * 0.5 + 0.35)
      if separationX < 0 and separationY < 0 then
        candidate.reason, candidate.minimumClearance = "trafficConflict", 0
        return false
      end
      minimumClearance = math.min(minimumClearance,
        math.sqrt(math.max(0, separationX) ^ 2 + math.max(0, separationY) ^ 2))
    end
  end
  local surfaceClear, surfaceReason, surfaceRisk, surfaceSamples =
    evaluateSurface(vehicle, candidate.points)
  candidate.surfaceRisk, candidate.surfaceSamples = surfaceRisk, surfaceSamples
  if not surfaceClear then candidate.reason, candidate.minimumClearance = surfaceReason, 0; return false end
  local staticClear, staticClearance = pathStaticClear(vehicle, candidate.points, context)
  if not staticClear then
    candidate.reason, candidate.minimumClearance = "staticObstacle", staticClearance
    return false
  end
  candidate.minimumClearance = minimumClearance == math.huge and 25 or minimumClearance
  candidate.pathLength = pathLength
  candidate.score = 220 - candidate.targetError * 42 - math.abs(candidate.offset) * 1.8 -
    pathLength * 0.12 + math.min(18, candidate.minimumClearance * 2.2) - number(surfaceRisk, 0) * 3
  candidate.reason = "clear"
  return true
end

local function approachEndpoints(context, target)
  local endpoints = {{x = target.x, y = target.y, z = target.z, targetError = 0}}
  local towardX, towardY = context.position.x - target.x, context.position.y - target.y
  local towardLength = math.max(0.001, length2(towardX, towardY))
  local baseAngle = angleBetween(towardY, towardX)
  for _, radius in ipairs({0.8, 1.5, 2.5, 3.5, 4.75, 6}) do
    for index = 0, 7 do
      local angle = baseAngle + index * math.pi * 0.25
      endpoints[#endpoints + 1] = {x = target.x + math.cos(angle) * radius,
        y = target.y + math.sin(angle) * radius, z = target.z, targetError = radius}
    end
  end
  return endpoints
end

local function chooseLocalApproach(vehicle, context, target, objects, sink, exactOnly)
  local feasible = {}
  for endpointIndex, endpoint in ipairs(approachEndpoints(context, target)) do
    if exactOnly and endpointIndex > 1 then break end
    if endpointIndex == 2 and #feasible > 0 then break end
    for _, offset in ipairs({0, 1.5, -1.5, 3, -3, 4.5, -4.5}) do
      if endpointIndex == 1 or math.abs(offset) <= 3 then
        local candidate = {endpoint = endpoint, targetError = endpoint.targetError,
          offset = offset, points = buildApproachPoints(context, endpoint, offset)}
        candidate.feasible = evaluateApproachCandidate(vehicle, context, objects, candidate)
        if sink then sink[#sink + 1] = candidate end
        if candidate.feasible then feasible[#feasible + 1] = candidate end
      end
    end
  end
  if #feasible == 0 then return nil end
  table.sort(feasible, function(first, second) return first.score > second.score end)
  return feasible[1]
end

local function contextAt(base, position, direction)
  local forwardX, forwardY, forwardZ = unit3(number(direction and direction.x, 1),
    number(direction and direction.y, 0), number(direction and direction.z, 0), 1, 0, 0)
  local planarLength = math.max(0.001, length2(forwardX, forwardY))
  local leftX, leftY, leftZ = unit3(-forwardY, forwardX, 0, 0, 1, 0)
  return {
    position = {x = number(position.x, 0), y = number(position.y, 0), z = number(position.z, 0)},
    forwardX = forwardX / planarLength, forwardY = forwardY / planarLength,
    leftX = -forwardY / planarLength, leftY = forwardX / planarLength,
    sensorForwardX = forwardX, sensorForwardY = forwardY, sensorForwardZ = forwardZ,
    sensorLeftX = leftX, sensorLeftY = leftY, sensorLeftZ = leftZ,
    sensorUpX = base.sensorUpX, sensorUpY = base.sensorUpY, sensorUpZ = base.sensorUpZ,
    roadAvailable = false, roadAlignment = 1, roadLateral = 0,
    halfWidth = math.huge, roadSlope = forwardZ / planarLength
  }
end

local function accessEdges(target, radius)
  local mapData = map and type(map.getMap) == "function" and map.getMap() or nil
  local nodes = mapData and mapData.nodes
  if not nodes then return {}, nodes end
  local result, seen = {}, {}
  for nodeA, node in pairs(nodes) do
    for nodeB, link in pairs(node.links or {}) do
      local firstKey, secondKey = tostring(nodeA), tostring(nodeB)
      local key = firstKey < secondKey and firstKey .. "\0" .. secondKey or secondKey .. "\0" .. firstKey
      local second = nodes[nodeB]
      if not seen[key] and second and node.pos and second.pos and number(link.drivability, 1) > 0.05 then
        seen[key] = true
        local dx, dy, dz = number(second.pos.x, 0) - number(node.pos.x, 0),
          number(second.pos.y, 0) - number(node.pos.y, 0),
          number(second.pos.z, 0) - number(node.pos.z, 0)
        local lengthSquared = dx * dx + dy * dy + dz * dz
        if lengthSquared > 1 then
          local t = clamp(((number(target.x, 0) - number(node.pos.x, 0)) * dx +
            (number(target.y, 0) - number(node.pos.y, 0)) * dy +
            (number(target.z, 0) - number(node.pos.z, 0)) * dz) / lengthSquared, 0, 1)
          local position = {x = number(node.pos.x, 0) + dx * t,
            y = number(node.pos.y, 0) + dy * t, z = number(node.pos.z, 0) + dz * t}
          local tx, ty = position.x - number(target.x, 0), position.y - number(target.y, 0)
          local distance = length2(tx, ty)
          if distance >= 3 and distance <= radius then
            result[#result + 1] = {nodeA = nodeA, nodeB = nodeB, position = position,
              direction = {x = dx, y = dy, z = dz}, targetDistance = distance, link = link}
          end
        end
      end
    end
  end
  -- Do not discard a road just because another edge in the same angular
  -- sector lies closer to the target. Entrances separated by a fence often
  -- share a sector, while only the farther one is actually reachable.
  table.sort(result, function(first, second) return first.targetDistance < second.targetDistance end)
  return result, nodes
end

local function projectOnPolyline(point, polyline)
  local best, progress = nil, 0
  for index = 1, #(polyline or {}) - 1 do
    local first, second = polyline[index], polyline[index + 1]
    local dx, dy = number(second.x, 0) - number(first.x, 0),
      number(second.y, 0) - number(first.y, 0)
    local lengthSquared = dx * dx + dy * dy
    local length = math.sqrt(lengthSquared)
    if length > 0.05 then
      local t = clamp(((number(point.x, 0) - number(first.x, 0)) * dx +
        (number(point.y, 0) - number(first.y, 0)) * dy) / lengthSquared, 0, 1)
      local px, py = number(first.x, 0) + dx * t, number(first.y, 0) + dy * t
      local crossTrack = length2(number(point.x, 0) - px, number(point.y, 0) - py)
      local candidate = {progress = progress + length * t, crossTrack = crossTrack}
      if not best or candidate.crossTrack < best.crossTrack then best = candidate end
      progress = progress + length
    end
  end
  return best
end

local function referenceAlignment(points, reference)
  if type(reference) ~= "table" or #reference < 2 then return true, 0 end
  local traveled, lastProgress, penalty = 0, 0, 0
  for index = 2, #points do
    traveled = traveled + length2(number(points[index].x, 0) - number(points[index - 1].x, 0),
      number(points[index].y, 0) - number(points[index - 1].y, 0))
    if traveled <= 48 then
      local projection = projectOnPolyline(points[index], reference)
      if not projection then return false, math.huge end
      -- The graph may leave the reference near an entrance, but it must not
      -- first run backwards along the road or jump across an unrelated edge.
      local allowedCrossTrack = traveled <= 24 and 10 or 16
      if projection.crossTrack > allowedCrossTrack or
        projection.progress + 5 < lastProgress then return false, math.huge end
      lastProgress = math.max(lastProgress, projection.progress)
      penalty = penalty + projection.crossTrack * 0.12
    end
  end
  if traveled >= 12 and lastProgress < math.min(10, traveled * 0.35) then
    return false, math.huge
  end
  return true, penalty
end

local function densifyPolyline(points, spacing)
  if type(points) ~= "table" or #points < 2 then return points end
  spacing = math.max(2, number(spacing, 4))
  local result = {{x = number(points[1].x, 0), y = number(points[1].y, 0),
    z = number(points[1].z, 0)}}
  for index = 1, #points - 1 do
    local first, second = points[index], points[index + 1]
    local distance = length2(number(second.x, 0) - number(first.x, 0),
      number(second.y, 0) - number(first.y, 0))
    local steps = math.max(1, math.ceil(distance / spacing))
    for step = 1, steps do
      local t = step / steps
      result[#result + 1] = {
        x = number(first.x, 0) + (number(second.x, 0) - number(first.x, 0)) * t,
        y = number(first.y, 0) + (number(second.y, 0) - number(first.y, 0)) * t,
        z = number(first.z, 0) + (number(second.z, 0) - number(first.z, 0)) * t
      }
    end
  end
  return result
end

local function smoothDriveablePolyline(points, turningRadius, spacing)
  if type(points) ~= "table" or #points < 3 then return densifyPolyline(points, spacing) end
  turningRadius, spacing = math.max(4, number(turningRadius, 6)), math.max(1.5, number(spacing, 2.5))
  local cleaned = {}
  for _, point in ipairs(points) do
    local previous = cleaned[#cleaned]
    if not previous or length2(number(point.x, 0) - previous.x,
      number(point.y, 0) - previous.y) > 0.2 then
      cleaned[#cleaned + 1] = {x = number(point.x, 0), y = number(point.y, 0),
        z = number(point.z, 0)}
    end
  end
  if #cleaned < 3 then return densifyPolyline(cleaned, spacing) end
  local result = {cleaned[1]}
  local function append(point)
    local previous = result[#result]
    if not previous or length2(point.x - previous.x, point.y - previous.y) > 0.08 then
      result[#result + 1] = point
    end
  end
  for index = 2, #cleaned - 1 do
    local previous, corner, following = cleaned[index - 1], cleaned[index], cleaned[index + 1]
    local inX, inY = corner.x - previous.x, corner.y - previous.y
    local outX, outY = following.x - corner.x, following.y - corner.y
    local inLength, outLength = length2(inX, inY), length2(outX, outY)
    if inLength < 0.5 or outLength < 0.5 then
      append(corner)
    else
      inX, inY, outX, outY = inX / inLength, inY / inLength, outX / outLength, outY / outLength
      local angle = math.acos(clamp(inX * outX + inY * outY, -1, 1))
      if angle < 0.1 then
        append(corner)
      else
        local trim = math.min(inLength * 0.42, outLength * 0.42,
          turningRadius * 1.35 * math.min(2, math.tan(angle * 0.5)))
        local entry = {x = corner.x - inX * trim, y = corner.y - inY * trim,
          z = corner.z + (previous.z - corner.z) * (trim / inLength)}
        local exit = {x = corner.x + outX * trim, y = corner.y + outY * trim,
          z = corner.z + (following.z - corner.z) * (trim / outLength)}
        append(entry)
        local samples = math.max(2, math.ceil(trim * 2 / spacing))
        for sample = 1, samples do
          local t, inverse = sample / samples, 1 - sample / samples
          append({x = inverse * inverse * entry.x + 2 * inverse * t * corner.x + t * t * exit.x,
            y = inverse * inverse * entry.y + 2 * inverse * t * corner.y + t * t * exit.y,
            z = inverse * inverse * entry.z + 2 * inverse * t * corner.z + t * t * exit.z})
        end
      end
    end
  end
  append(cleaned[#cleaned])
  return densifyPolyline(result, spacing)
end

local function buildForwardArc(context, radius, angle, spacing)
  local points = {}
  local arcLength = math.abs(radius * angle)
  local steps = math.max(4, math.ceil(arcLength / math.max(1.4, spacing or 2)))
  local side = angle >= 0 and 1 or -1
  for index = 0, steps do
    local currentAngle = math.abs(angle) * index / steps
    points[#points + 1] = localPoint(context,
      math.sin(currentAngle) * radius,
      side * radius * (1 - math.cos(currentAngle)))
  end
  return points
end

local function routeForwardTurn(vehicle, context, objects, referencePoints)
  if type(referencePoints) ~= "table" or #referencePoints < 2 then return nil end
  local anchor
  for index = 2, #referencePoints do
    local point = referencePoints[index]
    local dx, dy = number(point.x, 0) - context.position.x,
      number(point.y, 0) - context.position.y
    local distance = length2(dx, dy)
    if distance >= 12 then
      anchor = point
      if distance >= 24 then break end
    end
  end
  if not anchor then return nil end

  local anchorX, anchorY = number(anchor.x, 0) - context.position.x,
    number(anchor.y, 0) - context.position.y
  local localX = anchorX * context.forwardX + anchorY * context.forwardY
  local localY = anchorX * context.leftX + anchorY * context.leftY
  local desiredAngle = angleBetween(localY, localX)
  if math.abs(desiredAngle) < math.rad(12) then return nil end

  local ownLength = dimension(vehicle, "getInitialLength", 4.5)
  local minimumRadius = clamp(ownLength * 1.15, 4.8, 8)
  local signs = desiredAngle >= 0 and {1} or {-1}
  if math.abs(desiredAngle) > math.rad(155) then signs = {1, -1} end
  local magnitudes = {
    clamp(math.abs(desiredAngle) - math.rad(18), math.rad(18), math.rad(168)),
    clamp(math.abs(desiredAngle), math.rad(18), math.rad(168)),
    clamp(math.abs(desiredAngle) + math.rad(18), math.rad(18), math.rad(168))
  }
  local best, candidateCount = nil, 0
  for _, side in ipairs(signs) do
    for _, radius in ipairs({minimumRadius, minimumRadius * 1.45}) do
      for _, magnitude in ipairs(magnitudes) do
        candidateCount = candidateCount + 1
        local points = buildForwardArc(context, radius, magnitude * side, 1.8)
        local candidate = {points = points, targetError = 0, offset = 0}
        if evaluateApproachCandidate(vehicle, context, objects, candidate) then
          local endpoint = points[#points]
          local endpointError = length2(endpoint.x - number(anchor.x, 0),
            endpoint.y - number(anchor.y, 0))
          local endpointAngle = magnitude * side
          local angleError = math.abs(endpointAngle - desiredAngle)
          local aligned, alignmentPenalty = referenceAlignment(points, referencePoints)
          if aligned then
            candidate.score = 170 - endpointError * 1.25 - angleError * 9 -
              alignmentPenalty + math.min(12, number(candidate.minimumClearance, 0))
            candidate.signal = side > 0 and -1 or 1
            candidate.strategy = "routeForwardTurn"
            candidate.radius = radius
            candidate.turnAngle = endpointAngle
            candidate.candidateCount = candidateCount
            if not best or candidate.score > best.score then best = candidate end
          end
        end
      end
    end
  end
  if best then best.candidateCount = candidateCount end
  return best
end

local function graphPoints(vehicle, edge, nodes, pathCache, referencePoints)
  if not map or type(map.findClosestRoad) ~= "function" or type(map.getGraphpath) ~= "function" then return nil end
  local graph = map.getGraphpath()
  if not graph or type(graph.getPath) ~= "function" then return nil end
  local position, direction = vehicle:getPosition(), vehicle:getDirectionVector()
  local startA, startB = map.findClosestRoad(position)
  local best
  for _, startNode in ipairs({startA, startB}) do
    for _, endNode in ipairs({edge.nodeA, edge.nodeB}) do
      if startNode and endNode and nodes[startNode] and nodes[endNode] then
        local pathKey = tostring(startNode) .. "\0" .. tostring(endNode)
        local ids = pathCache and pathCache[pathKey] or nil
        local ok = ids ~= false
        if ids == nil then
          ok, ids = pcall(graph.getPath, graph, startNode, endNode)
          if pathCache then pathCache[pathKey] = ok and ids or false end
        end
        if ok and type(ids) == "table" then
          local route, routeLength, previous = {}, 0, position
          if #ids == 0 and startNode == endNode then ids = {startNode} end
          for _, id in ipairs(ids) do
            local node = nodes[id]
            if node and node.pos then
              local point = {x = number(node.pos.x, 0), y = number(node.pos.y, 0), z = number(node.pos.z, 0)}
              routeLength, previous = routeLength + length2(point.x - previous.x, point.y - previous.y), point
              route[#route + 1] = point
            end
          end
          if #route > 0 then
            routeLength = routeLength + length2(edge.position.x - previous.x, edge.position.y - previous.y)
            route[#route + 1] = {x = edge.position.x, y = edge.position.y, z = edge.position.z}
            local heading = 0
            for _, point in ipairs(route) do
              local px, py = point.x - number(position.x, 0), point.y - number(position.y, 0)
              if length2(px, py) > 4 then
                heading = px * number(direction.x, 1) + py * number(direction.y, 0)
                break
              end
            end
            if routeLength <= 160 and heading >= -1 then
              -- Start at the actual vehicle position and omit a graph-centre
              -- point that is only a few metres sideways. Steering directly
              -- at that point caused a full-lock turn into the road boundary.
              local usable = {{x = number(position.x, 0), y = number(position.y, 0),
                z = number(position.z, 0)}}
              for _, point in ipairs(route) do
                local px, py = point.x - number(position.x, 0), point.y - number(position.y, 0)
                local pointDistance = length2(px, py)
                local forwardDistance = px * number(direction.x, 1) + py * number(direction.y, 0)
                if pointDistance > 6 or forwardDistance > 2 then usable[#usable + 1] = point end
              end
              if #usable == 1 then usable[#usable + 1] = route[#route] end
              local aligned, alignmentPenalty = referenceAlignment(usable, referencePoints)
              local selectionScore = routeLength + alignmentPenalty
              if aligned and (not best or selectionScore < best.score) then
                best = {points = smoothDriveablePolyline(usable,
                    clamp(dimension(vehicle, "getInitialLength", 4.5) * 1.3, 5, 8), 2.5),
                  length = routeLength,
                  score = selectionScore, alignmentPenalty = alignmentPenalty,
                  startNode = startNode, endNode = endNode}
              end
            end
          end
        end
      end
    end
  end
  return best
end

local function segmentPoints(first, second, step)
  local distance = length2(second.x - first.x, second.y - first.y)
  local count, result = math.max(1, math.ceil(distance / (step or 1.8))), {}
  for index = 0, count do
    local t = index / count
    result[#result + 1] = {x = first.x + (second.x - first.x) * t,
      y = first.y + (second.y - first.y) * t,
      z = number(first.z, 0) + (number(second.z, 0) - number(first.z, 0)) * t}
  end
  return result
end

local function spatialGraphBypass(vehicle, context, obstacle, objects)
  -- This is a last-resort local planner. Keep the graph deliberately small:
  -- the old 168-node/600-iteration graph performed thousands of synchronous
  -- terrain rays in one game tick and could visibly stall the simulation.
  local directionCount, rings = 12, {6, 13, 22, 32}
  local nodes, ringNodes = {{point = {x = context.position.x, y = context.position.y,
    z = context.position.z}, localX = 0, localY = 0, ring = 0, angleIndex = 0}}, {}
  for ringIndex, radius in ipairs(rings) do
    ringNodes[ringIndex] = {}
    for angleIndex = 0, directionCount - 1 do
      local angle = angleIndex * math.pi * 2 / directionCount
      local localX, localY = math.cos(angle) * radius, math.sin(angle) * radius
      local node = {point = localPoint(context, localX, localY), localX = localX,
        localY = localY, ring = ringIndex, angleIndex = angleIndex, state = "untested"}
      nodes[#nodes + 1], ringNodes[ringIndex][angleIndex] = node, #nodes + 1
    end
  end
  local ownHalfLength = dimension(vehicle, "getInitialLength", 4.5) * 0.5
  local goalDistance = clamp(obstacle.longitudinal + obstacle.length * 0.5 + ownHalfLength + 8, 14, 30)
  local rejoin = context.roadAvailable and math.abs(context.roadAlignment) > 0.25 and
    clamp(-context.roadLateral / context.roadAlignment, -5, 5) or 0
  local goalPoint = localPoint(context, goalDistance, rejoin)
  local goals = {}
  for index, node in ipairs(nodes) do
    if index > 1 and node.localX >= goalDistance - 3 and math.abs(node.localY - rejoin) <= 7 then
      goals[index] = true
    end
  end
  local function neighbors(index)
    if index == 1 then
      local result = {}
      for angleIndex = 0, directionCount - 1 do
        local angle = angleIndex * math.pi * 2 / directionCount
        if math.cos(angle) >= -0.05 then result[#result + 1] = ringNodes[1][angleIndex] end
      end
      return result
    end
    local node, result = nodes[index], {}
    local function add(ring, angle)
      if ringNodes[ring] then result[#result + 1] = ringNodes[ring][angle % directionCount] end
    end
    add(node.ring, node.angleIndex - 1); add(node.ring, node.angleIndex + 1)
    for _, ring in ipairs({node.ring - 1, node.ring + 1}) do
      for delta = -1, 1 do add(ring, node.angleIndex + delta) end
    end
    if node.ring == 1 then result[#result + 1] = 1 end
    return result
  end
  local edgeCache = {}
  local function edgeClear(firstIndex, secondIndex)
    local low, high = math.min(firstIndex, secondIndex), math.max(firstIndex, secondIndex)
    local key = low .. ":" .. high
    if edgeCache[key] ~= nil then return edgeCache[key] end
    local candidate = {points = segmentPoints(nodes[firstIndex].point, nodes[secondIndex].point),
      targetError = 0, offset = 0}
    edgeCache[key] = evaluateApproachCandidate(vehicle, context, objects, candidate)
    nodes[secondIndex].state = edgeCache[key] and "clear" or nodes[secondIndex].state
    return edgeCache[key]
  end
  local open, g, parent = {[1] = true}, {[1] = 0}, {}
  local reached, iterations = nil, 0
  while next(open) and iterations < 140 do
    iterations = iterations + 1
    local current, currentScore
    for index in pairs(open) do
      local node = nodes[index]
      local heuristic = length2(goalPoint.x - node.point.x, goalPoint.y - node.point.y)
      local score = g[index] + heuristic
      if not currentScore or score < currentScore then current, currentScore = index, score end
    end
    open[current] = nil
    if goals[current] then reached = current; break end
    local currentNode = nodes[current]
    for _, nextIndex in ipairs(neighbors(current)) do
      local nextNode = nextIndex and nodes[nextIndex]
      if nextNode and nextNode.localX >= -1.5 and edgeClear(current, nextIndex) then
        local edgeLength = length2(nextNode.point.x - currentNode.point.x,
          nextNode.point.y - currentNode.point.y)
        local backward = nextNode.localX < currentNode.localX - 0.5 and edgeLength * 4 or 0
        local tentative = g[current] + edgeLength + backward + math.abs(nextNode.localY) * 0.015
        if g[nextIndex] == nil or tentative < g[nextIndex] then
          g[nextIndex], parent[nextIndex], open[nextIndex] = tentative, current, true
        end
      end
    end
  end
  if not reached then return nil, nodes end
  local indices, cursor = {}, reached
  while cursor do table.insert(indices, 1, cursor); cursor = parent[cursor] end
  local path = {}
  for pairIndex = 1, #indices - 1 do
    local segment = segmentPoints(nodes[indices[pairIndex]].point, nodes[indices[pairIndex + 1]].point, 2)
    for pointIndex = pairIndex == 1 and 1 or 2, #segment do path[#path + 1] = segment[pointIndex] end
  end
  local last = path[#path]
  local finalCandidate = {points = segmentPoints(last, goalPoint, 2), targetError = 0, offset = 0}
  if evaluateApproachCandidate(vehicle, context, objects, finalCandidate) then
    for index = 2, #finalCandidate.points do path[#path + 1] = finalCandidate.points[index] end
  end
  local smoothed = smoothDriveablePolyline(path,
    clamp(dimension(vehicle, "getInitialLength", 4.5) * 1.3, 5, 8), 2.2)
  local smoothedCandidate = {points = smoothed, targetError = 0, offset = 0}
  if evaluateApproachCandidate(vehicle, context, objects, smoothedCandidate) then path = smoothed end
  for _, index in ipairs(indices) do nodes[index].state = "path" end
  return {points = path, signal = nodes[indices[2]] and nodes[indices[2]].localY < 0 and 1 or -1,
    obstacleId = obstacle.id, offset = nodes[reached].localY, distance = goalDistance,
    score = 180 - g[reached], minimumClearance = 0, roadOutside = 0,
    strategy = "spatialGraph", graphCost = g[reached], graphNodeCount = #indices}, nodes
end

function M.new(sourceConfig)
  local config = sourceConfig or {}
  local service = {}
  local debugEnabled = false
  local debugTimer = 0
  local snapshot = {rays = {}, candidates = {}, reason = "idle"}
  local approachTarget = nil
  local accessCacheKey, accessCacheEdges, accessCacheNodes = nil, nil, nil

  local function assess(vehicle, preferredObstacleId, options)
    if not vehicle then return nil, "vehicleUnavailable" end
    local context, contextReason = contextFor(vehicle)
    if not context then return nil, contextReason end
    local scanDistance = number(config.followScanDistance, 160)
    local planningDistance = clamp(number(config.freeSpacePlanningDistance, 42), 24, 70)
    local objects = nearbyObjects(vehicle, context, math.min(scanDistance, planningDistance + 20))
    local rays = scanSpaceFan(vehicle, context, objects, planningDistance)
    local obstacle = closestObstacle(vehicle, context, objects, preferredObstacleId,
      math.min(scanDistance, planningDistance), rays)
    local current = {context = context, rays = rays, candidates = {}, obstacle = obstacle,
      reason = obstacle and "evaluating" or "noStationaryObstacle"}
    snapshot = current
    local routeTurn = routeForwardTurn(vehicle, context, objects,
      type(options) == "table" and options.referencePoints or nil)
    if routeTurn then
      routeTurn.obstacleId = obstacle and obstacle.id or nil
      routeTurn.distance = length2(routeTurn.points[#routeTurn.points].x - context.position.x,
        routeTurn.points[#routeTurn.points].y - context.position.y)
      routeTurn.feasible = true
      current.candidates[#current.candidates + 1] = routeTurn
    end
    if not obstacle then
      if routeTurn then
        routeTurn.chosen, current.chosen = true, routeTurn
        current.reason = "routeForwardTurn"
        return routeTurn
      end
      return nil, current.reason
    end
    local candidates = {}
    for _, side in ipairs({1, -1}) do
      for _, extra in ipairs({0, 1.25, 2.5}) do
        local candidate = buildCandidate(vehicle, context, obstacle, side, extra, config)
        if candidate.reason ~= "tooClose" then
          candidate.feasible = evaluateCandidate(vehicle, context, obstacle, objects, candidate, config)
        end
        current.candidates[#current.candidates + 1] = candidate
        if candidate.feasible then candidates[#candidates + 1] = candidate end
      end
    end
    local graphPlan, graphNodes
    if type(options) == "table" and options.allowSpatialGraph == true and
      #candidates == 0 and not routeTurn then
      graphPlan, graphNodes = spatialGraphBypass(vehicle, context, obstacle, objects)
      current.graphNodes = graphNodes
    end
    if graphPlan then
      graphPlan.feasible = true
      current.candidates[#current.candidates + 1] = graphPlan
    end
    if #candidates == 0 and not graphPlan and not routeTurn then
      current.reason = "noSafeCorridor"
      return nil, current.reason
    end
    table.sort(candidates, function(first, second) return first.score > second.score end)
    local chosen = candidates[1]
    if routeTurn and (not chosen or routeTurn.score > chosen.score) then chosen = routeTurn end
    if graphPlan and (not chosen or graphPlan.score > chosen.score) then chosen = graphPlan end
    chosen.chosen = true
    current.chosen = chosen
    current.reason = chosen.strategy == "spatialGraph" and "spatialGraphPath" or
      (chosen.strategy == "routeForwardTurn" and "routeForwardTurn" or "freeSpacePath")
    if chosen.strategy == "spatialGraph" or chosen.strategy == "routeForwardTurn" then return chosen end
    return {
      points = chosen.points,
      signal = chosen.offset > 0 and -1 or 1,
      obstacleId = obstacle.id,
      offset = chosen.offset,
      distance = chosen.exitEnd,
      score = chosen.score,
      minimumClearance = chosen.minimumClearance,
      roadOutside = chosen.roadOutside,
      strategy = "freeSpace"
    }
  end

  local function planApproach(vehicle, target, options)
    if not vehicle or not target then return nil, "targetUnavailable" end
    local context, reason = contextFor(vehicle)
    if not context then return nil, reason end
    local distance = length2(number(target.x, 0) - context.position.x,
      number(target.y, 0) - context.position.y)
    local objects = nearbyObjects(vehicle, context, math.max(18, distance + 10))
    local targetDot = (number(target.x, 0) - context.position.x) * context.sensorForwardX +
      (number(target.y, 0) - context.position.y) * context.sensorForwardY
    local rays = scanSpaceFan(vehicle, context, objects, math.min(48, math.max(12, distance)),
      targetDot < 0 and -1 or 1)
    local current = {context = context, rays = rays, candidates = {}, target = target,
      reason = "freeSpaceApproachPlanning"}
    local chosen = chooseLocalApproach(vehicle, context, target, objects, current.candidates)
    local graphChosen
    local preferGraph = type(options) == "table" and options.preferGraph == true
    local targetBehind = targetDot < -math.max(2, distance * 0.12)
    if preferGraph or not chosen or chosen.targetError > 0.1 or targetBehind then
      local level = ""
      if type(getCurrentLevelIdentifier) == "function" then
        local ok, value = pcall(getCurrentLevelIdentifier)
        if ok then level = tostring(value or "") end
      end
      local cacheKey = string.format("%s:%d:%d", level,
        math.floor(number(target.x, 0) / 2), math.floor(number(target.y, 0) / 2))
      if cacheKey ~= accessCacheKey then
        accessCacheEdges, accessCacheNodes = accessEdges(target,
          clamp(number(config.approachAccessRadius, 75), 40, 110))
        accessCacheKey = cacheKey
      end
      local edges, nodes = accessCacheEdges or {}, accessCacheNodes
      local pathCache = {}
      current.graphEdgeCount = #edges
      current.graphFeasibleCount = 0
      local routeCandidates = {}
      for _, edge in ipairs(edges) do
        local route = graphPoints(vehicle, edge, nodes, pathCache,
          type(options) == "table" and options.referencePoints or nil)
        if route then
          routeCandidates[#routeCandidates + 1] = {edge = edge, route = route,
            lowerBound = route.length + edge.targetDistance}
        end
      end
      table.sort(routeCandidates, function(first, second)
        return first.lowerBound < second.lowerBound
      end)
      current.graphRouteCount = #routeCandidates
      for _, routeCandidate in ipairs(routeCandidates) do
        -- Suffix length cannot be shorter than the straight distance from its
        -- access edge to the target. Once this bound exceeds the best complete
        -- route, all remaining graph turns are provably longer.
        if graphChosen and routeCandidate.lowerBound > graphChosen.routeCost + 0.75 then break end
        local edge, route = routeCandidate.edge, routeCandidate.route
          local last, previous = route.points[#route.points], route.points[#route.points - 1]
          local accessDirection = previous and {x = last.x - previous.x, y = last.y - previous.y,
            z = last.z - previous.z} or edge.direction
          local accessContext = contextAt(context, last, accessDirection)
          local accessObjects = nearbyObjects(vehicle, accessContext, math.max(18, edge.targetDistance + 10))
          local suffix = chooseLocalApproach(vehicle, accessContext, target, accessObjects, nil, true)
          if suffix then
            local combined = {}
            for _, point in ipairs(route.points) do combined[#combined + 1] = point end
            for index = 2, #suffix.points do combined[#combined + 1] = suffix.points[index] end
            combined = smoothDriveablePolyline(combined,
              clamp(dimension(vehicle, "getInitialLength", 4.5) * 1.3, 5, 8), 2.2)
            local candidate = {points = combined, endpoint = suffix.endpoint,
              targetError = suffix.targetError, minimumClearance = suffix.minimumClearance,
              offset = suffix.offset, pathLength = route.length + suffix.pathLength,
              graphLength = route.length, graphAssisted = true, feasible = true,
              reason = "graphAccess", score = suffix.score - route.length * 0.18,
              routeCost = route.length + suffix.pathLength,
              startNode = route.startNode, endNode = route.endNode,
              accessNodeA = edge.nodeA, accessNodeB = edge.nodeB}
            current.candidates[#current.candidates + 1] = candidate
            current.graphFeasibleCount = current.graphFeasibleCount + 1
            -- The complete drivable route is the primary criterion. Clearance
            -- and local-path quality only break near ties; they must not make a
            -- 95 m detour beat a feasible 68 m road path.
            if not graphChosen or candidate.routeCost < graphChosen.routeCost - 0.75 or
              (math.abs(candidate.routeCost - graphChosen.routeCost) <= 0.75 and
                candidate.score > graphChosen.score) then graphChosen = candidate end
          end
      end
    end
    if graphChosen and (preferGraph or not chosen or graphChosen.targetError < chosen.targetError - 0.1 or
      (targetBehind and graphChosen.targetError <= chosen.targetError + 0.1)) then chosen = graphChosen end
    if not chosen then snapshot = current; current.reason = "noReachablePoint"; return nil, current.reason end
    chosen.chosen, current.chosen = true, chosen
    current.reason = chosen.graphAssisted and "graphAccessApproach" or "freeSpaceApproach"
    snapshot = current
    return {points = chosen.points, endpoint = chosen.endpoint,
      targetError = chosen.targetError, minimumClearance = chosen.minimumClearance,
      completionRadius = chosen.targetError == 0 and 0.8 or 0.7,
      strategy = chosen.graphAssisted and "graphAccessApproach" or "freeSpaceApproach",
      graphAssisted = chosen.graphAssisted == true, graphLength = chosen.graphLength,
      pathLength = chosen.pathLength, routeCost = chosen.routeCost,
      startNode = chosen.startNode, endNode = chosen.endNode,
      accessNodeA = chosen.accessNodeA, accessNodeB = chosen.accessNodeB,
      graphEdgeCount = current.graphEdgeCount,
      graphRouteCount = current.graphRouteCount,
      graphFeasibleCount = current.graphFeasibleCount, score = chosen.score}
  end

  function service:planLocalBypass(vehicle, preferredObstacleId, options)
    approachTarget = nil
    return assess(vehicle, preferredObstacleId, options)
  end

  function service:planPointApproach(vehicle, target, options)
    approachTarget = target and {x = number(target.x, 0), y = number(target.y, 0),
      z = number(target.z, 0)} or nil
    return planApproach(vehicle, approachTarget, options)
  end

  function service:clearPointApproach()
    approachTarget = nil
  end

  function service:setDebugEnabled(value)
    debugEnabled = value == true
    debugTimer = 0
    if not debugEnabled then snapshot = {rays = {}, candidates = {}, reason = "disabled"} end
  end

  function service:updateDebug(vehicle, preferredObstacleId, dt, travelDirection, passive)
    if not debugEnabled or not vehicle then return end
    debugTimer = debugTimer - math.max(0, number(dt, 0))
    if debugTimer <= 0 then
      -- Draw every frame from a cached snapshot, but reassess at roughly a
      -- human reaction interval instead of tying expensive terrain rays to FPS.
      debugTimer = 0.33
      if passive == true then
        local context = contextFor(vehicle)
        if context then
          local distance = math.min(32, clamp(number(config.freeSpacePlanningDistance, 42), 24, 70))
          local objects = nearbyObjects(vehicle, context, distance + 10)
          snapshot = {context = context,
            rays = scanSpaceFan(vehicle, context, objects, distance, travelDirection),
            candidates = {}, reason = "signalWait"}
        end
      elseif approachTarget then
        local context = contextFor(vehicle)
        if context then
          local dx, dy = approachTarget.x - context.position.x, approachTarget.y - context.position.y
          local distance = length2(dx, dy)
          local objects = nearbyObjects(vehicle, context, math.max(18, distance + 10))
          local targetDot = dx * context.sensorForwardX + dy * context.sensorForwardY
          snapshot.context = context
          snapshot.rays = scanSpaceFan(vehicle, context, objects,
            math.min(48, math.max(12, distance)), targetDot < 0 and -1 or 1)
        end
      elseif travelDirection == -1 then
        local context = contextFor(vehicle)
        if context then
          local distance = clamp(number(config.freeSpacePlanningDistance, 42), 24, 70)
          local objects = nearbyObjects(vehicle, context, distance + 10)
          snapshot = {context = context, rays = scanSpaceFan(vehicle, context, objects, distance, -1),
            candidates = {}, reason = "reverseSpace"}
        end
      else assess(vehicle, preferredObstacleId) end
    end
  end

  function service:getDebugSnapshot()
    return snapshot
  end

  function service:drawDebug()
    if not debugEnabled or not debugDrawer or not ColorF or not ColorI or
      type(vec3) ~= "function" then return end
    local function finite(value)
      return type(value) == "number" and value == value and math.abs(value) < 1000000
    end
    local function point(value, lift)
      if type(value) ~= "table" then return nil end
      local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
      if not finite(x) or not finite(y) or not finite(z) then return nil end
      return vec3(x, y, z + (lift or 0))
    end
    local function drawLine(first, second, color)
      first, second = point(first, 0.5), point(second, 0.5)
      if first and second then debugDrawer:drawLine(first, second, color, false) end
    end
    local function drawSphere(value, lift, radius, color)
      value = point(value, lift)
      if value then debugDrawer:drawSphere(value, radius, color) end
    end
    for _, ray in ipairs(snapshot.rays or {}) do
      local color = ray.blocked and ColorF(1, 0.18, 0.12, 0.8) or ColorF(0.12, 0.72, 1, 0.42)
      drawLine(ray.start, ray.finish, color)
      drawSphere(ray.finish, 0.35, ray.blocked and 0.18 or 0.1, color)
    end
    for index, node in ipairs(snapshot.graphNodes or {}) do
      if node.state == "path" or index % 12 == 1 then
        local color = node.state == "path" and ColorF(0.15, 1, 0.35, 0.9) or
          (node.state == "clear" and ColorF(0.1, 0.65, 1, 0.28) or ColorF(0.55, 0.6, 0.68, 0.16))
        drawSphere(node.point, 0.28, node.state == "path" and 0.2 or 0.08, color)
      end
    end
    for candidateIndex, candidate in ipairs(snapshot.candidates or {}) do
      local drawCandidate = candidate.chosen or candidateIndex % 16 == 1
      local color = candidate.chosen and ColorF(0.15, 1, 0.35, 1) or
        (candidate.feasible and ColorF(1, 0.72, 0.08, 0.68) or ColorF(1, 0.12, 0.2, 0.5))
      if drawCandidate then
        for index = 1, #(candidate.points or {}) - 1 do
          drawLine(candidate.points[index], candidate.points[index + 1], color)
        end
        for index, waypoint in ipairs(candidate.points or {}) do
          if candidate.chosen or index % 2 == 0 then
            drawSphere(waypoint, 0.5, candidate.chosen and 0.28 or 0.14, color)
          end
        end
        for _, sample in ipairs(candidate.surfaceSamples or {}) do
          if number(sample.risk, 0) > 0.35 then
            local surfaceColor = number(sample.risk, 0) > 0.8 and
              ColorF(0.95, 0.1, 0.85, 0.9) or ColorF(0.7, 0.25, 1, 0.75)
            drawSphere(sample, 0.7, 0.2, surfaceColor)
          end
        end
      end
    end
    if snapshot.obstacle then
      local obstaclePoint = localPoint(snapshot.context, snapshot.obstacle.longitudinal,
        snapshot.obstacle.lateral)
      drawSphere(obstaclePoint, 0.7,
        math.max(0.5, number(snapshot.obstacle.width, 2) * 0.5), ColorF(1, 0.08, 0.08, 0.35))
      local chosen = snapshot.chosen
      local label = chosen and string.format("TaxiDriver AI: FREE SPACE  score %.1f  clearance %.1fm",
        number(chosen.score, 0), number(chosen.minimumClearance, 0)) or
        ("TaxiDriver AI: " .. tostring(snapshot.reason or "scanning"))
      local labelPoint = point(obstaclePoint, 2.1)
      if labelPoint then debugDrawer:drawTextAdvanced(labelPoint, label,
        ColorF(1, 1, 1, 1), true, false, ColorI(20, 24, 30, 220), false, false) end
    end
    if snapshot.target then
      local targetPoint = point(snapshot.target, 0.65)
      if targetPoint then debugDrawer:drawSphere(targetPoint, 0.34, ColorF(0.2, 0.7, 1, 0.95)) end
      local chosen = snapshot.chosen
      local label = chosen and string.format("TaxiDriver AI: POINT APPROACH  error %.1fm  clearance %.1fm",
        number(chosen.targetError, 0), number(chosen.minimumClearance, 0)) or
        ("TaxiDriver AI: " .. tostring(snapshot.reason or "point planning"))
      local labelPoint = point(snapshot.target, 1.8)
      if labelPoint then debugDrawer:drawTextAdvanced(labelPoint, label,
        ColorF(1, 1, 1, 1), true, false, ColorI(20, 24, 30, 220), false, false) end
    end
  end

  return service
end

return M
