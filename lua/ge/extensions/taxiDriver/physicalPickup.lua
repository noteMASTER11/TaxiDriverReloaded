-- Optional physical cargo prop. Passenger pickup is intentionally logical:
-- reaching the configured pickup radius is enough to begin boarding.
local M = {}

local function objectById(id)
  return type(getObjectByID) == "function" and getObjectByID(tonumber(id) or -1) or nil
end

local function safeDelete(id)
  local object = objectById(id)
  if object and type(object.delete) == "function" then pcall(object.delete, object) end
end

local function spawnCargo(position, rotation)
  if not core_vehicles or type(core_vehicles.spawnNewVehicle) ~= "function" or not position then
    return nil
  end
  local ok, object = pcall(core_vehicles.spawnNewVehicle, "cardboard_box", {
    config = "/vehicles/cardboard_box/small.pc",
    pos = position,
    rot = rotation or quat(0, 0, 0, 1),
    cling = true,
    autoEnterVehicle = false
  })
  if not ok or not object then return nil end
  object.playerUsable = false
  object.taxiDriverIgnoreObstacle = true
  object:queueLuaCommand("if mapmgr then mapmgr.disableTracking() end")
  return object
end

function M.new()
  local service = {objectId = nil, ready = true, fallback = false}

  function service:clear()
    safeDelete(self.objectId)
    self.objectId = nil
    self.ready = true
    self.fallback = false
  end

  function service:start(order)
    self:clear()
    if type(order) ~= "table" or order.isDelivery ~= true or
      not order.pickup or not order.pickup.pos then return false end
    local direction = order.pickup.dir or vec3(0, 1, 0)
    local rotation = type(quatFromDir) == "function" and
      quatFromDir(direction, vec3(0, 0, 1)) or quat(0, 0, 0, 1)
    local object = spawnCargo(order.pickup.pos, rotation)
    if not object then self.fallback = true; return false end
    self.objectId = object:getID()
    self.ready = false
    return true
  end

  function service:isReady()
    return self.ready == true
  end

  function service:update(taxi)
    if self.ready then return nil end
    local object = objectById(self.objectId)
    if not object or not taxi then
      self.fallback = true
      self:clear()
      return "ready"
    end
    if object:getPosition():distance(taxi:getPosition()) <= 9 then
      self:clear()
      return "ready"
    end
    return nil
  end

  return service
end

return M
