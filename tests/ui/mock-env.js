(() => {
  "use strict";
  const mockParams = new URLSearchParams(window.location.search);
  window.beamng = { ingame: mockParams.get("external") !== "1" };
  window.angular.module("beamng.apps", []);
  window.__taxiPlayedSounds = [];
  window.Audio = class MockAudio {
    constructor(source) { this.src = source; this.volume = 1; this.currentTime = 0; }
    play() { window.__taxiPlayedSounds.push(this.src); return Promise.resolve(); }
    pause() {}
  };

  const settings = {
    language: "en", rememberLanguage: true, difficulty: "standard",
    customDifficulty: {
      speedToleranceKmh: 10, speedGraceSeconds: 4, speedPenaltyStrengthPercent: 100,
      collisionSensitivityPercent: 50, collisionPenaltyStrengthPercent: 100,
      longitudinalGThreshold: 0.65, lateralGThreshold: 0.58,
      aggressionPenaltyStrengthPercent: 100, pickupPenaltyStrengthPercent: 100,
      maxFareReductionPercent: 50, earlyExitRatingLossPercent: 30,
    },
    fontBoost: 2, appVolume: 0.65, unitSystem: "metric", timeFormat: "12h",
    penaltyToggles: { speeding: true, collision: true, aggression: true, pickupDelay: true, fuelStop: true, rushBonus: true, cargoDamage: true },
    soundToggles: { click: true, newRide: true, offline: true, online: true, violation: true, message: true, overspeed: true },
    dynamicZoomIntensity: 120, overspeedWarningKmh: 10, economyMultiplier: 1, deliveryOrderSharePercent: 45,
    lanEnabled: true, silentMode: false, showRouteGuidance: true, realisticMode: true,
  };

  const offer = (id, delivery = false) => ({
    id, passengerName: delivery ? "" : ["Amelia Howard", "Lucas Roberts", "Grace Lewis"][id % 3],
    isDelivery: delivery, cargoWeightKg: delivery ? 138 + id : 0,
    isRush: id % 4 === 0, isMultiStop: !delivery && id % 5 === 0, stopCount: id % 5 === 0 ? 2 : 0,
    passengerCalmness: 25 + id * 5, pickupDistance: 700 + id * 120,
    rideDistance: 3600 + id * 430, etaMinutes: 7 + id, estimatedFare: 8.5 + id * 1.35,
    pickupWaitSeconds: 240, ratingBonusPercent: 9, ratingBonusAmount: 0.95,
  });

  const base = () => ({
    active: false, phase: "inactive", phaseLabel: "", message: "", balance: 75.15,
    rating: 4.37, ratingCount: 18, completedRides: 18,
    driverProfile: { fullName: "Alex Morgan", avatar: "🙂" },
    passengerOnboard: false, deliveryOnboard: false, realisticMode: true,
    vehicleEnergy: { available: true, energyType: "gasoline", quantity: 13.42, maxQuantity: 55, percent: 24.4, unit: "L", estimatedRangeKm: 128 },
    fuelStation: { available: false, id: "", name: "Gas Station", options: [], balance: 75.15,
      refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0, duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 } },
    fuelDetour: { active: false, hadTrip: false, passengerOnboard: false, stationName: "", routeDistance: 0, penaltyPercent: 0, arrived: false },
    lan: { enabled: true, connected: 0, address: "192.168.93.143", port: 8084,
      url: "http://192.168.93.143:8084/?token=6a574f0844bfa68fe570" },
    settings, settingsNeedsLegacyImport: false, offers: [], offerTargetCount: 12,
    nextOffer: null, notification: null, penaltyEvents: [], activeTripId: 0,
    passengerName: "", isDelivery: false, cargoWeightKg: 0, cargoWeightBonusPercent: 0,
    cargoWeightBonusAmount: 0, cargoDamagePercent: 0, passengerCalmness: 64,
    passengerInitialCalmness: 55, passengerMoodMaximum: 95, passengerMoodChangeId: 0,
    passengerMoodChangeDirection: "", passengerMoodChangeAmount: 0, passengerStressPercent: 12,
    forcedExitDuration: 5, forcedExitRemaining: 0, estimatedFare: 14.8, adjustedFare: 13.92,
    finalFare: 0, rideRating: 0, rideDistance: 9200, distanceToTarget: 3400,
    etaMinutes: 6, rideEtaMinutes: 14, routeProgress: 0.57, progressLabel: "tripProgress",
    pickupWaitLimit: 300, pickupTimeRemaining: 184, pickupLate: false, pickupLateSeconds: 0,
    ratingBonusPercent: 10.5, ratingBonusAmount: 1.38, isMultiStop: false, stopCount: 0,
    currentStopIndex: 0, stopProgressMarkers: [], stopWaitDuration: 10, stopWaitRemaining: 0,
    rushOrder: false, rushBonusActive: false, rushBonusLost: false, rushBonusAmount: 0,
    rushTimeLimit: 0, rushTimeRemaining: 0, penaltyPercent: 5.9, speedLimit: 50,
    currentSpeed: 42, penalties: { speedingPercent: 2.1, collisionPercent: 0,
      aggressionPercent: 3.8, pickupPercent: 0, fuelStopPercent: 0,
      speedingEvents: 1, collisions: 0, aggressionEvents: 2 },
  });

  const tripState = (delivery = false) => Object.assign(base(), {
    active: true, phase: "toDestination", passengerOnboard: !delivery,
    deliveryOnboard: delivery, activeTripId: delivery ? 202 : 101,
    passengerName: delivery ? "" : "Victoria Lewis", isDelivery: delivery,
    cargoWeightKg: delivery ? 234 : 0, cargoWeightBonusPercent: delivery ? 140 : 0,
    cargoWeightBonusAmount: delivery ? 8.12 : 0, cargoDamagePercent: delivery ? 7.4 : 0,
    penaltyPercent: delivery ? 7.4 : 5.9,
    penaltyEvents: delivery ? [
      { id: 1, type: "cargoDamage", penaltyPercent: 7.4, detail: "Impact damage" },
    ] : [
      { id: 1, type: "speeding", penaltyPercent: 2.1, detail: "Speed 67 km/h" },
      { id: 2, type: "aggression", penaltyPercent: 1.8, detail: "Peak load 0.82 g" },
      { id: 3, type: "aggression", penaltyPercent: 2.0, detail: "Peak load 0.89 g" },
    ],
  });

  window.__taxiScenarios = {
    home: base(),
    orders: Object.assign(base(), { active: true, phase: "searching", offers: Array.from({ length: 12 }, (_, index) => offer(index + 1, index % 3 === 0)) }),
    trip: tripState(false),
    delivery: tripState(true),
    overspeed: Object.assign(tripState(false), { speedLimit: 50, currentSpeed: 72 }),
    boarding: Object.assign(tripState(false), { phase: "boarding" }),
    forcedExit: Object.assign(tripState(false), { phase: "passengerForcedExit", forcedExitRemaining: 3.2 }),
    settings: base(),
    settingsConnection: base(),
    profile: base(),
    compact: tripState(false),
    nextOffer: Object.assign(tripState(false), { routeProgress: 0.88, nextOffer: Object.assign(offer(9, false), { duration: 5, timeRemaining: 3.8, accepted: false }) }),
    fuelRoute: Object.assign(tripState(false), {
      phase: "toFuelStation", distanceToTarget: 5200, etaMinutes: 8, routeProgress: 0.35,
      fuelDetour: { active: true, hadTrip: true, passengerOnboard: true, stationName: "West Coast Fuel", routeDistance: 5200, penaltyPercent: 2.5, arrived: false },
    }),
    fuel: Object.assign(tripState(false), { fuelStation: {
      available: true, id: "mock-fuel", name: "Gas Station", balance: 75.15,
      options: [{ energyType: "gasoline", unit: "L", currentPercent: 24, currentQuantity: 13.42,
        missingQuantity: 41.58, affordableQuantity: 28.4, pricePerUnit: 0.92 }],
      refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0,
        duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 },
    } }),
  };

  window.bngApi = {
    serializeToLua: (value) => JSON.stringify(value),
    engineLua(command, callback) {
      window.__taxiEngineLuaCommands = window.__taxiEngineLuaCommands || [];
      window.__taxiEngineLuaCommands.push(command);
      const cheatRating = command.match(/cheatSetRating\(["']?([0-9.]+)["']?\)/);
      if (cheatRating) {
        window.dispatchEvent(new CustomEvent("taxi-test-cheat-rating", {
          detail: Number(cheatRating[1]),
        }));
      }
      if (typeof callback === "function") {
        if (cheatRating) callback(Number(cheatRating[1]));
        else if (command.includes("AudioUiVol")) callback(1);
        else callback(null);
      }
      if (command.includes("requestHudState")) setTimeout(() => window.__emitTaxiState?.(), 0);
    },
  };
})();
