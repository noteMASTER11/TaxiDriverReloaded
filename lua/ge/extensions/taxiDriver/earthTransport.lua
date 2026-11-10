-- A request-only Earth connection. Never sends hello, pose or anchor messages.
local M = {}
local CHUNK_BYTES, READ_CALLS, FRAME_COUNT = 8192, 8, 8

local function frame(body)
  local n = #body
  return string.char(n % 256, math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256) .. body
end

function M.new(options)
  options = options or {}
  local service, active, destroyed = {}, nil, false
  local encode, decode = options.encode or jsonEncode, options.decode or jsonDecode
  local maxFrameBytes = math.min(tonumber(options.maxFrameBytes) or 1048576, 1048576)
  local counters = {bytesRead=0, bytesSent=0, readCalls=0, sendCalls=0, frames=0, requests=0}

  local function close(op)
    if op.socket then pcall(function() op.socket:close() end); op.socket = nil end
  end
  local function finish(op, result, err)
    if active ~= op then return end
    active = nil
    close(op)
    local callback = op.callback
    op.callback = nil
    if callback then pcall(callback, result, err) end
  end
  local function take(op, n)
    local pieces = {}
    while n > 0 do
      local chunk = op.queue[op.head]
      local count = math.min(n, #chunk - op.offset + 1)
      pieces[#pieces+1] = chunk:sub(op.offset, op.offset + count - 1)
      op.offset = op.offset + count
      if op.offset > #chunk then
        op.queue[op.head] = nil; op.head = op.head + 1; op.offset = 1
      end
      n = n - count; op.buffered = op.buffered - count
    end
    return table.concat(pieces)
  end
  local function parse(op, budget)
    while active == op and budget > 0 do
      if not op.length then
        if op.buffered < 4 then break end
        local h = take(op, 4)
        local a,b,c,d = h:byte(1,4)
        op.length = a + b*256 + c*65536 + d*16777216
        if op.length < 1 or op.length > maxFrameBytes then
          finish(op, nil, "invalid frame size"); break
        end
        op.parts, op.collected = {}, 0
      end
      local n = math.min(op.length - op.collected, op.buffered)
      if n > 0 then
        op.parts[#op.parts+1] = take(op, n)
        op.collected = op.collected + n
      end
      if op.collected < op.length then break end
      local ok, result = pcall(decode, table.concat(op.parts))
      op.length, op.parts = nil, nil
      budget = budget - 1; counters.frames = counters.frames + 1
      if not ok or type(result) ~= "table" or type(result.type) ~= "string" then
        finish(op, nil, "invalid JSON response"); break
      end
      if result.type == op.expected and result.id == op.id then finish(op, result, nil) end
    end
    return budget
  end

  function service:request(message, callback)
    if destroyed then return false, "destroyed" end
    if active then return false, "busy" end
    local port = options.port or 47613
    if type(port) ~= "number" or port ~= math.floor(port) or port < 1 or port > 65535 then
      return false, "invalid port"
    end
    if type(message) ~= "table" or (message.type ~= "route" and message.type ~= "geocode" and message.type ~= "map_labels" and message.type ~= "where") or
      message.id == nil or type(callback) ~= "function" then return false, "invalid request" end
    local ok, body = pcall(encode, message)
    if not ok or type(body) ~= "string" or #body > 8188 then return false, "invalid request encoding" end
    local lib = options.socket
    if not lib then ok, lib = pcall(require, "socket"); if not ok then return false, "socket unavailable" end end
    local created, sock, err = pcall(lib.tcp)
    if not created or not sock then return false, tostring(err or sock or "socket unavailable") end
    local timeoutOk, timeoutResult = pcall(function() return sock:settimeout(0) end)
    if not timeoutOk or not timeoutResult then pcall(function() sock:close() end); return false, "socket setup failed" end
    active = {socket=sock, port=port, callback=callback, expected=message.type .. "_result", id=message.id,
      connecting=true, outbound=frame(body), sent=0, queue={}, head=1, tail=0, offset=1, buffered=0,
      elapsed=0, lastClock=options.clock and options.clock() or nil}
    counters.requests = counters.requests + 1
    return true
  end

  function service:update(dtReal)
    local op = active
    if not op then return end
    local delta = tonumber(dtReal) or 0
    if options.clock then
      local now = options.clock()
      delta = now - op.lastClock
      op.lastClock = now
    end
    if delta >= 0 and delta < math.huge then op.elapsed = op.elapsed + delta end
    if op.elapsed >= 60 then finish(op,nil,"request timeout"); return end
    if op.connecting and op.elapsed >= 3 then finish(op,nil,"connect timeout"); return end
    if op.connecting then
      local ok, result, err = pcall(function() return op.socket:connect("127.0.0.1", op.port) end)
      if not ok then finish(op,nil,"connect failed: " .. tostring(result)); return end
      if result or (err and err:lower():find("already connected", 1, true)) then op.connecting = false
      elseif err == "timeout" or (err and err:lower():find("in progress", 1, true)) then return
      else finish(op,nil,"connect failed: " .. tostring(err)); return end
    end
    if op.sent < #op.outbound then
      counters.sendCalls = counters.sendCalls + 1
      local ok, last, err, partial = pcall(function() return op.socket:send(op.outbound, op.sent + 1) end)
      if not ok then finish(op,nil,"send failed: " .. tostring(last)); return end
      local sent = last or partial or op.sent
      counters.bytesSent = counters.bytesSent + math.max(0, sent - op.sent)
      op.sent = sent
      if err and err ~= "timeout" then finish(op,nil,"send failed: " .. tostring(err)); return end
      if op.sent < #op.outbound then return end
    end
    local budget = parse(op, FRAME_COUNT)
    if active ~= op then return end
    for _ = 1, READ_CALLS do
      if budget == 0 or op.closed then break end
      counters.readCalls = counters.readCalls + 1
      local ok, data, err, partial = pcall(function() return op.socket:receive(CHUNK_BYTES) end)
      if not ok then finish(op,nil,"receive failed: " .. tostring(data)); return end
      data = data or partial or ""
      if #data > 0 then
        counters.bytesRead = counters.bytesRead + #data
        op.tail = op.tail + 1; op.queue[op.tail] = data; op.buffered = op.buffered + #data
      end
      if err and err ~= "timeout" then op.closed = err end
      budget = parse(op, budget)
      if active ~= op then return end
      if err or #data == 0 then break end
    end
    if op.closed and (budget > 0 or op.buffered == 0) then
      finish(op,nil,"receive failed: " .. tostring(op.closed))
    end
  end

  function service:busy() return active ~= nil end
  function service:cancel()
    local op = active; active = nil
    if op then op.callback = nil; close(op) end
  end
  function service:destroy() self:cancel(); destroyed = true end
  function service:stats()
    local result = {}
    for k,v in pairs(counters) do result[k]=v end
    return result
  end
  return service
end

return M
