local M = {}
local fleetWorker = require("taxiDriver/fleetWorker")
local taxiConfig = require("taxiDriver/config")

local schemaVersion = 1
local settingsDirectoryPath = "/settings/TaxiDriver"
local filePath = settingsDirectoryPath .. "/fleet.json"
local logTag = "taxiDriver.fleet"
local worldLabels = {
  en = {taxi = "My fleet driver", passenger = "Passenger trip", delivery = "Cargo delivery", planning = "Planning route", resting = "Waiting for next job", unpaid = "Waiting for salary"},
  ru = {taxi = "Мой водитель такси", passenger = "Везёт пассажира", delivery = "Везёт груз", planning = "Строит маршрут", resting = "Ждёт следующий заказ", unpaid = "Ожидает зарплату"},
  de = {taxi = "Mein Taxifahrer", passenger = "Fahrgastfahrt", delivery = "Warenlieferung", planning = "Plant die Route", resting = "Wartet auf Auftrag", unpaid = "Wartet auf Lohn"},
  fr = {taxi = "Mon chauffeur", passenger = "Course passager", delivery = "Livraison", planning = "Calcule l'itinéraire", resting = "Attend une course", unpaid = "Attend son salaire"},
  es = {taxi = "Mi taxista", passenger = "Viaje de pasajero", delivery = "Entrega de carga", planning = "Calculando ruta", resting = "Esperando servicio", unpaid = "Esperando salario"},
  it = {taxi = "Il mio tassista", passenger = "Corsa passeggero", delivery = "Consegna merci", planning = "Calcolo percorso", resting = "In attesa di lavoro", unpaid = "In attesa dello stipendio"},
  pl = {taxi = "Mój taksówkarz", passenger = "Kurs z pasażerem", delivery = "Dostawa ładunku", planning = "Wyznacza trasę", resting = "Czeka na zlecenie", unpaid = "Czeka na wypłatę"},
  uk = {taxi = "Мій водій таксі", passenger = "Везе пасажира", delivery = "Везе вантаж", planning = "Прокладає маршрут", resting = "Чекає на замовлення", unpaid = "Очікує зарплату"},
  ["zh-CN"] = {taxi = "我的车队司机", passenger = "载客行程", delivery = "货物配送", planning = "正在规划路线", resting = "等待下一单", unpaid = "等待工资"}
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function money(value)
  return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

local function trim(value, maximum)
  return (tostring(value or ""):match("^%s*(.-)%s*$") or ""):sub(1, maximum or 200)
end

local function emptyStats()
  return {
    rides = 0, passengerRides = 0, deliveryRides = 0, distanceMeters = 0,
    grossRevenue = 0, ownerRevenue = 0, hiringFees = 0, wages = 0, netProfit = 0
  }
end

local function sanitizeStats(source)
  source = type(source) == "table" and source or {}
  local result = emptyStats()
  for _, key in ipairs({"rides", "passengerRides", "deliveryRides"}) do
    result[key] = math.max(0, math.floor(tonumber(source[key]) or 0))
  end
  result.distanceMeters = math.max(0, tonumber(source.distanceMeters) or 0)
  for _, key in ipairs({"grossRevenue", "ownerRevenue", "hiringFees", "wages"}) do
    result[key] = money(math.max(0, tonumber(source[key]) or 0))
  end
  result.netProfit = money(result.ownerRevenue - result.hiringFees - result.wages)
  return result
end

local function createStore(version)
  return {schemaVersion = schemaVersion, modVersion = tostring(version or "unknown"), stats = emptyStats(), vehicles = {}}
end

local function sanitizeStore(source, version)
  local result = createStore(version)
  if type(source) ~= "table" or tonumber(source.schemaVersion) ~= schemaVersion then return result end
  result.stats = sanitizeStats(source.stats)
  for key, value in pairs(type(source.vehicles) == "table" and source.vehicles or {}) do
    if type(value) == "table" and trim(key, 320) ~= "" then
      result.vehicles[trim(key, 320)] = {
        key = trim(key, 320), name = trim(value.name, 200), preview = trim(value.preview, 320),
        stats = sanitizeStats(value.stats), lastWorkedAt = math.max(0, math.floor(tonumber(value.lastWorkedAt) or 0))
      }
    end
  end
  return result
end

local function addStat(target, key, amount)
  if key == "rides" or key == "passengerRides" or key == "deliveryRides" then
    target[key] = math.max(0, math.floor(tonumber(target[key]) or 0) + math.floor(tonumber(amount) or 0))
  else
    target[key] = money((tonumber(target[key]) or 0) + (tonumber(amount) or 0))
  end
  target.netProfit = money((target.ownerRevenue or 0) - (target.hiringFees or 0) - (target.wages or 0))
end

local function vehicleIdentity(vehicle, fallback)
  fallback = type(fallback) == "table" and fallback or {}
  if not vehicle then return nil end
  local modelKey = trim(vehicle.jbeam or vehicle.JBeam or fallback.modelKey, 120)
  if modelKey == "" then return nil end
  local configPath = trim(vehicle.partConfig or fallback.configPath, 320)
  local configKey = trim(fallback.configKey, 160)
  if configKey == "" then configKey = configPath:match("([^/]+)%.pc$") or "custom" end
  local name = trim(fallback.name, 200)
  if name == "" and core_vehicles and core_vehicles.getModel then
    local ok, details = pcall(core_vehicles.getModel, modelKey)
    local model = ok and type(details) == "table" and details.model or nil
    name = trim(model and ((model.Brand and model.Brand .. " " or "") .. (model.Name or modelKey)) or modelKey, 200)
  end
  return {
    key = modelKey .. "|" .. configKey, modelKey = modelKey, configKey = configKey,
    configPath = configPath ~= "" and configPath or ("/vehicles/" .. modelKey .. "/" .. configKey .. ".pc"),
    name = name ~= "" and name or modelKey, preview = trim(fallback.preview, 320)
  }
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local service = {}
  local workerFactory = options.workerFactory or fleetWorker
  local version = tostring(options.modVersion or "unknown")
  local language = "en"
  local store = createStore(version)
  local settings = {}
  local drivers = {}
  local nextDriverId = 1
  local saveTimer, hudTimer, candidateTimer, sessionStartedAt = 0, 0, 0, 0
  local dirty, hudDirty = false, true
  local cachedTrafficCandidates = {}
  local minimap = {installed = false, originalSetState = nil, originalDraw = nil, wrappedSetState = nil, wrappedDraw = nil, td = nil, dpi = 1}

  local function writeStore()
    if not FS then return false end
    store.schemaVersion, store.modVersion = schemaVersion, version
    local ok, errorMessage = pcall(function()
      if not FS:directoryExists(settingsDirectoryPath) then FS:directoryCreate(settingsDirectoryPath) end
      jsonWriteFile(filePath, store, true)
    end)
    if not ok then log("E", logTag, "Unable to write fleet statistics: " .. tostring(errorMessage)) end
    if ok then dirty, saveTimer = false, 0 end
    return ok
  end

  local function vehicleStats(identity)
    local entry = store.vehicles[identity.key]
    if not entry then
      entry = {key = identity.key, name = identity.name, preview = identity.preview, stats = emptyStats(), lastWorkedAt = os.time()}
      store.vehicles[identity.key] = entry
    end
    entry.name, entry.preview, entry.lastWorkedAt = identity.name, identity.preview, os.time()
    return entry.stats
  end

  local function account(driver, key, value)
    addStat(store.stats, key, value)
    addStat(driver.stats, key, value)
    addStat(vehicleStats(driver.vehicle), key, value)
    dirty, hudDirty = true, true
  end

  local function workerSettings()
    return taxiConfig.fleetAiPresets[settings.aiPreset] or taxiConfig.fleetAiPresets.standard
  end

  local function buildRandomRoute(vehicle)
    local mapData = map and map.getMap and map.getMap() or nil
    local nodes = mapData and mapData.nodes or nil
    if not vehicle or type(nodes) ~= "table" or not next(nodes) then return nil end
    local startA, startB = map.findClosestRoad(vehicle:getPosition())
    if not (startA and startB and nodes[startA] and nodes[startB]) then return nil end
    local direction = vehicle:getDirectionVector()
    if (nodes[startB].pos - nodes[startA].pos):dot(direction) < 0 then startA, startB = startB, startA end
    local minimum = clamp(settings.minimumJobDistanceKm, 0.5, 20) * 1000
    local maximum = clamp(settings.maximumJobDistanceKm, minimum / 1000, 50) * 1000
    local desired = minimum + (maximum - minimum) * math.random()
    local graph = map.getGraphpath and map.getGraphpath() or nil
    if not graph or type(graph.getRandomPathG) ~= "function" then return nil end
    local path = graph:getRandomPathG(startA, direction, desired + 1200, 0.55, 1, true)
    if type(path) ~= "table" or #path < 2 then return nil end
    local route, distance = {}, 0
    for index, nodeId in ipairs(path) do
      local node = nodes[nodeId]
      if node then
        if route[#route] then distance = distance + route[#route].pos:distance(node.pos) end
        route[#route + 1] = {wp = nodeId, pos = node.pos}
        if distance >= desired and index >= 3 then break end
      end
    end
    if #route < 2 then return nil end
    for index = #route, 1, -1 do
      route[index].distToTarget = index == #route and 0 or
        route[index].pos:distance(route[index + 1].pos) + route[index + 1].distToTarget
    end
    local last, previous = route[#route], route[#route - 1]
    return {pos = vec3(last.pos), nodeA = previous.wp, nodeB = last.wp}, route, math.max(distance, minimum)
  end

  local function startJob(driver, vehicle)
    local passengerEnabled = settings.passengerJobs ~= false
    local deliveryEnabled = settings.deliveryJobs ~= false
    if passengerEnabled and deliveryEnabled then driver.jobType = math.random() < 0.62 and "passenger" or "delivery"
    elseif deliveryEnabled then driver.jobType = "delivery"
    else driver.jobType = "passenger" end
    local target, route, distance = buildRandomRoute(vehicle)
    driver.jobProgressMeters, driver.jobSeconds = 0, 0
    if not target then
      driver.status, driver.routeRetrySeconds = "planning", 2
      return false
    end
    driver.target, driver.route, driver.jobDistanceMeters = target, route, distance
    driver.status, driver.routeRetrySeconds = "working", 0
    if not driver.worker:start(vehicle, target, route, workerSettings()) then
      driver.status, driver.routeRetrySeconds, driver.target, driver.route = "planning", 2, nil, nil
      return false
    end
    return true
  end

  local function commandVehicle(vehicle, command)
    if vehicle and type(vehicle.queueLuaCommand) == "function" then vehicle:queueLuaCommand(command) end
  end

  local function activateVehicle(vehicle)
    if not vehicle then return end
    vehicle.playerUsable = false
    vehicle:setDynDataFieldbyName("isTraffic", 0, "false")
    commandVehicle(vehicle, 'electrics.setIgnitionLevel(2); mapmgr.enableTracking(); ai.setMode("disabled")')
  end

  local function detachTraffic(vehicleId)
    local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
    if traffic[vehicleId] and gameplay_traffic.removeTraffic then gameplay_traffic.removeTraffic(vehicleId, false) end
  end

  local function safeSpawnTransform()
    local player = be and be:getPlayerVehicle(0) or nil
    local pos = player and player:getPosition() or (core_camera and core_camera.getPosition())
    local dir = player and player:getDirectionVector() or (core_camera and core_camera.getForward())
    local utils = gameplay_traffic_trafficUtils
    if not utils then pcall(function() utils = require("gameplay/traffic/trafficUtils") end) end
    if utils and utils.findSafeSpawnPoint then
      local ok, spawnData = pcall(utils.findSafeSpawnPoint, pos, dir, 35, 220, 80)
      if ok and spawnData and spawnData.pos and spawnData.dir then
        local normal = map and map.surfaceNormal and map.surfaceNormal(spawnData.pos) or vec3(0, 0, 1)
        return spawnData.pos, quatFromDir(spawnData.dir, normal)
      end
    end
    return pos and (pos + vec3(8, 0, 1)) or vec3(0, 0, 1), quatFromDir(dir or vec3(0, 1, 0))
  end

  local function addDriver(vehicle, identity, source)
    if not vehicle or not identity then return nil, "vehicle_unavailable" end
    local id = nextDriverId
    nextDriverId = nextDriverId + 1
    local pos = vehicle:getPosition()
    local driver = {
      id = id, vehicleId = vehicle:getID(), source = source, vehicle = identity,
      hiredAt = os.time(), lastPosition = pos and vec3(pos) or nil, activeSeconds = 0,
      wageSeconds = 0, stoppedSeconds = 0, stats = emptyStats(),
      worker = workerFactory.new({config = taxiConfig.autopilot})
    }
    drivers[id] = driver
    activateVehicle(vehicle)
    if source == "spawned" then driver.status, driver.routeRetrySeconds = "planning", 2
    else startJob(driver, vehicle) end
    account(driver, "hiringFees", settings.hiringFee)
    return driver
  end

  local function findDriver(id)
    return drivers[math.floor(tonumber(id) or -1)]
  end

  local function activeCount()
    local count = 0
    for _ in pairs(drivers) do count = count + 1 end
    return count
  end

  local function validateCapacity(balance)
    if settings.enabled == false then return false, "fleet_disabled" end
    if activeCount() >= settings.maxDrivers then return false, "fleet_full" end
    if (tonumber(balance) or 0) < settings.hiringFee then return false, "insufficient_funds" end
    return true
  end

  local function hireGarage(args, balance)
    local valid, reason = validateCapacity(balance)
    if not valid then return false, reason, 0 end
    local modelKey, configKey = trim(args.modelKey, 120), trim(args.configKey, 160)
    if not modelKey:match("^[%w_%-]+$") or not configKey:match("^[%w_%-]+$") then return false, "invalid_vehicle", 0 end
    local model = core_vehicles and core_vehicles.getModel and core_vehicles.getModel(modelKey) or nil
    if not (model and model.model) then return false, "vehicle_unavailable", 0 end
    local pos, rot = safeSpawnTransform()
    local vehicle = core_vehicles.spawnNewVehicle(modelKey, {
      config = "/vehicles/" .. modelKey .. "/" .. configKey .. ".pc",
      pos = pos, rot = rot, cling = true, autoEnterVehicle = false
    })
    local identity = vehicleIdentity(vehicle, args)
    local driver, errorMessage = addDriver(vehicle, identity, "spawned")
    if not driver then return false, errorMessage, 0 end
    log("I", logTag, string.format("Hired spawned fleet vehicle %d (%s)", vehicle:getID(), identity.name))
    return true, nil, -settings.hiringFee
  end

  local function hireTraffic(args, balance)
    local valid, reason = validateCapacity(balance)
    if not valid then return false, reason, 0 end
    local vehicleId = math.floor(tonumber(args.vehicleId) or -1)
    if vehicleId == (be and be:getPlayerVehicleID(0) or -2) then return false, "invalid_vehicle", 0 end
    for _, driver in pairs(drivers) do if driver.vehicleId == vehicleId then return false, "already_hired", 0 end end
    local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
    local trafficVehicle = traffic[vehicleId]
    local vehicle = getObjectByID(vehicleId)
    if not trafficVehicle or not vehicle then return false, "vehicle_unavailable", 0 end
    local identity = vehicleIdentity(vehicle, {name = trafficVehicle.modelName})
    detachTraffic(vehicleId)
    local driver, errorMessage = addDriver(vehicle, identity, "traffic")
    if not driver then return false, errorMessage, 0 end
    log("I", logTag, string.format("Recruited traffic vehicle %d (%s)", vehicleId, identity.name))
    return true, nil, -settings.hiringFee
  end

  local function dismiss(args)
    local driver = findDriver(args.id)
    if not driver then return false, "driver_unavailable", 0 end
    local vehicle = getObjectByID(driver.vehicleId)
    if vehicle then
      driver.worker:stop(vehicle, "fleetDismissed")
      vehicle.playerUsable = true
      if driver.source == "spawned" then vehicle:delete()
      elseif gameplay_traffic and gameplay_traffic.insertTraffic then
        gameplay_traffic.insertTraffic(driver.vehicleId, false, false)
      end
    end
    drivers[driver.id] = nil
    hudDirty = true
    return true, nil, 0
  end

  local function listTrafficCandidates()
    local result, player = {}, be and be:getPlayerVehicle(0) or nil
    local playerPos = player and player:getPosition() or nil
    local hired = {}
    for _, driver in pairs(drivers) do hired[driver.vehicleId] = true end
    local traffic = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
    for vehicleId, trafficVehicle in pairs(traffic) do
      local vehicle = getObjectByID(vehicleId)
      if vehicle and vehicleId ~= (be and be:getPlayerVehicleID(0) or -1) and not hired[vehicleId] and trafficVehicle.isAi then
        local pos = vehicle:getPosition()
        result[#result + 1] = {
          vehicleId = vehicleId, name = trim(trafficVehicle.modelName, 200),
          distance = playerPos and pos and playerPos:distance(pos) or 0
        }
      end
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    while #result > 8 do table.remove(result) end
    return result
  end

  local function trafficCandidates()
    if candidateTimer <= 0 then
      cachedTrafficCandidates = listTrafficCandidates()
      candidateTimer = 2
    end
    return cachedTrafficCandidates
  end

  local function releaseDriver(driver, reason)
    local vehicle = driver and getObjectByID(driver.vehicleId) or nil
    if not vehicle then return end
    driver.worker:stop(vehicle, reason or "fleetReleased")
    vehicle.playerUsable = true
    if driver.source == "spawned" then
      vehicle:delete()
    elseif gameplay_traffic and gameplay_traffic.insertTraffic then
      gameplay_traffic.insertTraffic(driver.vehicleId, false, false)
    end
  end

  local function completeJob(driver)
    local km = math.max(0.5, driver.jobProgressMeters / 1000)
    local gross = money((2.5 + km * 1.1 + driver.jobSeconds / 60 * 0.12) * settings.incomeMultiplier)
    local owner = money(gross * settings.ownerSharePercent / 100)
    account(driver, "rides", 1)
    account(driver, driver.jobType == "delivery" and "deliveryRides" or "passengerRides", 1)
    account(driver, "distanceMeters", driver.jobProgressMeters)
    account(driver, "grossRevenue", gross)
    account(driver, "ownerRevenue", owner)
    local result = owner
    driver.status, driver.restSeconds = "resting", 4
    return result
  end

  local function drawMinimapMarkers()
    if not minimap.td or not ui_apps_minimap_utils then return end
    local purple, border = color(154, 74, 255, 255), color(25, 15, 40, 255)
    for _, driver in pairs(drivers) do
      local vehicle = getObjectByID(driver.vehicleId)
      if vehicle then
        local point = vec3(vehicle:getPosition())
        ui_apps_minimap_utils.worldToMapXYZ(point, point)
        minimap.td:circle(point.x, point.y, 7 * minimap.dpi, 0, border, border, 0, 0, 0, 95)
        minimap.td:circle(point.x, point.y, 4.5 * minimap.dpi, 0, purple, purple, 0, 0, 0, 96)
      end
    end
  end

  function service:installMinimapMarkers()
    if minimap.installed then return end
    if not ui_apps_minimap_vehicles and extensions then extensions.load("ui_apps_minimap_vehicles") end
    local module = ui_apps_minimap_vehicles
    if not module or type(module.setMinimapState) ~= "function" or type(module.drawOtherVehicles) ~= "function" then return end
    minimap.originalSetState, minimap.originalDraw = module.setMinimapState, module.drawOtherVehicles
    minimap.wrappedSetState = function(...)
      local args = {...}; minimap.td, minimap.dpi = args[10], tonumber(args[13]) or 1
      return minimap.originalSetState(...)
    end
    minimap.wrappedDraw = function(...)
      local result = minimap.originalDraw(...); drawMinimapMarkers(); return result
    end
    module.setMinimapState, module.drawOtherVehicles = minimap.wrappedSetState, minimap.wrappedDraw
    minimap.installed = true
  end

  function service:restoreMinimapMarkers()
    local module = ui_apps_minimap_vehicles
    if minimap.installed and module then
      if module.setMinimapState == minimap.wrappedSetState then module.setMinimapState = minimap.originalSetState end
      if module.drawOtherVehicles == minimap.wrappedDraw then module.drawOtherVehicles = minimap.originalDraw end
    end
    minimap = {installed = false, originalSetState = nil, originalDraw = nil, wrappedSetState = nil, wrappedDraw = nil, td = nil, dpi = 1}
  end

  function service:load()
    local source = nil
    if FS and FS:fileExists(filePath) then local ok, value = pcall(jsonReadFile, filePath); if ok then source = value end end
    store = sanitizeStore(source, version)
    sessionStartedAt, hudDirty = os.time(), true
    writeStore()
    self:installMinimapMarkers()
  end

  function service:configure(value, nextLanguage)
    settings = taxiConfig.sanitizeFleet(value)
    language = worldLabels[tostring(nextLanguage or "")] and tostring(nextLanguage) or "en"
    for _, driver in pairs(drivers) do driver.worker:configure(workerSettings()) end
    hudDirty = true
  end

  function service:command(action, args, balance)
    args = type(args) == "table" and args or {}
    if action == "hireGarage" then return hireGarage(args, balance) end
    if action == "hireTraffic" then return hireTraffic(args, balance) end
    if action == "dismiss" then return dismiss(args) end
    return false, "unsupported_command", 0
  end

  function service:update(dtReal, dtSim, balance)
    dtReal, dtSim = math.max(0, tonumber(dtReal) or 0), math.max(0, tonumber(dtSim) or 0)
    saveTimer, hudTimer = saveTimer + dtReal, hudTimer + dtReal
    candidateTimer = math.max(0, candidateTimer - dtReal)
    local walletDelta = 0
    for id, driver in pairs(drivers) do
      local vehicle = getObjectByID(driver.vehicleId)
      if not vehicle then
        drivers[id], hudDirty = nil, true
      elseif dtSim > 0 then
        local pos = vehicle:getPosition()
        local moved = driver.lastPosition and pos and driver.lastPosition:distance(pos) or 0
        if moved > math.max(3, dtSim * 100) then moved = 0 end
        driver.lastPosition = pos and vec3(pos) or driver.lastPosition
        driver.activeSeconds = driver.activeSeconds + dtSim
        if driver.status ~= "unpaid" then driver.wageSeconds = driver.wageSeconds + dtSim end
        if driver.status == "unpaid" then
          if (tonumber(balance) or 0) + walletDelta >= settings.wagePerTenMinutes then
            walletDelta = walletDelta - settings.wagePerTenMinutes
            account(driver, "wages", settings.wagePerTenMinutes)
            driver.status = "working"; driver.worker:suspend(vehicle, false)
          end
        elseif driver.status == "resting" then
          driver.restSeconds = math.max(0, (driver.restSeconds or 0) - dtSim)
          if driver.restSeconds <= 0 then startJob(driver, vehicle) end
        elseif driver.status == "planning" then
          driver.routeRetrySeconds = math.max(0, (driver.routeRetrySeconds or 0) - dtSim)
          if driver.routeRetrySeconds <= 0 then startJob(driver, vehicle) end
        else
          driver.worker:update(vehicle, dtSim)
          driver.jobProgressMeters = driver.jobProgressMeters + moved
          driver.jobSeconds = driver.jobSeconds + dtSim
          if driver.worker:hasArrived(vehicle) then
            driver.worker:stop(vehicle, "fleetJobComplete")
            walletDelta = walletDelta + completeJob(driver)
          end
          if driver.wageSeconds >= 600 then
            driver.wageSeconds = driver.wageSeconds - 600
            if (tonumber(balance) or 0) + walletDelta >= settings.wagePerTenMinutes then
              walletDelta = walletDelta - settings.wagePerTenMinutes
              account(driver, "wages", settings.wagePerTenMinutes)
            else
              driver.status = "unpaid"; driver.worker:suspend(vehicle, true); hudDirty = true
            end
          end
        end
      end
    end
    if dirty and saveTimer >= 5 then writeStore() end
    if hudTimer >= 1 then hudTimer, hudDirty = 0, true end
    return money(walletDelta), hudDirty
  end

  function service:consumeHudDirty()
    local value = hudDirty; hudDirty = false; return value
  end

  function service:getHud(balance, garage)
    local result = {
      enabled = settings.enabled ~= false, activeDrivers = activeCount(), maxDrivers = settings.maxDrivers,
      hiringFee = settings.hiringFee, wagePerTenMinutes = settings.wagePerTenMinutes,
      ownerSharePercent = settings.ownerSharePercent, canAffordHire = (tonumber(balance) or 0) >= settings.hiringFee,
      stats = sanitizeStats(store.stats), drivers = {}, markers = {}, trafficCandidates = trafficCandidates(), garage = {}
    }
    local seen = {}
    for _, candidate in ipairs(type(garage) == "table" and garage or {}) do
      if candidate.modelKey and candidate.configKey and not seen[candidate.key] then
        seen[candidate.key] = true; result.garage[#result.garage + 1] = candidate
      end
      if #result.garage >= 12 then break end
    end
    for _, driver in pairs(drivers) do
      local vehicle = getObjectByID(driver.vehicleId)
      local progress = (driver.jobDistanceMeters or 0) > 0 and clamp(driver.jobProgressMeters / driver.jobDistanceMeters, 0, 1) or 0
      result.drivers[#result.drivers + 1] = {
        id = driver.id, vehicleId = driver.vehicleId, name = driver.vehicle.name, preview = driver.vehicle.preview,
        source = driver.source, status = driver.status, jobType = driver.jobType, progress = progress,
        remainingMeters = math.max(0, (driver.jobDistanceMeters or 0) - (driver.jobProgressMeters or 0)),
        ai = driver.worker:getHud(vehicle), stats = sanitizeStats(driver.stats)
      }
      if vehicle then local pos = vehicle:getPosition(); result.markers[#result.markers + 1] = {id = driver.id, position = {pos.x, pos.y, pos.z}, name = driver.vehicle.name} end
    end
    table.sort(result.drivers, function(a, b) return a.id < b.id end)
    return result
  end

  function service:endSession()
    for _, driver in pairs(drivers) do releaseDriver(driver, "fleetSessionEnded") end
    drivers, hudDirty = {}, true
    if dirty then writeStore() end
  end

  function service:shutdown()
    self:endSession(); self:restoreMinimapMarkers()
  end

  function service:drawWorldLabels()
    if not debugDrawer or not ColorF or not ColorI then return end
    local player = be and be:getPlayerVehicle(0) or nil
    local playerPos = player and player:getPosition() or nil
    if not playerPos then return end
    local labels = worldLabels[language] or worldLabels.en
    for _, driver in pairs(drivers) do
      local vehicle = getObjectByID(driver.vehicleId)
      local pos = vehicle and vehicle:getPosition() or nil
      if pos and playerPos:distance(pos) <= settings.worldLabelDistance then
        local action = driver.status == "unpaid" and labels.unpaid or
          (driver.status == "planning" and labels.planning or
          (driver.status == "resting" and labels.resting or
          (driver.jobType == "delivery" and labels.delivery or labels.passenger)))
        local height = vehicle.getInitialHeight and vehicle:getInitialHeight() or 2
        debugDrawer:drawTextAdvanced(pos + vec3(0, 0, math.max(2.2, height + 0.7)),
          labels.taxi .. " · " .. action, ColorF(0.9, 0.8, 1, 1), true, false,
          ColorI(32, 15, 52, 225), false, false)
      end
    end
  end

  function service:write() return writeStore() end
  function service:onRouteDone(vehicleId)
    for _, driver in pairs(drivers) do
      if tonumber(driver.vehicleId) == tonumber(vehicleId) then return driver.worker:onRouteDone(getObjectByID(vehicleId)) end
    end
    return false
  end
  function service:onBypassComplete(vehicleId, success, reason)
    for _, driver in pairs(drivers) do
      if tonumber(driver.vehicleId) == tonumber(vehicleId) then
        return driver.worker:onBypassComplete(getObjectByID(vehicleId), success, reason)
      end
    end
    return false
  end
  function service:getStats() return sanitizeStats(store.stats) end
  return service
end

M.sanitizeStore = sanitizeStore
M.emptyStats = emptyStats
return M
