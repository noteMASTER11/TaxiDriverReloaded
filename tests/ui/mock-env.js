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
  if (mockParams.get("mockWebAudio") === "1") {
    const soundFiles = [
      "taxidriver_ui_click.mp3", "taxidriver_new_ride.mp3", "taxidriver_offline.mp3",
      "taxidriver_online.mp3", "taxidriver_violation_ping.mp3",
      "taxidriver_passenger_message.mp3", "taxidriver_overspeed.mp3",
    ];
    window.TaxiDriverSoundData = Object.fromEntries(soundFiles.map((fileName) =>
      [fileName, "data:audio/mpeg;base64,AA=="]
    ));
    window.__taxiMockWebAudio = {
      decoded: 0, resumeCalls: 0, starts: [], contextsCreated: 0, stateChanges: 0,
      interrupt() {},
    };
    let audioGestureReceived = false;
    let currentAudioContext = null;
    document.addEventListener("pointerdown", () => { audioGestureReceived = true; }, true);
    class MockAudioContext {
      constructor() {
        this.state = "suspended";
        this.destination = {};
        this.sampleRate = 44100;
        this.listeners = new Map();
        currentAudioContext = this;
        window.__taxiMockWebAudio.contextsCreated += 1;
      }
      decodeAudioData() {
        const buffer = { id: ++window.__taxiMockWebAudio.decoded };
        return Promise.resolve(buffer);
      }
      createBufferSource() {
        const source = {
          buffer: null,
          connect() {},
          start() { window.__taxiMockWebAudio.starts.push(source.buffer && source.buffer.id); },
        };
        return source;
      }
      createBuffer() { return { id: "prime" }; }
      createGain() { return { gain: { value: 1 }, connect() {} }; }
      addEventListener(type, listener) { this.listeners.set(type, listener); }
      removeEventListener(type) { this.listeners.delete(type); }
      dispatchStateChange() {
        window.__taxiMockWebAudio.stateChanges += 1;
        const listener = this.listeners.get("statechange") || this.onstatechange;
        if (listener) listener();
      }
      resume() {
        window.__taxiMockWebAudio.resumeCalls += 1;
        if (!audioGestureReceived) return Promise.reject(new Error("NotAllowedError"));
        this.state = "running";
        this.dispatchStateChange();
        return Promise.resolve();
      }
      close() { this.state = "closed"; return Promise.resolve(); }
    }
    window.__taxiMockWebAudio.interrupt = () => {
      if (!currentAudioContext) return;
      currentAudioContext.state = "interrupted";
      currentAudioContext.dispatchStateChange();
    };
    window.AudioContext = MockAudioContext;
    window.webkitAudioContext = MockAudioContext;
  }

  const settings = {
    language: "en", rememberLanguage: true, difficulty: "standard",
    customDifficulty: {
      speedToleranceKmh: 10, speedGraceSeconds: 4, speedPenaltyStrengthPercent: 100,
      collisionSensitivityPercent: 50, collisionPenaltyStrengthPercent: 100,
      longitudinalGThreshold: 0.65, lateralGThreshold: 0.58,
      aggressionPenaltyStrengthPercent: 100, pickupPenaltyStrengthPercent: 100,
      maxFareReductionPercent: 50, earlyExitRatingLossPercent: 30,
    },
    uiScalePercent: 100, appVolume: 0.65, unitSystem: "metric", timeFormat: "12h",
    penaltyToggles: { speeding: true, collision: true, aggression: true, pickupDelay: true, fuelStop: true, rushBonus: true, cargoDamage: true },
    soundToggles: { click: true, newRide: true, offline: true, online: true, violation: true, message: true, overspeed: true },
    dynamicZoomIntensity: 120, overspeedWarningKmh: 10, economyMultiplier: 1, deliveryOrderSharePercent: 45,
    lanEnabled: true, silentMode: false, showRouteGuidance: true, realisticMode: true,
    randomEventsEnabled: true,
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
    currentVehicle: { available: true, key: "etk800|854t", name: "ETK 854t", preview: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 640 300'%3E%3Cpath fill='%23ffd11a' d='M85 205l42-91q12-27 43-31l251-18q42-3 68 30l63 78 39 16v48H52v-20z'/%3E%3Cpath fill='%23171a1f' d='M182 105l218-16q28-2 47 21l45 56H144z'/%3E%3Ccircle fill='%23252a31' stroke='%23e7ebef' stroke-width='12' cx='164' cy='226' r='43'/%3E%3Ccircle fill='%23252a31' stroke='%23e7ebef' stroke-width='12' cx='494' cy='226' r='43'/%3E%3C/svg%3E", distanceMeters: 12843.7, completedRides: 7, income: 184.25 },
    passengerOnboard: false, deliveryOnboard: false, realisticMode: true,
    shift: { active: false, current: {}, last: { rides: 6, netIncome: 82.40, averageRating: 4.73 } },
    vehicleEnergy: { available: true, energyType: "gasoline", quantity: 13.42, maxQuantity: 55, percent: 24.4, unit: "L", estimatedRangeKm: 128 },
    fuelStation: { available: false, id: "", name: "Gas Station", magic: false, vehicleStopped: true, options: [], balance: 75.15,
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
    fuelEnoughForTrip: true, nextStopDistance: 0, tipAmount: 0, tripEvent: { kind: "none" },
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
    profileVehicles: base(),
    compact: tripState(false),
    nextOffer: Object.assign(tripState(false), { routeProgress: 0.88, nextOffer: Object.assign(offer(9, false), { duration: 5, timeRemaining: 3.8, accepted: false }) }),
    fuelRoute: Object.assign(tripState(false), {
      phase: "toFuelStation", distanceToTarget: 5200, etaMinutes: 8, routeProgress: 0.35,
      fuelDetour: { active: true, hadTrip: true, passengerOnboard: true, stationName: "West Coast Fuel", routeDistance: 5200, penaltyPercent: 2.5, arrived: false },
    }),
    fuel: Object.assign(tripState(false), { fuelStation: {
      available: true, id: "mock-fuel", name: "Gas Station", magic: false, vehicleStopped: true, balance: 75.15,
      options: [{ energyType: "gasoline", unit: "L", currentPercent: 24, currentQuantity: 13.42,
        maxQuantity: 55, missingQuantity: 41.58, affordableQuantity: 28.4, pricePerUnit: 0.92,
        consumptionPer100Km: 10 }],
      refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0,
        duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 },
    } }),
    magicFuel: Object.assign(tripState(false), {
      phase: "toFuelStation",
      fuelDetour: { active: true, hadTrip: true, passengerOnboard: true, stationName: "Magic Fuel", routeDistance: 0, penaltyPercent: 2.5, arrived: true },
      fuelStation: {
        available: true, id: "taxiDriverMagicFuel", name: "Magic Fuel", magic: true,
        vehicleStopped: true, balance: 75.15,
        options: [{ energyType: "gasoline", unit: "L", currentPercent: 24, currentQuantity: 13.42,
          maxQuantity: 55, missingQuantity: 41.58, affordableQuantity: 41.58, pricePerUnit: 0.93,
          consumptionPer100Km: 10 }],
        refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0,
          duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 },
      },
    }),
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
