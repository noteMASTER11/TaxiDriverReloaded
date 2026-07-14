-- Pure balancing helpers for cargo-delivery orders.
local M = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.generateWeight(config)
  config = config or {}
  local minimum = math.max(0, tonumber(config.minimumWeightKg) or 2)
  local maximum = math.max(minimum, tonumber(config.maximumWeightKg) or 250)
  local exponent = math.max(0.1, tonumber(config.weightDistributionExponent) or 1.55)
  return math.floor(minimum + (maximum - minimum) * math.pow(math.random(), exponent) + 0.5)
end

function M.calculateWeightBonusRate(weightKg, config)
  config = config or {}
  local threshold = math.max(0, tonumber(config.weightFareBonusThresholdKg) or 15)
  local maximumWeight = math.max(
    threshold + 0.01,
    tonumber(config.maximumWeightKg) or 250
  )
  local maximumBonus = math.max(0, tonumber(config.maximumWeightFareBonus) or 1.5)
  local weight = math.max(0, tonumber(weightKg) or 0)
  if weight <= threshold then return 0 end
  return clamp((weight - threshold) / (maximumWeight - threshold), 0, 1) * maximumBonus
end

function M.calculateFare(passengerFare, weightKg, config)
  local multiplier = clamp(tonumber(config and config.fareMultiplier) or 0.82, 0, 1)
  local weightBonusRate = M.calculateWeightBonusRate(weightKg, config)
  local deliveryFare = math.max(0, tonumber(passengerFare) or 0) * multiplier
  return deliveryFare * (1 + weightBonusRate), weightBonusRate,
    deliveryFare * weightBonusRate
end

function M.calculateImpactDamage(vehicleDamageDelta, config)
  config = config or {}
  local minimum = clamp(tonumber(config.minimumImpactDamagePercent) or 1, 0, 100)
  local maximum = clamp(tonumber(config.maximumImpactDamagePercent) or 35, minimum, 100)
  local scale = math.max(1, tonumber(config.impactDamageScale) or 4500)
  local severity = 1 - math.exp(-math.max(0, tonumber(vehicleDamageDelta) or 0) / scale)
  return clamp(minimum + (maximum - minimum) * severity, minimum, maximum)
end

function M.calculateRating(damagePercent, config)
  config = config or {}
  local damage = clamp(tonumber(damagePercent) or 0, 0, 100)
  local threshold = clamp(tonumber(config.ratingDamageThresholdPercent) or 5, 0, 99.9)
  if damage < threshold then return 5 end
  return clamp(5 - damage / 100 * 4, 1, 5)
end

return M
