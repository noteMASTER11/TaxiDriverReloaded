-- Geographic route previews use a separate Earth connection. Its route/prefetch
-- state belongs to that connection, never to the game's streaming connection.
local M = {}
local savePath = "/settings/TaxiDriver/earth_routes.json"

local function finite(value)
  value = tonumber(value)
  if value and value == value and value ~= math.huge and value ~= -math.huge then return value end
end
local function text(value, limit)
  if type(value)~="string" then return "" end
  local cut=math.min(#value,limit or 200)
  -- Keep a complete UTF-8 character when bounding place labels and errors.
  while cut>0 and cut<#value do
    local nextByte=value:byte(cut+1)
    if nextByte<128 or nextByte>191 then break end
    cut=cut-1
  end
  return value:sub(1,cut)
end
local function place(value)
  if type(value) ~= "table" then return nil end
  local lat, lon = finite(value.lat), finite(value.lon)
  if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then return nil end
  return {lat=lat,lon=lon,name=text(value.name,160),detail=text(value.detail,240)}
end
local function field() return {query="",selected=nil,results={},searching=false,error=""} end
local function idleRoute() return {status="idle",distanceM=0,durationS=0,error=""} end
local function randomLimit(value)
  return math.max(1,math.min(600,finite(value) or 50))
end
local function radialPoint(origin,meters,bearing)
  local lat,lon=math.rad(origin.lat),math.rad(origin.lon)
  local d=meters/6371008.8
  local destLat=math.asin(math.sin(lat)*math.cos(d)+math.cos(lat)*math.sin(d)*math.cos(bearing))
  local destLon=lon+math.atan2(math.sin(bearing)*math.sin(d)*math.cos(lat),
    math.cos(d)-math.sin(lat)*math.sin(destLat))
  return {lat=math.deg(destLat),lon=(math.deg(destLon)+540)%360-180}
end
local function invoke(api, method)
  if not (api and type(api[method]) == "function") then return nil end
  local ok, value = pcall(api[method]); if ok then return value end
end
local function readSettings()
  if type(jsonReadFile) == "function" then return jsonReadFile(savePath) end
end
local function writeSettings(value)
  if type(jsonWriteFile) ~= "function" then return false end
  if FS then FS:directoryCreate("/settings/TaxiDriver", true) end
  return jsonWriteFile(savePath,value,false)
end
local function sessionInfo()
  local core = rawget(_G,"beamngEarth_core")
  local hello = invoke(core,"serverHello")
  local ok, net = pcall(require,"beamngEarth/net")
  return hello and hello.sessionId or "", ok and net.PORT or 47613
end

function M.new(options)
  options = options or {}
  local service = {}
  local getApi = options.getApi or function() return rawget(_G,"beamngEarth_api") end
  local getSession = options.getSession or sessionInfo
  local createTransport = options.createTransport or function(args)
    return require("taxiDriver/earthTransport").new(args)
  end
  local emit, read, write = options.emit, options.read or readSettings, options.write or writeSettings
  local isTripActive = options.isTripActive or function() return false end
  local state = {available=false,status="absent",mode="vehicle",a=field(),b=field(),
    route=idleRoute(),gps=nil,error="",canNavigate=false,owner="",maxRandomKm=50,randomAttempt=0,startedTripId=0}
  local opened, destroyed, clock, detectAt, gpsAt = false,false,0,0,0
  local lastOwnerSeen=0
  local generation, requestId, transport, transportPort, currentSession = 0,0,nil,nil,nil
  local cache, cacheOrder, history = {},{},{}
  local api

  local function publish()
    if not destroyed and emit then emit(state) end
  end
  local function persist()
    local ok, result = pcall(write,{schemaVersion=1,mode=state.mode,
      a=place(state.a.selected),b=place(state.b.selected),history=history,maxRandomKm=state.maxRandomKm})
    if not ok or result == false then state.error="Could not save Earth places" end
  end
  local function remember(selected)
    local nextHistory = {place(selected)}
    for _, item in ipairs(history) do
      if #nextHistory>=12 then break end
      if item.lat~=selected.lat or item.lon~=selected.lon then nextHistory[#nextHistory+1]=item end
    end
    history=nextHistory
  end
  local function cancel()
    generation=generation+1
    if transport then transport:cancel() end
    state.a.searching,state.b.searching=false,false
    if state.route.status=="pending" then state.route=idleRoute() end
  end
  local function updateGps()
    local gps=invoke(api,"gps")
    state.gps = type(gps)=="table" and {name=text(gps.name),remaining=finite(gps.remaining),
      eta=finite(gps.eta),planning=gps.planning==true,lat=finite(gps.lat),lon=finite(gps.lon)} or nil
  end
  local function detect()
    api=getApi()
    local inWorld=invoke(api,"inWorld")==true
    local status="absent"
    if api then
      if invoke(api,"version")~=1 then status="unsupported"
      elseif not inWorld then status="outsideWorld"
      elseif invoke(api,"connected")~=true then status="disconnected"
      elseif invoke(api,"ready")~=true then status="loading"
      else status="ready" end
    end
    local beforeStatus,beforeCan=state.status,state.canNavigate
    state.available=inWorld and status~="unsupported"
    state.status=status
    local p=invoke(api,"pose")
    state.canNavigate=status=="ready" and p~=nil and p.camera~=true and not isTripActive() and
      not (state.route.status=="pending" and state.route.teleport)
    if status=="ready" or status=="loading" then
      local session,port=getSession()
      if currentSession and currentSession~=session then
        cancel();state.route=idleRoute();cache,cacheOrder={},{}
      end
      currentSession=session
      if transport and transportPort~=port then transport:destroy();transport=nil end
      transportPort=port
    elseif beforeStatus~=status then
      cancel();state.route=idleRoute();state.gps=nil
    end
    return beforeStatus~=status or beforeCan~=state.canNavigate
  end
  local function available()
    detect()
    if state.status=="ready" or state.status=="loading" then return true end
    state.error="BeamNG.Earth is not connected to an open Earth world"
    return false
  end
  local function request(message, callback)
    if not transport then transport=createTransport({port=transportPort or 47613}) end
    requestId=requestId+1;message.id=requestId
    local expected=generation
    local ok, why=transport:request(message,function(result,err)
      if destroyed or not opened or expected~=generation then return end
      callback(result,err);publish()
    end)
    if not ok then callback(nil,why or "Earth request could not start");publish() end
  end
  local function cacheKey(query)
    local p=invoke(api,"pose") or {}
    return query:lower()..":"..math.floor((finite(p.lat) or 0)*10)..":"..
      math.floor((finite(p.lon) or 0)*10),p
  end
  local function saveCache(key,results)
    if not cache[key] then cacheOrder[#cacheOrder+1]=key end
    cache[key]={at=clock,results=results}
    while #cacheOrder>32 do cache[table.remove(cacheOrder,1)]=nil end
  end
  local function search(args)
    local target=state[args.field]
    if args.field~="a" and args.field~="b" then return end
    cancel();state.route=idleRoute()
    target.query=text(args.query,2000):gsub("^%s+",""):gsub("%s+$","")
    target.selected,target.results,target.error=nil,{},""
    if #target.query<3 then target.error="Enter at least 3 characters";return end
    if #target.query>800 then target.error="Search text is too long";return end
    if not available() then return end
    local key,p=cacheKey(target.query)
    if cache[key] and clock-cache[key].at<600 then target.results=cache[key].results;return end
    target.searching=true
    request({type="geocode",q=target.query,lat=p.lat,lon=p.lon,full=true},function(result,err)
      target.searching=false
      if err or not result or result.error then
        target.error=text(err or (result and (result.text or result.error)) or "Place search failed",400)
        return
      end
      local results={}
      for _, item in ipairs(type(result.results)=="table" and result.results or {}) do
        local valid=place(item)
        if valid then results[#results+1]=valid end
        if #results>=8 then break end
      end
      target.results=results;saveCache(key,results)
    end)
  end
  local function preview()
    cancel();state.route=idleRoute()
    if not available() then return end
    local origin=state.mode=="vehicle" and invoke(api,"pose") or state.a.selected
    if state.mode=="vehicle" and origin and origin.camera then origin=nil end
    local from,to=place(origin),place(state.b.selected)
    if not from or not to then state.error="Select both route endpoints, or use the current vehicle";return end
    if state.mode=="vehicle" then from.name="Current vehicle" end
    state.route={status="pending",from=from,to=to,distanceM=0,durationS=0,error=""}
    local route=state.route
    request({type="route",lat0=from.lat,lon0=from.lon,lat1=to.lat,lon1=to.lon,download="off"},function(result,err)
      local distance,duration=finite(result and result.dist),finite(result and result.dur)
      if err or not result or result.error or not distance or distance<0 or not duration or duration<0 or
        type(result.points)~="table" or #result.points<2 then
        route.status="error";route.error=text(err or (result and result.error) or "No driving route found",400)
        return
      end
      route.status,route.distanceM,route.durationS="ready",distance,duration
      local first,last=result.points[1],result.points[#result.points]
      route.roadFrom=place({lat=first[1],lon=first[2],name=from.name})
      route.roadTo=place({lat=last[1],lon=last[2],name=to.name})
      -- Deliberately do not retain the full Earth geometry in the HUD/store.
    end)
  end

  local function randomPreview()
    cancel();state.route=idleRoute();state.randomAttempt=0
    if not available() then return end
    local origin=state.mode=="vehicle" and invoke(api,"pose") or state.a.selected
    if state.mode=="vehicle" and origin and origin.camera then origin=nil end
    local from=place(origin)
    if not from then state.error="Select point A or use the current vehicle";return end
    if state.mode=="vehicle" then from.name="Current vehicle" end
    local limit=state.maxRandomKm*1000
    state.route={status="pending",from=from,distanceM=0,durationS=0,error="",random=true}
    state.b.selected,state.b.results=nil,{}
    local route=state.route
    local attempt
    attempt=function()
      state.randomAttempt=state.randomAttempt+1
      local destination=radialPoint(from,limit*(0.35+0.3*math.random()),math.random()*math.pi*2)
      request({type="route",lat0=from.lat,lon0=from.lon,lat1=destination.lat,lon1=destination.lon,
        download="off"},function(result,err)
        local distance,duration=finite(result and result.dist),finite(result and result.dur)
        local points=result and result.points
        local last=type(points)=="table" and points[#points] or nil
        local to=type(last)=="table" and place({lat=last[1],lon=last[2]}) or nil
        if not err and result and not result.error and distance and distance>0 and distance<=limit and
          duration and duration>=0 and to and #points>=2 then
          to.name=string.format("%.5f, %.5f",to.lat,to.lon);to.detail="Earth · OSRM"
          route.to,route.status,route.distanceM,route.durationS=to,"ready",distance,duration
          route.roadFrom=place({lat=points[1][1],lon=points[1][2],name=from.name})
          route.roadTo=to
          state.b.selected,state.b.query=to,to.name
          remember(to);persist()
          return
        end
        -- Transport/service failures stop immediately. Only a road-network miss
        -- or a route exceeding the chosen distance gets another bounded try.
        local reason=text(err or (result and result.error),400)
        local networkMiss=reason=="" or reason:find("NoRoute",1,true) or reason:find("NoSegment",1,true)
        if not err and networkMiss and state.randomAttempt<4 then attempt()
        else
          route.status="error"
          route.error=reason~="" and reason or
            string.format("No driving route within %.0f km after %d attempts",state.maxRandomKm,state.randomAttempt)
        end
      end)
    end
    attempt()
  end

  local function teleportA()
    detect()
    local selected=state.mode=="points" and place(state.a.selected) or nil
    if not state.canNavigate then state.error="Teleport requires a ready Earth vehicle and no active taxi shift";return end
    if not selected then state.error="Select point A first";return end
    if type(api.teleport)~="function" then state.error="Earth teleport is unavailable";return end
    cancel()
    state.route={status="pending",distanceM=0,durationS=0,error="",teleport=true}
    state.canNavigate=false
    local route=state.route
    -- A geocoder often returns a town hall or building centroid. A zero-length
    -- OSRM route returns the driveable snapped position without loading a city.
    request({type="route",lat0=selected.lat,lon0=selected.lon,
      lat1=selected.lat,lon1=selected.lon,download="off"},function(result,err)
      local first=result and type(result.points)=="table" and result.points[1]
      local road=type(first)=="table" and place({lat=first[1],lon=first[2]}) or nil
      state.route=idleRoute();detect()
      if err or not result or result.error or not road then
        route.status="error";route.error=text(err or (result and result.error) or "No road near point A",400)
        state.route=route
        return
      end
      if not state.canNavigate then state.error="Earth is no longer ready for teleport";return end
      local accepted,reason=api.teleport(road.lat,road.lon,selected.name)
      if not accepted then state.error=text(reason or "Earth did not accept the teleport",400) end
      detect()
    end)
  end

  local ok,saved=pcall(read)
  if ok and type(saved)=="table" then
    state.maxRandomKm=randomLimit(saved.maxRandomKm)
    state.mode=saved.mode=="points" and "points" or "vehicle"
    state.a.selected,state.b.selected=place(saved.a),place(saved.b)
    state.a.query=state.a.selected and state.a.selected.name or ""
    state.b.query=state.b.selected and state.b.selected.name or ""
    for _, item in ipairs(type(saved.history)=="table" and saved.history or {}) do
      local valid=place(item);if valid then history[#history+1]=valid end
      if #history>=12 then break end
    end
  end

  function service:snapshot() return state end
  function service:command(action,args)
    if destroyed then return state end
    args=type(args)=="table" and args or {}
    if action~="open" and action~="setRandomLimit" and args.owner and args.owner~=state.owner then return state end
    lastOwnerSeen=clock
    state.error=""
    if action=="open" then
      local owner=text(args.owner,96)
      if opened and owner~=state.owner then cancel() end
      state.owner=owner;state.startedTripId=0;opened=true;detect();updateGps()
    elseif action=="close" then
      opened=false;cancel();state.a.results,state.b.results={},{};state.owner=""
    elseif action=="heartbeat" then return state
    elseif action=="started" then state.startedTripId=tonumber(args.tripId) or 0
    elseif action=="startFailed" then state.error=text(args.error or "Earth trip could not start",400)
    elseif action=="mode" then
      cancel();state.route=idleRoute();state.mode=args.mode=="points" and "points" or "vehicle";persist()
    elseif action=="setRandomLimit" then
      if state.route.random then cancel();state.route=idleRoute() end
      state.maxRandomKm=randomLimit(args.maxRandomKm);persist()
    elseif action=="edit" then
      if args.field=="a" or args.field=="b" then
        local target=state[args.field]
        cancel();state.route=idleRoute();target.selected,target.results=nil,{}
        target.query=text(args.query,2000);target.error=""
      end
    elseif action=="search" then search(args)
    elseif action=="select" and (args.field=="a" or args.field=="b") then
      local target=state[args.field]
      local index=finite(args.index)
      local selected=index and index%1==0 and place(target.results[index]) or nil
      if selected then
        cancel();state.route=idleRoute();target.selected=selected;target.query=selected.name
        target.results={};remember(selected);persist()
      end
    elseif action=="preview" then preview()
    elseif action=="randomPreview" then randomPreview()
    elseif action=="teleport" then
      if args.target=="a" then teleportA() end
    elseif action=="navigate" then
      detect()
      local selected=(args.target=="a" and state.a.selected) or (args.target=="b" and state.b.selected)
      if not state.canNavigate then state.error="Navigation requires a ready Earth vehicle and no active taxi shift"
      elseif not selected then state.error="Select a destination first"
      else
        local accepted,reason=api.gpsSet(selected.lat,selected.lon,selected.name)
        if not accepted then state.error=text(reason or "Earth did not accept the GPS destination",400) end
        updateGps()
      end
    end
    publish();return state
  end
  function service:update(dtReal)
    if destroyed then return end
    clock=clock+math.max(0,tonumber(dtReal) or 0)
    if opened and clock-lastOwnerSeen>10 then self:command("close",{owner=state.owner}) end
    if clock>=detectAt then
      detectAt=clock+1
      if detect() then publish() end
    end
    if transport then transport:update(dtReal) end
    if opened and clock>=gpsAt then gpsAt=clock+0.5;updateGps();publish() end
  end
  function service:destroy()
    if destroyed then return end
    cancel();if transport then transport:destroy() end
    destroyed=true
  end
  function service:stats()
    return {searchCache=#cacheOrder,history=#history,opened=opened,
      transport=transport and transport:stats() or nil}
  end
  return service
end
return M
