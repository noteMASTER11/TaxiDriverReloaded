local M = {}

local function randomRange(minimum, maximum)
  return minimum + (maximum - minimum) * math.random()
end

function M.create(isDelivery, isRush, isMultiStop)
  local roll = math.random()
  if isDelivery then
    if roll < 0.28 then
      return {kind = "fragileCargo", active = true, triggered = true, damageMultiplier = randomRange(1.25, 1.65)}
    end
    return {kind = "none"}
  end

  if roll < 0.08 then
    return {kind = "cancellation", triggerSeconds = randomRange(12, 35), elapsed = 0}
  elseif roll < 0.18 and not isMultiStop and not isRush then
    return {kind = "destinationChange", triggerProgress = randomRange(0.22, 0.48)}
  elseif roll < 0.28 and not isMultiStop and not isRush then
    return {kind = "additionalStop", triggerProgress = randomRange(0.18, 0.42)}
  elseif roll < 0.58 then
    return {
      kind = "tip",
      condition = isRush and "quick" or "careful",
      rate = randomRange(0.06, 0.16)
    }
  end
  return {kind = "none"}
end

function M.needsTarget(event)
  return event and (event.kind == "destinationChange" or event.kind == "additionalStop")
end

function M.updateBeforePickup(event, dt)
  if not event or event.triggered or event.kind ~= "cancellation" then return false end
  event.elapsed = (event.elapsed or 0) + math.max(0, tonumber(dt) or 0)
  if event.elapsed < (event.triggerSeconds or math.huge) then return false end
  event.triggered = true
  return true
end

function M.shouldTriggerOnRoute(event, progress)
  if not event or event.triggered or not M.needsTarget(event) or not event.target then return false end
  if math.max(0, tonumber(progress) or 0) < (event.triggerProgress or 1) then return false end
  event.triggered = true
  return true
end

function M.calculateTip(event, fare, penaltyRate, rushBonusActive)
  if not event or event.kind ~= "tip" or event.triggered then return 0 end
  local eligible = event.condition == "quick" and rushBonusActive == true or
    event.condition == "careful" and math.max(0, tonumber(penaltyRate) or 0) <= 0.02
  event.triggered = true
  if not eligible then return 0 end
  return math.floor(math.max(0, tonumber(fare) or 0) * (event.rate or 0) * 100 + 0.5) / 100
end

return M
