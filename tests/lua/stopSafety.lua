package.path = "lua/ge/extensions/?.lua;" .. package.path

local vector = {}
vector.__index = vector
function vec3(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vector)
end
function vector.__add(a, b) return vec3(a.x+b.x, a.y+b.y, a.z+b.z) end
function vector.__sub(a, b) return vec3(a.x-b.x, a.y-b.y, a.z-b.z) end
function vector.__mul(a, n) return vec3(a.x*n, a.y*n, a.z*n) end
function vector:dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function vector:squaredLength() return self:dot(self) end
function vector:length() return math.sqrt(self:squaredLength()) end
function vector:distance(b) return (self-b):length() end
function vector:normalize() local n=self:length(); self.x,self.y,self.z=self.x/n,self.y/n,self.z/n; return self end
function vector:normalized() return vec3(self):normalize() end

package.preload["gameplay/route/route"] = function()
  return function() return {
    setRouteParams = function() end,
    setupPath = function(self) self.path = {{wp = "a", distToTarget = 100}, {wp = "b"}} end
  } end
end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = function() end
getCurrentLevelIdentifier = function() return "test" end
local nodes = {
  a = {pos = vec3(0, 0, 0), radius = 4, links = {b = {drivability = 1}}},
  b = {pos = vec3(100, 0, 0), radius = 4, links = {}},
  c = {pos = vec3(0, 100, 0), radius = 4, links = {d = {drivability = 1}}},
  d = {pos = vec3(100, 100, 0), radius = 4, links = {}}
}
map = {getMap = function() return {nodes = nodes} end}
castRayStatic = function(origin, direction, reach)
  assert(direction.z == 1 and origin.z > 0, "roof checks must start above the road and point upward")
  return origin.y < 50 and 5 or reach
end
local planner = require("taxiDriver/routePlanner").new({offerConfig = {
  semanticLongitudinalJitterMax = 0, semanticScanBatchSize = 64,
  semanticCandidateAttempts = 1
}})
math.randomseed(2)
for _ = 1, 20 do
  local stop = planner.chooseStop(vec3(-100, 0, 0), vec3(1, 0, 0), 1, 500)
  assert(stop and stop.pos.y > 50, "road-graph fallback must never choose a covered tunnel stop")
end
print("TaxiDriver tunnel stop selection regression passed")

local cache = require("taxiDriver/routeCache")
local function stopAt(y)
  return {pos = vec3(10,y,0), dir = vec3(1,0,0), nodeA = "a", nodeB = "b", routeDistance = 100}
end
local coveredOffer = cache.serializeOffer({pickup = stopAt(100), destination = stopAt(0),
  stops = {}, rideDistance = 100}, vec3())
cache.loadOffers = function() return {coveredOffer} end
assert(cache.restoreBest({vehiclePos = vec3()}) == nil,
  "saved offers must not reintroduce destinations under tunnel roofs")
coveredOffer.destination.y = 100
assert(cache.restoreBest({vehiclePos = vec3()}) ~= nil, "open-air saved offers must still restore")
coveredOffer.stops = {cache.serializePoint(stopAt(0))}
assert(cache.restoreBest({vehiclePos = vec3()}) == nil,
  "intermediate stops must also be validated")
coveredOffer.stops = {}
coveredOffer.pickup.y = 0
assert(cache.restoreBest({vehiclePos = vec3()}) == nil, "pickups must also be validated")
print("TaxiDriver tunnel cached-offer regression passed")
