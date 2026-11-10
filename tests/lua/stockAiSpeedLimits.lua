-- A cap switches native AI from legal to limit; the observer must retain road limits.
local speed = 14
local nativeSpeed, nativeMode
local position = {x = 80, y = 0, z = 0}
obj = {
  getID = function() return 42 end,
  getPosition = function() return position end,
  getVelocity = function() return {x = speed, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getInitialLength = function() return 4.5 end,
  getInitialWidth = function() return 1.8 end,
  queueGameEngineLua = function() end
}
electrics = {values = {wheelspeed = speed}}
input = {event = function() end}
controller = nil
ai = {
  setSpeed = function(value) nativeSpeed = value end,
  setSpeedMode = function(value) nativeMode = value end,
  setRacing = function() end
}
local firstEdge = {speedLimit = 8, oneWay = false}
local secondEdge = {speedLimit = 4, oneWay = false}
mapmgr = {
  getObjects = function() return {} end,
  findClosestRoad = function() return "a", "b" end,
  mapData = {
    positions = {a = {x = 0, y = 0}, b = {x = 100, y = 0}, c = {x = 200, y = 0}},
    graph = {a = {b = firstEdge}, b = {a = firstEdge, c = secondEdge}, c = {b = secondEdge}},
    radius = {a = 4, b = 4, c = 4}
  }
}
local observer = dofile("lua/vehicle/extensions/taxiDriverStockAiObserver.lua")
assert(observer.watch({routeNodes = {"a", "b", "c"}, routeSpeedMode = "legal",
  targetX = 120, targetY = 0, targetZ = 0, arrivalRadius = 6}))
observer.updateGFX(0.2)
assert(nativeMode == "limit" and nativeSpeed <= 8,
  "an arrival cap must not disable the current road's 8 m/s legal limit")
position.x = 99
observer.updateGFX(0.2)
assert(nativeSpeed <= 5,
  "temporary limits must retain braking for the next planned 4 m/s edge")
position.x = -200 -- outside the arrival window, beginning cap release
observer.updateGFX(0.1)
assert(nativeMode == "limit" and nativeSpeed <= 8,
  "the cap release ramp must not accelerate past the current road limit")
observer.updateGFX(0.4)
assert(nativeMode == "legal" and nativeSpeed == nil,
  "a cleared cap must return control of legal limits to native AI")
observer.unwatch()
assert(nativeMode == "legal" and nativeSpeed == nil,
  "releasing the observer must restore native legal speed mode")

-- Disabling obedience must not silently reintroduce a road limit.
position.x = 80
assert(observer.watch({routeSpeedMode = "off", targetX = 120, arrivalRadius = 6}))
observer.updateGFX(0.2)
assert(nativeSpeed > 8, "unrestricted driving must continue to use only the requested cap")
print("PASS stock AI road limits during arrival and cap release")
