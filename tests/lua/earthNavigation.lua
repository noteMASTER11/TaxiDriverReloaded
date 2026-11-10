package.path="lua/ge/extensions/?.lua;"..package.path
local calls,cleared=0,0
local target={geo={lat=45,lon=39},pos={x=1,y=2,z=3},earthLocal=false}
local support={active=function()return true end,setTarget=function(_,p)assert(p==target);calls=calls+1;return true end,
  clearTarget=function()cleared=cleared+1 end,project=function(_,p)return p.pos end}
core_groundMarkers={setPath=function()error("A world destination must not enter the local route planner")end}
local nav=require("taxiDriver/navigationUi").new({nativeMinimap={},getEarthSupport=function()return support end})
nav:setNavigationTarget(target)
assert(calls==1)
nav:clearNavigation()
assert(cleared==1, "Earth navigation must release only its own GPS destination")
print("Earth navigation stays outside the local route planner")
