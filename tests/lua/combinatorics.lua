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
local aiLoggerModule = dofile("lua/ge/extensions/taxiDriver/aiLogger.lua")
local networkAddress = dofile("lua/ge/extensions/taxiDriver/networkAddress.lua")
local nextOfferGuard = dofile("lua/ge/extensions/taxiDriver/nextOfferGuard.lua")
local taxiConfig = dofile("lua/ge/extensions/taxiDriver/config.lua")

local guardedOffer = {id = 71}
local guarded = nextOfferGuard.update(guardedOffer, 0.2, false, 0.25,
  {active = true, hasTrip = true, phase = "toDestination", duration = 5})
assert(guarded.expired and guarded.reason == "timeout" and guarded.remaining == 0)
guarded = nextOfferGuard.update(guardedOffer, 5, false, 0,
  {active = true, hasTrip = true, phase = "complete", duration = 5})
assert(guarded.expired and guarded.reason == "phaseChanged")
guarded = nextOfferGuard.update(guardedOffer, 999999, false, 1,
  {active = true, hasTrip = true, phase = "toDestination", duration = 5})
assert(not guarded.expired and guarded.remaining == 4)
guarded = nextOfferGuard.update(guardedOffer, 0, true, 10,
  {active = true, hasTrip = true, phase = "complete", duration = 5})
assert(not guarded.expired)

assert(networkAddress.normalizeIPv4("IPv4 192.168.1.209 preferred") == "192.168.1.209")
assert(networkAddress.normalizeIPv4("999.168.1.1") == nil)
assert(networkAddress.isLanIPv4("10.0.0.4"))
assert(networkAddress.isLanIPv4("172.16.0.4"))
assert(networkAddress.isLanIPv4("172.31.255.254"))
assert(networkAddress.isLanIPv4("192.168.93.143"))
assert(networkAddress.isLanIPv4("100.64.1.2"))
assert(not networkAddress.isLanIPv4("127.0.0.1"))
assert(not networkAddress.isLanIPv4("169.254.1.2"))
assert(not networkAddress.isLanIPv4("172.32.0.4"))
local selectedNetworkAddress, addressCandidates = networkAddress.select({
  adapters = {
    {ipv4Addr = "172.25.192.1", description = "Hyper-V Virtual Ethernet Adapter"},
    {ipv4Addr = "10.8.0.2", description = "OpenVPN Data Channel Offload"},
    {ipv4Addr = "192.168.93.143", description = "Intel(R) Wi-Fi 6E AX211 160MHz"}
  },
  routedAddress = "10.8.0.2",
  savedAddress = "127.0.0.1",
  canBind = function() return true end
})
assert(selectedNetworkAddress == "192.168.93.143")
assert(#addressCandidates == 3)
selectedNetworkAddress = networkAddress.select({
  adapters = {}, routedAddress = "192.168.1.209",
  canBind = function(address) return address == "192.168.1.209" end
})
assert(selectedNetworkAddress == "192.168.1.209")
selectedNetworkAddress = networkAddress.select({
  adapters = {}, nativeAddress = "192.168.50.12",
  routedAddress = "172.25.192.1", canBind = function() return true end
})
assert(selectedNetworkAddress == "192.168.50.12")
selectedNetworkAddress = networkAddress.select({
  adapters = {}, savedAddress = "192.168.1.77",
  canBind = function() return false end
})
assert(selectedNetworkAddress == nil)

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
assert(exactApproachCommands[#exactApproachCommands]:find("completionRadius=0.80", 1, true))
assert(exactApproachCommands[#exactApproachCommands]:find("allowReverse=false", 1, true))
assert(select(2, exactApproachCommands[#exactApproachCommands]:gsub("{x=", "")) > 3)
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
local spatialCommands = {}
local spatialAutopilot = autopilotModule.new({phases = autopilotPhases,
  config = {stuckDelay = 1}, getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end})
local spatialVehicle = {getID = corridorVehicle.getID, getPosition = corridorVehicle.getPosition,
  getDirectionVector = corridorVehicle.getDirectionVector,
  queueLuaCommand = function(_, command) spatialCommands[#spatialCommands + 1] = command end}
assert(spatialAutopilot:enable(spatialVehicle, "toDestination", autopilotTarget))
spatialAutopilot:update(spatialVehicle, "toDestination", autopilotTarget, 1)
assert(spatialAutopilot:getHud(true).status == "recovering" and
  spatialCommands[#spatialCommands]:find("taxiDriverAutopilotRecovery.start", 1, true) and
  not spatialCommands[#spatialCommands]:find("startReverseEscape", 1, true))
assert(spatialAutopilot:onBypassComplete(spatialVehicle, true, autopilotTarget))
for index = 0, 23 do
  local angle = index * math.pi * 2 / 24
  map.objects[100 + index] = {pos = {x = math.cos(angle) * 4.5,
    y = math.sin(angle) * 4.5, z = 0}, vel = {x = 0, y = 0, z = 0}}
end
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
for index = 0, 23 do map.objects[100 + index] = nil end
core_trafficSignals.getMapNodeSignals = function()
  return {road0 = {road1 = {{action = 0, state = "greenTrafficLight",
    instance = "queueSignal", pos = {x = 20, y = 0, z = 0}}}}}
end
blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 0.2)
blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 2)
assert(blockedAutopilot:getHud(true).status ~= "waitingSignal")
core_trafficSignals = nil
map.objects[2] = nil

local clearCommands = {}
map.objects[2] = {pos = {x = 5, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
for index = 0, 23 do
  local angle = index * math.pi * 2 / 24
  map.objects[100 + index] = {pos = {x = math.cos(angle) * 4.5,
    y = math.sin(angle) * 4.5, z = 0}, vel = {x = 0, y = 0, z = 0}}
end
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
for index = 0, 23 do map.objects[100 + index] = nil end
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
followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2)
local followingLimit = tonumber(followingCommands[#followingCommands]:match("ai.setSpeed%(([%d%.]+)%)"))
assert(followingLimit and followingLimit > 10 and followingLimit < 20)
map.objects[3] = nil
for _ = 1, 5 do followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2) end
assert(followingCommands[#followingCommands]:find('ai.setSpeedMode("legal")', 1, true))

map.objects[3] = {pos = {x = 15, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
local rayObservation = {obstacleDetected = false, obstacleDistance = 10, driveReady = true}
local rayCommands = {}
local rayValidatedAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 36 end,
  getSafetyObservation = function() return rayObservation end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
local rayVehicle = {
  getID = followingVehicle.getID,
  getPosition = followingVehicle.getPosition,
  getDirectionVector = followingVehicle.getDirectionVector,
  getInitialLength = followingVehicle.getInitialLength,
  getInitialWidth = followingVehicle.getInitialWidth,
  queueLuaCommand = function(_, command) rayCommands[#rayCommands + 1] = command end
}
assert(rayValidatedAutopilot:enable(rayVehicle, "toDestination", autopilotTarget))
assert(rayCommands[1]:find("ai.setMode('disabled')", 1, true))
assert(not rayCommands[1]:find("ai.driveUsingPath", 1, true))
rayValidatedAutopilot:update(rayVehicle, "toDestination", autopilotTarget, 0.1)
assert(rayValidatedAutopilot:getHud(true).status == "driving")
for _ = 1, 3 do rayValidatedAutopilot:update(rayVehicle, "toDestination", autopilotTarget, 0.2) end
assert(rayValidatedAutopilot:getDiagnostics(rayVehicle, autopilotTarget, "toDestination").leadVehicleId == nil)
rayObservation = {obstacleDetected = true, obstacleDistance = 12.75, obstacleId = 3, driveReady = true}
rayValidatedAutopilot:update(rayVehicle, "toDestination", autopilotTarget, 0.2)
local rayDiagnostics = rayValidatedAutopilot:getDiagnostics(rayVehicle, autopilotTarget, "toDestination")
assert(rayDiagnostics.leadVehicleId == 3 and rayDiagnostics.leadRayConfirmed == true)

local escalationCommands = {}
local escalationGetMap = map.getMap
map.objects[3] = nil
map.getMap = function()
  local narrowLink = {oneWay = false}
  return {nodes = {
    road0 = {pos = {x = 0, y = 0, z = 0}, radius = 2.5, links = {road1 = narrowLink}},
    road1 = {pos = {x = 200, y = 0, z = 0}, radius = 2.5, links = {road0 = narrowLink}}
  }}
end
local escalationAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  config = {stuckDelay = 1, recoveryRepeatProgress = 2.5},
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}, {wp = "road2"}} end
})
local escalationVehicle = {
  getID = followingVehicle.getID,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = followingVehicle.getDirectionVector,
  queueLuaCommand = function(_, command) escalationCommands[#escalationCommands + 1] = command end
}
assert(escalationAutopilot:enable(escalationVehicle, "toDestination", autopilotTarget))
escalationAutopilot:update(escalationVehicle, "toDestination", autopilotTarget, 1)
assert(escalationCommands[#escalationCommands]:find("startReverseEscape", 1, true))
assert(escalationAutopilot:onBypassComplete(escalationVehicle, false, autopilotTarget,
  "frontEscapeAvailable"))
assert(escalationAutopilot:getDiagnostics(escalationVehicle, autopilotTarget,
  "toDestination").controllerMode == "creep")
assert(escalationCommands[#escalationCommands]:find("completionRadius=0.8", 1, true))
assert(escalationAutopilot:onBypassComplete(escalationVehicle, false, autopilotTarget, "timeout"))
assert(escalationCommands[#escalationCommands]:find("requireFrontBlocked=false", 1, true))
assert(escalationAutopilot:onBypassComplete(escalationVehicle, true, autopilotTarget,
  "reverseComplete"))
assert(escalationAutopilot:getHud(true).status == "driving")
map.getMap = escalationGetMap

local straightMap = map
local curveLink = {}
map = {
  objects = {},
  findClosestRoad = function() return "curve0", "curve1" end,
  getMap = function() return {nodes = {
    curve0 = {pos = {x = 0, y = 0, z = 0}, radius = 8, links = {curve1 = curveLink}},
    curve1 = {pos = {x = 100, y = 0, z = 0}, radius = 8,
      links = {curve0 = curveLink, curve2 = curveLink, branch = curveLink}},
    curve2 = {pos = {x = 100, y = 100, z = 0}, radius = 8, links = {curve1 = curveLink}},
    branch = {pos = {x = 150, y = -50, z = 0}, radius = 8, links = {curve1 = curveLink}}
  }} end
}
local curveCommands = {}
local curveAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 100 end,
  getRoutePath = function() return {{wp = "curve0"}, {wp = "curve1"}, {wp = "curve2"}} end
})
local curveVehicle = {
  getID = function() return 1 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) curveCommands[#curveCommands + 1] = command end
}
local curveTarget = {pos = {x = 100, y = 100, z = 0}, nodeA = "curve1", nodeB = "curve2"}
assert(curveAutopilot:enable(curveVehicle, "toDestination", curveTarget))
curveAutopilot:update(curveVehicle, "toDestination", curveTarget, 0.2)
local curveDiagnostics = curveAutopilot:getDiagnostics(curveVehicle, curveTarget, "toDestination")
assert(curveDiagnostics.routeRemainingDistance and curveDiagnostics.routeRemainingDistance >= 190)
assert(curveDiagnostics.routeSpeedCap and curveDiagnostics.routeSpeedCap < 28)
map = straightMap

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
local sinkEvents = {}
debugLogger.setEventSink(function(level, area, event)
  sinkEvents[#sinkEvents + 1] = {level = level, area = area, event = event}
end)
debugLogger.info("test", "disabled")
assert(#logLines == 1)
assert(#sinkEvents == 1 and sinkEvents[1].event == "disabled")
debugLogger.warn("test", "warning_visible")
assert(#logLines == 2 and logLines[2].level == "W")

local aiLogRecords = {}
local aiLogWrites = {}
local aiLogFlushes = 0
local aiLogClosed = false
local aiLogNow = 100
local aiLog = aiLoggerModule.new({
  clock = function() return aiLogNow end,
  sessionStamp = "20260721_120000",
  encode = function(record)
    aiLogRecords[#aiLogRecords + 1] = record
    return "{}"
  end,
  openFile = function(path, mode)
    assert(path == "/taxidriver_ailog_20260721_120000.jsonl")
    assert(mode == "a")
    return {
      write = function(_, value) aiLogWrites[#aiLogWrites + 1] = value end,
      flush = function() aiLogFlushes = aiLogFlushes + 1 end,
      close = function() aiLogClosed = true end
    }
  end,
  getContext = function() return {tripId = 7, vehicleName = "Test Car"} end
})
local aiLogVehicle = {
  getID = function() return 42 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end
}
local aiLogTarget = {pos = {x = 100, y = 0, z = 0}, exactApproach = true}
assert(not aiLog:isEnabled())
assert(aiLog:start(aiLogVehicle, "toPickup", aiLogTarget) == false and #aiLogRecords == 0)
aiLog:setEnabled(true)
assert(aiLog:start(aiLogVehicle, "toPickup", aiLogTarget) and aiLog:isActive())
aiLog:onStructuredEvent("I", "autopilot", "route_started", {nodes = 12})
aiLog:onVehicleTelemetry({damage = 10, wheelSpeed = 3, gear = "D", gearIndex = 1,
  gearboxBehavior = "arcade", ignitionLevel = 2, engineRunning = true})
aiLogNow = 101
aiLog:update(aiLogVehicle, "toPickup", aiLogTarget, {
  status = "driving", targetKey = "pickup", targetDistance = 100,
  speedKmh = 10.8, routeNodeCount = 12, routePending = false,
  approachStage = 0, stuckSeconds = 0, recoveryAttempt = 0
}, 1)
aiLogNow = 102
aiLog:onVehicleTelemetry({damage = 25, wheelSpeed = 2, gear = "R", gearIndex = -1,
  gearboxBehavior = "realistic", ignitionLevel = 2, engineRunning = true,
  autopilotController = {mode = "reverse", safetyHolding = true, safetyBrake = 1,
    obstacleDistance = 1.2, obstacleClosingSpeed = 2, obstacleId = 88,
    obstacleDetected = true, preflightFrontClearance = 1.2, preflightRearClearance = 6}})
aiLog:update(aiLogVehicle, "toPickup", aiLogTarget, {
  status = "recovering", targetKey = "pickup", targetDistance = 120,
  speedKmh = 7.2, routeNodeCount = 12, routePending = false,
  approachStage = 0, stuckSeconds = 0, recoveryAttempt = 1, controllerMode = "reverse",
  routeRemainingDistance = 82, routeSegmentIndex = 4, routeCrossTrack = 0.4,
  leadVehicleId = 88, leadGap = 1.2, leadSpeed = 0, leadClosingSpeed = 2,
  leadTtc = 0.6, leadConfirmed = true, leadRayConfirmed = true,
  signalAction = 0, signalGreenSeconds = 3.2, recoveryRepeatCount = 2,
  recoveryEscalation = 1
}, 1)
aiLog:setEnabled(false)
assert(not aiLog:isEnabled() and not aiLog:isActive())
aiLog:close()
local aiEvents = {}
local richNavigationRecord = nil
for _, record in ipairs(aiLogRecords) do
  aiEvents[record.event] = true
  if record.event == "navigation_snapshot" and record.routeRemainingDistance then
    richNavigationRecord = record
  end
end
assert(aiEvents.ai_session_started and aiEvents.autopilot_route_started)
assert(aiEvents.navigation_snapshot and aiEvents.vehicle_damage_increased)
assert(aiEvents.gear_changed and aiEvents.gearbox_mode_drift)
assert(aiEvents.collision_safety_engaged and aiEvents.target_distance_increased)
assert(richNavigationRecord and richNavigationRecord.leadRayConfirmed == true and
  richNavigationRecord.routeSegmentIndex == 4 and richNavigationRecord.signalAction == 0 and
  richNavigationRecord.obstacleDetected == true)
assert(aiEvents.ai_session_finished and #aiLogWrites == #aiLogRecords and
  aiLogFlushes >= #aiLogRecords and aiLogClosed)

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

local perceptionVehicle = {}
local perceptionVehicleHeight = 1.5
local perceptionDirection = {x = 1, y = 0, z = 0}
function perceptionVehicle:getID() return 42 end
function perceptionVehicle:getPosition() return {x = 0, y = 0, z = 0} end
function perceptionVehicle:getDirectionVector() return perceptionDirection end
function perceptionVehicle:getDirectionVectorUp() return {x = -perceptionDirection.z, y = 0, z = perceptionDirection.x} end
function perceptionVehicle:getInitialLength() return 4.5 end
function perceptionVehicle:getInitialWidth() return 2 end
function perceptionVehicle:getInitialHeight() return perceptionVehicleHeight end
local perceptionObstacle = {}
function perceptionObstacle:getInitialLength() return 4.5 end
function perceptionObstacle:getInitialWidth() return 2 end
function perceptionObstacle:getDirectionVector() return {x = 1, y = 0, z = 0} end
getObjectByID = function(id) return (id == 91 or id == 92) and perceptionObstacle or nil end
map = {
  objects = {[91] = {pos = {x = 14, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0},
    dirVec = {x = 1, y = 0, z = 0}}},
  findClosestRoad = function() return "p1", "p2" end,
  getMap = function() return {nodes = {
    p1 = {pos = {x = 0, y = 0, z = 0}, radius = 3, links = {p2 = {oneWay = false}}},
    p2 = {pos = {x = 80, y = 0, z = 0}, radius = 3, links = {p1 = {oneWay = false}}}
  }} end
}
castRayStatic = nil
local perceptionModule = dofile("lua/ge/extensions/taxiDriver/autopilotPerception.lua")
local perception = perceptionModule.new({followScanDistance = 80, bypassControllerSpeed = 7})
local freeSpacePlan, freeSpaceReason = perception:planLocalBypass(perceptionVehicle, 91)
assert(freeSpacePlan and freeSpaceReason == nil and
  (freeSpacePlan.strategy == "freeSpace" or freeSpacePlan.strategy == "spatialGraph"))
local bypassDetours = false
for _, point in ipairs(freeSpacePlan.points) do
  if math.abs(point.y) > 2 then bypassDetours = true; break end
end
assert(#freeSpacePlan.points >= 5 and bypassDetours)
-- This maneuver extends beyond the narrow graph radius. It must remain usable
-- because road markings are a score penalty, not a hard collision boundary.
if freeSpacePlan.strategy == "freeSpace" then assert((freeSpacePlan.roadOutside or 0) > 0)
else assert((freeSpacePlan.graphNodeCount or 0) >= 3) end
local parkedPerceptionVehicle = {isParked = "true"}
function parkedPerceptionVehicle:getID() return 94 end
function parkedPerceptionVehicle:getPosition() return {x = 14, y = 0, z = 0} end
function parkedPerceptionVehicle:getDirectionVector() return {x = 0, y = 1, z = 0} end
function parkedPerceptionVehicle:getVelocity() return {x = 0, y = 0, z = 0} end
function parkedPerceptionVehicle:getInitialLength() return 4.8 end
function parkedPerceptionVehicle:getInitialWidth() return 2.1 end
local mapObstacle = map.objects[91]
map.objects[91] = nil
getAllVehicles = function() return {perceptionVehicle, parkedPerceptionVehicle} end
local parkedBypass = perception:planLocalBypass(perceptionVehicle, 94)
assert(parkedBypass and parkedBypass.obstacleId == 94 and #parkedBypass.points >= 5)
getAllVehicles = nil
map.objects[91] = mapObstacle
local pointApproach = perception:planPointApproach(perceptionVehicle, {x = 27, y = 0, z = 0})
assert(pointApproach and pointApproach.strategy == "freeSpaceApproach" and
  pointApproach.targetError == 0 and #pointApproach.points > 10)
local approachDetours = false
for _, point in ipairs(pointApproach.points) do
  if math.abs(point.y) > 2.5 then approachDetours = true; break end
end
assert(approachDetours)
map.objects[92] = {pos = {x = 27, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0},
  dirVec = {x = 1, y = 0, z = 0}}
local closestApproach = perception:planPointApproach(perceptionVehicle, {x = 27, y = 0, z = 0})
assert(closestApproach and closestApproach.targetError > 0 and closestApproach.targetError <= 6)
map.objects[92] = nil
-- A 15 cm pavement is rejected by a low car but may be used by a taller
-- vehicle whose conservative suspension/body-height proxy can climb it.
castRayStatic = function(origin, direction, maximumDistance)
  if math.abs(direction.z or 0) < 0.5 then return maximumDistance end
  local ground = math.abs(origin.y or 0) > 2 and 0.15 or 0
  return (origin.z or 0) - ground
end
perceptionVehicleHeight = 1.2
local lowCarPlan, lowCarReason = perception:planLocalBypass(perceptionVehicle, 91)
assert(lowCarPlan == nil and lowCarReason == "noSafeCorridor")
perceptionVehicleHeight = 2.2
local tallCarPlan = perception:planLocalBypass(perceptionVehicle, 91)
assert(tallCarPlan and (tallCarPlan.strategy == "freeSpace" or
  tallCarPlan.strategy == "spatialGraph"))
castRayStatic = nil
local perceptionDraws = {lines = 0, spheres = 0, texts = 0}
ColorF, ColorI = function(...) return {...} end, function(...) return {...} end
debugDrawer = {
  drawLine = function() perceptionDraws.lines = perceptionDraws.lines + 1 end,
  drawSphere = function() perceptionDraws.spheres = perceptionDraws.spheres + 1 end,
  drawTextAdvanced = function() perceptionDraws.texts = perceptionDraws.texts + 1 end
}
perception:setDebugEnabled(true)
perception:updateDebug(perceptionVehicle, 91, 0.2)
perception:drawDebug()
assert(perceptionDraws.lines > 10 and perceptionDraws.spheres > 5 and perceptionDraws.texts == 1)
assert(perception:getDebugSnapshot().chosen ~= nil)
perception:updateDebug(perceptionVehicle, 91, 0.4, 1, true)
local passiveSnapshot = perception:getDebugSnapshot()
assert(passiveSnapshot.reason == "signalWait" and #passiveSnapshot.rays == 19 and
  #passiveSnapshot.candidates == 0 and passiveSnapshot.graphNodes == nil)
perceptionDirection = {x = 0.894427, y = 0, z = 0.447214}
perception:setDebugEnabled(false); perception:setDebugEnabled(true)
perception:updateDebug(perceptionVehicle, 91, 0.2)
local pitchedRay = perception:getDebugSnapshot().rays[10]
assert(pitchedRay.finish.z > pitchedRay.start.z + pitchedRay.distance * 0.4)
perceptionDirection = {x = 1, y = 0, z = 0}
perception:setDebugEnabled(false); perception:setDebugEnabled(true)
perception:clearPointApproach()
perception:updateDebug(perceptionVehicle, nil, 0.4, -1)
local rearWorldRay = perception:getDebugSnapshot().rays[10]
assert(rearWorldRay.travelDirection == -1 and rearWorldRay.finish.x < rearWorldRay.start.x)

-- A narrow charging post just outside the old center ray must still intersect
-- the swept body width. The hit exists only for the new outer comb probe.
combObjects = map.objects
map.objects = {}
castRayStatic = function(origin, direction, maximumDistance)
  if (direction.x or 0) > 0.8 and (origin.y or 0) > 1.15 then return 2 end
  return maximumDistance
end
perception:setDebugEnabled(false); perception:setDebugEnabled(true)
perception:updateDebug(perceptionVehicle, nil, 0.4, 1, true)
combCenterRay = perception:getDebugSnapshot().rays[10]
assert(combCenterRay.blocked and combCenterRay.hitKind == "static" and
  math.abs(combCenterRay.distance - 2) < 0.01)
castRayStatic = nil
map.objects = combObjects

local accessNodes = {
  a = {pos = {x = 0, y = 0, z = 0}, radius = 4, links = {b = {drivability = 1}}},
  b = {pos = {x = 10, y = 0, z = 0}, radius = 4,
    links = {a = {drivability = 1}, c = {drivability = 1}}},
  c = {pos = {x = 10, y = 15, z = 0}, radius = 4,
    links = {b = {drivability = 1}, d = {drivability = 1}}},
  d = {pos = {x = 20, y = 15, z = 0}, radius = 4, links = {c = {drivability = 1}}}
}
local function accessPath(startNode, endNode)
  local queue, parents, head = {startNode}, {[startNode] = false}, 1
  while queue[head] do
    local current = queue[head]; head = head + 1
    if current == endNode then break end
    for neighbor in pairs(accessNodes[current].links) do
      if parents[neighbor] == nil then parents[neighbor], queue[#queue + 1] = current, neighbor end
    end
  end
  if parents[endNode] == nil then return {} end
  local reversed, current = {}, endNode
  while current do reversed[#reversed + 1], current = current, parents[current] end
  local result = {}
  for index = #reversed, 1, -1 do result[#result + 1] = reversed[index] end
  return result
end
map = {objects = {}, getMap = function() return {nodes = accessNodes} end,
  findClosestRoad = function() return "a", "b" end,
  getGraphpath = function() return {getPath = function(_, first, second)
    return accessPath(first, second)
  end} end}
castRayStatic = function(origin, direction, maximumDistance)
  if (direction.z or 0) < -0.5 then return origin.z or 3 end
  if math.abs(direction.x or 0) > 0.001 then
    local distance = (12 - (origin.x or 0)) / direction.x
    local y = (origin.y or 0) + (direction.y or 0) * distance
    if distance >= 0 and distance <= maximumDistance and y >= -20 and y <= 12 then return distance end
  end
  return maximumDistance
end
local accessPlan = perception:planPointApproach(perceptionVehicle, {x = 20, y = 10, z = 0})
assert(accessPlan and accessPlan.graphAssisted and accessPlan.targetError == 0 and
  accessPlan.strategy == "graphAccessApproach")
local visitedEntrance = false
for _, point in ipairs(accessPlan.points) do
  if point.y >= 14 then visitedEntrance = true; break end
end
assert(visitedEntrance)

local proactiveCommands = {}
local parkedTrackingCommands = {}
local parkedTrackingVehicle = {isParked = "true"}
function parkedTrackingVehicle:getID() return 95 end
function parkedTrackingVehicle:getPosition() return {x = -38, y = 28, z = 0} end
function parkedTrackingVehicle:queueLuaCommand(command)
  parkedTrackingCommands[#parkedTrackingCommands + 1] = command
end
local proactiveVehicle = {
  getID = function() return 93 end,
  getPosition = function() return {x = -45, y = 0, z = 0} end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) proactiveCommands[#proactiveCommands + 1] = command end
}
local proactiveTarget = {
  pos = {x = 20, y = 10, z = 0}, nodeA = "c", nodeB = "d", exactApproach = true
}
local earlyGraphPlan = perception:planPointApproach(proactiveVehicle, proactiveTarget.pos,
  {preferGraph = true})
assert(earlyGraphPlan and earlyGraphPlan.graphAssisted and earlyGraphPlan.graphEdgeCount >= 3)
assert(earlyGraphPlan.points[1].x == -45 and earlyGraphPlan.points[1].y == 0)
local firstDrivenPoint = earlyGraphPlan.points[2]
local firstDrivenDistance = firstDrivenPoint and math.sqrt((firstDrivenPoint.x + 45) ^ 2 +
  firstDrivenPoint.y ^ 2) or 0
assert(firstDrivenDistance > 0.5 and firstDrivenDistance <= 4.1)
local proactiveAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 35 end,
  getRoutePath = function() return {{wp = "a"}, {wp = "b"}, {wp = "c"}, {wp = "d"}} end
})
local perceptionGetObjectByID = getObjectByID
getAllVehicles = function() return {proactiveVehicle, parkedTrackingVehicle} end
getObjectByID = function(id)
  if id == 95 then return parkedTrackingVehicle end
  return perceptionGetObjectByID(id)
end
assert(proactiveAutopilot:enable(proactiveVehicle, "toFuelStation", proactiveTarget))
assert(parkedTrackingCommands[#parkedTrackingCommands] == "mapmgr.enableTracking()")
proactiveAutopilot:update(proactiveVehicle, "toFuelStation", proactiveTarget, 0.1)
assert(proactiveAutopilot:getHud(true).status == "approaching")
assert(proactiveCommands[#proactiveCommands]:find("taxiDriverAutopilotRecovery.start", 1, true) and
  proactiveCommands[#proactiveCommands]:find("stopAtEnd=true", 1, true))
proactiveAutopilot:disable(proactiveVehicle, "proactive-test")
assert(parkedTrackingCommands[#parkedTrackingCommands] == "mapmgr.disableTracking()")
getAllVehicles = nil
getObjectByID = perceptionGetObjectByID
castRayStatic = nil

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
-- Route geometry uses positive Y as the vehicle's left side, while BeamNG's
-- steering input uses a negative value for a left turn.
assert(recoveryInputs.leftSignal and recoveryInputs.steering < 0 and recoveryInputs.throttle > 0)
for _, point in ipairs(recoveryPoints) do
  recoveryPosition = point
  recoveryController.updateGFX(0.1)
end
assert(recoveryCallbacks[#recoveryCallbacks]:find("onAutopilotBypassComplete(42,true", 1, true))

recoveryCallbacks = {}
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 0
safetyObjects = {}
assert(recoveryController.start({points = {{x = -8, y = -2, z = 0}}, targetSpeed = 3,
  timeout = 10, allowReverse = true}))
recoveryController.updateGFX(0.1)
-- The destination is to the left of the rearward travel vector. Reverse
-- kinematics therefore require the opposite input sign from forward motion.
assert(recoveryInputs.steering > 0 and recoveryInputs.brake > 0)
recoveryController.stop()

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
recoveryCallbacks = {}
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 0
safetyObjects = {}
assert(recoveryController.start({points = {{x = -12, y = 0, z = 0}}, targetSpeed = 4,
  timeout = 20, allowReverse = false}))
recoveryController.updateGFX(0.1)
assert(recoveryInputs.throttle > 0 and recoveryInputs.brake == 0)
recoveryController.stop()
recoveryCallbacks = {}
assert(recoveryController.start({points = {{x = 10, y = 0, z = 0}}, targetSpeed = 4,
  timeout = 20, allowReverse = false}))
for _ = 1, 36 do recoveryController.updateGFX(0.1) end
assert(recoveryCallbacks[#recoveryCallbacks]:find(
  'onAutopilotBypassComplete(42,false,"waypointNoProgress")', 1, true))
recoveryPosition = {x = 0, y = 0, z = 0}
electrics.values.wheelspeed = 15
safetyObjects[77] = {pos = {x = 35, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
recoveryController.setGearboxOverride(true)
recoveryController.updateGFX(0.1)
assert(recoveryInputs.brake > 0 and recoveryInputs.brake < 1 and recoveryInputs.throttle == 0)
safetyObjects[77].pos = {x = 6, y = 0, z = 0}
recoveryController.updateGFX(0.1)
assert(recoveryInputs.brake == 1)
safetyObjects[77].pos = {x = 8, y = -2.2, z = 0}
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
safetyObjects = {[88] = {pos = {x = 3, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}}
electrics.values.wheelspeed = 0
assert(recoveryController.startReverseEscape({
  minDistance = 3, maxDistance = 6, targetSpeed = 2.2, requireFrontBlocked = true
}))
safetyObjects[90] = {pos = {x = -7, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0}}
electrics.values.wheelspeed = -4
electrics.values.gearIndex = -1
recoveryController.updateGFX(0.1)
local rearDebug = recoveryController.getDebugState()
assert(recoveryInputs.throttle == 1 and recoveryInputs.brake == 0 and
  rearDebug.reverseRayCount == 13 and rearDebug.reverseFanClearance ~= nil)
recoveryController.stop()

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
local recoveryDebug = recoveryController.getDebugState()
assert(type(recoveryDebug) == "table" and type(recoveryDebug.obstacleDetected) == "boolean")

local defaultFleet = taxiConfig.sanitizeFleet(nil)
assert(defaultFleet.aiPreset == "standard" and defaultFleet.passengerJobs and defaultFleet.deliveryJobs)
local disabledFleetJobs = taxiConfig.sanitizeFleet({passengerJobs = false, deliveryJobs = false})
assert(disabledFleetJobs.passengerJobs and not disabledFleetJobs.deliveryJobs)
assert(taxiConfig.sanitizeFleet({worldLabelDistance = 1}).worldLabelDistance == 50)
assert(taxiConfig.sanitizeFleet({worldLabelDistance = 5000}).worldLabelDistance == 1000)
for _, preset in ipairs({"careful", "standard", "fast"}) do
  for _, passengerJobs in ipairs({false, true}) do
    for _, deliveryJobs in ipairs({false, true}) do
      local fleetSettings = taxiConfig.sanitizeFleet({
        aiPreset = preset, passengerJobs = passengerJobs, deliveryJobs = deliveryJobs,
        ownerSharePercent = 999, maxDrivers = 99
      })
      assert(fleetSettings.aiPreset == preset and fleetSettings.ownerSharePercent == 90 and fleetSettings.maxDrivers == 12)
      assert(fleetSettings.passengerJobs or fleetSettings.deliveryJobs)
    end
  end
end

local function fleetVector(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  local value = {x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0}
  local methods = {}
  function methods:distance(other)
    local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  function methods:dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
  return setmetatable(value, {
    __index = methods,
    __add = function(a, b) return fleetVector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    __sub = function(a, b) return fleetVector(a.x - b.x, a.y - b.y, a.z - b.z) end
  })
end

vec3 = fleetVector
quatFromDir = function() return {} end
local fleetVehicles, deletedVehicles = {}, {}
local function mockFleetVehicle(id, modelKey, configKey, position)
  local vehicle = {jbeam = modelKey, partConfig = "/vehicles/" .. modelKey .. "/" .. configKey .. ".pc", position = position}
  function vehicle:getID() return id end
  function vehicle:getPosition() return self.position end
  function vehicle:getDirectionVector() return fleetVector(1, 0, 0) end
  function vehicle:getInitialHeight() return 1.6 end
  function vehicle:setDynDataFieldbyName() end
  function vehicle:queueLuaCommand() end
  function vehicle:delete() deletedVehicles[id], fleetVehicles[id] = true, nil end
  fleetVehicles[id] = vehicle
  return vehicle
end

local fleetPlayer = mockFleetVehicle(42, "etk800", "base", fleetVector(0, 0, 0))
local spawnedFleetVehicle = mockFleetVehicle(101, "etk800", "base", fleetVector(0, 0, 0))
local trafficFleetVehicle = mockFleetVehicle(202, "pickup", "base", fleetVector(30, 0, 0))
be = {
  getPlayerVehicle = function() return fleetPlayer end,
  getPlayerVehicleID = function() return 42 end
}
getObjectByID = function(id) return fleetVehicles[id] end
local trafficData = {[202] = {isAi = true, modelName = "Gavril Pickup"}}
local trafficRemoved, trafficInserted = false, false
gameplay_traffic = {
  getTrafficData = function() return trafficData end,
  removeTraffic = function(id) trafficData[id], trafficRemoved = nil, true end,
  insertTraffic = function(id) trafficData[id], trafficInserted = {isAi = true, modelName = "Gavril Pickup"}, true end
}
map = {
  objects = {},
  findClosestRoad = function() return "n1", "n2" end,
  getGraphpath = function()
    return {getRandomPathG = function() return {"n1", "n2", "n3"} end}
  end,
  getMap = function()
    return {nodes = {
      n1 = {pos = fleetVector(0, 0, 0)},
      n2 = {pos = fleetVector(1500, 0, 0)},
      n3 = {pos = fleetVector(3500, 0, 0)}
    }}
  end
}
core_vehicles = {
  getModel = function() return {model = {Brand = "ETK", Name = "800 Series"}} end,
  spawnNewVehicle = function() return spawnedFleetVehicle end
}
FS = {
  fileExists = function() return false end,
  directoryExists = function() return true end,
  directoryCreate = function() end
}
jsonWriteFile = function() end
ui_apps_minimap_vehicles = nil
ui_apps_minimap_utils = nil
extensions = nil

local workerInstances = {}
local workerFactory = {new = function()
  local worker = {arrived = false, enabled = false, configured = nil, suspended = false}
  function worker:configure(value) self.configured = value end
  function worker:start(_, _, _, value) self.enabled, self.configured = true, value; return true end
  function worker:update() end
  function worker:hasArrived() return self.arrived end
  function worker:stop() self.enabled = false end
  function worker:suspend(_, value) self.suspended = value end
  function worker:onRouteDone() return true end
  function worker:onBypassComplete() return true end
  function worker:getHud() return {status = self.suspended and "suspended" or "driving"} end
  workerInstances[#workerInstances + 1] = worker
  return worker
end}
local fleetManager = dofile("lua/ge/extensions/taxiDriver/fleetManager.lua")
local fleetService = fleetManager.new({modVersion = "test", workerFactory = workerFactory})
fleetService:configure({
  aiPreset = "careful", ownerSharePercent = 40, hiringFee = 75,
  wagePerTenMinutes = 12, maxDrivers = 2, passengerJobs = true, deliveryJobs = true
}, "ru")
fleetService:load()
local hiredGarage, garageReason, garageDelta = fleetService:command("hireGarage", {
  modelKey = "etk800", configKey = "base", key = "etk800|base", name = "ETK 800"
}, 1000)
assert(hiredGarage and not garageReason and garageDelta == -75)
local hiredTraffic, trafficReason, trafficDelta = fleetService:command("hireTraffic", {vehicleId = 202}, 925)
assert(hiredTraffic and not trafficReason and trafficDelta == -75 and trafficRemoved)
assert(#workerInstances == 2 and workerInstances[1] ~= workerInstances[2])
assert(workerInstances[2].configured.aggressionPercent == taxiConfig.fleetAiPresets.careful.aggressionPercent)
local fleetHud = fleetService:getHud(850, {{key = "etk800|base", modelKey = "etk800", configKey = "base", name = "ETK 800"}})
assert(fleetHud.activeDrivers == 2 and #fleetHud.drivers == 2 and #fleetHud.markers == 2)
local fleetWorldLabels = {}
ColorF, ColorI = function(...) return {...} end, function(...) return {...} end
debugDrawer = {drawTextAdvanced = function(_, _, value) fleetWorldLabels[#fleetWorldLabels + 1] = value end}
fleetService:drawWorldLabels()
assert(#fleetWorldLabels == 2 and fleetWorldLabels[1]:find("Мой водитель такси", 1, true))
trafficFleetVehicle.position = fleetVector(500, 0, 0)
fleetService:drawWorldLabels()
assert(#fleetWorldLabels == 3)
trafficFleetVehicle.position = fleetVector(30, 0, 0)
local fullResult, fullReason = fleetService:command("hireTraffic", {vehicleId = 202}, 850)
assert(not fullResult and fullReason == "fleet_full")
local wageDelta = 0
for _ = 1, 600 do
  local tickDelta = fleetService:update(0, 1, 850 + wageDelta)
  wageDelta = wageDelta + tickDelta
end
assert(wageDelta <= 0 and fleetService:getStats().wages > 0)
workerInstances[1].arrived, workerInstances[2].arrived = true, true
local incomeDelta = fleetService:update(0.1, 1, 850 + wageDelta)
assert(incomeDelta > 0 and fleetService:getStats().rides == 2 and fleetService:getStats().ownerRevenue > 0)
assert(fleetService:onRouteDone(101) and fleetService:onBypassComplete(202, true, "test"))
local dismissed = fleetService:command("dismiss", {id = 2}, 850)
assert(dismissed and trafficInserted)
fleetService:shutdown()
assert(deletedVehicles[101])

print("TaxiDriver Lua combinatorics: fleet worker presets/economy/lifecycle, AI logging, adaptive bypass, trajectory rays, powertrain handshake, gameplay modes, and 500 deferred respawns passed")
