-- Native AI command contract. Run in a fresh Lua environment, like other tests/lua tests.
package.path = "lua/ge/extensions/?.lua;" .. package.path
local requestedRouteOptions
package.loaded["taxiDriver/aiDriverRoute"] = nil
package.preload["taxiDriver/aiDriverRoute"] = function()
  return {new = function() return {
    request = function(_, _, _, revision, callback, requestOptions)
      requestedRouteOptions = requestOptions
      callback(true, {path = {"a", "b", "c"}, routeRevision = revision})
      return true
    end,
    cancel = function() end
  } end}
end
log = function() end

local commands, native, observed, resolvedPath = {}, nil, nil, nil
local vehicle = {
  getID = function() return 42 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getVelocity = function() return {x = 0, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) commands[#commands + 1] = command end
}
getObjectByID = function() return vehicle end
extensions = {
  load = function() end,
  taxiDriverStockAiObserver = {
    watch = function(config) observed = config end,
    prepareRouteIngress = function(args)
      resolvedPath = args.path
      args.wpTargetList = {args.path[1], args.path[2]}
      args.path = nil
    end,
    unwatch = function() end
  }
}
electrics = {set_left_signal = function() end, set_right_signal = function() end}
ai = {driveUsingPath = function(config) native = config end}

local autopilot = dofile("lua/ge/extensions/taxiDriver/autopilot.lua")
local service = autopilot.new({phases = {toDestination = "drive"}})
service:configure({strictGpsRoute = true})
assert(service:enable(vehicle, "drive", {pos = {x = 200, y = 0, z = 0}}))
assert(requestedRouteOptions and requestedRouteOptions.strictGpsRoute == true,
  "the selected strict GPS profile must reach the route adapter")
assert(loadstring(commands[#commands]))()
assert(native.path == nil and native.wpTargetList[1] == "a" and native.wpTargetList[2] == "b" and
  #native.wpTargetList == 2 and resolvedPath[3] == "c",
  "native point-to-node ingress must receive only the first edge while the observer retains the exact suffix")
assert(observed.arrivalRadius < 8,
  "native braking must aim inside the GE 8 m completion radius, rather than stop at 14 m")
assert(observed.routeNodes and observed.routeNodes[3] == "c",
  "the observer needs the actual route nodes to retain upcoming legal speed limits during temporary caps")
print("PASS AI Driver BeamNG 0.40 native route contract")
