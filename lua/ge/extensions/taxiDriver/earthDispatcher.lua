-- Builds ordinary Earth offers through an isolated, request-only connection.
local M = {}
local function finite(v)
  v=tonumber(v)
  if v and v==v and v~=math.huge and v~=-math.huge then return v end
end
local function geo(p)
  if type(p)~="table" then return nil end
  local lat,lon=finite(p.lat or p[1]),finite(p.lon or p[2])
  if lat and lon and math.abs(lat)<=90 and math.abs(lon)<=180 then return {lat=lat,lon=lon} end
end
local function distance(a,b)
  local lat=math.rad(b.lat-a.lat)
  local lon=math.rad(b.lon-a.lon)
  local h=math.sin(lat/2)^2+math.cos(math.rad(a.lat))*math.cos(math.rad(b.lat))*math.sin(lon/2)^2
  return 12742017.6*math.asin(math.sqrt(math.min(1,h)))
end
local function key(p) return string.format("%.5f:%.5f",p.lat,p.lon) end
local function transientTransportError(err)
  if type(err)~="string" then return false end
  local message=err:lower()
  if message:find("noroute",1,true) or message:match("http%s*4%d%d") then return false end
  return message:find("timeout",1,true)~=nil or message:find("connect failed",1,true)~=nil or
    message:find("send failed",1,true)~=nil or message:find("receive failed",1,true)~=nil or
    message:find("connection reset",1,true)~=nil or message=="closed" or message=="busy"
end

function M.new(options)
  options=options or {}
  local service={}
  local createTransport=options.createTransport or function(args) return require("taxiDriver/earthTransport").new(args) end
  local candidates=options.candidateService or require("taxiDriver/earthCandidates").new({
    createTransport=createTransport,getEndpoint=options.getEndpoint})
  local transport,transportEndpoint,activeEndpoint
  local generation,requestId,clock=0,0,0
  local state="idle"
  local errorText=""
  local origin,maxKm,targetCount,generated,attempts= nil,25,12,0,0
  local queue,ready={}, {}
  local nextRouteAt=0
  local pickupAttempts,nextPickupAt=0,0
  local destroyed=false

  local function endpoint()
    local e=options.getEndpoint and options.getEndpoint() or 47613
    return type(e)=="table" and e or {port=e}
  end
  local function endpointKey()
    local e=endpoint()
    return tostring(e.port or 47613)..":"..tostring(e.sessionId or "")
  end
  local function stillCurrent(expected)
    if destroyed or expected~=generation then return false end
    local current=geo(options.getOrigin and options.getOrigin())
    if not current or not origin or distance(origin,current)>2000 or endpointKey()~=activeEndpoint then
      service:cancel()
      state,errorText="cancelled","Earth vehicle origin changed"
      return false
    end
    return true
  end

  local function organize(rows)
    local buckets={{},{},{}}
    local shortLimit=math.min(10000,maxKm*100)
    local mediumLimit=math.min(100000,maxKm*400)
    local seen={}
    for i,item in ipairs(type(rows)=="table" and rows or {}) do
      if i>128 then break end
      local p=geo(item)
      if p then
        local meters=distance(origin,p)
        local id=key(p)
        if meters>50 and meters<=maxKm*1000 and not seen[id] then
          seen[id]=true
          local bucket=meters<=shortLimit and 1 or (meters<=mediumLimit and 2 or 3)
          buckets[bucket][#buckets[bucket]+1]={lat=p.lat,lon=p.lon,name=item.name or "Earth",source=item.source or "radial",id=id,meters=meters}
        end
      end
    end
    local farTarget=maxKm*600
    for index,bucket in ipairs(buckets) do
      table.sort(bucket,function(a,b)
        if a.source~=b.source then return a.source=="earth_label" end
        if index==3 then
          local aGap,bGap=math.abs(a.meters-farTarget),math.abs(b.meters-farTarget)
          if aGap~=bGap then return aGap<bGap end
        end
        return a.meters>b.meters
      end)
    end
    while #buckets[1]+#buckets[2]+#buckets[3]>0 do
      for _,bucket in ipairs(buckets) do
        if #bucket>0 then queue[#queue+1]=table.remove(bucket,1) end
      end
    end
  end

  function service:cancel()
    if destroyed then return end
    generation=generation+1
    candidates:cancel()
    if transport then transport:cancel() end
    queue,ready={},{}
    state,errorText="idle",""
  end
  function service:start(args)
    if destroyed then return false,"destroyed" end
    self:cancel()
    args=args or {}
    maxKm=math.max(1,math.min(args.unlimited==true and 600 or 25,finite(args.maxKm) or 50))
    targetCount=math.max(1,math.min(128,math.floor(finite(args.targetCount) or 12)))
    generated,attempts,pickupAttempts=0,0,0
    nextRouteAt,nextPickupAt=clock,clock
    origin=geo(options.getOrigin and options.getOrigin())
    if not origin then state,errorText="error","Earth vehicle coordinates unavailable";return false,errorText end
    activeEndpoint=endpointKey()
    if transport and transportEndpoint~=activeEndpoint then transport:destroy();transport=nil end
    state="candidates"
    local expected=generation
    local ok,why=candidates:request(origin,maxKm,function(rows,err)
      if not stillCurrent(expected) then return end
      if err and not rows then state,errorText="error",tostring(err);return end
      organize(rows)
      state="ready"
    end)
    if ok==false then state,errorText="error",tostring(why or "Earth candidates unavailable");return false,errorText end
    return true
  end
  function service:update(dtReal)
    if destroyed then return end
    clock=clock+math.max(0,finite(dtReal) or 0)
    candidates:update(dtReal)
    if self:hasPending() and not stillCurrent(generation) then return end
    local before=state
    if transport then transport:update(dtReal) end
    if before=="routing" then return end
    if state~="ready" or clock<nextRouteAt then return end
    if generated>=targetCount then state="complete";return end
    if attempts>=targetCount*3+4 then state,errorText="exhausted","Earth route attempt budget exhausted";return end
    if clock<nextPickupAt then return end
    local candidate=table.remove(queue,1)
    if not candidate then state,errorText="exhausted","No routable Earth destinations remain";return end
    local pickup=options.getPickup and options.getPickup()
    local from=pickup and geo(pickup.geo)
    if not from then
      table.insert(queue,1,candidate)
      pickupAttempts=pickupAttempts+1;nextPickupAt=clock+0.5
      if pickupAttempts>=8 then state,errorText="waiting","Earth pickup is not available yet" end
      return
    end
    pickupAttempts=0
    if not transport then transport=createTransport(endpoint());transportEndpoint=activeEndpoint end
    attempts=attempts+1;candidate.tries=(candidate.tries or 0)+1;requestId=requestId+1
    state="routing";nextRouteAt=clock+2
    local expected=generation
    local function completed(result,err)
      if not stillCurrent(expected) then return end
      state="ready"
      local points=result and result.points
      local last=type(points)=="table" and points[#points]
      local to=geo(last)
      local meters,duration=finite(result and result.dist),finite(result and result.dur)
      if err or not result or result.error or not to or #points<2 or not meters or meters<=0 or meters>maxKm*1000 or not duration or duration<0 then
        errorText=tostring(err or (result and result.error) or "Earth route unavailable")
        if transientTransportError(err) and candidate.tries<3 then queue[#queue+1]=candidate end
        return
      end
      local elevations=result.elev
      local lastElevation=type(elevations)=="table" and elevations[#elevations]
      to.alt=finite(last.alt) or finite(type(lastElevation)=="table" and lastElevation[2] or lastElevation)
      local plan={earth=true,pickup=pickup,destination={geo=to,name=candidate.name,routeDistance=meters},
        distanceM=meters,durationS=duration,source=candidate.source}
      ready[#ready+1]=plan
      generated=generated+1;errorText=""
      if generated>=targetCount then state="complete" end
      if options.onPlan then options.onPlan(plan) end
    end
    local ok,err=transport:request({type="route",id=requestId,lat0=from.lat,lon0=from.lon,
      lat1=candidate.lat,lon1=candidate.lon,download="off"},completed)
    if not ok then completed(nil,err or "Earth route request rejected") end
  end
  function service:takePlan() return table.remove(ready,1) end
  function service:hasPending() return state=="candidates" or state=="ready" or state=="routing" end
  function service:status() return state end
  function service:stats()
    return {status=state,error=errorText,generated=generated,attempts=attempts,maxKm=maxKm,targetCount=targetCount,readyCount=#ready}
  end
  function service:destroy()
    if destroyed then return end
    self:cancel();destroyed=true;state="destroyed"
    candidates:destroy()
    if transport then transport:destroy();transport=nil end
  end
  return service
end
return M
