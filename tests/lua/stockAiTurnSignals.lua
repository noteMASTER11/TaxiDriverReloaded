-- driveUsingPath uses native manual mode, which never calls trafficActions.
local position = {x = -30, y = 0, z = 0}
local speed, heading = 10, {x = 1, y = 0, z = 0}
local calls = {}
obj = {getID = function() return 42 end, getPosition = function() return position end,
  getVelocity = function() return {x = speed * heading.x, y = speed * heading.y, z = 0} end,
  getDirectionVector = function() return heading end,
  getInitialLength = function() return 4.5 end, getInitialWidth = function() return 1.8 end,
  queueGameEngineLua = function() end}
electrics = {values = {wheelspeed = speed, signal_left_input = 0, signal_right_input = 0}}
local function signal(side, value, autoCancel)
  calls[#calls + 1] = {side = side, value = value, autoCancel = autoCancel}
  electrics.values['signal_' .. side .. '_input'] = value and 1 or 0
  if value then electrics.values['signal_' .. (side == 'left' and 'right' or 'left') .. '_input'] = 0 end
end
electrics.set_left_signal = function(value, autoCancel) signal('left', value, autoCancel) end
electrics.set_right_signal = function(value, autoCancel) signal('right', value, autoCancel) end
input = {event = function() end}
ai = {mode = 'manual', setSpeed = function() end, setSpeedMode = function() end,
  setRacing = function() end}
local observer = dofile('lua/vehicle/extensions/taxiDriverStockAiObserver.lua')
local function setup(turn, degree)
  observer.unwatch()
  electrics.values.signal_left_input, electrics.values.signal_right_input = 0, 0
  position, heading = {x = -30, y = 0, z = 0}, {x = 1, y = 0, z = 0}
  local positions = {a = {x = -100, y = 0, z = 0}, b = {x = 0, y = 0, z = 0},
    c = {x = turn == 'straight' and 100 or 0, y = turn == 'left' and 100 or turn == 'right' and -100 or 0, z = 0},
    d = {x = 0, y = turn == 'left' and -100 or 100, z = 0},
    e = {x = turn == 'straight' and 0 or 100, y = turn == 'straight' and -100 or 0, z = 0}}
  local graph = {a = {}, b = {}, c = {}, d = {}, e = {}}
  local function link(a,b)
    local edge = {drivability = 1, speedLimit = 20}
    graph[a][b], graph[b][a] = edge, edge
  end
  link('a','b'); link('b','c')
  if degree >= 3 then link('b','d') end
  if degree >= 4 then link('b','e') end
  mapmgr = {mapData = {positions = positions, graph = graph, radius = {}},
    getObjects = function() return {} end,
    findClosestRoad = function() return 'a','b' end}
  assert(observer.watch({routeNodes = {'a','b','c'}}))
  calls = {}
end
local function tick() observer.updateGFX(0.2) end
local function side() return electrics.values.signal_left_input == 1 and 'left'
  or electrics.values.signal_right_input == 1 and 'right' or 'off' end

for _, degree in ipairs({3,4}) do
  for _, turn in ipairs({'left','right'}) do
    setup(turn, degree)
    tick()
    assert(side() == turn, 'manual AI must signal ' .. turn .. ' before a ' .. degree .. '-leg intersection')
    assert(calls[1].autoCancel == false, 'route progress, not steering auto-cancel, owns the junction signal')
    for _ = 1,5 do tick() end
    assert(#calls == 1, 'repeated scans must not restart the flasher pulse')
    -- The signal stays on while waiting and during the turn, then clears.
    position = {x = 0, y = turn == 'left' and 3 or -3, z = 0}; tick()
    assert(side() == turn, 'do not cancel at the centre of the intersection')
    position.y = turn == 'left' and 20 or -20; tick()
    assert(side() == 'off', 'cancel after leaving the intersection')
  end
end
setup('straight',3); tick(); assert(side() == 'off', 'straight through a T-junction does not signal')
setup('straight',4); tick(); assert(side() == 'off', 'straight through a crossroad does not signal')
setup('left',2); tick(); assert(side() == 'off', 'a road bend without a junction does not signal')
setup('right',4); position.x = -90; tick(); assert(side() == 'off', 'do not signal too early')
position.x = -20; tick(); assert(side() == 'right')
observer.pause({}); tick(); assert(side() == 'off', 'paused AI must release and not relight its signal')
setup('left',3); tick(); observer.requestPark({}); assert(side() == 'off', 'parking must release the turn signal')
setup('right',3); tick(); observer.unwatch(); tick(); assert(side() == 'off', 'handoff must release the turn signal')
-- The observer does not own manually selected indicators while it is inactive.
electrics.set_left_signal(true,false); observer.updateGFX(0.2)
assert(side() == 'left', 'inactive observer must preserve player indicators')
setup('left',3); ai.mode = 'traffic'; tick(); assert(side() == 'off', 'native traffic mode retains its own signals')
ai.mode = 'manual'
-- Map authors often split a junction exit into several short graph edges.
setup('left',3)
mapmgr.mapData.positions.c = {x = 3, y = 0, z = 0}
mapmgr.mapData.positions.f = {x = 3, y = 100, z = 0}
mapmgr.mapData.graph.c.f, mapmgr.mapData.graph.f = {drivability = 1}, {c = {drivability = 1}}
observer.watch({routeNodes = {'a','b','c','f'}})
tick(); assert(side() == 'left', 'short exit connectors must not hide the upcoming turn')
observer.fail({},'test'); tick(); assert(side() == 'off', 'failure must release and not relight the signal')
setup('right',3); electrics.values.hazard_enabled = true; tick()
assert(#calls == 0, 'route signalling must not replace enabled hazard lights')
electrics.values.hazard_enabled = false
-- A straight connector can place the actual turn beyond the junction node.
setup('left',3)
mapmgr.mapData.positions.c = {x = 11, y = 0, z = 0}
mapmgr.mapData.positions.f = {x = 11, y = 100, z = 0}
mapmgr.mapData.graph.c.f, mapmgr.mapData.graph.f = {drivability = 1}, {c = {drivability = 1}}
observer.watch({routeNodes = {'a','b','c','f'}})
tick(); assert(side() == 'left')
position.x = 9; tick(); assert(side() == 'left', 'do not cancel on a connector before the actual turn')
position = {x = 11, y = 3, z = 0}; tick(); assert(side() == 'left', 'hold through a turn after a connector')
position.y = 20; tick(); assert(side() == 'off')
-- Adjacent junctions must remain separate manoeuvres, rather than averaging
-- a short left/right sequence into a straight continuation.
setup('left',3)
mapmgr.mapData.positions.c = {x = 0, y = 8, z = 0}
mapmgr.mapData.positions.f = {x = 100, y = 8, z = 0}
mapmgr.mapData.positions.g = {x = -100, y = 8, z = 0}
mapmgr.mapData.graph.c.f, mapmgr.mapData.graph.f = {drivability = 1}, {c = {drivability = 1}}
mapmgr.mapData.graph.c.g, mapmgr.mapData.graph.g = {drivability = 1}, {c = {drivability = 1}}
observer.watch({routeNodes = {'a','b','c','f'}})
tick(); assert(side() == 'left', 'the next junction must not hide the first left turn')
position = {x = 0, y = 7, z = 0}; tick()
assert(side() == 'right', 'a nearby following junction must get its own right signal')
print('PASS manual-route turn signals at crossroads and T-junctions')
