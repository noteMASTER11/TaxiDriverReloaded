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
function vector:normalized() return vec3(self):normalize() end
package.preload["gameplay/route/route"] = function() return function() return {} end end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = function() end
getCurrentLevelIdentifier = function() return "budget-test" end
local nodes = {}
for index=1,200 do
  local a,b = "a"..index,"b"..index
  nodes[a] = {pos=vec3(index*20,0,0),radius=4,links={[b]={drivability=1}}}
  nodes[b] = {pos=vec3(index*20+10,0,0),radius=4,links={}}
end
map = {getMap=function() return {nodes=nodes} end,
  findClosestRoad=function() return "a1","b1" end,
  getGraphpath=function() return {getRandomPathG=function() return nil end} end}
castRayStatic = function(_,_,reach) return reach end
local calls=0
local planner = require("taxiDriver/routePlanner").new({offerConfig={
  semanticLongitudinalJitterMax=0, semanticScanBatchSize=6,
  semanticCandidateAttempts=40, graphCandidateAttempts=7, randomRouteAttempts=1,
  randomDistanceExponent=1.15
}})
planner.calculateDistance = function() calls=calls+1; return 100 end
local thread = coroutine.create(function()
  local stop = planner.chooseStop(vec3(-1000,0,0),vec3(1,0,0),2000,10000)
  assert(stop == nil, "unreachable minimum must still fail")
end)
local resumes=0
while coroutine.status(thread)~="dead" do
  resumes=resumes+1
  local ok,err=coroutine.resume(thread); assert(ok,err)
  assert(resumes<2000, "search must terminate")
end
assert(calls==7, "road graph search must honor candidate budget instead of scanning every point; got "..calls)
print("TaxiDriver route-planner candidate budget regression passed")
