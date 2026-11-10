package.path = "lua/ge/extensions/?.lua;" .. package.path

local file = assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local production = assert(source:match("(local function updatePickupDeadline.-)\nlocal function startPassengerLeg"))
local phases = {toPickup = "toPickup", toFuelStation = "toFuelStation", toDestination = "toDestination"}
local detour = {active = true, previousPhase = phases.toPickup, arrived = false}
local env = setmetatable({
  phases = phases,
  state = {phase = phases.toFuelStation},
  trip = {pickupTimeRemaining = 30},
  realisticFuel = {detour = detour, adjustPassengerMood = function() end},
  userSettings = {penaltyToggles = {pickupDelay = true}},
  balanceConfig = {pickupLateBasePenalty = 0.01, pickupLatePenaltyPerSecond = 0.001,
    maxPickupLatePenalty = 0.1, passengerMoodPickupLateLoss = 1, passengerMoodPickupLateStepLoss = 1},
  clampValue = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end,
  createPassengerPenaltyDisposition = function() return {ignored = false} end,
  applyPassengerPenalty = function(value) return value end,
  addPenaltyEvent = function() return {} end,
  showPhoneNotification = function() end
}, {__index = _G})
local chunk = assert(loadstring(production .. "\nreturn updatePickupDeadline"))
setfenv(chunk, env)
local update = chunk()

update(10)
assert(env.trip.pickupTimeRemaining == 20, "driving to fuel must consume the pickup deadline")
detour.arrived = true
update(25)
assert(env.trip.pickupTimeRemaining == 0 and env.trip.pickupLateSeconds == 5,
  "waiting at fuel must consume the deadline and charge only the overdue seconds")
assert(env.trip.pickupPenalty > 0, "the pickup delay penalty must still apply during the detour")

env.trip = {pickupTimeRemaining = 30}
env.userSettings.penaltyToggles.pickupDelay = false
update(10)
assert(env.trip.pickupTimeRemaining == 20 and not env.trip.pickupLate,
  "disabling the penalty must leave the pickup countdown running")

env.userSettings.penaltyToggles.pickupDelay = true
detour.previousPhase = phases.toDestination
update(10)
assert(env.trip.pickupTimeRemaining == 20, "a passenger ride detour must not consume a pickup deadline")
detour.previousPhase = phases.toPickup
detour.active = false
update(10)
assert(env.trip.pickupTimeRemaining == 20, "an inactive detour must not impersonate pickup")
env.state.phase = phases.toPickup
update(5)
assert(env.trip.pickupTimeRemaining == 15, "normal pickup must continue counting down")
env.trip.isDelivery = true
update(5)
assert(env.trip.pickupTimeRemaining == 15, "delivery orders have no passenger pickup deadline")

print("TaxiDriver pickup deadline detour regressions passed")
