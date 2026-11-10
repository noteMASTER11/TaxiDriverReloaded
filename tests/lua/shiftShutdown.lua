package.path = "lua/ge/extensions/?.lua;" .. package.path
log = function() end
FS = {fileExists = function() return false end, directoryExists = function() return true end}
jsonWriteFile = function() end

local file = assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local missionHook = assert(source:match("(function M.onClientEndMission.-)\nend function M.onPreRender")) .. "\nend"
local unloadHook = assert(source:match("(function M.onExtensionUnloaded.-)\nfunction M.onSerialize"))
local history = require("taxiDriver/shiftHistory")
local function noop() end
local dummy = setmetatable({}, {__index = function() return noop end})

for _, hook in ipairs({{name = "onClientEndMission", source = missionHook},
    {name = "onExtensionUnloaded", source = unloadHook}}) do
  history.load("test")
  local vehicle = {getID = function() return 42 end}
  local vehicleData = {modelKey = "etki", configKey = "2400_A"}
  local summary = {rides = 1}
  local id = history.begin(vehicleData, {energyType = "gasoline", percent = 64}, summary)
  local fuel = {dashboardEnergy = {available = true, energyType = "gasoline", percent = 64},
    persistence = dummy, restoreEconomy = noop}
  fuel.resetDashboardEnergy = function()
    fuel.dashboardEnergy = {available = false, energyType = "", percent = 0}
  end
  local env = setmetatable({
    M = {}, realisticFuel = fuel, state = {active = true, activeVehicleId = 42},
    runtimeBoundary = {cleanup = function(_, _, callback, ...) return callback(...) end},
    routeCache = dummy, physicalPickup = dummy, shiftHistory = history, policeCheck = dummy,
    lanBridge = dummy, fleet = dummy, autopilot = dummy, aiLogger = dummy,
    navigationUi = dummy, routePlanning = dummy, vehicleHistory = dummy, vehicleScanGuard = dummy,
    offerGeneration = {}, delivery = dummy,
    getPlayerVehicle = function() return vehicle end,
    getObjectByID = function() return vehicle end,
    writeUserProgress = noop, restoreNavigationVisualSettings = noop,
    stopModeInternal = function()
      history.finishActive(vehicle, vehicleData, fuel.dashboardEnergy, summary)
    end
  }, {__index = _G})
  -- No core_vehicleBridge is provided: a VM response is unavailable during shutdown.
  local chunk = assert(loadstring(hook.source)); setfenv(chunk, env); chunk()
  env.M[hook.name]()
  assert(history.get(id).energy.percent == 64,
    hook.name .. " must retain the last known fuel when the VM cannot answer")
  assert(fuel.dashboardEnergy.available == false, hook.name .. " must still clear dashboard state")
end

print("TaxiDriver shutdown shift energy regressions passed")
