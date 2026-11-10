package.path = "lua/ge/extensions/?.lua;" .. package.path
local transport = require("taxiDriver/earthTransport")

local function frame(body)
  local n = #body
  return string.char(n % 256, math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) .. body
end
local payloads = {
  result = {type="route_result", id=7, points={{lat=41,lon=44}}},
  other = {type="route_result", id=99},
  status = {type="status", ready=true},
  geocode = {type="geocode_result", id=8, results={{lat=41,lon=44}}}
}
local function socketFixture(options)
  options = options or {}
  local sock = {incoming={}, sent="", calls=0, closed=0, connects=0}
  function sock:settimeout(t) assert(t == 0); return 1 end
  function sock:connect(host, port)
    assert(host == "127.0.0.1" and port == 47613)
    self.connects = self.connects + 1
    if options.connect then return options.connect(self) end
    return 1
  end
  function sock:send(data, start)
    local last = #data
    if options.writeLimit then last = math.min(last, start + options.writeLimit - 1) end
    self.sent = self.sent .. data:sub(start, last)
    if last < #data then return nil, "timeout", last end
    return last
  end
  function sock:receive(n)
    self.calls = self.calls + 1
    assert(n <= 8192, "reads must use small chunks")
    local item = table.remove(self.incoming, 1)
    if not item then return nil, "timeout", "" end
    local data = item.data or item
    assert(#data <= n)
    if type(item) == "table" then return nil, item.err, data end
    return data
  end
  function sock:close() self.closed = self.closed + 1 end
  return sock
end
local function service(sockets, extra)
  local i = 0
  local opts = {socket={tcp=function() i=i+1; return assert(sockets[i]) end},
    encode=function() return '{"type":"route","id":7,"download":"off"}' end,
    decode=function(s) if s == "bad" then error("bad JSON") end; return payloads[s] end}
  for k,v in pairs(extra or {}) do opts[k]=v end
  return transport.new(opts)
end
local request = {type="route",id=7,download="off"}

-- Settlement discovery must use the same isolated request-only protocol.
do
  local s, got = socketFixture(), nil
  payloads.labels = {type="map_labels_result",id=9,rows={{"town","Local",41,44,9,99,38,"town"}}}
  local encoded = '{"type":"map_labels","id":9,"lat":41,"lon":44,"zoom":12,"radius":600000}'
  local t = service({s},{encode=function(message)
    assert(message.type == "map_labels" and message.zoom == 12 and message.radius == 600000)
    return encoded
  end})
  s.incoming={frame("labels")}
  assert(t:request({type="map_labels",id=9,lat=41,lon=44,zoom=12,radius=600000},function(result,err)
    assert(not err); got=result
  end), "map_labels must be an accepted request")
  t:update(0.01)
  assert(got == payloads.labels and s.sent == frame(encoded) and s.closed == 1)
end

-- Reverse address requests remain isolated and preserve their own request id.
do
  local s,got=socketFixture(),nil
  payloads.where={type="where_result",id=10,street="Main Street",place="Town",region="Region",country="Country"}
  local encoded='{"type":"where","id":10,"lat":45.0347,"lon":38.9771,"online":true}'
  local t=service({s},{encode=function(message)
    assert(message.type=="where" and message.online==true and message.id==10)
    return encoded
  end})
  s.incoming={frame("where")}
  assert(t:request({type="where",id=10,lat=45.0347,lon=38.9771,online=true},function(result,err)
    assert(not err);got=result
  end),"where must be an accepted request")
  t:update(0.01)
  assert(got==payloads.where and s.sent==frame(encoded) and s.closed==1)
end

-- Dropping partial bytes or accepting an unrelated id must not complete a request.
do
  local s = socketFixture()
  local t, got, count = service({s}), nil, 0
  assert(t:request(request, function(result, err) assert(not err); got=result; count=count+1 end))
  local ok, err = t:request(request, function() error("busy callback") end)
  assert(not ok and err == "busy")
  s.incoming = {frame("status") .. frame("other") .. frame("result"):sub(1,2)}
  t:update(0.01)
  assert(not got and t:busy())
  s.incoming = {{data=frame("result"):sub(3),err="closed"}}
  t:update(0.01)
  assert(got == payloads.result and count == 1 and not t:busy() and s.closed == 1)
  assert(s.sent == frame('{"type":"route","id":7,"download":"off"}'), "only the requested message may be sent")
  t:update(1)
  assert(count == 1)
end

-- A stalled nonblocking connect must terminate, rather than occupying the service forever.
do
  local s = socketFixture({connect=function() return nil,"timeout" end})
  local t, count, reason = service({s}), 0, nil
  assert(t:request(request, function(result, err) assert(not result); reason=err; count=count+1 end))
  t:update(2.9); assert(t:busy())
  t:update(0.11)
  assert(not t:busy() and count == 1 and reason == "connect timeout" and s.closed == 1)
end

-- A connected peer which never answers has a total request deadline.
do
  local s, now = socketFixture(), 10
  local t, reason = service({s}, {clock=function() return now end}), nil
  assert(t:request(request, function(_, err) reason=err end))
  t:update(0)
  now=69.9; t:update(0); assert(t:busy())
  now=70; t:update(0)
  assert(not t:busy() and reason == "request timeout" and s.closed == 1)
end

-- Pending Windows connects may finish with the "already connected" response.
do
  local s=socketFixture({connect=function(sock)
    if sock.connects == 1 then return nil,"Operation already in progress" end
    return nil,"already connected"
  end})
  local t,got=service({s}),false
  s.incoming={frame("result")}
  assert(t:request(request,function() got=true end))
  t:update(0.01); assert(t:busy() and not got and s.sent == "")
  t:update(0.01); assert(got and not t:busy())
end

-- LuaSocket reports an absolute last-byte index on partial writes.
do
  local s = socketFixture({writeLimit=3})
  local t, got = service({s}), nil
  s.incoming = {frame("result")}
  assert(t:request(request, function(result) got=result end))
  for _=1,50 do t:update(0.01) end
  assert(got == payloads.result)
  assert(s.sent == frame('{"type":"route","id":7,"download":"off"}'))
end

-- Fragments may split every byte of the header and body, across many updates.
do
  local s, got=socketFixture(),false
  local t=service({s})
  assert(t:request(request,function() got=true end))
  local bytes=frame("result")
  for i=1,#bytes do
    s.incoming={{data=bytes:sub(i,i),err="timeout"}}
    t:update(0.01)
    assert(got == (i == #bytes))
  end
end

-- Oversized headers and invalid JSON must fail once without retaining a connection.
for _,body in ipairs({string.char(1,0,16,0), frame("bad"), frame("unknown")}) do
  local s, count, reason = socketFixture(), 0, nil
  local t = service({s})
  s.incoming = {body}
  assert(t:request(request, function(_, err) reason=err; count=count+1 end))
  t:update(0.01); t:update(0.01)
  assert(not t:busy() and reason and count == 1 and s.closed == 1)
end

-- Closed streams with an incomplete header must fail immediately, after draining valid frames.
do
  local s, reason = socketFixture(), nil
  local t = service({s})
  s.incoming = {{data=string.rep(frame("status"),8) .. string.char(6,0),err="closed"}}
  assert(t:request(request, function(_,err) reason=err end))
  t:update(0.01); assert(t:busy())
  t:update(0.01)
  assert(not t:busy() and reason == "receive failed: closed" and s.closed == 1)
end

-- Raising the configurable frame limit must not remove the 1 MiB ceiling.
do
  local s, reason = socketFixture(), nil
  local t = service({s}, {maxFrameBytes=2097152})
  s.incoming = {string.char(1,0,16,0)}
  assert(t:request(request,function(_,err) reason=err end))
  t:update(0.01)
  assert(not t:busy() and reason == "invalid frame size" and s.closed == 1)
end

-- Cancellation isolates late packets; callbacks may issue another request synchronously.
do
  local a,b,c = socketFixture(),socketFixture(),socketFixture()
  local t, count = service({a,b,c}), 0
  a.incoming = {frame("result")}
  assert(t:request(request, function() error("cancelled callback") end))
  t:cancel(); t:update(0.01)
  assert(a.closed == 1 and a.calls == 0 and not t:busy())
  b.incoming = {frame("result") .. frame("result")}
  c.incoming = {frame("geocode")}
  assert(t:request(request, function(result)
    assert(result == payloads.result); count=count+1
    assert(t:request({type="geocode",id=8}, function(nextResult)
      assert(nextResult == payloads.geocode); count=count+1
    end))
  end))
  t:update(0.01)
  assert(count == 1 and t:busy() and c.calls == 0)
  t:update(0.01)
  assert(count == 2 and not t:busy() and b.closed == 1 and c.closed == 1)
  t:destroy(); t:update(1)
  local ok,err=t:request(request,function() end)
  assert(not ok and err == "destroyed")
end

-- Bound both decoded frames and socket reads per update, including queued frames.
do
  local s, got = socketFixture(), false
  local t = service({s})
  s.incoming = {string.rep(frame("status"),20) .. frame("result")}
  assert(t:request(request, function() got=true end))
  t:update(0.01); assert(t:stats().frames == 8 and not got)
  t:update(0.01); assert(t:stats().frames == 16 and not got)
  t:update(0.01); assert(got and t:stats().frames == 21)
end
do
  local s, got = socketFixture(), false
  local t = service({s})
  local body=string.rep("x",150000)
  payloads[body] = payloads.result
  local bytes = frame(body)
  for start=1,#bytes,8192 do s.incoming[#s.incoming+1]=bytes:sub(start,start+8191) end
  assert(t:request(request, function() got=true end))
  t:update(0.01)
  assert(s.calls == 8 and t:stats().bytesRead == 65536 and not got)
  t:update(0.01); assert(s.calls == 16 and not got)
  t:update(0.01); assert(got and s.closed == 1)
  payloads[body] = nil
end

-- Reject invalid setup before creating sockets; a thrown callback must not poison later requests.
do
  for _,port in ipairs({0,65536,1.5,"47613"}) do
    local t = service({}, {port=port})
    local ok,err=t:request(request,function() end)
    assert(not ok and err == "invalid port")
  end
  local s = socketFixture()
  local t = service({s})
  local ok=t:request({type="hello",id=7},function() end)
  assert(not ok)
  s.incoming={frame("result")}
  assert(t:request(request,function() error("callback failure") end))
  t:update(0.01)
  assert(not t:busy() and s.closed == 1)
end

print("TaxiDriver Earth transport regressions passed")
