package.path = "lua/ge/extensions/?.lua;" .. package.path
package.preload["gameplay/route/route"] = function() return {} end
local nodes = {
  nearA = {pos = {x = -1241.67, y = 216.54, z = 100}},
  nearB = {pos = {x = -1249.83, y = 220.52, z = 100}},
  rampA = {pos = {x = -1300.04, y = 205.82, z = 101.91}},
  rampB = {pos = {x = -1294.18, y = 187.25, z = 101.68}},
  a = {pos = {x = -830, y = -510, z = 100}},
  b = {pos = {x = -820, y = -530, z = 100}}
}
local edge = {drivability = 1}
local roads = {nearA = {nearB = edge, a = edge}, nearB = {nearA = edge},
  rampA = {rampB = edge}, rampB = {rampA = edge, a = edge},
  a = {nearA = edge, rampB = edge, b = edge}, b = {a = edge}}
map = {getMap = function() return {nodes = nodes} end,
  getGraphpath = function() return {graph = roads} end,
  findClosestRoad = function() return "nearA", "nearB", 15 end,
  findBestRoad = function() return "rampA", "rampB", 38 end}
local vehicle = {getPosition = function() return {x = -1261.85, y = 208.68, z = 100.2} end,
  getDirectionVector = function() return {x = 0.122, y = -0.992, z = 0} end}
local calls, callback, outcome, failure = {}, nil, nil, nil
local module = dofile("lua/ge/extensions/taxiDriver/aiDriverRoute.lua")
local service = module.new({routeFactory = function() return {
  setupPathMultiJob = function(self, positions, done)
    calls[#calls + 1] = positions
    callback = function(path) self.path = path; done(self) end
  end
} end})
assert(service:request(vehicle, {pos = {x = -823.1, y = -518.9, z = 100},
  nodeA = "a", nodeB = "b", dir = {x = 0, y = -1, z = 0}}, 1,
  function(ok, result, err) outcome, failure = ok and result or nil, err end))
callback({"rampA", "rampB", "a"})
assert(not outcome and #calls == 2,
  "a route attached to the raised ramp must be replanned before issuing native driving")
assert(calls[2][1].x == nodes.nearA.pos.x,
  "source repair must anchor to the forward endpoint of the closest physical road")
callback({"nearA", "a"})
assert(not failure and outcome.path[1] == "nearA" and outcome.path[2] == "a" and
  outcome.path[3] == "b", "repaired start must retain the connected legal destination suffix")
assert(outcome.diagnostics.startJoin.replanned and
  outcome.diagnostics.startJoin.anchorNode == "nearA",
  "diagnostics must identify source repair and its road anchor")

-- The repair itself is bounded: a planner that still attaches to another
-- road must fail instead of recursively scheduling more jobs.
outcome, failure, calls = nil, nil, {}
assert(service:request(vehicle, {pos = nodes.b.pos}, 2,
  function(ok, result, err) outcome, failure = ok and result or nil, err end))
callback({"rampA", "rampB", "a", "b"})
callback({"rampA", "rampB", "a", "b"})
assert(not outcome and failure == "startRoadJoinFailed" and #calls == 2,
  "a failed fixed-road repair must terminate after one retry")

local fallbackStart
map.getGraphpath = function() return {graph = roads,
  getFilteredPath = function(_, start)
    fallbackStart = start
    return {start, "a", "b"}
  end} end
local fallback = module.new()
fallback:request(vehicle, {pos = nodes.b.pos}, 3, function(ok) assert(ok) end)
assert(fallbackStart == "nearA",
  "the bounded graph fallback must also start on the nearest road, not heading-matched ramp")
print("PASS AI native route source joins the closest physical road instead of a nearby ramp")
