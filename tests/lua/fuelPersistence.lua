package.path = "lua/ge/extensions/?.lua;" .. package.path
log = function() end
local config = require("taxiDriver/config")
local settingsStore = require("taxiDriver/persistence").new({taxiConfig = config})
assert(settingsStore:createDefaultSettings().initialFuelPercent == 5,
  "new settings must retain a 5% default")
for _, case in ipairs({{20, 20}, {1, 5}, {80, 30}, {15.6, 16}, {"bad", 5}}) do
  assert(settingsStore:sanitizeSettings({initialFuelPercent = case[1]}).initialFuelPercent == case[2])
end

local disk = {}
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end
FS = {fileExists = function(_, path) return disk[path] ~= nil end,
  directoryExists = function() return true end}
jsonWriteFile = function(path, data) disk[path] = copy(data) end
jsonReadFile = function(path) return copy(disk[path]) end
local fuel = require("taxiDriver/fuelPersistence")
local vehicle = {jbeam = "etki", partConfig = "vehicles/etki/2400_A.pc",
  getID = function() return 42 end}
local key = fuel.vehicleKey(vehicle)
assert(key and key ~= "")
local tanks = {
  {name = "mainTank", energyType = "gasoline", maxEnergy = 1000, currentEnergy = 1000},
  {name = "battery", energyType = "electricEnergy", maxEnergy = 2000, currentEnergy = 2000}
}
fuel.load()
local initial = fuel.plan(key, tanks, 20, 0.2)
assert(initial[1].currentEnergy == 200 and initial[2].currentEnergy == 400,
  "new fuel uses slider while initial EV charge keeps its own default")
fuel.capture(key, initial)
local purchased = copy(initial)
purchased[1].currentEnergy = 500
fuel.capture(key, purchased)
assert(fuel.flush())
-- A new mission/VM has a different runtime ID and a magically full tank.
vehicle.getID = function() return 900 end
fuel.load()
assert(fuel.vehicleKey(vehicle) == key)
local restored = fuel.plan(key, tanks, 5, 0.2)
assert(restored[1].currentEnergy == 500, "paid 50% must survive leaving/rejoining")
assert(restored[2].currentEnergy == 400)
fuel.capture(key, {{name = "mainTank", energyType = "gasoline", maxEnergy = 1000, currentEnergy = 0}})
assert(fuel.plan(key, tanks, 30, 0.2)[1].currentEnergy == 0, "empty must not mean missing")
assert(fuel.plan(key, {{name = "mainTank", energyType = "diesel", maxEnergy = 500, currentEnergy = 400}}, 10, 0.2)[1].currentEnergy == 50,
  "a changed storage type must not inherit incompatible saved fuel")

career_career = {isActive = function() return true end}
local profile = "Profile A"
career_saveSystem = {getCurrentProfile = function() return profile, "/saves/" .. profile end}
local inventoryId = 7
career_modules_inventory = {getInventoryIdFromVehicleId = function() return inventoryId end}
local careerKey = fuel.vehicleKey(vehicle)
assert(careerKey ~= key)
inventoryId = 8
assert(fuel.vehicleKey(vehicle) ~= careerKey, "same model in another inventory slot is another car")
inventoryId = 7
profile = "Profile B"
assert(fuel.vehicleKey(vehicle) ~= careerKey, "career profiles must remain independent")
profile = "Profile A"
assert(fuel.vehicleKey(vehicle) == careerKey)
inventoryId = nil
assert(fuel.vehicleKey(vehicle) == nil, "wait for career identity rather than draining an unknown vehicle")
print("TaxiDriver fuel persistence and initial fuel setting regressions passed")
