package.path = "lua/ge/extensions/?.lua;" .. package.path
package.preload["gameplay/route/route"] = function() return {} end
log = function() end

local nodes = {
  a = {pos = {x = 0, y = 0, z = 0}, links = {}},
  b = {pos = {x = 100, y = 0, z = 0}, links = {}},
  c = {pos = {x = 200, y = 0, z = 0}, links = {}}
}
local edge = {drivability = 1, oneWay = false}
nodes.a.links.b, nodes.b.links.a = edge, edge
nodes.b.links.c, nodes.c.links.b = edge, edge
local roads = {
  a = {b = edge},
  b = {a = edge, c = edge},
  c = {b = edge}
}
map = {
  getMap = function() return {nodes = nodes} end,
  getGraphpath = function() return {
    graph = roads,
    getFilteredPath = function() return {"a", "b", "c"} end
  } end,
  findBestRoad = function() return "a", "b" end,
  findClosestRoad = function(position)
    return position.x > 100 and "b", "c" or "a", "b"
  end
}

local commands = {}
local vehicle = {
  getID = function() return 42 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getVelocity = function() return {x = 0, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) commands[#commands + 1] = command end
}
getObjectByID = function(id) return tonumber(id) == 42 and vehicle or nil end
local phases = {toPickup = "toPickup", toStop = "toStop",
  toDestination = "toDestination", toFuelStation = "toFuelStation"}
local target = {pos = {x = 150, y = 0, z = 0}}
local autopilotModule = dofile("lua/ge/extensions/taxiDriver/autopilot.lua")

local manualHandoff = autopilotModule.new({phases = phases})
local manualEnabled = manualHandoff:enable(vehicle, phases.toDestination, target)
assert(manualEnabled, manualHandoff:getHud(true).reason)
assert(manualHandoff:toggle(vehicle, phases.toDestination, target) == false)
assert(not manualHandoff:isEnabled())
assert(commands[#commands]:find("ai.setMode('disabled')", 1, true))
assert(commands[#commands]:find("abortParking", 1, true))

commands = {}
local terminalParking = autopilotModule.new({phases = phases,
  getSpeedKmh = function() return 2 end})
assert(terminalParking:enable(vehicle, phases.toDestination, target))
assert(terminalParking:park(vehicle, "destinationReached"))
assert(not terminalParking:isEnabled())
assert(commands[#commands]:find("ai.setMode('stop')", 1, true))
assert(not commands[#commands]:find("ai.setMode('disabled')", 1, true))

print("TaxiDriver AI manual handoff / terminal parking regression passed")
