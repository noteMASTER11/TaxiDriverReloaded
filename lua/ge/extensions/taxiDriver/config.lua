-- Static TaxiDriver configuration. Runtime state stays in the main extension;
-- constants and balance presets live here so they can be reviewed separately.
local M = {}

M.supportedLanguages = {
  en = true, de = true, fr = true, es = true,
  pl = true, uk = true, ru = true
}

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

M.offer = {
  initialDelay = 1.5,
  intervalMin = 1.2,
  intervalMax = 2.2,
  generationStepInterval = 0.02,
  semanticScanBatchSize = 6,
  semanticCandidateAttempts = 40,
  randomRouteAttempts = 24,
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
