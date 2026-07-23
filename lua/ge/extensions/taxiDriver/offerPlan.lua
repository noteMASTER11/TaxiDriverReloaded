local M = {}

function M.randomRange(minimum, maximum)
  minimum = tonumber(minimum) or 0
  maximum = tonumber(maximum) or minimum
  return minimum + (maximum - minimum) * math.random()
end

local function shuffle(values)
  for index = #values, 2, -1 do
    local swapIndex = math.random(index)
    values[index], values[swapIndex] = values[swapIndex], values[index]
  end
  return values
end

function M.build(targetCount, allowMultiStop, config, deliverySharePercent)
  config = type(config) == "table" and config or {}
  targetCount = math.max(0, math.floor(tonumber(targetCount) or 0))
  local plan = {}
  local requestedDeliveryCount = targetCount *
    math.max(0, math.min(100, tonumber(deliverySharePercent) or 50)) / 100
  local deliveryCount = math.floor(requestedDeliveryCount)
  if math.random() < requestedDeliveryCount - deliveryCount then
    deliveryCount = deliveryCount + 1
  end
  deliveryCount = math.min(targetCount, math.max(0, deliveryCount))
  local multiStopCount = 0
  if allowMultiStop ~= false then
    multiStopCount = math.min(
      math.max(0, targetCount - deliveryCount - 2),
      math.random(
        math.floor(tonumber(config.multiStopVisibleMin) or 0),
        math.floor(tonumber(config.multiStopVisibleMax) or 0)
      )
    )
  end
  local rushCount = math.min(
    math.max(0, targetCount - deliveryCount - multiStopCount - 1),
    math.random(
      math.floor(tonumber(config.rushVisibleMin) or 0),
      math.floor(tonumber(config.rushVisibleMax) or 0)
    )
  )
  for _ = 1, deliveryCount do plan[#plan + 1] = "delivery" end
  for _ = 1, multiStopCount do plan[#plan + 1] = "multiStop" end
  for _ = 1, rushCount do plan[#plan + 1] = "rush" end
  while #plan < targetCount do plan[#plan + 1] = "normal" end
  shuffle(plan)
  if plan[1] ~= "normal" then
    for index = 2, #plan do
      if plan[index] == "normal" then
        plan[1], plan[index] = plan[index], plan[1]
        break
      end
    end
  end
  return plan
end

return M
