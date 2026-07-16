local M = {}

function M.getSpeedKmh(vehicle)
  return vehicle and vehicle:getVelocity():length() * 3.6 or 0
end

function M.setTelemetryEnabled(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format(
    "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry.setEnabled(%s) end",
    enabled and "true" or "false"
  ))
end

function M.setForcedStop(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format(
    "if extensions.taxiDriverTelemetry then extensions.taxiDriverTelemetry.setForcedStop(%s) end",
    enabled and "true" or "false"
  ))
end

function M.setFrozen(vehicle, enabled)
  if not vehicle then return end
  vehicle:queueLuaCommand(string.format("controller.setFreeze(%d)", enabled and 1 or 0))
end

function M.releaseForcedStop(vehicle)
  M.setFrozen(vehicle, false)
  M.setForcedStop(vehicle, false)
end

function M.toggleAccess(vehicle, preferredTriggerId, accessType)
  if not vehicle or not extensions.core_vehicle_manager or not core_vehicleTriggers then return nil end

  local vehicleId = vehicle:getID()
  local vehicleData = extensions.core_vehicle_manager.getVehicleData(vehicleId)
  local vdata = vehicleData and vehicleData.vdata or nil
  if not vdata or type(vdata.triggers) ~= "table" or
    type(vdata.triggerEventLinksDict) ~= "table" then return nil end

  local selectedId = nil
  local selectedScore = -1
  for _, trigger in pairs(vdata.triggers) do
    local triggerId = trigger.abid
    local links = triggerId and vdata.triggerEventLinksDict[triggerId] or nil
    local name = string.lower(tostring(trigger.name or trigger.id or ""))

    if preferredTriggerId and triggerId == preferredTriggerId and links and links.action0 then
      selectedId = triggerId
      break
    end

    local score = -1
    if links and links.action0 and accessType == "cargo" then
      if string.find(name, "trunk", 1, true) then score = 130
      elseif string.find(name, "tailgate", 1, true) then score = 125
      elseif string.find(name, "liftgate", 1, true) then score = 120
      elseif string.find(name, "hatch", 1, true) then score = 115
      elseif string.find(name, "boot", 1, true) then score = 110
      elseif string.find(name, "frunk", 1, true) then score = 105
      elseif string.find(name, "cargo door", 1, true) then score = 100
      elseif string.find(name, "rear gate", 1, true) then score = 95
      elseif string.find(name, "rear door", 1, true) then score = 70
      end
    elseif links and links.action0 and string.find(name, "door", 1, true) and
      not string.find(name, "int", 1, true) and
      not string.find(name, "interior", 1, true) and
      not string.find(name, "cargo", 1, true) then
      score = 10
      if string.find(name, "rr", 1, true) or string.find(name, "rear right", 1, true) then
        score = 100
      elseif string.find(name, "rl", 1, true) or string.find(name, "rear left", 1, true) then
        score = 90
      elseif string.find(name, "fr", 1, true) or string.find(name, "front right", 1, true) then
        score = 70
      elseif string.find(name, "passenger", 1, true) then
        score = 60
      end
    end
    if score >= 0 and score > selectedScore then
      selectedScore = score
      selectedId = triggerId
    end
  end

  if not selectedId then return nil end
  local success = pcall(function()
    core_vehicleTriggers.triggerEvent("action0", 1, selectedId, vehicleId, vdata)
    core_vehicleTriggers.triggerEvent("action0", 0, selectedId, vehicleId, vdata)
  end)
  return success and selectedId or nil
end

function M.togglePassengerDoor(vehicle, preferredTriggerId)
  return M.toggleAccess(vehicle, preferredTriggerId, "passenger")
end

function M.toggleCargoAccess(vehicle, preferredTriggerId)
  return M.toggleAccess(vehicle, preferredTriggerId, "cargo")
end

return M
