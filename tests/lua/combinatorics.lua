package.path = "lua/ge/extensions/?.lua;" .. package.path

local tripEvents = dofile("lua/ge/extensions/taxiDriver/tripEvents.lua")
local shiftTracker = dofile("lua/ge/extensions/taxiDriver/shiftTracker.lua")
local offerGenerator = dofile("lua/ge/extensions/taxiDriver/offerGenerator.lua")
local hudPublisher = dofile("lua/ge/extensions/taxiDriver/hudPublisher.lua")
local vehicleScanGuard = dofile("lua/ge/extensions/taxiDriver/vehicleScanGuard.lua")
local vehicleControl = dofile("lua/ge/extensions/taxiDriver/vehicleControl.lua")
local delivery = dofile("lua/ge/extensions/taxiDriver/delivery.lua")

local logLines = {}
log = function(level, tag, message)
  logLines[#logLines + 1] = {level = level, tag = tag, message = message}
end
local debugLogging = true
local debugLogger = dofile("lua/ge/extensions/taxiDriver/logger.lua")
debugLogger.setEnabledProvider(function() return debugLogging end)
debugLogger.info("test", "enabled", {value = 1})
assert(#logLines == 1 and logLines[1].message:find("[TaxiDriver]", 1, true))
debugLogging = false
debugLogger.info("test", "disabled")
assert(#logLines == 1)
debugLogger.warn("test", "warning_visible")
assert(#logLines == 2 and logLines[2].level == "W")

math.randomseed(240717)

local orderTypes = {
  {name = "passenger", delivery = false, rush = false, multi = false},
  {name = "rush", delivery = false, rush = true, multi = false},
  {name = "multiStop", delivery = false, rush = false, multi = true},
  {name = "delivery", delivery = true, rush = false, multi = false}
}

for _, realistic in ipairs({false, true}) do
  for _, eventsEnabled in ipairs({false, true}) do
    for _, order in ipairs(orderTypes) do
      for _ = 1, 250 do
        local event = eventsEnabled and
          tripEvents.create(order.delivery, order.rush, order.multi) or {kind = "none"}
        assert(type(event) == "table" and type(event.kind) == "string")
        if not eventsEnabled then assert(event.kind == "none") end
        if order.delivery then
          assert(event.kind == "none" or event.kind == "fragileCargo")
        elseif order.rush or order.multi then
          assert(event.kind == "none" or event.kind == "cancellation" or event.kind == "tip")
        end
        if tripEvents.needsTarget(event) then
          assert(not order.delivery and not order.rush and not order.multi)
          event.target = {routeDistance = 1200}
          assert(tripEvents.shouldTriggerOnRoute(event, event.triggerProgress or 1))
          assert(not tripEvents.shouldTriggerOnRoute(event, 1))
        end
      end
      assert(realistic == true or realistic == false)
    end
  end
end

local cancellation = {kind = "cancellation", triggerSeconds = 2, elapsed = 0}
assert(not tripEvents.updateBeforePickup(cancellation, 1))
assert(tripEvents.updateBeforePickup(cancellation, 1))
assert(not tripEvents.updateBeforePickup(cancellation, 10))

assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0, false) == 2)
assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0.1, false) == 0)
assert(tripEvents.calculateTip({kind = "tip", condition = "quick", rate = 0.1}, 20, 0, true) == 2)

local shifts = shiftTracker.new(nil)
shifts:start()
shifts:recordRide(20, 4.5, 2)
shifts:recordFuelCost(3)
local completed = shifts:finish()
assert(completed.rides == 1)
assert(completed.grossIncome == 20)
assert(completed.netIncome == 17)
assert(completed.averageRating == 4.5)
assert(not shifts:getHud().active)
shifts:setAllRatings(3.25)
assert(shifts:getHud().last.averageRating == 3.25)
assert(shifts:getHud().last.ratingTotal == 3.25)

local published = {}
local function encode(value)
  local keys = {}
  for key, _ in pairs(value or {}) do table.insert(keys, tostring(key)) end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(value[key])) end
  return table.concat(parts, ";")
end
local function trigger(name, payload)
  table.insert(published, {name = name, payload = payload})
end
local hudState = {active = true, currentSpeed = 20, settings = {language = "en"}}
hudPublisher.publishFull(hudState, trigger, encode)
assert(#published == 1 and published[1].name == "TaxiDriverHUDState")
local hudEpoch = published[1].payload.hudEpoch
assert(type(hudEpoch) == "string" and hudEpoch ~= "")
assert(published[1].payload.hudRevision == 1)
assert(not hudPublisher.publishPatch(hudState, trigger, encode))
hudState.currentSpeed = 21
assert(hudPublisher.publishPatch(hudState, trigger, encode))
assert(#published == 2 and published[2].name == "TaxiDriverHUDPatch")
assert(published[2].payload.values.currentSpeed == 21)
assert(published[2].payload.epoch == hudEpoch)
assert(published[2].payload.baseRevision == 1)
assert(published[2].payload.revision == 2)
assert(hudPublisher.clientNeedsSync(hudEpoch, 1))
assert(not hudPublisher.clientNeedsSync(hudEpoch, 2))
hudState.settings.language = "de"
assert(not hudPublisher.publishPatch(hudState, trigger, encode))

for _ = 1, 10000 do
  local job = offerGenerator.create(function()
    error("synthetic late next-offer failure")
  end, 0)
  local status, errorMessage = offerGenerator.step(job, 1)
  assert(status == "error")
  assert(tostring(errorMessage):find("synthetic late next-offer failure", 1, true))
end

local vehicleCommands = {}
local commandVehicle = {queueLuaCommand = function(_, command)
  table.insert(vehicleCommands, command)
end}
vehicleControl.setTelemetryEnabled(commandVehicle, true)
vehicleControl.setTelemetryEnabled(commandVehicle, false)
delivery.applyVehicleMass(commandVehicle, 75)
delivery.applyVehicleMass(commandVehicle, 0)
assert(vehicleCommands[1]:find("extensions.load('taxiDriverTelemetry')", 1, true))
assert(vehicleCommands[2]:find("extensions.unload('taxiDriverTelemetry')", 1, true))
assert(vehicleCommands[3]:find("extensions.load('taxiDriverCargo')", 1, true))
assert(vehicleCommands[4]:find("extensions.unload('taxiDriverCargo')", 1, true))
local telemetryExtension = dofile("lua/vehicle/extensions/taxiDriverTelemetry.lua")
telemetryExtension.onReset()

local detailLookups = 0
local position = {x = 0, y = 0, z = 0}
function position:distance() return 0 end
local vehicle = {
  jbeam = "etk800",
  partConfig = "/vehicles/etk800/base.pc"
}
function vehicle:getID() return 42 end
function vehicle:getPosition() return position end
be = {getPlayerVehicle = function() return vehicle end}
FS = {
  fileExists = function() return false end,
  directoryExists = function() return true end,
  directoryCreate = function() end
}
jsonWriteFile = function() end
vec3 = function(x, y, z)
  local value = {x = x, y = y, z = z}
  function value:distance() return 0 end
  return value
end
core_vehicles = {
  getVehicleDetails = function()
    detailLookups = detailLookups + 1
    return {
      model = {Brand = "ETK", Name = "800 Series"},
      configs = {Name = "854t"},
      current = {config_key = "base"}
    }
  end
}
local vehicleHistory = dofile("lua/ge/extensions/taxiDriver/vehicleHistory.lua")
vehicleHistory.load("test")
assert(vehicleHistory.refreshCurrentVehicle())
local originalKey = vehicleHistory.getCurrentHud().key
vehicle.partConfig = "/vehicles/etk800/live_parts_edit.pc"
for _ = 1, 500 do
  vehicleHistory.onVehicleReset(42)
  assert(not vehicleHistory.update(0.016, 0))
  assert(vehicleHistory.getCurrentHud().key == originalKey)
end
assert(detailLookups == 1)

assert(not vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.onUiChangedState("menu.vehicleconfig.parts", "play"))
local staleGeneration = vehicleScanGuard.getGeneration()
assert(vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.isConfigurationOpen())
for _ = 1, 500 do
  vehicleScanGuard.update(0.016)
  assert(vehicleScanGuard.isSuspended())
end
assert(vehicleScanGuard.onUiChangedState("play", "menu.vehicleconfig.parts"))
assert(vehicleScanGuard.isSuspended())
assert(not vehicleScanGuard.isConfigurationOpen())
assert(not vehicleScanGuard.isRequestCurrent(staleGeneration))
for _ = 1, 93 do vehicleScanGuard.update(0.016) end
assert(vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.update(0.016))
assert(not vehicleScanGuard.isSuspended())
local stableGeneration = vehicleScanGuard.getGeneration()
assert(vehicleScanGuard.isRequestCurrent(stableGeneration))
assert(vehicleScanGuard.onVehicleLifecycle(42, 42))
assert(vehicleScanGuard.isSuspended())
assert(not vehicleScanGuard.onVehicleLifecycle(7, 42))

print("TaxiDriver Lua combinatorics: gameplay modes, lazy vehicle extensions, and 500 deferred respawns passed")
