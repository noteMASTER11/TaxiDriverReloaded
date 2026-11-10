-- Geographic taxi stops remain authoritative across BeamNG.Earth origin rebases.
-- Uses only the public Earth API; distant targets never enter the local route graph.
local M = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function validGeo(p)
  return type(p)=="table" and finite(p.lat) and finite(p.lon) and
    math.abs(p.lat)<=90 and math.abs(p.lon)<=180
end
local function call(object, name, ...)
  if not object or type(object[name])~="function" then return nil end
  local ok,a,b,c=pcall(object[name], ...)
  if ok then return a,b,c end
end
local function vector(x,y,z)
  if type(vec3)=="function" then return vec3(x,y,z) end
  return {x=x,y=y,z=z}
end
local function distance(a,b)
  if not validGeo(a) or not validGeo(b) then return nil end
  local lat=math.rad(b.lat-a.lat)
  local lon=math.rad(b.lon-a.lon)
  local h=math.sin(lat/2)^2+math.cos(math.rad(a.lat))*math.cos(math.rad(b.lat))*math.sin(lon/2)^2
  return 12742000*math.asin(math.sqrt(math.max(0,math.min(1,h))))
end
local function sameGeo(a,b)
  return validGeo(a) and validGeo(b) and math.abs(a.lat-b.lat)<1e-7 and math.abs(a.lon-b.lon)<1e-7
end

-- Closest point on a road segment, with a horizontal matching radius. Terrain
-- can be absent under Earth meshes, so a nearby road supplies height first.
local function roadAt(pos)
  local mapApi=rawget(_G,"map")
  local a,b=call(mapApi,"findClosestRoad",pos)
  local data=call(mapApi,"getMap")
  local nodes=data and data.nodes
  a,b=nodes and nodes[a],nodes and nodes[b]
  a,b=a and a.pos,b and b.pos
  if not a or not b or not finite(a.x) or not finite(a.y) or not finite(a.z) or
    not finite(b.x) or not finite(b.y) or not finite(b.z) then return nil end
  local dx,dy=b.x-a.x,b.y-a.y
  local length=dx*dx+dy*dy
  local t=length>0 and math.max(0,math.min(1,((pos.x-a.x)*dx+(pos.y-a.y)*dy)/length)) or 0
  return vector(a.x+t*dx,a.y+t*dy,a.z+t*(b.z-a.z))
end

function M.new(options)
  options=options or {}
  local service={}
  local anchor,anchorLat,anchorLon,owned,ownedApi
  local stopAnchors=setmetatable({},{__mode="k"})
  local localRadius=finite(options.localRadius) and math.max(0,options.localRadius) or 5000
  local roadRadius=finite(options.roadRadius) and math.max(0,options.roadRadius) or 60
  local function getApi()
    if options.getApi then local ok,a=pcall(options.getApi);if ok then return a end;return nil end
    return rawget(_G,"beamngEarth_api")
  end
  local function activeApi()
    local api=getApi()
    if call(api,"connected")==true and call(api,"inWorld")==true then return api end
  end
  local function frame(p)
    if not p or not finite(p.anchorLat) or not finite(p.anchorLon) or
      math.abs(p.anchorLat)>90 or math.abs(p.anchorLon)>180 then return nil end
    if anchor and anchorLat==p.anchorLat and anchorLon==p.anchorLon then return anchor end
    -- Do not retain the former frame if the new anchor cannot be constructed.
    anchor,anchorLat,anchorLon=nil,nil,nil
    local ok,g
    if options.getGeodesy then ok,g=pcall(options.getGeodesy)
    else ok,g=pcall(require,"beamngEarth/geodesy") end
    if not ok or type(g)~="table" or type(g.newAnchor)~="function" then return nil end
    ok,g=pcall(g.newAnchor,p.anchorLat,p.anchorLon)
    if not ok or type(g)~="table" then return nil end
    anchor,anchorLat,anchorLon=g,p.anchorLat,p.anchorLon
    return anchor
  end
  local function matchingGps(api,geo,name)
    local gps=call(api,"gps")
    if sameGeo(gps,geo) and (name==nil or gps.name==name) then return gps end
  end
  function service:active() return activeApi()~=nil end
  function service:pose()
    local p=call(activeApi(),"pose")
    if validGeo(p) and p.camera~=true then return p end
  end
  function service:toGeo(pos)
    if not pos or not finite(pos.x) or not finite(pos.y) or not finite(pos.z) then return nil end
    local a=frame(self:pose())
    if not a or type(a.worldToGeodetic)~="function" then return nil end
    local ok,lat,lon,alt=pcall(a.worldToGeodetic,a,pos.x,pos.y,pos.z)
    local geo={lat=lat,lon=lon,alt=alt}
    if ok and validGeo(geo) and finite(alt) then return geo end
  end
  function service:ready()
    local api=activeApi()
    return api~=nil and call(api,"ready")==true
  end
  function service:distanceTo(stop) return distance(self:pose(),stop and stop.geo) end
  function service:project(stop)
    if type(stop)~="table" then return nil end
    local p=self:pose()
    local a=frame(p)
    local geo=stop.geo
    local d=distance(p,geo)
    stop.earthDistance,stop.earthLocal=d,false
    if not a or not validGeo(geo) or type(a.geodeticToWorld)~="function" then stop.pos=nil;return nil end
    local ok,x,y,z=pcall(a.geodeticToWorld,a,geo.lat,geo.lon,finite(geo.alt) and geo.alt or 0)
    if not ok or not finite(x) or not finite(y) or not finite(z) then stop.pos=nil;return nil end
    local pos=vector(x,y,z)
    stop.earthLocal=d~=nil and d<=localRadius
    if not finite(geo.alt) and stop.earthLocal then
      local roadOk,road=pcall(options.findRoad or roadAt,pos)
      if roadOk and road and finite(road.x) and finite(road.y) and finite(road.z) and
        (road.x-x)^2+(road.y-y)^2<=roadRadius^2 then
        pos.z=road.z
      else
        local height
        if options.groundHeight then
          local heightOk,value=pcall(options.groundHeight,pos)
          if heightOk then height=value end
        else height=call(rawget(_G,"core_terrain"),"getTerrainHeight",pos) end
        if finite(height) then pos.z=height end
      end
    end
    local old=stopAnchors[stop]
    if old and old~=a and stop.dir and type(old.transformTo)=="function" then
      local transformed,t=pcall(old.transformTo,old,a)
      if transformed and t and type(t.rotate)=="function" then
        local rotated,dx,dy,dz=pcall(t.rotate,t,stop.dir.x,stop.dir.y,stop.dir.z)
        if rotated and finite(dx) and finite(dy) and finite(dz) then stop.dir=vector(dx,dy,dz) end
      end
    end
    stopAnchors[stop]=a
    stop.pos=pos
    return pos
  end
  function service:refreshOffer(offer)
    if type(offer)~="table" or not offer.earth then return false end
    local seen={}
    local function project(stop)
      if type(stop)=="table" and not seen[stop] then seen[stop]=true;self:project(stop) end
    end
    project(offer.pickup)
    for _,stop in ipairs(offer.stops or {}) do project(stop) end
    project(offer.destination)
    return true
  end
  function service:arrived(stop,radius,maxSpeed)
    local p=self:pose()
    local d=distance(p,stop and stop.geo)
    return d~=nil and finite(radius) and radius>=0 and d<=radius and
      finite(p.speed) and math.abs(p.speed)<=(finite(maxSpeed) and math.max(0,maxSpeed) or 1)
  end
  function service:setTarget(stop)
    local api=activeApi()
    local geo=stop and stop.geo
    if not api or not validGeo(geo) then return false end
    -- Once the target was accepted, frame updates must not restart planning or
    -- take the GPS back after the player changes it manually.
    if ownedApi==api and sameGeo(owned,geo) then return true end
    local name=type(stop.name)=="string" and stop.name or "Taxi"
    if call(api,"gpsSet",geo.lat,geo.lon,name)~=true then return false end
    owned,ownedApi={lat=geo.lat,lon=geo.lon,name=name},api
    return true
  end
  function service:clearTarget()
    local api=getApi()
    if owned and api==ownedApi and matchingGps(api,owned,owned.name) then call(api,"gpsClear") end
    owned,ownedApi=nil,nil
  end
  function service:remaining(stop)
    local geo=stop and stop.geo
    local api=activeApi()
    local gps=api and matchingGps(api,geo)
    if gps and gps.planning==true then return nil end
    if gps and gps.planning~=true and finite(gps.remaining) and gps.remaining>=0 then return gps.remaining end
    return self:distanceTo(stop)
  end
  function service:eta(stop)
    local api=activeApi()
    local gps=api and matchingGps(api,stop and stop.geo)
    if gps and gps.planning~=true and finite(gps.eta) and gps.eta>=0 then return gps.eta end
  end
  function service:reset()
    self:clearTarget()
    anchor,anchorLat,anchorLon=nil,nil,nil
    stopAnchors=setmetatable({},{__mode="k"})
  end
  return service
end

return M
