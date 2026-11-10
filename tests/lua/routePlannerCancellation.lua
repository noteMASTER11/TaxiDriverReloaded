package.path = "lua/ge/extensions/?.lua;" .. package.path
local vector = {}; vector.__index = vector
function vec3(x,y,z)
  if type(x) == "table" then x,y,z = x.x,x.y,x.z end
  return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vector)
end
function vector.__add(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector.__mul(a,n) return vec3(a.x*n,a.y*n,a.z*n) end
function vector:dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function vector:squaredLength() return self:dot(self) end
function vector:length() return math.sqrt(self:squaredLength()) end
function vector:distance(b) return (self-b):length() end
function vector:normalize() local n=self:length(); self.x,self.y,self.z=self.x/n,self.y/n,self.z/n; return self end
package.preload["gameplay/route/route"] = function() return function() return {} end end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = function() end
local level = "large-map"
getCurrentLevelIdentifier = function() return level end
local nodes = {}
for index=1,10000 do
  local a,b = "a"..index,"b"..index
  nodes[a] = {pos=vec3(index*20,0,0),radius=4,links={[b]={drivability=1}}}
  nodes[b] = {pos=vec3(index*20+10,0,0),radius=4,links={}}
end
map = {getMap=function() return {nodes=nodes} end}
local poiIds = {}
for index=1,20000 do poiIds[index] = index end
scenetree = {
  findClassObjects=function(kind)
    return kind == "BeamNGPointOfInterest" and poiIds or {}
  end,
  findObject=function() return {getPosition=function() return vec3(0,0,0) end} end
}
castRayStatic = function(_,_,reach) return reach end
local generator = require("taxiDriver/offerGenerator")
local planner = require("taxiDriver/routePlanner").new({offerConfig={
  semanticLongitudinalJitterMax=0, semanticScanBatchSize=6,
  semanticCandidateAttempts=40, graphCandidateAttempts=7
}})
planner.calculateDistance = function() return 3000 end
local function job()
  return generator.create(function()
    return planner.chooseStop(vec3(-1000,0,0),vec3(1,0,0),2000,nil)
  end, 0, {maxResumes=16, timeBudgetSeconds=1, maxJobSeconds=8, clock=function() return 0 end})
end
local function finish(current)
  while true do
    local status,result = generator.step(current,1/15)
    if status ~= "pending" then return status,result end
  end
end
local status = finish(job())
assert(status == "error", "large-map warmup must exercise timeout cancellation")
local stop
for _=1,3 do
  status,stop = finish(job())
  if status == "complete" then break end
end
assert(status == "complete" and stop and stop.routeDistance == 3000,
  "retry must preserve road and semantic cache warmup progress after a timed-out offer")
planner.reset()
assert(finish(job()) == "error", "reset must discard completed warmup caches")
level, nodes, poiIds = "empty-map", {}, {}
status,stop = finish(job())
assert(status == "complete" and stop == nil,
  "changing maps must discard suspended builders rather than publish stale map points")
print("TaxiDriver route-cache warmup cancellation regression passed")
