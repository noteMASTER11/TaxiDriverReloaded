-- Persistent, map-scoped storage for complete dispatcher offers shown in UI.
--
-- BeamNG virtual paths under /settings resolve inside the active user folder,
-- including installations whose user folder was moved away from AppData.
local M = {}

local schemaVersion = 2
local cacheDirectory = "/settings/TaxiDriver/route_cache"
local maximumRoutes = 96

local function finiteNumber(value)
  value = tonumber(value)
  if value == nil or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end

local function trim(value, maximumLength)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return value:sub(1, maximumLength or 160)
end

local function filenamePart(value, fallback)
  value = trim(value, 96):lower()
  value = value:gsub("[^%w%-]+", "_"):gsub("_+", "_")
  value = value:gsub("^[_%-]+", ""):gsub("[_%-]+$", "")
  if value == "" then value = tostring(fallback or "map") end
  return value:sub(1, 64)
end

local function currentMapDescriptor()
  local mapId = trim(type(getCurrentLevelIdentifier) == "function" and
    getCurrentLevelIdentifier() or "", 128)
  if mapId == "" then mapId = "unknown" end

  local mapName = mapId
  if core_levels and type(core_levels.getLevelByName) == "function" then
    local ok, info = pcall(core_levels.getLevelByName, mapId)
    if ok and type(info) == "table" then
      local title = info.title
      if type(title) == "table" then title = title.txt or title.context end
      if type(title) == "string" and trim(title) ~= "" then mapName = trim(title, 128) end
    end
  end

  return {
    mapId = mapId,
    mapName = mapName,
    filePath = string.format(
      "%s/routes_%s_%s.json",
      cacheDirectory,
      filenamePart(mapName, mapId),
      filenamePart(mapId, "map")
    )
  }
end

local function defaultDocument(descriptor)
  return {
    schemaVersion = schemaVersion,
    mapId = descriptor.mapId,
    mapName = descriptor.mapName,
    updatedAt = 0,
    routes = {}
  }
end

local function ensureDirectory()
  if not FS then return false end
  local ok = pcall(function()
    if not FS:directoryExists("/settings/TaxiDriver") then
      FS:directoryCreate("/settings/TaxiDriver", true)
    end
    if not FS:directoryExists(cacheDirectory) then
      FS:directoryCreate(cacheDirectory, true)
    end
  end)
  return ok
end

local function readDocument(descriptor)
  local result = defaultDocument(descriptor)
  if not (FS and type(jsonReadFile) == "function") then return result, false end
  local exists = false
  local existsOk = pcall(function() exists = FS:fileExists(descriptor.filePath) end)
  if not existsOk or not exists then return result, false end

  local ok, source = pcall(jsonReadFile, descriptor.filePath)
  if not ok or type(source) ~= "table" then
    log("W", "taxiDriver.routeCache",
      "Unable to read route cache '" .. descriptor.filePath .. "': " .. tostring(source))
    return result, true
  end
  if trim(source.mapId, 128):lower() ~= descriptor.mapId:lower() then
    return result, true
  end

  -- Schema 1 contained road samples rather than complete dispatcher offers.
  -- It is intentionally migrated to an empty route history.
  if tonumber(source.schemaVersion) == 1 then return result, true end
  if tonumber(source.schemaVersion) ~= schemaVersion then return result, true end
  result.updatedAt = finiteNumber(source.updatedAt) or 0
  result.routes = type(source.routes) == "table" and source.routes or {}
  return result, true
end

local function writeDocument(document, descriptor)
  if type(jsonWriteFile) ~= "function" or not ensureDirectory() then return false end
  document.schemaVersion = schemaVersion
  document.mapId = descriptor.mapId
  document.mapName = descriptor.mapName
  document.updatedAt = os.time()
  local ok, writeResult = pcall(jsonWriteFile, descriptor.filePath, document, true)
  if not ok or writeResult == false then
    log("W", "taxiDriver.routeCache",
      "Unable to write route cache '" .. descriptor.filePath .. "': " ..
      tostring(writeResult))
    return false
  end
  return true
end

local function sanitizePoint(source, nodes)
  if type(source) ~= "table" then return nil end
  local nodeA = trim(source.nodeA, 160)
  local nodeB = trim(source.nodeB, 160)
  if nodeA == "" or nodeB == "" or nodeA == nodeB then return nil end
  if nodes and not (nodes[nodeA] and nodes[nodeB]) then return nil end

  local x, y, z = finiteNumber(source.x), finiteNumber(source.y), finiteNumber(source.z)
  local dirX, dirY, dirZ = finiteNumber(source.dirX), finiteNumber(source.dirY),
    finiteNumber(source.dirZ)
  if not (x and y and z and dirX and dirY and dirZ) then return nil end
  if math.abs(x) > 1000000 or math.abs(y) > 1000000 or math.abs(z) > 100000 then
    return nil
  end

  local result = {
    x = x, y = y, z = z,
    dirX = dirX, dirY = dirY, dirZ = dirZ,
    nodeA = nodeA, nodeB = nodeB,
    anchorKind = trim(source.anchorKind, 48) ~= "" and
      trim(source.anchorKind, 48) or "routeCache"
  }
  local routeDistance = finiteNumber(source.routeDistance)
  if routeDistance and routeDistance >= 0 then result.routeDistance = routeDistance end
  return result
end

function M.serializePoint(stop)
  local pos, dir = stop and stop.pos, stop and stop.dir
  if not (pos and dir) then return nil end
  return sanitizePoint({
    x = pos.x, y = pos.y, z = pos.z,
    dirX = dir.x, dirY = dir.y, dirZ = dir.z,
    nodeA = stop.nodeA, nodeB = stop.nodeB,
    anchorKind = stop.anchorKind,
    routeDistance = stop.routeDistance
  })
end

local function serializeOrigin(pos)
  if not pos then return nil end
  local x, y, z = finiteNumber(pos.x), finiteNumber(pos.y), finiteNumber(pos.z)
  if not (x and y and z) then return nil end
  return {x = x, y = y, z = z}
end

local function sanitizeOrigin(source)
  if type(source) ~= "table" then return nil end
  return serializeOrigin(source)
end

local function safeNumber(source, key, fallback)
  local value = finiteNumber(source[key])
  return value == nil and fallback or value
end

local function serializeOffer(offer, originPos)
  if type(offer) ~= "table" then return nil end
  local pickup = M.serializePoint(offer.pickup)
  local destination = M.serializePoint(offer.destination)
  if not (pickup and destination and pickup.routeDistance and
    destination.routeDistance) then return nil end

  local stops = {}
  for _, stop in ipairs(type(offer.stops) == "table" and offer.stops or {}) do
    local serialized = M.serializePoint(stop)
    if not (serialized and serialized.routeDistance) then return nil end
    stops[#stops + 1] = serialized
    if #stops >= 6 then break end
  end

  local rideDistance = finiteNumber(offer.rideDistance)
  if not rideDistance or rideDistance <= 0 then return nil end
  return {
    savedAt = os.time(),
    origin = serializeOrigin(originPos),
    passengerName = trim(offer.passengerName, 96),
    isDelivery = offer.isDelivery == true,
    cargoWeightKg = safeNumber(offer, "cargoWeightKg", 0),
    cargoWeightBonusRate = safeNumber(offer, "cargoWeightBonusRate", 0),
    cargoWeightBonusAmount = safeNumber(offer, "cargoWeightBonusAmount", 0),
    cargoDamagePercent = safeNumber(offer, "cargoDamagePercent", 0),
    passengerCalmness = safeNumber(offer, "passengerCalmness", 50),
    passengerInitialCalmness = safeNumber(offer, "passengerInitialCalmness", 50),
    pickup = pickup,
    destination = destination,
    stops = stops,
    isMultiStop = offer.isMultiStop == true,
    rideDistance = rideDistance,
    totalEtaMinutes = safeNumber(offer, "totalEtaMinutes", 0),
    baseFare = safeNumber(offer, "baseFare", 0),
    ratingAdjustedFare = safeNumber(offer, "ratingAdjustedFare", 0),
    ratingBonusRate = safeNumber(offer, "ratingBonusRate", 0),
    ratingBonusAmount = safeNumber(offer, "ratingBonusAmount", 0),
    estimatedFare = safeNumber(offer, "estimatedFare", 0),
    pickupWaitLimit = safeNumber(offer, "pickupWaitLimit", 0),
    isRush = offer.isRush == true,
    bonusPercent = safeNumber(offer, "bonusPercent", 0),
    bonusAmount = safeNumber(offer, "bonusAmount", 0),
    rushTimeLimit = safeNumber(offer, "rushTimeLimit", 0)
  }
end

local function sanitizeOffer(source)
  if type(source) ~= "table" then return nil end
  local pickup = sanitizePoint(source.pickup)
  local destination = sanitizePoint(source.destination)
  local rideDistance = finiteNumber(source.rideDistance)
  if not (pickup and destination and pickup.routeDistance and
    destination.routeDistance and rideDistance and rideDistance > 0) then
    return nil
  end

  local stops = {}
  for _, stop in ipairs(type(source.stops) == "table" and source.stops or {}) do
    local sanitized = sanitizePoint(stop)
    if not (sanitized and sanitized.routeDistance) then return nil end
    stops[#stops + 1] = sanitized
    if #stops >= 6 then break end
  end

  return {
    savedAt = safeNumber(source, "savedAt", 0),
    origin = sanitizeOrigin(source.origin),
    passengerName = trim(source.passengerName, 96),
    isDelivery = source.isDelivery == true,
    cargoWeightKg = safeNumber(source, "cargoWeightKg", 0),
    cargoWeightBonusRate = safeNumber(source, "cargoWeightBonusRate", 0),
    cargoWeightBonusAmount = safeNumber(source, "cargoWeightBonusAmount", 0),
    cargoDamagePercent = safeNumber(source, "cargoDamagePercent", 0),
    passengerCalmness = safeNumber(source, "passengerCalmness", 50),
    passengerInitialCalmness = safeNumber(source, "passengerInitialCalmness", 50),
    pickup = pickup,
    destination = destination,
    stops = stops,
    isMultiStop = source.isMultiStop == true and #stops > 0,
    rideDistance = rideDistance,
    totalEtaMinutes = safeNumber(source, "totalEtaMinutes", 0),
    baseFare = safeNumber(source, "baseFare", 0),
    ratingAdjustedFare = safeNumber(source, "ratingAdjustedFare", 0),
    ratingBonusRate = safeNumber(source, "ratingBonusRate", 0),
    ratingBonusAmount = safeNumber(source, "ratingBonusAmount", 0),
    estimatedFare = safeNumber(source, "estimatedFare", 0),
    pickupWaitLimit = safeNumber(source, "pickupWaitLimit", 0),
    isRush = source.isRush == true,
    bonusPercent = safeNumber(source, "bonusPercent", 0),
    bonusAmount = safeNumber(source, "bonusAmount", 0),
    rushTimeLimit = safeNumber(source, "rushTimeLimit", 0)
  }
end

local function routeKey(route)
  local parts = {
    route.isDelivery and "delivery" or "passenger",
    route.isMultiStop and "multi" or "direct"
  }
  local function addPoint(point)
    parts[#parts + 1] = string.format("%.0f:%.0f",
      (point.x or 0) / 25, (point.y or 0) / 25)
  end
  addPoint(route.pickup)
  for _, stop in ipairs(route.stops or {}) do addPoint(stop) end
  addPoint(route.destination)
  return table.concat(parts, "|")
end

function M.ensureCurrentMapFile()
  local descriptor = currentMapDescriptor()
  local document = readDocument(descriptor)
  return writeDocument(document, descriptor)
end

function M.appendOffer(offer, originPos)
  local descriptor = currentMapDescriptor()
  local route = serializeOffer(offer, originPos)
  if not route then return false end
  local document = readDocument(descriptor)
  local routes = {}
  local newKey = routeKey(route)
  for _, source in ipairs(document.routes or {}) do
    local cached = sanitizeOffer(source)
    if cached and routeKey(cached) ~= newKey then routes[#routes + 1] = cached end
  end
  routes[#routes + 1] = route
  while #routes > maximumRoutes do table.remove(routes, 1) end
  document.routes = routes
  if not writeDocument(document, descriptor) then return false end
  log("I", "taxiDriver.routeCache", string.format(
    "Cached dispatcher offer %d/%d for '%s' in '%s'",
    #routes, maximumRoutes, descriptor.mapId, descriptor.filePath
  ))
  return true
end

function M.loadOffers()
  local descriptor = currentMapDescriptor()
  local document = readDocument(descriptor)
  local result, seen = {}, {}
  for index = #document.routes, 1, -1 do
    local route = sanitizeOffer(document.routes[index])
    if route then
      local key = routeKey(route)
      if not seen[key] then
        seen[key] = true
        result[#result + 1] = route
      end
    end
  end
  return result, descriptor
end

local function inflatePoint(source)
  return {
    pos = vec3(source.x, source.y, source.z),
    dir = vec3(source.dirX, source.dirY, source.dirZ),
    nodeA = source.nodeA,
    nodeB = source.nodeB,
    anchorKind = source.anchorKind or "routeCache",
    routeDistance = source.routeDistance
  }
end

function M.inflateOffer(source, offerId)
  local cached = sanitizeOffer(source)
  if not cached then return nil end
  local stops = {}
  for _, stop in ipairs(cached.stops) do stops[#stops + 1] = inflatePoint(stop) end
  return {
    id = offerId,
    passengerName = cached.passengerName ~= "" and cached.passengerName or
      (cached.isDelivery and "Delivery" or "Passenger"),
    isDelivery = cached.isDelivery,
    cargoWeightKg = cached.cargoWeightKg,
    cargoWeightBonusRate = cached.cargoWeightBonusRate,
    cargoWeightBonusAmount = cached.cargoWeightBonusAmount,
    cargoDamagePercent = cached.cargoDamagePercent,
    passengerCalmness = cached.passengerCalmness,
    passengerInitialCalmness = cached.passengerInitialCalmness,
    pickup = inflatePoint(cached.pickup),
    destination = inflatePoint(cached.destination),
    stops = stops,
    isMultiStop = cached.isMultiStop,
    rideDistance = cached.rideDistance,
    totalEtaMinutes = cached.totalEtaMinutes,
    baseFare = cached.baseFare,
    ratingAdjustedFare = cached.ratingAdjustedFare,
    ratingBonusRate = cached.ratingBonusRate,
    ratingBonusAmount = cached.ratingBonusAmount,
    estimatedFare = cached.estimatedFare,
    pickupWaitLimit = cached.pickupWaitLimit,
    isRush = cached.isRush,
    bonusPercent = cached.bonusPercent,
    bonusAmount = cached.bonusAmount,
    rushTimeLimit = cached.rushTimeLimit,
    randomEvent = {kind = "none"},
    cachedRoute = true,
    cacheSavedAt = cached.savedAt,
    cacheOrigin = cached.origin
  }
end

function M.restoreBest(options)
  options = options or {}
  local vehiclePos = options.vehiclePos
  if not vehiclePos then return nil end
  local requestedType = options.requestedType
  local selected, selectedScore = nil, nil
  for _, cached in ipairs(M.loadOffers()) do
    local compatible = requestedType == nil or
      (requestedType == "delivery" and cached.isDelivery) or
      (requestedType ~= "delivery" and not cached.isDelivery)
    if compatible then
      local candidate = M.inflateOffer(cached, options.offerId)
      if candidate then
        local directDistance = vehiclePos:distance(candidate.pickup.pos)
        local exactType = requestedType == nil or
          (requestedType == "delivery" and candidate.isDelivery) or
          (requestedType == "multiStop" and candidate.isMultiStop) or
          (requestedType == "rush" and candidate.isRush) or
          (requestedType == "normal" and not candidate.isMultiStop and
            not candidate.isRush and not candidate.isDelivery)
        local diverse = true
        if type(options.isDiverse) == "function" then
          diverse = options.isDiverse(candidate) == true
        end
        local score = directDistance + (exactType and 0 or 1000000) +
          (diverse and 0 or 100000)
        if selectedScore == nil or score < selectedScore then
          selected, selectedScore = candidate, score
        end
      end
    end
  end
  if not selected then return nil end

  local pickupDistance = type(options.calculateDistance) == "function" and
    options.calculateDistance(vehiclePos, selected.pickup.pos) or nil
  selected.pickup.routeDistance = pickupDistance or math.max(
    tonumber(selected.pickup.routeDistance) or 0,
    vehiclePos:distance(selected.pickup.pos)
  )
  if selected.isDelivery then
    selected.pickupWaitLimit = 0
  elseif type(options.calculatePickupWait) == "function" then
    selected.pickupWaitLimit = options.calculatePickupWait(
      selected.pickup.routeDistance)
  end
  return selected
end

function M.getCurrentDescriptor()
  return currentMapDescriptor()
end

M.schemaVersion = schemaVersion
M.cacheDirectory = cacheDirectory
M.maximumRoutes = maximumRoutes
M.filenamePart = filenamePart
M.serializeOffer = serializeOffer
M.sanitizeOffer = sanitizeOffer
M.routeKey = routeKey

return M
