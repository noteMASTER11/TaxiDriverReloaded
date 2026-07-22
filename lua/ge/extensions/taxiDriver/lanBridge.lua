-- TaxiDriver lightweight External UI server.
-- It uses BeamNG's native bng-ext-app-v1 transport, but serves only the
-- TaxiDriver phone instead of booting the complete game UI in the browser.
local M = {}
local logger = require("taxiDriver/logger")
local networkAddress = require("taxiDriver/networkAddress")
local wsUtils = require("utils/wsUtils")

local port = 8085
local protocolName = "bng-ext-app-v1"
local externalEntryPoint = "/ui/modules/apps/TaxiDriverHUD/external/index.html"
local externalUiRevision = "330-beta"
local connectionFilePath = "/settings/TaxiDriver/lan.json"
local heartbeatTimeout = 8.0
local mapRefreshInterval = 1.5
local vehicleRefreshInterval = 0.25
local maximumRoadSegments = 50000
local roadChunkSize = 750
local maximumProxyClients = 24
local proxyAcceptPerFrame = 8
local proxyReadSize = 32768
local proxyBufferLimit = 2 * 1024 * 1024

local enabled = false
local server = nil
local externalHeartbeatAge = math.huge
local connected = false
local chosenAddress = "127.0.0.1"
local savedAddressHint = ""
local sessionToken = ""
local statusChanged = false
local mapTimer = 0
local vehicleTimer = 0
local externalView = "home"
local externalVisible = true
local externalMapEnabled = true
local externalTerrainEnabled = true
local externalMapQuality = "balanced"
local authoritativeActive = false
local authoritativePhase = "inactive"
local mapKey = ""
local mapRevision = 0
local cachedMap = nil
local roadLevelKey = ""
local roadRevision = 0
local cachedRoads = nil
local cachedTerrainTiles = nil
local pendingRoadChunk = 0
local pendingRoadChunkCount = 0
local socketLib = require("socket.socket")
local lanListener = nil
local proxyConnections = {}
local bridgeReady = false
local bridgeError = ""
local activeTransport = ""

local navigationViews = {
  trip = true,
  compact = true,
  fuelRoute = true,
  fleet = true
}

local navigationPhases = {
  toPickup = true,
  toStop = true,
  toDestination = true,
  toFuelStation = true
}

local function canPublishNavigation()
  -- The game state is authoritative. A browser tab may miss a view-change
  -- event or be backgrounded, but that must never stop live vehicle telemetry
  -- for an active route.
  return connected and externalMapEnabled and ((authoritativeActive and
    navigationPhases[authoritativePhase] == true) or
    (externalVisible and externalView == "fleet"))
end

local function closeSocket(socket)
  if socket then pcall(function() socket:close() end) end
end

local function closeProxyConnection(connection)
  if not connection then return end
  closeSocket(connection.client)
  closeSocket(connection.upstream)
end

local function stopLanProxy()
  closeSocket(lanListener)
  lanListener = nil
  for _, connection in ipairs(proxyConnections) do
    closeProxyConnection(connection)
  end
  proxyConnections = {}
end

local function startLanProxy()
  stopLanProxy()
  local ok, listenerOrError, bindError = pcall(function()
    return socketLib.bind(chosenAddress, port, 16)
  end)
  if not ok or not listenerOrError then
    bridgeError = tostring(ok and bindError or listenerOrError)
    logger.error("lan", "proxy_bind_failed", {
      address = chosenAddress, port = port, reason = bridgeError
    })
    return false
  end
  lanListener = listenerOrError
  lanListener:settimeout(0)
  logger.info("lan", "proxy_listening", {
    address = chosenAddress, port = port, upstream = "127.0.0.1:" .. port
  })
  return true
end

local function appendProxyBuffer(connection, field, data)
  if not data or data == "" then return true end
  connection[field] = connection[field] .. data
  return #connection[field] <= proxyBufferLimit
end

local function receiveProxyData(socket, connection, field)
  local data, err, partial = socket:receive(proxyReadSize)
  if not appendProxyBuffer(connection, field, data or partial) then
    return false, "buffer limit"
  end
  if err == "closed" then
    if field == "toUpstream" then
      connection.clientClosed = true
    else
      connection.upstreamClosed = true
    end
    return true
  end
  if err and err ~= "timeout" then return false, err end
  return true
end

local function sendProxyData(socket, connection, field)
  local buffer = connection[field]
  if buffer == "" then return true end
  local sent, err, last = socket:send(buffer)
  local count = tonumber(sent) or tonumber(last) or 0
  if count > 0 then connection[field] = buffer:sub(count + 1) end
  if err and err ~= "timeout" then return false, err end
  return true
end

local function acceptProxyClients()
  if not lanListener then return end
  for _ = 1, proxyAcceptPerFrame do
    local client, acceptError = lanListener:accept()
    if not client then
      if acceptError and acceptError ~= "timeout" then
        bridgeError = tostring(acceptError)
      end
      return
    end
    if #proxyConnections >= maximumProxyClients then
      closeSocket(client)
    else
      client:settimeout(0)
      local upstream = socketLib.tcp()
      upstream:settimeout(0.05)
      local connectedUpstream, connectError = upstream:connect("127.0.0.1", port)
      upstream:settimeout(0)
      if connectedUpstream or connectError == "already connected" then
        proxyConnections[#proxyConnections + 1] = {
          client = client,
          upstream = upstream,
          toClient = "",
          toUpstream = "",
          clientClosed = false,
          upstreamClosed = false
        }
      else
        closeSocket(client)
        closeSocket(upstream)
        bridgeError = "Loopback connection failed: " .. tostring(connectError)
        logger.warn("lan", "loopback_connection_failed", {reason = bridgeError})
      end
    end
  end
end

local function updateLanProxy()
  if not lanListener then return end
  acceptProxyClients()
  for index = #proxyConnections, 1, -1 do
    local connection = proxyConnections[index]
    local clientRead = connection.clientClosed or
      receiveProxyData(connection.client, connection, "toUpstream")
    local upstreamRead = clientRead and (connection.upstreamClosed or
      receiveProxyData(connection.upstream, connection, "toClient"))
    local upstreamWrite = upstreamRead and
      sendProxyData(connection.upstream, connection, "toUpstream")
    local clientWrite = upstreamWrite and
      sendProxyData(connection.client, connection, "toClient")
    local finished = (connection.clientClosed and connection.toUpstream == "") or
      (connection.upstreamClosed and connection.toClient == "")
    if not clientWrite or finished then
      closeProxyConnection(connection)
      table.remove(proxyConnections, index)
    end
  end
end

local function probeNativeLanListener(address)
  local client = socketLib.tcp()
  if not client then return false, "tcp unavailable" end
  client:settimeout(0.15)
  local connected, reason = client:connect(address, port)
  closeSocket(client)
  return connected == 1 or connected == true or reason == "already connected", reason
end

local function makeToken()
  local now = os.time() or 0
  local a = math.random(0, 0x7fffffff)
  local b = math.random(0, 0x7fffffff)
  return string.format("%08x%08x%04x", now % 0xffffffff, a, b % 0xffff)
end

local function isValidToken(value)
  return type(value) == "string" and #value >= 20 and #value <= 64 and
    value:match("^[a-fA-F0-9]+$") ~= nil
end

local function routedLanAddress()
  -- Connecting a UDP socket does not send a packet. Windows only resolves the
  -- route and assigns the local interface, which gives us a fallback when the
  -- BeamNG adapter list is incomplete.
  for _, destination in ipairs({"1.1.1.1", "8.8.8.8", "192.0.2.1"}) do
    local udp = socketLib.udp()
    if udp then
      pcall(function() udp:settimeout(0) end)
      local connectedOk, connected = pcall(function()
        return udp:setpeername(destination, 53)
      end)
      local address = nil
      if connectedOk and connected then
        local nameOk, value = pcall(function() return udp:getsockname() end)
        if nameOk then address = networkAddress.normalizeIPv4(value) end
      end
      closeSocket(udp)
      if networkAddress.isLanIPv4(address) then return address end
    end
  end
  return nil
end

local function canBindAddress(address)
  local ok, listener = pcall(function() return socketLib.bind(address, 0, 1) end)
  if ok and listener then closeSocket(listener); return true end
  closeSocket(listener)
  return false
end

local function adapterAddresses()
  local ok, addresses = pcall(function()
    return BNGWebWSServer.getNetworkAdapterAddresses()
  end)
  local usable = ok and type(addresses) == "table" and addresses or {}
  logger.info("lan", "adapter_discovery", {
    count = #usable,
    resultType = type(addresses),
    success = ok
  })
  return usable
end

local function hostnameAddresses()
  local results = {}
  local hostname = ""
  local ok, failure = pcall(function()
    hostname = tostring(socketLib.dns.gethostname() or "")
    if hostname == "" then return end
    local addresses = socketLib.dns.getaddrinfo(hostname)
    for _, entry in ipairs(type(addresses) == "table" and addresses or {}) do
      if type(entry) == "table" and entry.family == "inet" then
        results[#results + 1] = {
          ipv4Addr = entry.addr,
          description = "Windows hostname " .. hostname
        }
      end
    end
  end)
  logger.info("lan", "hostname_discovery", {
    count = #results,
    hostname = hostname,
    reason = ok and "" or tostring(failure),
    success = ok
  })
  return results
end

local function candidateSources(candidate)
  local values = {}
  for _, key in ipairs({"adapter", "native", "route", "saved"}) do
    if candidate.sources and candidate.sources[key] then values[#values + 1] = key end
  end
  return table.concat(values, ",")
end

local function selectLanAddress(nativeAddress)
  local routedAddress = routedLanAddress()
  logger.info("lan", "route_discovery", {address = routedAddress or ""})
  local adapters = adapterAddresses()
  for _, entry in ipairs(hostnameAddresses()) do
    adapters[#adapters + 1] = entry
  end
  local address, candidates = networkAddress.select({
    adapters = adapters,
    nativeAddress = nativeAddress,
    routedAddress = routedAddress,
    savedAddress = savedAddressHint,
    canBind = canBindAddress
  })
  for _, candidate in ipairs(candidates or {}) do
    logger.info("lan", "address_candidate", {
      address = candidate.address,
      bindable = candidate.bindable,
      description = candidate.description,
      penalty = candidate.penalty,
      score = candidate.score,
      sources = candidateSources(candidate)
    })
  end
  logger.info("lan", "address_selected", {
    address = address or "", candidateCount = #(candidates or {})
  })
  return address
end

local function loadConnectionIdentity()
  local saved = nil
  if FS:fileExists(connectionFilePath) then
    local ok, value = pcall(jsonReadFile, connectionFilePath)
    if ok and type(value) == "table" then saved = value end
  end
  sessionToken = saved and isValidToken(saved.token) and saved.token or makeToken()
  local savedAddress = saved and tostring(saved.address or "") or ""
  savedAddressHint = networkAddress.isLanIPv4(savedAddress) and savedAddress or ""
  chosenAddress = savedAddressHint ~= "" and savedAddressHint or "127.0.0.1"
end

local function saveConnectionIdentity()
  jsonWriteFile(connectionFilePath, {
    schemaVersion = 1,
    token = sessionToken,
    address = chosenAddress
  }, true)
end

local function point(pos)
  if not pos then return nil end
  return {
    math.floor((tonumber(pos.x) or 0) * 10 + 0.5) / 10,
    math.floor((tonumber(pos.y) or 0) * 10 + 0.5) / 10
  }
end

local function getRoutePath()
  local planner = core_groundMarkers and core_groundMarkers.routePlanner or nil
  return planner and planner.path or {}
end

local function currentMapKey()
  local path = getRoutePath()
  if #path == 0 then return "empty" end
  local samples = {}
  local function add(index)
    local entry = path[index]
    if not entry then return end
    local p = entry.pos
    samples[#samples + 1] = tostring(entry.wp or "p") .. ":" ..
      string.format("%.0f:%.0f", p and p.x or 0, p and p.y or 0)
  end
  add(1)
  add(2)
  add(math.floor(#path / 2))
  add(#path - 1)
  add(#path)
  return tostring(#path) .. ":" .. table.concat(samples, "|")
end

local function currentRoadLevelKey()
  local mapData = map and map.getMap and map.getMap() or nil
  local nodes = mapData and mapData.nodes or nil
  local levelId = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ""
  return tostring(levelId or "") .. ":" .. tostring(nodes)
end

local function buildRoadNetwork(mapData)
  local roads = {}
  if not mapData or type(mapData.nodes) ~= "table" then return roads end
  local visitedEdges = {}
  for nodeId, node in pairs(mapData.nodes) do
    if node and node.pos and type(node.links) == "table" then
      for linkedId, edge in pairs(node.links) do
        local linked = mapData.nodes[linkedId]
        if linked and linked.pos then
          local a, b = tostring(nodeId), tostring(linkedId)
          local edgeKey = a < b and (a .. "|" .. b) or (b .. "|" .. a)
          if not visitedEdges[edgeKey] then
            visitedEdges[edgeKey] = true
            local edgeData = type(edge) == "table" and edge or {}
            local drivability = math.max(0, math.min(1,
              tonumber(edgeData.drivability) or 1))
            if edgeData.hiddenInNavi ~= true and drivability > 0 then
              local radius = tonumber(edgeData.radius) or
                ((tonumber(edgeData.inRadius) or 0) +
                  (tonumber(edgeData.outRadius) or 0)) * 0.5
              if radius <= 0 then
                radius = ((tonumber(node.radius) or 4) +
                  (tonumber(linked.radius) or 4)) * 0.5
              end
              roads[#roads + 1] = {
                math.floor((tonumber(node.pos.x) or 0) * 10 + 0.5) / 10,
                math.floor((tonumber(node.pos.y) or 0) * 10 + 0.5) / 10,
                math.floor((tonumber(linked.pos.x) or 0) * 10 + 0.5) / 10,
                math.floor((tonumber(linked.pos.y) or 0) * 10 + 0.5) / 10,
                math.max(2, math.min(18, radius)),
                drivability
              }
            end
            if #roads >= maximumRoadSegments then break end
          end
        end
      end
    end
    if #roads >= maximumRoadSegments then break end
  end
  return roads
end

local function vectorComponent(value, index, key)
  if not value then return nil end
  local component = nil
  pcall(function()
    component = value[index]
    if component == nil then component = value[key] end
  end)
  return tonumber(component)
end

local function normalizeTerrainFile(fileName, levelId)
  local file = tostring(fileName or "")
  if file == "" then return "" end
  if file:sub(1, 1) == "/" then return file end
  if file:find("/", 1, true) then return "/" .. file end
  return "/levels/" .. tostring(levelId or "") .. "/" .. file
end

local function buildTerrainTiles()
  local tiles = {}
  local levelId = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ""
  local levelData = core_levels and core_levels.getLevelByName and
    core_levels.getLevelByName(levelId) or nil
  local source = levelData and levelData.minimap or nil
  if type(source) == "table" then
    for _, tile in ipairs(source) do
      local size = tile and tile.size or nil
      local offset = tile and tile.offset or nil
      local file = normalizeTerrainFile(tile and tile.file, levelId)
      local sizeX = vectorComponent(size, 1, "x")
      local sizeY = vectorComponent(size, 2, "y")
      local offsetX = vectorComponent(offset, 1, "x")
      local offsetY = vectorComponent(offset, 2, "y")
      if file ~= "" and sizeX and sizeY and offsetX and offsetY then
        tiles[#tiles + 1] = {
          file = file, size = {sizeX, sizeY}, offset = {offsetX, offsetY}
        }
      end
    end
  end
  if #tiles == 0 then
    local terrain = getObjectByClass and getObjectByClass("TerrainBlock") or nil
    if terrain then
      local blockSize = tonumber(terrain:getWorldBlockSize()) or 0
      local terrainPos = terrain:getPosition()
      local file = normalizeTerrainFile(terrain.minimapImage, levelId)
      if blockSize > 0 and terrainPos and file ~= "" then
        tiles[1] = {
          file = file,
          size = {blockSize, blockSize},
          offset = {terrainPos.x, terrainPos.y + blockSize}
        }
      end
    end
  end
  return tiles
end

local function vehicleSnapshot()
  local vehicle = getPlayerVehicle and getPlayerVehicle(0) or nil
  if not vehicle then return nil end
  local pos = vehicle:getPosition()
  local direction = vehicle:getDirectionVector()
  return {
    position = point(pos),
    direction = direction and {direction.x, direction.y} or {0, 1}
  }
end

local function rebuildMap()
  local path = getRoutePath()
  local route = {}
  for _, entry in ipairs(path) do
    local p = point(entry.pos)
    if p then route[#route + 1] = p end
  end
  mapRevision = mapRevision + 1
  cachedMap = {
    revision = mapRevision,
    route = route,
    target = route[#route]
  }
  mapKey = currentMapKey()
end

local function rebuildRoads()
  local mapData = map and map.getMap and map.getMap() or nil
  cachedRoads = buildRoadNetwork(mapData)
  cachedTerrainTiles = externalTerrainEnabled and buildTerrainTiles() or {}
  roadRevision = roadRevision + 1
  roadLevelKey = currentRoadLevelKey()
  local mapFields = {roads = #cachedRoads, terrainTiles = #cachedTerrainTiles}
  if #cachedRoads > 0 then logger.info("lan", "map_prepared", mapFields)
  else logger.warn("lan", "map_empty", mapFields) end
end

local function queueRoadPublish()
  pendingRoadChunk = 1
  pendingRoadChunkCount = math.max(1,
    math.ceil(#(cachedRoads or {}) / roadChunkSize))
end

local function publishNextRoadChunk()
  if pendingRoadChunk < 1 or not cachedRoads then return end
  local firstIndex = (pendingRoadChunk - 1) * roadChunkSize + 1
  local lastIndex = math.min(#cachedRoads, firstIndex + roadChunkSize - 1)
  local chunk = {}
  for index = firstIndex, lastIndex do
    chunk[#chunk + 1] = cachedRoads[index]
  end
  guihooks.trigger("TaxiDriverExternalRoadData", {
    revision = roadRevision,
    chunkIndex = pendingRoadChunk,
    chunkCount = pendingRoadChunkCount,
    totalRoads = #cachedRoads,
    reset = pendingRoadChunk == 1,
    complete = pendingRoadChunk >= pendingRoadChunkCount,
    terrainTiles = pendingRoadChunk == 1 and cachedTerrainTiles or nil,
    roads = chunk
  })
  pendingRoadChunk = pendingRoadChunk + 1
  if pendingRoadChunk > pendingRoadChunkCount then pendingRoadChunk = 0 end
end

local function publishMap()
  if not cachedMap then rebuildMap() end
  guihooks.trigger("TaxiDriverExternalMapData", cachedMap or {})
end

local function setConnected(value)
  value = value == true
  if connected ~= value then
    connected = value
    statusChanged = true
    logger.info("lan", value and "client_connected" or "client_disconnected", {view = externalView})
  end
end

local function normalizeExternalView(view)
  local normalizedView = tostring(view or "home")
  if not navigationViews[normalizedView] and normalizedView ~= "home" and
    normalizedView ~= "orders" and normalizedView ~= "settings" and
    normalizedView ~= "profile" and normalizedView ~= "fleet" and normalizedView ~= "fuel" and
    normalizedView ~= "status" and normalizedView ~= "hidden" then
    normalizedView = "home"
  end
  return normalizedView
end

local function applyExternalView(view, visible, wasPublishing)
  local normalizedView = normalizeExternalView(view)
  if wasPublishing == nil then wasPublishing = canPublishNavigation() end
  local normalizedVisible = visible == true and normalizedView ~= "hidden"
  local changed = externalView ~= normalizedView or externalVisible ~= normalizedVisible
  externalView = normalizedView
  externalVisible = normalizedVisible
  if changed then vehicleTimer = 0 end
  if not wasPublishing and canPublishNavigation() then M.requestExternalMap() end
end

function M.start()
  if enabled then return true end
  if sessionToken == "" then loadConnectionIdentity() end
  externalHeartbeatAge = math.huge
  setConnected(false)
  -- In BeamNG 0.38 the native adapter list is populated only when a server is
  -- created on "any". The native server therefore owns the LAN listener; a
  -- second LuaSocket proxy on the same port would conflict with it.
  local ok, createdServer, nativeAddress = pcall(function()
    return wsUtils.createOrGetWS(
      "any", port, "./", protocolName, externalEntryPoint, true
    )
  end)
  if not ok or not createdServer then
    server = nil
    enabled = false
    statusChanged = true
    logger.error("lan", "server_start_failed")
    return false
  end
  server = createdServer
  pcall(function() server:enableDataStreams() end)
  logger.info("lan", "native_server_started", {
    address = tostring(nativeAddress or ""), listenAddress = "any", port = port
  })
  local detectedAddress = selectLanAddress(nativeAddress)
  if not detectedAddress then
    bridgeError = "No bindable LAN IPv4 address was found after server initialization"
    pcall(function() BNGWebWSServer.destroy(server) end)
    server = nil
    enabled = false
    statusChanged = true
    logger.error("lan", "external_ui_unavailable", {reason = bridgeError})
    return false
  end
  chosenAddress = detectedAddress
  stopLanProxy()
  local nativeReachable, nativeProbeError = probeNativeLanListener(chosenAddress)
  logger.info("lan", "native_lan_probe", {
    address = chosenAddress,
    reachable = nativeReachable,
    reason = nativeProbeError or ""
  })
  if nativeReachable then
    activeTransport = "native_any"
  elseif startLanProxy() then
    activeTransport = "lua_proxy"
  else
    pcall(function() BNGWebWSServer.destroy(server) end)
    server = nil
    enabled = false
    bridgeReady = false
    statusChanged = true
    logger.error("lan", "external_ui_unavailable", {reason = bridgeError})
    return false
  end
  bridgeReady = true
  bridgeError = ""
  savedAddressHint = chosenAddress
  saveConnectionIdentity()
  enabled = true
  statusChanged = true
  logger.info("lan", "external_ui_started", {
    address = chosenAddress, port = port, transport = activeTransport
  })
  return true
end

function M.stop()
  stopLanProxy()
  bridgeReady = false
  activeTransport = ""
  if server then
    pcall(function() BNGWebWSServer.destroy(server) end)
    server = nil
  end
  enabled = false
  externalView = "home"
  externalVisible = true
  authoritativeActive = false
  authoritativePhase = "inactive"
  externalHeartbeatAge = math.huge
  setConnected(false)
  cachedMap = nil
  cachedRoads = nil
  cachedTerrainTiles = nil
  mapKey = ""
  roadLevelKey = ""
  pendingRoadChunk = 0
  pendingRoadChunkCount = 0
  statusChanged = true
  logger.info("lan", "external_ui_stopped")
end

function M.setEnabled(value)
  if value == true then return M.start() end
  M.stop()
  return true
end

function M.externalHeartbeat(token, view, visible)
  if not enabled then return false end
  if tostring(token or "") ~= sessionToken then return false end
  local wasPublishing = canPublishNavigation()
  externalHeartbeatAge = 0
  setConnected(true)
  if view ~= nil then applyExternalView(view, visible, wasPublishing) end
  return true
end

function M.requestExternalMap()
  if not enabled or not canPublishNavigation() then return end
  if not cachedRoads or roadLevelKey ~= currentRoadLevelKey() then rebuildRoads() end
  publishMap()
  queueRoadPublish()
  publishNextRoadChunk()
  guihooks.trigger("TaxiDriverExternalVehicleState", vehicleSnapshot() or {})
end

function M.setExternalView(view, visible, token)
  if not enabled or tostring(token or "") ~= sessionToken then return false end
  applyExternalView(view, visible)
  return true
end

function M.setPerformanceOptions(options)
  options = type(options) == "table" and options or {}
  local previousTerrain = externalTerrainEnabled
  externalMapEnabled = options.externalMapEnabled ~= false
  externalTerrainEnabled = options.externalTerrainEnabled ~= false
  local quality = tostring(options.externalMapQuality or "balanced")
  if quality ~= "eco" and quality ~= "smooth" then quality = "balanced" end
  externalMapQuality = quality
  vehicleRefreshInterval = quality == "eco" and 0.5 or
    (quality == "smooth" and 0.125 or 0.25)
  if previousTerrain ~= externalTerrainEnabled then
    cachedRoads = nil
    cachedTerrainTiles = nil
    roadLevelKey = ""
    pendingRoadChunk = 0
  end
  logger.info("lan", "performance_options", {
    mapEnabled = externalMapEnabled,
    quality = externalMapQuality,
    terrainEnabled = externalTerrainEnabled,
    vehicleRefreshInterval = vehicleRefreshInterval
  })
  if not externalMapEnabled then pendingRoadChunk = 0 end
end

function M.getStatus()
  return {
    enabled = enabled,
    connected = connected and 1 or 0,
    bridgeReady = bridgeReady and 1 or 0,
    bridgeError = bridgeError,
    address = chosenAddress,
    port = port,
    url = enabled and ("http://" .. chosenAddress .. ":" .. port ..
      externalEntryPoint .. "?token=" .. sessionToken .. "&v=" .. externalUiRevision) or ""
  }
end

function M.consumeStatusChanged()
  local changed = statusChanged
  statusChanged = false
  return changed
end

function M.update(dtReal)
  if not enabled then return end
  if server then
    -- Command and hook traffic is handled by BeamNG's native transport.
    -- Drain peer notifications so the server queue cannot grow indefinitely.
    pcall(function()
      server:update()
      server:getPeerEvents()
    end)
  end
  updateLanProxy()
  dtReal = math.max(0, tonumber(dtReal) or 0)
  externalHeartbeatAge = externalHeartbeatAge + dtReal
  if externalHeartbeatAge > heartbeatTimeout then setConnected(false) end
  if not connected then return end

  if not canPublishNavigation() then return end

  mapTimer = mapTimer + dtReal
  local newKey = currentMapKey()
  if not cachedMap or (mapTimer >= mapRefreshInterval and newKey ~= mapKey) then
    mapTimer = 0
    rebuildMap()
    publishMap()
  end

  local newRoadLevelKey = currentRoadLevelKey()
  if not cachedRoads or newRoadLevelKey ~= roadLevelKey then
    rebuildRoads()
    queueRoadPublish()
  end
  publishNextRoadChunk()

  vehicleTimer = vehicleTimer + dtReal
  if vehicleTimer >= vehicleRefreshInterval then
    vehicleTimer = 0
    guihooks.trigger("TaxiDriverExternalVehicleState", vehicleSnapshot() or {})
  end
end

function M.setState(state)
  state = type(state) == "table" and state or {}
  local wasPublishing = canPublishNavigation()
  authoritativeActive = state.active == true
  authoritativePhase = tostring(state.phase or "inactive")
  if not wasPublishing and canPublishNavigation() then M.requestExternalMap() end
end

function M.isConnected()
  return connected
end

-- Kept as a no-op so older taxiDriver.lua builds can load this module safely.
function M.setCommandHandler() end

return M
