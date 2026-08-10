-- Pure pricing/damage-normalization helpers for gas-station vehicle repairs.
local M = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

-- Converts BeamNG's raw, unbounded beamstate.damage scalar into a 0-100 percent,
-- using the same exponential-saturating curve shape as delivery.calculateImpactDamage,
-- but spanning the full range instead of delivery's fare-penalty cap.
function M.calculateDamagePercent(rawDamage, config)
  config = config or {}
  local scale = math.max(1, tonumber(config.damagePercentScale) or 4500)
  local clampedDamage = math.max(0, tonumber(rawDamage) or 0)
  local severity = 1 - math.exp(-clampedDamage / scale)
  return clamp(severity * 100, 0, 100)
end

function M.calculateRepairPrice(damagePercent, config)
  config = config or {}
  local minimum = math.max(0, tonumber(config.minimumRepairPrice) or 5)
  local maximum = math.max(minimum, tonumber(config.maximumRepairPrice) or 250)
  local scale = math.max(1, tonumber(config.repairPriceScale) or 45)
  local clampedDamage = clamp(tonumber(damagePercent) or 0, 0, 100)
  local severity = 1 - math.exp(-clampedDamage / scale)
  return clamp(minimum + (maximum - minimum) * severity, minimum, maximum)
end

return M
