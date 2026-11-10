package.path = "lua/ge/extensions/?.lua;" .. package.path
local found, candidates = pcall(require, "taxiDriver/earthCandidates")
assert(found and type(candidates.new) == "function", "Earth settlement candidate service is missing")

local function fixture(extra)
  local state={now=0,requests={},transports={},endpoint={port=47613,sessionId="a"}}
  local opts={clock=function() return state.now end,getEndpoint=function() return state.endpoint end,
    createTransport=function(args)
      local t={args=args,cancelled=0,destroyed=0,updates=0}
      state.transports[#state.transports+1]=t
      function t:request(msg,cb)
        state.requests[#state.requests+1]=msg; self.callback=cb; return true
      end
      function t:update() self.updates=self.updates+1 end
      function t:cancel() self.cancelled=self.cancelled+1 end
      function t:destroy() self.destroyed=self.destroyed+1 end
      return t
    end}
  for k,v in pairs(extra or {}) do opts[k]=v end
  state.service=candidates.new(opts)
  function state:answer(rows,err)
    local t=self.transports[#self.transports]
    t.callback(rows and {type="map_labels_result",id=self.requests[#self.requests].id,rows=rows} or nil,err)
  end
  return state
end
local function request(f,origin,km)
  local out={}
  assert(f.service:request(origin or {lat=0,lon=0},km or 25,function(result,err) out.rows=result;out.err=err end))
  return out
end
local function label(kind,name,lat,lon,extra)
  return {kind,name,lat,lon,9,99,38,extra or "",false}
end

-- Administrative labels, malformed coordinates, duplicates and towns outside the trip radius must be excluded.
do
  local f=fixture()
  local out=request(f)
  local msg=f.requests[1]
  assert(msg.type=="map_labels" and msg.lat==0 and msg.lon==0 and msg.zoom==12 and msg.radius==25000)
  f:answer({label("country","Country",0,0),label("region","Region",0,0),label("district","District",0,0),
    label("town","Village",0,0.1,"village"),label("city","City",0.15,0),
    label("town","Village",0,0.1,"village"),label("town","Distant",1,0,"town"),
    label("town","Invalid",91,0,"town"),label("town","",0.1,0,"town"),
    label("town","Nan",0/0,0,"town")})
  assert(not out.err and #out.rows==32)
  local village,city=out.rows[1],out.rows[2]
  assert(village.name=="Village" and village.kind=="village" and village.source=="earth_label")
  assert(village.distanceM>11119 and village.distanceM<11120 and city.name=="City")
  for i,row in ipairs(out.rows) do
    assert(row.distanceM>0 and row.distanceM<=25000 and row.lat>=-90 and row.lat<=90)
    if i>2 then assert(row.source=="radial") end
  end
end

-- A crowded local area must not push every far city out of the bounded Unlimited candidate pool.
do
  local f=fixture()
  local out=request(f,{lat=0,lon=0},600)
  local rows={}
  for i=1,220 do rows[#rows+1]=label("town","Local "..i,0,i*0.0005,"town") end
  rows[#rows+1]=label("city","Far City",0,4.5)
  rows[#rows+1]=label("city","Too far",0,6)
  f:answer(rows)
  local far=false
  assert(f.requests[1].radius==600000 and #out.rows==128)
  for _,row in ipairs(out.rows) do
    assert(row.source=="earth_label" and row.distanceM<=600000)
    if row.name=="Far City" then far=true;assert(row.distanceM>500000) end
  end
  assert(far,"Unlimited pool must keep far settlements alongside local ones")
  assert(f.service:stats().candidateCount<=128)
end

-- Cache hits reuse nearby labels but recompute distance from the moving car; radius and expiry invalidate the hit.
do
  local f=fixture()
  local first=request(f)
  f:answer({label("city","City",0,0.1)})
  first.rows[1].name="Mutated caller copy"
  f.now=599
  local nextResult=request(f,{lat=0,lon=0.001})
  assert(#f.requests==1 and nextResult.rows[1].name=="City")
  assert(nextResult.rows[1].distanceM>11008 and nextResult.rows[1].distanceM<11009)
  f.now=600
  request(f,{lat=0,lon=0.001})
  assert(#f.requests==2,"ten-minute cache must expire")
  f:answer({label("city","City",0,0.1)})
  request(f,{lat=0,lon=0.001},600)
  assert(#f.requests==3,"a local search cannot satisfy an Unlimited request")
end

-- Empty or failed label lookups still expose explicitly marked radial seeds, including long distances.
for _,err in ipairs({false,"connect failed"}) do
  local f=fixture()
  local out=request(f,{lat=80,lon=179.8},600)
  if err then f:answer(nil,err) else f:answer({}) end
  assert(#out.rows==32 and out.err==(err or nil))
  local far,near=false,false
  for _,row in ipairs(out.rows) do
    assert(row.source=="radial" and row.kind=="radial" and row.name~="")
    assert(row.lat>=-90 and row.lat<=90 and row.lon>=-180 and row.lon<=180)
    assert(row.distanceM>0 and row.distanceM<=600000)
    if row.distanceM>300000 then far=true end
    if row.distanceM<25000 then near=true end
  end
  assert(far and near,"Unlimited fallback must cover both nearby and far destinations")
end

-- Great-circle filtering must understand the antimeridian instead of treating nearby towns as 360 degrees away.
do
  local f=fixture()
  local out=request(f,{lat=0,lon=179.95},25)
  f:answer({label("town","Across date line",0,-179.95,"town")})
  assert(out.rows[1].name=="Across date line" and out.rows[1].distanceM<11120)
end

-- Cancel/destroy suppress late callbacks, and a new Earth session must not reuse an old label cache.
do
  local f=fixture()
  local cancelled=request(f)
  local old=f.transports[1]
  f.service:cancel(); f:answer({label("city","Old",0,0.1)})
  assert(not cancelled.rows and old.cancelled>0)
  local fresh=request(f)
  f.service:update(0.1)
  assert(old.updates==1)
  f:answer({label("city","Fresh",0,0.1)})
  assert(fresh.rows[1].name=="Fresh")
  f.endpoint={port=47614,sessionId="b"}
  local changed=request(f)
  assert(#f.requests==3 and old.destroyed==1 and f.transports[2].args.port==47614)
  f.service:destroy(); f:answer({label("city","Late",0,0.1)})
  assert(not changed.rows and f.transports[2].destroyed==1)
  local ok,err=f.service:request({lat=0,lon=0},25,function() end)
  assert(not ok and err=="destroyed")
end

-- Invalid origins cannot create Earth requests; maximum search size is clamped before talking to Earth.
do
  local f=fixture()
  for _,origin in ipairs({{}, {lat=91,lon=0},{lat=0,lon=181},{lat=0/0,lon=0}}) do
    local ok=f.service:request(origin,25,function() end)
    assert(not ok and #f.requests==0)
  end
  request(f,{lat=0,lon=0},99999)
  assert(f.requests[1].radius==600000)
end

print("TaxiDriver Earth settlement candidates regressions passed")
