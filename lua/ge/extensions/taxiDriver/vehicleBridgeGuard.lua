local vehicleScanGuard = require("taxiDriver/vehicleScanGuard")
local logger = require("taxiDriver/logger")

local M = {}

local function vehicleId(vehicle)
  if not vehicle or type(vehicle.getID) ~= "function" then return nil end
  local ok, value = pcall(vehicle.getID, vehicle)
  return ok and tonumber(value) or nil
end

local function reject(callback, reason)
  if type(callback) == "function" then pcall(callback, tostring(reason or "rejected")) end
end

function M.request(vehicle, valueName, callback, rejected)
  local requestedVehicleId = vehicleId(vehicle)
  if not requestedVehicleId then
    reject(rejected, "vehicleUnavailable")
    return false
  end
  if vehicleScanGuard.isSuspended() then
    reject(rejected, "vehicleScanSuspended")
    return false
  end
  if not core_vehicleBridge or type(core_vehicleBridge.requestValue) ~= "function" then
    reject(rejected, "vehicleBridgeUnavailable")
    return false
  end

  local scanGeneration = vehicleScanGuard.getGeneration()
  local ok, errorMessage = pcall(function()
    core_vehicleBridge.requestValue(vehicle, function(data)
      if scanGeneration ~= vehicleScanGuard.getGeneration() or
        not vehicleScanGuard.isRequestCurrent(scanGeneration) then
        reject(rejected, "staleGeneration")
        return
      end
      local currentVehicle = getObjectByID and getObjectByID(requestedVehicleId) or nil
      if not currentVehicle or vehicleId(currentVehicle) ~= requestedVehicleId then
        reject(rejected, "vehicleUnavailable")
        return
      end
      if type(callback) == "function" then
        local callbackOk, callbackError =
          pcall(callback, data, currentVehicle, requestedVehicleId)
        if not callbackOk then
          logger.error("vehicle_bridge", "callback_failed", {
            reason = tostring(callbackError), valueName = valueName,
            vehicleId = requestedVehicleId
          })
        end
      end
    end, valueName)
  end)
  if not ok then
    reject(rejected, errorMessage)
    return false
  end
  return true
end

function M.execute(vehicle, action, ...)
  if not vehicle or not core_vehicleBridge or
    type(core_vehicleBridge.executeAction) ~= "function" then return false end
  return pcall(core_vehicleBridge.executeAction, vehicle, action, ...)
end

return M
