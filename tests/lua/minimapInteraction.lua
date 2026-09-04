package.path = "lua/ge/extensions/?.lua;" .. package.path

local vector = {}
vector.__index = vector
function vec3(x, y, z)
  if type(x) == "table" then x,y,z = x.x,x.y,x.z end
  return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vector)
end
function vector:set(other) self.x,self.y,self.z=other.x,other.y,other.z end
function vector.__add(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
local rotation = {}
rotation.__index = rotation
function quat(other) return setmetatable({angle=other and other.angle or 0},rotation) end
function rotation:set(other) self.angle=other.angle end
function rotation.__mul(r,v)
  return vec3(v.x*math.cos(r.angle)-v.y*math.sin(r.angle),v.x*math.sin(r.angle)+v.y*math.cos(r.angle),v.z)
end

local originalSetUtils = function() end
ui_apps_minimap_utils = {setMinimapState = originalSetUtils}
local nativeDraw = function() return 1 end
ui_apps_minimap_vehicles = {drawPlayer = nativeDraw}
ui_apps_minimap_minimap = {onMinimapSettingsChanged=function() end,setDrawTransform=function() end,
  hide=function() end,resetOcclusionTransform=function() end}
extensions={load=function() end}
settings={getValue=function() return "rect" end,setValue=function() end}
local active = true
local nav=require("taxiDriver/navigationUi").new({isActive=function() return active end,
  isRouteActive=function() return true end,getZoomIntensity=function() return 0 end})
nav:setTransform(0,0,0.5,0.5,false,true)
local pos=vec3(100,200,0)
local rot,inv=quat(),quat()
local clears=0
local texture={clearOnceBeforeRender=function(_,color) assert(color==0); clears=clears+1 end}
ui_apps_minimap_utils.setMinimapState(200,100,0,0,pos,rot,inv,2,0.5,texture)
assert(type(nav.panMinimap)=="function", "native map must support cursor drag")
nav:panMinimap(0.25,0.5)
pos:set(vec3(500,600,0)) -- vehicle/camera moves while inspecting the map
ui_apps_minimap_utils.setMinimapState(200,100,0,0,pos,rot,inv,2,0.5,texture)
assert(pos.x==0 and pos.y==300, "drag must move map with cursor and keep inspected position fixed")
assert(clears==1, "moving the map must clear old road geometry before rendering")
nav:zoomMinimap(0.8)
assert(math.abs(ui_apps_minimap_vehicles.drawPlayer(0.016,0.016)-0.8)<0.00001)
nav:resetMinimapView()
pos:set(vec3(500,600,0))
ui_apps_minimap_utils.setMinimapState(200,100,0,0,pos,rot,inv,2,0.5)
assert(pos.x==500 and pos.y==600, "reset must resume following the vehicle")
assert(ui_apps_minimap_vehicles.drawPlayer(0.016,0.016)==1)
nav:hideMinimap()
assert(ui_apps_minimap_utils.setMinimapState==originalSetUtils, "native wrapper must be restored on hide")
assert(ui_apps_minimap_vehicles.drawPlayer==nativeDraw)
active = false
nav:setTransform(0,0,0.5,0.5,true,true)
nav:zoomMinimap(0.8)
assert(math.abs(ui_apps_minimap_vehicles.drawPlayer(0.016,0.016)-0.8)<0.00001,
  "fleet map zoom must work while the player's taxi shift is offline")
nav:hideMinimap()
print("TaxiDriver native minimap interaction regressions passed")
