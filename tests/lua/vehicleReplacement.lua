package.path = "lua/ge/extensions/?.lua;" .. package.path
log = function() end
local guard = require("taxiDriver/vehicleScanGuard")
local bridge = require("taxiDriver/vehicleBridgeGuard")
local vehicle = {getID = function() return 42 end}
getObjectByID = function() return vehicle end
local pending, writes, accepted, rejected = nil, 0, 0, nil
core_vehicleBridge = {
  requestValue = function(_, callback) pending = callback end,
  executeAction = function() writes = writes + 1 end
}

for _, menu in ipairs({"menu.vehicles", "menu.vehiclesnew", "menu.vehicleconfig.parts",
  "garage.vehicles", "garage.mycars", "garage.vehicle.parts"}) do
  guard.reset()
  assert(bridge.request(vehicle, "energyStorage", function() accepted = accepted + 1 end,
    function(reason) rejected = reason end))
  assert(guard.onUiChangedState(menu, "play"), menu .. " must suspend vehicle work")
  assert(guard.isSuspended())
  guard.update(10)
  assert(guard.isSuspended(), "menu must remain suspended regardless of time")
  assert(not bridge.execute(vehicle, "setEnergyStorageEnergy", "fuel", 100),
    "writes cannot bypass the vehicle replacement guard")
  assert(writes == 0)
  guard.onUiChangedState("play", menu)
  pending({fuel = 100})
  assert(accepted == 0 and rejected == "staleGeneration", "discard old VM response")
  assert(guard.isSuspended(), "replacement VM needs a settle period")
  guard.update(2)
  assert(not guard.isSuspended())
end

guard.reset()
assert(bridge.request(vehicle, "energyStorage", function() accepted = accepted + 1 end,
  function(reason) rejected = reason end))
assert(guard.onVehicleSwitched(42, 42), "a replaced VM may reuse its vehicle id")
guard.update(2)
pending({fuel = 100})
assert(accepted == 0 and rejected == "staleGeneration")
assert(bridge.execute(vehicle, "setEnergyStorageEnergy", "fuel", 100))
assert(writes == 1, "writes resume once the replacement is stable")

FS = {fileExists = function() return false end, directoryExists = function() return true end}
jsonWriteFile = function() end
vec3 = function(x, y, z) return {x = x, y = y, z = z} end
local history = require("taxiDriver/vehicleHistory")
local detailReads = 0
core_vehicles = {getVehicleDetails = function() detailReads = detailReads + 1; return {} end}
vehicle.jbeam, vehicle.partConfig = "etki", "vehicles/etki/2400_A.pc"
vehicle.getPosition = function() return {x = 0, y = 0, z = 0} end
be = {getPlayerVehicle = function() return vehicle end}
guard.reset()
history.load("test")
assert(history.getCurrentHud().key == "etki|2400_A")
local oldReads = detailReads
guard.onUiChangedState("menu.vehicles", "play")
vehicle.partConfig = "vehicles/etki/3000.pc"
vehicle.getID = function() return 43 end
history.getCurrentHud() -- notifyHud() is called during replacement too
assert(detailReads == oldReads, "HUD publishing must not bypass suspended vehicle scanning")
guard.onUiChangedState("play", "menu.vehicles")
guard.update(2)
assert(history.getCurrentHud().key == "etki|3000")
guard.onVehicleSwitched(43, 43)
vehicle.partConfig = "vehicles/etki/2400_A.pc"
guard.update(2)
assert(history.getCurrentHud().key == "etki|2400_A", "reused IDs must refresh identity after settling")
print("TaxiDriver vehicle replacement boundary regressions passed")
