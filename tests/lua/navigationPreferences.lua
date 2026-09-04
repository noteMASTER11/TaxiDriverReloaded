package.path = "lua/ge/extensions/?.lua;" .. package.path

local preferences = {showNavigationGroundmarkers = false, showNavigationArrows = true}
local writes = 0
settings = {
  getValue = function(key) return preferences[key] end,
  setValue = function(key, value) preferences[key] = value; writes = writes + 1 end
}
local arrowsCleared = false
core_groundMarkers = {
  setPath = function() arrowsCleared = false end,
  onSettingsChanged = function() end
}
core_groundMarkerArrows = {clearArrows = function() arrowsCleared = true end}
local hidden = false
local navigation = require("taxiDriver/navigationUi").new({
  isRouteGuidanceHidden = function() return hidden end
})
navigation:setNavigationTarget({pos = {x = 1, y = 2, z = 3}})
assert(preferences.showNavigationGroundmarkers == false, "floating-only preference must survive route changes")
assert(preferences.showNavigationArrows == true)
assert(writes == 0, "visible guidance must not write the user's game settings")

preferences.showNavigationGroundmarkers = true
preferences.showNavigationArrows = false
navigation:setNavigationTarget({pos = {}})
assert(preferences.showNavigationGroundmarkers and not preferences.showNavigationArrows)
assert(arrowsCleared, "setPath creates arrows; disabled preference must be applied afterward")

hidden = true
navigation:setNavigationTarget({pos = {}})
assert(not preferences.showNavigationGroundmarkers and not preferences.showNavigationArrows)
hidden = false
navigation:setNavigationTarget({pos = {}})
assert(preferences.showNavigationGroundmarkers and not preferences.showNavigationArrows)
hidden = true
navigation:setNavigationTarget({pos = {}})
navigation:restoreNavigationVisualSettings()
assert(preferences.showNavigationGroundmarkers and not preferences.showNavigationArrows)
print("TaxiDriver navigation preferences regressions passed")
