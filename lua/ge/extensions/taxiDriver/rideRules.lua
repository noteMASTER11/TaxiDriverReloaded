local M = {}

function M.new(options)
  options = type(options) == "table" and options or {}
  local balance = type(options.balance) == "table" and options.balance or {}
  local offer = type(options.offer) == "table" and options.offer or {}
  local phases = type(options.phases) == "table" and options.phases or {}
  local averageCitySpeedKmh = math.max(1, tonumber(options.averageCitySpeedKmh) or 32)
  local economyMultiplier = type(options.getEconomyMultiplier) == "function" and
    options.getEconomyMultiplier or function() return 1 end
  local getDetour = type(options.getDetour) == "function" and options.getDetour or
    function() return nil end
  local service = {}

  local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
  end

  local function roundMoney(value)
    return math.floor(value * 100 + 0.5) / 100
  end

  local function effectivePhase(phase)
    local detour = getDetour()
    if phase == phases.toFuelStation and detour and detour.active then
      return detour.previousPhase
    end
    return phase
  end

  function service.calculateEtaMinutes(distanceMeters)
    return math.max(0, tonumber(distanceMeters) or 0) / 1000 / averageCitySpeedKmh * 60
  end

  function service.calculateFare(distanceMeters, waitingSeconds)
    local distanceKm = math.max(0, tonumber(distanceMeters) or 0) / 1000
    local etaMinutes = service.calculateEtaMinutes(distanceMeters) +
      math.max(0, tonumber(waitingSeconds) or 0) / 60
    return roundMoney(((tonumber(balance.baseFare) or 0) +
      distanceKm * (tonumber(balance.farePerKm) or 0) +
      etaMinutes * (tonumber(balance.farePerMinute) or 0)) *
      clamp(tonumber(economyMultiplier()) or 1, 0.25, 5))
  end

  function service.calculateRatingBonusRate(rating)
    local threshold = tonumber(balance.ratingBonusThreshold) or 4
    local progress = clamp((tonumber(rating) or 0) - threshold, 0, 5 - threshold) /
      math.max(0.01, 5 - threshold)
    return progress * math.max(0, tonumber(balance.maxRatingBonus) or 0)
  end

  function service.calculatePickupWaitSeconds(pickupDistance)
    return clamp(
      service.calculateEtaMinutes(pickupDistance) * 60 *
        (tonumber(offer.pickupTimeMultiplier) or 1) +
        (tonumber(offer.pickupTimeGraceSeconds) or 0),
      tonumber(offer.pickupTimeMinSeconds) or 0,
      tonumber(offer.pickupTimeMaxSeconds) or math.huge
    )
  end

  function service.isPassengerDrivingPhase(phase)
    phase = effectivePhase(phase)
    return phase == phases.toStop or phase == phases.toDestination
  end

  function service.isPassengerOnboardPhase(phase)
    phase = effectivePhase(phase)
    return phase == phases.boarding or phase == phases.toStop or
      phase == phases.stopWaiting or phase == phases.toDestination or
      phase == phases.passengerStopDemand or phase == phases.passengerForcedExit or
      phase == phases.driverAbandoning or phase == phases.alighting
  end

  return service
end

return M
