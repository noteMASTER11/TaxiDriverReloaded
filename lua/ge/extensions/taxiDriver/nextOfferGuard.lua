local M = {}

local function finite(value)
  value = tonumber(value)
  return value ~= nil and value == value and value > -math.huge and value < math.huge and value or nil
end

function M.update(offer, remaining, accepted, dtReal, context)
  if not offer then return {remaining = 0, expired = false} end
  if accepted == true then return {remaining = math.max(0, finite(remaining) or 0), expired = false} end
  context = type(context) == "table" and context or {}
  local id = math.floor(finite(offer.id) or -1)
  if id <= 0 then return {remaining = 0, expired = true, reason = "invalidId"} end
  if context.active ~= true or context.hasTrip ~= true then
    return {remaining = 0, expired = true, reason = "orphaned"}
  end
  if tostring(context.phase or "") ~= tostring(context.expectedPhase or "toDestination") then
    return {remaining = 0, expired = true, reason = "phaseChanged"}
  end

  local duration = math.max(0.25, finite(context.duration) or 5)
  local value = finite(remaining)
  if not value then return {remaining = 0, expired = true, reason = "invalidTimer"} end
  -- A corrupted or stale HUD value must not make an offer immortal.
  value = math.min(value, duration)
  local delta = finite(dtReal)
  if not delta or delta < 0 then delta = 0 end
  value = math.max(0, value - delta)
  return {remaining = value, expired = value <= 0, reason = value <= 0 and "timeout" or nil}
end

return M
