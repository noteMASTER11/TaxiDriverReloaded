-- Optional physical pickup props. The stock unicycle is controlled through its
-- own playerController instance, so the real player vehicle and camera are not
-- switched. Every failure falls back to the regular logical pickup.
local M = {}
local logger = require("taxiDriver/logger")

local function objectById(id)
  return type(getObjectByID) == "function" and getObjectByID(tonumber(id) or -1) or nil
end

local function safeDelete(id)
  local object = objectById(id)
  if object and type(object.delete) == "function" then pcall(object.delete, object) end
end

local function spawn(model, config, position, rotation)
  if not core_vehicles or type(core_vehicles.spawnNewVehicle) ~= "function" or not position then
    return nil
  end
  local ok, vehicle = pcall(core_vehicles.spawnNewVehicle, model, {
    config = config,
    pos = position,
    rot = rotation or quat(0, 0, 0, 1),
    cling = true,
    autoEnterVehicle = false
  })
  if not ok or not vehicle then return nil end
  vehicle.playerUsable = false
  -- Keep the prop out of expensive all-vehicle prediction scans. It remains a
  -- real collidable object; pickup-distance control below is the lightweight
  -- safety guard used by the taxi AI.
  vehicle.taxiDriverIgnoreObstacle = true
  vehicle:queueLuaCommand("if mapmgr then mapmgr.disableTracking() end")
  return vehicle
end

local function stopWalker(object)
  if not object or type(object.queueLuaCommand) ~= "function" then return end
  object:queueLuaCommand(
    "local c=controller.getControllerSafe('playerController'); " ..
    "if c then c.walkUpDownRaw(0); c.walkLeftRightRaw(0) end"
  )
end

local function setHorn(taxi, enabled)
  if taxi and type(taxi.queueLuaCommand) == "function" then
    taxi:queueLuaCommand(
      "extensions.load('taxiDriverTelemetry'); " ..
      "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry." ..
      (enabled and "startPickupHonk()" or "stopPickupHonk()") .. " end"
    )
  end
end

local function passengerInsideTaxi(taxi, position)
  if not taxi or not position or type(taxi.getSpawnWorldOOBB) ~= "function" then return false end
  local ok, inside = pcall(function()
    local box = taxi:getSpawnWorldOOBB()
    local relative, half = position - box:getCenter(), box:getHalfExtents()
    local extents = {half.x, half.y, half.z}
    for axis = 0, 2 do
      if math.abs(relative:dot(box:getAxis(axis))) > extents[axis + 1] + 0.45 then return false end
    end
    return true
  end)
  return ok and inside == true
end

function M.new()
  local service = {
    objectId = nil,
    kind = nil,
    ready = true,
    aiHold = false,
    following = false,
    elapsed = 0,
    commandTimer = 0,
    stopStableTimer = 0,
    hornLatched = false, hornStage = 0, hornTimer = 0, hornTaxiId = nil,
    fallback = false
  }

  function service:clear(preserveAiHold)
    local aiHold = preserveAiHold == true and self.aiHold == true
    local object = objectById(self.objectId)
    setHorn(objectById(self.hornTaxiId), false)
    stopWalker(object)
    safeDelete(self.objectId)
    self.objectId, self.kind = nil, nil
    self.ready, self.aiHold, self.following, self.fallback = true, aiHold, false, false
    self.elapsed, self.commandTimer, self.stopStableTimer, self.hornLatched = 0, 0, 0, false
    self.hornStage, self.hornTimer, self.hornTaxiId = 0, 0, nil
  end

  function service:start(order)
    self:clear()
    if type(order) ~= "table" or not order.pickup or not order.pickup.pos then return false end
    if not order.isDelivery and order.randomEvent and
      order.randomEvent.kind == "passengerNoShow" then
      self.kind, self.ready = "noShow", false
      return true
    end
    local direction = order.pickup.dir or vec3(0, 1, 0)
    local rotation = type(quatFromDir) == "function" and
      quatFromDir(direction, vec3(0, 0, 1)) or quat(0, 0, 0, 1)
    local object
    if order.isDelivery then
      object = spawn("cardboard_box", "/vehicles/cardboard_box/small.pc",
        order.pickup.pos, rotation)
      self.kind = "cargo"
    else
      object = spawn("unicycle", "/vehicles/unicycle/with_mesh.pc",
        order.pickup.pos, rotation)
      self.kind = "passenger"
    end
    if not object then
      self.ready, self.fallback = true, true
      return false
    end
    self.objectId = object:getID()
    self.ready, self.following = false, false
    return true
  end

  function service:isReady()
    return self.ready == true
  end

  function service:isAiHold()
    return self.aiHold == true
  end

  function service:beginAiPickup(taxi)
    if self.ready or self.aiHold or self.kind ~= "passenger" or not taxi then return false end
    self.aiHold = true
    self.stopStableTimer = 0
    self.hornStage, self.hornTimer, self.hornTaxiId = -1, 0, taxi:getID()
    setHorn(taxi, false)
    logger.info("physicalPickup", "ai_pickup_arrival_latched", {
      taxiId = taxi:getID(), hornStage = self.hornStage
    })
    return true
  end

  function service:update(taxi, telemetry, dt, speedKmh)
    if self.ready or self.kind == "noShow" then return nil end
    local object = objectById(self.objectId)
    if not object then
      self.objectId = nil
      self.ready, self.fallback = true, true
      return "ready"
    end
    if not taxi then self.fallback = true; self:clear(); return "ready" end
    local objectPosition = object:getPosition()
    local distance = objectPosition:distance(taxi:getPosition())
    if self.kind == "cargo" then
      if distance <= 9 then
        self.ready = true
        self:clear(true)
        return "ready"
      end
      return nil
    end

    speedKmh = math.max(0, tonumber(speedKmh) or 0)
    local delta = math.max(0, tonumber(dt) or 0)
    if self.hornStage == -1 then
      self.stopStableTimer = speedKmh <= 0.2 and
        self.stopStableTimer + delta or 0
      if self.stopStableTimer >= 0.25 then
        self.hornStage, self.hornTimer = 1, 0
        setHorn(taxi, true)
        logger.info("physicalPickup", "ai_pickup_honk_started", {
          taxiId = taxi:getID(), stopStableSeconds = self.stopStableTimer
        })
      end
    end
    if speedKmh >= 4 and passengerInsideTaxi(taxi, objectPosition) then
      self:clear()
      return "passengerHit"
    end

    if self.hornStage > 0 then
      self.hornTimer = self.hornTimer + delta
      if self.hornStage == 1 and self.hornTimer >= 0.6 then
        self.hornStage, self.hornTimer = 2, self.hornTimer - 0.6
      elseif self.hornStage == 2 and self.hornTimer >= 0.2 then
        self.hornStage, self.hornTimer = 3, self.hornTimer - 0.2
      elseif self.hornStage == 3 and self.hornTimer >= 0.6 then
        self.hornStage, self.hornTimer = 4, 0
        setHorn(taxi, false)
        logger.info("physicalPickup", "ai_pickup_honk_finished", {
          taxiId = taxi:getID()
        })
      end
    end

    local horn = telemetry and telemetry.horn == true or self.hornStage == 1 or self.hornStage == 3
    if horn and not self.hornLatched and not self.following and distance <= 18 then
      self.following, self.elapsed = true, 0
      self.hornLatched = true
      return "hornAccepted"
    elseif not horn then
      self.hornLatched = false
    end
    if not self.following then return nil end

    self.elapsed = self.elapsed + delta
    self.commandTimer = self.commandTimer + delta
    if (distance <= 2.6 and (self.hornStage == 0 or self.hornStage >= 4)) or self.elapsed >= 14 then
      self.ready = true
      self:clear(true)
      logger.info("physicalPickup", "passenger_boarding_completed")
      return "ready"
    end
    if self.commandTimer < 0.25 then return nil end
    self.commandTimer = self.commandTimer - 0.25

    local from = object:getPosition()
    local taxiDirection = taxi:getDirectionVector()
    local right = vec3(taxiDirection.y, -taxiDirection.x, 0)
    local target = taxi:getPosition() + right * 1.4
    local direction = (target - from):z0()
    if direction:length() <= 0.01 then return nil end
    direction:normalize()
    local rotation = type(quatFromDir) == "function" and
      quatFromDir(direction, vec3(0, 0, 1)) or quat(0, 0, 0, 1)
    object:queueLuaCommand(
      "local c=controller.getControllerSafe('playerController'); " ..
      "if c then c.setCameraControlData(" ..
      serialize({cameraRotation = rotation}) ..
      "); c.setSpeedCoef(0); c.walkUpDownRaw(1); c.walkLeftRightRaw(0) end"
    )
    return nil
  end

  return service
end

return M
