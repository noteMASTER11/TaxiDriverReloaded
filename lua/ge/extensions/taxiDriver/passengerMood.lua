-- Pure passenger mood calculations. The main extension owns trip state and
-- calls these helpers when progress or driving events change the mood.
local M = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.apply(currentMood, initialMood, delta, maximumGain)
  currentMood = clamp(tonumber(currentMood) or 50, 0, 100)
  initialMood = clamp(tonumber(initialMood) or currentMood, 0, 100)
  delta = tonumber(delta) or 0
  local upperLimit = math.min(100, initialMood + math.max(0, maximumGain or 0))
  local nextMood = delta > 0 and
    clamp(currentMood + delta, 0, upperLimit) or
    clamp(currentMood + delta, 0, 100)
  return nextMood, nextMood - currentMood, upperLimit
end

function M.consumeProgress(previousProgress, currentProgress, accumulator, perfectRideGain)
  previousProgress = clamp(tonumber(previousProgress) or currentProgress or 0, 0, 1)
  currentProgress = clamp(tonumber(currentProgress) or previousProgress, 0, 1)
  accumulator = math.max(0, tonumber(accumulator) or 0) +
    math.max(0, currentProgress - previousProgress) * math.max(0, perfectRideGain or 0)
  local gain = math.floor(accumulator)
  return accumulator - gain, gain
end

function M.speedingLoss(baseLoss, excessKmh)
  return math.max(0, tonumber(baseLoss) or 0) +
    math.floor(math.min(4, math.max(0, tonumber(excessKmh) or 0) / 15))
end

function M.collisionLoss(baseLoss, damageDelta)
  return math.max(0, tonumber(baseLoss) or 0) +
    math.floor(math.min(15, math.max(0, tonumber(damageDelta) or 0) / 200))
end

function M.aggressionLoss(baseLoss, thresholdExcess)
  return math.max(0, tonumber(baseLoss) or 0) +
    math.floor(math.min(4, math.max(0, tonumber(thresholdExcess) or 0) * 8))
end

return M
