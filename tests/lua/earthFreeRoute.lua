package.path="lua/ge/extensions/?.lua;"..package.path
local p={lat=45,lon=39,speed=0}
local gps,sets,clears=nil,0,0
local api={inWorld=function()return true end,ready=function()return true end,pose=function()return p end,
  gps=function()return gps end,gpsSet=function(lat,lon,name)sets=sets+1;gps={lat=lat,lon=lon,name=name,planning=true};return true end,
  gpsClear=function()clears=clears+1;gps=nil end}
local f=require('taxiDriver/earthFreeRoute').new({getApi=function()return api end})
local route={status='ready',from={lat=45.01,lon=39,name='A'},to={lat=46,lon=40,name='B'},distanceM=200000,durationS=10000}
assert(f:start(route,'points'))
assert(f:snapshot().active and f:snapshot().leg=='a' and sets==1)
f:update(.5);assert(sets==1, 'frame updates must not restart GPS')
p.lat=45.01;f:update(.5)
assert(f:snapshot().leg=='b' and sets==2)
gps.planning=false;gps.remaining=190000;gps.eta=9500
f:update(.5);assert(f:snapshot().remainingM==190000 and f:snapshot().etaS==9500)
api.ready=function()return false end;gps.remaining=0
f:update(.5);assert(f:snapshot().remainingM==190000, 'loading pauses route progress')
api.ready=function()return true end;p.lat=46;p.lon=40;f:update(.5)
assert(not f:snapshot().active and f:snapshot().status=='complete' and clears==1)
assert(f:start(route,'vehicle') and f:snapshot().leg=='b')
gps={lat=10,lon=20,name='Other navigation'};f:update(.5)
assert(not f:snapshot().active and clears==1, 'manual GPS handoff must preserve the new destination')
assert(f:start(route,'vehicle'));api.inWorld=function()return false end;f:update(.5)
assert(not f:snapshot().active, 'leaving Earth retires a personal route')
print('Earth passenger-free route sequencing and GPS ownership regressions passed')
