-- Native main.lua runs ai.updateGFX before extension updateGFX. The first
-- native frame builds ingress; the observer then extends its resolved suffix.
local appended, appends = nil, 0
ai = {setSpeed = function() end, setSpeedMode = function() end,
  setPath = function(path) appended = path; appends = appends + 1 end,
  setRacing = function() end, mode = "manual"}
obj = {getID = function() return 42 end, getPosition = function() return {x = 0, y = 0, z = 0} end,
  getVelocity = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getInitialLength = function() return 4.5 end, getInitialWidth = function() return 1.8 end,
  queueGameEngineLua = function() end}
electrics = {values = {wheelspeed = 0}}
mapmgr = {mapData = {}, getObjects = function() return {} end}
input = {event = function() end}
local observer = dofile("lua/vehicle/extensions/taxiDriverStockAiObserver.lua")
assert(observer.watch({routeNodes = {"a", "b", "c", "d"}}))
local nativeArgs = {path = {"a", "b", "c", "d"}, noOfLaps = 1}
assert(type(observer.prepareRouteIngress) == "function",
  "the observer must prepare native ingress before passing the resolved suffix")
assert(observer.prepareRouteIngress(nativeArgs))
assert(nativeArgs.path == nil and nativeArgs.wpTargetList[1] == "a" and
  nativeArgs.wpTargetList[2] == "b" and #nativeArgs.wpTargetList == 2,
  "only the first edge should use native point-to-node ingress planning")
assert(appends == 0, "suffix must wait until native AI has initialized its ingress plan")
observer.updateGFX(0.001)
assert(appends == 1 and appended[1] == "b" and appended[2] == "c" and appended[3] == "d",
  "first extension frame must extend the existing native path with the exact shared-node suffix")
observer.updateGFX(0.001)
assert(appends == 1, "native suffix must be appended exactly once")
mapmgr.mapData = nil
observer.prepareRouteIngress({path = {"a", "b", "loadedLater"}})
observer.updateGFX(0.001)
assert(appends == 1, "map loading must leave the native prefix intact until native AI can initialize it")
mapmgr.mapData = {}
observer.updateGFX(0.001)
assert(appends == 2 and appended[2] == "loadedLater",
  "suffix must be queued after the first native frame with available map data")
observer.prepareRouteIngress({path = {"a", "b", "other"}})
observer.pause({})
observer.updateGFX(0.001)
assert(appends == 2, "pause must cancel a pending suffix rather than restarting native manual AI")
observer.prepareRouteIngress({path = {"a", "b", "parked"}})
observer.requestPark({})
observer.updateGFX(0.001)
assert(appends == 2, "parking must cancel any queued ingress suffix")
print("PASS stock AI native ingress preserves the resolved suffix and cancellation")
