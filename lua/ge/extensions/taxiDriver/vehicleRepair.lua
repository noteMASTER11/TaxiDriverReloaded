local M = {}

local function dependency(options, name, fallback)
  if type(options) == "table" and options[name] ~= nil then return options[name] end
  return fallback
end

-- Mirrors BeamNG 0.39's own sandbox "Repair vehicle" action. Unlike
-- reloadVehicle(), this resets the existing physics object in place and does
-- not tear down/reconstruct the vehicle Lua VM.
function M.repairInPlace(vehicle, options)
  if not vehicle then return false, "vehicleMissing" end

  local spawnApi = dependency(options, "spawn", spawn)
  local makeRotation = dependency(options, "quatFromDir", quatFromDir)
  if type(spawnApi) ~= "table" or type(spawnApi.safeTeleport) ~= "function" then
    return false, "safeTeleportUnavailable"
  end
  if type(makeRotation) ~= "function" then return false, "quatFromDirUnavailable" end
  if type(vehicle.getPosition) ~= "function" or
    type(vehicle.getDirectionVector) ~= "function" or
    type(vehicle.getDirectionVectorUp) ~= "function" then
    return false, "vehiclePoseUnavailable"
  end

  local ok, result = pcall(function()
    local position = vehicle:getPosition()
    local rotation = makeRotation(
      vehicle:getDirectionVector(), vehicle:getDirectionVectorUp())
    if not position or not rotation then error("vehiclePoseUnavailable") end

    -- BeamNG's own quick-access repair performs both calls in this order.
    -- safeTeleport(..., true) restores the initial node positions and resets
    -- physics while retaining the current world pose.
    if type(vehicle.resetBrokenFlexMesh) == "function" then
      vehicle:resetBrokenFlexMesh()
    end
    spawnApi.safeTeleport(vehicle, position, rotation, nil, nil, nil, nil, true)
    return true
  end)
  if not ok then return false, tostring(result or "repairFailed") end
  if result == true then return true, nil end
  return false, "repairFailed"
end

return M
