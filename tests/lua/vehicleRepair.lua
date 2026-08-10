local vehicleRepair = dofile("lua/ge/extensions/taxiDriver/vehicleRepair.lua")

local callOrder = {}
local pose = {x = 1, y = 2, z = 3}
local rotation = {x = 0, y = 0, z = 0, w = 1}
local vehicle = {
  getPosition = function() return pose end,
  getDirectionVector = function() return {x = 0, y = 1, z = 0} end,
  getDirectionVectorUp = function() return {x = 0, y = 0, z = 1} end,
  resetBrokenFlexMesh = function() callOrder[#callOrder + 1] = "flex" end
}

local repaired, reason = vehicleRepair.repairInPlace(vehicle, {
  quatFromDir = function() return rotation end,
  spawn = {safeTeleport = function(actualVehicle, position, actualRotation,
      _, _, _, _, resetVehicle)
    assert(actualVehicle == vehicle)
    assert(position == pose and actualRotation == rotation)
    assert(resetVehicle == true)
    callOrder[#callOrder + 1] = "teleport"
  end}
})
assert(repaired and reason == nil)
assert(callOrder[1] == "flex" and callOrder[2] == "teleport")

local failed, failureReason = vehicleRepair.repairInPlace(vehicle, {
  quatFromDir = function() return rotation end,
  spawn = {safeTeleport = function() error("expected test failure") end}
})
assert(not failed and failureReason:find("expected test failure", 1, true))

assert(not vehicleRepair.repairInPlace(nil, {}))
assert(not vehicleRepair.repairInPlace(vehicle, {spawn = {}}))

print("TaxiDriver in-place vehicle repair regression passed")
