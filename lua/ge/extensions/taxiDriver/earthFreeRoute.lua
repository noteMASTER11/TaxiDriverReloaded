-- Personal Earth GPS trips have no taxi order, passenger, payment or penalties.
local M={}
local function valid(p)
  return type(p)=='table' and type(p.lat)=='number' and type(p.lon)=='number' and
    p.lat==p.lat and p.lon==p.lon and math.abs(p.lat)<=90 and math.abs(p.lon)<=180
end
local function distance(a,b)
  local lat1,lat2=math.rad(a.lat),math.rad(b.lat)
  local x=math.sin((lat2-lat1)/2)^2+math.cos(lat1)*math.cos(lat2)*math.sin(math.rad(b.lon-a.lon)/2)^2
  return 12742017.6*math.asin(math.sqrt(math.min(1,x)))
end
local function same(a,b)
  return valid(a) and valid(b) and math.abs(a.lat-b.lat)<1e-7 and math.abs(a.lon-b.lon)<1e-7 and a.name==b.name
end
function M.new(options)
  options=options or {}
  local getApi=options.getApi or function()return rawget(_G,'beamngEarth_api')end
  local s={active=false,status='idle',leg='b',remainingM=0,distanceM=0,etaS=0,progress=0,name=''}
  local service,owner,target,route,mode,observed={},nil,nil,nil,nil,false
  local function setTarget(point)
    target={lat=point.lat,lon=point.lon,name=point.name or ''}
    if owner.gpsSet(target.lat,target.lon,target.name)~=true then return false end
    observed=false;s.name=target.name
    local pose=owner.pose()
    s.distanceM=s.leg=='b' and route.distanceM or (valid(pose) and distance(pose,target) or 0)
    s.remainingM=s.distanceM;s.etaS=s.leg=='b' and route.durationS or 0;s.progress=0
    return true
  end
  function service:snapshot()return s end
  function service:stop(status)
    if owner and target and getApi()==owner and owner.inWorld() and same(owner.gps(),target) then owner.gpsClear() end
    s.active=false;s.status=status or 'cancelled'
    owner,target,route,mode=nil,nil,nil,nil
  end
  function service:start(preview,routeMode)
    local api=getApi()
    if not api or not api.inWorld() or not api.ready() or type(api.gpsSet)~='function' or
      type(preview)~='table' or preview.status~='ready' or not valid(preview.to) or not valid(preview.from) then return false end
    local pose=api.pose()
    if not valid(pose) or pose.camera then return false end
    self:stop()
    owner,route,mode=api,preview,routeMode
    local a=preview.roadFrom or preview.from
    s.leg=mode=='points' and distance(pose,a)>25 and 'a' or 'b'
    s.active=true;s.status='driving'
    if not setTarget(s.leg=='a' and a or (preview.roadTo or preview.to)) then self:stop('error');return false end
    return true
  end
  function service:update()
    if not s.active then return end
    if getApi()~=owner or not owner.inWorld() then self:stop('cancelled');return end
    if not owner.ready() then return end
    local pose,gps=owner.pose(),owner.gps()
    if not valid(pose) or pose.camera then return end
    if gps and not same(gps,target) then self:stop('cancelled');return end
    local arrived=distance(pose,target)<=25 and type(pose.speed)=='number' and math.abs(pose.speed)<=1
    if same(gps,target) then
      observed=true
      if not gps.planning then
        if type(gps.remaining)=='number' and gps.remaining>=0 then s.remainingM=gps.remaining end
        if type(gps.eta)=='number' and gps.eta>=0 then s.etaS=gps.eta end
        s.distanceM=math.max(s.distanceM,s.remainingM)
        s.progress=s.distanceM>0 and math.max(0,math.min(1,1-s.remainingM/s.distanceM)) or 0
      end
    elseif observed and not arrived then self:stop('cancelled');return end
    if arrived then
      if s.leg=='a' then
        s.leg='b'
        if not setTarget(route.roadTo or route.to) then self:stop('error') end
      else
        s.remainingM=0;s.etaS=0;s.progress=1;self:stop('complete')
      end
    end
  end
  return service
end
return M
