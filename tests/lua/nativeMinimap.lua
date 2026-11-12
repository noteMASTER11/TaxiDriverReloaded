package.path = "lua/ge/extensions/?.lua;" .. package.path

local globalSettings = {mode = "circle"}
local settingsWrites, globalHooks = 0, 0
settings = {
  getValue = function(key) return key == "minimapMode" and globalSettings.mode or nil end,
  setValue = function() settingsWrites = settingsWrites + 1 end
}
extensions = {hookUpdate = function() globalHooks = globalHooks + 1 end}
local textures, windows = {}, {}
TextureDrawPrimitiveRegistry = {
  getOrCreate = function(_, name) textures[#textures + 1] = name; return name end
}
ui_imgui = {Begin = function(name) windows[#windows + 1] = name; return true end}
ui_apps_minimap_minimap = {sentinel = true}
local globalMap = ui_apps_minimap_minimap
local draws = 0
local stockMarkerDraws, privateMarkerDraws = 0, 0
gameplay_playmodeMarkers = {getMarkerForCluster = function()
  return {pos = {x = 1, y = 2, z = 3}, drawOnMinimap = function() stockMarkerDraws = stockMarkerDraws + 1 end}
end}
local function loadNative(name, env)
  if name == "minimap" then
    return {
      onMinimapSettingsChanged = function() assert(env.settings.getValue("minimapMode") == "rect") end,
      setDrawTransform = function()
        env.extensions.hookUpdate("onUpdate")
      end,
      onUpdate = function()
        draws = draws + 1
        env.ui_imgui.Begin("SDF Minimap")
        env.TextureDrawPrimitiveRegistry:getOrCreate("sdfMinimap", 300, 200)
        assert(env.ui_apps_minimap_utils ~= ui_apps_minimap_utils)
        env.gameplay_playmodeMarkers.getMarkerForCluster({visibilityPos = {x = 1, y = 2, z = 3}}):drawOnMinimap()
      end,
      hide = function() env.extensions.hookUpdate("onUpdate") end
    }
  end
  return {private = true, simpleCircle = function() privateMarkerDraws = privateMarkerDraws + 1 end}
end
local private = require("taxiDriver/nativeMinimap").new({loadModule = loadNative})
local modules = assert(private:getModules())
local resets=0
modules.roads.reset=function()resets=resets+1 end
private:invalidateRoads()
assert(resets==1, "streamed graph changes must invalidate the private road cache")
assert(modules.minimap ~= globalMap)
assert(ui_apps_minimap_minimap == globalMap, "must not replace the stock widget")
modules.minimap.setDrawTransform(0.1, 0.1, 0.4, 0.4)
private:update(0.016, 0.016)
assert(draws == 1)
assert(textures[1] == "sdfTaxiDriverMinimap", "TaxiDriver needs its own texture")
assert(windows[1] == "TaxiDriver SDF Minimap", "ImGui windows must have independent IDs")
assert(settingsWrites == 0 and globalSettings.mode == "circle", "stock shape is untouched")
assert(globalHooks == 0, "private callbacks must not alter the extension hook registry")
assert(stockMarkerDraws == 0 and privateMarkerDraws == 1,
  "private POIs must not invoke marker closures bound to the stock texture")
private:reset()
assert(ui_apps_minimap_minimap == globalMap)
local unavailable = require("taxiDriver/nativeMinimap").new({loadModule = function() error("missing API") end})
assert(unavailable:getModules() == nil, "missing native APIs must fail without touching stock map")
local graph={edges={}}
local updates,unhooks=0,0
local stockRoads={sentinel=true};ui_apps_minimap_roads=stockRoads
beamngEarth_api={inWorld=function()return true end}
local earthPrivate=require('taxiDriver/nativeMinimap').new({loadModule=loadNative,
  getEarthGraph=function()return graph end,
  loadEarthModule=function(env)
    assert(env._G==env and env.ui_apps_minimap_roads~=stockRoads)
    return {hook=function()assert(ui_apps_minimap_roads==stockRoads)end,
      update=function(g)assert(g==graph);updates=updates+1 end,
      unhook=function()unhooks=unhooks+1 end,status=function()return {links=4}end}
  end})
earthPrivate:getModules();earthPrivate:update(.016,.016)
graph={edges={{1,2}}};earthPrivate:update(.016,.016)
assert(updates==2 and earthPrivate:stats().earth.links==4,
  'private Earth roads must follow each streamed graph without modifying the stock renderer')
earthPrivate:reset();assert(unhooks==1 and ui_apps_minimap_roads==stockRoads)
print("TaxiDriver private native minimap regressions passed")
