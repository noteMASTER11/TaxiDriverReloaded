-- Background stop addresses use their own Earth connection, independently of
-- route previews and the dispatcher. No address lookup delays a published offer.
local M={}
local QUEUE_MAX,CACHE_MAX,CACHE_TTL,LOOKUP_INTERVAL=24,128,600,3
local CELL_DEG=50/111320

local function finite(value)
  value=tonumber(value)
  if value and value==value and value~=math.huge and value~=-math.huge then return value end
end
local function clean(value,limit)
  if type(value)~="string" then return "" end
  value=value:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
  local cut=math.min(#value,limit or 200)
  while cut>0 and cut<#value do
    local b=value:byte(cut+1)
    if b<128 or b>191 then break end
    cut=cut-1
  end
  return value:sub(1,cut)
end
local function stopData(stop)
  local geo=type(stop)=="table" and stop.geo
  if type(geo)~="table" then return nil end
  local lat,lon=finite(geo.lat),finite(geo.lon)
  if not lat or not lon or math.abs(lat)>90 or math.abs(lon)>180 then return nil end
  local title=clean(stop.name)
  if title=="" then title=clean(geo.name) end
  return {lat=lat,lon=lon,name=title}
end
local function cell(point)
  local latCell=math.floor((point.lat+90)/CELL_DEG)
  local centerLat=(latCell+0.5)*CELL_DEG-90
  local lonStep=CELL_DEG/math.max(0.01,math.cos(math.rad(centerLat)))
  return tostring(latCell)..":"..tostring(math.floor((point.lon+180)/lonStep))
end
local function normalized(value)
  value=type(value)=="table" and value or {}
  local address=type(value.address)=="table" and value.address or {}
  local function first(...)
    for i=1,select("#",...) do
      local text=clean((select(i,...)))
      if text~="" then return text end
    end
    return ""
  end
  local function house(value)
    if type(value)=="number" and finite(value) then return tostring(value) end
    return clean(value,48)
  end
  return {houseNumber=first(house(value.house_number),house(value.houseNumber),house(address.house_number),house(address.houseNumber)),
    street=first(value.street,address.street,address.road),
    place=first(value.place,address.city,address.town,address.village,address.hamlet),
    region=first(value.region,address.state),country=first(value.country,address.country)}
end
local function defaultEndpoint()
  local ok,net=pcall(require,"beamngEarth/net")
  local core=rawget(_G,"beamngEarth_core")
  local hello
  if core and type(core.serverHello)=="function" then
    local success,value=pcall(core.serverHello)
    if success then hello=value end
  end
  return {port=ok and net.PORT or 47613,sessionId=hello and hello.sessionId or ""}
end

function M.new(options)
  options=options or {}
  local service={}
  local getEndpoint=options.getEndpoint or defaultEndpoint
  local createTransport=options.createTransport or function(args) return require("taxiDriver/earthTransport").new(args) end
  local queue,cache,cacheOrder={},{},{}
  local active,transport,endpointKey
  local destroyed,elapsed,nextAt,sequence=false,0,0,0
  local counters={requests=0,completed=0,cacheHits=0,dropped=0}
  local function now() return options.clock and options.clock() or elapsed end
  local function reset()
    active=nil;queue={}
    cache,cacheOrder={},{}
    if transport then transport:destroy();transport=nil end
  end
  local function endpoint()
    local ok,ep=pcall(getEndpoint)
    if type(ep)=="number" then ep={port=ep} end
    local port=ok and type(ep)=="table" and finite(ep.port or 47613)
    if not port or port<1 or port>65535 or port~=math.floor(port) then
      if endpointKey then reset();endpointKey=nil end
      return nil
    end
    local key=tostring(port)..":"..tostring(ep.sessionId or "")
    if key~=endpointKey then reset();endpointKey=key end
    return port
  end
  local function touch(key)
    for i=#cacheOrder,1,-1 do if cacheOrder[i]==key then table.remove(cacheOrder,i);break end end
    cacheOrder[#cacheOrder+1]=key
  end
  local function cached(key)
    local entry=cache[key]
    if not entry then return nil end
    local age=now()-entry.at
    if age<0 or age>=CACHE_TTL then
      cache[key]=nil
      for i=#cacheOrder,1,-1 do if cacheOrder[i]==key then table.remove(cacheOrder,i);break end end
      return nil
    end
    touch(key)
    return entry.fields
  end
  local function remember(key,fields)
    cache[key]={fields=fields,at=now()};touch(key)
    while #cacheOrder>CACHE_MAX do cache[table.remove(cacheOrder,1)]=nil end
  end
  local function deliver(job,fields,err)
    local result={lat=job.point.lat,lon=job.point.lon}
    for k,v in pairs(fields) do result[k]=v end
    result.source=(fields.street~="" or fields.place~="" or fields.houseNumber~="") and "earth_where" or "fallback"
    if err then result.error=clean(tostring(err)) end
    local parts={}
    if fields.houseNumber~="" then parts[#parts+1]=fields.houseNumber end
    if fields.street~="" then parts[#parts+1]=fields.street end
    local place=fields.place~="" and fields.place or job.point.name
    if place~="" and place~=parts[#parts] then parts[#parts+1]=place end
    counters.completed=counters.completed+1
    pcall(job.callback,table.concat(parts,", "),result)
  end
  function service:enqueue(stop,callback)
    if destroyed then return false,"destroyed" end
    local point=stopData(stop)
    if not point or type(callback)~="function" then return false,"invalid stop" end
    if not endpoint() then return false,"Earth endpoint unavailable" end
    local job={point=point,key=cell(point),callback=callback}
    local fields=cached(job.key)
    if fields then
      counters.cacheHits=counters.cacheHits+1;deliver(job,fields)
      return true
    end
    if #queue+(active and 1 or 0)>=QUEUE_MAX then counters.dropped=counters.dropped+1;return false,"queue full" end
    queue[#queue+1]=job
    return true
  end
  function service:update(dtReal)
    if destroyed then return end
    local delta=finite(dtReal)
    if delta and delta>0 then elapsed=elapsed+delta end
    local port=endpoint()
    if not port then return end
    if transport then transport:update(dtReal) end
    if active then return end
    -- Drain at most this queue's capacity, including callbacks that enqueue work.
    for _=1,QUEUE_MAX do
      local job=queue[1]
      if not job then return end
      local fields=cached(job.key)
      if fields then
        table.remove(queue,1)
        counters.cacheHits=counters.cacheHits+1;deliver(job,fields)
        if destroyed or active or not endpoint() then return end
      else
        if now()<nextAt then return end
        table.remove(queue,1)
        active=job;nextAt=now()+LOOKUP_INTERVAL
        if not transport then
          local ok,value=pcall(createTransport,{port=port,clock=options.clock})
          if not ok or not value then active=nil;deliver(job,normalized(),"Earth transport unavailable");return end
          transport=value
        end
        sequence=sequence+1;counters.requests=counters.requests+1
        local expectedEndpoint=endpointKey
        local function finish(result,err)
          if destroyed or active~=job then return end
          endpoint()
          if active~=job or endpointKey~=expectedEndpoint then return end
          active=nil
          local fields=normalized(result)
          if not err and (type(result)~="table" or result.type~="where_result") then err="invalid where response" end
          if not err then remember(job.key,fields) end
          deliver(job,fields,err)
        end
        local ok,accepted,err=pcall(function()
          return transport:request({type="where",id=sequence,lat=job.point.lat,lon=job.point.lon,online=true},finish)
        end)
        if not ok or not accepted then finish(nil,tostring(err or accepted or "Earth request failed")) end
        return
      end
    end
  end
  function service:cancel()
    active=nil;queue={}
    if transport then transport:cancel() end
  end
  function service:destroy()
    destroyed=true;reset();endpointKey=nil
  end
  function service:stats()
    local result={pending=active~=nil,queued=#queue,cacheEntries=#cacheOrder}
    for k,v in pairs(counters) do result[k]=v end
    return result
  end
  return service
end

return M
