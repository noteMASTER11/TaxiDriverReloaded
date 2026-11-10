package.path = "lua/ge/extensions/?.lua;" .. package.path
package.loaded["taxiDriver/aiDriverRoute"] = nil
local requests = 0
package.preload["taxiDriver/aiDriverRoute"] = function() return {new = function() return {
  request = function(_, _, _, revision, callback)
    requests = requests + 1
    callback(true, {path = {"a", "b"}, routeRevision = revision})
    return true
  end, cancel = function() end
} end} end
log = function() end
local position = {x = 12, y = 0, z = 0}
local vehicle = {getID = function() return 42 end,
  getPosition = function() return position end,
  getDirectionVector = function() return {x = 0, y = 1, z = 0} end,
  queueLuaCommand = function() end}
getObjectByID = function() return vehicle end
local module = dofile("lua/ge/extensions/taxiDriver/autopilot.lua")
local target = {pos = {x = 1000, y = 0, z = 0}}
local function makeService()
  position = {x = 12, y = 0, z = 0}
  local service = module.new({phases = {toDestination = "drive"},
    getSpeedKmh = function() return 24 end})
  assert(service:enable(vehicle, "drive", target))
  return service
end
local circling = makeService()
local before = requests
for second = 1, 31 do
  local angle = second * math.pi / 6
  position = {x = 12 * math.cos(angle), y = 12 * math.sin(angle), z = 0}
  circling:update(vehicle, "drive", target, 1)
end
assert(requests == before + 1 and circling:getDiagnostics().circlingRecoveryAttempt == 1,
  "moving in a small circle must trigger one bounded native route replan")
for second = 32, 63 do
  local angle = second * math.pi / 6
  position = {x = 12 * math.cos(angle), y = 12 * math.sin(angle), z = 0}
  circling:update(vehicle, "drive", target, 1)
end
assert(requests == before + 1 and circling:getDiagnostics().parking and
  circling:getDiagnostics().reason == "circlingAfterRecovery",
  "persistent circling must park after the one replan rather than retry indefinitely")
local progressing = makeService()
before = requests
for second = 1, 65 do
  position = {x = 12 + second * 6, y = 0, z = 0}
  progressing:update(vehicle, "drive", target, 1)
end
assert(requests == before and not progressing:getDiagnostics().parking,
  "ordinary moving progress must not trigger circling recovery")
print("PASS AI moving-circle recovery is bounded and forward travel is preserved")
