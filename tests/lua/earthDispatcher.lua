package.path = "lua/ge/extensions/?.lua;" .. package.path
local dispatcher = require("taxiDriver/earthDispatcher")

local function fixture(cities, extra)
  local candidates = {requests=0}
  function candidates:request(origin,maxKm,callback)
    self.requests=self.requests+1; self.maxKm=maxKm; self.callback=callback
    callback(cities)
    return true
  end
  function candidates:update() end
  function candidates:cancel() end
  function candidates:destroy() end
  local wire={requests={},callbacks={},pending=false}
  function wire:request(message,callback)
    assert(not self.pending,"only one route request may run")
    self.requests[#self.requests+1]=message;self.callbacks[#self.callbacks+1]=callback
    self.pending=true;return true
  end
  function wire:update() end
  function wire:cancel() self.pending=false end
  function wire:destroy() self.pending=false end
  local pose={lat=0,lon=0}
  local pickup={geo={lat=0.001,lon=0.002},pos={x=1},dir={x=1},name="Pickup"}
  local opts={candidateService=candidates,createTransport=function() return wire end,
    getOrigin=function() return pose end,getPickup=function() return pickup end}
  for k,v in pairs(extra or {}) do opts[k]=v end
  local service=dispatcher.new(opts)
  local function resolve(result,err)
    wire.pending=false;wire.callbacks[#wire.callbacks](result,err)
  end
  return service,wire,candidates,resolve,pose,pickup
end
local cities={
  {name="Near",lat=0,lon=0.02,distanceM=2224,source="earth_label"},
  {name="Middle",lat=0,lon=0.3,distanceM=33358,source="earth_label"},
  {name="Far",lat=0,lon=2,distanceM=222390,source="earth_label"}}
local function route(distance, lon)
  return {dist=distance,dur=distance/10,points={{lat=0.001,lon=0.002},{lat=0.01,lon=lon}},elev={10,20}}
end

-- Earth routing.py sends points as [lat,lon] and elevation as [distance,height].
do
  local s,_,_,resolve=fixture({{name="Destination",lat=35.7,lon=-119.3,source="earth_label"}},
    {getOrigin=function() return {lat=35.37,lon=-119.01} end,
     getPickup=function() return {geo={lat=35.37,lon=-119.01},name="Pickup"} end})
  s:start({unlimited=true,maxKm=100,targetCount=1});s:update(0)
  resolve({type="route_result",id=1,dist=45678,dur=3210,
    points={{35.37,-119.01},{35.69,-119.29}},elev={{0,123},{45678,456}}})
  local plan=s:takePlan()
  assert(plan,"the native Earth wire-format route must produce an offer")
  assert(plan.destination.geo.lat==35.69 and plan.destination.geo.lon==-119.29,
    "the destination must use the final road-snapped array coordinate")
  assert(plan.destination.geo.alt==456,"altitude must use the final elevation row height")
  assert(plan.distanceM==45678 and plan.durationS==3210 and not plan.points and not plan.elev)
end

-- Returning only a local route used to leave Unlimited orders at 1/12.
do
  local s,w,c,resolve,_,pickup=fixture(cities)
  s:start({unlimited=true,maxKm=600,targetCount=3})
  s:update(0)
  assert(c.maxKm==600 and #w.requests==1)
  local chosen={}
  for i=1,3 do
    local request=w.requests[#w.requests]
    chosen[request.lon1]=true
    assert(request.lat0==0.001 and request.lon0==0.002 and request.download=="off")
    resolve(route(i*10000,request.lon1+0.001))
    assert(#w.requests==i,"completion must not recursively launch another route")
    local plan=s:takePlan()
    assert(plan and plan.earth and plan.pickup==pickup and plan.distanceM==i*10000)
    assert(plan.destination.geo.lon==request.lon1+0.001 and plan.destination.geo.alt==20)
    assert(plan.destination.name and plan.durationS==i*1000 and not plan.points)
    assert(s:takePlan()==nil,"plans must only be consumed once")
    s:update(2)
  end
  assert(chosen[0.02] and chosen[0.3] and chosen[2],"Unlimited must cover different trip lengths")
  assert(s:stats().generated==3 and s:status()=="complete" and not s:hasPending())
end

-- A slow OSRM answer from a previous origin/start must never become an offer.
do
  local s,w,_,resolve,pose=fixture(cities)
  s:start({unlimited=true,maxKm=600});s:update(0)
  local stale=w.callbacks[1]
  s:start({unlimited=false,maxKm=600});stale(route(1000,0.02))
  assert(s:takePlan()==nil and s:stats().maxKm==25)
  s:update(2)
  assert(w.requests[2].lon1==0.02,"normal mode must exclude long candidates")
  pose.lon=20
  resolve(route(1000,0.02))
  assert(s:takePlan()==nil,"a teleport must invalidate an in-flight route even before the next update")
  assert(s:status()=="cancelled" and not s:hasPending())
end

-- Distances are accepted from the road route, never from a candidate estimate.
do
  local s,w,_,resolve=fixture({cities[1],{name="Other",lat=0,lon=0.03,source="earth_label"}})
  s:start({unlimited=false,maxKm=600,targetCount=1});s:update(0)
  resolve(route(26000,0.02));assert(s:takePlan()==nil)
  s:update(2);assert(#w.requests==2)
  resolve({error="NoRoute"});assert(s:takePlan()==nil)
  for _=1,50 do s:update(2);if w.pending then resolve(nil,"request timeout") end end
  assert(not s:hasPending() and s:status()=="exhausted" and s:stats().error~="")
  assert(#w.requests<=7,"network failure retries must have a finite per-run budget")
end

-- A pickup graph which is still loading must be polled at a bounded frequency.
do
  local s,w=fixture(cities,{getPickup=function() return nil end})
  local calls=0
  local s2=dispatcher.new({candidateService={request=function(_,_,_,cb) cb(cities) end,
      cancel=function() end,update=function() end,destroy=function() end},
    createTransport=function() return w end,getOrigin=function() return {lat=0,lon=0} end,
    getPickup=function() calls=calls+1;return nil end})
  s2:start({unlimited=true,maxKm=600})
  for _=1,100 do s2:update(0.01) end
  assert(calls<=4 and #w.requests==0,"loading pickup must not be polled every frame")
  for _=1,20 do s2:update(0.5) end
  assert(calls<=8 and s2:status()=="waiting" and not s2:hasPending())
  s:destroy();s2:destroy()
end

-- Fixed geometry failures must not be retried against the same cached OSRM route.
do
  local s,w,_,resolve=fixture({
    {name="Over limit",lat=0,lon=0.02,source="earth_label"},
    {name="No route",lat=0,lon=0.03,source="earth_label"},
    {name="HTTP 400",lat=0,lon=0.04,source="earth_label"},
    {name="Bad geometry",lat=0,lon=0.05,source="earth_label"}})
  s:start({unlimited=false,maxKm=25,targetCount=4})
  local seen={}
  for i=1,4 do
    s:update(2)
    local request=w.requests[#w.requests]
    seen[request.lon1]=(seen[request.lon1] or 0)+1
    if i==1 then resolve(route(26000,request.lon1))
    elseif i==2 then resolve({error="NoRoute"})
    elseif i==3 then resolve(nil,"HTTP 400 Bad Request")
    else resolve({dist=2000,dur=200,points={}}) end
  end
  for _=1,20 do s:update(2);if w.pending then resolve(nil,"request timeout") end end
  assert(#w.requests==4,"over-limit, NoRoute, HTTP400 and invalid geometry must each be attempted once")
  for _,count in pairs(seen) do assert(count==1) end
  assert(s:status()=="exhausted" and not s:hasPending())
end

-- Connection failures remain retryable, but cannot hold dispatch forever.
do
  local s,w,_,resolve=fixture({cities[1]})
  s:start({unlimited=true,maxKm=600,targetCount=1})
  s:update(0);resolve(nil,"connect timeout")
  s:update(2);assert(#w.requests==2)
  resolve(route(3000,0.02))
  assert(s:takePlan() and s:status()=="complete")
end

-- The far bucket favors feasible aerial distances inside the road-distance limit.
do
  local s,w=fixture({
    {name="Edge",lat=0,lon=5.3,source="earth_label"},
    {name="Middle far",lat=0,lon=3.2,source="earth_label"},
    {name="Near far",lat=0,lon=2,source="earth_label"}})
  s:start({unlimited=true,maxKm=600,targetCount=1});s:update(0)
  assert(w.requests[1].lon1==3.2,"far routes should leave room for road winding inside the chosen limit")
end

-- An endpoint/session swap invalidates routes even when the vehicle pose is unchanged.
do
  local endpoint={port=47613,sessionId="a"}
  local s,w,_,resolve=fixture(cities,{getEndpoint=function() return endpoint end})
  s:start({unlimited=true,maxKm=600});s:update(2)
  endpoint={port=47614,sessionId="b"}
  resolve(route(1000,0.02))
  assert(s:takePlan()==nil and s:status()=="cancelled")
end

-- A smaller Unlimited radius must still distribute offers across that radius.
do
  local s,w,_,resolve=fixture({cities[1],
    {name="Middle",lat=0,lon=0.1,source="earth_label"},
    {name="Long",lat=0,lon=0.4,source="earth_label"}})
  s:start({unlimited=true,maxKm=50,targetCount=3});s:update(0)
  assert(w.requests[1].lon1==0.02)
  resolve(route(3000,0.02));s:update(2)
  assert(w.requests[2].lon1==0.1,"medium offers must scale with the selected radius")
  resolve(route(13000,0.1));s:update(2)
  assert(w.requests[3].lon1==0.4)
end

-- A candidate provider which rejects its request must not leave dispatch pending forever.
do
  local s=dispatcher.new({candidateService={request=function() return false,"offline" end,
      cancel=function() end,update=function() end,destroy=function() end},
    getOrigin=function() return {lat=0,lon=0} end})
  local ok,err=s:start({unlimited=true,maxKm=600})
  assert(not ok and err=="offline" and s:status()=="error" and not s:hasPending())
end

-- Destroy is terminal, including an attempted restart from a previously queued UI action.
do
  local s,w=fixture(cities)
  s:start({unlimited=true,maxKm=600});s:update(0)
  local stale=w.callbacks[1]
  s:destroy();stale(route(1000,0.02))
  assert(s:takePlan()==nil and not s:hasPending())
  local ok,err=s:start({unlimited=true,maxKm=600})
  assert(not ok and err=="destroyed" and s:status()=="destroyed")
end

print("earthDispatcher: all tests passed")
