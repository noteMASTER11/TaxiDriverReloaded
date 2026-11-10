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
print("TaxiDriver private native minimap regressions passed")
