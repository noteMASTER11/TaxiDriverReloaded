local f=assert(io.open('lua/ge/extensions/taxiDriver/taxiDriver.lua','r'))
local source=f:read('*a'):gsub('\r\n','\n');f:close()
local function part(first,last)
  local a=assert(source:find(first,1,true),'Missing '..first)
  local b=assert(source:find(last,a+#first,true),'Missing '..last)
  return source:sub(a,b-1)
end
local production=part('function realisticFuel.serviceVehicle()','function realisticFuel.buildHud()')..
  part('function realisticFuel.buildHud()','local function buildHudState')..
  part('function realisticFuel.resetRefueling()','function realisticFuel.clearStation()')..
  part('function realisticFuel.resetRepairing()','function realisticFuel.clearRepairStation()')..
  part('function realisticFuel.refreshOptions()','-- On-demand current-damage read')..
  part('function realisticFuel.purchaseRepair()','function realisticFuel.repairVehiclePhysically')..
  part('function realisticFuel.openMagicStation(vehicle)','function realisticFuel.requestRoute()')..
  part('function M.requestFuelStop()','function M.onActivityAcceptGatherData')
local id=42
local vehicle={getID=function()return id end,getPosition=function()return {}end}
local tanks={{name='tank',energyType='gasoline',currentEnergy=10,maxEnergy=50}}
local writes=0
local fuel={refuelingCompletionId=0,detour={active=false},config={estimatedConsumptionPer100Km={gasoline=10},fuelRatePerSecond=10},
  energyMJPerUnit={gasoline=1},readableUnit={gasoline='L'},initializedVehicles={},
  energyToReadableUnit=function(v)return v end,readableUnitToEnergy=function(v)return v end,
  getPrice=function()return 3 end,isTypeAvailable=function()return true end,
  deferDashboardEnergy=function()end,recordBalanceHistory=function()end,
  repairLastDamagePercent=10,requestCurrentDamage=function(_,cb)cb(10)end,
  persistence={vehicleKey=function()return 'car' end,capture=function()end,applyUpdates=function()end,flush=function()end},
  beginDetour=function()error('Personal service must not redirect GPS or enter a taxi phase')end}
-- Assign the closures after the local exists.
fuel.clearStation=function()fuel.station=nil;fuel.options={};fuel.resetRefueling()end
fuel.clearRepairStation=function()fuel.repairStation=nil;fuel.resetRepairing()end
local env={M={_earthFree={snapshot=function()return {active=true}end}},realisticFuel=fuel,
  state={active=false,realisticMode=false,phase='inactive',balance=100,rating=4},
  userSettings={realisticMode=true},getPlayerVehicle=function()return vehicle end,
  getVehicleSpeedKmh=function()return 0 end,getObjectByID=function()return vehicle end,
  roundMoney=function(n)return math.floor(n*100+.5)/100 end,
  clampValue=function(n,a,b)return math.max(a,math.min(b,n))end,
  notifyHud=function()end,notifyHudPatch=function()end,showPhoneNotification=function()end,
  runtimeConfig={hudUpdateInterval=.1},taxiConfig={repair={minimumRepairableDamagePercent=.5}},
  Engine={Audio={playOnce=function()end}},vec3=function()return {}end,
  repairPricing={calculateDamagePercent=function()return 10 end,calculateRepairPrice=function()return 20 end},
  shiftTracking={recordFuelCost=function()end},logger={info=function()end},
  vehicleBridgeGuard={request=function(_,_,callback)callback({tanks},vehicle)end,
    execute=function(_,_,_,energy)writes=writes+1;tanks[1].currentEnergy=energy end}}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(production));setfenv(chunk,env);chunk()
fuel.resetRefueling();fuel.resetRepairing()
env.M.requestFuelStop()
assert(fuel.personalSession and fuel.station and fuel.repairStation)
assert(fuel.buildHud().available and fuel.buildRepairHud().price==20)
assert(not env.state.active and env.state.phase=='inactive' and env.state.rating==4)
fuel.purchase('gasoline',5);assert(fuel.refueling.active)
fuel.updateRefueling(10)
assert(writes==1 and tanks[1].currentEnergy==15 and env.state.balance==85,
  'personal fueling must deliver and charge once while taxi mode stays inactive')
fuel.purchaseRepair()
assert(fuel.repairing.active and fuel.repairing.cost==20,
  'personal repair must start with its normal price without activating a shift')
fuel.purchase('gasoline',5);assert(not fuel.refueling.active,'fuel and repair must remain mutually exclusive')
fuel.resetRepairing()
env.M.completeFuelStop()
assert(not fuel.personalSession and not fuel.station and not fuel.repairStation)
assert(env.state.phase=='inactive' and not env.state.active)
env.userSettings.realisticMode=false;env.M.requestFuelStop()
assert(fuel.buildRepairHud().price==0)
fuel.purchase('gasoline',5);fuel.updateRefueling(10)
assert(writes==2 and tanks[1].currentEnergy==20 and env.state.balance==85,
  'non-realistic personal services must not charge for fuel or repair')
env.M.completeFuelStop()
env.userSettings.realisticMode=true;env.M.requestFuelStop()
local pending
env.vehicleBridgeGuard.request=function(_,_,cb)pending=cb end
fuel.purchase('gasoline',5);env.M.completeFuelStop();pending({tanks},vehicle)
assert(writes==2 and env.state.balance==85, 'closing the form rejects late purchase callbacks')
env.M.requestFuelStop();id=43
assert(not fuel.serviceActive(), 'vehicle replacement must invalidate the personal service context')
print('Personal-route fuel, repair access and GPS isolation regressions passed')
