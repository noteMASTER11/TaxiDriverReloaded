local M = {}

local ignoredPeriodicFields = {
  settings = true,
  settingsNeedsLegacyImport = true,
  driverProfile = true,
  difficulty = true,
  realisticMode = true,
  hudEpoch = true,
  hudRevision = true
}

local lastSignatures = {}
local revision = 0
local epoch = ""

local function createEpoch()
  local timestamp = math.floor(tonumber(os.time and os.time() or 0) or 0)
  local nonce = math.random(0, 0x7fffffff)
  return string.format("%08x-%08x", timestamp % 0xffffffff, nonce)
end

epoch = createEpoch()

local function signature(value, encode)
  local valueType = type(value)
  if valueType == "nil" then return "nil:" end
  if valueType ~= "table" then return valueType .. ":" .. tostring(value) end
  local ok, result = pcall(encode, value)
  if ok then return "table:" .. tostring(result) end
  return "table-error:" .. tostring(result)
end

local function remember(state, encode)
  lastSignatures = {}
  for key, value in pairs(state or {}) do
    if not ignoredPeriodicFields[key] then
      lastSignatures[key] = signature(value, encode)
    end
  end
end

function M.publishFull(state, trigger, encode)
  revision = revision + 1
  state.hudEpoch = epoch
  state.hudRevision = revision
  remember(state, encode)
  trigger("TaxiDriverHUDState", state)
  return revision
end

function M.publishPatch(state, trigger, encode)
  local values = {}
  local removed = {}
  local changed = false
  local seen = {}

  for key, value in pairs(state or {}) do
    if not ignoredPeriodicFields[key] then
      seen[key] = true
      local currentSignature = signature(value, encode)
      if lastSignatures[key] ~= currentSignature then
        lastSignatures[key] = currentSignature
        values[key] = value
        changed = true
      end
    end
  end

  for key, _ in pairs(lastSignatures) do
    if not seen[key] then
      lastSignatures[key] = nil
      table.insert(removed, key)
      changed = true
    end
  end

  if changed then
    local baseRevision = revision
    revision = revision + 1
    trigger("TaxiDriverHUDPatch", {
      epoch = epoch,
      baseRevision = baseRevision,
      revision = revision,
      values = values,
      removed = removed
    })
  end
  return changed
end

function M.getEpoch()
  return epoch
end

function M.getRevision()
  return revision
end

function M.clientNeedsSync(clientEpoch, clientRevision)
  return tostring(clientEpoch or "") ~= epoch or
    tonumber(clientRevision) ~= revision
end

function M.reset()
  lastSignatures = {}
  revision = 0
  epoch = createEpoch()
end

return M
