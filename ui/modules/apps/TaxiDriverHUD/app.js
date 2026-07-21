const loadTaxiDriverI18n = () => {
  try {
    const revision = typeof window !== "undefined" && window.TaxiDriverAssetRevision
      ? `?v=${encodeURIComponent(window.TaxiDriverAssetRevision)}` : "";
    const request = new XMLHttpRequest();
    request.open("GET", `/ui/modules/apps/TaxiDriverHUD/locales.json${revision}`, false);
    request.send(null);
    if ((request.status === 0 || (request.status >= 200 && request.status < 300)) &&
        request.responseText) {
      return JSON.parse(request.responseText);
    }
  } catch (error) {
    console.error("TaxiDriverHUD: unable to load locales.json", error);
  }
  return { en: {} };
};
angular.module("beamng.apps").directive("taxiDriverHud", [
  function () {
    const revision = typeof window !== "undefined" && window.TaxiDriverAssetRevision
      ? `?v=${encodeURIComponent(window.TaxiDriverAssetRevision)}` : "";
    return {
      templateUrl: `/ui/modules/apps/TaxiDriverHUD/app.html${revision}`,
      replace: false,
      restrict: "E",
      scope: true,
      controllerAs: "hud",
      controller: function ($scope, $element) {
        const externalPhoneMode = typeof beamng !== "undefined" && beamng.ingame === false;
        const externalSessionToken = externalPhoneMode
          ? (new URLSearchParams(window.location.search).get("token") || "").replace(/[^a-fA-F0-9]/g, "")
          : "";
        $scope.externalPhoneMode = externalPhoneMode;
        $scope.vehicleConfigSuspended = false;
        const i18n = loadTaxiDriverI18n();
        const settingsKey = "taxiDriverHUD.settings.v1";
        const languages = [
          { code: "en", label: "English" }, { code: "de", label: "Deutsch" },
          { code: "fr", label: "Français" }, { code: "es", label: "Español" },
          { code: "it", label: "Italiano" }, { code: "pl", label: "Polski" },
          { code: "uk", label: "Українська" },
          { code: "ru", label: "Русский" },
          { code: "zh-CN", label: "简体中文" },
        ];
        const difficulties = ["elementary", "easy", "standard", "professional", "custom"];
        const aiDriverPresetNames = ["novice", "cautious", "balanced", "assertive", "racer", "custom"];
        const aiDriverDefaults = {
          aggressionPercent: 30, followingTimeGap: 2.2, brakingDeceleration: 2.8,
          stuckDelaySeconds: 15, obeySpeedLimits: true, obeyTrafficSignals: true,
          allowOvertaking: true, laneChangeClearancePercent: 100,
          allowOncomingRecovery: true, allowReverseRecovery: true,
          recoveryMaxAttempts: 3, finalApproachSpeedKmh: 12,
        };
        const aiDriverPresetValues = {
          novice: Object.assign({}, aiDriverDefaults, {
            aggressionPercent: 15, followingTimeGap: 3.5, brakingDeceleration: 2,
            stuckDelaySeconds: 25, allowOvertaking: false, laneChangeClearancePercent: 160,
            allowOncomingRecovery: false, recoveryMaxAttempts: 2, finalApproachSpeedKmh: 7,
          }),
          cautious: Object.assign({}, aiDriverDefaults, {
            aggressionPercent: 25, followingTimeGap: 3, brakingDeceleration: 2.4,
            stuckDelaySeconds: 20, allowOvertaking: false, laneChangeClearancePercent: 140,
            allowOncomingRecovery: false, finalApproachSpeedKmh: 9,
          }),
          balanced: Object.assign({}, aiDriverDefaults),
          assertive: Object.assign({}, aiDriverDefaults, {
            aggressionPercent: 50, followingTimeGap: 1.7, brakingDeceleration: 3.4,
            stuckDelaySeconds: 12, obeySpeedLimits: false, laneChangeClearancePercent: 75,
            recoveryMaxAttempts: 4, finalApproachSpeedKmh: 16,
          }),
          racer: Object.assign({}, aiDriverDefaults, {
            aggressionPercent: 80, followingTimeGap: 1.2, brakingDeceleration: 4.5,
            stuckDelaySeconds: 8, obeySpeedLimits: false, obeyTrafficSignals: false,
            laneChangeClearancePercent: 50, recoveryMaxAttempts: 5,
            finalApproachSpeedKmh: 20,
          }),
        };
        const customDifficultyDefaults = {
          speedToleranceKmh: 10,
          speedGraceSeconds: 4,
          speedPenaltyStrengthPercent: 100,
          collisionSensitivityPercent: 50,
          collisionPenaltyStrengthPercent: 100,
          longitudinalGThreshold: 0.65,
          lateralGThreshold: 0.58,
          aggressionPenaltyStrengthPercent: 100,
          pickupPenaltyStrengthPercent: 100,
          maxFareReductionPercent: 50,
          earlyExitRatingLossPercent: 30,
        };
        const customDifficultyRanges = {
          speedToleranceKmh: [0, 30], speedGraceSeconds: [0, 10],
          speedPenaltyStrengthPercent: [0, 250], collisionSensitivityPercent: [0, 100],
          collisionPenaltyStrengthPercent: [0, 250], longitudinalGThreshold: [0.30, 1.20],
          lateralGThreshold: [0.30, 1.20], aggressionPenaltyStrengthPercent: [0, 250],
          pickupPenaltyStrengthPercent: [0, 200], maxFareReductionPercent: [10, 75],
          earlyExitRatingLossPercent: [0, 60],
        };
        const normalizeCustomDifficulty = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const result = {};
          Object.keys(customDifficultyDefaults).forEach((key) => {
            const numeric = Number(value[key]);
            const range = customDifficultyRanges[key];
            result[key] = Math.max(
              range[0],
              Math.min(range[1], Number.isFinite(numeric) ? numeric : customDifficultyDefaults[key])
            );
          });
          return result;
        };
        const normalizePenaltyToggles = (source) => {
          const value = source && typeof source === "object" ? source : {};
          return {
            speeding: value.speeding !== false,
            collision: value.collision !== false,
            aggression: value.aggression !== false,
            pickupDelay: value.pickupDelay !== false,
            fuelStop: value.fuelStop !== false,
            rushBonus: value.rushBonus !== false,
            cargoDamage: value.cargoDamage !== false,
          };
        };
        const normalizeSoundToggles = (source) => {
          const value = source && typeof source === "object" ? source : {};
          return {
            click: value.click !== false,
            newRide: value.newRide !== false,
            offline: value.offline !== false,
            online: value.online !== false,
            violation: value.violation !== false,
            message: value.message !== false,
            overspeed: value.overspeed !== false,
          };
        };
        const normalizeAiDriver = (source) => {
          const hasSource = source && typeof source === "object";
          const value = hasSource ? source : {};
          const clampNumber = (input, fallback, minimum, maximum) => {
            const numeric = Number(input);
            return Math.max(minimum, Math.min(maximum, Number.isFinite(numeric) ? numeric : fallback));
          };
          const preset = aiDriverPresetNames.includes(value.preset)
            ? value.preset : (hasSource && Object.keys(value).length ? "custom" : "balanced");
          const base = preset === "custom" ? aiDriverDefaults : aiDriverPresetValues[preset];
          const settings = preset === "custom" ? value : base;
          const legacyRules = settings.obeyTrafficRules;
          return {
            preset,
            obeySpeedLimits: settings.obeySpeedLimits === undefined
              ? legacyRules !== false : settings.obeySpeedLimits !== false,
            obeyTrafficSignals: settings.obeyTrafficSignals === undefined
              ? legacyRules !== false : settings.obeyTrafficSignals !== false,
            allowOvertaking: settings.allowOvertaking !== false,
            allowOncomingRecovery: settings.allowOncomingRecovery !== false,
            allowReverseRecovery: settings.allowReverseRecovery !== false,
            aggressionPercent: clampNumber(settings.aggressionPercent, base.aggressionPercent, 10, 80),
            followingTimeGap: clampNumber(settings.followingTimeGap, base.followingTimeGap, 1.2, 3.5),
            brakingDeceleration: clampNumber(settings.brakingDeceleration, base.brakingDeceleration, 1.5, 4.5),
            stuckDelaySeconds: clampNumber(settings.stuckDelaySeconds, base.stuckDelaySeconds, 8, 30),
            laneChangeClearancePercent: clampNumber(settings.laneChangeClearancePercent,
              base.laneChangeClearancePercent, 50, 175),
            recoveryMaxAttempts: Math.round(clampNumber(settings.recoveryMaxAttempts,
              base.recoveryMaxAttempts, 1, 5)),
            finalApproachSpeedKmh: clampNumber(settings.finalApproachSpeedKmh,
              base.finalApproachSpeedKmh, 5, 20),
          };
        };
        const normalizeFleet = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const number = (key, fallback, minimum, maximum) => {
            const numeric = Number(value[key]);
            return Math.max(minimum, Math.min(maximum, Number.isFinite(numeric) ? numeric : fallback));
          };
          const minimumJobDistanceKm = number("minimumJobDistanceKm", 1.5, 0.5, 20);
          let passengerJobs = value.passengerJobs !== false;
          let deliveryJobs = value.deliveryJobs !== false;
          if (!passengerJobs && !deliveryJobs) passengerJobs = true;
          return {
            enabled: value.enabled !== false,
            aiPreset: ["careful", "standard", "fast"].includes(value.aiPreset) ? value.aiPreset : "standard",
            ownerSharePercent: Math.round(number("ownerSharePercent", 35, 10, 90)),
            hiringFee: Math.round(number("hiringFee", 75, 0, 1000)),
            wagePerTenMinutes: Math.round(number("wagePerTenMinutes", 12, 0, 250)),
            maxDrivers: Math.round(number("maxDrivers", 6, 1, 12)),
            worldLabelDistance: Math.round(number("worldLabelDistance", 400, 50, 1000)),
            incomeMultiplier: number("incomeMultiplier", 1, 0.25, 3),
            minimumJobDistanceKm,
            maximumJobDistanceKm: number("maximumJobDistanceKm", 8, minimumJobDistanceKm, 50),
            passengerJobs, deliveryJobs,
          };
        };
        let persisted = {};
        let legacySettingsFound = false;
        try {
          const legacyValue = localStorage.getItem(settingsKey);
          if (legacyValue) {
            const parsed = JSON.parse(legacyValue);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              persisted = parsed;
              // LAN sharing is session-only and must never be restored by the
              // legacy browser settings cache.
              persisted.lanEnabled = false;
              legacySettingsFound = true;
            }
          }
        } catch (_) { persisted = {}; }
        const initialLanguage = persisted.rememberLanguage && i18n[persisted.language] ? persisted.language : "en";
        const initialDifficulty = difficulties.includes(persisted.difficulty) ? persisted.difficulty : "standard";
        const savedUiScalePercent = Number(persisted.uiScalePercent);
        const legacyFontBoost = Number(persisted.fontBoost);
        const initialUiScalePercent = Math.max(80, Math.min(180, Math.round(
          (Number.isFinite(savedUiScalePercent)
            ? savedUiScalePercent
            : (Number.isFinite(legacyFontBoost) ? 100 + (legacyFontBoost - 2) * 10 : 100)) / 10
        ) * 10));
        const savedAppVolume = persisted.appVolume === undefined ? 0.65 : Number(persisted.appVolume);
        const initialAppVolume = Math.max(0, Math.min(1, Number.isFinite(savedAppVolume) ? savedAppVolume : 0.65));
        const initialSilentMode = persisted.silentMode === true;
        const initialShowRouteGuidance = persisted.showRouteGuidance !== false;
        const initialRealisticMode = persisted.realisticMode === true;
        const initialRandomEventsEnabled = persisted.randomEventsEnabled === true;
        const initialLanEnabled = false;
        const initialExternalMapEnabled = persisted.externalMapEnabled !== false;
        const initialExternalTerrainEnabled = persisted.externalTerrainEnabled !== false;
        const initialExternalMapQuality = ["eco", "balanced", "smooth"].includes(persisted.externalMapQuality)
          ? persisted.externalMapQuality : "balanced";
        const initialUnitSystem = persisted.unitSystem === "imperial" ? "imperial" : "metric";
        const initialTimeFormat = persisted.timeFormat === "24h" ? "24h" : "12h";
        const savedDynamicZoomIntensity = Number(persisted.dynamicZoomIntensity);
        const initialDynamicZoomIntensity = Math.max(0, Math.min(200,
          Number.isFinite(savedDynamicZoomIntensity) ? savedDynamicZoomIntensity : 100));
        const savedOverspeedWarningKmh = Number(persisted.overspeedWarningKmh);
        const initialOverspeedWarningKmh = Math.max(0, Math.min(30,
          Number.isFinite(savedOverspeedWarningKmh) ? savedOverspeedWarningKmh : 10));
        const savedEconomyMultiplier = Number(persisted.economyMultiplier);
        const initialEconomyMultiplier = Math.max(0.25, Math.min(5,
          Number.isFinite(savedEconomyMultiplier) ? savedEconomyMultiplier : 1));
        const savedDeliveryOrderShare = Number(persisted.deliveryOrderSharePercent);
        const initialDeliveryOrderShare = Math.max(0, Math.min(100,
          Number.isFinite(savedDeliveryOrderShare) ? savedDeliveryOrderShare : 50));
        const initialUnlimitedRouteDistance = persisted.unlimitedRouteDistance === true;

        $scope.languages = languages;
        $scope.difficulties = difficulties;
        $scope.aiDriverPresets = aiDriverPresetNames;
        $scope.aiManeuversOpen = false;
        $scope.language = initialLanguage;
        $scope.settingsOpen = false;
        $scope.fleetOpen = false;
        $scope.settingsSaved = false;
        $scope.settingsSections = {
          general: true, gameplay: false, aiDriver: false, fleet: false, navigation: false, audio: false, connectivity: false, cheats: false,
        };
        $scope.customDifficultyGroups = [
          { title: "customSpeed", controls: [
            { key: "speedToleranceKmh", label: "customSpeedTolerance", min: 0, max: 30, step: 1, unit: "kmh", decimals: 0 },
            { key: "speedGraceSeconds", label: "customSpeedGrace", min: 0, max: 10, step: 0.5, unit: "seconds", decimals: 1 },
            { key: "speedPenaltyStrengthPercent", label: "customSpeedPenalty", min: 0, max: 250, step: 5, unit: "percent", decimals: 0 },
          ] },
          { title: "customImpacts", controls: [
            { key: "collisionSensitivityPercent", label: "customCollisionSensitivity", min: 0, max: 100, step: 5, unit: "percent", decimals: 0 },
            { key: "collisionPenaltyStrengthPercent", label: "customCollisionPenalty", min: 0, max: 250, step: 5, unit: "percent", decimals: 0 },
            { key: "longitudinalGThreshold", label: "customLongitudinalG", min: 0.30, max: 1.20, step: 0.05, unit: "g", decimals: 2 },
            { key: "lateralGThreshold", label: "customLateralG", min: 0.30, max: 1.20, step: 0.05, unit: "g", decimals: 2 },
            { key: "aggressionPenaltyStrengthPercent", label: "customAggressionPenalty", min: 0, max: 250, step: 5, unit: "percent", decimals: 0 },
          ] },
          { title: "customEconomy", controls: [
            { key: "pickupPenaltyStrengthPercent", label: "customPickupPenalty", min: 0, max: 200, step: 5, unit: "percent", decimals: 0 },
            { key: "maxFareReductionPercent", label: "customMaxReduction", min: 10, max: 75, step: 5, unit: "percent", decimals: 0 },
            { key: "earlyExitRatingLossPercent", label: "customEarlyExit", min: 0, max: 60, step: 5, unit: "percent", decimals: 0 },
          ] },
        ];
        $scope.penaltyToggleOptions = [
          { key: "speeding", label: "penalty_speeding", help: "penaltyToggleSpeedingHelp" },
          { key: "collision", label: "penalty_collision", help: "penaltyToggleCollisionHelp" },
          { key: "aggression", label: "penalty_aggression", help: "penaltyToggleAggressionHelp" },
          { key: "pickupDelay", label: "penalty_pickupDelay", help: "penaltyTogglePickupHelp" },
          { key: "fuelStop", label: "penalty_fuelStop", help: "penaltyToggleFuelStopHelp" },
          { key: "rushBonus", label: "penalty_bonus", help: "penaltyToggleRushHelp" },
          { key: "cargoDamage", label: "penalty_cargoDamage", help: "penaltyToggleCargoHelp" },
        ];
        $scope.soundToggleOptions = [
          { key: "click", label: "sound_click" },
          { key: "newRide", label: "sound_newRide" },
          { key: "online", label: "sound_online" },
          { key: "offline", label: "sound_offline" },
          { key: "violation", label: "sound_violation" },
          { key: "message", label: "sound_message" },
          { key: "overspeed", label: "sound_overspeed" },
        ];
        $scope.cheatRating = 5;
        $scope.cheatEnergyPercent = 0;
        $scope.cheatEnergyDraft = 0;
        $scope.cheatResetArmed = false;
        $scope.profileOpen = false;
        $scope.profileTab = "identity";
        $scope.profileSaved = false;
        $scope.reviewPage = 1;
        $scope.reviewsPerPage = 6;
        $scope.offlineHoldProgress = 0;
        $scope.offlineConfirmOpen = false;
        $scope.phoneMinimized = false;
        $scope.localPhoneOpen = true;
        $scope.phoneToast = null;
        $scope.passengerChat = null;
        $scope.passengerMoodFlash = "";
        $scope.nextOfferAcceptedVisible = false;
        $scope.fuelStationOpen = false;
        $scope.shiftHistoryOpen = false;
        $scope.selectedFuelType = "";
        $scope.refuel = { amount: 0 };
        $scope.settings = {
          language: initialLanguage,
          rememberLanguage: persisted.rememberLanguage === true,
          difficulty: initialDifficulty,
          customDifficulty: normalizeCustomDifficulty(persisted.customDifficulty),
          uiScalePercent: initialUiScalePercent,
          appVolume: initialAppVolume,
          unitSystem: initialUnitSystem,
          timeFormat: initialTimeFormat,
          penaltyToggles: normalizePenaltyToggles(persisted.penaltyToggles),
          soundToggles: normalizeSoundToggles(persisted.soundToggles),
          dynamicZoomIntensity: initialDynamicZoomIntensity,
          overspeedWarningKmh: initialOverspeedWarningKmh,
          economyMultiplier: initialEconomyMultiplier,
          deliveryOrderSharePercent: initialDeliveryOrderShare,
          unlimitedRouteDistance: initialUnlimitedRouteDistance,
          lanEnabled: initialLanEnabled,
          externalMapEnabled: initialExternalMapEnabled,
          externalTerrainEnabled: initialExternalTerrainEnabled,
          externalMapQuality: initialExternalMapQuality,
          silentMode: initialSilentMode,
          showRouteGuidance: initialShowRouteGuidance,
          realisticMode: initialRealisticMode,
          randomEventsEnabled: initialRandomEventsEnabled,
          aiDebugLogging: persisted.aiDebugLogging === true,
          aiDriver: normalizeAiDriver(persisted.aiDriver),
          fleet: normalizeFleet(persisted.fleet),
          godMode: persisted.godMode === true,
          debugLogging: persisted.debugLogging !== false,
        };
        $scope.driverProfile = { fullName: "John Doe", birthDate: "", avatar: "🙂" };
        $scope.profileDraft = Object.assign({}, $scope.driverProfile);
        $scope.profileProgress = {
          reviews: [], ratingHistory: [], balanceHistory: [], aiRideHistory: [],
          balance: 0, rating: 5, completedRides: 0, aiRideCount: 0,
        };
        $scope.profileReviews = [];
        $scope.profileVehicles = [];
        $scope.vehicleSort = "distance";
        $scope.offerSort = "fare";
        $scope.offerSortMenuOpen = false;
        $scope.offerSortOptions = [
          { value: "fare", label: "sortFare" },
          { value: "pickup", label: "sortPickup" },
          { value: "duration", label: "sortDuration" },
          { value: "perKm", label: "sortPerKm" },
        ];
        $scope.penaltiesExpanded = false;
        $scope.avatarOptions = [
          "🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔",
          "👨‍🦰", "👩‍🦰", "👨‍🦱", "👩‍🦱", "👨‍🦳", "👩‍🦳", "🧑‍✈️", "🧑‍💼",
          "🧑‍🔧", "🦸", "🥷", "🤠", "🧢", "🎩", "🚕", "🏁",
          "🐻", "🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐧",
        ];

        $scope.t = (key, values) => {
          const dictionary = i18n[$scope.language] || i18n.en;
          let text = dictionary[key] || i18n.en[key] || key;
          Object.keys(values || {}).forEach((name) => {
            text = text.split(`{${name}}`).join(String(values[name]));
          });
          return text;
        };

        const emptyPenalties = () => ({
          speedingPercent: 0,
          collisionPercent: 0,
          aggressionPercent: 0,
          pickupPercent: 0,
          speedingEvents: 0,
          collisions: 0,
          aggressionEvents: 0,
        });

        $scope.state = {
          active: false,
          phase: "inactive",
          phaseLabel: "",
          message: "",
          balance: 0,
          rating: 5,
          ratingCount: 0,
          completedRides: 0,
          driverProfile: { fullName: "John Doe", avatar: "🙂" },
          currentVehicle: { available: false, key: "", name: "", preview: "", distanceMeters: 0, completedRides: 0, income: 0 },
          passengerOnboard: false,
          deliveryOnboard: false,
          realisticMode: false,
          shift: { active: false, current: {}, last: {} },
          shiftHistory: { items: [], restoring: false, restoringId: 0 },
          fleet: { enabled: true, activeDrivers: 0, maxDrivers: 6, hiringFee: 75, wagePerTenMinutes: 12, ownerSharePercent: 35, stats: {}, drivers: [], markers: [], trafficCandidates: [], garage: [] },
          vehicleEnergy: { available: false, energyType: "", quantity: 0, maxQuantity: 0, percent: 0, unit: "", estimatedRangeKm: 0 },
          fuelStation: {
            available: false, id: "", name: "", magic: false, vehicleStopped: false, options: [], balance: 0,
            refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0, duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 },
          },
          fuelDetour: { active: false, hadTrip: false, passengerOnboard: false, stationName: "", routeDistance: 0, penaltyPercent: 0, arrived: false },
          autopilot: { available: false, enabled: false, suspended: false, status: "off", reason: "", stuckSeconds: 0, recoveryAttempt: 0 },
          lan: { enabled: false, connected: 0, address: "", port: 8085, url: "" },
          offlinePenaltyExtraPercent: 30,
          offlinePenaltyRatingLoss: 2.5,
          offlinePenaltyFinalRating: 2.5,
          offers: [],
          offerTargetCount: 10,
          penaltyEvents: [],
          activeTripId: 0,
          passengerName: "",
          isDelivery: false,
          cargoWeightKg: 0,
          cargoWeightBonusPercent: 0,
          cargoWeightBonusAmount: 0,
          cargoDamagePercent: 0,
          passengerCalmness: 50,
          passengerInitialCalmness: 50,
          passengerMoodMaximum: 90,
          passengerMoodChangeId: 0,
          passengerMoodChangeDirection: "",
          passengerMoodChangeAmount: 0,
          passengerStressPercent: 0,
          forcedExitDuration: 5,
          forcedExitRemaining: 0,
          earlyExitRatingLossPercent: 0,
          driverAbandonmentRatingLoss: 0,
          driverAbandonmentExtraPercent: 0,
          estimatedFare: 0,
          adjustedFare: 0,
          finalFare: 0,
          rideRating: 0,
          rideDistance: 0,
          distanceToTarget: 0,
          etaMinutes: 0,
          rideEtaMinutes: 0,
          pickupWaitLimit: 0,
          pickupTimeRemaining: 0,
          pickupLate: false,
          pickupLateSeconds: 0,
          ratingBonusPercent: 0,
          ratingBonusAmount: 0,
          isMultiStop: false,
          stopCount: 0,
          currentStopIndex: 0,
          stopProgressMarkers: [],
          stopWaitDuration: 10,
          stopWaitRemaining: 0,
          routeProgress: 0,
          progressLabel: "",
          rushOrder: false,
          rushBonusActive: false,
          rushBonusLost: false,
          rushBonusAmount: 0,
          rushTimeLimit: 0,
          rushTimeRemaining: 0,
          penaltyPercent: 0,
          fuelEnoughForTrip: false,
          tipAmount: 0,
          nextStopDistance: 0,
          tripEvent: { kind: "none" },
          speedLimit: 0,
          currentSpeed: 0,
          nextOffer: null,
          penalties: emptyPenalties(),
        };
        $scope.stars = [1, 2, 3, 4, 5];

        const ExternalAudioContext = window.AudioContext || window.webkitAudioContext;
        const externalWebAudioEnabled = externalPhoneMode &&
          typeof ExternalAudioContext === "function" && window.TaxiDriverSoundData;
        const createAppAudioPool = (fileName, volume, size) => {
          const players = [];
          const embeddedSource = externalPhoneMode && window.TaxiDriverSoundData
            ? window.TaxiDriverSoundData[fileName]
            : null;
          const source = embeddedSource || `/ui/modules/apps/TaxiDriverHUD/sounds/${fileName}`;
          if (!externalWebAudioEnabled) {
            for (let index = 0; index < size; index += 1) {
              const audio = new Audio(source);
              audio.preload = "auto";
              audio.volume = volume;
              players.push(audio);
            }
          }
          return { players, cursor: 0, baseVolume: volume, fileName, source, size };
        };
        const appAudio = {
          click: createAppAudioPool("taxidriver_ui_click.mp3", 0.52, 3),
          newRide: createAppAudioPool("taxidriver_new_ride.mp3", 0.78, 2),
          offline: createAppAudioPool("taxidriver_offline.mp3", 0.75, 2),
          online: createAppAudioPool("taxidriver_online.mp3", 0.75, 2),
          violation: createAppAudioPool("taxidriver_violation_ping.mp3", 0.7, 3),
          message: createAppAudioPool("taxidriver_passenger_message.mp3", 0.72, 3),
          overspeed: createAppAudioPool("taxidriver_overspeed.mp3", 0.72, 2),
        };
        let externalAudioContext = null;
        let externalAudioPreparePromise = null;
        let externalAudioUnlocked = false;
        let externalAudioActivated = false;
        let externalAudioPrimeStarted = false;
        let externalAudioQueue = [];
        const externalAudioBuffers = new Map();
        const externalAudioDecodeFailures = new Set();
        const externalAudioQueueTtlMs = 30000;
        const externalAudioQueueLimit = 24;
        const externalSilentAudioSource =
          "data:audio/wav;base64,UklGRiUAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQEAAACA";
        let externalHtmlAudioUnlocked = false;
        let externalHtmlAudioUnlockPromise = null;
        let externalHtmlAudioCursor = 0;
        const externalHtmlAudioPlayers = [];
        if (externalPhoneMode) {
          for (let index = 0; index < 4; index += 1) {
            try {
              const audio = new Audio(externalSilentAudioSource);
              audio.preload = "auto";
              externalHtmlAudioPlayers.push(audio);
            } catch (_) {}
          }
        }
        const passengerEmojiMoods = [
          {
            id: "cheerful",
            messages: ["☀️ 😊 ✨", "🌈 😄 🙌", "🎶 🚕 😎", "🌻 😁 💛", "🍀 😊 🛣️", "🌤️ 😄 🎵"],
          },
          {
            id: "sad",
            messages: ["🌧️ 😔 💭", "☁️ 😢 🫶", "🥀 😞 🕰️", "🌙 😔 💙", "🫥 🌧️ 🪟", "💧 😢 🌫️"],
          },
          {
            id: "excited",
            messages: ["🚕 🤩 🎉", "⚡ 😆 🙌", "🛣️ 🔥 😎", "🎊 🥳 ✨", "🏁 🤩 💫", "🚀 😄 🎶"],
          },
          {
            id: "sleepy",
            messages: ["🌙 😴 💤", "☕ 🥱 ⏳", "🛌 😪 🌧️", "🌌 😴 🚕", "🥱 💤 🫠", "🌙 ☕ 😪"],
          },
          {
            id: "dreamy",
            messages: ["🌸 ☺️ 💫", "🌆 🥰 🎶", "💐 😊 🌤️", "🦋 😌 💜", "🌌 🙂 ✨", "🌷 ☺️ 🎧"],
          },
          {
            id: "grumpy",
            messages: ["⏰ 😑 👀", "🚕 🫤 ⌛", "🌧️ 🙄 🕰️", "📍 😒 ⏳", "👀 🚕 😐", "⌛ 😤 🌫️"],
          },
        ];
        const passengerChatDisplayMs = 1800;
        let penaltyTrackingReady = false;
        let knownPenaltyEventIds = new Set();
        let lastPhoneNotificationId = 0;
        let phoneToastTimer = null;
        let acceptedOfferTimer = null;
        let trackedNextOfferId = null;
        const expiredNextOfferIds = new Set();
        $scope.nextOfferUiRemaining = 0;
        let settingsInitializedFromBackend = false;
        let legacyImportRequested = false;
        let hudStateReceived = false;
        let hudEpoch = "";
        let hudRevision = 0;
        let hudResyncRequestedAt = 0;
        let lastAnnouncedNextOfferId = null;
        let passengerChatTimer = null;
        let passengerChatHideTimer = null;
        let passengerMoodFlashTimer = null;
        let passengerChatGeneration = 0;
        let passengerChatTripId = 0;
        let passengerChatPassenger = "";
        let passengerChatMood = null;
        let passengerChatLastMessage = -1;
        let passengerChatMessageTarget = 0;
        let passengerChatMessageCount = 0;
        let gameUiVolume = 1;
        let offlineHoldStartedAt = 0;
        let offlineHoldTimer = null;
        let activeFuelStationId = "";
        let settingsSaveTimer = null;
        let pendingSettingsFingerprint = "";
        let pendingSettingsDeadline = 0;
        let overspeedWarningActive = false;
        $scope.overspeedWarningActive = false;

        const clampAudioVolume = (value) => Math.max(0, Math.min(1, Number(value) || 0));
        const applyGameUiVolume = () => {
          const appVolume = clampAudioVolume($scope.settings.appVolume);
          Object.keys(appAudio).forEach((soundId) => {
            const pool = appAudio[soundId];
            const volume = clampAudioVolume(pool.baseVolume * gameUiVolume * appVolume);
            pool.players.forEach((audio) => { audio.volume = volume; });
          });
        };
        const setGameUiVolume = (value) => {
          const parsed = Number(value);
          if (!Number.isFinite(parsed)) return;
          gameUiVolume = clampAudioVolume(parsed);
          applyGameUiVolume();
        };
        const refreshGameUiVolume = () => {
          bngApi.engineLua('settings.getValue("AudioUiVol")', setGameUiVolume);
        };

        const ensureHtmlAudioPlayers = (pool) => {
          if (!pool || pool.players.length) return;
          for (let index = 0; index < pool.size; index += 1) {
            const audio = new Audio(pool.source);
            audio.preload = "auto";
            pool.players.push(audio);
          }
        };
        const getPoolVolume = (pool) => clampAudioVolume(
          pool.baseVolume * gameUiVolume * clampAudioVolume($scope.settings.appVolume)
        );
        const playHtmlAudio = (pool) => {
          if (!pool) return false;
          if (externalPhoneMode) {
            if (!externalHtmlAudioUnlocked || !externalHtmlAudioPlayers.length) return false;
            const audio = externalHtmlAudioPlayers[externalHtmlAudioCursor];
            externalHtmlAudioCursor = (externalHtmlAudioCursor + 1) % externalHtmlAudioPlayers.length;
            try {
              audio.pause();
              audio.src = pool.source;
              audio.volume = getPoolVolume(pool);
              audio.currentTime = 0;
              if (typeof audio.load === "function") audio.load();
              const playback = audio.play();
              if (playback && playback.catch) {
                playback.catch(() => { externalHtmlAudioUnlocked = false; });
              }
              return true;
            } catch (_) {
              externalHtmlAudioUnlocked = false;
              return false;
            }
          }
          ensureHtmlAudioPlayers(pool);
          if (!pool.players.length) return false;
          const audio = pool.players[pool.cursor];
          pool.cursor = (pool.cursor + 1) % pool.players.length;
          try {
            audio.volume = getPoolVolume(pool);
            audio.currentTime = 0;
            const playback = audio.play();
            if (playback && playback.catch) playback.catch(() => {});
            return true;
          } catch (_) { return false; }
        };
        const queueExternalAudio = (soundId, createdAt = Date.now()) => {
          externalAudioQueue = externalAudioQueue
            .filter((request) => createdAt - request.createdAt <= externalAudioQueueTtlMs)
            .slice(-(externalAudioQueueLimit - 1));
          externalAudioQueue.push({ soundId, createdAt });
        };
        let flushExternalAudioQueue = () => {};
        const handleExternalAudioStateChange = () => {
          externalAudioUnlocked = !!externalAudioContext && externalAudioContext.state === "running";
          if (externalAudioUnlocked) flushExternalAudioQueue();
        };
        const ensureExternalAudioContext = () => {
          if (!externalWebAudioEnabled) return null;
          if (externalAudioContext) return externalAudioContext;
          try {
            externalAudioContext = new ExternalAudioContext({ latencyHint: "interactive" });
          } catch (_) {
            try { externalAudioContext = new ExternalAudioContext(); } catch (_) { return null; }
          }
          externalAudioUnlocked = externalAudioContext.state === "running";
          if (typeof externalAudioContext.addEventListener === "function") {
            externalAudioContext.addEventListener("statechange", handleExternalAudioStateChange);
          } else {
            externalAudioContext.onstatechange = handleExternalAudioStateChange;
          }
          return externalAudioContext;
        };
        const primeExternalWebAudio = (context) => {
          if (externalAudioPrimeStarted || !context || typeof context.createBuffer !== "function") return;
          externalAudioPrimeStarted = true;
          try {
            const source = context.createBufferSource();
            source.buffer = context.createBuffer(1, 1, context.sampleRate || 44100);
            source.connect(context.destination);
            source.start(0);
          } catch (_) {
            externalAudioPrimeStarted = false;
          }
        };
        const unlockExternalHtmlAudio = () => {
          if (!externalPhoneMode || !externalHtmlAudioPlayers.length) return Promise.resolve(false);
          if (externalHtmlAudioUnlocked) return Promise.resolve(true);
          if (externalHtmlAudioUnlockPromise) return externalHtmlAudioUnlockPromise;
          const attempts = externalHtmlAudioPlayers.map((audio) => {
            try {
              audio.src = externalSilentAudioSource;
              audio.volume = 1;
              audio.currentTime = 0;
              if (typeof audio.load === "function") audio.load();
              const playback = audio.play();
              return Promise.resolve(playback).then(() => {
                audio.pause();
                audio.currentTime = 0;
                return true;
              }).catch(() => false);
            } catch (_) { return Promise.resolve(false); }
          });
          externalHtmlAudioUnlockPromise = Promise.all(attempts).then((results) => {
            externalHtmlAudioUnlocked = results.some(Boolean);
            if (externalHtmlAudioUnlocked) flushExternalAudioQueue();
            return externalHtmlAudioUnlocked;
          }).finally(() => { externalHtmlAudioUnlockPromise = null; });
          return externalHtmlAudioUnlockPromise;
        };
        const dataUriToArrayBuffer = (source) => {
          const comma = source.indexOf(",");
          if (comma < 0) throw new Error("Invalid embedded audio source");
          const metadata = source.slice(0, comma);
          const payload = source.slice(comma + 1);
          const binary = /;base64/i.test(metadata) ? atob(payload) : decodeURIComponent(payload);
          const bytes = new Uint8Array(binary.length);
          for (let index = 0; index < binary.length; index += 1) {
            bytes[index] = binary.charCodeAt(index) & 0xff;
          }
          return bytes.buffer;
        };
        const decodeExternalAudioBuffer = (context, arrayBuffer) => new Promise((resolve, reject) => {
          let settled = false;
          const complete = (buffer) => {
            if (settled) return;
            settled = true;
            resolve(buffer);
          };
          const fail = (error) => {
            if (settled) return;
            settled = true;
            reject(error || new Error("Audio decoding failed"));
          };
          try {
            const result = context.decodeAudioData(arrayBuffer.slice(0), complete, fail);
            if (result && typeof result.then === "function") result.then(complete, fail);
          } catch (error) { fail(error); }
        });
        const prepareExternalWebAudio = () => {
          if (!externalWebAudioEnabled) return Promise.resolve(false);
          if (externalAudioPreparePromise) return externalAudioPreparePromise;
          const context = ensureExternalAudioContext();
          if (!context) return Promise.resolve(false);
          externalAudioPreparePromise = Promise.all(Object.keys(appAudio).map((soundId) => {
            const pool = appAudio[soundId];
            return decodeExternalAudioBuffer(context, dataUriToArrayBuffer(pool.source))
              .then((buffer) => {
                externalAudioBuffers.set(soundId, buffer);
                return true;
              })
              .catch(() => {
                externalAudioDecodeFailures.add(soundId);
                return false;
              });
          })).then(() => true);
          return externalAudioPreparePromise;
        };
        const startExternalWebAudio = (soundId) => {
          const context = externalAudioContext;
          const pool = appAudio[soundId];
          const buffer = externalAudioBuffers.get(soundId);
          if (!externalAudioUnlocked || !context || context.state !== "running" || !pool || !buffer) return false;
          try {
            const source = context.createBufferSource();
            const gain = context.createGain();
            source.buffer = buffer;
            gain.gain.value = clampAudioVolume(
              pool.baseVolume * gameUiVolume * clampAudioVolume($scope.settings.appVolume)
            );
            source.connect(gain);
            gain.connect(context.destination);
            source.start(0);
            return true;
          } catch (_) { return false; }
        };
        flushExternalAudioQueue = () => {
          const now = Date.now();
          const pending = externalAudioQueue;
          externalAudioQueue = [];
          pending.forEach((request) => {
            if (now - request.createdAt > externalAudioQueueTtlMs) return;
            const useHtmlFallback = !externalWebAudioEnabled ||
              externalAudioDecodeFailures.has(request.soundId);
            if (useHtmlFallback) {
              if (!playHtmlAudio(appAudio[request.soundId])) externalAudioQueue.push(request);
            } else if (!startExternalWebAudio(request.soundId)) {
              externalAudioQueue.push(request);
            }
          });
        };
        const resumeExternalWebAudio = (fromUserGesture = false) => {
          const context = externalAudioContext || (fromUserGesture ? ensureExternalAudioContext() : null);
          if (!context) return Promise.resolve(false);
          if (fromUserGesture) primeExternalWebAudio(context);
          let resumed;
          try {
            resumed = context.state === "running" ? Promise.resolve() : context.resume();
          } catch (_) { return Promise.resolve(false); }
          return Promise.resolve(resumed).then(() => {
            externalAudioUnlocked = context.state === "running";
            if (!externalAudioUnlocked) return false;
            return prepareExternalWebAudio().then(() => {
              flushExternalAudioQueue();
              return true;
            });
          }).catch(() => false);
        };

        const playAppSound = (soundId) => {
          if ($scope.settings.silentMode) return;
          if ($scope.settings.soundToggles && $scope.settings.soundToggles[soundId] === false) return;
          if (!externalPhoneMode && $scope.state && $scope.state.lan &&
              Number($scope.state.lan.connected || 0) > 0) return;
          const pool = appAudio[soundId];
          if (!pool) return;
          if (externalPhoneMode) {
            if (externalWebAudioEnabled && !externalAudioDecodeFailures.has(soundId)) {
              if (!startExternalWebAudio(soundId)) {
                queueExternalAudio(soundId);
                if (externalAudioActivated) resumeExternalWebAudio(false);
              }
            } else if (!playHtmlAudio(pool)) {
              queueExternalAudio(soundId);
            }
            return;
          }
          playHtmlAudio(pool);
        };
        const playViolationSound = () => playAppSound("violation");

        const randomDelay = (minimum, maximum) =>
          minimum + Math.random() * Math.max(0, maximum - minimum);
        const isPassengerChatEligible = () =>
          $scope.state.active === true &&
          $scope.state.phase === "toPickup" &&
          $scope.state.isDelivery !== true &&
          Number($scope.state.activeTripId || 0) > 0 &&
          String($scope.state.passengerName || "").length > 0;
        const dismissPassengerChat = () => {
          if (passengerChatHideTimer) clearTimeout(passengerChatHideTimer);
          passengerChatHideTimer = null;
          $scope.passengerChat = null;
        };
        const stopPassengerChat = () => {
          passengerChatGeneration += 1;
          if (passengerChatTimer) clearTimeout(passengerChatTimer);
          passengerChatTimer = null;
          dismissPassengerChat();
          passengerChatTripId = 0;
          passengerChatPassenger = "";
          passengerChatMood = null;
          passengerChatLastMessage = -1;
          passengerChatMessageTarget = 0;
          passengerChatMessageCount = 0;
        };
        const schedulePassengerChat = (initial, requestedDelay) => {
          if (passengerChatTimer) clearTimeout(passengerChatTimer);
          passengerChatTimer = null;
          if (!isPassengerChatEligible() || !passengerChatMood ||
              passengerChatMessageCount >= passengerChatMessageTarget) return;
          const generation = passengerChatGeneration;
          const delay = requestedDelay === undefined
            ? randomDelay(initial ? 4500 : 7000, initial ? 7000 : 13000)
            : requestedDelay;
          passengerChatTimer = setTimeout(() => $scope.$evalAsync(() => {
            passengerChatTimer = null;
            if (generation !== passengerChatGeneration || !isPassengerChatEligible()) return;
            if ($scope.settingsOpen || $scope.profileOpen || $scope.phoneMinimized || $scope.phoneToast) {
              schedulePassengerChat(false, 2500);
              return;
            }

            const messages = passengerChatMood.messages;
            let messageIndex = Math.floor(Math.random() * messages.length);
            if (messages.length > 1 && messageIndex === passengerChatLastMessage) {
              messageIndex = (messageIndex + 1 + Math.floor(Math.random() * (messages.length - 1))) % messages.length;
            }
            passengerChatLastMessage = messageIndex;
            passengerChatMessageCount += 1;
            $scope.passengerChat = {
              passengerName: passengerChatPassenger,
              sentAt: new Date().toLocaleTimeString([], {
                hour: "2-digit", minute: "2-digit", hour12: $scope.settings.timeFormat !== "24h",
              }),
              content: messages[messageIndex],
              mood: passengerChatMood.id,
            };
            playAppSound("message");
            passengerChatHideTimer = setTimeout(() => $scope.$evalAsync(() => {
              passengerChatHideTimer = null;
              $scope.passengerChat = null;
              if (generation === passengerChatGeneration && isPassengerChatEligible() &&
                  passengerChatMessageCount < passengerChatMessageTarget) {
                schedulePassengerChat(false);
              }
            }), passengerChatDisplayMs);
          }), delay);
        };
        const syncPassengerChat = () => {
          if (!isPassengerChatEligible()) {
            if (passengerChatPassenger || passengerChatTimer || $scope.passengerChat) stopPassengerChat();
            return;
          }
          const tripId = Number($scope.state.activeTripId || 0);
          const passengerName = String($scope.state.passengerName || "");
          if (tripId === passengerChatTripId && passengerName === passengerChatPassenger && passengerChatMood) {
            if (!passengerChatTimer && !$scope.passengerChat &&
                passengerChatMessageCount < passengerChatMessageTarget) {
              schedulePassengerChat(false, 2500);
            }
            return;
          }
          stopPassengerChat();
          passengerChatGeneration += 1;
          passengerChatTripId = tripId;
          passengerChatPassenger = passengerName;
          passengerChatMood = passengerEmojiMoods[Math.floor(Math.random() * passengerEmojiMoods.length)];
          passengerChatMessageTarget = 1 + Math.floor(Math.random() * 3);
          passengerChatMessageCount = 0;
          schedulePassengerChat(true);
        };

        const appRoot = $element[0];
        const handleExternalAudioUnlock = () => {
          externalAudioActivated = true;
          // Both transports are unlocked from the same trusted gesture. Web
          // Audio is primary; pre-warmed HTMLAudio elements cover decode/API
          // failures in older or restricted mobile browsers.
          unlockExternalHtmlAudio();
          resumeExternalWebAudio(true);
        };
        const handleExternalAudioVisibility = () => {
          if (document.visibilityState === "visible" && externalAudioActivated) {
            resumeExternalWebAudio(false);
          }
        };
        const handleExternalAudioPageShow = () => {
          if (externalAudioActivated) resumeExternalWebAudio(false);
        };
        if (externalPhoneMode) {
          appRoot.addEventListener("pointerdown", handleExternalAudioUnlock, true);
          appRoot.addEventListener("touchend", handleExternalAudioUnlock, true);
          appRoot.addEventListener("keydown", handleExternalAudioUnlock, true);
          document.addEventListener("visibilitychange", handleExternalAudioVisibility);
          window.addEventListener("pageshow", handleExternalAudioPageShow);
          window.addEventListener("focus", handleExternalAudioPageShow);
        }
        let lastLanQrUrl = "";
        const renderLanQr = () => {
          if (!$scope.settingsOpen || !$scope.settings.lanEnabled) return;
          const target = appRoot.querySelector(".taxi-lan__qr-code");
          if (!target) return;
          const url = String($scope.state.lan && $scope.state.lan.url || "");
          if (!url) {
            target.innerHTML = "";
            lastLanQrUrl = "";
            return;
          }
          if (url === lastLanQrUrl && target.children.length) return;
          target.innerHTML = "";
          lastLanQrUrl = url;
          if (typeof QRCode === "undefined") return;
          try {
            new QRCode(target, {
              text: url,
              width: 140,
              height: 140,
              colorDark: "#111317",
              colorLight: "#ffffff",
              correctLevel: QRCode.CorrectLevel.M,
            });
          } catch (error) {
            console.error("TaxiDriverHUD: unable to render LAN QR code", error);
          }
        };
        const scheduleLanQr = () => $scope.$evalAsync(() => requestAnimationFrame(renderLanQr));
        const handleAppClick = (event) => {
          let target = event.target;
          while (target && target !== appRoot) {
            if (target.getAttribute && target.getAttribute("data-taxi-no-click-sound") === "true") return;
            const tagName = String(target.tagName || "").toLowerCase();
            if (tagName === "button" || tagName === "input" || tagName === "select") {
              playAppSound("click");
              return;
            }
            target = target.parentElement;
          }
        };
        appRoot.addEventListener("click", handleAppClick, true);

        const callTaxiDriver = (functionName) => {
          bngApi.engineLua(
            `if not taxiDriver_taxiDriver then extensions.load("taxiDriver_taxiDriver") end; taxiDriver_taxiDriver.${functionName}()`
          );
        };

        const clearNextOfferCountdown = () => {
          trackedNextOfferId = null;
          $scope.nextOfferUiRemaining = 0;
        };

        const expireNextOfferLocally = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0 || expiredNextOfferIds.has(id)) return;
          expiredNextOfferIds.add(id);
          clearNextOfferCountdown();
          if ($scope.state.nextOffer && Number($scope.state.nextOffer.id) === id &&
              !$scope.state.nextOffer.accepted) {
            $scope.state = Object.assign({}, $scope.state, { nextOffer: null });
          }
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.expireNextOffer(${id}) end`
          );
        };

        const syncNextOfferCountdown = (offer) => {
          if (!offer || offer.accepted) {
            clearNextOfferCountdown();
            return;
          }
          const id = Math.floor(Number(offer.id || 0));
          if (id <= 0 || expiredNextOfferIds.has(id)) return;
          trackedNextOfferId = id;
          const reportedRemaining = Number(offer.timeRemaining);
          const remaining = Math.max(0, Number.isFinite(reportedRemaining)
            ? reportedRemaining
            : Number(offer.duration || 5));
          $scope.nextOfferUiRemaining = remaining;
        };

        const normalizeSettings = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const uiScalePercent = Number(value.uiScalePercent);
          const legacyFontBoost = Number(value.fontBoost);
          const appVolume = value.appVolume === undefined ? 0.65 : Number(value.appVolume);
          const dynamicZoomIntensity = value.dynamicZoomIntensity === undefined
            ? 100 : Number(value.dynamicZoomIntensity);
          const overspeedWarningKmh = value.overspeedWarningKmh === undefined
            ? 10 : Number(value.overspeedWarningKmh);
          const economyMultiplier = value.economyMultiplier === undefined
            ? 1 : Number(value.economyMultiplier);
          const deliveryOrderSharePercent = value.deliveryOrderSharePercent === undefined
            ? 50 : Number(value.deliveryOrderSharePercent);
          return {
            language: i18n[value.language] ? value.language : "en",
            rememberLanguage: value.rememberLanguage === true,
            difficulty: difficulties.includes(value.difficulty) ? value.difficulty : "standard",
            customDifficulty: normalizeCustomDifficulty(value.customDifficulty),
            uiScalePercent: Math.max(80, Math.min(180, Math.round(
              (Number.isFinite(uiScalePercent)
                ? uiScalePercent
                : (Number.isFinite(legacyFontBoost) ? 100 + (legacyFontBoost - 2) * 10 : 100)) / 10
            ) * 10)),
            appVolume: Math.max(0, Math.min(1, Number.isFinite(appVolume) ? appVolume : 0.65)),
            unitSystem: value.unitSystem === "imperial" ? "imperial" : "metric",
            timeFormat: value.timeFormat === "24h" ? "24h" : "12h",
            penaltyToggles: normalizePenaltyToggles(value.penaltyToggles),
            soundToggles: normalizeSoundToggles(value.soundToggles),
            dynamicZoomIntensity: Math.max(0, Math.min(200,
              Number.isFinite(dynamicZoomIntensity) ? dynamicZoomIntensity : 100)),
            overspeedWarningKmh: Math.max(0, Math.min(30,
              Number.isFinite(overspeedWarningKmh) ? overspeedWarningKmh : 10)),
            economyMultiplier: Math.max(0.25, Math.min(5,
              Number.isFinite(economyMultiplier) ? economyMultiplier : 1)),
            deliveryOrderSharePercent: Math.max(0, Math.min(100,
              Number.isFinite(deliveryOrderSharePercent) ? deliveryOrderSharePercent : 50)),
            unlimitedRouteDistance: value.unlimitedRouteDistance === true,
            lanEnabled: value.lanEnabled === true,
            externalMapEnabled: value.externalMapEnabled !== false,
            externalTerrainEnabled: value.externalTerrainEnabled !== false,
            externalMapQuality: ["eco", "balanced", "smooth"].includes(value.externalMapQuality)
              ? value.externalMapQuality : "balanced",
            silentMode: value.silentMode === true,
            showRouteGuidance: value.showRouteGuidance !== false,
            realisticMode: value.realisticMode === true,
            randomEventsEnabled: value.randomEventsEnabled === true,
            aiDebugLogging: value.aiDebugLogging === true,
            aiDriver: normalizeAiDriver(value.aiDriver),
            fleet: normalizeFleet(value.fleet),
            godMode: value.godMode === true,
            debugLogging: value.debugLogging !== false,
          };
        };

        const settingsFingerprint = (source) => JSON.stringify(normalizeSettings(source));
        const retainLocalSettingsUntilAcknowledged = () => {
          const normalized = normalizeSettings($scope.settings);
          $scope.settings = normalized;
          $scope.language = normalized.language;
          if ($scope.state) $scope.state.settings = Object.assign({}, normalized);
          pendingSettingsFingerprint = settingsFingerprint(normalized);
          pendingSettingsDeadline = Date.now() + 5000;
          return normalized;
        };

        const normalizeFuelStation = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const refuelingSource = value.refueling && typeof value.refueling === "object"
            ? value.refueling : {};
          const options = Array.isArray(value.options) ? value.options.map((option) => ({
            energyType: String(option.energyType || ""),
            unit: String(option.unit || ""),
            currentQuantity: Math.max(0, Number(option.currentQuantity || 0)),
            maxQuantity: Math.max(0, Number(option.maxQuantity || 0)),
            missingQuantity: Math.max(0, Number(option.missingQuantity || 0)),
            affordableQuantity: Math.max(0, Number(option.affordableQuantity || 0)),
            currentPercent: Math.max(0, Math.min(100, Number(option.currentPercent || 0))),
            pricePerUnit: Math.max(0, Number(option.pricePerUnit || 0)),
            maxCost: Math.max(0, Number(option.maxCost || 0)),
            consumptionPer100Km: Math.max(0, Number(option.consumptionPer100Km || 0)),
          })).filter((option) => option.energyType) : [];
          return {
            available: value.available === true,
            id: String(value.id || ""),
            name: String(value.name || ""),
            magic: value.magic === true,
            vehicleStopped: value.vehicleStopped === true,
            balance: Math.max(0, Number(value.balance || 0)),
            options,
            refueling: {
              active: refuelingSource.active === true,
              completing: refuelingSource.completing === true,
              energyType: String(refuelingSource.energyType || ""),
              quantity: Math.max(0, Number(refuelingSource.quantity || 0)),
              cost: Math.max(0, Number(refuelingSource.cost || 0)),
              duration: Math.max(0, Number(refuelingSource.duration || 0)),
              elapsed: Math.max(0, Number(refuelingSource.elapsed || 0)),
              progress: Math.max(0, Math.min(1, Number(refuelingSource.progress || 0))),
              remainingSeconds: Math.max(0, Number(refuelingSource.remainingSeconds || 0)),
              completionId: Math.max(0, Number(refuelingSource.completionId || 0)),
            },
          };
        };

        const normalizeFuelDetour = (source) => {
          const value = source && typeof source === "object" ? source : {};
          return {
            active: value.active === true,
            hadTrip: value.hadTrip === true,
            passengerOnboard: value.passengerOnboard === true,
            stationName: String(value.stationName || ""),
            routeDistance: Math.max(0, Number(value.routeDistance || 0)),
            penaltyPercent: Math.max(0, Number(value.penaltyPercent || 0)),
            arrived: value.arrived === true,
          };
        };

        const getFuelOption = (energyType, station) => {
          const source = station || $scope.state.fuelStation || {};
          const options = Array.isArray(source.options) ? source.options : [];
          return options.find((option) => option.energyType === energyType) || null;
        };

        const clampRefuelAmount = () => {
          const option = getFuelOption($scope.selectedFuelType);
          const maximum = option ? Math.max(0, Number(option.affordableQuantity || 0)) : 0;
          const amount = Math.max(0, Number($scope.refuel.amount || 0));
          $scope.refuel.amount = Math.min(maximum, amount);
        };

        const syncFuelStation = (station) => {
          if (!station.available) {
            activeFuelStationId = "";
            $scope.fuelStationOpen = false;
            $scope.selectedFuelType = "";
            $scope.refuel.amount = 0;
            return;
          }

          const isNewStation = station.id !== activeFuelStationId;
          activeFuelStationId = station.id;
          if (isNewStation) {
            $scope.refuel.amount = 0;
            if (!$scope.settingsOpen && !$scope.profileOpen && !$scope.offlineConfirmOpen) {
              $scope.fuelStationOpen = true;
              $scope.phoneMinimized = false;
              dismissPassengerChat();
              hideMinimap();
            }
          }

          if (!getFuelOption($scope.selectedFuelType, station)) {
            $scope.selectedFuelType = station.options.length ? station.options[0].energyType : "";
            $scope.refuel.amount = 0;
          }
          clampRefuelAmount();
        };

        const saveSettingsToLua = (source) => {
          const luaSettings = bngApi.serializeToLua(normalizeSettings(source));
          bngApi.engineLua(
            `if not taxiDriver_taxiDriver then extensions.load("taxiDriver_taxiDriver") end; taxiDriver_taxiDriver.saveSettings(${luaSettings})`
          );
        };

        const persistSettingsNow = () => {
          if (settingsSaveTimer) clearTimeout(settingsSaveTimer);
          settingsSaveTimer = null;
          retainLocalSettingsUntilAcknowledged();
          applyGameUiVolume();
          updateClock();
          saveSettingsToLua($scope.settings);
          $scope.settingsSaved = true;
        };

        const queueSettingsSave = (delay) => {
          $scope.settingsSaved = false;
          retainLocalSettingsUntilAcknowledged();
          if (settingsSaveTimer) clearTimeout(settingsSaveTimer);
          settingsSaveTimer = setTimeout(() => $scope.$evalAsync(() => {
            persistSettingsNow();
          }), delay === undefined ? 180 : Math.max(0, delay));
        };

        const normalizeProfile = (source) => {
          const value = source && typeof source === "object" ? source : {};
          const fullName = String(value.fullName || "John Doe").trim().replace(/\s+/g, " ");
          const birthDate = /^\d{4}-\d{2}-\d{2}$/.test(String(value.birthDate || ""))
            ? String(value.birthDate)
            : "";
          const avatar = $scope.avatarOptions.includes(value.avatar) ? value.avatar : "🙂";
          return { fullName: fullName || "John Doe", birthDate, avatar };
        };

        const requestProfileData = () => bngApi.engineLua(
          'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestProfileData() end'
        );

        const saveProfileToLua = (profile) => {
          const luaProfile = bngApi.serializeToLua(normalizeProfile(profile));
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.saveDriverProfile(${luaProfile}) end`
          );
        };

        const stopOfflineHold = () => {
          if (offlineHoldTimer) clearInterval(offlineHoldTimer);
          offlineHoldTimer = null;
          offlineHoldStartedAt = 0;
          $scope.offlineHoldProgress = 0;
        };

        const completeOfflineHold = () => {
          stopOfflineHold();
          if ($scope.state.passengerOnboard) {
            $scope.offlineConfirmOpen = true;
            dismissPassengerChat();
            hideMinimap();
          } else {
            callTaxiDriver("stopMode");
          }
        };

        const sampleHistory = (source, limit) => {
          const values = Array.isArray(source) ? source : [];
          if (values.length <= limit) return values;
          const sampled = [];
          const step = (values.length - 1) / (limit - 1);
          for (let index = 0; index < limit; index += 1) {
            sampled.push(values[Math.round(index * step)]);
          }
          return sampled;
        };

        $scope.getChartPoints = (history, chartType) => {
          const values = sampleHistory(history, 80);
          if (!values.length) return "";
          const width = 320;
          const height = 92;
          const padding = 8;
          const numbers = values.map((item) => Number(item.value || 0));
          let minimum = chartType === "rating" ? 0 : Math.min(0, ...numbers);
          let maximum = chartType === "rating" ? 5 : Math.max(...numbers);
          if (maximum <= minimum) maximum = minimum + 1;
          return values.map((item, index) => {
            const x = padding + (width - padding * 2) * (values.length === 1 ? 0.5 : index / (values.length - 1));
            const ratio = (Number(item.value || 0) - minimum) / (maximum - minimum);
            const y = height - padding - ratio * (height - padding * 2);
            return `${x.toFixed(1)},${y.toFixed(1)}`;
          }).join(" ");
        };

        $scope.getAge = (birthDate) => {
          if (!/^\d{4}-\d{2}-\d{2}$/.test(String(birthDate || ""))) return "—";
          const birthday = new Date(`${birthDate}T12:00:00`);
          if (Number.isNaN(birthday.getTime()) || birthday > new Date()) return "—";
          const now = new Date();
          let age = now.getFullYear() - birthday.getFullYear();
          const beforeBirthday = now.getMonth() < birthday.getMonth() ||
            (now.getMonth() === birthday.getMonth() && now.getDate() < birthday.getDate());
          if (beforeBirthday) age -= 1;
          return Math.max(0, age);
        };

        $scope.getReviewPageCount = () => Math.max(
          1,
          Math.ceil($scope.profileReviews.length / $scope.reviewsPerPage)
        );
        $scope.getPagedReviews = () => {
          const maximumPage = $scope.getReviewPageCount();
          $scope.reviewPage = Math.max(1, Math.min(maximumPage, $scope.reviewPage));
          const offset = ($scope.reviewPage - 1) * $scope.reviewsPerPage;
          return $scope.profileReviews.slice(offset, offset + $scope.reviewsPerPage);
        };
        let reviewPaginationFrame = 0;
        let reviewPaginationRetry = 0;
        const updateReviewPagination = () => {
          reviewPaginationFrame = 0;
          if (!$scope.profileOpen || $scope.profileTab !== "reviews" || !$scope.profileReviews.length) return;
          const content = appRoot.querySelector(".taxi-profile__content");
          const panel = appRoot.querySelector(".taxi-profile__panel--reviews");
          const regularMeasure = panel && panel.querySelector('[data-review-measure="regular"]');
          const aiMeasure = panel && panel.querySelector('[data-review-measure="ai"]');
          const pager = panel && panel.querySelector(".taxi-profile__pager");
          if (!content || !panel || !regularMeasure || !aiMeasure || !pager) {
            if (reviewPaginationRetry < 3) {
              reviewPaginationRetry += 1;
              reviewPaginationFrame = requestAnimationFrame(updateReviewPagination);
            }
            return;
          }
          reviewPaginationRetry = 0;
          const contentRect = content.getBoundingClientRect();
          const panelRect = panel.getBoundingClientRect();
          const contentStyle = getComputedStyle(content);
          const panelStyle = getComputedStyle(panel);
          const cssPixels = (value) => Number.parseFloat(value) || 0;
          const verticalInsets = cssPixels(contentStyle.paddingBottom) +
            cssPixels(panelStyle.paddingTop) + cssPixels(panelStyle.paddingBottom) +
            cssPixels(panelStyle.borderTopWidth) + cssPixels(panelStyle.borderBottomWidth);
          const regularRowHeight = Math.max(1, regularMeasure.getBoundingClientRect().height);
          const aiRowHeight = Math.max(regularRowHeight, aiMeasure.getBoundingClientRect().height);
          const pagerHeight = pager.getBoundingClientRect().height;
          const availableHeight = Math.max(regularRowHeight,
            contentRect.bottom - panelRect.top - verticalInsets - pagerHeight - 8);
          const reviewHeights = $scope.profileReviews.map((review) =>
            review && review.usedAutopilot ? aiRowHeight : regularRowHeight
          );
          const maximumCandidate = Math.min(50, reviewHeights.length);
          let nextPerPage = 1;
          for (let candidate = 2; candidate <= maximumCandidate; candidate += 1) {
            let fits = true;
            for (let start = 0; start < reviewHeights.length; start += candidate) {
              const pageHeight = reviewHeights.slice(start, start + candidate)
                .reduce((sum, height) => sum + height, 0);
              if (pageHeight > availableHeight + 1) {
                fits = false;
                break;
              }
            }
            if (!fits) break;
            nextPerPage = candidate;
          }
          if (nextPerPage === $scope.reviewsPerPage) return;
          const firstVisibleIndex = ($scope.reviewPage - 1) * $scope.reviewsPerPage;
          $scope.$evalAsync(() => {
            $scope.reviewsPerPage = nextPerPage;
            $scope.reviewPage = Math.floor(firstVisibleIndex / nextPerPage) + 1;
            scheduleReviewPagination();
          });
        };
        const scheduleReviewPagination = () => {
          if (reviewPaginationFrame) cancelAnimationFrame(reviewPaginationFrame);
          reviewPaginationRetry = 0;
          reviewPaginationFrame = requestAnimationFrame(updateReviewPagination);
        };
        const stopReviewPaginationWatch = $scope.$watchGroup([
          "profileOpen", "profileTab", "profileReviews.length", "settings.uiScalePercent",
        ], scheduleReviewPagination);
        const reviewResizeObserver = typeof ResizeObserver === "function"
          ? new ResizeObserver(scheduleReviewPagination) : null;
        if (reviewResizeObserver) reviewResizeObserver.observe(appRoot);
        $scope.formatReviewDate = (timestamp) => {
          const value = Number(timestamp || 0);
          if (!value) return "—";
          return new Date(value * 1000).toLocaleDateString($scope.language || "en", {
            year: "numeric", month: "short", day: "numeric",
          });
        };
        $scope.getReviewRatingClass = (review) => {
          const orderRating = Number(review && review.orderRating || 0);
          const profileRating = Number(review && review.rating || 0);
          if (Math.abs(orderRating - profileRating) < 0.005) return "equal";
          return orderRating > profileRating ? "higher" : "lower";
        };

        let lastMinimapRect = "";
        let minimapVisible = false;
        let uiVisible = true;
        let externalMapData = { route: [], roads: [], revision: 0 };
        let externalVehicleState = null;
        let externalMapFrame = 0;
        let externalMapDelayTimer = 0;
        let externalMapLastDrawAt = 0;
        let externalViewKey = "";
        let sendExternalHeartbeat = null;
        let externalCameraCenter = null;
        let externalCameraHeading = null;
        let externalCameraRadius = null;
        let externalCameraZoomUpdatedAt = 0;
        let externalRoadRevision = 0;
        let externalRoads = [];
        let externalTerrainTiles = [];
        const externalRoadGrid = new Map();
        const externalRoadCellSize = 500;
        const resetExternalRoads = () => {
          externalRoads = [];
          externalRoadGrid.clear();
        };
        const addExternalRoads = (roads, reset) => {
          if (reset) resetExternalRoads();
          if (!Array.isArray(roads)) return;
          roads.forEach((road) => {
            if (!Array.isArray(road) || road.length < 4) return;
            const roadIndex = externalRoads.length;
            externalRoads.push(road);
            const minCellX = Math.floor(Math.min(Number(road[0]), Number(road[2])) / externalRoadCellSize);
            const maxCellX = Math.floor(Math.max(Number(road[0]), Number(road[2])) / externalRoadCellSize);
            const minCellY = Math.floor(Math.min(Number(road[1]), Number(road[3])) / externalRoadCellSize);
            const maxCellY = Math.floor(Math.max(Number(road[1]), Number(road[3])) / externalRoadCellSize);
            for (let cellX = minCellX; cellX <= maxCellX; cellX += 1) {
              for (let cellY = minCellY; cellY <= maxCellY; cellY += 1) {
                const key = `${cellX}:${cellY}`;
                if (!externalRoadGrid.has(key)) externalRoadGrid.set(key, []);
                externalRoadGrid.get(key).push(roadIndex);
              }
            }
          });
        };
        const getExternalRoadsNear = (center, radius) => {
          if (!externalRoads.length) return [];
          const margin = radius * 1.5;
          const minCellX = Math.floor((Number(center[0]) - margin) / externalRoadCellSize);
          const maxCellX = Math.floor((Number(center[0]) + margin) / externalRoadCellSize);
          const minCellY = Math.floor((Number(center[1]) - margin) / externalRoadCellSize);
          const maxCellY = Math.floor((Number(center[1]) + margin) / externalRoadCellSize);
          const indices = new Set();
          for (let cellX = minCellX; cellX <= maxCellX; cellX += 1) {
            for (let cellY = minCellY; cellY <= maxCellY; cellY += 1) {
              const entries = externalRoadGrid.get(`${cellX}:${cellY}`);
              if (entries) entries.forEach((index) => indices.add(index));
            }
          }
          return Array.from(indices, (index) => externalRoads[index]);
        };
        const setExternalTerrainTiles = (tiles) => {
          if (!Array.isArray(tiles)) return;
          externalTerrainTiles = tiles.map((tile) => {
            const image = new Image();
            image.decoding = "async";
            image.onload = () => scheduleMinimapUpdate();
            image.onerror = () => scheduleMinimapUpdate();
            image.src = String(tile && tile.file || "");
            return {
              image,
              size: Array.isArray(tile && tile.size) ? tile.size : [0, 0],
              offset: Array.isArray(tile && tile.offset) ? tile.offset : [0, 0],
            };
          });
        };
        const minimapPhases = new Set(["toPickup", "toStop", "toDestination", "toFuelStation"]);
        const externalMapVisible = () => externalPhoneMode && !document.hidden &&
          $scope.settings.externalMapEnabled !== false && ($scope.fleetOpen || minimapPhases.has($scope.state.phase)) &&
          !$scope.settingsOpen && !$scope.profileOpen && !$scope.offlineConfirmOpen &&
          !$scope.fuelStationOpen;
        const getExternalView = () => {
          if (!externalPhoneMode) return "hidden";
          if ($scope.settingsOpen) return "settings";
          if ($scope.profileOpen) return "profile";
          if ($scope.fuelStationOpen) return "fuel";
          if ($scope.fleetOpen) return "fleet";
          if (!$scope.settings.externalMapEnabled && minimapPhases.has($scope.state.phase)) return "status";
          if ($scope.phoneMinimized && minimapPhases.has($scope.state.phase)) return "compact";
          if ($scope.state.phase === "toFuelStation") return "fuelRoute";
          if (["toPickup", "toStop", "toDestination"].includes($scope.state.phase)) return "trip";
          if ($scope.state.phase === "searching") return "orders";
          return $scope.state.active ? "status" : "home";
        };
        const syncExternalView = () => {
          if (!externalPhoneMode) return;
          const view = getExternalView();
          const visible = view !== "hidden";
          const key = `${view}:${visible ? 1 : 0}`;
          if (key === externalViewKey) return;
          externalViewKey = key;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setExternalPhoneView("${view}", ${visible ? "true" : "false"}, "${externalSessionToken}") end`
          );
        };
        const canRenderMinimap = (hudState) => !externalPhoneMode && uiVisible && hudState &&
          (!(hudState.lan && Number(hudState.lan.connected || 0) > 0) || $scope.localPhoneOpen) &&
          ($scope.fleetOpen || (hudState.active === true && minimapPhases.has(hudState.phase))) &&
          ($scope.phoneMinimized || (
            !$scope.settingsOpen && !$scope.profileOpen && !$scope.offlineConfirmOpen &&
            !$scope.fuelStationOpen
          ));
        const hideMinimap = (force) => {
          if (!force && !minimapVisible && !lastMinimapRect) return;
          lastMinimapRect = "";
          minimapVisible = false;
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.hideMinimap() end"
          );
        };

        const updateMinimap = () => {
          if (!canRenderMinimap($scope.state)) {
            hideMinimap();
            return;
          }

          const surface = $element[0].querySelector(
            $scope.fleetOpen
              ? ".taxi-fleet .taxi-minimap-surface"
              : ($scope.phoneMinimized
              ? ".taxi-compact .taxi-minimap-surface"
              : ".taxi-phone .taxi-minimap-surface")
          );
          if (!surface) {
            hideMinimap();
            return;
          }

          const rect = surface.getBoundingClientRect();
          if (rect.width < 20 || rect.height < 20 || window.innerWidth <= 0 || window.innerHeight <= 0) return;

          const normalizeRect = (element) => {
            if (!element) return [0, 0, 0, 0];
            const elementRect = element.getBoundingClientRect();
            const left = Math.max(0, Math.min(window.innerWidth, elementRect.left + window.scrollX));
            const top = Math.max(0, Math.min(window.innerHeight, elementRect.top + window.scrollY));
            const right = Math.max(left, Math.min(window.innerWidth, elementRect.right + window.scrollX));
            const bottom = Math.max(top, Math.min(window.innerHeight, elementRect.bottom + window.scrollY));
            return [
              left / window.innerWidth,
              top / window.innerHeight,
              (right - left) / window.innerWidth,
              (bottom - top) / window.innerHeight,
            ];
          };

          const values = normalizeRect(surface);
          const routeInfoValues = normalizeRect($element[0].querySelector(
            $scope.phoneMinimized ? ".taxi-compact__route-info" : ".taxi-map__route-info"
          ));
          const speedLimitValues = normalizeRect($element[0].querySelector(
            $scope.phoneMinimized ? ".taxi-compact__speed" : ".taxi-map__speed"
          ));
          const autopilotValues = $scope.phoneMinimized
            ? [0, 0, 0, 0]
            : normalizeRect($element[0].querySelector(".taxi-map__autopilot"));
          const notificationValues = $scope.phoneMinimized
            ? [0, 0, 0, 0]
            : normalizeRect($element[0].querySelector(".taxi-phone-toast"));
          const fleetStatusValues = $scope.fleetOpen
            ? normalizeRect($element[0].querySelector(".taxi-fleet__map-status"))
            : [0, 0, 0, 0];
          const layoutKey = values
            .concat(routeInfoValues, speedLimitValues, notificationValues, autopilotValues, fleetStatusValues)
            .map((value) => value.toFixed(5))
            .join(",");
          if (layoutKey === lastMinimapRect) return;
          lastMinimapRect = layoutKey;
          minimapVisible = true;

          const rectKey = values.map((value) => value.toFixed(5)).join(",");
          const occlusionKey = routeInfoValues
            .concat(speedLimitValues, notificationValues, autopilotValues, fleetStatusValues)
            .map((value) => value.toFixed(5))
            .join(",");

          const allowFleetMap = $scope.fleetOpen ? "true" : "false";
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapTransform(${rectKey}, ${allowFleetMap}); taxiDriver_taxiDriver.setMinimapOcclusions(${occlusionKey}, ${allowFleetMap}) end`
          );
        };

        const getExternalMapFrameInterval = () => {
          const quality = $scope.settings.externalMapQuality;
          return quality === "eco" ? 1000 / 6 : (quality === "smooth" ? 1000 / 30 : 1000 / 15);
        };
        const scheduleExternalMapDraw = () => {
          if (!externalMapVisible() || externalMapFrame || externalMapDelayTimer) return;
          const remaining = Math.max(0,
            getExternalMapFrameInterval() - (performance.now() - externalMapLastDrawAt)
          );
          const requestDraw = () => {
            externalMapDelayTimer = 0;
            externalMapFrame = requestAnimationFrame((timestamp) => {
              externalMapFrame = 0;
              externalMapLastDrawAt = timestamp;
              drawExternalMap();
            });
          };
          if (remaining > 2) externalMapDelayTimer = setTimeout(requestDraw, remaining);
          else requestDraw();
        };
        const scheduleMinimapUpdate = () => {
          if (externalPhoneMode) scheduleExternalMapDraw();
          else $scope.$evalAsync(() => requestAnimationFrame(updateMinimap));
        };

        const drawExternalMap = () => {
          if (!externalMapVisible() || !externalVehicleState ||
              !externalVehicleState.position || (!$scope.fleetOpen && !minimapPhases.has($scope.state.phase))) {
            externalCameraCenter = null;
            externalCameraHeading = null;
            externalCameraRadius = null;
            externalCameraZoomUpdatedAt = 0;
            return;
          }
          const surfaces = $element[0].querySelectorAll("canvas.taxi-external-minimap");
          const targetCenter = externalVehicleState.position.map((value) => Number(value) || 0);
          const direction = externalVehicleState.direction || [0, 1];
          const targetHeading = Math.atan2(Number(direction[0]) || 0, Number(direction[1]) || 1);
          if (!externalCameraCenter) externalCameraCenter = targetCenter.slice();
          if (externalCameraHeading === null) externalCameraHeading = targetHeading;
          const centerDeltaX = targetCenter[0] - externalCameraCenter[0];
          const centerDeltaY = targetCenter[1] - externalCameraCenter[1];
          externalCameraCenter[0] += centerDeltaX * 0.32;
          externalCameraCenter[1] += centerDeltaY * 0.32;
          const headingDelta = Math.atan2(
            Math.sin(targetHeading - externalCameraHeading),
            Math.cos(targetHeading - externalCameraHeading)
          );
          externalCameraHeading += headingDelta * 0.25;
          const center = externalCameraCenter;
          const headingSin = Math.sin(externalCameraHeading);
          const headingCos = Math.cos(externalCameraHeading);
          const speed = Math.max(0, Number($scope.state.currentSpeed || 0));
          const intensity = Math.max(0, Math.min(2, Number(
            $scope.settings.dynamicZoomIntensity || 100
          ) / 100));
          // Connected Phone has much less map area than the in-game minimap.
          // Keep its initial view close, ease the speed response, and cap the
          // high-speed range so road detail remains useful on a phone screen.
          const speedRatio = Math.max(0, Math.min(1, speed / 160));
          const easedSpeed = speedRatio * speedRatio * (3 - 2 * speedRatio);
          const baseRadius = 220;
          const dynamicRadius = baseRadius + (720 - baseRadius) * easedSpeed;
          const targetRadius = Math.max(180, Math.min(
            1200,
            baseRadius + (dynamicRadius - baseRadius) * intensity
          ));
          const zoomUpdatedAt = performance.now();
          if (externalCameraRadius === null) {
            externalCameraRadius = targetRadius;
          } else {
            const elapsed = externalCameraZoomUpdatedAt > 0
              ? Math.max(0, Math.min(0.1, (zoomUpdatedAt - externalCameraZoomUpdatedAt) / 1000))
              : 0;
            const blend = 1 - Math.exp(-elapsed * 1.8);
            externalCameraRadius += (targetRadius - externalCameraRadius) * blend;
          }
          externalCameraZoomUpdatedAt = zoomUpdatedAt;
          const radius = externalCameraRadius;
          const visibleRoads = getExternalRoadsNear(center, radius);
          surfaces.forEach((canvas) => {
            const rect = canvas.getBoundingClientRect();
            if (rect.width < 20 || rect.height < 20) return;
            const quality = $scope.settings.externalMapQuality;
            const maximumRatio = quality === "eco" ? 1 : 2;
            const ratio = Math.min(maximumRatio, window.devicePixelRatio || 1);
            const width = Math.max(1, Math.round(rect.width * ratio));
            const height = Math.max(1, Math.round(rect.height * ratio));
            if (canvas.width !== width || canvas.height !== height) {
              canvas.width = width;
              canvas.height = height;
            }
            const ctx = canvas.getContext("2d");
            ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
            const w = rect.width;
            const h = rect.height;
            canvas.dataset.mapSpeed = speed.toFixed(2);
            canvas.dataset.mapRadius = radius.toFixed(2);
            canvas.dataset.mapTargetRadius = targetRadius.toFixed(2);
            ctx.fillStyle = "#0b1017";
            ctx.fillRect(0, 0, w, h);
            const scale = Math.min(w, h) / (radius * 2);
            const vehicleScreenY = h * 0.68;
            const project = (point) => {
              const worldX = Number(point[0]) - Number(center[0]);
              const worldY = Number(point[1]) - Number(center[1]);
              const localRight = worldX * headingCos - worldY * headingSin;
              const localForward = worldX * headingSin + worldY * headingCos;
              return [w / 2 + localRight * scale, vehicleScreenY - localForward * scale];
            };
            const visibleTerrainTiles = $scope.settings.externalTerrainEnabled === false
              ? [] : externalTerrainTiles;
            visibleTerrainTiles.forEach((tile) => {
              const image = tile.image;
              const sizeX = Number(tile.size[0]) || 0;
              const sizeY = Number(tile.size[1]) || 0;
              const offsetX = Number(tile.offset[0]) || 0;
              const offsetY = Number(tile.offset[1]) || 0;
              if (!image || !image.complete || !image.naturalWidth || !sizeX || !sizeY) return;
              const topLeft = project([offsetX, offsetY]);
              const topRight = project([offsetX + sizeX, offsetY]);
              const bottomLeft = project([offsetX, offsetY - sizeY]);
              ctx.save();
              ctx.globalAlpha = 0.72;
              ctx.transform(
                (topRight[0] - topLeft[0]) / image.naturalWidth,
                (topRight[1] - topLeft[1]) / image.naturalWidth,
                (bottomLeft[0] - topLeft[0]) / image.naturalHeight,
                (bottomLeft[1] - topLeft[1]) / image.naturalHeight,
                topLeft[0], topLeft[1]
              );
              ctx.drawImage(image, 0, 0);
              ctx.restore();
            });
            if (visibleTerrainTiles.length) {
              ctx.fillStyle = "rgba(5, 9, 14, .34)";
              ctx.fillRect(0, 0, w, h);
            }
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            visibleRoads.forEach((road) => {
              const a = project(road);
              const b = project([road[2], road[3]]);
              const drivability = Math.max(0, Math.min(1, Number(road[5] || 1)));
              ctx.strokeStyle = drivability < 0.5 ? "#202832" : "#313b46";
              ctx.lineWidth = Math.max(3, Math.min(13, Number(road[4] || 4) * scale * 2.4));
              ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
              ctx.strokeStyle = drivability < 0.5 ? "#53606b" : "#a3adb5";
              ctx.lineWidth = Math.max(1.25, ctx.lineWidth - 2.5);
              ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
            });
            const route = externalMapData.route || [];
            if (route.length > 1) {
              ctx.strokeStyle = "#fff"; ctx.lineWidth = 8; ctx.beginPath();
              route.forEach((point, index) => {
                const p = project(point);
                if (index) ctx.lineTo(p[0], p[1]); else ctx.moveTo(p[0], p[1]);
              });
              ctx.stroke();
              ctx.strokeStyle = "#1688ff"; ctx.lineWidth = 5; ctx.beginPath();
              route.forEach((point, index) => {
                const p = project(point);
                if (index) ctx.lineTo(p[0], p[1]); else ctx.moveTo(p[0], p[1]);
              });
              ctx.stroke();
              const target = project(route[route.length - 1]);
              ctx.fillStyle = "#ffd21c";
              ctx.beginPath(); ctx.arc(target[0], target[1], 7, 0, Math.PI * 2); ctx.fill();
            }
            const fleetMarkers = $scope.state.fleet && Array.isArray($scope.state.fleet.markers)
              ? $scope.state.fleet.markers : [];
            fleetMarkers.forEach((marker) => {
              if (!Array.isArray(marker.position)) return;
              const point = project(marker.position);
              if (point[0] < -12 || point[0] > w + 12 || point[1] < -12 || point[1] > h + 12) return;
              ctx.fillStyle = "#211432"; ctx.beginPath(); ctx.arc(point[0], point[1], 8, 0, Math.PI * 2); ctx.fill();
              ctx.fillStyle = "#9a4aff"; ctx.beginPath(); ctx.arc(point[0], point[1], 5, 0, Math.PI * 2); ctx.fill();
            });
            const pointerScale = Math.max(0.72, Math.min(1, Math.min(w, h) / 300));
            ctx.save(); ctx.translate(w / 2, vehicleScreenY); ctx.scale(pointerScale, pointerScale);
            ctx.fillStyle = "#ff791a"; ctx.strokeStyle = "#fff"; ctx.lineWidth = 2;
            ctx.beginPath(); ctx.moveTo(0, -15); ctx.lineTo(10, 12);
            ctx.lineTo(0, 8); ctx.lineTo(-10, 12); ctx.closePath(); ctx.fill(); ctx.stroke();
            ctx.restore();
          });
          const centerDistance = Math.hypot(centerDeltaX, centerDeltaY);
          const radiusDelta = Math.abs(targetRadius - radius);
          if (centerDistance > 0.15 || Math.abs(headingDelta) > 0.002 || radiusDelta > 0.25) {
            scheduleExternalMapDraw();
          }
        };

        const updateClock = () => {
          $scope.currentClock = new Date().toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
            hour12: $scope.settings.timeFormat !== "24h",
          });
        };

        this.startMode = () => callTaxiDriver("startMode");
        this.toggleFleet = () => {
          $scope.fleetOpen = !$scope.fleetOpen;
          $scope.shiftHistoryOpen = false;
          lastMinimapRect = "";
          if ($scope.fleetOpen) dismissPassengerChat();
          scheduleMinimapUpdate();
          syncExternalView();
        };
        this.fleetCommand = (action, args) => {
          const luaAction = bngApi.serializeToLua(String(action || ""));
          const luaArgs = bngApi.serializeToLua(args || {});
          bngApi.engineLua(`if taxiDriver_taxiDriver then taxiDriver_taxiDriver.fleetCommand(${luaAction}, ${luaArgs}) end`);
        };
        this.toggleShiftHistory = () => {
          if ($scope.state.shiftHistory && $scope.state.shiftHistory.restoring) return;
          $scope.shiftHistoryOpen = !$scope.shiftHistoryOpen;
        };
        this.resumeShift = (shiftId) => {
          const id = Math.max(1, Math.floor(Number(shiftId) || 0));
          $scope.profileOpen = false;
          $scope.fleetOpen = false;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.resumeShift(${id}) end`
          );
        };
        this.openVehicleSelector = () => callTaxiDriver("openVehicleSelector");
        this.toggleAutopilot = () => callTaxiDriver("toggleAutopilot");
        this.stopMode = () => callTaxiDriver("stopMode");
        this.toggleOfferSortMenu = () => {
          $scope.offerSortMenuOpen = !$scope.offerSortMenuOpen;
        };
        this.selectOfferSort = (value) => {
          if ($scope.offerSortOptions.some((option) => option.value === value)) {
            $scope.offerSort = value;
          }
          $scope.offerSortMenuOpen = false;
        };
        this.beginOfflineHold = (event) => {
          if ($scope.offlineConfirmOpen || offlineHoldTimer) return;
          if (event && event.button !== undefined && event.button !== 0) return;
          if (event) event.preventDefault();
          offlineHoldStartedAt = Date.now();
          $scope.offlineHoldProgress = 0;
          offlineHoldTimer = setInterval(() => {
            const progress = Math.min(100, (Date.now() - offlineHoldStartedAt) / 20);
            $scope.$evalAsync(() => {
              $scope.offlineHoldProgress = progress;
              if (progress >= 100 && offlineHoldTimer) completeOfflineHold();
            });
          }, 25);
        };
        this.cancelOfflineHold = () => stopOfflineHold();
        this.cancelOfflineConfirmation = () => {
          $scope.offlineConfirmOpen = false;
          scheduleMinimapUpdate();
        };
        this.confirmOfflineWithPassenger = () => {
          $scope.offlineConfirmOpen = false;
          bngApi.engineLua(
            'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.confirmDriverAbandonment() end'
          );
        };
        this.toggleMinimized = () => {
          $scope.phoneMinimized = !$scope.phoneMinimized;
          if ($scope.phoneMinimized) {
            dismissPassengerChat();
          }
          lastMinimapRect = "";
          scheduleMinimapUpdate();
        };
        this.toggleLocalPhone = () => {
          $scope.localPhoneOpen = !$scope.localPhoneOpen;
          if (!$scope.localPhoneOpen) {
            dismissPassengerChat();
            hideMinimap(true);
          }
          lastMinimapRect = "";
          scheduleMinimapUpdate();
        };
        this.toggleSettings = () => {
          if ($scope.settingsOpen && settingsSaveTimer) persistSettingsNow();
          $scope.settingsOpen = !$scope.settingsOpen;
          $scope.profileOpen = false;
          $scope.fleetOpen = false;
          $scope.fuelStationOpen = false;
          $scope.offlineConfirmOpen = false;
          $scope.settingsSaved = $scope.settingsOpen;
          if ($scope.settingsOpen) {
            $scope.cheatRating = Number($scope.state.rating || 5);
            $scope.cheatEnergyPercent = Math.max(0, Math.min(100,
              Number($scope.state.vehicleEnergy && $scope.state.vehicleEnergy.percent || 0)
            ));
            $scope.cheatEnergyDraft = $scope.cheatEnergyPercent;
            $scope.cheatResetArmed = false;
            dismissPassengerChat();
            hideMinimap();
            scheduleLanQr();
          }
          else scheduleMinimapUpdate();
        };
        this.toggleProfile = () => {
          $scope.profileOpen = !$scope.profileOpen;
          $scope.settingsOpen = false;
          $scope.fleetOpen = false;
          $scope.fuelStationOpen = false;
          $scope.offlineConfirmOpen = false;
          $scope.profileSaved = false;
          stopOfflineHold();
          if ($scope.profileOpen) {
            dismissPassengerChat();
            hideMinimap();
            requestProfileData();
            scheduleReviewPagination();
          } else {
            scheduleMinimapUpdate();
          }
        };
        this.selectProfileTab = (tab) => {
          if (!["identity", "reviews", "analytics", "vehicles", "shifts"].includes(tab)) return;
          $scope.profileTab = tab;
          if (tab === "reviews") {
            const content = appRoot.querySelector(".taxi-profile__content");
            if (content) content.scrollTop = 0;
            scheduleReviewPagination();
          }
        };
        this.selectAvatar = (avatar) => {
          if ($scope.avatarOptions.includes(avatar)) $scope.profileDraft.avatar = avatar;
          $scope.profileSaved = false;
        };
        this.saveProfile = () => {
          $scope.profileDraft = normalizeProfile($scope.profileDraft);
          saveProfileToLua($scope.profileDraft);
          $scope.profileSaved = true;
        };
        this.previousReviewPage = () => {
          $scope.reviewPage = Math.max(1, $scope.reviewPage - 1);
        };
        this.nextReviewPage = () => {
          $scope.reviewPage = Math.min($scope.getReviewPageCount(), $scope.reviewPage + 1);
        };
        this.selectLanguage = (languageCode) => {
          if (!i18n[languageCode]) return;
          $scope.settings.language = languageCode;
          $scope.language = languageCode;
          queueSettingsSave();
        };
        this.selectDifficulty = (preset) => {
          if (difficulties.includes(preset)) $scope.settings.difficulty = preset;
          queueSettingsSave();
        };
        this.selectAiDriverPreset = (preset) => {
          if (!aiDriverPresetNames.includes(preset)) return;
          const source = preset === "custom"
            ? Object.assign({}, $scope.settings.aiDriver, { preset: "custom" })
            : Object.assign({}, aiDriverPresetValues[preset], { preset });
          $scope.settings.aiDriver = normalizeAiDriver(source);
          queueSettingsSave();
        };
        this.toggleAiManeuvers = () => {
          $scope.aiManeuversOpen = !$scope.aiManeuversOpen;
        };
        this.toggleSettingsSection = (section) => {
          if (!Object.prototype.hasOwnProperty.call($scope.settingsSections, section)) return;
          const open = !$scope.settingsSections[section];
          if ($scope.externalPhoneMode) {
            Object.keys($scope.settingsSections).forEach((key) => {
              $scope.settingsSections[key] = false;
            });
          }
          $scope.settingsSections[section] = open;
          if (section !== "cheats") $scope.cheatResetArmed = false;
        };
        this.settingsChanged = () => {
          applyGameUiVolume();
          updateClock();
          scheduleMinimapUpdate();
          scheduleReviewPagination();
          queueSettingsSave();
        };
        this.selectExternalMapQuality = (quality) => {
          if (!["eco", "balanced", "smooth"].includes(quality)) return;
          $scope.settings.externalMapQuality = quality;
          this.settingsChanged();
        };
        this.selectUnitSystem = (unitSystem) => {
          $scope.settings.unitSystem = unitSystem === "imperial" ? "imperial" : "metric";
          this.settingsChanged();
        };
        this.selectTimeFormat = (timeFormat) => {
          $scope.settings.timeFormat = timeFormat === "24h" ? "24h" : "12h";
          this.settingsChanged();
        };
        this.previewAppVolume = () => {
          $scope.settings.appVolume = Math.max(
            0,
            Math.min(1, Number($scope.settings.appVolume) || 0)
          );
          applyGameUiVolume();
          queueSettingsSave();
        };
        this.testAppVolume = () => {
          this.previewAppVolume();
          const soundIds = ["click", "newRide", "offline", "online", "violation", "message", "overspeed"];
          const enabledSounds = soundIds.filter((soundId) =>
            !$scope.settings.soundToggles || $scope.settings.soundToggles[soundId] !== false
          );
          if (enabledSounds.length) {
            playAppSound(enabledSounds[Math.floor(Math.random() * enabledSounds.length)]);
          }
        };
        this.toggleRealisticMode = () => {
          $scope.settings.realisticMode = $scope.settings.realisticMode === true;
          persistSettingsNow();
        };
        this.toggleRandomEvents = () => {
          $scope.settings.randomEventsEnabled = $scope.settings.randomEventsEnabled === true;
          persistSettingsNow();
        };
        this.cheatSetRating = () => {
          const rating = Math.max(0, Math.min(5, Number($scope.cheatRating) || 0));
          $scope.cheatRating = rating;
          // Reflect the explicit cheat immediately. Lua remains authoritative
          // and publishes the same canonical value back in the next snapshot.
          $scope.state.rating = rating;
          $scope.profileProgress.rating = rating;
          const serializedRating = bngApi.serializeToLua(rating.toFixed(2));
          // This is deliberately a plain statement without `if`/`return` or a
          // callback. BeamNG wraps callback commands as Lua expressions, which
          // makes a conditional statement invalid and raises a Fatal Lua Error.
          // cheatSetRating publishes the authoritative HUD/profile snapshots.
          bngApi.engineLua(`taxiDriver_taxiDriver.cheatSetRating(${serializedRating})`);
        };
        this.cheatSetEnergyPercent = (event) => {
          const input = event && event.currentTarget && event.currentTarget.parentElement
            ? event.currentTarget.parentElement.querySelector('input[type="range"]')
            : null;
          const selectedValue = input ? input.value : $scope.cheatEnergyDraft;
          const percent = Math.max(0, Math.min(100,
            Math.round(Number(selectedValue) || 0)
          ));
          $scope.cheatEnergyPercent = percent;
          $scope.cheatEnergyDraft = percent;
          bngApi.engineLua(`taxiDriver_taxiDriver.cheatSetEnergyPercent(${percent})`);
        };
        this.cheatEnergyChanged = () => {
          $scope.cheatEnergyDraft = Math.max(0, Math.min(100,
            Math.round(Number($scope.cheatEnergyPercent) || 0)
          ));
        };
        this.cheatAddMoney = (amount) => {
          const allowed = [1, 5, 10, 50];
          const value = Number(amount);
          if (!allowed.includes(value)) return;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatAddMoney(${value}) end`
          );
        };
        this.cheatAddRandomReview = () => bngApi.engineLua(
          "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatAddRandomReview() end"
        );
        this.armCheatReset = () => {
          $scope.cheatResetArmed = true;
        };
        this.cancelCheatReset = () => {
          $scope.cheatResetArmed = false;
        };
        this.confirmCheatReset = () => {
          $scope.cheatResetArmed = false;
          $scope.cheatRating = 5;
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatResetProgress() end"
          );
        };
        this.openFuelStation = () => {
          if (!$scope.state.fuelStation || !$scope.state.fuelStation.available) return;
          $scope.fuelStationOpen = true;
          $scope.settingsOpen = false;
          $scope.profileOpen = false;
          $scope.offlineConfirmOpen = false;
          dismissPassengerChat();
          hideMinimap();
          bngApi.engineLua(
            'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestRealisticFuelData() end'
          );
        };
        this.handleFuelAction = () => {
          if (!$scope.state.active || !$scope.state.realisticMode) return;
          if ($scope.state.fuelDetour.active && $scope.state.fuelStation.available) {
            this.openFuelStation();
            return;
          }
          bngApi.engineLua(
            'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestFuelStop() end'
          );
        };
        this.closeFuelStation = () => {
          if ($scope.state.fuelStation.refueling.active) return;
          $scope.fuelStationOpen = false;
          bngApi.engineLua(
            'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.completeFuelStop() end'
          );
          scheduleMinimapUpdate();
        };
        this.cancelFuelRoute = () => {
          if ($scope.state.fuelStation.refueling.active) return;
          $scope.fuelStationOpen = false;
          bngApi.engineLua(
            'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cancelFuelStop() end'
          );
          scheduleMinimapUpdate();
        };
        this.selectFuelType = (energyType) => {
          if ($scope.state.fuelStation.refueling.active) return;
          if (!getFuelOption(energyType)) return;
          $scope.selectedFuelType = energyType;
          $scope.refuel.amount = 0;
        };
        this.updateRefuelAmount = () => clampRefuelAmount();
        this.setRefuelPreset = (preset) => {
          const option = getFuelOption($scope.selectedFuelType);
          if (!option || $scope.state.fuelStation.refueling.active) return;
          const affordable = Math.max(0, Number(option.affordableQuantity || 0));
          if (preset === "half") {
            $scope.refuel.amount = Math.max(0,
              Number(option.maxQuantity || 0) * 0.5 - Number(option.currentQuantity || 0));
          } else if (preset === "full") {
            $scope.refuel.amount = affordable;
          } else {
            $scope.refuel.amount = Number($scope.refuel.amount || 0) + Math.max(0, Number(preset || 0));
          }
          clampRefuelAmount();
        };
        this.purchaseFuel = () => {
          if ($scope.state.fuelStation.refueling.active || !$scope.state.fuelStation.vehicleStopped) return;
          const option = getFuelOption($scope.selectedFuelType);
          clampRefuelAmount();
          const quantity = Number($scope.refuel.amount || 0);
          if (!option || quantity <= 0) return;
          const energyType = bngApi.serializeToLua(option.energyType);
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.purchaseRealisticFuel(${energyType}, ${quantity.toFixed(3)}) end`
          );
        };
        this.acceptOrder = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0) return;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptOrder(${id}) end`
          );
        };
        this.acceptNextOffer = (offerId) => {
          const id = Math.floor(Number(offerId || 0));
          if (id <= 0) return;
          if ($scope.nextOfferUiRemaining <= 0) {
            expireNextOfferLocally(id);
            return;
          }
          clearNextOfferCountdown();
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptNextOffer(${id}) end`
          );
        };

        $scope.formatMoney = (value) => `$${Number(value || 0).toFixed(2)}`;
        $scope.formatOdometer = (meters) => {
          const distance = Math.max(0, Number(meters || 0));
          const value = $scope.settings.unitSystem === "imperial"
            ? distance / 1609.344 : distance / 1000;
          const fixed = value.toFixed(1).split(".");
          const decimalSeparator = $scope.language === "en" || $scope.language === "zh-CN" ? "." : ",";
          const unit = $scope.t($scope.settings.unitSystem === "imperial" ? "unitMile" : "unitKm");
          return `${fixed[0].padStart(4, "0")}${decimalSeparator}${fixed[1]} ${unit}`;
        };
        $scope.formatShiftDate = (timestamp) => {
          const value = Math.max(0, Number(timestamp || 0));
          if (!value) return "";
          return new Date(value * 1000).toLocaleString($scope.language || "en", {
            year: "numeric", month: "short", day: "numeric",
            hour: "2-digit", minute: "2-digit",
            hour12: $scope.settings.timeFormat !== "24h",
          });
        };
        $scope.formatDistance = (meters) => {
          const value = Math.max(0, Number(meters || 0));
          if ($scope.settings.unitSystem === "imperial") {
            return value >= 1609.344
              ? `${(value / 1609.344).toFixed(1)} ${$scope.t("unitMile")}`
              : `${Math.round(value * 3.28084)} ${$scope.t("unitFoot")}`;
          }
          return value >= 1000
            ? `${(value / 1000).toFixed(1)} ${$scope.t("unitKm")}`
            : `${Math.round(value)} ${$scope.t("unitMeter")}`;
        };
        $scope.formatSpeed = (kmh) => $scope.settings.unitSystem === "imperial"
          ? `${Math.round(Math.max(0, Number(kmh || 0)) * 0.621371)} ${$scope.t("unitMph")}`
          : `${Math.round(Math.max(0, Number(kmh || 0)))} ${$scope.t("unitKmh")}`;
        $scope.formatSpeedValue = (kmh) => $scope.settings.unitSystem === "imperial"
          ? Math.round(Math.max(0, Number(kmh || 0)) * 0.621371)
          : Math.round(Math.max(0, Number(kmh || 0)));
        $scope.getSpeedUnit = () => $scope.t(
          $scope.settings.unitSystem === "imperial" ? "unitMph" : "unitKmh"
        );
        $scope.formatEta = (minutes) => {
          const value = Math.max(0, Number(minutes || 0));
          if (value < 1) return `< 1 ${$scope.t("unitMin")}`;
          if (value < 60) return `${Math.ceil(value)} ${$scope.t("unitMin")}`;
          const hours = Math.floor(value / 60);
          return `${hours} ${$scope.t("unitHour")} ${Math.ceil(value - hours * 60)} ${$scope.t("unitMin")}`;
        };
        $scope.formatCountdown = (seconds) => {
          const value = Math.max(0, Math.ceil(Number(seconds || 0)));
          const minutes = Math.floor(value / 60);
          return `${minutes}:${String(value % 60).padStart(2, "0")}`;
        };
        $scope.getArrivalTime = (minutes) => {
          const arrival = new Date(Date.now() + Math.max(0, Number(minutes || 0)) * 60000);
          return arrival.toLocaleTimeString([], {
            hour: "2-digit", minute: "2-digit", hour12: $scope.settings.timeFormat !== "24h",
          });
        };
        $scope.getInitials = (name) =>
          String(name || "P")
            .split(/\s+/)
            .slice(0, 2)
            .map((part) => part.charAt(0).toUpperCase())
            .join("");
        $scope.getCalmnessEmoji = (value) => {
          const numeric = Number(value);
          const calmness = Number.isFinite(numeric)
            ? Math.max(0, Math.min(100, numeric))
            : 50;
          if (calmness < 15) return "😤";
          if (calmness < 30) return "😠";
          if (calmness < 45) return "😟";
          if (calmness < 60) return "😐";
          if (calmness < 75) return "🙂";
          if (calmness < 90) return "😌";
          return "😇";
        };
        $scope.getOfferName = (offer) => offer && offer.isDelivery
          ? $scope.t("deliveryOrder")
          : String(offer && offer.passengerName || "");
        $scope.formatCargoWeight = (value) => $scope.settings.unitSystem === "imperial"
          ? `${(Math.max(0, Number(value || 0)) * 2.20462).toFixed(0)} ${$scope.t("unitPound")}`
          : $scope.t("cargoWeightValue", { weight: Number(value || 0).toFixed(0) });
        $scope.getProgressPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.routeProgress || 0) * 100));
        $scope.getStarFill = (star) => {
          const rating = Number($scope.state.rating || 0);
          return Math.max(0, Math.min(100, (rating - (star - 1)) * 100));
        };
        $scope.getRatingPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.rating || 0) / 5 * 100));
        $scope.getUiScalePercent = () => Math.max(80, Math.min(
          180,
          Math.round((Number($scope.settings.uiScalePercent) || 100) / 10) * 10
        ));
        $scope.getUiScaleStyle = () => {
          const percent = $scope.getUiScalePercent();
          return {
            zoom: (percent / 100).toFixed(2),
          };
        };
        $scope.getUiScaleClass = () => {
          const percent = $scope.getUiScalePercent();
          if (percent >= 130) return "taxi-shell__scale-stage--xl";
          return "";
        };
        $scope.getAppVolumePercent = () => Math.round(
          Math.max(0, Math.min(1, Number($scope.settings.appVolume) || 0)) * 100
        );
        $scope.formatCustomDifficultyValue = (control) => {
          const value = Number($scope.settings.customDifficulty[control.key] || 0);
          if (control.unit === "kmh") return $scope.formatSpeed(value);
          if (control.unit === "percent") return `${value.toFixed(control.decimals)}%`;
          if (control.unit === "seconds") return `${value.toFixed(control.decimals)} ${$scope.t("unitSeconds")}`;
          if (control.unit === "g") return `${value.toFixed(control.decimals)} g`;
          return value.toFixed(control.decimals);
        };
        $scope.getPassengerOrderShare = () =>
          Math.max(0, 100 - Number($scope.settings.deliveryOrderSharePercent || 0));
        $scope.formatEconomyMultiplier = () =>
          `${Number($scope.settings.economyMultiplier || 1).toFixed(2)}×`;
        $scope.formatRating = (value) => Number(value || 0).toFixed(2);
        $scope.formatBonusPercent = (value) => Number(value || 0).toFixed(1).replace(/\.0$/, "");
        $scope.getOfferIncomePerMinute = (offer) => Number(offer && offer.estimatedFare || 0) /
          Math.max(0.1, Number(offer && offer.etaMinutes || 0));
        $scope.getOfferIncomePerKm = (offer) => Number(offer && offer.estimatedFare || 0) /
          Math.max(0.1, Number(offer && offer.rideDistance || 0) / 1000) *
          ($scope.settings.unitSystem === "imperial" ? 1.609344 : 1);
        $scope.getVehicleProfitPerDistance = (vehicle) => Number(vehicle && vehicle.profitPerKm || 0) *
          ($scope.settings.unitSystem === "imperial" ? 1.609344 : 1);
        $scope.getOfferSortLabel = () => {
          const selected = $scope.offerSortOptions.find((option) => option.value === $scope.offerSort);
          return $scope.t(selected ? selected.label : "sortFare");
        };
        $scope.getSortedOffers = () => ($scope.state.offers || []).slice().sort((left, right) => {
          const key = $scope.offerSort;
          if (key === "pickup") return Number(left.pickupDistance || 0) - Number(right.pickupDistance || 0);
          if (key === "duration") return Number(left.etaMinutes || 0) - Number(right.etaMinutes || 0);
          if (key === "perKm") return $scope.getOfferIncomePerKm(right) - $scope.getOfferIncomePerKm(left);
          return Number(right.estimatedFare || 0) - Number(left.estimatedFare || 0);
        });
        $scope.getPenaltyFareLoss = () => Math.max(
          0,
          Number($scope.state.estimatedFare || 0) - Number($scope.state.adjustedFare || 0)
        );
        $scope.getSortedProfileVehicles = () => $scope.profileVehicles.slice().sort((left, right) => {
          if ($scope.vehicleSort === "income") return Number(right.income || 0) - Number(left.income || 0);
          if ($scope.vehicleSort === "rides") return Number(right.completedRides || 0) - Number(left.completedRides || 0);
          return Number(right.distanceMeters || 0) - Number(left.distanceMeters || 0);
        });
        $scope.getSelectedFuelOption = () => getFuelOption($scope.selectedFuelType);
        $scope.getFuelDisplayUnit = (option) => option && option.unit === "L" &&
          $scope.settings.unitSystem === "imperial" ? $scope.t("unitGallon") : String(option && option.unit || "");
        $scope.getFuelDisplayQuantity = (quantity, option) => option && option.unit === "L" &&
          $scope.settings.unitSystem === "imperial" ? Number(quantity || 0) / 3.785411784 : Number(quantity || 0);
        $scope.getFuelDisplayPrice = (option) => {
          if (!option) return 0;
          return option.unit === "L" && $scope.settings.unitSystem === "imperial"
            ? Number(option.pricePerUnit || 0) * 3.785411784
            : Number(option.pricePerUnit || 0);
        };
        $scope.formatEnergyRange = (kilometers) => $scope.settings.unitSystem === "imperial"
          ? `${Math.round(Math.max(0, Number(kilometers || 0)) * 0.621371)} ${$scope.t("unitMile")}`
          : `${Math.round(Math.max(0, Number(kilometers || 0)))} ${$scope.t("unitKm")}`;
        $scope.formatDashboardEnergy = () => {
          const energy = $scope.state.vehicleEnergy || {};
          return `${$scope.getFuelDisplayQuantity(energy.quantity, energy).toFixed(2)} ${$scope.getFuelDisplayUnit(energy)}`;
        };
        $scope.getRouteFuelPercent = () => {
          const energy = $scope.state.vehicleEnergy || {};
          const suppliedPercent = Number(energy.percent);
          if (Number.isFinite(suppliedPercent) && suppliedPercent > 0) {
            return Math.max(0, Math.min(100, suppliedPercent));
          }
          const quantity = Math.max(0, Number(energy.quantity || 0));
          const maximum = Math.max(0, Number(energy.maxQuantity || 0));
          return maximum > 0 ? Math.max(0, Math.min(100, quantity / maximum * 100)) : 0;
        };
        $scope.getRouteFuelGaugeBackground = () => {
          const percent = $scope.getRouteFuelPercent().toFixed(2);
          return `conic-gradient(var(--taxi-accent) ${percent}%, rgba(255,255,255,.1) ${percent}% 100%)`;
        };
        $scope.getRefuelMaximum = () => {
          const option = getFuelOption($scope.selectedFuelType);
          return option ? Math.max(0, Number(option.affordableQuantity || 0)) : 0;
        };
        $scope.getRefuelCost = () => {
          const option = getFuelOption($scope.selectedFuelType);
          return option ? Number($scope.refuel.amount || 0) * Number(option.pricePerUnit || 0) : 0;
        };
        $scope.getRefuelSelectionPercent = () => {
          const maximum = $scope.getRefuelMaximum();
          return maximum > 0
            ? Math.max(0, Math.min(100, Number($scope.refuel.amount || 0) / maximum * 100))
            : 0;
        };
        $scope.getProjectedFuelPercent = () => {
          const option = getFuelOption($scope.selectedFuelType);
          if (!option) return 0;
          const maximum = Number(option.maxQuantity || 0);
          const added = maximum > 0 ? Number($scope.refuel.amount || 0) / maximum * 100 : 0;
          return Math.max(0, Math.min(100, Number(option.currentPercent || 0) + added));
        };
        $scope.getProjectedFuelRange = () => {
          const option = getFuelOption($scope.selectedFuelType);
          if (!option || Number(option.consumptionPer100Km || 0) <= 0) return 0;
          return (Number(option.currentQuantity || 0) + Number($scope.refuel.amount || 0)) /
            Number(option.consumptionPer100Km) * 100;
        };
        $scope.isProjectedFuelEnough = () => $scope.getProjectedFuelRange() * 1000 >=
          Math.max(0, Number($scope.state.distanceToTarget || 0));
        $scope.getDisplayedFuelPercent = () => {
          const option = getFuelOption($scope.selectedFuelType);
          if (!option) return 0;
          const session = $scope.state.fuelStation.refueling;
          const addedPercent = session.active && session.energyType === option.energyType &&
            Number(option.maxQuantity || 0) > 0
            ? Number(session.quantity || 0) / Number(option.maxQuantity) * 100 *
              Number(session.progress || 0)
            : 0;
          return Math.max(0, Math.min(100, Number(option.currentPercent || 0) + addedPercent));
        };
        $scope.shouldShowNextOffer = () => {
          const offer = $scope.state.nextOffer;
          if ($scope.settingsOpen || $scope.profileOpen || $scope.offlineConfirmOpen || $scope.fuelStationOpen) return false;
          if (!offer || $scope.state.phase !== "toDestination") return false;
          return offer.accepted ? $scope.nextOfferAcceptedVisible : $scope.nextOfferUiRemaining > 0;
        };
        $scope.shouldShowQueuedOrder = () => {
          const offer = $scope.state.nextOffer;
          if (!offer || offer.accepted !== true) return false;
          const activeTripId = Number($scope.state.activeTripId || 0);
          const queuedTripIsCurrent = activeTripId > 0 && Number(offer.id || 0) === activeTripId;
          return !queuedTripIsCurrent || $scope.state.phase === "toPickup";
        };
        $scope.getPhaseLabel = () => {
          if ($scope.state.isDelivery && $scope.state.phase === "toPickup") return $scope.t("phase_deliveryPickup");
          if ($scope.state.isDelivery && $scope.state.phase === "toDestination") return $scope.t("phase_deliveryDestination");
          if ($scope.state.isDelivery && $scope.state.phase === "boarding") return $scope.t("loadingCargo");
          if ($scope.state.isDelivery && $scope.state.phase === "alighting") return $scope.t("unloadingCargo");
          return $scope.t(`phase_${$scope.state.phase || "inactive"}`);
        };
        $scope.isNavigationPhase = () => minimapPhases.has($scope.state.phase);
        $scope.getCompactTitle = () => {
          if (!$scope.state.active) return "TaxiDriver";
          if ($scope.state.phase === "toFuelStation") {
            return $scope.state.fuelDetour.stationName || $scope.t("fuelRouteTitle");
          }
          if ($scope.state.isDelivery) return $scope.t("deliveryOrder");
          return $scope.state.passengerName || $scope.getPhaseLabel();
        };
        $scope.getProgressLabel = () => {
          const map = {
            toPickup: $scope.state.isDelivery ? "progress_deliveryPickup" : "progress_pickup",
            boarding: "progress_boarding",
            toStop: "progress_stop", stopWaiting: "progress_stopWaiting",
            toDestination: $scope.state.isDelivery ? "progress_delivery" : "progress_ride",
            toFuelStation: "progress_fuel",
            alighting: "progress_alighting",
          };
          return $scope.t(map[$scope.state.phase] || "progress_route");
        };
        $scope.getStatusText = () => {
          if ($scope.state.phase === "searching") {
            return $scope.state.offers.length
              ? $scope.t("offersDynamic", {
                  count: $scope.state.offers.length,
                  target: $scope.state.offerTargetCount,
                })
              : $scope.t("connecting");
          }
          return $scope.t("followRoute");
        };
        $scope.getPenaltyLabel = (event) => $scope.t(`penalty_${event.kind || "speeding"}`);
        $scope.getPhoneNotificationText = () => {
          if (!$scope.phoneToast) return "";
          const values = Object.assign({}, $scope.phoneToast.values || {});
          if ($scope.phoneToast.key === "notify_deliveryLoaded" && values.weight !== undefined) {
            values.weight = $scope.formatCargoWeight(values.weight);
          }
          return $scope.t($scope.phoneToast.key, values);
        };
        $scope.getPenaltyDetail = (event) => {
          if (event.kind === "speeding") return $scope.t("detail_speeding", {
            speed: $scope.formatSpeedValue(event.speedExcess || 0),
            unit: $scope.getSpeedUnit(),
            duration: Number(event.duration || 0).toFixed(1),
          });
          if (event.kind === "collision") return $scope.t("detail_collision", {
            damage: Number(event.damage || 0).toFixed(0),
          });
          if (event.kind === "cargoDamage") return $scope.t("detail_cargoDamage", {
            damage: Number(event.cargoDamagePercent || 0).toFixed(1),
          });
          if (event.kind === "aggression") return $scope.t("detail_aggression", {
            g: Number(event.peakG || 0).toFixed(2),
          });
          if (event.kind === "bonus") return $scope.t("detail_bonus");
          if (event.kind === "pickupDelay") return $scope.t("detail_pickupDelay", {
            time: $scope.formatCountdown(event.lateSeconds || 0),
          });
          if (event.kind === "fuelStop") return $scope.t("detail_fuelStop", {
            station: event.stationName || $scope.t("refuelTitle"),
          });
          return event.detail || "";
        };
        $scope.getQuality = () => Math.max(
          $scope.state.isDelivery ? 0 : 50,
          100 - Number($scope.state.penaltyPercent || 0)
        );

        const requestHudResync = () => {
          const now = Date.now();
          if (now - hudResyncRequestedAt < 750) return;
          hudResyncRequestedAt = now;
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestExternalHudState() end"
          );
        };

        $scope.$on("TaxiDriverHUDPatch", (_, patch) => {
          if (!patch || typeof patch !== "object") return;
          const patchEpoch = String(patch.epoch || "");
          const baseRevision = Number(patch.baseRevision);
          const patchRevision = Number(patch.revision);
          const versioned = patchEpoch && Number.isFinite(baseRevision) &&
            Number.isFinite(patchRevision);
          if (versioned) {
            if (patchEpoch === hudEpoch && patchRevision <= hudRevision) return;
            if (patchEpoch !== hudEpoch || baseRevision !== hudRevision ||
                patchRevision !== baseRevision + 1) {
              requestHudResync();
              return;
            }
          }
          const merged = Object.assign({}, $scope.state, patch.values || {});
          (Array.isArray(patch.removed) ? patch.removed : []).forEach((key) => {
            merged[key] = null;
          });
          if (versioned) {
            merged.hudEpoch = patchEpoch;
            merged.hudRevision = patchRevision;
          }
          $scope.$broadcast("TaxiDriverHUDState", merged);
        });
        $scope.$on("TaxiDriverHUDState", (_, data) => {
          if (!data) return;
          const incomingEpoch = String(data.hudEpoch || "");
          const incomingRevision = Number(data.hudRevision);
          if (incomingEpoch && Number.isFinite(incomingRevision)) {
            if (incomingEpoch === hudEpoch && incomingRevision <= hudRevision) return;
            if (incomingEpoch !== hudEpoch) {
              hudEpoch = incomingEpoch;
              hudRevision = 0;
            }
            hudRevision = incomingRevision;
            hudResyncRequestedAt = 0;
          }
          const previousMapPhase = $scope.state.phase;
          const previousMapSpeed = Number($scope.state.currentSpeed || 0);
          data.currentVehicle = Object.assign(
            { available: false, key: "", name: "", preview: "", distanceMeters: 0, completedRides: 0, income: 0 },
            data.currentVehicle || {}
          );
          data.vehicleEnergy = Object.assign(
            { available: false, energyType: "", quantity: 0, maxQuantity: 0, percent: 0, unit: "", estimatedRangeKm: 0 },
            data.vehicleEnergy || {}
          );
          data.fuelStation = normalizeFuelStation(data.fuelStation);
          data.fuelDetour = normalizeFuelDetour(data.fuelDetour);
          data.autopilot = Object.assign(
            { available: false, enabled: false, suspended: false, status: "off", reason: "", stuckSeconds: 0, recoveryAttempt: 0 },
            data.autopilot || {}
          );
          const refuelingJustCompleted = hudStateReceived &&
            data.fuelStation.refueling.completionId >
              Number($scope.state.fuelStation.refueling.completionId || 0);
          const passengerMoodChanged = hudStateReceived &&
            Number(data.activeTripId || 0) > 0 &&
            Number(data.activeTripId || 0) === Number($scope.state.activeTripId || 0) &&
            Number(data.passengerMoodChangeId || 0) >
              Number($scope.state.passengerMoodChangeId || 0);
          if (!data.active || data.phase === "driverAbandoning") {
            stopOfflineHold();
            $scope.offlineConfirmOpen = false;
          }
          const pickupJustStarted = data.phase === "boarding" && $scope.state.phase === "toPickup";
          if (pickupJustStarted) {
            $scope.nextOfferAcceptedVisible = false;
            if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
            acceptedOfferTimer = null;
            if ($scope.phoneToast && ["notify_orderAccepted", "notify_deliveryAccepted"].includes($scope.phoneToast.key)) {
              $scope.phoneToast = null;
              if (phoneToastTimer) clearTimeout(phoneToastTimer);
              phoneToastTimer = null;
            }
          }
          if (data.settings) {
            const backendSettings = normalizeSettings(data.settings);
            const resetUnrememberedLanguage = !settingsInitializedFromBackend &&
              !backendSettings.rememberLanguage && backendSettings.language !== "en";
            if (data.settingsNeedsLegacyImport && !legacyImportRequested) {
              legacyImportRequested = true;
              saveSettingsToLua(legacySettingsFound ? persisted : backendSettings);
            } else if (!data.settingsNeedsLegacyImport) {
              if (!settingsInitializedFromBackend && !backendSettings.rememberLanguage) {
                backendSettings.language = "en";
              }
              const backendFingerprint = settingsFingerprint(backendSettings);
              const pendingIsCurrent = pendingSettingsFingerprint &&
                Date.now() <= pendingSettingsDeadline;
              if (pendingIsCurrent && backendFingerprint !== pendingSettingsFingerprint) {
                // A periodic HUD packet can still contain the previous server
                // value while the debounced save is queued or in flight.
                // Preserve the user's local choice in the merged HUD state.
                data.settings = Object.assign({}, $scope.settings);
              } else {
                if (backendFingerprint === pendingSettingsFingerprint || !pendingIsCurrent) {
                  pendingSettingsFingerprint = "";
                  pendingSettingsDeadline = 0;
                }
                $scope.settings = backendSettings;
                $scope.language = backendSettings.language;
                data.settings = backendSettings;
                applyGameUiVolume();
              }
              if (!settingsInitializedFromBackend) {
                settingsInitializedFromBackend = true;
                try { localStorage.removeItem(settingsKey); } catch (_) {}
                if (resetUnrememberedLanguage) {
                  // Persist the one-time English fallback so a later full HUD
                  // snapshot cannot resurrect an intentionally unremembered
                  // language during the same UI session.
                  pendingSettingsFingerprint = settingsFingerprint(backendSettings);
                  pendingSettingsDeadline = Date.now() + 5000;
                  saveSettingsToLua(backendSettings);
                }
              }
            }
          }
          if (data.nextOffer && expiredNextOfferIds.has(Number(data.nextOffer.id))) {
            data.nextOffer = null;
          }
          syncNextOfferCountdown(data.nextOffer);
          const incomingNextOfferId = data.nextOffer ? Number(data.nextOffer.id || 0) : 0;
          const hasNewNextOffer = hudStateReceived && incomingNextOfferId > 0 &&
            data.nextOffer.accepted !== true && incomingNextOfferId !== lastAnnouncedNextOfferId;
          if (incomingNextOfferId > 0) lastAnnouncedNextOfferId = incomingNextOfferId;
          const hasNewAcceptedOffer = !pickupJustStarted && data.nextOffer && data.nextOffer.accepted &&
            (!$scope.state.nextOffer || !$scope.state.nextOffer.accepted);
          const hasNewNotification = data.notification && data.notification.id !== lastPhoneNotificationId &&
            !(pickupJustStarted && ["notify_orderAccepted", "notify_deliveryAccepted"].includes(data.notification.key));
          const becameOnline = hudStateReceived && data.active === true && $scope.state.active !== true;
          const becameOffline = hudStateReceived && data.active === false && $scope.state.active === true;
          const navigationPhase = ["toPickup", "toStop", "toDestination", "toFuelStation"].includes(data.phase);
          const overspeedThreshold = Number(data.speedLimit || 0) +
            Number($scope.settings.overspeedWarningKmh || 0);
          const isOverspeedWarning = data.active === true && navigationPhase &&
            Number(data.speedLimit || 0) > 0 && Number(data.currentSpeed || 0) > overspeedThreshold;
          if (becameOnline) playAppSound("online");
          if (becameOffline) playAppSound("offline");
          if (hasNewNextOffer) playAppSound("newRide");
          if (isOverspeedWarning && !overspeedWarningActive) playAppSound("overspeed");
          overspeedWarningActive = isOverspeedWarning;
          $scope.overspeedWarningActive = isOverspeedWarning;
          if ((hasNewNextOffer || hasNewNotification) && $scope.phoneMinimized &&
              !(data.lan && Number(data.lan.connected || 0) > 0)) {
            $scope.phoneMinimized = false;
          }
          if (hasNewNotification) {
            dismissPassengerChat();
            lastPhoneNotificationId = data.notification.id;
            $scope.phoneToast = data.notification;
            if (phoneToastTimer) clearTimeout(phoneToastTimer);
            phoneToastTimer = setTimeout(() => $scope.$evalAsync(() => {
              $scope.phoneToast = null;
              phoneToastTimer = null;
            }), 3600);
          }
          if (hasNewAcceptedOffer) {
            $scope.nextOfferAcceptedVisible = true;
            if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
            acceptedOfferTimer = setTimeout(() => $scope.$evalAsync(() => {
              $scope.nextOfferAcceptedVisible = false;
              acceptedOfferTimer = null;
            }), 1200);
          }
          // Empty Lua tables are serialized as objects, not JavaScript arrays.
          // Normalize list fields before using array methods or binding them in Angular.
          const penaltyEvents = Array.isArray(data.penaltyEvents) ? data.penaltyEvents : [];
          data.penaltyEvents = penaltyEvents;
          data.offers = Array.isArray(data.offers) ? data.offers : [];
          data.stopProgressMarkers = Array.isArray(data.stopProgressMarkers)
            ? data.stopProgressMarkers
            : [];
          const shiftHistory = data.shiftHistory && typeof data.shiftHistory === "object"
            ? data.shiftHistory
            : {};
          data.shiftHistory = Object.assign(
            { items: [], restoring: false, restoringId: 0 },
            shiftHistory,
            { items: Array.isArray(shiftHistory.items) ? shiftHistory.items : [] }
          );
          const fleet = data.fleet && typeof data.fleet === "object" ? data.fleet : {};
          data.fleet = Object.assign(
            { enabled: true, activeDrivers: 0, maxDrivers: 6, hiringFee: 75, wagePerTenMinutes: 12, ownerSharePercent: 35, stats: {}, drivers: [], markers: [], trafficCandidates: [], garage: [] },
            fleet,
            {
              drivers: Array.isArray(fleet.drivers) ? fleet.drivers : [],
              markers: Array.isArray(fleet.markers) ? fleet.markers : [],
              trafficCandidates: Array.isArray(fleet.trafficCandidates) ? fleet.trafficCandidates : [],
              garage: Array.isArray(fleet.garage) ? fleet.garage : [],
            }
          );
          if (data.active) $scope.shiftHistoryOpen = false;
          const penaltyPhase = ["toPickup", "toStop", "toDestination", "passengerStopDemand"].includes(data.phase);
          if (!penaltyPhase) {
            penaltyTrackingReady = false;
            knownPenaltyEventIds = new Set();
          } else if (!penaltyTrackingReady) {
            knownPenaltyEventIds = new Set(penaltyEvents.map((event) => event.id));
            penaltyTrackingReady = true;
          } else {
            const hasNewPenalty = penaltyEvents.some((event) => !knownPenaltyEventIds.has(event.id));
            penaltyEvents.forEach((event) => knownPenaltyEventIds.add(event.id));
            if (hasNewPenalty) playViolationSound();
          }
          data.penalties = Object.assign(emptyPenalties(), data.penalties || {});
          data.lan = Object.assign(
            { enabled: false, connected: 0, address: "", port: 8085, url: "" },
            data.lan || {}
          );
          const wasRemotelyConnected = Number($scope.state.lan && $scope.state.lan.connected || 0) > 0;
          const isRemotelyConnected = Number(data.lan.connected || 0) > 0;
          if (!wasRemotelyConnected && isRemotelyConnected) {
            $scope.localPhoneOpen = false;
            $scope.phoneMinimized = false;
            dismissPassengerChat();
          } else if (wasRemotelyConnected && !isRemotelyConnected) {
            $scope.localPhoneOpen = true;
          }
          $scope.state = Object.assign({}, $scope.state, data);
          scheduleLanQr();
          syncFuelStation($scope.state.fuelStation);
          if (passengerMoodChanged) {
            const moodDirection = data.passengerMoodChangeDirection === "up" ? "up" : "down";
            const moodVariant = Number(data.passengerMoodChangeId || 0) % 2 ? "a" : "b";
            $scope.passengerMoodFlash = `${moodDirection}-${moodVariant}`;
            if (passengerMoodFlashTimer) clearTimeout(passengerMoodFlashTimer);
            passengerMoodFlashTimer = setTimeout(() => $scope.$evalAsync(() => {
              $scope.passengerMoodFlash = "";
              passengerMoodFlashTimer = null;
            }), 950);
          }
          if (refuelingJustCompleted) {
            $scope.fuelStationOpen = false;
            $scope.refuel.amount = 0;
            bngApi.engineLua(
              'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.completeFuelStop() end'
            );
          }
          syncPassengerChat();
          hudStateReceived = true;
          lastMinimapRect = "";
          syncExternalView();
          if (externalPhoneMode) {
            if (previousMapPhase !== data.phase ||
                Math.abs(previousMapSpeed - Number(data.currentSpeed || 0)) >= 0.5) {
              scheduleMinimapUpdate();
            }
          } else if (canRenderMinimap($scope.state)) scheduleMinimapUpdate();
          else hideMinimap(minimapVisible);
        });
        $scope.$on("TaxiDriverExternalMapData", (_, data) => {
          if (!externalPhoneMode || !data) return;
          externalMapData = {
            revision: Number(data.revision || 0),
            route: Array.isArray(data.route) ? data.route : [],
            roads: [],
          };
          // Compatibility with builds that published roads together with the route.
          if (Array.isArray(data.roads)) addExternalRoads(data.roads, true);
          scheduleMinimapUpdate();
        });
        $scope.$on("TaxiDriverExternalRoadData", (_, data) => {
          if (!externalPhoneMode || !data) return;
          const revision = Number(data.revision || 0);
          const reset = data.reset === true || revision !== externalRoadRevision;
          if (reset) externalRoadRevision = revision;
          if (Array.isArray(data.terrainTiles)) setExternalTerrainTiles(data.terrainTiles);
          addExternalRoads(data.roads, reset);
          scheduleMinimapUpdate();
        });
        $scope.$on("TaxiDriverExternalVehicleState", (_, data) => {
          if (!externalPhoneMode || !data) return;
          const previous = externalVehicleState;
          externalVehicleState = data;
          const previousPosition = previous && previous.position || [];
          const position = data.position || [];
          const previousDirection = previous && previous.direction || [];
          const direction = data.direction || [];
          const moved = Math.hypot(
            Number(position[0] || 0) - Number(previousPosition[0] || 0),
            Number(position[1] || 0) - Number(previousPosition[1] || 0)
          ) > 0.05;
          const turned = Math.hypot(
            Number(direction[0] || 0) - Number(previousDirection[0] || 0),
            Number(direction[1] || 0) - Number(previousDirection[1] || 0)
          ) > 0.001;
          if (!previous || moved || turned) scheduleExternalMapDraw();
        });
        $scope.$on("TaxiDriverProfileData", (_, data) => {
          if (!data) return;
          if (Array.isArray(data.avatarOptions) && data.avatarOptions.length) {
            $scope.avatarOptions = data.avatarOptions;
          }
          const profile = normalizeProfile(data.profile);
          const progress = data.progress && typeof data.progress === "object" ? data.progress : {};
          const vehicles = Array.isArray(data.vehicles) ? data.vehicles : [];
          progress.reviews = Array.isArray(progress.reviews) ? progress.reviews : [];
          progress.ratingHistory = Array.isArray(progress.ratingHistory) ? progress.ratingHistory : [];
          progress.balanceHistory = Array.isArray(progress.balanceHistory) ? progress.balanceHistory : [];
          progress.aiRideHistory = Array.isArray(progress.aiRideHistory) ? progress.aiRideHistory : [];
          $scope.driverProfile = profile;
          $scope.profileDraft = Object.assign({}, profile);
          $scope.profileProgress = Object.assign({
            balance: 0, rating: 5, completedRides: 0, aiRideCount: 0,
            reviews: [], ratingHistory: [], balanceHistory: [], aiRideHistory: [],
          }, progress);
          $scope.profileReviews = progress.reviews.slice().reverse();
          $scope.profileVehicles = vehicles.map((vehicle) => ({
            key: String(vehicle.key || ""),
            name: String(vehicle.name || ""),
            preview: String(vehicle.preview || ""),
            distanceMeters: Math.max(0, Number(vehicle.distanceMeters || 0)),
            completedRides: Math.max(0, Math.floor(Number(vehicle.completedRides || 0))),
            aiRides: Math.max(0, Math.floor(Number(vehicle.aiRides || 0))),
            income: Math.max(0, Number(vehicle.income || 0)),
            passengerRides: Math.max(0, Math.floor(Number(vehicle.passengerRides || 0))),
            deliveryRides: Math.max(0, Math.floor(Number(vehicle.deliveryRides || 0))),
            averageIncome: Math.max(0, Number(vehicle.averageIncome || 0)),
            averageRating: Math.max(0, Number(vehicle.averageRating || 0)),
            penaltyLoss: Math.max(0, Number(vehicle.penaltyLoss || 0)),
            cargoDamageLoss: Math.max(0, Number(vehicle.cargoDamageLoss || 0)),
            fuelConsumed: Math.max(0, Number(vehicle.fuelConsumed || 0)),
            fuelCost: Math.max(0, Number(vehicle.fuelCost || 0)),
            rideDistanceMeters: Math.max(0, Number(vehicle.rideDistanceMeters || 0)),
            profitPerKm: Math.max(0, Number(vehicle.profitPerKm || 0)),
            lastSeen: Math.max(0, Number(vehicle.lastSeen || 0)),
          })).filter((vehicle) => vehicle.key && vehicle.name);
          $scope.reviewPage = Math.min($scope.reviewPage, $scope.getReviewPageCount());
          scheduleReviewPagination();
        });
        $scope.$on("TaxiDriverMinimapInvalidated", () => {
          lastMinimapRect = "";
          minimapVisible = false;
          if (uiVisible) scheduleMinimapUpdate();
        });
        $scope.$on("TaxiDriverUiSuspended", (_, data) => {
          if (externalPhoneMode) return;
          const suspended = !!(data && data.suspended === true);
          if ($scope.vehicleConfigSuspended === suspended) return;
          $scope.vehicleConfigSuspended = suspended;
          lastMinimapRect = "";
          if (suspended) hideMinimap(true);
          else if (uiVisible) scheduleMinimapUpdate();
        });
        $scope.$on("onCefVisibilityChanged", (_, visible) => {
          // This hook describes the in-game CEF layer. It may become hidden
          // while the independently opened phone page is still visible.
          if (externalPhoneMode) return;
          uiVisible = visible !== false;
          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapAppVisibility(${uiVisible ? "true" : "false"}) end`
          );
          if (uiVisible) {
            refreshGameUiVolume();
            scheduleMinimapUpdate();
          }
          else hideMinimap();
        });
        $scope.$on("SettingsChanged", (_, data) => {
          const value = data && data.values ? data.values.AudioUiVol : undefined;
          if (value === undefined) refreshGameUiVolume();
          else setGameUiVolume(value);
        });

        updateClock();
        refreshGameUiVolume();
        if (!externalPhoneMode) {
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapAppVisibility(true) end"
          );
        }
        const clockTimer = setInterval(() => $scope.$evalAsync(updateClock), 30000);
        const minimapTimer = externalPhoneMode ? null : setInterval(updateMinimap, 500);
        const resizeMap = () => {
          scheduleMinimapUpdate();
          scheduleReviewPagination();
        };
        window.addEventListener("resize", resizeMap);
        let externalHeartbeatTimer = null;
        let nativeHudHeartbeatTimer = null;
        const stopExternalMapWork = () => {
          if (externalMapFrame) cancelAnimationFrame(externalMapFrame);
          externalMapFrame = 0;
          if (externalMapDelayTimer) clearTimeout(externalMapDelayTimer);
          externalMapDelayTimer = 0;
        };
        const handleExternalDocumentVisibility = () => {
          externalViewKey = "";
          if (document.hidden) stopExternalMapWork();
          else {
            if (sendExternalHeartbeat) sendExternalHeartbeat();
            scheduleMinimapUpdate();
          }
          syncExternalView();
        };
        const stopExternalViewWatch = externalPhoneMode
          ? $scope.$watchGroup([
              "settingsOpen", "profileOpen", "fuelStationOpen", "offlineConfirmOpen",
              "fleetOpen", "phoneMinimized", "state.phase", "state.active", "settings.externalMapEnabled",
            ], syncExternalView)
          : null;
        if (externalPhoneMode) {
          sendExternalHeartbeat = () => {
            const view = getExternalView();
            const visible = view !== "hidden";
            bngApi.engineLua(
              `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.externalPhoneHeartbeat("${externalSessionToken}", "${view}", ${visible ? "true" : "false"}, "${hudEpoch}", ${hudRevision}) end`
            );
          };
          sendExternalHeartbeat();
          externalHeartbeatTimer = setInterval(sendExternalHeartbeat, 2500);
          document.addEventListener("visibilitychange", handleExternalDocumentVisibility);
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestExternalHudState() end"
          );
          syncExternalView();
        } else {
          const sendNativeHudHeartbeat = () => bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.hudClientHeartbeat("${hudEpoch}", ${hudRevision}) end`
          );
          sendNativeHudHeartbeat();
          nativeHudHeartbeatTimer = setInterval(sendNativeHudHeartbeat, 2500);
        }
        $scope.$on("$destroy", () => {
          if (settingsSaveTimer) persistSettingsNow();
          clearInterval(clockTimer);
          if (minimapTimer) clearInterval(minimapTimer);
          if (externalHeartbeatTimer) clearInterval(externalHeartbeatTimer);
          if (nativeHudHeartbeatTimer) clearInterval(nativeHudHeartbeatTimer);
          stopExternalMapWork();
          if (stopExternalViewWatch) stopExternalViewWatch();
          if (phoneToastTimer) clearTimeout(phoneToastTimer);
          if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
          if (passengerMoodFlashTimer) clearTimeout(passengerMoodFlashTimer);
          stopOfflineHold();
          stopPassengerChat();
          appRoot.removeEventListener("click", handleAppClick, true);
          if (externalPhoneMode) {
            appRoot.removeEventListener("pointerdown", handleExternalAudioUnlock, true);
            appRoot.removeEventListener("touchend", handleExternalAudioUnlock, true);
            appRoot.removeEventListener("keydown", handleExternalAudioUnlock, true);
            document.removeEventListener("visibilitychange", handleExternalAudioVisibility);
            document.removeEventListener("visibilitychange", handleExternalDocumentVisibility);
            window.removeEventListener("pageshow", handleExternalAudioPageShow);
            window.removeEventListener("focus", handleExternalAudioPageShow);
            externalAudioQueue = [];
            if (externalAudioContext && typeof externalAudioContext.close === "function") {
              if (typeof externalAudioContext.removeEventListener === "function") {
                externalAudioContext.removeEventListener("statechange", handleExternalAudioStateChange);
              } else if (externalAudioContext.onstatechange === handleExternalAudioStateChange) {
                externalAudioContext.onstatechange = null;
              }
              try { externalAudioContext.close(); } catch (_) {}
            }
          }
          window.removeEventListener("resize", resizeMap);
          if (reviewPaginationFrame) cancelAnimationFrame(reviewPaginationFrame);
          stopReviewPaginationWatch();
          if (reviewResizeObserver) reviewResizeObserver.disconnect();
          if (!externalPhoneMode) {
            hideMinimap();
            bngApi.engineLua(
              "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.disableExternalPhone() end"
            );
          }
        });
        if (!externalPhoneMode) {
          bngApi.engineLua(
            "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.disableExternalPhone() end"
          );
        }
        callTaxiDriver("requestHudState");
        scheduleMinimapUpdate();
      },
    };
  },
]);
