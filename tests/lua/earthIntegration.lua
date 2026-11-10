package.path="lua/ge/extensions/?.lua;"..package.path
local f=assert(io.open("lua/ge/extensions/taxiDriver/taxiDriver.lua","r"))
local source=f:read("*a"):gsub("\r\n","\n");f:close()
local function extracted(first,last,env,result)
  local a=assert(source:find(first,1,true));local b=assert(source:find(last,a+#first,true))
  local chunk=assert(loadstring(source:sub(a,b-1).."\nreturn "..result))
  setfenv(chunk,setmetatable(env,{__index=_G}));return chunk()
end
local vehicle={getPosition=function()return {}end,getDirectionVector=function()return {}end}
local forbidden=function()error("Earth orders must not search the local map for a world destination")end
local env={state={rating=4},getPlayerVehicle=function()return vehicle end,
  chooseTaxiStopPoint=forbidden,routePlanning={getStopCandidateCount=forbidden},
  userSettings={deliveryOrderSharePercent=0,unlimitedRouteDistance=true,randomEventsEnabled=false},
  runtimeConfig={minRideDistance=1000,maxRideDistance=25000,stopWaitingDuration=10},
  offerConfig={},taxiConfig={delivery={}},delivery={},
  rideRules={calculateFare=function(d)return d/1000+3 end,calculateRatingBonusRate=function()return 0 end,
    calculateEtaMinutes=function(d)return d/1000 end,calculatePickupWaitSeconds=function()return 180 end},
  roundMoney=function(n)return math.floor(n*100+.5)/100 end,clampValue=function(n)return n end,
  identity={createPassengerName=function()return "Passenger"end},tripEvents={needsTarget=function()return false end},
  offerPlan={},nextOfferId=1,M={}}
local create=extracted("local function createOffer(","local function createDiverseOffer",env,"createOffer")
local pickup={pos={},dir={},geo={lat=45,lon=39},routeDistance=300,name="Krasnodar"}
local destination={pos={},dir={},geo={lat=43.6,lon=39.7},routeDistance=292800,name="Sochi"}
local plan={earth=true,pickup=pickup,destination=destination,distanceM=292800,durationS=16800}
local offer=assert(create("normal",0,plan))
assert(offer.earth and offer.rideDistance==292800 and offer.destination.geo.lat==43.6)
assert(offer.totalEtaMinutes==280, "Earth ETA must come from the world route, not a truncated local path")
assert(offer.baseFare>250 and offer.pickup.name=="Krasnodar")
local remaining=extracted("local function getRemainingDistance()","local function getRouteProgress",{
  state={active=true,phase="toDestination"},trip=offer,phases={toPickup="toPickup",boarding="boarding",toStop="toStop",toFuelStation="toFuelStation"},
  M={_earthTrip={remaining=function(_,target)assert(target==destination);return 292000 end}},
  core_groundMarkers={getPathLength=function()return 500 end}},"getRemainingDistance")
assert(remaining()==292000, "HUD must use the whole Earth route rather than the local graph window")
local started,accepted,ack=0,nil,nil
local manualState={active=false}
local snapshot={owner="ui",startedTripId=0,route={status="ready",distanceM=292800,durationS=16800,
  from={name="Krasnodar",lat=45,lon=39},to={name="Sochi",lat=43.6,lon=39.7},
  roadFrom={lat=45.001,lon=39.001},roadTo={lat=43.601,lon=39.701}}}
local mod={_earthRouting={snapshot=function()return snapshot end,
  command=function(_,action,args)ack={action=action,args=args}end},
  _earthTrip={active=function()return true end,project=function(_,p)p.pos={};return p.pos end,
    distanceTo=function()return 300 end}}
mod.startMode=function()started=started+1;manualState.active=true;manualState.phase="searching"end
local start=extracted("function M.startEarthTrip(args)","function M.onExtensionLoaded()",{
  M=mod,state=manualState,phases={searching="searching"},getPlayerVehicle=function()return vehicle end,
  stopModeInternal=function()manualState.active=false end,
  notifyHud=function()end,
  createOffer=create,startAcceptedOffer=function(o)accepted=o;return true end},"M.startEarthTrip")
assert(start({owner="ui"}) and started==1 and accepted.earth)
assert(accepted.pickup.geo.lat==45.001 and accepted.destination.geo.lat==43.601,
  "manual trips must use road-snapped geographic endpoints")
assert(ack.action=="started" and ack.args.tripId==accepted.id)
manualState.phase="toDestination";ack=nil
assert(start({owner="ui"})==false and ack.action=="startFailed",
  "the start button cannot overwrite an active paid trip")
manualState.phase="searching"
snapshot.route.to.name="10 Downing Street"
snapshot.route.to.detail="Downing Street 10, London"
assert(start({owner="ui"}) and accepted.destination.address=="Downing Street 10, London",
  "known house numbers from a selected address must survive background address enrichment")
local restarts,updates=0,0
local paidOffer=accepted
mod._earthFree={start=function(_,r,mode)assert(r==snapshot.route);return true end,stop=function()end}
manualState.active=true;manualState.phase='searching'
assert(start({owner='ui',withoutPassenger=true}))
assert(not manualState.active and accepted==paidOffer and started==1,
  'passenger-free routes must not create a paid order or start taxi economy')
local dispatcher={status=function()return "cancelled"end,update=function()updates=updates+1 end}
local recoverMod={_earthDispatcher=dispatcher,_earthTrip={pose=function()return {lat=45,lon=39}end}}
local recover=extracted("function M.updateEarthDispatcher(dtReal)","function M.getEarthPickupStop()",{
  M=recoverMod,state={active=true,phase="searching"},phases={searching="searching"},
  offers={},offerTargetCount=12,beginSearching=function()restarts=restarts+1 end,
  os={clock=function()return 100 end,clockhp=function()return 100 end}},"M.updateEarthDispatcher")
recover(0.1);recover(0.1)
assert(restarts==1 and updates==2, "a recovered Earth connection restarts search once with bounded backoff")
print("Earth paid-offer and whole-route integration regressions passed")
