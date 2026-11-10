package.path="lua/ge/extensions/?.lua;"..package.path
local found,addresses=pcall(require,"taxiDriver/earthAddresses")
assert(found and type(addresses.new)=="function","Earth address enrichment service is missing")

local function fixture()
  local f={now=0,endpoint={port=47613,sessionId="a"},requests={},transports={}}
  f.service=addresses.new({clock=function() return f.now end,getEndpoint=function() return f.endpoint end,
    createTransport=function(args)
      local t={args=args,cancelled=0,destroyed=0,updates=0}
      f.transports[#f.transports+1]=t
      function t:request(msg,callback)
        self.callback=callback;f.requests[#f.requests+1]=msg
        return true
      end
      function t:update() self.updates=self.updates+1 end
      function t:cancel() self.cancelled=self.cancelled+1 end
      function t:destroy() self.destroyed=self.destroyed+1 end
      return t
    end})
  function f:advance(seconds) self.now=self.now+seconds;self.service:update(seconds) end
  function f:answer(fields,err)
    fields=fields or {}
    fields.type,fields.id="where_result",self.requests[#self.requests].id
    self.transports[#self.transports].callback(fields,err)
  end
  return f
end
local function stop(lon,title)
  return {name=title or "Fallback city",geo={lat=45.0347,lon=lon or 38.9771}}
end
local function enqueue(f,destination)
  local out={count=0}
  assert(f.service:enqueue(destination or stop(),function(address,fields)
    out.address,out.fields,out.count=address,fields,out.count+1
  end))
  return out
end

-- Address lookups must start from update, never while the dispatcher publishes a new offer.
do
  local f=fixture()
  local first=enqueue(f)
  local second=enqueue(f,stop(39.1))
  assert(#f.requests==0 and not first.address and f.service:stats().queued==2)
  f:advance(0)
  local msg=f.requests[1]
  assert(msg.type=="where" and msg.online==true and msg.lat==45.0347 and msg.lon==38.9771)
  f:answer({street="Main Street",place="Krasnodar",region="Krasnodar region",country="Russia"})
  assert(first.address=="Main Street, Krasnodar" and first.fields.street=="Main Street" and first.count==1)
  f:advance(2.99);assert(#f.requests==1 and not second.address)
  f:advance(0.01);assert(#f.requests==2)
  f:answer({street="Next Street",place="Next town"})
  assert(second.address=="Next Street, Next town")
end

-- House numbers may only appear when explicitly returned by Earth; support its common field spellings.
for _,fields in ipairs({
  {house_number="12А",street="  Main   Street ",place="Krasnodar"},
  {houseNumber="12А",street="Main Street",place="Krasnodar"},
  {address={house_number="12А",road="Main Street",city="Krasnodar"}},
  {house_number="",houseNumber="12А",street="",place="",address={road="Main Street",city="Krasnodar"}}
}) do
  local f=fixture()
  local out=enqueue(f)
  f:advance(0);f:answer(fields)
  assert(out.address=="12А, Main Street, Krasnodar" and out.fields.houseNumber=="12А")
end

-- A missing street must retain real place information or the existing stop name, without invented numbers.
for _,case in ipairs({
  {response={place="Krasnodar",street=""},want="Krasnodar"},
  {response={street="Main Street"},want="Main Street, Fallback city"},
  {response={region="Region",country="Country"},want="Fallback city"},
  {response={},want="Fallback city"}
}) do
  local f=fixture();local out=enqueue(f)
  f:advance(0);f:answer(case.response)
  assert(out.address==case.want and out.fields.houseNumber=="")
end

-- Cache snapshots are independent of callers, expire after ten minutes, and share only nearby coordinate cells.
do
  local f=fixture();local first=enqueue(f)
  f:advance(0);f:answer({street="Cached Street",place="City"})
  first.fields.street="Caller mutation"
  f:advance(599)
  local hit=enqueue(f)
  assert(hit.address=="Cached Street, City" and #f.requests==1)
  f:advance(1)
  local expired=enqueue(f)
  assert(not expired.address)
  f:advance(0);assert(#f.requests==2)
  f:answer({place="Fresh city"})
  assert(expired.address=="Fresh city")
end

-- The work queue is bounded, including its in-flight request, so a burst of orders cannot grow it indefinitely.
do
  local f=fixture()
  for i=1,24 do enqueue(f,stop(39+i*0.001)) end
  local ok,err=f.service:enqueue(stop(40),function() error("overflow callback") end)
  assert(not ok and err=="queue full" and f.service:stats().queued==24)
  f:advance(0)
  assert(f.service:stats().queued==23 and f.service:stats().pending)
  ok,err=f.service:enqueue(stop(40),function() error("overflow callback") end)
  assert(not ok and err=="queue full")
end

-- Cancelling or replacing the Earth session must suppress responses already in flight.
do
  local f=fixture();local old=enqueue(f)
  f:advance(0)
  local oldCallback=f.transports[1].callback
  f.service:cancel()
  local fresh=enqueue(f,stop(39))
  f:advance(3)
  oldCallback({type="where_result",id=1,street="Stale",place="Old"})
  assert(not old.address and not fresh.address)
  f:answer({place="Fresh"});assert(fresh.address=="Fresh")
  f:advance(3)
  local sessionOld=enqueue(f,stop(39.1));f:advance(0)
  local sessionCallback=f.transports[1].callback
  f.endpoint={port=47614,sessionId="b"}
  f:advance(0)
  sessionCallback({type="where_result",id=3,street="Stale session",place="Old"})
  assert(not sessionOld.address and f.transports[1].destroyed==1)
  local nextSession=enqueue(f,stop(39.1));f:advance(3)
  assert(f.transports[2].args.port==47614)
  f:answer({place="New session"});assert(nextSession.address=="New session")
  f.service:destroy()
  local ok,err=f.service:enqueue(stop(),function() end)
  assert(not ok and err=="destroyed")
end

-- Cache eviction must hold memory to 128 addresses, while transient lookup errors still release the queue.
do
  local f=fixture()
  for i=1,130 do
    local out=enqueue(f,stop(39+i*0.001))
    f:advance(i==1 and 0 or 3)
    f:answer({street="Street "..i,place="City"})
    assert(out.address=="Street "..i..", City")
  end
  assert(f.service:stats().cacheEntries==128)
  local evicted=enqueue(f,stop(39.001));f:advance(3)
  assert(not evicted.address and #f.requests==131)
  f:answer({},"connection closed")
  assert(evicted.address=="Fallback city" and evicted.fields.error=="connection closed")
  local nextJob=enqueue(f,stop(40));f:advance(3);f:answer({place="Next"})
  assert(nextJob.address=="Next" and not f.service:stats().pending)
end

-- Invalid or non-Earth stops must not enter the background work queue.
do
  local f=fixture()
  for _,s in ipairs({{}, {geo={lat=91,lon=0}},{geo={lat=0,lon=181}},{geo={lat=0/0,lon=0}}}) do
    local ok=f.service:enqueue(s,function() end)
    assert(not ok and f.service:stats().queued==0)
  end
end

print("TaxiDriver Earth address enrichment regressions passed")
