local file = assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local production = assert(source:match("(function realisticFuel.resetRefueling.-)\nfunction realisticFuel.clearStation")) .. "\n" ..
  assert(source:match("(function realisticFuel.resetRepairing.-)\nfunction realisticFuel.clearRepairStation")) .. "\n" ..
  assert(source:match("(function realisticFuel.finishPurchase.-)\nfunction realisticFuel.updateRefueling")) .. "\n" ..
  assert(source:match("(function realisticFuel.repairVehiclePhysically.-)\nfunction realisticFuel.updateRepairing"))
local function noop() end
local function fixture()
  local calls = {fuel = 0, repair = 0, fuelCost = 0, repairCost = 0, requests = {}, notifications = {}}
  local vehicle = {getID = function() return 42 end}
  local fuel = {station = {id = "station"}, repairStation = {id = "station"},
    initializedVehicles = {}, refuelingCompletionId = 0, readableUnit = {gasoline = "L"},
    deferDashboardEnergy = noop, recordBalanceHistory = noop}
  local env = setmetatable({realisticFuel = fuel,
    state = {active = true, realisticMode = true, activeVehicleId = 42, balance = 120},
    be = {getPlayerVehicleID = function() return 42 end},
    getObjectByID = function() return vehicle end, getPlayerVehicle = function() return vehicle end,
    getVehicleSpeedKmh = function() return 0 end,
    roundMoney = function(value) return math.floor(value * 100 + 0.5) / 100 end,
    notifyHud = noop, logger = {info = noop, error = noop},
    showPhoneNotification = function(key) calls.notifications[#calls.notifications + 1] = key end,
    vehicleBridgeGuard = {
      execute = function() calls.fuel = calls.fuel + 1 end,
      request = function(_, _, callback, rejected)
        calls.requests[#calls.requests + 1] = {success = callback, rejected = rejected}
      end
    },
    vehicleRepair = {repairInPlace = function() calls.repair = calls.repair + 1; return true end},
    shiftTracking = {
      recordFuelCost = function(_, cost) calls.fuelCost = calls.fuelCost + cost end,
      recordRepairCost = function(_, cost) calls.repairCost = calls.repairCost + cost end
    }
  }, {__index = _G})
  local chunk = assert(loadstring(production)); setfenv(chunk, env); chunk()
  fuel.resetRefueling(); fuel.resetRepairing()
  local function beginFuel()
    fuel.refueling = {active = true, completing = false, vehicleId = 42, stationId = "station",
      cost = 80, quantity = 5, energyType = "gasoline", updates = {{name = "tank", energy = 500}}}
  end
  local function beginRepair()
    fuel.repairing = {active = true, completing = false, vehicleId = 42, stationId = "station", cost = 80}
  end
  return env, calls, beginFuel, beginRepair
end

do
  local env, calls, beginFuel = fixture()
  beginFuel()
  env.state.balance = env.state.balance - 100 -- a competing fleet purchase consumes the funds
  env.realisticFuel.finishPurchase()
  assert(calls.fuel == 0 and env.state.balance == 20 and calls.fuelCost == 0,
    "fuel must not be delivered after a competing purchase spends the balance")
  assert(not env.realisticFuel.refueling.active and calls.notifications[1] == "notify_realisticNoMoney")
  env.realisticFuel.finishPurchase()
  assert(calls.fuel == 0 and env.state.balance == 20, "repeated completion cannot revive a rejected purchase")
end
do
  local env, calls, beginFuel = fixture()
  beginFuel(); env.realisticFuel.finishPurchase(); env.realisticFuel.finishPurchase()
  assert(calls.fuel == 1 and calls.fuelCost == 80 and env.state.balance == 40,
    "an affordable fuel purchase must charge and deliver once")
  beginFuel(); env.realisticFuel.resetRefueling(); env.realisticFuel.finishPurchase()
  assert(calls.fuel == 1 and env.state.balance == 40, "cancelled fueling cannot complete")
end
do
  local env, calls, _, beginRepair = fixture()
  beginRepair(); env.state.balance = 20; env.realisticFuel.finishRepair()
  assert(#calls.requests == 0 and calls.repair == 0 and env.state.balance == 20,
    "an unaffordable repair must stop before starting the physical repair flow")
  assert(calls.notifications[1] == "notify_repairNoMoney" and not env.realisticFuel.repairing.active)
end
do
  local env, calls, _, beginRepair = fixture()
  beginRepair(); env.realisticFuel.finishRepair(); env.realisticFuel.finishRepair()
  assert(#calls.requests == 1, "repeated completion cannot queue duplicate repairs")
  env.state.balance = env.state.balance - 100
  calls.requests[1].success({{}})
  assert(calls.repair == 0 and calls.repairCost == 0 and env.state.balance == 20,
    "a competing purchase during the energy read must prevent the irreversible repair")
  assert(calls.notifications[1] == "notify_repairNoMoney" and not env.realisticFuel.repairing.active)
end
do
  local env, calls, _, beginRepair = fixture()
  beginRepair(); env.realisticFuel.finishRepair(); env.realisticFuel.resetRepairing()
  calls.requests[1].success({{}})
  assert(calls.repair == 0 and calls.repairCost == 0 and env.state.balance == 120,
    "cancelling a pending repair must prevent a late callback from repairing or charging")
end
do
  local env, calls, _, beginRepair = fixture()
  beginRepair(); env.realisticFuel.finishRepair(); env.realisticFuel.resetRepairing(); beginRepair()
  local replacement = env.realisticFuel.repairing
  calls.requests[1].rejected()
  assert(calls.repair == 0 and env.realisticFuel.repairing == replacement,
    "a stale callback cannot complete or cancel a replacement repair session")
  env.realisticFuel.finishRepair(); calls.requests[2].success({{}}); calls.requests[2].success({{}})
  assert(calls.repair == 1 and calls.repairCost == 80 and env.state.balance == 40,
    "an affordable asynchronous repair must apply and charge exactly once")
end
do
  local env, calls, _, beginRepair = fixture()
  beginRepair(); env.realisticFuel.finishRepair()
  env.vehicleRepair.repairInPlace = function() return false, "failure" end
  calls.requests[1].success({{}})
  assert(calls.repairCost == 0 and env.state.balance == 120,
    "a failed physical repair must not charge the balance")
end
do
  local env, calls = fixture()
  local completed = 0
  env.realisticFuel.repairVehiclePhysically(env.getPlayerVehicle(), function(success)
    assert(success); completed = completed + 1
  end)
  calls.requests[1].rejected(); calls.requests[1].success({{}})
  assert(calls.repair == 1 and completed == 1 and env.state.balance == 120,
    "the free repair caller must remain supported and complete once even if the bridge repeats its result")
end

print("TaxiDriver fuel and repair payment interleaving regressions passed")
