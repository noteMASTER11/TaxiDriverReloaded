-- Lazy-loaded physical cargo mass for TaxiDriver deliveries. The added mass is
-- distributed across stable body nodes while avoiding wheel and energy-storage
-- nodes whose mass is managed dynamically by BeamNG.
local M = {}

local cargoMassKg = 0
local cargoNodes = nil

local function collectDynamicMassNodes()
  local excluded = {}
  if energyStorage and type(energyStorage.getStorages) == "function" then
    for _, storage in pairs(energyStorage.getStorages() or {}) do
      for nodeId in pairs(storage.fuelNodes or {}) do excluded[nodeId] = true end
      for nodeId in pairs(storage.nodes or {}) do excluded[nodeId] = true end
    end
  end
  return excluded
end

local function buildCargoNodes()
  local excluded = collectDynamicMassNodes()
  local result = {}
  for _, node in pairs(v.data.nodes or {}) do
    if type(node.cid) == "number" and obj:getNodeMass(node.cid) > 0 and
      node.wheelID == nil and node.cargoGroup == nil and not excluded[node.cid] then
      table.insert(result, node.cid)
    end
  end

  -- Very unusual vehicles may expose only wheel or special-purpose nodes. Keep
  -- deliveries functional by falling back to every non-dynamic positive node.
  if not result[1] then
    for _, node in pairs(v.data.nodes or {}) do
      if type(node.cid) == "number" and obj:getNodeMass(node.cid) > 0 and
        not excluded[node.cid] then
        table.insert(result, node.cid)
      end
    end
  end
  cargoNodes = result
end

local function setCargoMass(value)
  local target = math.max(0, math.min(1000, tonumber(value) or 0))
  local delta = target - cargoMassKg
  if math.abs(delta) < 0.001 then return end
  if not cargoNodes then buildCargoNodes() end
  if not cargoNodes[1] then
    cargoMassKg = 0
    return
  end

  local perNode = delta / #cargoNodes
  for _, nodeId in ipairs(cargoNodes) do
    obj:setNodeMass(nodeId, math.max(0.01, obj:getNodeMass(nodeId) + perNode))
  end
  cargoMassKg = target
end

local function onReset()
  -- BeamNG restores the base node masses before vehicle extensions receive the
  -- reset hook, so no subtractive cleanup is necessary here.
  cargoMassKg = 0
  cargoNodes = nil
end

M.setCargoMass = setCargoMass
M.onReset = onReset

return M
