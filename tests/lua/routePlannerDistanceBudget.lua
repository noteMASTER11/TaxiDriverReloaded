package.path = "lua/ge/extensions/?.lua;" .. package.path
local function point(x)
  return {x=x,y=0,z=0,distance=function(a,b) return math.abs(a.x-b.x) end}
end
package.preload["gameplay/route/route"] = function()
  return function() return {setRouteParams=function() end,
    setupPath=function(self) self.path={} end} end
end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = function() end
local calls=0
local nodes={a={pos=point(0)},b={pos=point(100)}}
map={getMap=function() return {nodes=nodes} end,
  findClosestRoad=function() return "a","b" end,
  getGraphpath=function() return {getPath=function(_,from,to)
    calls=calls+1; return {from,to}
  end} end}
local planner=require("taxiDriver/routePlanner").new()
local distance
local thread=coroutine.create(function() distance=planner.calculateDistance(point(10),point(90)) end)
while coroutine.status(thread)~="dead" do
  local before=calls
  local ok,err=coroutine.resume(thread); assert(ok,err)
  assert(calls-before<=1, "a resume must perform at most one fallback path search")
end
assert(calls==4 and distance==100, "all endpoint combinations must still be considered")
print("TaxiDriver route-distance yield granularity regression passed")
