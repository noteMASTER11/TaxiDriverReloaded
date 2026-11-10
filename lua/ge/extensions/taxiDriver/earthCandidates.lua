-- Settlement discovery on an isolated request-only Earth connection. Zoom 12 reads
-- Natural Earth and cached localities without requesting road/POI cells.
local M = {}
local EARTH_M, MAX_CANDIDATES, CACHE_SECONDS = 6371008.8, 128, 600
local MAX_ROWS, MIN_POOL = 4096, 32
local settlementKinds = {megacity=true,city=true,town=true,village=true,hamlet=true,locality=true}

local function finite(value)
  value=tonumber(value)
  if value and value==value and value~=math.huge and value~=-math.huge then return value end
end
local function place(value)
  if type(value)~="table" then return nil end
  local lat,lon=finite(value.lat),finite(value.lon)
  if lat and lon and lat>=-90 and lat<=90 and lon>=-180 and lon<=180 then return {lat=lat,lon=lon} end
end
local function name(value)
  if type(value)~="string" then return "" end
  value=value:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
  local cut=math.min(#value,160)
  while cut>0 and cut<#value do
    local b=value:byte(cut+1)
    if b<128 or b>191 then break end
    cut=cut-1
  end
  return value:sub(1,cut)
end
local function distance(a,b)
  local lat1,lat2=math.rad(a.lat),math.rad(b.lat)
  local dlat,dlon=lat2-lat1,math.rad(b.lon-a.lon)
  local h=math.sin(dlat/2)^2+math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)^2
  return 2*EARTH_M*math.asin(math.sqrt(math.min(1,math.max(0,h))))
end
local function radial(origin,meters,bearing)
  local lat,lon=math.rad(origin.lat),math.rad(origin.lon)
  local d=meters/EARTH_M
  local destLat=math.asin(math.sin(lat)*math.cos(d)+math.cos(lat)*math.sin(d)*math.cos(bearing))
  local y,x=math.sin(bearing)*math.sin(d)*math.cos(lat),math.cos(d)-math.sin(lat)*math.sin(destLat)
  local destLon=lon+(math.atan2 and math.atan2(y,x) or math.atan(y,x))
  return {lat=math.deg(destLat),lon=(math.deg(destLon)+540)%360-180}
end
local function copy(row,origin)
  return {name=row.name,lat=row.lat,lon=row.lon,kind=row.kind,source=row.source,distanceM=distance(origin,row)}
end
local function ringBounds(radius)
  if radius>100000 then return {25000,100000,math.max(100000,radius*0.5),radius} end
  return {radius*0.25,radius*0.5,radius*0.75,radius}
end
local function bounded(rows,origin,radius)
  local buckets,bounds,seen={{},{},{},{}},ringBounds(radius),{}
  for index=1,math.min(#rows,MAX_ROWS) do
    local row=rows[index]
    if type(row)=="table" then
      local kind=row[1]
      local point=place({lat=row[3],lon=row[4]})
      local title=name(row[2])
      if settlementKinds[kind] and point and title~="" then
        local d=distance(origin,point)
        local key=title:lower()..":"..string.format("%.4f:%.4f",point.lat,point.lon)
        if d>0 and d<=radius and not seen[key] then
          seen[key]=true
          if kind=="town" and settlementKinds[row[8]] then kind=row[8] end
          local candidate={name=title,lat=point.lat,lon=point.lon,kind=kind,distanceM=d,source="earth_label"}
          for i=1,4 do
            if d<=bounds[i] then
              local bucket=buckets[i]
              -- Keep only the nearest 128 in any ring, even for oversized responses.
              local at=#bucket+1
              while at>1 and bucket[at-1].distanceM>d do at=at-1 end
              if at<=MAX_CANDIDATES then
                table.insert(bucket,at,candidate)
                if #bucket>MAX_CANDIDATES then table.remove(bucket) end
              end
              break
            end
          end
        end
      end
    end
  end
  local result,positions={}, {1,1,1,1}
  while #result<MAX_CANDIDATES do
    local added=false
    for i=1,4 do
      local candidate=buckets[i][positions[i]]
      if candidate and #result<MAX_CANDIDATES then
        result[#result+1]=candidate;positions[i]=positions[i]+1;added=true
      end
    end
    if not added then break end
  end
  -- Real local settlements lead the pool, while the allocation above reserves far cities.
  table.sort(result,function(a,b)
    if a.distanceM==b.distanceM then return a.name<b.name end
    return a.distanceM<b.distanceM
  end)
  return result
end
local function pool(rows,origin,radius)
  local result={}
  for _,row in ipairs(rows) do
    local candidate=copy(row,origin)
    if candidate.distanceM>0 and candidate.distanceM<=radius then result[#result+1]=candidate end
  end
  table.sort(result,function(a,b) return a.distanceM<b.distanceM end)
  local needed=MIN_POOL-#result
  for i=1,needed do
    -- Four rings cover local, medium and long trips; the outer ring stops inside the requested radius.
    local ring=(i-1)%4+1
    local meters=({math.min(radius*0.06,15000),math.min(radius*0.22,75000),radius*0.55,radius*0.92})[ring]
    local point=radial(origin,meters,(i-1)*2.399963229728653)
    point.name="Earth "..tostring(math.floor(meters/1000+0.5)).." km "..i
    point.kind,point.source,point.distanceM="radial","radial",distance(origin,point)
    result[#result+1]=point
  end
  return result
end
local function endpoint()
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
  local service,active,transport,transportKey,cache={},nil,nil,nil,nil
  local destroyed,elapsed,sequence=false,0,0
  local counters={requests=0,cacheHits=0,candidateCount=0,scannedRows=0}
  local getEndpoint=options.getEndpoint or endpoint
  local createTransport=options.createTransport or function(args) return require("taxiDriver/earthTransport").new(args) end
  local function now() return options.clock and options.clock() or elapsed end
  local function deliver(op,rows,err)
    if active~=op or destroyed then return end
    active=nil
    local result=pool(rows,op.origin,op.radius)
    counters.candidateCount=#result
    pcall(op.callback,result,err)
  end
  function service:request(origin,maxKm,callback)
    if destroyed then return false,"destroyed" end
    if active then return false,"busy" end
    origin=place(origin)
    if not origin or type(callback)~="function" then return false,"invalid request" end
    local radius=math.max(1,math.min(600,finite(maxKm) or 25))*1000
    local gotEndpoint,ep=pcall(getEndpoint)
    if not gotEndpoint then return false,"Earth endpoint unavailable" end
    if type(ep)=="number" then ep={port=ep} end
    if type(ep)~="table" then return false,"Earth endpoint unavailable" end
    local port=finite(ep.port) or 47613
    if port<1 or port>65535 or port~=math.floor(port) then return false,"invalid port" end
    local epKey=tostring(port)..":"..tostring(ep.sessionId or "")
    if epKey~=transportKey then
      if transport then transport:destroy() end
      transport=nil;cache=nil;transportKey=epKey
    end
    local key=string.format("%d:%d:%.3f",math.floor(origin.lat/0.02),math.floor(origin.lon/0.02),radius)
    local op={origin=origin,radius=radius,callback=callback}
    active=op
    if cache and cache.key==key and now()-cache.at>=0 and now()-cache.at<CACHE_SECONDS then
      counters.cacheHits=counters.cacheHits+1
      deliver(op,cache.rows,nil)
      return true
    end
    if not transport then
      local ok,value=pcall(createTransport,{port=port,clock=options.clock})
      if not ok or not value then deliver(op,{},"Earth transport unavailable");return true end
      transport=value
    end
    sequence=sequence+1
    counters.requests=counters.requests+1
    local ok,accepted,err=pcall(function()
      return transport:request({type="map_labels",id=sequence,lat=origin.lat,lon=origin.lon,zoom=12,radius=radius},
        function(result,failure)
          if active~=op or destroyed then return end
          local rows={}
          if not failure and type(result)=="table" and type(result.rows)=="table" then
            counters.scannedRows=counters.scannedRows+math.min(#result.rows,MAX_ROWS)
            rows=bounded(result.rows,origin,radius)
            cache={key=key,at=now(),rows=rows}
          elseif not failure then failure="invalid map labels response" end
          deliver(op,rows,failure)
        end)
    end)
    if not ok or not accepted then deliver(op,{},tostring(err or accepted or "Earth request failed")) end
    return true
  end
  function service:update(dtReal)
    local delta=finite(dtReal)
    if delta and delta>0 then elapsed=elapsed+delta end
    if transport and not destroyed then transport:update(dtReal) end
  end
  function service:cancel()
    active=nil
    if transport then transport:cancel() end
  end
  function service:destroy()
    active=nil;destroyed=true;cache=nil
    if transport then transport:destroy();transport=nil end
  end
  function service:stats()
    local result={pending=active~=nil}
    for k,v in pairs(counters) do result[k]=v end
    return result
  end
  return service
end

return M
