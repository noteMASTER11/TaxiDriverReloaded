package.path = "lua/ge/extensions/?.lua;" .. package.path
local calls = 0
local vanilla = {setMinimapState = function() calls = calls + 1 end,
  drawOtherVehicles = function() calls = calls + 1 end}
ui_apps_minimap_vehicles = vanilla
local originals = {vanilla.setMinimapState, vanilla.drawOtherVehicles}
local private = {vehicles = {setMinimapState = function() calls = calls + 1 end,
  drawOtherVehicles = function() calls = calls + 1 end}, utils = {}}
local fleet = require("taxiDriver/fleetManager").new({modVersion = "test"})
fleet:installMinimapMarkers(private)
assert(vanilla.setMinimapState == originals[1] and vanilla.drawOtherVehicles == originals[2],
  "fleet markers must not modify the stock map")
local retainedSet, retainedDraw = private.vehicles.setMinimapState, private.vehicles.drawOtherVehicles
-- Another wrapper may retain the callbacks after fleet teardown.
fleet:restoreMinimapMarkers()
retainedSet()
retainedDraw()
assert(calls == 2, "retained callbacks must keep valid originals after teardown")
fleet:installMinimapMarkers(private)
fleet:restoreMinimapMarkers()
private.vehicles.setMinimapState()
assert(calls == 3)
print("TaxiDriver fleet minimap lifecycle regressions passed")
