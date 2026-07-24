-- Static TaxiDriver configuration. Runtime state stays in the main extension;
-- constants and balance presets live here so they can be reviewed separately.
local M = {}

M.supportedLanguages = {
  en = true, de = true, fr = true, es = true,
  it = true, pl = true, uk = true, ru = true,
  ["zh-CN"] = true
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

M.customDifficultyDefaults = {
  speedToleranceKmh = 10,
  speedGraceSeconds = 4,
  speedPenaltyStrengthPercent = 100,
  collisionSensitivityPercent = 50,
  collisionPenaltyStrengthPercent = 100,
  longitudinalGThreshold = 0.65,
  lateralGThreshold = 0.58,
  aggressionPenaltyStrengthPercent = 100,
  pickupPenaltyStrengthPercent = 100,
  maxFareReductionPercent = 50,
  earlyExitRatingLossPercent = 30
}

M.customDifficultyRanges = {
  speedToleranceKmh = {0, 30},
  speedGraceSeconds = {0, 10},
  speedPenaltyStrengthPercent = {0, 250},
  collisionSensitivityPercent = {0, 100},
  collisionPenaltyStrengthPercent = {0, 250},
  longitudinalGThreshold = {0.30, 1.20},
  lateralGThreshold = {0.30, 1.20},
  aggressionPenaltyStrengthPercent = {0, 250},
  pickupPenaltyStrengthPercent = {0, 200},
  maxFareReductionPercent = {10, 75},
  earlyExitRatingLossPercent = {0, 60}
}

function M.sanitizeCustomDifficulty(source)
  source = type(source) == "table" and source or {}
  local result = {}
  for key, defaultValue in pairs(M.customDifficultyDefaults) do
    local range = M.customDifficultyRanges[key]
    result[key] = clamp(tonumber(source[key]) or defaultValue, range[1], range[2])
  end
  return result
end

function M.buildCustomDifficulty(source)
  local custom = M.sanitizeCustomDifficulty(source)
  local speedStrength = custom.speedPenaltyStrengthPercent / 100
  local collisionStrength = custom.collisionPenaltyStrengthPercent / 100
  local aggressionStrength = custom.aggressionPenaltyStrengthPercent / 100
  local pickupStrength = custom.pickupPenaltyStrengthPercent / 100
  local collisionSensitivity = custom.collisionSensitivityPercent / 100
  return {
    maxTotalPenalty = custom.maxFareReductionPercent / 100,
    pickupLateBasePenalty = 0.05 * pickupStrength,
    pickupLatePenaltyPerSecond = 0.000333 * pickupStrength,
    maxPickupLatePenalty = 0.12 * pickupStrength,
    speedToleranceKmh = custom.speedToleranceKmh,
    speedToleranceRatio = 0,
    speedGraceSeconds = custom.speedGraceSeconds,
    speedPenaltyRate = 0.0008 * speedStrength,
    maxSpeedPenalty = 0.15 * speedStrength,
    collisionDamageScale = 30000 - 24000 * collisionSensitivity,
    collisionDamageThreshold = 100 - 95 * collisionSensitivity,
    collisionDamagePenalty = 0.18 * collisionStrength,
    collisionEventPenalty = 0.01 * collisionStrength,
    maxCollisionPenalty = 0.20 * collisionStrength,
    longitudinalGThreshold = custom.longitudinalGThreshold,
    lateralGThreshold = custom.lateralGThreshold,
    longitudinalGRelease = math.max(0.15, custom.longitudinalGThreshold * 0.65),
    lateralGRelease = math.max(0.15, custom.lateralGThreshold * 0.65),
    aggressionEventPenalty = 0.005 * aggressionStrength,
    aggressionExtraRate = 0.015 * aggressionStrength,
    aggressionExtraMax = 0.01 * aggressionStrength,
    maxAggressionPenalty = 0.12 * aggressionStrength
  }
end

M.aiDriverPresetOrder = {"novice", "cautious", "balanced", "assertive", "racer", "custom"}

M.aiDriverDefaults = {
  aggressionPercent = 40,
  followingTimeGap = 2.3,
  minimumFollowingDistance = 4,
  brakingDeceleration = 3.5,
  trafficWaitSeconds = 3,
  obeySpeedLimits = true,
  laneDiscipline = true,
  strictGpsRoute = false
}

M.aiDriverPresets = {
  novice = {
    aggressionPercent = 30, followingTimeGap = 3.4, minimumFollowingDistance = 7,
    brakingDeceleration = 2.5, trafficWaitSeconds = 6,
    obeySpeedLimits = true, laneDiscipline = true
  },
  cautious = {
    aggressionPercent = 35, followingTimeGap = 2.8, minimumFollowingDistance = 5.5,
    brakingDeceleration = 3, trafficWaitSeconds = 4,
    obeySpeedLimits = true, laneDiscipline = true
  },
  balanced = {
    aggressionPercent = 40, followingTimeGap = 2.3, minimumFollowingDistance = 4,
    brakingDeceleration = 3.5, trafficWaitSeconds = 3,
    obeySpeedLimits = true, laneDiscipline = true
  },
  assertive = {
    aggressionPercent = 60, followingTimeGap = 1.8, minimumFollowingDistance = 3,
    brakingDeceleration = 4.5, trafficWaitSeconds = 2,
    obeySpeedLimits = false, laneDiscipline = true
  },
  racer = {
    aggressionPercent = 85, followingTimeGap = 1.3, minimumFollowingDistance = 2,
    brakingDeceleration = 6, trafficWaitSeconds = 1,
    obeySpeedLimits = false, laneDiscipline = false
  }
}

function M.sanitizeAiDriver(source)
  local hasSource = type(source) == "table"
  source = hasSource and source or {}
  local requestedPreset = tostring(source.preset or "")
  local preset = M.aiDriverPresets[requestedPreset] and requestedPreset or
    (requestedPreset == "custom" and "custom" or nil)
  if not preset then preset = hasSource and next(source) ~= nil and "custom" or "balanced" end
  local base = preset == "custom" and M.aiDriverDefaults or M.aiDriverPresets[preset]
  local values = preset == "custom" and source or base
  local obeySpeedLimits = values.obeySpeedLimits
  if obeySpeedLimits == nil then obeySpeedLimits = values.obeyTrafficRules ~= false end
  return {
    preset = preset,
    aggressionPercent = clamp(tonumber(values.aggressionPercent) or base.aggressionPercent, 30, 100),
    followingTimeGap = clamp(tonumber(values.followingTimeGap) or base.followingTimeGap, 1, 4),
    minimumFollowingDistance = clamp(tonumber(values.minimumFollowingDistance) or
      base.minimumFollowingDistance, 2, 10),
    brakingDeceleration = clamp(tonumber(values.brakingDeceleration) or
      base.brakingDeceleration, 2, 8),
    trafficWaitSeconds = clamp(tonumber(values.trafficWaitSeconds) or
      base.trafficWaitSeconds, 1, 10),
    obeySpeedLimits = obeySpeedLimits ~= false,
    laneDiscipline = values.laneDiscipline ~= false,
    -- Route fidelity is independent from driving temperament and therefore
    -- survives preset changes.
    strictGpsRoute = source.strictGpsRoute == true
  }
end

M.randomEventOrder = {
  "cancellation",
  "destinationChange",
  "additionalStop",
  "tip",
  "fragileCargo",
  "policeCheck",
  "passengerNoShow",
  "vipQuietRide",
  "forgottenItem",
  "roadClosure"
}

M.randomEventDefaults = {
  cancellation = {enabled = true, chancePercent = 8},
  destinationChange = {enabled = true, chancePercent = 10},
  additionalStop = {enabled = true, chancePercent = 10},
  tip = {enabled = true, chancePercent = 30},
  fragileCargo = {enabled = true, chancePercent = 28},
  policeCheck = {enabled = false, chancePercent = 9, preloadConfirmed = false},
  passengerNoShow = {enabled = true, chancePercent = 7},
  vipQuietRide = {enabled = true, chancePercent = 12},
  forgottenItem = {enabled = true, chancePercent = 8},
  roadClosure = {enabled = true, chancePercent = 10}
}

function M.sanitizeRandomEvents(source)
  source = type(source) == "table" and source or {}
  local result = {}
  for _, key in ipairs(M.randomEventOrder) do
    local defaults = M.randomEventDefaults[key]
    local value = type(source[key]) == "table" and source[key] or {}
    local enabled = value.enabled == nil and defaults.enabled == true or value.enabled == true
    if key == "policeCheck" and value.preloadConfirmed ~= true then enabled = false end
    result[key] = {
      enabled = enabled,
      chancePercent = math.floor(clamp(
        tonumber(value.chancePercent) or defaults.chancePercent,
        0,
        100
      ) + 0.5),
      preloadConfirmed = key == "policeCheck" and value.preloadConfirmed == true or nil
    }
  end
  return result
end

M.fleetDefaults = {
  enabled = true,
  aiPreset = "standard",
  ownerSharePercent = 35,
  hiringFee = 75,
  wagePerTenMinutes = 12,
  maxDrivers = 6,
  worldLabelDistance = 400,
  incomeMultiplier = 1,
  minimumJobDistanceKm = 1.5,
  maximumJobDistanceKm = 8,
  passengerJobs = true,
  deliveryJobs = true
}

M.fleetAiPresets = {
  careful = {
    aggressionPercent = 20, followingTimeGap = 3.1, brakingDeceleration = 2.3,
    stuckDelaySeconds = 20, obeySpeedLimits = true, obeyTrafficSignals = true,
    allowOvertaking = false, laneChangeClearancePercent = 145,
    allowOncomingRecovery = false, allowReverseRecovery = true,
    recoveryMaxAttempts = 3, finalApproachSpeedKmh = 8
  },
  standard = {
    aggressionPercent = 30, followingTimeGap = 2.4, brakingDeceleration = 2.8,
    stuckDelaySeconds = 15, obeySpeedLimits = true, obeyTrafficSignals = true,
    allowOvertaking = true, laneChangeClearancePercent = 110,
    allowOncomingRecovery = true, allowReverseRecovery = true,
    recoveryMaxAttempts = 3, finalApproachSpeedKmh = 11
  },
  fast = {
    aggressionPercent = 52, followingTimeGap = 1.8, brakingDeceleration = 3.5,
    stuckDelaySeconds = 11, obeySpeedLimits = false, obeyTrafficSignals = true,
    allowOvertaking = true, laneChangeClearancePercent = 75,
    allowOncomingRecovery = true, allowReverseRecovery = true,
    recoveryMaxAttempts = 4, finalApproachSpeedKmh = 15
  }
}

function M.sanitizeFleet(source)
  source = type(source) == "table" and source or {}
  local defaults = M.fleetDefaults
  local minimum = clamp(tonumber(source.minimumJobDistanceKm) or defaults.minimumJobDistanceKm, 0.5, 20)
  local passengerJobs = source.passengerJobs ~= false
  local deliveryJobs = source.deliveryJobs ~= false
  if not passengerJobs and not deliveryJobs then passengerJobs = true end
  return {
    enabled = source.enabled ~= false,
    aiPreset = M.fleetAiPresets[tostring(source.aiPreset or "")] and tostring(source.aiPreset) or defaults.aiPreset,
    ownerSharePercent = math.floor(clamp(tonumber(source.ownerSharePercent) or defaults.ownerSharePercent, 10, 90) + 0.5),
    hiringFee = math.floor(clamp(tonumber(source.hiringFee) or defaults.hiringFee, 0, 1000) + 0.5),
    wagePerTenMinutes = math.floor(clamp(tonumber(source.wagePerTenMinutes) or defaults.wagePerTenMinutes, 0, 250) + 0.5),
    maxDrivers = math.floor(clamp(tonumber(source.maxDrivers) or defaults.maxDrivers, 1, 12) + 0.5),
    worldLabelDistance = math.floor(clamp(tonumber(source.worldLabelDistance) or defaults.worldLabelDistance, 50, 1000) + 0.5),
    incomeMultiplier = clamp(tonumber(source.incomeMultiplier) or defaults.incomeMultiplier, 0.25, 3),
    minimumJobDistanceKm = minimum,
    maximumJobDistanceKm = clamp(tonumber(source.maximumJobDistanceKm) or defaults.maximumJobDistanceKm, minimum, 50),
    passengerJobs = passengerJobs,
    deliveryJobs = deliveryJobs
  }
end

M.runtime = {
  minRideDistance = 1000,
  maxRideDistance = 25000,
  minPickupDistance = 400,
  maxPickupDistance = 3500,
  arrivalRadius = 14,
  maxArrivalSpeedKmh = 4,
  averageCitySpeedKmh = 40,
  minimumDrivability = 0.7,
  hudUpdateInterval = 0.2,
  boardingDuration = 3,
  alightingDuration = 3,
  completedDuration = 4,
  stopWaitingDuration = 10,
  forcedExitDuration = 5
}

M.autopilot = {
  normalAggression = 0.3,
  recoveryAggression = 1,
  stuckDelay = 15,
  recoveryRetryInterval = 8,
  recoverySuccessDistance = 8,
  signalHoldDistance = 120,
  approachDistance = 45,
  finalApproachDistance = 20,
  stopDistance = 8,
  approachSpeed = 8,
  finalApproachSpeed = 3.5,
  stoppedSpeedKmh = 1.5,
  movingSpeedKmh = 4,
  bypassSpeed = 12,
  bypassDistance = 32,
  bypassOffset = 5,
  oncomingScanAhead = 200,
  oncomingScanBehind = 25,
  oncomingRetryInterval = 2,
  oncomingMaxWait = 20,
  bypassControllerSpeed = 7,
  bypassControllerTimeout = 14,
  followTimeGap = 2.2,
  followMinimumGap = 7,
  followEmergencyGap = 3.5,
  followComfortableDeceleration = 2.8,
  followGapResponseTime = 4,
  followScanDistance = 160,
  followScanInterval = 0.2,
  followLaneMargin = 0.9,
  signalLookAhead = 160,
  signalLaneHalfWidth = 12,
  signalStopBuffer = 5,
  signalComfortableDeceleration = 3,
  yellowDecisionDeceleration = 3.5,
  intersectionClearDistance = 30,
  proactiveApproachDistance = 75,
  proactiveApproachRetryInterval = 2,
  proactiveApproachFailureCooldown = 10,
  directApproachDistance = 48,
  directApproachDelay = 0.4,
  directApproachSpeed = 3.5,
  directApproachTimeout = 20,
  laneChangeLeadDistance = 35,
  laneChangeLeadHold = 2,
  laneChangeRoadAlignment = 0.96,
  laneChangeIntersectionDistance = 65,
  laneChangeWidth = 3.6,
  laneChangeDistance = 35,
  laneChangeDuration = 5,
  laneChangeCooldown = 20,
  laneChangeFreeAhead = 55,
  laneChangeFreeBehind = 22
}

M.offer = {
  initialDelay = 1.5,
  intervalMin = 1.2,
  intervalMax = 2.2,
  generationStepInterval = 0.02,
  semanticScanBatchSize = 6,
  semanticCandidateAttempts = 40,
  randomRouteAttempts = 24,
  unboundedRouteAttempts = 48,
  semanticLongitudinalJitterMax = 70,
  randomDistanceExponent = 1.15,
  recentStopLimit = 48,
  recentStopSeparation = 150,
  routeDiversityMinimumShare = 0.65,
  routeDiversityAttempts = 3,
  routeDiversityCellSize = 400,
  routeDiversityEndpointSeparation = 280,
  recentRouteLimit = 20,
  minVisible = 10,
  maxVisible = 12,
  nextOfferDuration = 5,
  nextOfferRetryMin = 5,
  nextOfferRetryMax = 10,
  nextOfferErrorLimit = 3,
  nextOfferProgressThreshold = 0.80,
  pickupTimeMultiplier = 1.35,
  pickupTimeGraceSeconds = 60,
  pickupTimeMinSeconds = 120,
  pickupTimeMaxSeconds = 600,
  multiStopChance = 0.24,
  multiStopVisibleMin = 2,
  multiStopVisibleMax = 3,
  rushVisibleMin = 2,
  rushVisibleMax = 4,
  multiStopCountMin = 2,
  multiStopCountMax = 2,
  multiStopMinimumCandidates = 20,
  multiStopSegmentMin = 3000,
  multiStopSegmentMax = 7000,
  multiStopRouteAttempts = 18,
  generationFailureBackoffMin = 4,
  generationFailureBackoffMax = 7,
  rushChance = 0.28,
  rushBonusMin = 0.22,
  rushBonusMax = 0.42,
  rushTimeRatioMin = 0.72,
  rushTimeRatioMax = 0.86
}

M.balance = {
  baseFare = 3.25,
  farePerKm = 1.55,
  farePerMinute = 0.20,
  ratingBonusThreshold = 3.99,
  maxRatingBonus = 0.15,
  maxTotalPenalty = 0.50,
  pickupLateBasePenalty = 0.05,
  pickupLatePenaltyPerSecond = 0.000333,
  maxPickupLatePenalty = 0.12,
  speedToleranceKmh = 8,
  speedToleranceRatio = 0.15,
  speedGraceSeconds = 3,
  speedPenaltyRate = 0.0008,
  maxSpeedPenalty = 0.15,
  collisionDamageScale = 12000,
  collisionDamageThreshold = 20,
  collisionDamagePenalty = 0.18,
  collisionEventPenalty = 0.01,
  collisionCooldownSeconds = 3,
  maxCollisionPenalty = 0.20,
  longitudinalGThreshold = 0.62,
  lateralGThreshold = 0.55,
  longitudinalGRelease = 0.40,
  lateralGRelease = 0.35,
  aggressionEventPenalty = 0.005,
  aggressionExtraRate = 0.015,
  aggressionExtraMax = 0.01,
  aggressionCooldownSeconds = 3,
  maxAggressionPenalty = 0.12,
  ratingPenaltyScale = 8,
  collisionRatingPenalty = 0.15,
  minimumRideRating = 1,
  calmPenaltyIgnoreMaximum = 0.70,
  calmPenaltyMultiplierThreshold = 50,
  passengerStressThresholdMinimum = 72,
  passengerStressThresholdCalmBonus = 23,
  passengerMoodMaximumGain = 40,
  passengerMoodPerfectRideGain = 40,
  passengerMoodStressRecovery = 0.8,
  passengerMoodPickupLateLoss = 4,
  passengerMoodPickupLateStepLoss = 2,
  passengerMoodSpeedingBaseLoss = 2,
  passengerMoodCollisionBaseLoss = 10,
  passengerMoodAggressionBaseLoss = 4,
  passengerMoodRushExpiredLoss = 6
}

M.earlyExitRatingLoss = {
  elementary = 0.10,
  easy = 0.20,
  standard = 0.30,
  professional = 0.45
}

M.driverAbandonmentExtraLoss = {
  elementary = 0.10,
  easy = 0.20,
  standard = 0.30,
  professional = 0.45
}

M.realisticFuel = {
  fuelInitialLevel = 0.05,
  electricInitialLevel = 0.30,
  fallbackPricePerUnit = 1,
  fuelRatePerSecond = 2,
  electricPercentRatePerSecond = 4,
  dashboardRefreshInterval = 1,
  estimatedConsumptionPer100Km = {
    gasoline = 10,
    diesel = 8.5,
    kerosine = 12.5,
    electricEnergy = 22
  },
  priceByEnergyType = {
    gasoline = 0.93,
    electricEnergy = 0.50
  }
}

M.delivery = {
  visibleMin = 5,
  visibleMax = 7,
  chance = 0.22,
  minimumWeightKg = 2,
  maximumWeightKg = 250,
  weightDistributionExponent = 1.55,
  minimumDistance = 2000,
  maximumDistance = 25000,
  routeAttempts = 28,
  diversityAttempts = 3,
  fareMultiplier = 0.82,
  weightFareBonusThresholdKg = 15,
  maximumWeightFareBonus = 1.50,
  collisionDamageThreshold = 20,
  minimumImpactDamagePercent = 1,
  maximumImpactDamagePercent = 35,
  impactDamageScale = 4500,
  ratingDamageThresholdPercent = 5
}

M.difficultyPresets = {
  elementary = {
    maxTotalPenalty = 0.50,
    pickupLateBasePenalty = 0.05, pickupLatePenaltyPerSecond = 0.000333,
    maxPickupLatePenalty = 0.12,
    speedToleranceKmh = 15, speedToleranceRatio = 0.25, speedGraceSeconds = 6,
    speedPenaltyRate = 0.00025, maxSpeedPenalty = 0.06,
    collisionDamageScale = 22000, collisionDamageThreshold = 60,
    collisionDamagePenalty = 0.10, collisionEventPenalty = 0.004, maxCollisionPenalty = 0.10,
    longitudinalGThreshold = 0.88, lateralGThreshold = 0.78,
    longitudinalGRelease = 0.55, lateralGRelease = 0.48,
    aggressionEventPenalty = 0.002, aggressionExtraRate = 0.006,
    aggressionExtraMax = 0.004, maxAggressionPenalty = 0.05
  },
  easy = {
    maxTotalPenalty = 0.50,
    pickupLateBasePenalty = 0.05, pickupLatePenaltyPerSecond = 0.000333,
    maxPickupLatePenalty = 0.12,
    speedToleranceKmh = 11, speedToleranceRatio = 0.20, speedGraceSeconds = 4.5,
    speedPenaltyRate = 0.00045, maxSpeedPenalty = 0.10,
    collisionDamageScale = 17000, collisionDamageThreshold = 35,
    collisionDamagePenalty = 0.14, collisionEventPenalty = 0.007, maxCollisionPenalty = 0.14,
    longitudinalGThreshold = 0.74, lateralGThreshold = 0.66,
    longitudinalGRelease = 0.48, lateralGRelease = 0.42,
    aggressionEventPenalty = 0.0035, aggressionExtraRate = 0.01,
    aggressionExtraMax = 0.006, maxAggressionPenalty = 0.08
  },
  standard = {
    maxTotalPenalty = 0.50,
    pickupLateBasePenalty = 0.05, pickupLatePenaltyPerSecond = 0.000333,
    maxPickupLatePenalty = 0.12,
    speedToleranceKmh = 8, speedToleranceRatio = 0.15, speedGraceSeconds = 3,
    speedPenaltyRate = 0.0008, maxSpeedPenalty = 0.15,
    collisionDamageScale = 12000, collisionDamageThreshold = 20,
    collisionDamagePenalty = 0.18, collisionEventPenalty = 0.01, maxCollisionPenalty = 0.20,
    longitudinalGThreshold = 0.62, lateralGThreshold = 0.55,
    longitudinalGRelease = 0.40, lateralGRelease = 0.35,
    aggressionEventPenalty = 0.005, aggressionExtraRate = 0.015,
    aggressionExtraMax = 0.01, maxAggressionPenalty = 0.12
  },
  professional = {
    maxTotalPenalty = 0.50,
    pickupLateBasePenalty = 0.05, pickupLatePenaltyPerSecond = 0.000333,
    maxPickupLatePenalty = 0.12,
    speedToleranceKmh = 4, speedToleranceRatio = 0.08, speedGraceSeconds = 1.5,
    speedPenaltyRate = 0.0018, maxSpeedPenalty = 0.25,
    collisionDamageScale = 8000, collisionDamageThreshold = 10,
    collisionDamagePenalty = 0.24, collisionEventPenalty = 0.02, maxCollisionPenalty = 0.30,
    longitudinalGThreshold = 0.48, lateralGThreshold = 0.42,
    longitudinalGRelease = 0.32, lateralGRelease = 0.28,
    aggressionEventPenalty = 0.01, aggressionExtraRate = 0.025,
    aggressionExtraMax = 0.018, maxAggressionPenalty = 0.20
  }
}

M.phases = {
  inactive = "inactive",
  searching = "searching",
  toFuelStation = "toFuelStation",
  toPickup = "toPickup",
  boarding = "boarding",
  toStop = "toStop",
  stopWaiting = "stopWaiting",
  toDestination = "toDestination",
  passengerStopDemand = "passengerStopDemand",
  passengerForcedExit = "passengerForcedExit",
  driverAbandoning = "driverAbandoning",
  alighting = "alighting",
  complete = "complete",
  error = "error"
}

M.phaseLabels = {
  inactive = "Режим такси выключен",
  searching = "Поиск заказов",
  toFuelStation = "Следуйте к заправке",
  toPickup = "Следуйте к пассажиру",
  boarding = "Пассажир садится",
  toStop = "Следуйте к промежуточной остановке",
  stopWaiting = "Ожидание на остановке",
  toDestination = "Доставьте пассажира",
  passengerStopDemand = "Пассажир требует немедленно остановиться",
  passengerForcedExit = "Пассажир досрочно покидает машину",
  driverAbandoning = "Водитель завершает поездку",
  alighting = "Пассажир выходит",
  complete = "Поездка завершена",
  error = "Заказ недоступен"
}

return M
