-- Physical passing-lane gate for both road rule directions.
local position, vehicles, racing, rightHandDrive
obj = {
  getID = function() return 42 end,
  getPosition = function() return position end,
  getVelocity = function() return {x = 10, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getInitialLength = function() return 4.5 end,
  getInitialWidth = function() return 1.8 end,
  getObjectInitialLength = function() return 4.5 end,
  getObjectInitialWidth = function() return 1.8 end,
  queueGameEngineLua = function() end
}
electrics = {values = {wheelspeed = 10}}
input = {event = function() end}
controller = nil
ai = {
  setSpeed = function() end,
  setSpeedMode = function() end,
  setRacing = function(value) racing = value end,
  getEdgeLaneConfig = function() return "++" end
}
local edge = {speedLimit = 20, oneWay = true, lanes = "++"}
mapmgr = {
  getObjects = function() return vehicles end,
  findClosestRoad = function() return "a", "b" end,
  mapData = {
    positions = {a = {x = 0, y = 0}, b = {x = 200, y = 0}},
    graph = {a = {b = edge}, b = {a = edge}}, radius = {a = 4, b = 4}
  },
  rules = {}
}
local observer = dofile("lua/vehicle/extensions/taxiDriverStockAiObserver.lua")
for _, driveOnLeft in ipairs({false, true}) do
  rightHandDrive = driveOnLeft
  mapmgr.rules.rightHandDrive = rightHandDrive
  -- Forward is +X; the vehicle's right is -Y. The ordinary travel lane is
  -- right-hand (Y=-2) in right-side traffic, left-hand (Y=2) otherwise.
  position = {x = 30, y = driveOnLeft and 2 or -2, z = 0}
  vehicles = {[7] = {pos = {x = 60, y = position.y, z = 0},
    vel = {x = 6, y = 0, z = 0}, dirVec = {x = 1, y = 0, z = 0}}}
  assert(observer.watch({allowOvertaking = true, targetX = 300,
    targetY = position.y, targetZ = 0}))
  for _ = 1, 24 do observer.updateGFX(0.1) end
  assert(racing == true, "passing must use the inner lane, not the outside road shoulder")
  observer.unwatch()
end
print("PASS stock AI passing lane follows right/left traffic rules")
