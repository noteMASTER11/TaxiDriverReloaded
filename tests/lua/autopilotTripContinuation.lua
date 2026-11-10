package.path = "lua/ge/extensions/?.lua;" .. package.path
package.loaded["taxiDriver/aiDriverRoute"] = nil
local requests = {}
package.preload["taxiDriver/aiDriverRoute"] = function() return {new = function() return {
  request = function(_, _, target, revision, callback)
    requests[#requests + 1] = target.pos.x
    callback(true, {path = {"a", "b"}, routeRevision = revision})
    return true
  end,
  cancel = function() end
} end} end
log = function() end
local position = {x = 0, y = 0, z = 0}
local telemetry, commands = {}, {}
local vehicle = {
  getID = function() return 42 end,
  getPosition = function() return position end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) commands[#commands + 1] = command end
}
getObjectByID = function(id) return id == 42 and vehicle or nil end
local phases = {toPickup = "pickup", toStop = "stop", toDestination = "destination",
  toFuelStation = "fuel", boarding = "boarding"}
local pickup = {pos = {x = 100, y = 0, z = 0}}
local destination = {pos = {x = 500, y = 0, z = 0}}
local module = dofile("lua/ge/extensions/taxiDriver/autopilot.lua")
local function parkedPickup()
  position, telemetry = {x = 0, y = 0, z = 0}, {}
  local service = module.new({phases = phases, getSpeedKmh = function() return 0 end,
    getSafetyObservation = function() return telemetry end})
  assert(service:enable(vehicle, phases.toPickup, pickup))
  position = {x = 94, y = 0, z = 0}
  service:update(vehicle, phases.toPickup, pickup, 0.1)
  telemetry = {parked = true}
  service:update(vehicle, phases.toPickup, pickup, 0.1)
  assert(service:isParked() and not service:isEnabled())
  return service
end

local service = parkedPickup()
local pickupSession = service:getDiagnostics().sessionId
local afterPickup = #requests
service:suspend(vehicle, true)
service:update(vehicle, phases.boarding, nil, 2)
assert(#requests == afterPickup, "boarding must hold the confirmed pickup parking")
service:suspend(vehicle, false)
service:update(vehicle, phases.toDestination, destination, 0.1)
assert(service:isEnabled() and #requests == afterPickup + 1 and requests[#requests] == 500,
  "the passenger leg must resume AI after the pickup parking handshake")
local resumed = service:getDiagnostics()
assert(resumed.sessionId ~= pickupSession and resumed.phase == phases.toDestination and
  resumed.targetKey:find("destination|", 1, true) == 1 and not resumed.routeDone,
  "continuation must create a fresh route for the destination, clearing the pickup state")

local cancelled = parkedPickup()
cancelled:disable(vehicle, "driver")
local beforeCancelled = #requests
cancelled:update(vehicle, phases.toDestination, destination, 0.1)
assert(not cancelled:isEnabled() and #requests == beforeCancelled,
  "an explicit driver disable while boarding must cancel automatic continuation")
local featureOff = parkedPickup()
featureOff:configure({enabled = false})
local beforeFeatureOff = #requests
featureOff:update(vehicle, phases.toDestination, destination, 0.1)
assert(not featureOff:isEnabled() and #requests == beforeFeatureOff and
  not featureOff:enable(vehicle, phases.toDestination, destination),
  "disabling the AI feature during boarding must cancel continuation and reject new enables")

position, telemetry = {x = 0, y = 0, z = 0}, {}
local parkingOff = module.new({phases = phases, getSpeedKmh = function() return 0 end,
  getSafetyObservation = function() return telemetry end})
assert(parkingOff:enable(vehicle, phases.toPickup, pickup))
position = {x = 94, y = 0, z = 0}
parkingOff:update(vehicle, phases.toPickup, pickup, 0.1)
parkingOff:configure({enabled = false})
telemetry = {parked = true}
parkingOff:update(vehicle, phases.toPickup, pickup, 0.1)
local beforeParkingOff = #requests
parkingOff:update(vehicle, phases.toDestination, destination, 0.1)
assert(not parkingOff:isEnabled() and #requests == beforeParkingOff and
  not parkingOff:getDiagnostics().continuationPending,
  "parking acknowledgement must not recreate continuation after the feature was disabled")
local toggledOff = parkedPickup()
assert(toggledOff:toggle(vehicle, phases.boarding, nil) == false)
local beforeToggle = #requests
toggledOff:update(vehicle, phases.toDestination, destination, 0.1)
assert(not toggledOff:isEnabled() and #requests == beforeToggle,
  "a driver toggle while parked for boarding must cancel continuation")

local changedVehicle = parkedPickup()
local replacement = {getID = function() return 43 end}
local beforeChange = #requests
changedVehicle:update(replacement, phases.toDestination, destination, 0.1)
changedVehicle:update(vehicle, phases.toDestination, destination, 0.1)
assert(not changedVehicle:isEnabled() and #requests == beforeChange,
  "changing vehicles must cancel the parked session's pending continuation")

local abandoned = parkedPickup()
local beforeAbandoned = #requests
abandoned:update(vehicle, "searching", nil, 0.1)
abandoned:update(vehicle, phases.toDestination, destination, 0.1)
assert(not abandoned:isEnabled() and #requests == beforeAbandoned,
  "ending the order during boarding must cancel its pending AI continuation")

local completed = parkedPickup()
completed:update(vehicle, phases.toDestination, destination, 0.1)
position, telemetry = {x = 494, y = 0, z = 0}, {}
completed:update(vehicle, phases.toDestination, destination, 0.1)
telemetry = {parked = true}
completed:update(vehicle, phases.toDestination, destination, 0.1)
local beforeNewOrder = #requests
completed:update(vehicle, phases.toPickup, pickup, 0.1)
assert(completed:isParked() and not completed:isEnabled() and #requests == beforeNewOrder,
  "destination parking must remain terminal until the driver enables AI again")

-- A pause can end on a new target. Do not send the old route before update()
-- has supplied the current phase and destination.
position, telemetry = {x = 0, y = 0, z = 0}, {}
local paused = module.new({phases = phases, getSpeedKmh = function() return 0 end})
assert(paused:enable(vehicle, phases.toPickup, pickup))
paused:suspend(vehicle, true)
local beforeResume = #requests
paused:suspend(vehicle, false)
assert(#requests == beforeResume, "resume must wait for the current target before replanning")
paused:update(vehicle, phases.toDestination, destination, 0.1)
assert(#requests == beforeResume + 1 and requests[#requests] == 500,
  "resume must issue only the new destination route")
print("PASS AI pickup boarding destination continuation and explicit cancellation")
