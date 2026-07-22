local M = {}

local function lower(value)
  return string.lower(tostring(value or ""))
end

function M.normalizeIPv4(value)
  local a, b, c, d = tostring(value or ""):match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not a or not b or not c or not d or
    a > 255 or b > 255 or c > 255 or d > 255 then return nil end
  return string.format("%d.%d.%d.%d", a, b, c, d), a, b, c, d
end

function M.isLanIPv4(value)
  local _, a, b = M.normalizeIPv4(value)
  if not a then return false end
  if a == 10 or (a == 192 and b == 168) or
    (a == 172 and b >= 16 and b <= 31) then return true end
  -- Carrier-grade NAT ranges are also used by some home and mobile routers.
  return a == 100 and b >= 64 and b <= 127
end

local virtualMarkers = {
  "virtualbox", "vmware", "hyper-v", "default switch", "loopback",
  "openvpn", "wireguard", "tailscale", "zerotier", "hamachi",
  "tap-windows", "tunnel", "bluetooth", "vethernet"
}

local function adapterPenalty(description)
  description = lower(description)
  for _, marker in ipairs(virtualMarkers) do
    if description:find(marker, 1, true) then return 220 end
  end
  return 0
end

local function subnetScore(address)
  if address:match("^192%.168%.") then return 50 end
  if address:match("^10%.") then return 40 end
  if address:match("^172%.") then return 35 end
  if address:match("^100%.") then return 25 end
  return 0
end

function M.select(options)
  options = type(options) == "table" and options or {}
  local saved = M.normalizeIPv4(options.savedAddress)
  local routed = M.normalizeIPv4(options.routedAddress)
  local native = M.normalizeIPv4(options.nativeAddress)
  local candidates, byAddress = {}, {}

  local function add(value, description, source)
    local address = M.normalizeIPv4(value)
    if not address or not M.isLanIPv4(address) then return end
    local candidate = byAddress[address]
    if not candidate then
      candidate = {address = address, description = tostring(description or ""), sources = {}}
      byAddress[address] = candidate
      candidates[#candidates + 1] = candidate
    elseif candidate.description == "" and description then
      candidate.description = tostring(description)
    end
    candidate.sources[source] = true
  end

  for _, adapter in ipairs(type(options.adapters) == "table" and options.adapters or {}) do
    if type(adapter) == "table" then
      add(adapter.ipv4Addr or adapter.address or adapter.ip,
        adapter.description or adapter.name, "adapter")
    end
  end
  add(native, "BeamNG native server", "native")
  add(routed, "", "route")
  add(saved, "", "saved")

  local canBind = type(options.canBind) == "function" and options.canBind or function() return true end
  for _, candidate in ipairs(candidates) do
    local description = lower(candidate.description)
    local score = subnetScore(candidate.address)
    if candidate.sources.native then score = score + 100 end
    if candidate.sources.route then score = score + 90 end
    if candidate.sources.saved then score = score + 15 end
    if description:find("wi%-fi") or description:find("wireless", 1, true) or
      description:find("wlan", 1, true) or description:find("802%.11") then
      score = score + 80
    elseif description:find("ethernet", 1, true) or
      description:find("gigabit", 1, true) then
      score = score + 55
    end
    candidate.penalty = adapterPenalty(description)
    candidate.bindable = canBind(candidate.address) == true
    candidate.score = candidate.bindable and (score - candidate.penalty) or -10000
  end

  table.sort(candidates, function(first, second)
    if first.score ~= second.score then return first.score > second.score end
    return first.address < second.address
  end)
  local best = candidates[1]
  if not best or not best.bindable or best.score <= 0 then return nil, candidates end
  return best.address, candidates
end

return M
