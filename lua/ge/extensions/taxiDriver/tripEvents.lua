local M = {}

local function randomRange(minimum, maximum)
  return minimum + (maximum - minimum) * math.random()
end

local defaults = {
  cancellation = {enabled = true, chancePercent = 8},
  destinationChange = {enabled = true, chancePercent = 10},
  additionalStop = {enabled = true, chancePercent = 10},
  tip = {enabled = true, chancePercent = 30},
  fragileCargo = {enabled = true, chancePercent = 28},
  policeCheck = {enabled = false, chancePercent = 9},
  passengerNoShow = {enabled = true, chancePercent = 7},
  vipQuietRide = {enabled = true, chancePercent = 12},
  forgottenItem = {enabled = true, chancePercent = 8},
  roadClosure = {enabled = true, chancePercent = 10}
}

local function enabledChance(settings, key)
  local value = type(settings) == "table" and settings[key] or nil
  value = type(value) == "table" and value or defaults[key]
  if value.enabled == false then return 0 end
  return math.max(0, math.min(100, tonumber(value.chancePercent) or defaults[key].chancePercent))
end

local function addCandidate(candidates, settings, key, applicable)
  if not applicable then return end
  local chance = enabledChance(settings, key)
  if chance > 0 and math.random() * 100 <= chance then
    candidates[#candidates + 1] = key
  end
end

function M.create(isDelivery, isRush, isMultiStop, settings)
  local candidates = {}
  addCandidate(candidates, settings, "cancellation", not isDelivery)
  addCandidate(candidates, settings, "destinationChange", not isDelivery and not isMultiStop and not isRush)
  addCandidate(candidates, settings, "additionalStop", not isDelivery and not isMultiStop and not isRush)
  addCandidate(candidates, settings, "tip", not isDelivery)
  addCandidate(candidates, settings, "fragileCargo", isDelivery)
  addCandidate(candidates, settings, "policeCheck", true)
  addCandidate(candidates, settings, "passengerNoShow", not isDelivery)
  addCandidate(candidates, settings, "vipQuietRide", not isDelivery)
  addCandidate(candidates, settings, "forgottenItem", not isDelivery and not isMultiStop and not isRush)
  addCandidate(candidates, settings, "roadClosure", true)
  if not candidates[1] then return {kind = "none"} end

  local kind = candidates[math.random(#candidates)]
  if kind == "fragileCargo" then
    return {kind = kind, active = true, triggered = true, damageMultiplier = randomRange(1.25, 1.65)}
  elseif kind == "cancellation" then
    return {kind = kind, triggerSeconds = randomRange(12, 35), elapsed = 0}
  elseif kind == "destinationChange" then
    return {kind = kind, triggerProgress = randomRange(0.22, 0.48)}
  elseif kind == "additionalStop" then
    return {kind = kind, triggerProgress = randomRange(0.18, 0.42)}
  elseif kind == "policeCheck" then
    return {kind = kind, triggerProgress = randomRange(0.18, 0.62)}
  elseif kind == "passengerNoShow" then
    return {kind = kind, triggerSeconds = randomRange(8, 14), elapsed = 0}
  elseif kind == "vipQuietRide" then
    return {kind = kind, active = true, triggered = true, rate = randomRange(0.08, 0.18)}
  elseif kind == "forgottenItem" then
    return {kind = kind, triggerProgress = randomRange(0.62, 0.82)}
  elseif kind == "roadClosure" then
    return {kind = kind, triggerProgress = randomRange(0.20, 0.58)}
  end
  return {
    kind = "tip",
    condition = isRush and "quick" or "careful",
    rate = randomRange(0.06, 0.16)
  }
end

function M.needsTarget(event)
  return event and (event.kind == "destinationChange" or event.kind == "additionalStop" or
    event.kind == "forgottenItem")
end

function M.isRouteTargetEvent(event)
  return event and (M.needsTarget(event) or event.kind == "roadClosure")
end

function M.updateBeforePickup(event, dt)
  if not event or event.triggered or event.kind ~= "cancellation" then return false end
  event.elapsed = (event.elapsed or 0) + math.max(0, tonumber(dt) or 0)
  if event.elapsed < (event.triggerSeconds or math.huge) then return false end
  event.triggered = true
  return true
end

function M.updateNoShow(event, atPickup, dt)
  if not event or event.triggered or event.kind ~= "passengerNoShow" then return false end
  if not atPickup then
    event.elapsed = 0
    return false
  end
  event.elapsed = (event.elapsed or 0) + math.max(0, tonumber(dt) or 0)
  if event.elapsed < (event.triggerSeconds or math.huge) then return false end
  event.triggered, event.status = true, "noShow"
  return true
end

function M.shouldTriggerOnRoute(event, progress)
  if not event or event.triggered or not M.isRouteTargetEvent(event) or not event.target then return false end
  if math.max(0, tonumber(progress) or 0) < (event.triggerProgress or 1) then return false end
  event.triggered = true
  return true
end

function M.shouldTriggerPolice(event, phase, progress)
  if not event or event.triggered or event.kind ~= "policeCheck" then return false end
  if phase ~= "toPickup" and phase ~= "toDestination" and phase ~= "toStop" then return false end
  if math.max(0, tonumber(progress) or 0) < (event.triggerProgress or 1) then return false end
  event.triggered = true
  event.active = true
  return true
end

function M.calculateTip(event, fare, penaltyRate, rushBonusActive)
  if not event then return 0 end
  if event.kind == "vipQuietRide" then
    if event.resolved then return 0 end
    event.resolved = true
    local eligible = math.max(0, tonumber(penaltyRate) or 0) <= 0.01
    event.status = eligible and "completed" or "conditionsFailed"
    event.amount = eligible and math.floor(math.max(0, tonumber(fare) or 0) *
      (event.rate or 0) * 100 + 0.5) / 100 or 0
    return event.amount
  end
  if event.kind ~= "tip" or event.triggered then return 0 end
  local eligible = event.condition == "quick" and rushBonusActive == true or
    event.condition == "careful" and math.max(0, tonumber(penaltyRate) or 0) <= 0.02
  event.triggered = true
  if not eligible then event.status = "conditionsFailed"; return 0 end
  event.amount = math.floor(math.max(0, tonumber(fare) or 0) * (event.rate or 0) * 100 + 0.5) / 100
  event.status = "completed"
  return event.amount
end

function M.history(event)
  if not event or event.kind == "none" then return {} end
  return {{
    kind = tostring(event.kind or "none"),
    status = tostring(event.status or (event.triggered and "completed" or "notTriggered")),
    amount = math.max(0, tonumber(event.amount or event.fineAmount) or 0)
  }}
end

return M
