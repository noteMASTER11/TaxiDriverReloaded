package.path = "lua/ge/extensions/?.lua;" .. package.path
local api, session, emitted, writes, busyTrip = nil, "one", 0, 0, false
local pose = {lat=35.4,lon=-118.7,camera=false}
local calls, cancelled, lastCallback = {}, 0, nil
local transport = {}
function transport:request(message, callback)
  calls[#calls+1] = message; lastCallback = callback; return true
end
function transport:update() end
function transport:cancel() cancelled=cancelled+1 end
function transport:destroy() end
function transport:stats() return {requests=#calls} end
package.preload["taxiDriver/earthTransport"] = function() return {new=function() return transport end} end
local routing = require("taxiDriver/earthRouting")
local function service(saved)
  return routing.new({getApi=function() return api end,
    getSession=function() return session,47613 end,
    createTransport=function() return transport end,
    emit=function() emitted=emitted+1 end,
    read=function() return saved end,
    write=function() writes=writes+1;return true end,
    isTripActive=function() return busyTrip end})
end
local s=service()
s:update(0)
assert(not s:snapshot().available, "ordinary maps must not expose Earth controls")
api={version=function()return 1,1 end,earthVersion=function()return "1.9.1-beta"end,
  connected=function()return true end,inWorld=function()return true end,ready=function()return true end,
  pose=function()return pose end,gps=function()return nil end,gpsSet=function()return true end}
s:update(1)
assert(s:snapshot().status=="ready")
s:command("open",{})
s:command("search",{field="b",query="Bakersfield"})
assert(#calls==1 and calls[1].type=="geocode" and calls[1].full==true)
local old=lastCallback
local results={}
for i=1,12 do results[i]={name="City "..i,detail="California",lat=35+i/100,lon=-119} end
lastCallback({type="geocode_result",results=results})
assert(#s:snapshot().b.results==8, "search results must be bounded")
s:command("select",{field="b",index=1})
assert(s:snapshot().b.selected.name=="City 1" and writes>0)
pose={lat=36,lon=-120,camera=false}
s:command("preview",{})
assert(calls[#calls].type=="route" and calls[#calls].download=="off")
assert(calls[#calls].lat0==36, "vehicle start is captured at request time")
lastCallback({dist=2500000,dur=100000,points={{36,-120},{35.01,-119}}})
assert(s:snapshot().route.status=="ready" and s:snapshot().route.distanceM==2500000,
  "long routes must not use the normal map's 25km limit")
assert(s:snapshot().route.points==nil, "full route geometry must not enter regular HUD snapshots")
s:command("edit",{field="b",query="other"})
assert(s:snapshot().route.status=="idle" and s:snapshot().b.selected==nil)
s:command("search",{field="b",query="other"})
local late=lastCallback
s:command("close",{})
late({results=results})
assert(not s:snapshot().b.searching and #s:snapshot().b.results==0,
  "late replies after close must not restore results")
s:command("open",{})
s:command("mode",{mode="points"})
for _,field in ipairs({"a","b"}) do
  s:command("search",{field=field,query="Bakersfield"})
  if s:snapshot()[field].searching then lastCallback({results=results}) end
  s:command("select",{field=field,index=field=="a" and 1 or 2})
end
s:command("preview",{})
assert(calls[#calls].lat0==35.01 and calls[#calls].lat1==35.02,
  "arbitrary A and B must both reach Earth")
local previous=lastCallback
session="two";s:update(1)
previous({dist=42,dur=10,points={{1,2},{3,4}}})
assert(s:snapshot().route.status~="ready", "a previous connection cannot complete the new session")
assert(s:snapshot().b.selected~=nil, "geographic selections survive a connection change")
busyTrip=true
local gpsCalls=0;api.gpsSet=function()gpsCalls=gpsCalls+1;return true end
s:command("navigate",{target="b"})
assert(gpsCalls==0, "preview must not take over an active taxi order's GPS")
busyTrip=false;s:update(1)
s:command("navigate",{target="b"})
assert(gpsCalls==1)
s:command("search",{field="a",query="bad"})
lastCallback({results={{name="NaN",lat=0/0,lon=0},{name="range",lat=1000,lon=0}}})
assert(#s:snapshot().a.results==0, "invalid geocoder coordinates are rejected")
local restored=service({mode="points",a={name="Saved",lat=45,lon=10},
  b={name="Bad",lat=1000,lon=0},history={}})
assert(restored:snapshot().a.selected.name=="Saved" and restored:snapshot().b.selected==nil)
local before=#calls
restored:command("preview",{})
assert(#calls==before, "missing selection cannot trigger a network request")
s:destroy();old({results=results})
assert(cancelled>0 and emitted>0)
local inEarth,connected=true,true
api.inWorld=function()return inEarth end
api.connected=function()return connected end
local switching=service();switching:update(0)
assert(switching:snapshot().available)
switching:command("open",{owner="switch-test"})
switching:command("search",{owner="switch-test",field="b",query="Paris"})
local stale=lastCallback
inEarth=false;switching:update(1)
assert(not switching:snapshot().available,
  "an installed Earth API must not expose Earth controls outside the Earth level")
assert(switching:snapshot().status=="outsideWorld" and not switching:snapshot().b.searching)
stale({results=results})
assert(#switching:snapshot().b.results==0, "a reply from the old Earth world cannot populate the ordinary level")
inEarth=true;connected=false;switching:update(1)
assert(switching:snapshot().available and switching:snapshot().status=="disconnected",
  "Earth controls stay visible while the active Earth level reconnects")
connected=true;switching:update(1)
assert(switching:snapshot().available and switching:snapshot().status=="ready")
api=nil;switching:update(1)
assert(not switching:snapshot().available and switching:snapshot().status=="absent")
switching:destroy()
api={version=function()return 1 end,connected=function()return true end,
  inWorld=function()return true end,ready=function()return true end,
  pose=function()return pose end,gps=function()return nil end,gpsSet=function()return true end}
local owned=service();owned:update(0)
owned:command("open",{owner="first"})
owned:command("search",{owner="first",field="b",query="Paris"})
owned:command("close",{owner="second"})
assert(owned:snapshot().b.searching, "another HUD must not cancel the owner's request")
owned:command("close",{owner="first"})
assert(not owned:snapshot().b.searching)
owned:command("open",{owner="first"})
owned:update(8);owned:command("heartbeat",{owner="first"});owned:update(8)
assert(owned:stats().opened, "live owners retain their lease")
owned:update(11)
assert(not owned:stats().opened, "a crashed or disconnected HUD cannot leave background polling active")
local moved=0
api.teleport=function(lat,lon) moved=moved+1;assert(lat==45.001 and lon==10.001);return true end
restored:update(0);restored:command("open",{})
restored:command("teleport",{target="a"})
assert(moved==0 and lastCallback, "a city-centre coordinate must be snapped to a road before teleporting")
lastCallback({dist=0,dur=0,points={{45.001,10.001},{45.001,10.001}}})
assert(moved==1, "teleport A must use Earth's road-snapped geographic API")
busyTrip=true;restored:command("teleport",{target="a"});busyTrip=false
assert(moved==1, "teleport must not interrupt an active taxi order")
local randomService=service({mode="points",a={name="Start",lat=35,lon=-119},history={},maxRandomKm=999})
local settingsOnly=service();settingsOnly:update(0)
settingsOnly:command("setRandomLimit",{owner="settings-hud",maxRandomKm=600})
assert(settingsOnly:snapshot().maxRandomKm==600 and not settingsOnly:stats().opened,
  "Gameplay settings save without an open Earth panel lease")
randomService:update(0);randomService:command("open",{})
assert(randomService:snapshot().maxRandomKm==600, "saved random limit is bounded at 600km")
randomService:command("setRandomLimit",{maxRandomKm=50})
randomService:command("randomPreview",{})
local attemptsBefore=#calls
assert(randomService:snapshot().route.status=="pending", "random planning needs no selected B")
for i=1,4 do lastCallback({dist=60001,dur=2000,points={{35,-119},{36,-118}}}) end
assert(randomService:snapshot().route.status=="error" and #calls==attemptsBefore+3,
  "random routes over the configured road distance get at most four attempts")
randomService:command("randomPreview",{})
lastCallback({dist=49000,dur=1900,points={{35,-119},{35.1,-119.2}}})
assert(randomService:snapshot().route.status=="ready" and
  randomService:snapshot().b.selected.lat==35.1, "random destination uses the road-snapped endpoint")
local randomPrevious=lastCallback
randomService:command("randomPreview",{})
randomService:command("close",{})
randomPrevious({dist=100,dur=10,points={{35,-119},{35.2,-119.3}}})
assert(randomService:snapshot().route.status~="ready", "cancelled random planning cannot restore a route")
local bounded=service();bounded:update(0);bounded:command("open",{})
for i=1,100 do
  bounded:command("search",{field="b",query="city"..i})
  lastCallback({results={{name="City "..i,lat=30+i/100,lon=-100}}})
  bounded:command("select",{field="b",index=1})
end
assert(bounded:stats().searchCache==32 and bounded:stats().history==12,
  "repeated searches and selections must reach a fixed memory bound")
bounded:command("close",{})
assert(not bounded:stats().opened)
local preference=service({withoutPassenger=true});preference:update(0)
assert(preference:snapshot().withoutPassenger==true, 'passenger-free preference survives service recreation')
preference:command('open',{})
local beforeWrite=writes;preference:command('setWithoutPassenger',{value=false})
assert(not preference:snapshot().withoutPassenger and writes==beforeWrite+1)
api.place=function()return {street='Old Street',place='City'}end
preference:update(1);assert(preference:snapshot().location=='Old Street')
api.place=function()return {street='New Street',place='City'}end
preference:update(1);assert(preference:snapshot().location=='New Street')
api.inWorld=function()return false end
preference:update(1);assert(preference:snapshot().location=='')
preference:destroy()
print("Earth route lifecycle, long-distance, persistence and GPS ownership regressions passed")
