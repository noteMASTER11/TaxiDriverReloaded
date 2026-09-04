-- BeamNG's engineLua callback wraps the supplied code as a Lua expression.
local file = assert(io.open("ui/modules/apps/TaxiDriverHUD/app.js", "r"))
local source = file:read("*a")
file:close()
local expression = assert(source:match('"([^"\n]*ui_router%.getCurrent[^"\n]*)"'))
local reply
guihooks = {trigger = function(event, id, value)
  assert(event == "onBNGAPICallback" and id == 1)
  reply = value
end}
local callback, err = loadstring('guihooks.trigger("onBNGAPICallback",1,' .. expression .. ')')
assert(callback, "initial HUD route must be a callback-compatible expression: " .. tostring(err))
ui_router = {getCurrent = function() return {request = {name = "pause.bigmap"}} end}
callback()
assert(reply == "pause.bigmap", "HUD must receive the active overlay route")
ui_router.getCurrent = function() return nil end
callback()
assert(reply == nil, "missing current route must be tolerated")
ui_router = nil
callback()
assert(reply == nil, "missing router must be tolerated")
print("PASS native route callback expression")
