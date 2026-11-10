package.path = "lua/ge/extensions/?.lua;" .. package.path
local support = require("taxiDriver/earthTripSupport")
local currentPose = {lat=40,lon=44,x=0,y=0,z=30,alt=30,anchorLat=40,anchorLon=44,speed=0,camera=false}
local connected, inWorld, target, sets, clears = true, true, nil, 0, 0
local api = {
  connected=function() return connected end, inWorld=function() return inWorld end,
  pose=function() return currentPose end, gps=function() return target end,
  gpsSet=function(lat,lon,name) sets=sets+1; target={lat=lat,lon=lon,name=name};return true end,
  gpsClear=function() clears=clears+1;target=nil end
}
local anchors, terrainCalls, roadCalls = 0, 0, 0
local geodesy = {newAnchor=function(lat0,lon0)
  anchors=anchors+1
  return {
    geodeticToWorld=function(_,lat,lon,alt) return (lon-lon0)*100000,(lat-lat0)*100000,alt end,
    worldToGeodetic=function(_,x,y,z) return lat0+y/100000,lon0+x/100000,z end,
    transformTo=function() return {rotate=function(_,x,y,z) return -y,x,z end} end
  }
end}
local s = support.new({getApi=function() return api end,getGeodesy=function() return geodesy end,
  groundHeight=function(pos) terrainCalls=terrainCalls+1;return 45 end,
  findRoad=function(pos) roadCalls=roadCalls+1;return {x=pos.x+2,y=pos.y,z=55} end})
assert(s:active() and s:pose()==currentPose)
local stop={geo={lat=40.001,lon=44.002},name="Pickup",dir={x=0,y=1,z=0}}
local p=s:project(stop)
assert(math.abs(p.x-200)<0.001 and math.abs(p.y-100)<0.001 and p.z==55)
assert(stop.earthLocal and stop.earthDistance>0 and roadCalls==1)
local converted=s:toGeo({x=200,y=100,z=55})
assert(math.abs(converted.lat-stop.geo.lat)<1e-10 and converted.alt==55)
local before=s:distanceTo(stop)
local old=p
currentPose.anchorLat=40.01;currentPose.anchorLon=44.01
s:refreshOffer({earth=true,pickup=stop,stops={stop},destination=stop})
assert(stop.pos~=old and math.abs(stop.pos.x+800)<0.001 and math.abs(stop.pos.y+900)<0.001)
assert(stop.dir.x==-1 and stop.dir.y==0, "direction is rotated once despite duplicate stops")
assert(math.abs(s:distanceTo(stop)-before)<0.001, "arrival distance must ignore origin rebases")
assert(anchors==2, "one geodesy anchor is reused until an actual rebase")
local far={geo={lat=41,lon=45},name="Far"}
local previousRoadCalls=roadCalls
local previousTerrainCalls=terrainCalls
s:project(far)
assert(not far.earthLocal and roadCalls==previousRoadCalls and terrainCalls==previousTerrainCalls,
  "distant targets cannot query the local road graph or terrain")
assert(s:setTarget(stop));assert(s:setTarget(stop));assert(sets==1, "GPS is set once per geographic target")
target.remaining=1234
assert(s:remaining(stop)==1234)
assert(s:remaining(far)==s:distanceTo(far), "remaining belongs only to the matching target")
target.remaining=-10
assert(s:remaining(stop)==s:distanceTo(stop))
target.remaining=1234;target.planning=true
assert(s:remaining(stop)==nil, "a planning route must retain the known road distance instead of showing a straight-line shortcut")
target={lat=42,lon=45,name="User destination"}
assert(s:setTarget(stop) and sets==1, "per-frame target updates must not overwrite a user's GPS")
s:clearTarget();assert(clears==0, "a user's replacement GPS must survive trip cleanup")
assert(s:setTarget(stop) and sets==2)
s:reset();assert(clears==1 and target==nil)
assert(s:setTarget(stop));target.name="Player's saved destination"
s:clearTarget();assert(clears==1 and target~=nil, "a replacement label also relinquishes GPS ownership")
assert(not s:arrived(stop,20,1))
currentPose.lat=stop.geo.lat;currentPose.lon=stop.geo.lon;currentPose.speed=5
assert(not s:arrived(stop,20,1));currentPose.speed=0
assert(s:arrived(stop,20,1))
currentPose.camera=true
assert(s:pose()==nil and not s:arrived(stop,20,1), "free camera cannot complete a taxi stop")
currentPose.camera=false;connected=false
assert(not s:active() and s:toGeo({x=0,y=0,z=0})==nil)
s:project(stop);assert(stop.pos==nil and stop.earthLocal==false, "an unavailable frame cannot retain an old position")
connected=true;inWorld=false;assert(not s:active());inWorld=true
local bad={geo={lat=0/0,lon=44},pos={x=1,y=2,z=3}}
assert(s:project(bad)==nil and bad.pos==nil and not s:setTarget(bad))
local explicit={geo={lat=40,lon=44,alt=250}}
local n=roadCalls;s:project(explicit);assert(explicit.pos.z==250 and roadCalls==n)
local terrainOnly=support.new({getApi=function() return api end,getGeodesy=function() return geodesy end,
  findRoad=function() return {x=100000,y=100000,z=999} end,groundHeight=function() return 42 end})
local near={geo={lat=40,lon=44}}
terrainOnly:project(near);assert(near.pos.z==42, "far-away road segments cannot supply the target height")
local gpsError=support.new({getApi=function() return api end})
api.gpsSet=function()return false,"not ready"end
assert(not gpsError:setTarget(stop));gpsError:clearTarget();assert(clears==1)

-- Exercise the engine adapters without a loaded level or vehicle.
map={findClosestRoad=function() return "a","b" end,getMap=function()return {nodes={
  a={pos={x=-1010,y=-1000,z=60}},b={pos={x=-990,y=-1000,z=80}}
}}end}
core_terrain={getTerrainHeight=function()return 91 end}
local defaults=support.new({getApi=function()return api end,getGeodesy=function()return geodesy end})
local defaultStop={geo={lat=40,lon=44}}
defaults:project(defaultStop);assert(math.abs(defaultStop.pos.z-70)<0.001, "road height interpolates the closest segment")
map.findClosestRoad=function() error("map not loaded") end
defaults:project(defaultStop);assert(defaultStop.pos.z==91, "terrain handles an unavailable road graph")
core_terrain.getTerrainHeight=function()error("no terrain")end
defaults:project(defaultStop);assert(defaultStop.pos.z==0, "unloaded ground uses geodesy's zero-altitude projection")
local originalApi=api
api.ready=function()return false end
assert(not s:ready(), "Earth loading must pause paid-trip timers")
api.ready=function()return true end
assert(s:ready())
api.gpsSet=function(lat,lon,name)target={lat=lat,lon=lon,name=name};return true end
assert(defaults:setTarget(defaultStop))
api={connected=function()return true end,inWorld=function()return true end,gps=function()return target end,
  gpsClear=function()error("must not clear another session")end}
defaults:reset();assert(target~=nil and clears==1, "ownership cannot pass to another Earth API instance")
api=originalApi
local unavailable=support.new({getApi=function()return api end,getGeodesy=function()error("not loaded")end})
unavailable:project(defaultStop);assert(defaultStop.pos==nil)
assert(unavailable:toGeo({x=0,y=0,z=0})==nil)

-- Exact geographic identity is kept at real Earth heights and across rebases.
local source="dist/research/beamng.earth/mod/beamng_earth/lua/ge/extensions/beamngEarth/geodesy.lua"
local file=io and io.open and io.open(source,"rb")
if file then
  file:close()
  math.atan2=math.atan2 or function(y,x)return math.atan(y,x)end
  local realGeodesy=dofile(source)
  currentPose={lat=39,lon=-119,alt=1650,x=0,y=0,z=1650,anchorLat=39,anchorLon=-119,speed=0}
  local real=support.new({getApi=function()return api end,getGeodesy=function()return realGeodesy end})
  local mountain={geo={lat=39.1,lon=-118.9,alt=1650}}
  real:project(mountain)
  local roundtrip=real:toGeo(mountain.pos)
  assert(math.abs(roundtrip.lat-mountain.geo.lat)<1e-8 and math.abs(roundtrip.lon-mountain.geo.lon)<1e-8)
  assert(math.abs(roundtrip.alt-1650)<0.001)
  currentPose.anchorLat=39.1;currentPose.anchorLon=-118.9
  real:project(mountain)
  assert(math.abs(mountain.pos.x)<0.001 and math.abs(mountain.pos.y)<0.001)
  local dateLine={geo={lat=0,lon=-179.999}}
  currentPose.lat=0;currentPose.lon=179.999
  assert(real:distanceTo(dateLine)<225, "geographic distance crosses the date line by the short arc")
end
print("earthTripSupport: all assertions passed")
