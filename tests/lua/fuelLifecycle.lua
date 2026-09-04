package.path = "lua/ge/extensions/?.lua;" .. package.path
log = function() end
FS = {fileExists = function() return false end, directoryExists = function() return true end}
jsonWriteFile = function() end
local fuel = require("taxiDriver/fuelPersistence")
fuel.load()
-- Exercise the production orchestrator's asynchronous initializer, with the
-- engine bridge as the boundary; no source-text assertions.
local file = assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua", "r"))
local source = file:read("*a"); file:close()
local initialize = assert(source:match("(function realisticFuel.initializeVehicle.-)\nfunction realisticFuel.updateStation"))
local pending, rejected, writes = nil, nil, {}
local vehicle = {jbeam = "etki", partConfig = "vehicles/etki/2400_A.pc", getID = function() return 42 end}
local env = setmetatable({
  realisticFuel = {persistence = fuel, config = {electricInitialLevel = 0.2},
    initializedVehicles = {}, initializationPending = {}, deferDashboardEnergy = function() end},
  state = {active = true, realisticMode = true, activeVehicleId = 42},
  userSettings = {initialFuelPercent = 25},
  showPhoneNotification = function() end,
  vehicleBridgeGuard = {
    request = function(_, _, callback, onRejected) pending, rejected = callback, onRejected end,
    execute = function(_, _, name, value) writes[name] = value; return true end
  }
}, {__index = _G})
local chunk = assert(loadstring(initialize)); setfenv(chunk, env); chunk()
local tanks = {{name = "tank", energyType = "gasoline", maxEnergy = 1000, currentEnergy = 1000}}
env.realisticFuel.initializeVehicle(vehicle)
pending({tanks}, vehicle)
assert(writes.tank == 250, "first shift must use selected 25%")
tanks[1].currentEnergy = 500
fuel.capture(fuel.vehicleKey(vehicle), tanks)
env.realisticFuel.initializedVehicles = {}
writes = {}
env.realisticFuel.initializeVehicle(vehicle)
pending({tanks}, vehicle)
assert(writes.tank == 500, "next session must restore paid fuel")

env.realisticFuel.initializedVehicles = {}
writes = {}
env.realisticFuel.initializeVehicle(vehicle)
env.state.active = false
pending({tanks}, vehicle)
assert(next(writes) == nil, "ending shift before callback must prevent late tank mutation")
env.state.active = true
env.realisticFuel.initializeVehicle(vehicle)
vehicle.partConfig = "vehicles/etki/3000.pc"
pending({tanks}, vehicle)
assert(next(writes) == nil, "replacement config cannot receive previous car's fuel")

env.realisticFuel.initializeVehicle(vehicle)
local oldRejection = rejected
env.realisticFuel.initializationPending = {}
env.realisticFuel.initializeVehicle(vehicle)
local currentRequest = env.realisticFuel.initializationPending[42]
oldRejection()
assert(env.realisticFuel.initializationPending[42] == currentRequest,
  "a stale rejection must not clear a newer initialization")

env.vehicleScanGuard = {onVehicleSwitched = function() end, isConfigurationOpen = function() return true end}
env.notifyHud = function() end
env.M = {}
local switched = assert(source:match("(function M.onVehicleSwitched.-)\nfunction M.onVehicleGroupSpawned"))
chunk = assert(loadstring(switched)); setfenv(chunk, env); chunk()
env.realisticFuel.initializedVehicles[42] = fuel.vehicleKey(vehicle)
env.M.onVehicleSwitched(42, 42)
assert(env.realisticFuel.initializedVehicles[42] == nil and env.realisticFuel.initializationPending[42] == nil,
  "same-ID replacement inside the selector must invalidate saved-VM ownership before early return")
print("TaxiDriver asynchronous fuel lifecycle regressions passed")
