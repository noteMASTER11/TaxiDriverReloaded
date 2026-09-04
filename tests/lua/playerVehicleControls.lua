package.path = "lua/ge/extensions/?.lua;" .. package.path
package.preload["gameplay/route/route"] = function() return {} end
log = function() end

local failures = 0
local function test(name, callback)
  local ok, result = pcall(callback)
  if not ok then failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(result))
  else print("PASS " .. name) end
end

local mode = "arcade"
local pedals = {}
FILTER_DIRECT, FILTER_AI = 0, "FILTER_AI"
controller = {mainController = {
  gearboxBehavior = "arcade",
  getState = function() return {grb_bhv = mode} end,
  setGearboxMode = function(value) mode = value end
}}
input = {event = function(name, value) pedals[name] = value end}
electrics = {values = {wheelspeed = 0},
  set_left_signal = function() end, set_right_signal = function() end}

test("forced stop cannot turn a stationary arcade brake into reverse throttle", function()
  local telemetry = dofile("lua/vehicle/extensions/taxiDriverTelemetry.lua")
  telemetry.setForcedStop(true)
  telemetry.updateGFX(0.1)
  assert(pedals.brake == 1, "forced stop must still brake")
  assert(mode == "realistic", "full brake at zero speed must not run in arcade")
  mode = "arcade" -- a later native AI handoff may restore its saved mode
  telemetry.updateGFX(0.1)
  assert(mode == "realistic", "the full-brake hold must remain safe after native handoff")
  telemetry.setForcedStop(true) -- repeated GE commands must not replace saved mode
  telemetry.setForcedStop(false)
  assert(mode == "arcade", "release must restore the player's live mode")
  assert(pedals.brake == 0 and pedals.parkingbrake == 0)
end)

test("forced stop preserves a live realistic override and ignores duplicate release", function()
  mode, pedals = "realistic", {}
  local telemetry = dofile("lua/vehicle/extensions/taxiDriverTelemetry.lua")
  telemetry.setForcedStop(true)
  telemetry.updateGFX(0.1)
  telemetry.setForcedStop(false)
  assert(mode == "realistic", "compiled-in arcade default is not the live mode")
  pedals.brake = 0.5
  telemetry.setForcedStop(false)
  assert(pedals.brake == 0.5, "unowned input must be left to the player")
end)

test("AI handoff restores the mode from before native driveUsingPath", function()
  mode = "realistic"
  local nodes = {
    a = {pos = {x = 0, y = 0, z = 0}, links = {}},
    b = {pos = {x = 100, y = 0, z = 0}, links = {}}
  }
  local edge = {drivability = 1, oneWay = false}
  nodes.a.links.b, nodes.b.links.a = edge, edge
  map = {
    getMap = function() return {nodes = nodes} end,
    getGraphpath = function() return {
      graph = {a = {b = edge}, b = {a = edge}},
      getFilteredPath = function() return {"a", "b"} end
    } end,
    findBestRoad = function() return "a", "b" end,
    findClosestRoad = function() return "a", "b" end
  }
  local vehicle = {
    getID = function() return 42 end,
    getPosition = function() return {x = 0, y = 0, z = 0} end,
    getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
    getVelocity = function() return {x = 0, y = 0, z = 0} end,
    queueLuaCommand = function(_, command) assert(loadstring(command))() end
  }
  getObjectByID = function(id) return id == 42 and vehicle or nil end
  ai = {
    -- BeamNG ai.lua setMode('manual') changes the gearbox synchronously.
    driveUsingPath = function() mode = "arcade" end,
    -- Native disable restores its own saved mode first. The observer must
    -- not then overwrite that with the AI's temporary arcade mode.
    setMode = function(value) if value == "disabled" then mode = "realistic" end end,
    setSpeed = function() end, setSpeedMode = function() end
  }
  mapmgr = {getObjects = function() return {} end}
  extensions = {load = function() end,
    taxiDriverStockAiObserver = dofile("lua/vehicle/extensions/taxiDriverStockAiObserver.lua")}
  local autopilot = require("taxiDriver/autopilot").new({
    phases = {toDestination = "toDestination"}
  })
  assert(autopilot:enable(vehicle, "toDestination", {pos = {x = 90, y = 0, z = 0}}))
  assert(mode == "arcade", "native AI should retain its required driving behavior")
  local telemetry = dofile("lua/vehicle/extensions/taxiDriverTelemetry.lua")
  telemetry.setForcedStop(true) -- boarding can begin before AI handoff finishes
  assert(autopilot:disable(vehicle, "driver"))
  assert(mode == "realistic", "handoff must restore pre-AI realistic mode")
  telemetry.setForcedStop(false)
  assert(mode == "realistic", "boarding release must not resurrect AI's temporary arcade mode")
end)

assert(failures == 0, tostring(failures) .. " vehicle control regressions failed")
