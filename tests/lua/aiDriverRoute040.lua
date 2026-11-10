package.path = "lua/ge/extensions/?.lua;" .. package.path
package.preload["gameplay/route/route"] = function() return {} end
local edge = {oneWay = true, inNode = "a", drivability = 1}
local nodes = {
  a = {pos = {x = 0, y = 0, z = 0}},
  b = {pos = {x = 100, y = 0, z = 0}},
  c = {pos = {x = -100, y = 0, z = 0}}
}
local filteredPath = {"c", "a"}
local startEdge = {oneWay = false, drivability = 1}
local roads = {a = {b = edge, c = startEdge}, b = {a = edge}, c = {a = startEdge}}
map = {
  getMap = function() return {nodes = nodes} end,
  getGraphpath = function() return {
    graph = roads, getFilteredPath = function() return filteredPath end
  } end,
  findBestRoad = function() return "c", "a" end,
  findClosestRoad = function() return "a", "b" end
}
local vehicle = {
  getPosition = function() return {x = -100, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end
}
local module = dofile("lua/ge/extensions/taxiDriver/aiDriverRoute.lua")
local result, reason, planned
local function finished(ok, value, err) result, reason, planned = ok, err, value end
local service = module.new()
service:request(vehicle, {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = -1, y = 0, z = 0}}, 1, finished)
assert(result == false and reason == "targetEdgeWrongWay",
  "a target orientation must not append a wrong-way one-way edge to a legal route")

filteredPath = {}
service:request(vehicle, {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = 1, y = 0, z = 0}}, 2, finished)
assert(result == false and reason == "fallbackPathTooShort",
  "an unreachable graph search must not become a successful route by appending target endpoints")

filteredPath = {"c", "a"}
service:request(vehicle, {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = 1, y = 0, z = 0}}, 3, finished)
assert(result == true, "a legal reachable target edge must remain routable")
filteredPath = {"c", "a", "b"}
service:request(vehicle, {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = 1, y = 0, z = 0}}, 4, finished)
assert(result and #planned.path == 3 and planned.path[3] == "b",
  "an already complete target edge must not be appended a second time")
local asynchronous = module.new({routeFactory = function() return {
  setupPathMultiJob = function(self, _, callback)
    self.path = {}
    callback(self)
  end
} end})
asynchronous:request(vehicle, {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = 1, y = 0, z = 0}}, 4, finished)
assert(result == false and reason == "asyncPathTooShort",
  "an empty asynchronous route must not become successful by appending target endpoints")

local gpsMarkers = {{pos = {x = -100, y = 0, z = 0}},
  {wp = "c"}, {wp = "a"}, {wp = "b"}, {pos = {x = 50, y = 0, z = 0}}}
local gpsService = module.new({getRoutePath = function() return gpsMarkers end})
local gpsTarget = {pos = {x = 50, y = 0, z = 0},
  nodeA = "a", nodeB = "b", dir = {x = 1, y = 0, z = 0}}
gpsService:request(vehicle, gpsTarget, 5, finished, {strictGpsRoute = true})
assert(result and planned.source == "displayedGps" and
  #planned.path == 3 and planned.path[1] == "c" and planned.path[3] == "b",
  "strict GPS must preserve the exact displayed graph sequence without prefix trimming")
gpsMarkers = {{wp = "b"}, {wp = "a"}} -- wrong-way one-way route must fall back
gpsService:request(vehicle, gpsTarget, 6, finished, {strictGpsRoute = true})
assert(result and planned.source == "graphpathFallback" and
  planned.path[2] == "a" and planned.path[3] == "b",
  "an invalid displayed route must fall back to the legal native planner")
gpsMarkers = {}
gpsService:request(vehicle, gpsTarget, 7, finished, {strictGpsRoute = true})
assert(result and planned.source == "graphpathFallback",
  "GPS markers that are not ready yet must not prevent driving")
gpsMarkers = {{wp = "c"}, {wp = "removed_node"}, {wp = "a"}, {wp = "b"}}
gpsService:request(vehicle, gpsTarget, 8, finished, {strictGpsRoute = true})
assert(result and planned.source == "graphpathFallback",
  "strict GPS must reject unknown waypoints rather than silently shorten its displayed sequence")
print("PASS AI Driver wrong-way target and unreachable fallback")
