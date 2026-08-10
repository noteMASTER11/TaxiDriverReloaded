package.path = "lua/ge/extensions/?.lua;" .. package.path

local clearFlags = {}
local textureDraw = {
  setClearFlag = function(_, value)
    clearFlags[#clearFlags + 1] = value
  end
}

local originalSetState = function() return "state" end
local originalDrawPlayer = function() return 1 end

ui_apps_minimap_vehicles = {
  setMinimapState = originalSetState,
  drawPlayer = originalDrawPlayer
}
ui_apps_minimap_minimap = {
  onMinimapSettingsChanged = function() end,
  setDrawTransform = function() end,
  resetOcclusionTransform = function() end,
  hide = function() end
}
extensions = {
  load = function() end
}
settings = {
  getValue = function() return "rect" end,
  setValue = function() end
}

local navigationUi = require("taxiDriver/navigationUi").new({
  isActive = function() return true end,
  isRouteActive = function() return true end,
  getZoomIntensity = function() return 100 end
})

navigationUi:setTransform(0.1, 0.1, 0.5, 0.3, false, true)
assert(ui_apps_minimap_vehicles.setMinimapState ~= originalSetState)
ui_apps_minimap_vehicles.setMinimapState(nil, nil, nil, nil, nil, nil, nil, nil, nil, textureDraw)
assert(clearFlags[#clearFlags] == "Always")

-- Compact mode must keep BeamNG's cheaper stock dirty-region clearing even
-- when the map rectangle itself has not changed.
navigationUi:setTransform(0.1, 0.1, 0.5, 0.3, false, false)
ui_apps_minimap_vehicles.setMinimapState(nil, nil, nil, nil, nil, nil, nil, nil, nil, textureDraw)
assert(clearFlags[#clearFlags] == "WhenDirty")

navigationUi:hideMinimap()
assert(ui_apps_minimap_vehicles.setMinimapState == originalSetState)
assert(ui_apps_minimap_vehicles.drawPlayer == originalDrawPlayer)
assert(clearFlags[#clearFlags] == "WhenDirty")

print("TaxiDriver full minimap texture clearing regression passed")
