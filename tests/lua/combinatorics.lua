package.path = "lua/ge/extensions/?.lua;" .. package.path

package.preload["gameplay/route/route"] = function() return {} end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = log or function() end

local tripEvents = dofile("lua/ge/extensions/taxiDriver/tripEvents.lua")
local shiftTracker = dofile("lua/ge/extensions/taxiDriver/shiftTracker.lua")
local shiftHistory = dofile("lua/ge/extensions/taxiDriver/shiftHistory.lua")
local offerGenerator = dofile("lua/ge/extensions/taxiDriver/offerGenerator.lua")
local hudPublisher = dofile("lua/ge/extensions/taxiDriver/hudPublisher.lua")
local vehicleScanGuard = dofile("lua/ge/extensions/taxiDriver/vehicleScanGuard.lua")
local vehicleControl = dofile("lua/ge/extensions/taxiDriver/vehicleControl.lua")
local delivery = dofile("lua/ge/extensions/taxiDriver/delivery.lua")
local routePlanner = dofile("lua/ge/extensions/taxiDriver/routePlanner.lua")
local autopilotModule = dofile("lua/ge/extensions/taxiDriver/autopilot.lua")
local taxiConfig = dofile("lua/ge/extensions/taxiDriver/config.lua")

local defaultAiDriver = taxiConfig.sanitizeAiDriver(nil)
assert(defaultAiDriver.preset == "balanced")
assert(defaultAiDriver.obeySpeedLimits == true and defaultAiDriver.obeyTrafficSignals == true)
local legacyAiDriver = taxiConfig.sanitizeAiDriver({
  aggressionPercent = 42, obeyTrafficRules = false, allowOvertaking = false
})
assert(legacyAiDriver.preset == "custom")
assert(legacyAiDriver.aggressionPercent == 42)
assert(legacyAiDriver.obeySpeedLimits == false and legacyAiDriver.obeyTrafficSignals == false)
local independentAiDriver = taxiConfig.sanitizeAiDriver({
  preset = "custom", obeySpeedLimits = false, obeyTrafficSignals = true,
  laneChangeClearancePercent = 999, recoveryMaxAttempts = 0, finalApproachSpeedKmh = 99
})
assert(independentAiDriver.obeySpeedLimits == false and independentAiDriver.obeyTrafficSignals == true)
assert(independentAiDriver.laneChangeClearancePercent == 175)
assert(independentAiDriver.recoveryMaxAttempts == 1)
assert(independentAiDriver.finalApproachSpeedKmh == 20)
for _, preset in ipairs(taxiConfig.aiDriverPresetOrder) do
  local configured = taxiConfig.sanitizeAiDriver({preset = preset})
  assert(configured.preset == preset)
  if preset ~= "custom" then
    assert(configured.aggressionPercent == taxiConfig.aiDriverPresets[preset].aggressionPercent)
  end
end

assert(routePlanner.isDistanceAllowed(25000, 1000, 25000))
assert(not routePlanner.isDistanceAllowed(25001, 1000, 25000))
assert(routePlanner.isDistanceAllowed(250000, 1000, nil))
assert(not routePlanner.isDistanceAllowed(999, 1000, nil))

local autopilotCommands = {}
local autopilotPosition = {x = 0, y = 0, z = 0}
local autopilotSpeed = 0
local autopilotVehicle = {
  getID = function() return 1 end,
  getPosition = function() return autopilotPosition end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) autopilotCommands[#autopilotCommands + 1] = command end
}
local autopilotPhases = {
  toPickup = "toPickup", toStop = "toStop", toDestination = "toDestination",
  toFuelStation = "toFuelStation", boarding = "boarding", stopWaiting = "stopWaiting"
}
local autopilotTarget = {
  pos = {x = 100, y = 0, z = 0}, nodeA = "road2", nodeB = "road3"
}
local initialRoadLink = {oneWay = false}
map = {
  objects = {[2] = {pos = {x = 15, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}},
  getMap = function()
    return {nodes = {
      road0 = {pos = {x = 0, y = 0, z = 0}, radius = 6, links = {road1 = initialRoadLink}},
      road1 = {pos = {x = 200, y = 0, z = 0}, radius = 6, links = {road0 = initialRoadLink}}
    }}
  end,
  findClosestRoad = function() return "road0", "road1" end
}
local autopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 2, recoveryRetryInterval = 1, recoverySuccessDistance = 5},
  getSpeedKmh = function() return autopilotSpeed end,
  getRoutePath = function()
    return {{wp = "road0"}, {wp = "road1"}, {wp = "road2"}}
  end
})
assert(autopilot:enable(autopilotVehicle, "toDestination", autopilotTarget))
assert(load(autopilotCommands[#autopilotCommands]))
assert(autopilotCommands[#autopilotCommands]:find("ai.driveUsingPath", 1, true))
assert(autopilotCommands[#autopilotCommands]:find('avoidCars="on"', 1, true))
assert(autopilotCommands[#autopilotCommands]:find("enableElectrics=true", 1, true))
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 1)
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 1)
assert(autopilot:getHud(true).status == "recovering")
assert(not autopilotCommands[#autopilotCommands]:find('ai.setAvoidCars("off")', 1, true))
assert(autopilotCommands[#autopilotCommands]:find("taxiDriverAutopilotRecovery.start", 1, true))
assert(autopilotCommands[#autopilotCommands]:find("signal=-1", 1, true))
autopilotPosition = {x = 7, y = 0, z = 0}
assert(autopilot:onBypassComplete(autopilotVehicle, true, autopilotTarget))
assert(autopilot:getHud(true).status == "driving")
assert(autopilotCommands[#autopilotCommands]:find('avoidCars="on"', 1, true))
autopilot:update(autopilotVehicle, "stopWaiting", nil, 1)
assert(autopilot:isEnabled() and autopilot:getHud(true).status == "paused")

core_trafficSignals = {
  getMapNodeSignals = function()
    return {road1 = {road2 = {{action = 2, pos = {x = 20, y = 0, z = 0}}}}}
  end
}
autopilotTarget = {pos = {x = 120, y = 0, z = 0}, nodeA = "road2", nodeB = "road3"}
autopilotSpeed = 72
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 0.2)
local redSignalLimit = tonumber(autopilotCommands[#autopilotCommands]:match("ai.setSpeed%(([%d%.]+)%)"))
assert(redSignalLimit and redSignalLimit < 20)
autopilotSpeed = 0
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 0.1)
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 3)
assert(autopilot:getHud(true).status == "waitingSignal")
assert(autopilot:getHud(true).stuckSeconds == 0)
autopilotPosition = {x = 21, y = 0, z = 0}
autopilotSpeed = 10
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 0.2)
assert(autopilot:getHud(true).status == "driving")
core_trafficSignals = nil
autopilot:disable(autopilotVehicle, "test")
assert(not autopilot:isEnabled())

local exactApproachCommands = {}
local exactApproachVehicle = {
  getID = function() return 9 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) exactApproachCommands[#exactApproachCommands + 1] = command end
}
local exactApproachTarget = {
  pos = {x = 27, y = 0, z = 0}, nodeA = "road2", nodeB = "road3", exactApproach = true
}
local exactApproach = autopilotModule.new({
  phases = autopilotPhases,
  config = {directApproachDelay = 1},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}, {wp = "road2"}} end
})
assert(exactApproach:enable(exactApproachVehicle, "toDestination", exactApproachTarget))
assert(exactApproach:onRouteDone(exactApproachVehicle, exactApproachTarget))
exactApproach:update(exactApproachVehicle, "toDestination", exactApproachTarget, 0.01)
assert(exactApproach:getHud(true).status == "approaching")
assert(exactApproachCommands[#exactApproachCommands]:find("stopAtEnd=true", 1, true))
assert(exactApproachCommands[#exactApproachCommands]:find("completionRadius=1.25", 1, true))
assert(exactApproach:onBypassComplete(exactApproachVehicle, true, exactApproachTarget))
assert(exactApproachCommands[#exactApproachCommands]:find('ai.setMode("stop")', 1, true))

for _, phase in ipairs({"toPickup", "toStop", "toDestination", "toFuelStation"}) do
  local commands = {}
  local controller = autopilotModule.new({
    phases = autopilotPhases,
    getSpeedKmh = function() return 0 end,
    getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}, {wp = "road2"}} end
  })
  local vehicleForPhase = {
    getPosition = function() return {x = 0, y = 0, z = 0} end,
    queueLuaCommand = function(_, command) commands[#commands + 1] = command end
  }
  assert(controller:enable(vehicleForPhase, phase, {pos = {x = 7, y = 0, z = 0}, nodeB = "road3"}))
  controller:update(vehicleForPhase, phase, {pos = {x = 7, y = 0, z = 0}, nodeB = "road3"}, 0.1)
  assert(commands[#commands]:find('ai.setMode("stop")', 1, true))
  controller:disable(vehicleForPhase, "matrix")
end

local alternatingCommands = {}
local alternatingAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 1, recoveryRetryInterval = 1},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}, {wp = "road2"}} end
})
local alternatingVehicle = {
  getID = function() return 1 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) alternatingCommands[#alternatingCommands + 1] = command end
}
assert(alternatingAutopilot:enable(alternatingVehicle, "toDestination",
  {pos = {x = 100, y = 0, z = 0}, nodeB = "road3"}))
alternatingAutopilot:update(alternatingVehicle, "toDestination",
  {pos = {x = 100, y = 0, z = 0}, nodeB = "road3"}, 1)
local firstBypass = alternatingCommands[#alternatingCommands]
alternatingAutopilot:update(alternatingVehicle, "toDestination",
  {pos = {x = 100, y = 0, z = 0}, nodeB = "road3"}, 1)
local secondBypass = alternatingCommands[#alternatingCommands]
assert(firstBypass == secondBypass and alternatingAutopilot:getHud(true).recoveryAttempt == 1)

local savedMap = map
local roadLink = {oneWay = false}
map = {
  objects = {[2] = {pos = {x = 15, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}},
  getMap = function()
    return {nodes = {
      road0 = {pos = {x = 0, y = 0, z = 0}, radius = 6, links = {road1 = roadLink}},
      road1 = {pos = {x = 200, y = 0, z = 0}, radius = 6, links = {road0 = roadLink}}
    }}
  end,
  findClosestRoad = function() return "road0", "road1" end,
  getRoadRules = function() return {rightHandDrive = false} end
}
local corridorCommands = {}
local corridorVehicle = {
  getID = function() return 1 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) corridorCommands[#corridorCommands + 1] = command end
}
local corridorAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 1},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(corridorAutopilot:enable(corridorVehicle, "toDestination", autopilotTarget))
corridorAutopilot:update(corridorVehicle, "toDestination", autopilotTarget, 1)
assert(corridorCommands[#corridorCommands]:find("taxiDriverAutopilotRecovery", 1, true))
assert(corridorCommands[#corridorCommands]:find("signal=-1", 1, true))
assert(corridorAutopilot:onBypassComplete(corridorVehicle, true, autopilotTarget))
assert(corridorCommands[#corridorCommands]:find("ai.driveUsingPath", 1, true))

map.objects[2] = {pos = {x = 5, y = 0, z = 0}, dirVec = {x = 1, y = 0, z = 0}}
local blockedCommands = {}
local blockedVehicle = {
  getID = corridorVehicle.getID,
  getPosition = corridorVehicle.getPosition,
  getDirectionVector = corridorVehicle.getDirectionVector,
  queueLuaCommand = function(_, command) blockedCommands[#blockedCommands + 1] = command end
}
local blockedAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 1, oncomingRetryInterval = 2, oncomingMaxWait = 20},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(blockedAutopilot:enable(blockedVehicle, "toDestination", autopilotTarget))
blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 1)
assert(blockedAutopilot:getHud(true).status == "recovering")
assert(blockedCommands[#blockedCommands]:find("startReverseEscape", 1, true))
assert(blockedCommands[#blockedCommands]:find("minDistance=3.00", 1, true))
assert(blockedCommands[#blockedCommands]:find("maxDistance=6.00", 1, true))
assert(blockedAutopilot:onBypassComplete(blockedVehicle, false, autopilotTarget, "rearBlocked"))
assert(blockedAutopilot:getHud(true).status == "waitingTraffic")
core_trafficSignals = {
  getMapNodeSignals = function()
    return {road0 = {road1 = {{action = 2, state = "redTrafficLight",
      instance = "queueSignal", pos = {x = 20, y = 0, z = 0}}}}}
  end
}
blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 0.2)
assert(blockedAutopilot:getHud(true).status == "waitingSignal")
map.objects[2].vel = {x = 3, y = 0, z = 0}
core_trafficSignals.getMapNodeSignals = function()
  return {road0 = {road1 = {{action = 0, state = "greenTrafficLight",
    instance = "queueSignal", pos = {x = 20, y = 0, z = 0}}}}}
end
blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 0.2)
assert(blockedAutopilot:getHud(true).status == "driving")
core_trafficSignals = nil
map.objects[2] = nil

local clearCommands = {}
map.objects[2] = {pos = {x = 5, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
local clearAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 1, oncomingRetryInterval = 0.1},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
local clearVehicle = {
  getID = corridorVehicle.getID,
  getPosition = corridorVehicle.getPosition,
  getDirectionVector = corridorVehicle.getDirectionVector,
  queueLuaCommand = function(_, command) clearCommands[#clearCommands + 1] = command end
}
assert(clearAutopilot:enable(clearVehicle, "toDestination", autopilotTarget))
clearAutopilot:update(clearVehicle, "toDestination", autopilotTarget, 1)
assert(clearAutopilot:getHud(true).status == "recovering")
assert(clearCommands[#clearCommands]:find("startReverseEscape", 1, true))
assert(clearAutopilot:onBypassComplete(clearVehicle, false, autopilotTarget, "rearBlocked"))
assert(clearAutopilot:getHud(true).status == "waitingTraffic")
map.objects[2] = nil
clearAutopilot:update(clearVehicle, "toDestination", autopilotTarget, 0.2)
assert(clearAutopilot:getHud(true).status == "driving")
assert(clearCommands[#clearCommands]:find("ai.driveUsingPath", 1, true))

map.objects[3] = {pos = {x = 45, y = 0, z = 0}, vel = {x = 10, y = 0, z = 0}}
local followingCommands = {}
local followingVehicle = {
  getID = corridorVehicle.getID,
  getPosition = corridorVehicle.getPosition,
  getDirectionVector = corridorVehicle.getDirectionVector,
  getInitialLength = function() return 4.5 end,
  getInitialWidth = function() return 2 end,
  queueLuaCommand = function(_, command) followingCommands[#followingCommands + 1] = command end
}
local followingAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 72 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(followingAutopilot:enable(followingVehicle, "toDestination", autopilotTarget))
followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2)
local followingLimit = tonumber(followingCommands[#followingCommands]:match("ai.setSpeed%(([%d%.]+)%)"))
assert(followingLimit and followingLimit > 10 and followingLimit < 20)
map.objects[3] = nil
followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2)
assert(followingCommands[#followingCommands]:find('ai.setSpeedMode("legal")', 1, true))

roadLink.lanes, roadLink.inNode = "--++", "road0"
map.getMap = function()
  return {nodes = {
    road0 = {pos = {x = 0, y = 0, z = 0}, radius = 8, links = {road1 = roadLink}},
    road1 = {pos = {x = 200, y = 0, z = 0}, radius = 8, links = {road0 = roadLink}}
  }}
end
map.objects[3] = {pos = {x = 24, y = -5.4, z = 0}, vel = {x = 3, y = 0, z = 0}}
local overtakeCommands = {}
local overtakeVehicle = {
  getID = function() return 1 end,
  getPosition = function() return {x = 0, y = -5.4, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getInitialLength = followingVehicle.getInitialLength,
  getInitialWidth = followingVehicle.getInitialWidth,
  queueLuaCommand = function(_, command) overtakeCommands[#overtakeCommands + 1] = command end
}
local overtakeAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 72 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(overtakeAutopilot:enable(overtakeVehicle, "toDestination", autopilotTarget))
for _ = 1, 12 do overtakeAutopilot:update(overtakeVehicle, "toDestination", autopilotTarget, 0.2) end
local overtakeStarted, overtakeSignaled = false, false
for _, command in ipairs(overtakeCommands) do
  overtakeStarted = overtakeStarted or command:find("ai.laneChange", 1, true) ~= nil
  overtakeSignaled = overtakeSignaled or command:find("set_left_signal(true", 1, true) ~= nil
end
assert(overtakeStarted and overtakeSignaled)

local innerLaneCommands = {}
local innerLaneVehicle = {
  getID = overtakeVehicle.getID,
  getPosition = function() return {x = 0, y = -1.8, z = 0} end,
  getDirectionVector = overtakeVehicle.getDirectionVector,
  getInitialLength = overtakeVehicle.getInitialLength,
  getInitialWidth = overtakeVehicle.getInitialWidth,
  queueLuaCommand = function(_, command) innerLaneCommands[#innerLaneCommands + 1] = command end
}
map.objects[3].pos.y = -1.8
local innerLaneAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 72 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(innerLaneAutopilot:enable(innerLaneVehicle, "toDestination", autopilotTarget))
for _ = 1, 15 do innerLaneAutopilot:update(innerLaneVehicle, "toDestination", autopilotTarget, 0.2) end
for _, command in ipairs(innerLaneCommands) do assert(not command:find("ai.laneChange", 1, true)) end

local configuredCommands = {}
local configuredVehicle = {
  getID = overtakeVehicle.getID,
  getPosition = overtakeVehicle.getPosition,
  getDirectionVector = overtakeVehicle.getDirectionVector,
  getInitialLength = overtakeVehicle.getInitialLength,
  getInitialWidth = overtakeVehicle.getInitialWidth,
  queueLuaCommand = function(_, command) configuredCommands[#configuredCommands + 1] = command end
}
map.objects[3].pos.y = -5.4
local configuredAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 72 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
configuredAutopilot:configure({
  obeyTrafficRules = false, allowOvertaking = false, allowOncomingRecovery = false,
  aggressionPercent = 55, followingTimeGap = 3.1, brakingDeceleration = 2.1,
  stuckDelaySeconds = 24, laneChangeClearancePercent = 150,
  recoveryMaxAttempts = 2, finalApproachSpeedKmh = 9
})
assert(configuredAutopilot:enable(configuredVehicle, "toDestination", autopilotTarget))
assert(configuredCommands[1]:find('aggression=0.55', 1, true))
assert(configuredCommands[1]:find('routeSpeedMode="off"', 1, true))
assert(configuredCommands[1]:find('setSafetyConfig({timeGap=3.1,comfortableDeceleration=2.1})', 1, true))
for _ = 1, 15 do configuredAutopilot:update(configuredVehicle, "toDestination", autopilotTarget, 0.2) end
for _, command in ipairs(configuredCommands) do assert(not command:find("ai.laneChange", 1, true)) end

for _, obeySpeedLimits in ipairs({false, true}) do
  for _, obeyTrafficSignals in ipairs({false, true}) do
    for _, allowOvertaking in ipairs({false, true}) do
      for _, allowRecovery in ipairs({false, true}) do
        for _, profile in ipairs({
          {aggressionPercent = 10, followingTimeGap = 1.2, brakingDeceleration = 1.5, stuckDelaySeconds = 8},
          {aggressionPercent = 80, followingTimeGap = 3.5, brakingDeceleration = 4.5, stuckDelaySeconds = 30}
        }) do
          local commands = {}
          local matrixVehicle = {
            getID = overtakeVehicle.getID,
            getPosition = function() return {x = 0, y = -5.4, z = 0} end,
            getDirectionVector = overtakeVehicle.getDirectionVector,
            getInitialLength = overtakeVehicle.getInitialLength,
            getInitialWidth = overtakeVehicle.getInitialWidth,
            queueLuaCommand = function(_, command) commands[#commands + 1] = command end
          }
          local matrixAutopilot = autopilotModule.new({
            phases = autopilotPhases,
            getSpeedKmh = function() return 36 end,
            getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
          })
          profile.obeySpeedLimits = obeySpeedLimits
          profile.obeyTrafficSignals = obeyTrafficSignals
          profile.allowOvertaking = allowOvertaking
          profile.allowOncomingRecovery = allowRecovery
          profile.allowReverseRecovery = allowRecovery
          profile.laneChangeClearancePercent = obeySpeedLimits and 175 or 50
          profile.recoveryMaxAttempts = allowRecovery and 5 or 1
          profile.finalApproachSpeedKmh = obeyTrafficSignals and 5 or 20
          matrixAutopilot:configure(profile)
          assert(matrixAutopilot:enable(matrixVehicle, "toDestination", autopilotTarget))
          assert(commands[1]:find('routeSpeedMode="' .. (obeySpeedLimits and "legal" or "off") .. '"', 1, true))
          for _ = 1, 5 do matrixAutopilot:update(matrixVehicle, "toDestination", autopilotTarget, 0.2) end
        end
      end
    end
  end
end
map = savedMap

local logLines = {}
log = function(level, tag, message)
  logLines[#logLines + 1] = {level = level, tag = tag, message = message}
end
local debugLogging = true
local debugLogger = dofile("lua/ge/extensions/taxiDriver/logger.lua")
debugLogger.setEnabledProvider(function() return debugLogging end)
debugLogger.info("test", "enabled", {value = 1})
assert(#logLines == 1 and logLines[1].message:find("[TaxiDriver]", 1, true))
debugLogging = false
debugLogger.info("test", "disabled")
assert(#logLines == 1)
debugLogger.warn("test", "warning_visible")
assert(#logLines == 2 and logLines[2].level == "W")

math.randomseed(240717)

local orderTypes = {
  {name = "passenger", delivery = false, rush = false, multi = false},
  {name = "rush", delivery = false, rush = true, multi = false},
  {name = "multiStop", delivery = false, rush = false, multi = true},
  {name = "delivery", delivery = true, rush = false, multi = false}
}

for _, realistic in ipairs({false, true}) do
  for _, eventsEnabled in ipairs({false, true}) do
    for _, order in ipairs(orderTypes) do
      for _ = 1, 250 do
        local event = eventsEnabled and
          tripEvents.create(order.delivery, order.rush, order.multi) or {kind = "none"}
        assert(type(event) == "table" and type(event.kind) == "string")
        if not eventsEnabled then assert(event.kind == "none") end
        if order.delivery then
          assert(event.kind == "none" or event.kind == "fragileCargo")
        elseif order.rush or order.multi then
          assert(event.kind == "none" or event.kind == "cancellation" or event.kind == "tip")
        end
        if tripEvents.needsTarget(event) then
          assert(not order.delivery and not order.rush and not order.multi)
          event.target = {routeDistance = 1200}
          assert(tripEvents.shouldTriggerOnRoute(event, event.triggerProgress or 1))
          assert(not tripEvents.shouldTriggerOnRoute(event, 1))
        end
      end
      assert(realistic == true or realistic == false)
    end
  end
end

local cancellation = {kind = "cancellation", triggerSeconds = 2, elapsed = 0}
assert(not tripEvents.updateBeforePickup(cancellation, 1))
assert(tripEvents.updateBeforePickup(cancellation, 1))
assert(not tripEvents.updateBeforePickup(cancellation, 10))

assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0, false) == 2)
assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0.1, false) == 0)
assert(tripEvents.calculateTip({kind = "tip", condition = "quick", rate = 0.1}, 20, 0, true) == 2)

local shifts = shiftTracker.new(nil)
shifts:start()
shifts:recordRide(20, 4.5, 2, true)
shifts:recordFuelCost(3)
local completed = shifts:finish()
assert(completed.rides == 1)
assert(completed.grossIncome == 20)
assert(completed.netIncome == 17)
assert(completed.averageRating == 4.5)
assert(completed.aiRides == 1)
assert(not shifts:getHud().active)
shifts:setAllRatings(3.25)
assert(shifts:getHud().last.averageRating == 3.25)
assert(shifts:getHud().last.ratingTotal == 3.25)

local published = {}
local function encode(value)
  local keys = {}
  for key, _ in pairs(value or {}) do table.insert(keys, tostring(key)) end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do table.insert(parts, key .. "=" .. tostring(value[key])) end
  return table.concat(parts, ";")
end
local function trigger(name, payload)
  table.insert(published, {name = name, payload = payload})
end
local hudState = {active = true, currentSpeed = 20, settings = {language = "en"}}
hudPublisher.publishFull(hudState, trigger, encode)
assert(#published == 1 and published[1].name == "TaxiDriverHUDState")
local hudEpoch = published[1].payload.hudEpoch
assert(type(hudEpoch) == "string" and hudEpoch ~= "")
assert(published[1].payload.hudRevision == 1)
assert(not hudPublisher.publishPatch(hudState, trigger, encode))
hudState.currentSpeed = 21
assert(hudPublisher.publishPatch(hudState, trigger, encode))
assert(#published == 2 and published[2].name == "TaxiDriverHUDPatch")
assert(published[2].payload.values.currentSpeed == 21)
assert(published[2].payload.epoch == hudEpoch)
assert(published[2].payload.baseRevision == 1)
assert(published[2].payload.revision == 2)
assert(hudPublisher.clientNeedsSync(hudEpoch, 1))
assert(not hudPublisher.clientNeedsSync(hudEpoch, 2))
hudState.settings.language = "de"
assert(not hudPublisher.publishPatch(hudState, trigger, encode))

for _ = 1, 10000 do
  local job = offerGenerator.create(function()
    error("synthetic late next-offer failure")
  end, 0)
  local status, errorMessage = offerGenerator.step(job, 1)
  assert(status == "error")
  assert(tostring(errorMessage):find("synthetic late next-offer failure", 1, true))
end

local vehicleCommands = {}
local commandVehicle = {queueLuaCommand = function(_, command)
  table.insert(vehicleCommands, command)
end}
vehicleControl.setTelemetryEnabled(commandVehicle, true)
vehicleControl.setTelemetryEnabled(commandVehicle, false)
delivery.applyVehicleMass(commandVehicle, 75)
delivery.applyVehicleMass(commandVehicle, 0)
assert(vehicleCommands[1]:find("extensions.load('taxiDriverTelemetry')", 1, true))
assert(vehicleCommands[2]:find("extensions.unload('taxiDriverTelemetry')", 1, true))
assert(vehicleCommands[3]:find("extensions.load('taxiDriverCargo')", 1, true))
assert(vehicleCommands[4]:find("extensions.unload('taxiDriverCargo')", 1, true))
local telemetryExtension = dofile("lua/vehicle/extensions/taxiDriverTelemetry.lua")
telemetryExtension.onReset()

local detailLookups = 0
local position = {x = 0, y = 0, z = 0}
function position:distance() return 0 end
local vehicle = {
  jbeam = "etk800",
  partConfig = "/vehicles/etk800/base.pc"
}
function vehicle:getID() return 42 end
function vehicle:getPosition() return position end
be = {getPlayerVehicle = function() return vehicle end}
FS = {
  fileExists = function() return false end,
  directoryExists = function() return true end,
  directoryCreate = function() end
}
jsonWriteFile = function() end
vec3 = function(x, y, z)
  local value = {x = x, y = y, z = z}
  function value:distance() return 0 end
  return value
end
core_vehicles = {
  getModelList = function() return {models = {etk800 = {key = "etk800"}}} end,
  getModel = function(modelKey)
    if modelKey == "etk800" then
      return {model = {key = "etk800"}, configs = {base = {key = "base"}}}
    end
    return {}
  end,
  getVehicleDetails = function()
    detailLookups = detailLookups + 1
    return {
      model = {Brand = "ETK", Name = "800 Series"},
      configs = {Name = "854t"},
      current = {config_key = "base"}
    }
  end
}
shiftHistory.load("test")
local savedShiftId = shiftHistory.begin({
  modelKey = "etk800", configKey = "base", configPath = "/vehicles/etk800/base.pc",
  name = "ETK 854t", preview = "/vehicles/etk800/base.png"
}, {energyType = "gasoline", percent = 64, fuelPercent = 64}, {rides = 2, netIncome = 18})
assert(savedShiftId and not shiftHistory.update(59, {rides = 2, netIncome = 18}))
assert(shiftHistory.update(1, {rides = 3, netIncome = 25}))
assert(shiftHistory.saveSnapshot(savedShiftId, nil,
  {energyType = "gasoline", percent = 51, fuelPercent = 51},
  {rides = 3, netIncome = 25, averageRating = 4.5}))
local removedShiftId = shiftHistory.begin({
  modelKey = "removed_mod", configKey = "missing", name = "Removed car"
}, {energyType = "gasoline", percent = 20}, {})
shiftHistory.finish(nil, nil, {})
assert(not shiftHistory.get(removedShiftId))
assert(shiftHistory.updateValidation(2))
assert(not shiftHistory.pruneUnavailable())
assert(shiftHistory.get(savedShiftId).energy.fuelPercent == 51)
shiftHistory.setRestoring(savedShiftId)
assert(shiftHistory.buildHud().restoringId == savedShiftId)
shiftHistory.setRestoring(nil)
local vehicleHistory = dofile("lua/ge/extensions/taxiDriver/vehicleHistory.lua")
vehicleHistory.load("test")
assert(vehicleHistory.refreshCurrentVehicle())
local originalKey = vehicleHistory.getCurrentHud().key
vehicle.partConfig = "/vehicles/etk800/live_parts_edit.pc"
for _ = 1, 500 do
  vehicleHistory.onVehicleReset(42)
  assert(not vehicleHistory.update(0.016, 0))
  assert(vehicleHistory.getCurrentHud().key == originalKey)
end
assert(detailLookups == 1)

assert(not vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.onUiChangedState("menu.vehicleconfig.parts", "play"))
local staleGeneration = vehicleScanGuard.getGeneration()
assert(vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.isConfigurationOpen())
for _ = 1, 500 do
  vehicleScanGuard.update(0.016)
  assert(vehicleScanGuard.isSuspended())
end
assert(vehicleScanGuard.onUiChangedState("play", "menu.vehicleconfig.parts"))
assert(vehicleScanGuard.isSuspended())
assert(not vehicleScanGuard.isConfigurationOpen())
assert(not vehicleScanGuard.isRequestCurrent(staleGeneration))
for _ = 1, 93 do vehicleScanGuard.update(0.016) end
assert(vehicleScanGuard.isSuspended())
assert(vehicleScanGuard.update(0.016))
assert(not vehicleScanGuard.isSuspended())
local stableGeneration = vehicleScanGuard.getGeneration()
assert(vehicleScanGuard.isRequestCurrent(stableGeneration))
assert(vehicleScanGuard.onVehicleLifecycle(42, 42))
assert(vehicleScanGuard.isSuspended())
assert(not vehicleScanGuard.onVehicleLifecycle(7, 42))

local recoveryInputs, recoveryCallbacks = {}, {}
local safetyObjects = {}
local recoveryPosition = {x = 0, y = 0, z = 0}
input = {state = {steering = {val = 0}}, event = function(name, value, _, _, _, _, source)
  recoveryInputs[name], recoveryInputs[name .. "Source"] = value, source
end}
electrics = {
  values = {wheelspeed = 0, ignitionLevel = 2, gearIndex = 1},
  setIgnitionLevel = function(value) electrics.values.ignitionLevel = value end,
  set_left_signal = function(value) recoveryInputs.leftSignal = value end,
  set_right_signal = function(value) recoveryInputs.rightSignal = value end
}
mapmgr = {getObjects = function() return safetyObjects end}
obj = {
  getID = function() return 42 end,
  getPosition = function() return recoveryPosition end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getInitialLength = function() return 4.5 end,
  getInitialWidth = function() return 2 end,
  getObjectCenterPosition = function(_, id) return safetyObjects[id] and safetyObjects[id].pos end,
  getObjectDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  getObjectInitialLength = function() return 4.5 end,
  getObjectInitialWidth = function() return 2 end,
  queueGameEngineLua = function(_, command) recoveryCallbacks[#recoveryCallbacks + 1] = command end
}
local gearboxCalls = {}
local mainController = {gearboxBehavior = "realistic"}
mainController.setGearboxMode = function(mode)
  gearboxCalls.mode = mode
  gearboxCalls.modeCount = (gearboxCalls.modeCount or 0) + 1
  mainController.gearboxBehavior = mode
end
mainController.shiftToGearIndex = function(index)
  gearboxCalls.gear = index
  gearboxCalls.directShifts = (gearboxCalls.directShifts or 0) + 1
  mainController.gearboxBehavior = "realistic"
end
controller = {mainController = mainController}
guihooks = {trigger = function() end}
local recoveryController = dofile("lua/vehicle/extensions/taxiDriverAutopilotRecovery.lua")
assert(recoveryController.watchRouteDone())
recoveryController.setGearboxOverride(true)
assert(gearboxCalls.mode == "arcade" and gearboxCalls.modeCount == 1)
recoveryController.setGearboxOverride(true)
assert(gearboxCalls.modeCount == 1)
guihooks.trigger("AIStatusChange", {status = "route done", category = "route"})
assert(recoveryCallbacks[#recoveryCallbacks]:find("onAutopilotRouteDone(42)", 1, true))
local recoveryPoints = {
  {x = 6, y = 2, z = 0}, {x = 12, y = 4, z = 0}, {x = 27, y = 4, z = 0},
  {x = 36, y = 2, z = 0}, {x = 44, y = 0, z = 0}
}
assert(recoveryController.start({points = recoveryPoints, targetSpeed = 7, timeout = 14, signal = -1}))
assert(gearboxCalls.mode == "arcade" and not gearboxCalls.directShifts)
recoveryController.updateGFX(0.1)
assert(recoveryInputs.leftSignal and recoveryInputs.steering > 0 and recoveryInputs.throttle > 0)
for _, point in ipairs(recoveryPoints) do
  recoveryPosition = point
  recoveryController.updateGFX(0.1)
end
assert(recoveryCallbacks[#recoveryCallbacks]:find("onAutopilotBypassComplete(42,true", 1, true))

recoveryCallbacks = {}
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 0.4
assert(recoveryController.start({
  points = {{x = 6, y = 0, z = 0}}, targetSpeed = 3.5, timeout = 20,
  stopAtEnd = true, completionRadius = 6
}))
recoveryPosition = {x = 6, y = 0, z = 0}
recoveryController.updateGFX(0.1)
assert(recoveryCallbacks[#recoveryCallbacks]:find("onAutopilotBypassComplete(42,true", 1, true))
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 15
safetyObjects[77] = {pos = {x = 35, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
recoveryController.setGearboxOverride(true)
recoveryController.updateGFX(0.1)
assert(recoveryInputs.brake > 0 and recoveryInputs.brake < 1 and recoveryInputs.throttle == 0)
safetyObjects[77].pos = {x = 6, y = 0, z = 0}
recoveryController.updateGFX(0.1)
assert(recoveryInputs.brake == 1)
safetyObjects[77].pos = {x = 8, y = 2.2, z = 0}
input.state.steering.val = 1
recoveryController.updateGFX(0.1)
assert(recoveryInputs.brake > 0)

safetyObjects = {}
electrics.values.wheelspeed = 2
input.state = {steering = {val = 0}, throttle = {val = 0.5}, brake = {val = 0},
  parkingbrake = {val = 0}}
recoveryController.updateGFX(0.1)
electrics.values.wheelspeed = 0
electrics.values.gearIndex = 1
input.state.throttle.val = 0
input.state.brake.val = 1
recoveryController.updateGFX(0.1)
assert(recoveryInputs.throttle == 0.03 and recoveryInputs.brake == 1 and
  recoveryInputs.parkingbrake == 0)
assert(not gearboxCalls.directShifts and mainController.gearboxBehavior == "arcade")
electrics.values.gearIndex = 0
recoveryController.updateGFX(0.1)
assert(recoveryInputs.throttle == 0.12 and recoveryInputs.brake == 0 and
  recoveryInputs.parkingbrake == 1)
electrics.values.gearIndex = 1
electrics.values.wheelspeed = 0.3
input.state.throttle.val = 0.5
input.state.brake.val = 0
recoveryController.updateGFX(0.1)
assert(recoveryInputs.throttle == 0 and recoveryInputs.brake == 0 and
  recoveryInputs.parkingbrake == 0)

safetyObjects = {
  [88] = {pos = {x = 3, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
}
recoveryCallbacks = {}
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 0
electrics.values.gearIndex = 1
input.state.steering.val = 0
assert(recoveryController.startReverseEscape({
  minDistance = 3, maxDistance = 6, targetSpeed = 2.2, requireFrontBlocked = true
}))
assert(not gearboxCalls.directShifts and mainController.gearboxBehavior == "arcade")
recoveryController.updateGFX(0.1)
assert(not gearboxCalls.directShifts and mainController.gearboxBehavior == "arcade")
assert(recoveryInputs.throttle == 0 and recoveryInputs.brake > 0)
recoveryPosition = {x = -6, y = 0, z = 0}
recoveryController.updateGFX(0.1)
assert(recoveryCallbacks[#recoveryCallbacks]:find(
  'onAutopilotBypassComplete(42,true,"reverseComplete")', 1, true))

recoveryCallbacks = {}
recoveryPosition = {x = 0, y = 0, z = 0}
safetyObjects[89] = {pos = {x = -3, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
assert(not recoveryController.startReverseEscape({
  minDistance = 3, maxDistance = 6, requireFrontBlocked = true
}))
assert(recoveryCallbacks[#recoveryCallbacks]:find(
  'onAutopilotBypassComplete(42,false,"rearBlocked")', 1, true))
safetyObjects = {}
input.state.steering.val = 0
electrics.values.wheelspeed = 0
local starterRequests = 0
local engine = {starterMaxAV = 10, outputAV1 = 0}
powertrain = {getDevicesByType = function() return {engine} end}
mainController.setEngineIgnition = function(value) gearboxCalls.ignition = value end
mainController.setStarter = function(value) if value then starterRequests = starterRequests + 1 end end
electrics.values.ignitionLevel = 0
recoveryController.setGearboxOverride(false)
recoveryController.setGearboxOverride(true)
assert(gearboxCalls.modeCount == 1 and mainController.gearboxBehavior == "arcade")
recoveryController.updateGFX(0.1)
assert(electrics.values.ignitionLevel == 3 and gearboxCalls.ignition and starterRequests == 1)
engine.outputAV1 = 9
recoveryController.updateGFX(0.1)
assert(electrics.values.ignitionLevel == 2)
recoveryController.setGearboxOverride(false)
assert(gearboxCalls.mode == "arcade" and gearboxCalls.modeCount == 1)
assert(not gearboxCalls.directShifts)

print("TaxiDriver Lua combinatorics: adaptive bypass, trajectory rays, powertrain handshake, gameplay modes, and 500 deferred respawns passed")
