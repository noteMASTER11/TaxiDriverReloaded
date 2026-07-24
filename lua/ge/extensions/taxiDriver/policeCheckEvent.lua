-- Optional random police inspection built on BeamNG's native traffic/pursuit
-- systems. An installed police configuration is loaded asynchronously near the
-- start of a shift and then kept as an inactive, invisible scene object. The
-- event can therefore activate it 500-600 metres behind the player without
-- loading a vehicle at the surprise moment.
local M = {}

local spawnSequence = 0

local function objectById(id)
  if type(getObjectByID) ~= "function" then return nil end
  return getObjectByID(tonumber(id) or -1)
end

local function trafficData()
  if not gameplay_traffic or type(gameplay_traffic.getTrafficData) ~= "function" then return {} end
  return gameplay_traffic.getTrafficData() or {}
end

local function installedPoliceGroup()
  local group
  if gameplay_traffic_trafficUtils and
    type(gameplay_traffic_trafficUtils.createPoliceGroup) == "function" then
    local ok, result = pcall(gameplay_traffic_trafficUtils.createPoliceGroup, 1, true)
    if ok and type(result) == "table" and result[1] then group = result end
  end
  if group then return group end
  if not core_multiSpawn or type(core_multiSpawn.createGroup) ~= "function" then return nil end
  local ok, result = pcall(core_multiSpawn.createGroup, 1, {
    allMods = true,
    allConfigs = true,
    minPop = 0,
    modelPopPower = 1,
    configPopPower = 1,
    filters = {
      Type = {car = 1, truck = 0.6},
      ["Config Type"] = {police = 1}
    }
  })
  return ok and type(result) == "table" and result[1] and result or nil
end

function M.new()
  local service = {
    active = false,
    stage = "idle",
    elapsed = 0,
    releaseTimer = 0,
    playerId = nil,
    policeId = nil,
    spawnedPolice = false,
    playerWasTraffic = false,
    spawnGroupName = nil,
    preloadGroupName = nil,
    preparedPoliceId = nil,
    preloadRequested = false,
    discardPreloadOnArrival = false,
    event = nil,
    callbacks = {}
  }

  function service:_notify(name, ...)
    local callback = self.callbacks and self.callbacks[name]
    if type(callback) == "function" then
      local ok, result = pcall(callback, ...)
      if ok then return result end
    end
    return nil
  end

  function service:_stashOwnedPolice()
    if not self.spawnedPolice or not self.policeId then return end
    if gameplay_traffic and type(gameplay_traffic.removeTraffic) == "function" then
      pcall(gameplay_traffic.removeTraffic, self.policeId, true)
    end
    local vehicle = objectById(self.policeId)
    if vehicle and vehicle.setActive then
      pcall(vehicle.setActive, vehicle, 0)
      self.preparedPoliceId = self.policeId
    end
  end

  function service:_discardPreparedPolice()
    local vehicle = objectById(self.preparedPoliceId)
    if vehicle and vehicle.delete then pcall(vehicle.delete, vehicle) end
    self.preparedPoliceId = nil
  end

  function service:_restorePlayerTraffic()
    if self.playerWasTraffic or not self.playerId then return end
    local data = trafficData()[self.playerId]
    if data and (not data.pursuit or (tonumber(data.pursuit.mode) or 0) <= 0) and
      gameplay_traffic and type(gameplay_traffic.removeTraffic) == "function" then
      pcall(gameplay_traffic.removeTraffic, self.playerId, false)
    end
  end

  function service:_finish(reason)
    local event = self.event
    if event then
      event.active = false
      event.status = reason or "complete"
    end
    self:_stashOwnedPolice()
    self:_restorePlayerTraffic()
    self:_notify("complete", reason or "complete", event)
    self.active = false
    self.stage = "idle"
    self.elapsed = 0
    self.releaseTimer = 0
    self.playerId = nil
    self.policeId = nil
    self.spawnedPolice = false
    self.playerWasTraffic = false
    self.spawnGroupName = nil
    self.event = nil
    self.callbacks = {}
  end

  function service:prepare()
    if self.active or self.preloadRequested or objectById(self.preparedPoliceId) then return true end
    local player = getPlayerVehicle and getPlayerVehicle(0) or nil
    local mapData = map and map.getMap and map.getMap() or nil
    if not player or not mapData or not mapData.nodes or not next(mapData.nodes) then return false end
    if extensions and type(extensions.load) == "function" then
      if not gameplay_traffic then pcall(extensions.load, "gameplay_traffic") end
      if not gameplay_police then pcall(extensions.load, "gameplay_police") end
    end
    local group = installedPoliceGroup()
    if not group or not core_multiSpawn or type(core_multiSpawn.spawnGroup) ~= "function" then return false end
    spawnSequence = spawnSequence + 1
    self.preloadGroupName = string.format("taxiDriverPolicePreload_%d", spawnSequence)
    self.preloadRequested = true
    self.discardPreloadOnArrival = false
    local ok = pcall(core_multiSpawn.spawnGroup, group, 1, {
      name = self.preloadGroupName,
      mode = "roadBehind",
      gap = 1000,
      instant = false,
      randomPaints = false
    })
    if not ok then
      self.preloadRequested = false
      self.preloadGroupName = nil
    end
    return ok
  end

  function service:_activatePreparedPolice()
    local vehicle = objectById(self.preparedPoliceId)
    if not vehicle then
      self.preparedPoliceId = nil
      return false
    end
    local policeId = self.preparedPoliceId
    self.preparedPoliceId = nil
    local distance = 500 + math.random() * 100
    if vehicle.setActive then pcall(vehicle.setActive, vehicle, 1) end
    local placed = core_multiSpawn and type(core_multiSpawn.placeGroup) == "function" and
      pcall(core_multiSpawn.placeGroup, {policeId}, {
          mode = "roadBehind",
          gap = distance,
          instant = true
        })
    if not placed then
      if vehicle.setActive then pcall(vehicle.setActive, vehicle, 0) end
      self.preparedPoliceId = policeId
      self:_notify("unavailable", "placement_failed", self.event)
      self:_finish("unavailable")
      return false
    end
    return self:_beginPursuit(policeId, true)
  end

  function service:_beginPursuit(policeId, spawned)
    if not objectById(self.playerId) or not objectById(policeId) then
      self:_notify("unavailable", "vehicle_missing", self.event)
      self:_finish("unavailable")
      return false
    end
    if not gameplay_police or type(gameplay_police.setupPursuitGameplay) ~= "function" or
      type(gameplay_police.setPursuitMode) ~= "function" then
      self:_notify("unavailable", "police_api_missing", self.event)
      self:_finish("unavailable")
      return false
    end
    self.policeId = tonumber(policeId)
    self.spawnedPolice = spawned == true
    local ok, setupResult = pcall(
      gameplay_police.setupPursuitGameplay,
      self.playerId,
      {self.policeId},
      {pursuitMode = 1, preventAutoStart = true}
    )
    if not ok or setupResult == false then
      self:_notify("unavailable", "pursuit_setup_failed", self.event)
      self:_finish("unavailable")
      return false
    end
    local pursuitOk = pcall(gameplay_police.setPursuitMode, 1, self.playerId, {self.policeId})
    if not pursuitOk then
      self:_notify("unavailable", "pursuit_start_failed", self.event)
      self:_finish("unavailable")
      return false
    end
    self.stage = "pursuit"
    self.elapsed = 0
    if self.event then self.event.status = "pursuit" end
    self:_notify("started", self.event, self.policeId)
    return true
  end

  function service:start(event, playerId, callbacks)
    if self.active or not event or event.kind ~= "policeCheck" then return false, "busy" end
    if extensions and type(extensions.load) == "function" then
      if not gameplay_traffic then pcall(extensions.load, "gameplay_traffic") end
      if not gameplay_police then pcall(extensions.load, "gameplay_police") end
    end
    playerId = tonumber(playerId)
    if not playerId or not objectById(playerId) then return false, "player_missing" end
    local playerTraffic = trafficData()[playerId]
    if playerTraffic and playerTraffic.pursuit and
      (tonumber(playerTraffic.pursuit.mode) or 0) > 0 then
      event.active, event.status = false, "native_pursuit_active"
      return false, "native_pursuit_active"
    end

    self.active = true
    self.stage = "preparing"
    self.elapsed = 0
    self.playerId = playerId
    self.playerWasTraffic = playerTraffic ~= nil
    self.event = event
    self.callbacks = type(callbacks) == "table" and callbacks or {}
    event.active, event.status = true, "preparing"

    if objectById(self.preparedPoliceId) then return self:_activatePreparedPolice() end
    if self.preloadRequested then
      self.stage = "waitingPreload"
      event.status = "preparing"
      return true
    end

    local group = installedPoliceGroup()
    if not group or not core_multiSpawn or type(core_multiSpawn.spawnGroup) ~= "function" then
      self:_notify("unavailable", "no_police_configuration", event)
      self:_finish("unavailable")
      return false, "no_police_configuration"
    end
    spawnSequence = spawnSequence + 1
    self.spawnGroupName = string.format("taxiDriverPoliceCheck_%d_%d", playerId, spawnSequence)
    self.stage = "spawning"
    event.status = "spawning"
    local ok = pcall(core_multiSpawn.spawnGroup, group, 1, {
      name = self.spawnGroupName,
      mode = "roadBehind",
      gap = 500 + math.random() * 100,
      instant = false,
      randomPaints = false
    })
    if not ok then
      self:_notify("unavailable", "spawn_failed", event)
      self:_finish("unavailable")
      return false, "spawn_failed"
    end
    return true
  end

  function service:onVehicleGroupSpawned(vehicleIds, _, groupName)
    if self.preloadRequested and groupName == self.preloadGroupName then
      self.preloadRequested = false
      self.preloadGroupName = nil
      local policeId = type(vehicleIds) == "table" and tonumber(vehicleIds[1]) or nil
      local vehicle = objectById(policeId)
      if self.discardPreloadOnArrival then
        self.discardPreloadOnArrival = false
        if vehicle and vehicle.delete then pcall(vehicle.delete, vehicle) end
        return true
      end
      if vehicle and vehicle.setActive then
        pcall(vehicle.setActive, vehicle, 0)
        self.preparedPoliceId = policeId
      elseif vehicle and vehicle.delete then
        pcall(vehicle.delete, vehicle)
      end
      if self.active and self.stage == "waitingPreload" and objectById(self.preparedPoliceId) then
        self:_activatePreparedPolice()
      end
      return true
    end
    if not self.active or self.stage ~= "spawning" or groupName ~= self.spawnGroupName then return false end
    local policeId = type(vehicleIds) == "table" and tonumber(vehicleIds[1]) or nil
    if not policeId then
      self:_notify("unavailable", "spawn_empty", self.event)
      self:_finish("unavailable")
      return true
    end
    self:_beginPursuit(policeId, true)
    return true
  end

  function service:onPursuitAction(vehicleId, action)
    if not self.active or tonumber(vehicleId) ~= tonumber(self.playerId) then return false end
    if action == "arrest" and self.stage ~= "fined" then
      local minimum = math.max(0, tonumber(self.event and self.event.fineMinimum) or 15)
      local maximum = math.max(minimum, tonumber(self.event and self.event.fineMaximum) or 60)
      local amount = math.floor(minimum + math.random() * (maximum - minimum) + 0.5)
      self.stage = "fined"
      self.releaseTimer = 1.25
      if self.event then
        self.event.status = "fined"
        self.event.fineAmount = amount
      end
      self:_notify("fine", amount, self.event)
      return true
    elseif action == "evade" then
      self:_finish("evaded")
      return true
    end
    return false
  end

  function service:update(dt)
    if not self.active then return false end
    dt = math.max(0, tonumber(dt) or 0)
    self.elapsed = self.elapsed + dt
    if (self.stage == "spawning" or self.stage == "waitingPreload") and self.elapsed >= 30 then
      self:_notify("unavailable", "spawn_timeout", self.event)
      self:_finish("unavailable")
      return true
    end
    if self.stage == "pursuit" and self.elapsed >= 150 then
      if gameplay_police and type(gameplay_police.setPursuitMode) == "function" then
        pcall(gameplay_police.setPursuitMode, 0, self.playerId, {self.policeId})
      end
      self:_finish("timeout")
      return true
    end
    if self.stage == "fined" then
      self.releaseTimer = self.releaseTimer - dt
      if self.releaseTimer <= 0 then
        if gameplay_police and type(gameplay_police.releaseVehicle) == "function" then
          pcall(gameplay_police.releaseVehicle, self.playerId, false)
        elseif gameplay_police and type(gameplay_police.setPursuitMode) == "function" then
          pcall(gameplay_police.setPursuitMode, 0, self.playerId, {self.policeId})
        end
        self:_finish("ticketed")
        return true
      end
    end
    return false
  end

  function service:cancel(reason)
    local terminal = reason == "shiftStopped" or reason == "missionEnded" or reason == "extensionUnloaded"
    local wasActive = self.active
    if self.active and gameplay_police and type(gameplay_police.setPursuitMode) == "function" and self.playerId then
      pcall(gameplay_police.setPursuitMode, 0, self.playerId, self.policeId and {self.policeId} or nil)
    end
    if self.active then self:_finish(reason or "cancelled") end
    if terminal then
      if self.preloadRequested then self.discardPreloadOnArrival = true end
      self:_discardPreparedPolice()
    end
    return wasActive or terminal
  end

  function service:getState()
    return {
      active = self.active,
      stage = self.stage,
      playerId = self.playerId,
      policeId = self.policeId,
      spawnedPolice = self.spawnedPolice,
      preparedPoliceId = self.preparedPoliceId,
      preloadRequested = self.preloadRequested
    }
  end

  return service
end

return M
