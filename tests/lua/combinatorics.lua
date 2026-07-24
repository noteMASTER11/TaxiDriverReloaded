package.path = "lua/ge/extensions/?.lua;" .. package.path

package.preload["gameplay/route/route"] = function() return {} end
package.preload["gameplay/traffic/trafficUtils"] = function() return {} end
log = log or function() end

local tripEvents = dofile("lua/ge/extensions/taxiDriver/tripEvents.lua")
tripHistory = dofile("lua/ge/extensions/taxiDriver/tripHistory.lua")
physicalPickupModule = dofile("lua/ge/extensions/taxiDriver/physicalPickup.lua")
local policeCheckModule = dofile("lua/ge/extensions/taxiDriver/policeCheckEvent.lua")
local shiftTracker = dofile("lua/ge/extensions/taxiDriver/shiftTracker.lua")
local shiftHistory = dofile("lua/ge/extensions/taxiDriver/shiftHistory.lua")
local offerGenerator = dofile("lua/ge/extensions/taxiDriver/offerGenerator.lua")
local hudPublisher = dofile("lua/ge/extensions/taxiDriver/hudPublisher.lua")
local vehicleScanGuard = require("taxiDriver/vehicleScanGuard")
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
assert(defaultAiDriver.obeySpeedLimits == true and defaultAiDriver.laneDiscipline == true)
assert(defaultAiDriver.strictGpsRoute == false)
assert(defaultAiDriver.minimumFollowingDistance == 4 and defaultAiDriver.trafficWaitSeconds == 3)
local legacyAiDriver = taxiConfig.sanitizeAiDriver({
  aggressionPercent = 42, obeyTrafficRules = false
})
assert(legacyAiDriver.preset == "custom")
assert(legacyAiDriver.aggressionPercent == 42)
assert(legacyAiDriver.obeySpeedLimits == false)
local independentAiDriver = taxiConfig.sanitizeAiDriver({
  preset = "custom", obeySpeedLimits = false, laneDiscipline = false,
  strictGpsRoute = true,
  minimumFollowingDistance = 999, trafficWaitSeconds = 0,
  brakingDeceleration = 99, followingTimeGap = 0
})
assert(independentAiDriver.obeySpeedLimits == false and independentAiDriver.laneDiscipline == false)
assert(independentAiDriver.strictGpsRoute == true)
assert(independentAiDriver.minimumFollowingDistance == 10)
assert(independentAiDriver.trafficWaitSeconds == 1)
assert(independentAiDriver.brakingDeceleration == 8)
assert(independentAiDriver.followingTimeGap == 1)
for _, preset in ipairs(taxiConfig.aiDriverPresetOrder) do
  local configured = taxiConfig.sanitizeAiDriver({preset = preset})
  assert(configured.preset == preset)
  if preset ~= "custom" then
    assert(configured.aggressionPercent == taxiConfig.aiDriverPresets[preset].aggressionPercent)
    assert(taxiConfig.sanitizeAiDriver({
      preset = preset, strictGpsRoute = true
    }).strictGpsRoute == true)
  end
end

assert(routePlanner.isDistanceAllowed(25000, 1000, 25000))
assert(not routePlanner.isDistanceAllowed(25001, 1000, 25000))
assert(routePlanner.isDistanceAllowed(250000, 1000, nil))
assert(not routePlanner.isDistanceAllowed(999, 1000, nil))

local orientedMap = map
local orientedNodes = {
  roadStart = {pos = {x = -100, y = 0, z = 0}, links = {}},
  targetA = {pos = {x = 0, y = 0, z = 0}, links = {}},
  targetB = {pos = {x = 100, y = 0, z = 0}, links = {}},
  roadFar = {pos = {x = 200, y = 0, z = 0}, links = {}},
  loop1 = {pos = {x = 0, y = 100, z = 0}, links = {}},
  loop2 = {pos = {x = 100, y = 100, z = 0}, links = {}}
}
local orientedRoads = {}
local function orientedLink(first, second)
  local data = {oneWay = false, len = 100}
  orientedNodes[first].links[second] = data
  orientedNodes[second].links[first] = data
  orientedRoads[first] = orientedRoads[first] or {}
  orientedRoads[second] = orientedRoads[second] or {}
  orientedRoads[first][second] = data
  orientedRoads[second][first] = data
end
orientedLink("roadStart", "targetA")
orientedLink("targetA", "targetB")
orientedLink("targetB", "roadFar")
orientedLink("targetA", "loop1")
orientedLink("loop1", "loop2")
orientedLink("loop2", "targetA")
map = {
  getMap = function() return {nodes = orientedNodes} end,
  getGraphpath = function() return {graph = orientedRoads} end,
  findClosestRoad = function(position)
    if position.x < -50 then return "roadStart", "targetA" end
    if position.x > 100 then return "roadFar", "targetB" end
    return "targetB", "targetA"
  end
}
local orientedCommands = {}
local orientedPosition = {x = -100, y = 0, z = 0}
local orientedDirection = {x = 1, y = 0, z = 0}
local orientedVehicle = {
  getID = function() return 7 end,
  getPosition = function() return orientedPosition end,
  getDirectionVector = function() return orientedDirection end,
  getVelocity = function() return {x = 0, y = 0, z = 0} end,
  queueLuaCommand = function(_, command)
    orientedCommands[#orientedCommands + 1] = command
  end
}
local orientedPhases = {
  toPickup = "toPickup", toStop = "toStop",
  toDestination = "toDestination", toFuelStation = "toFuelStation"
}
local orientedTarget = {
  pos = {x = 40, y = 4, z = 0}, dir = {x = 1, y = 0, z = 0},
  nodeA = "targetA", nodeB = "targetB"
}
local orientedAutopilot = autopilotModule.new({
  phases = orientedPhases, arrivalRadius = 14, maxArrivalSpeedKmh = 4,
  getSpeedKmh = function() return 0 end
})
assert(orientedAutopilot:enable(orientedVehicle, "toPickup", orientedTarget))
assert(load(orientedCommands[#orientedCommands]))
assert(orientedAutopilot:isTargetAligned(orientedVehicle, orientedTarget))
orientedDirection = {x = -1, y = 0, z = 0}
assert(not orientedAutopilot:isTargetAligned(orientedVehicle, orientedTarget))
orientedDirection = {x = 1, y = 0, z = 0}
assert(orientedCommands[#orientedCommands]:find(
  'path={"targetA","targetB"}', 1, true))
assert(orientedCommands[#orientedCommands]:find(
  "targetX=40.000,targetY=4.000,targetZ=0.000", 1, true))
orientedPosition = {x = -60, y = 0, z = 0}
assert(orientedAutopilot:onRouteDone(orientedVehicle, orientedTarget))
assert(#orientedCommands == 2)
local prematureDiagnostics = orientedAutopilot:getDiagnostics(
  orientedVehicle, orientedTarget, "toPickup")
assert(prematureDiagnostics.routeDoneRetryCount == 1)
assert(prematureDiagnostics.orientedApproach and
  prematureDiagnostics.approachNode == "targetA" and
  prematureDiagnostics.departureNode == "targetB")
orientedAutopilot:disable(orientedVehicle, "test")

orientedCommands, orientedPosition, orientedDirection =
  {}, {x = 150, y = 0, z = 0}, {x = -1, y = 0, z = 0}
orientedTarget.dir = {x = -1, y = 0, z = 0}
orientedAutopilot = autopilotModule.new({
  phases = orientedPhases, arrivalRadius = 14,
  getSpeedKmh = function() return 0 end
})
assert(orientedAutopilot:enable(orientedVehicle, "toPickup", orientedTarget))
assert(orientedCommands[#orientedCommands]:find(
  'path={"targetB","targetA"}', 1, true))
orientedAutopilot:disable(orientedVehicle, "test")

-- When already travelling the wrong way on the target edge, route through a
-- legal loop and return from the correct side instead of reversing immediately.
orientedCommands, orientedPosition, orientedDirection =
  {}, {x = 50, y = 0, z = 0}, {x = -1, y = 0, z = 0}
orientedTarget.dir = {x = 1, y = 0, z = 0}
orientedAutopilot = autopilotModule.new({
  phases = orientedPhases, arrivalRadius = 14,
  getSpeedKmh = function() return 0 end
})
assert(orientedAutopilot:enable(orientedVehicle, "toPickup", orientedTarget))
assert(orientedCommands[#orientedCommands]:find(
  'path={"targetA","loop1","loop2","targetA","targetB"}', 1, true) or
  orientedCommands[#orientedCommands]:find(
    'path={"targetA","loop2","loop1","targetA","targetB"}', 1, true))
assert(not orientedCommands[#orientedCommands]:find(
  'path={"targetA","targetB"}', 1, true))
orientedAutopilot:disable(orientedVehicle, "test")

orientedCommands, orientedPosition, orientedDirection =
  {}, {x = -100, y = 0, z = 0}, {x = 1, y = 0, z = 0}
local strictGpsAutopilot = autopilotModule.new({
  phases = orientedPhases, arrivalRadius = 14,
  getSpeedKmh = function() return 0 end,
  getRoutePath = function() return {
    {pos = {x = -100, y = 0, z = 0}},
    {wp = "gpsA"}, {wp = "gpsB"}, {wp = "gpsC"},
    {pos = orientedTarget.pos}
  } end
})
strictGpsAutopilot:configure({
  strictGpsRoute = true, obeySpeedLimits = true, laneDiscipline = true
})
assert(strictGpsAutopilot:enable(orientedVehicle, "toPickup", orientedTarget))
assert(orientedCommands[#orientedCommands]:find(
  'path={"gpsA","gpsB","gpsC"}', 1, true))
assert(not orientedCommands[#orientedCommands]:find('"loop1"', 1, true))
strictGpsAutopilot:disable(orientedVehicle, "test")
map = orientedMap

if false then
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
assert(autopilot:getHud(true).status == "waitingTraffic")
assert(autopilotCommands[#autopilotCommands]:find('ai.setMode("stop")', 1, true))
map.objects[2].vel = {x = 3, y = 0, z = 0}
autopilot:update(autopilotVehicle, "toDestination", autopilotTarget, 0.2)
assert(autopilot:getHud(true).status == "driving")
assert(autopilotCommands[#autopilotCommands]:find('avoidCars="on"', 1, true))
map.objects[2].vel = {x = 0, y = 0, z = 0}
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
assert(spatialAutopilot:getHud(true).status == "waitingTraffic" or
  spatialAutopilot:getHud(true).status == "waitingObstacle")
for _ = 1, 8 do
  spatialAutopilot:update(spatialVehicle, "toDestination", autopilotTarget, 1)
  if spatialAutopilot:getHud(true).status == "recovering" then break end
end
assert(spatialAutopilot:getHud(true).status == "recovering" and
  spatialCommands[#spatialCommands]:find("taxiDriverAutopilotRecovery.start", 1, true) and
  spatialCommands[#spatialCommands]:find("allowReverse=false", 1, true) and
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
assert(blockedAutopilot:getHud(true).status == "waitingTraffic" or
  blockedAutopilot:getHud(true).status == "waitingObstacle")
for _ = 1, 10 do
  blockedAutopilot:update(blockedVehicle, "toDestination", autopilotTarget, 1)
  if blockedCommands[#blockedCommands]:find("startReverseEscape", 1, true) then break end
end
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
for _ = 1, 10 do
  clearAutopilot:update(clearVehicle, "toDestination", autopilotTarget, 1)
  if clearCommands[#clearCommands]:find("startReverseEscape", 1, true) then break end
end
assert(clearAutopilot:getHud(true).status == "recovering")
assert(clearCommands[#clearCommands]:find("startReverseEscape", 1, true))
assert(clearAutopilot:onBypassComplete(clearVehicle, false, autopilotTarget, "rearBlocked"))
assert(clearAutopilot:getHud(true).status == "waitingTraffic")
map.objects[2] = nil
for index = 0, 23 do map.objects[100 + index] = nil end
for _ = 1, 5 do clearAutopilot:update(clearVehicle, "toDestination", autopilotTarget, 0.2) end
assert(clearAutopilot:getHud(true).status == "driving")
assert(clearCommands[#clearCommands]:find("ai.driveUsingPath", 1, true))

map.objects[3] = {pos = {x = 45, y = 3.6, z = 0}, vel = {x = 10, y = 0, z = 0}}
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
for _ = 1, 3 do followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2) end
assert(followingAutopilot:getDiagnostics(followingVehicle, autopilotTarget,
  "toDestination").leadVehicleId == nil)
map.objects[3].pos.y = 0
followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2)
followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2)
local followingLimit = tonumber(followingCommands[#followingCommands]:match("ai.setSpeed%(([%d%.]+)%)"))
assert(followingLimit and followingLimit > 19 and followingLimit < 20)
for _ = 1, 5 do followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2) end
settledFollowingLimit = tonumber(followingCommands[#followingCommands]:match("ai.setSpeed%(([%d%.]+)%)"))
assert(settledFollowingLimit and settledFollowingLimit < followingLimit)
map.objects[3] = nil
for _ = 1, 10 do followingAutopilot:update(followingVehicle, "toDestination", autopilotTarget, 0.2) end
assert(followingCommands[#followingCommands]:find('ai.setSpeedMode("legal")', 1, true))

legalCommands = {}
legalAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 90 end,
  getSpeedLimitKmh = function() return 50 end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
legalVehicle = {
  getID = followingVehicle.getID, getPosition = followingVehicle.getPosition,
  getDirectionVector = followingVehicle.getDirectionVector,
  getInitialLength = followingVehicle.getInitialLength,
  getInitialWidth = followingVehicle.getInitialWidth,
  queueLuaCommand = function(_, command) legalCommands[#legalCommands + 1] = command end
}
legalAutopilot:configure(taxiConfig.aiDriverPresets.balanced)
assert(legalAutopilot:enable(legalVehicle, "toDestination", autopilotTarget))
for _ = 1, 3 do legalAutopilot:update(legalVehicle, "toDestination", autopilotTarget, 0.2) end
legalDiagnostics = legalAutopilot:getDiagnostics(legalVehicle, autopilotTarget, "toDestination")
assert(math.abs(legalDiagnostics.legalSpeedCap - 50 / 3.6) < 0.01)
assert(legalDiagnostics.filteredSpeedCap and legalDiagnostics.filteredSpeedCap < 25)

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
for _ = 1, 5 do
  escalationAutopilot:update(escalationVehicle, "toDestination", autopilotTarget, 1)
  if escalationCommands[#escalationCommands]:find("startReverseEscape", 1, true) then break end
end
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
curvePosition = {x = 0, y = 0, z = 0}
local curveAutopilot = autopilotModule.new({
  phases = autopilotPhases,
  getSpeedKmh = function() return 100 end,
  getRoutePath = function() return {{wp = "curve0"}, {wp = "curve1"}, {wp = "curve2"}} end
})
local curveVehicle = {
  getID = function() return 1 end,
  getPosition = function() return curvePosition end,
  getDirectionVector = function() return {x = 1, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) curveCommands[#curveCommands + 1] = command end
}
local curveTarget = {pos = {x = 100, y = 100, z = 0}, nodeA = "curve1", nodeB = "curve2"}
assert(curveAutopilot:enable(curveVehicle, "toDestination", curveTarget))
curveAutopilot:update(curveVehicle, "toDestination", curveTarget, 0.2)
local curveDiagnostics = curveAutopilot:getDiagnostics(curveVehicle, curveTarget, "toDestination")
assert(curveDiagnostics.routeRemainingDistance and curveDiagnostics.routeRemainingDistance >= 190)
assert(curveDiagnostics.routeSpeedCap and curveDiagnostics.routeSpeedCap < 28)
assert(curveDiagnostics.routeTurnSignal == -1 and curveDiagnostics.routeTurnNodeIndex == 2)
assert(curveCommands[#curveCommands]:find("set_left_signal(true", 1, true))
curvePosition = {x = 100, y = 8, z = 0}
for _ = 1, 6 do curveAutopilot:update(curveVehicle, "toDestination", curveTarget, 0.2) end
curveDiagnostics = curveAutopilot:getDiagnostics(curveVehicle, curveTarget, "toDestination")
assert(curveDiagnostics.routeTurnSignal == nil)
assert(curveCommands[#curveCommands]:find("set_left_signal(false", 1, true))
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
end

stockCommands = {}
stockPosition = {x = 0, y = 0, z = 0}
stockSpeed = 0
stockPhases = {
  toPickup = "toPickup", toStop = "toStop", toDestination = "toDestination",
  toFuelStation = "toFuelStation", boarding = "boarding", stopWaiting = "stopWaiting"
}
stockTarget = {pos = {x = 100, y = 0, z = 0}, nodeA = "road1", nodeB = "road2"}
stockVehicle = {
  getID = function() return 1 end,
  getPosition = function() return stockPosition end,
  queueLuaCommand = function(_, command) stockCommands[#stockCommands + 1] = command end
}
stockAutopilot = autopilotModule.new({
  phases = stockPhases,
  isPlayerVehicle = function(vehicle) return vehicle == stockVehicle end,
  getSpeedKmh = function() return stockSpeed end,
  getRoutePath = function() return {
    {pos = {x = 0, y = 0, z = 0}},
    {wp = "road0"}, {wp = "road1"},
    {pos = {x = 100, y = 0, z = 0}}
  } end
})
assert(stockAutopilot:enable(stockVehicle, "toDestination", stockTarget))
assert(stockAutopilot:isEnabled())
assert(stockCommands[1]:find("ai.driveUsingPath", 1, true))
assert(stockCommands[1]:find("aggression=0.40", 1, true))
assert(stockCommands[1]:find('routeSpeedMode="legal"', 1, true))
assert(stockCommands[1]:find("followingTimeGap=2.30", 1, true))
assert(stockCommands[1]:find("minimumGap=4.00", 1, true))
assert(stockCommands[1]:find("extensions.unload('taxiDriverAutopilotRecovery')", 1, true))
assert(stockCommands[1]:find("taxiDriverStockAiObserver.watch({", 1, true))
assert(not stockCommands[1]:find("taxiDriverAutopilotRecovery.start", 1, true))
assert(stockCommands[1]:find("ai.setRecoverOnCrash(false)", 1, true))
assert(not stockCommands[1]:find("ai.setRecoverOnCrash(true)", 1, true))
assert(not stockCommands[1]:find("table:", 1, true))
stockAutopilot:update(stockVehicle, "toDestination", stockTarget, 1)
stockDiagnostics = stockAutopilot:getDiagnostics(stockVehicle, stockTarget, "toDestination")
assert(stockDiagnostics.stockAi and not stockDiagnostics.customPerception and
  not stockDiagnostics.customRecovery and stockDiagnostics.routeNodeCount == 3)
stockPosition = {x = 91, y = 0, z = 0}
assert(stockAutopilot:onRouteDone(stockVehicle, stockTarget))
stockDiagnostics = stockAutopilot:getDiagnostics(stockVehicle, stockTarget, "toDestination")
assert(stockDiagnostics.routeDone and stockDiagnostics.routeDoneDistance == 9)
stockAutopilot:markRouteDirty()
stockAutopilot:update(stockVehicle, "toDestination", stockTarget, 0.2)
assert(#stockCommands == 2 and stockCommands[2]:find("ai.driveUsingPath", 1, true))
stockAutopilot:suspend(stockVehicle, true)
assert(stockAutopilot:getHud(true, stockVehicle).status == "paused")
stockAutopilot:suspend(stockVehicle, false)
assert(stockAutopilot:getHud(true, stockVehicle).status == "driving")
assert(not stockAutopilot:onBypassComplete())
stockAutopilot:disable(stockVehicle, "test")
assert(not stockAutopilot:isEnabled())

local npcCommands = {}
local npcVehicle = {
  getID = function() return 2 end,
  getPosition = function() return {x = 0, y = 0, z = 0} end,
  queueLuaCommand = function(_, command) npcCommands[#npcCommands + 1] = command end
}
local playerOnlyAutopilot = autopilotModule.new({
  phases = stockPhases,
  isPlayerVehicle = function(vehicle) return vehicle == stockVehicle end,
  getRoutePath = function() return {{wp = "road0"}, {wp = "road1"}} end
})
assert(not playerOnlyAutopilot:enable(npcVehicle, "toDestination", stockTarget))
assert(#npcCommands == 0 and not playerOnlyAutopilot:isEnabled())

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
          assert(event.kind == "none" or event.kind == "fragileCargo" or
            event.kind == "policeCheck" or event.kind == "roadClosure")
        elseif order.rush or order.multi then
          assert(event.kind == "none" or event.kind == "cancellation" or event.kind == "tip" or
            event.kind == "policeCheck" or event.kind == "passengerNoShow" or
            event.kind == "vipQuietRide" or event.kind == "roadClosure")
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
;(function()
local vipEvent = {kind = "vipQuietRide", rate = 0.15}
assert(tripEvents.calculateTip(vipEvent, 20, 0.005, false) == 3 and vipEvent.status == "completed")
local failedVipEvent = {kind = "vipQuietRide", rate = 0.15}
assert(tripEvents.calculateTip(failedVipEvent, 20, 0.02, false) == 0 and
  failedVipEvent.status == "conditionsFailed")
local noShow = {kind = "passengerNoShow", triggerSeconds = 2, elapsed = 0}
assert(not tripEvents.updateNoShow(noShow, false, 5) and noShow.elapsed == 0)
assert(not tripEvents.updateNoShow(noShow, true, 1))
assert(tripEvents.updateNoShow(noShow, true, 1) and noShow.status == "noShow")
local historyPenalties = tripHistory.sanitizePenalties({
  {kind = "speeding", detail = "Too fast", penalty = 0.15},
  {kind = "collision", detail = string.rep("x", 300), fareAmount = 2.5}
})
assert(#historyPenalties == 2 and historyPenalties[1].penalty == 0.15)
assert(#historyPenalties[2].detail == 180 and historyPenalties[2].fareAmount == 2.5)
local physicalNoShow = physicalPickupModule.new()
assert(physicalNoShow:start({
  isDelivery = false, pickup = {pos = {}}, randomEvent = {kind = "passengerNoShow"}
}))
assert(not physicalNoShow:isReady())
physicalNoShow:clear()
assert(physicalNoShow:isReady())
local hornCommands = {}
local physicalPassenger = physicalPickupModule.new()
physicalPassenger.kind, physicalPassenger.ready = "passenger", false
local pickupPosition = {x = 0, y = 0, z = 0}
function pickupPosition:distance() return 1.5 end
local fakeTaxi = {
  getID = function() return 77 end,
  getPosition = function() return pickupPosition end,
  queueLuaCommand = function(_, command) hornCommands[#hornCommands + 1] = command end
}
local savedPickupObjectLookup = getObjectByID
physicalPassenger.objectId = 88
getObjectByID = function(id)
  return id == 88 and {getPosition = function() return pickupPosition end} or nil
end
assert(physicalPassenger:beginAiPickup(fakeTaxi))
assert(physicalPassenger:isAiHold() and not physicalPassenger:beginAiPickup(fakeTaxi))
assert(physicalPassenger.hornStage == -1 and
  string.find(hornCommands[1], "stopPickupHonk", 1, true))
physicalPassenger:update(fakeTaxi, {}, 0.1, 1.2)
assert(physicalPassenger.hornStage == -1)
physicalPassenger:update(fakeTaxi, {}, 0.1, 0.1)
physicalPassenger:update(fakeTaxi, {}, 0.1, 0.1)
physicalPassenger:update(fakeTaxi, {}, 0.1, 0.1)
assert(physicalPassenger.hornStage == 1 and
  string.find(hornCommands[#hornCommands], "startPickupHonk", 1, true))
getObjectByID = savedPickupObjectLookup
end)()

;(function()
local randomEventSettings = taxiConfig.sanitizeRandomEvents({
  cancellation = {enabled = false, chancePercent = 150},
  policeCheck = {enabled = true, chancePercent = 43.6, preloadConfirmed = true}
})
assert(not randomEventSettings.cancellation.enabled and randomEventSettings.cancellation.chancePercent == 100)
assert(randomEventSettings.policeCheck.enabled and randomEventSettings.policeCheck.chancePercent == 44)
assert(not taxiConfig.sanitizeRandomEvents(nil).policeCheck.enabled)
assert(not taxiConfig.sanitizeRandomEvents({policeCheck = {enabled = true}}).policeCheck.enabled)
assert(tripEvents.shouldTriggerPolice(
  {kind = "policeCheck", triggerProgress = 0.25},
  "toDestination",
  0.25
))
assert(not tripEvents.shouldTriggerPolice({kind = "policeCheck"}, "searching", 1))
local eventKeys = {
  "cancellation", "destinationChange", "additionalStop", "tip", "fragileCargo",
  "policeCheck", "passengerNoShow", "vipQuietRide", "forgottenItem", "roadClosure"
}
local orderShapes = {
  {delivery = false, rush = false, multi = false},
  {delivery = false, rush = true, multi = false},
  {delivery = false, rush = false, multi = true},
  {delivery = true, rush = false, multi = false}
}
for mask = 0, 1023 do
  local configured = {}
  for index, key in ipairs(eventKeys) do
    configured[key] = {enabled = math.floor(mask / (2 ^ (index - 1))) % 2 == 1, chancePercent = 100}
  end
  for _, shape in ipairs(orderShapes) do
    local generated = tripEvents.create(shape.delivery, shape.rush, shape.multi, configured)
    if generated.kind ~= "none" then assert(configured[generated.kind].enabled) end
    if shape.delivery then
      assert(generated.kind == "none" or generated.kind == "fragileCargo" or
        generated.kind == "policeCheck" or generated.kind == "roadClosure")
    else
      assert(generated.kind ~= "fragileCargo")
    end
  end
end
local zeroChance = {}
for _, key in ipairs(eventKeys) do zeroChance[key] = {enabled = true, chancePercent = 0} end
assert(tripEvents.create(false, false, false, zeroChance).kind == "none")

local savedPoliceGlobals = {
  getObjectByID = getObjectByID,
  gameplay_traffic = gameplay_traffic,
  gameplay_police = gameplay_police,
  gameplay_traffic_trafficUtils = gameplay_traffic_trafficUtils,
  core_multiSpawn = core_multiSpawn,
  extensions = extensions,
  getPlayerVehicle = getPlayerVehicle,
  map = map
}
local function policeVector(x, y, z)
  local value = {x = x or 0, y = y or 0, z = z or 0}
  function value:distance(other)
    local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  return value
end
local policeActiveState = 1
local policeObjects = {
  [901] = {getPosition = function() return policeVector(0, 0, 0) end},
  [902] = {
    getPosition = function() return policeVector(30, 0, 0) end,
    setActive = function(_, value) policeActiveState = value end
  }
}
policeObjects[902].delete = function() policeObjects[902] = nil end
local policeTraffic = {
  [901] = {pursuit = {mode = 0}},
  [902] = {role = {flags = {}}}
}
local pursuitCalls, releasedPlayer = {}, false
getObjectByID = function(id) return policeObjects[id] end
gameplay_traffic = {
  getTrafficData = function() return policeTraffic end,
  removeTraffic = function() end
}
gameplay_police = {
  getPoliceVehicles = function() return {} end,
  setupPursuitGameplay = function() return true end,
  setPursuitMode = function(mode, id, policeIds)
    pursuitCalls[#pursuitCalls + 1] = {mode = mode, id = id, policeIds = policeIds}
    policeTraffic[901].pursuit.mode = mode
  end,
  releaseVehicle = function(id)
    releasedPlayer = id == 901
    policeTraffic[901].pursuit.mode = 0
  end
}
local preloadOptions, placementOptions
gameplay_traffic_trafficUtils = {
  createPoliceGroup = function() return {{model = "police", config = "police"}} end
}
core_multiSpawn = {
  spawnGroup = function(_, _, options) preloadOptions = options; return 51 end,
  placeGroup = function(_, options) placementOptions = options end
}
getPlayerVehicle = function() return policeObjects[901] end
map = {getMap = function() return {nodes = {a = {}}} end}
local policeFine, policeCompletion
local policeService = policeCheckModule.new()
assert(policeService:prepare() and preloadOptions.gap == 1000 and preloadOptions.instant == false)
assert(policeService:onVehicleGroupSpawned({902}, 51, preloadOptions.name))
assert(policeActiveState == 0 and policeService:getState().preparedPoliceId == 902)
assert(policeService:start(
  {kind = "policeCheck", triggered = true},
  901,
  {
    fine = function(amount) policeFine = amount end,
    complete = function(reason) policeCompletion = reason end
  }
))
assert(policeService:getState().policeId == 902 and #pursuitCalls == 1)
assert(policeActiveState == 1 and placementOptions.gap >= 500 and placementOptions.gap <= 600)
assert(policeService:onPursuitAction(901, "arrest"))
policeService:update(2)
assert(policeFine >= 15 and policeFine <= 60 and releasedPlayer and policeCompletion == "ticketed")
assert(policeActiveState == 0 and policeService:getState().preparedPoliceId == 902)
assert(policeService:cancel("shiftStopped") and policeObjects[902] == nil)
policeObjects[903] = {
  getPosition = function() return policeVector(40, 0, 0) end,
  setActive = function() end,
  delete = function() policeObjects[903] = nil end
}
local pendingPoliceService = policeCheckModule.new()
assert(pendingPoliceService:prepare())
local pendingGroupName = preloadOptions.name
assert(pendingPoliceService:cancel("missionEnded"))
assert(pendingPoliceService:onVehicleGroupSpawned({903}, 52, pendingGroupName))
assert(policeObjects[903] == nil)
getObjectByID = savedPoliceGlobals.getObjectByID
gameplay_traffic = savedPoliceGlobals.gameplay_traffic
gameplay_police = savedPoliceGlobals.gameplay_police
gameplay_traffic_trafficUtils = savedPoliceGlobals.gameplay_traffic_trafficUtils
core_multiSpawn = savedPoliceGlobals.core_multiSpawn
extensions = savedPoliceGlobals.extensions
getPlayerVehicle = savedPoliceGlobals.getPlayerVehicle
map = savedPoliceGlobals.map
end)()

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
for _ = 1, 94 do vehicleScanGuard.update(0.016) end
assert(not vehicleScanGuard.isSuspended())

do
  local vehicleBridgeGuard = require("taxiDriver/vehicleBridgeGuard")
  local bridgeCallback = nil
  local bridgeVehicle = {getID = function() return 42 end}
  getObjectByID = function(id) return id == 42 and bridgeVehicle or nil end
  core_vehicleBridge = {
    requestValue = function(_, callback) bridgeCallback = callback end,
    executeAction = function() return true end
  }
  local acceptedBridgeCallback, rejectedBridgeCallback = false, false
  assert(vehicleBridgeGuard.request(bridgeVehicle, "energyStorage", function(_, currentVehicle)
    acceptedBridgeCallback = currentVehicle == bridgeVehicle
  end, function() rejectedBridgeCallback = true end))
  assert(vehicleScanGuard.onVehicleLifecycle(42, 42))
  bridgeCallback({})
  assert(not acceptedBridgeCallback and rejectedBridgeCallback)
  for _ = 1, 94 do vehicleScanGuard.update(0.016) end
  assert(vehicleBridgeGuard.request(bridgeVehicle, "energyStorage", function()
    acceptedBridgeCallback = true
  end))
  bridgeCallback({})
  assert(acceptedBridgeCallback)

  local isolatedCleanupRan = false
  local boundary = require("taxiDriver/faultBoundary").new({retrySeconds = 0.1})
  local boundaryOk = boundary:call("failingSubsystem", function() error("expected") end)
  assert(not boundaryOk)
  assert(boundary:cleanup("independentCleanup", function() isolatedCleanupRan = true end))
  assert(isolatedCleanupRan)
end

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
forwardTurnPlan = perception:planLocalBypass(perceptionVehicle, 91, {
  referencePoints = {
    {x = 0, y = 0, z = 0}, {x = 8, y = 10, z = 0}, {x = 5, y = 24, z = 0}
  },
  allowSpatialGraph = false
})
assert(forwardTurnPlan and forwardTurnPlan.strategy == "routeForwardTurn")
assert(forwardTurnPlan.signal == -1 and forwardTurnPlan.radius >= 4.8)
for _, point in ipairs(forwardTurnPlan.points) do assert(point.x >= -0.1) end
map.objects[91] = nil
forwardTurnPlan = perception:planLocalBypass(perceptionVehicle, nil, {
  referencePoints = {
    {x = 0, y = 0, z = 0}, {x = 8, y = 10, z = 0}, {x = 5, y = 24, z = 0}
  }
})
assert(forwardTurnPlan and forwardTurnPlan.strategy == "routeForwardTurn")
map.objects[91] = {pos = {x = 14, y = 0, z = 0}, vel = {x = 0, y = 0, z = 0},
  dirVec = {x = 1, y = 0, z = 0}}
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
if false then
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
end
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

local function guardVector(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  local value = {x = x or 0, y = y or 0, z = z or 0}
  local methods = {}
  function methods:dot(other)
    return self.x * other.x + self.y * other.y + self.z * other.z
  end
  function methods:normalize()
    local length = self:length()
    if length > 0 then
      self.x, self.y, self.z = self.x / length, self.y / length, self.z / length
    end
  end
  function methods:length() return math.sqrt(self:dot(self)) end
  return setmetatable(value, {
    __index = methods,
    __sub = function(a, b)
      return guardVector(a.x - b.x, a.y - b.y, a.z - b.z)
    end
  })
end
local guardSpeedCalls = {}
local guardObjects = {
  [42] = {pos = guardVector(0, 0, 0), vel = guardVector(20, 0, 0)},
  [88] = {pos = guardVector(60, 0, 0), vel = guardVector(10, 0, 0)}
}
vec3 = guardVector
mapmgr = {
  getObjects = function() return guardObjects end,
  enableTracking = function() end
}
obj = {
  getID = function() return 42 end,
  getPosition = function() return guardObjects[42].pos end,
  getVelocity = function() return guardObjects[42].vel end,
  getDirectionVector = function() return guardVector(1, 0, 0) end,
  getInitialLength = function() return 4.5 end,
  getInitialWidth = function() return 2 end,
  getObjectInitialLength = function() return 4.5 end,
  getObjectInitialWidth = function() return 2 end,
  queueGameEngineLua = function() end
}
ai = {
  setSpeed = function(value) guardSpeedCalls[#guardSpeedCalls + 1] = {value = value} end,
  setSpeedMode = function() end
}
guihooks = {trigger = function() end}
local stockAiObserver = dofile("lua/vehicle/extensions/taxiDriverStockAiObserver.lua")
assert(stockAiObserver.watch({
  followingTimeGap = 2.3, minimumGap = 4, brakingDeceleration = 3.5
}))
for _ = 1, 6 do stockAiObserver.updateGFX(0.1) end
assert(#guardSpeedCalls == 6)
local previousSpeed, previousDeceleration = 20, 0
for _, call in ipairs(guardSpeedCalls) do
  assert(call.value <= previousSpeed)
  local deceleration = (previousSpeed - call.value) / 0.1
  assert(deceleration >= previousDeceleration - 0.001)
  assert(deceleration - previousDeceleration <= 0.251)
  previousSpeed, previousDeceleration = call.value, deceleration
end
local smoothGuardState = stockAiObserver.getDebugState()
assert(smoothGuardState.safetyHolding and not smoothGuardState.emergencyBraking)
assert(smoothGuardState.appliedDeceleration > 0 and
  smoothGuardState.appliedDeceleration <= 3.5)

stockAiObserver.unwatch()
guardSpeedCalls = {}
guardObjects[88].pos, guardObjects[88].vel =
  guardVector(6, 0, 0), guardVector(0, 0, 0)
assert(stockAiObserver.watch())
stockAiObserver.updateGFX(0.1)
local emergencyGuardState = stockAiObserver.getDebugState()
assert(guardSpeedCalls[#guardSpeedCalls].value == 0)
assert(emergencyGuardState.emergencyBraking and
  emergencyGuardState.appliedDeceleration == 8.5)

stockAiObserver.unwatch()
guardSpeedCalls = {}
guardObjects[42].vel, guardObjects[88].vel =
  guardVector(10, 0, 0), guardVector(10, 0, 0)
assert(stockAiObserver.watch())
stockAiObserver.updateGFX(0.1)
local matchedSpeedGuardState = stockAiObserver.getDebugState()
assert(guardSpeedCalls[#guardSpeedCalls].value == 10)
assert(not matchedSpeedGuardState.emergencyBraking)
stockAiObserver.unwatch()

guardSpeedCalls = {}
guardObjects[42].vel = guardVector(8, 0, 0)
guardObjects[88] = {
  pos = guardVector(7, 4, 0), vel = guardVector(0, 0, 0)
}
input.state.steering.val = 0.65
assert(stockAiObserver.watch())
stockAiObserver.updateGFX(0.1)
local curvedPathGuardState = stockAiObserver.getDebugState()
assert(curvedPathGuardState.safetyHolding and
  curvedPathGuardState.curvedPathRisk and
  curvedPathGuardState.curvedPathRiskTime > 0)
assert(#guardSpeedCalls == 1 and guardSpeedCalls[1].value < 8)
stockAiObserver.unwatch()
input.state.steering.val = 0

guardSpeedCalls = {}
guardObjects[88] = nil
guardObjects[42].pos, guardObjects[42].vel =
  guardVector(0, 0, 0), guardVector(15, 0, 0)
assert(stockAiObserver.watch({
  targetX = 40, targetY = 4, targetZ = 0,
  targetDirX = 1, targetDirY = 0,
  arrivalRadius = 14, maximumArrivalSpeed = 4 / 3.6
}))
stockAiObserver.updateGFX(0.1)
local targetApproachState = stockAiObserver.getDebugState()
assert(targetApproachState.targetApproachActive and
  not targetApproachState.safetyHolding)
assert(targetApproachState.targetSpeedCap > 4 / 3.6 and
  targetApproachState.targetSpeedCap < 15)
assert(guardSpeedCalls[#guardSpeedCalls].value < 15)
stockAiObserver.unwatch()

guardSpeedCalls = {}
assert(stockAiObserver.watch({
  targetX = 40, targetY = 4, targetZ = 0,
  targetDirX = -1, targetDirY = 0,
  arrivalRadius = 14, maximumArrivalSpeed = 4 / 3.6
}))
stockAiObserver.updateGFX(0.1)
assert(not stockAiObserver.getDebugState().targetApproachActive)
assert(#guardSpeedCalls == 0)
stockAiObserver.unwatch()

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
  function methods:length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
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
  local vehicle = {jbeam = modelKey, partConfig = "/vehicles/" .. modelKey .. "/" .. configKey .. ".pc",
    position = position, velocity = fleetVector(0, 0, 0), commands = {}}
  function vehicle:getID() return id end
  function vehicle:getPosition() return self.position end
  function vehicle:getDirectionVector() return fleetVector(1, 0, 0) end
  function vehicle:getVelocity() return self.velocity end
  function vehicle:getInitialHeight() return 1.6 end
  function vehicle:setDynDataFieldbyName() end
  function vehicle:queueLuaCommand(command) self.commands[#self.commands + 1] = command end
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
    return {
      getRandomPathG = function() return {"n1", "n2", "n3"} end,
      getPath = function(_, startNode, destination) return {startNode, destination} end
    }
  end,
  getMap = function()
    return {nodes = {
      n1 = {pos = fleetVector(0, 0, 0)},
      n2 = {pos = fleetVector(1500, 0, 0)},
      n3 = {pos = fleetVector(3500, 0, 0)}
    }}
  end
}

do
local nativeFleetWorker = dofile("lua/ge/extensions/taxiDriver/fleetWorker.lua")
local nativeVehicle = mockFleetVehicle(303, "etk800", "base", fleetVector(0, 0, 0))
local nativeTarget = {pos = fleetVector(3500, 0, 0), nodeA = "n2", nodeB = "n3"}
local nativeRoute = {
  {wp = "n1", pos = fleetVector(0, 0, 0)},
  {wp = "n2", pos = fleetVector(1500, 0, 0)},
  {wp = "n3", pos = fleetVector(3500, 0, 0)}
}
local nativeWorker = nativeFleetWorker.new({updateOffset = 0})
assert(nativeWorker:start(nativeVehicle, nativeTarget, nativeRoute, taxiConfig.fleetAiPresets.standard))
local nativeStartCommand = nativeVehicle.commands[#nativeVehicle.commands]
assert(nativeStartCommand:find("ai.driveUsingPath", 1, true))
assert(nativeStartCommand:find("taxiDriverStockAiObserver.watch({", 1, true))
assert(nativeStartCommand:find("followingTimeGap=2.40", 1, true))
assert(nativeStartCommand:find("brakingDeceleration=2.80", 1, true))
assert(nativeStartCommand:find("updateInterval=0.20", 1, true))
assert(nativeStartCommand:find("trajectorySamples=6", 1, true))
assert(not nativeStartCommand:find(
  "taxiDriverAutopilotRecovery.watchRouteDone()", 1, true))
assert(not nativeStartCommand:find("taxiDriverAutopilotRecovery.start", 1, true))
assert(not nativeStartCommand:find("setGearboxOverride(true)", 1, true))
nativeVehicle.position = fleetVector(1600, 0, 0)
assert(nativeWorker:onRouteDone(nativeVehicle))
nativeWorker:update(nativeVehicle, 1.1)
local nativeReplanCommand = nativeVehicle.commands[#nativeVehicle.commands]
assert(nativeReplanCommand:find('path={"n2","n3"}', 1, true))
assert(not nativeReplanCommand:find('"n1"', 1, true))
nativeVehicle.position = fleetVector(3500, 0, 0)
assert(nativeWorker:onRouteDone(nativeVehicle) and nativeWorker:hasArrived(nativeVehicle))
nativeWorker:stop(nativeVehicle, "testComplete")
assert(nativeVehicle.commands[#nativeVehicle.commands]:find(
  "taxiDriverStockAiObserver.unwatch()", 1, true))

local stalledVehicle = mockFleetVehicle(304, "pickup", "base", fleetVector(0, 0, 0))
local stalledWorker = nativeFleetWorker.new({updateOffset = 0})
local stalledSettings = {}
for key, value in pairs(taxiConfig.fleetAiPresets.standard) do stalledSettings[key] = value end
stalledSettings.recoveryMaxAttempts = 1
assert(stalledWorker:start(stalledVehicle, nativeTarget, nativeRoute, stalledSettings))
for _ = 1, 100 do stalledWorker:update(stalledVehicle, 1) end
assert(stalledWorker:hasFailed(stalledVehicle))
stalledWorker:stop(stalledVehicle, "testComplete")
end

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

print("TaxiDriver Lua combinatorics: stock player AI routing, lightweight fleet routing, fleet presets/economy/lifecycle, AI logging, powertrain handshake, gameplay modes, and 500 deferred respawns passed")
