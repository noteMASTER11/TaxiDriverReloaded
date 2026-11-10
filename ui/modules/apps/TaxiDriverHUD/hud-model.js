let taxiDriverI18nPromise;
const loadTaxiDriverI18n = () => {
  if (taxiDriverI18nPromise) return taxiDriverI18nPromise;
  taxiDriverI18nPromise = new Promise((resolve) => {
    const fallback = () => resolve({ en: {} });
    try {
      const revision = typeof window !== "undefined" && window.TaxiDriverAssetRevision
        ? `?v=${encodeURIComponent(window.TaxiDriverAssetRevision)}` : "";
      const request = new XMLHttpRequest();
      request.open("GET", `/ui/modules/apps/TaxiDriverHUD/locales.json${revision}`, true);
      request.timeout = 10000;
      request.onload = () => {
        try {
          if ((request.status === 0 || (request.status >= 200 && request.status < 300)) &&
              request.responseText) {
            const data = JSON.parse(request.responseText);
            if (data && data.en && typeof data.en === "object") {
              resolve(data);
              return;
            }
          }
        } catch (error) {
          console.error("TaxiDriverHUD: unable to parse locales.json", error);
        }
        fallback();
      };
      request.onerror = request.ontimeout = fallback;
      request.send(null);
    } catch (error) {
      console.error("TaxiDriverHUD: unable to load locales.json", error);
      fallback();
    }
  });
  return taxiDriverI18nPromise;
};
/** Shared Vue 3 HUD state and behavior for the game and Connected Phone. */
export function createHudModel({ host, bridge, vue, externalPhoneMode: externalMode,
  storage = window.localStorage, session = window.sessionStorage }) {
  if (!host || !bridge?.api || !bridge?.events || !vue?.reactive || !vue?.watch || !vue?.nextTick) {
    throw new TypeError('TaxiDriverHUD requires a host, the game bridge and Vue 3 reactive/watch/nextTick');
  }
  const { reactive, watch, nextTick } = vue;
  const bngApi = bridge.api;
  const view = reactive({});
  const hud = {};
  let destroyed = false;
  const disposers = [];
  const localEvents = new Map();
  const onDestroy = callback => { disposers.push(callback); };
  // Own resources as soon as they are acquired, including during partial startup.
  const timeouts = new Set(), intervals = new Set();
  const setTimeout = (callback, delay) => {
    const timer = globalThis.setTimeout(() => {
      timeouts.delete(timer);
      if (!destroyed) callback();
    }, delay);
    timeouts.add(timer);
    return timer;
  };
  const clearTimeout = timer => { globalThis.clearTimeout(timer); timeouts.delete(timer); };
  const setInterval = (callback, delay) => {
    const timer = globalThis.setInterval(() => { if (!destroyed) callback(); }, delay);
    intervals.add(timer);
    return timer;
  };
  const clearInterval = timer => { globalThis.clearInterval(timer); intervals.delete(timer); };
  onDestroy(() => {
    for (const timer of timeouts) globalThis.clearTimeout(timer);
    for (const timer of intervals) globalThis.clearInterval(timer);
    timeouts.clear(); intervals.clear();
  });
  const listen = (target, name, callback, options) => {
    target.addEventListener(name, callback, options);
    onDestroy(() => target.removeEventListener(name, callback, options));
  };
  const scheduleUi = callback => nextTick(() => { if (!destroyed) callback(); });
  const pendingFrames = new Set();
  const requestFrame = callback => {
    const frame = requestAnimationFrame(timestamp => {
      pendingFrames.delete(frame);
      if (!destroyed) callback(timestamp);
    });
    pendingFrames.add(frame);
    return frame;
  };
  const cancelFrame = frame => { cancelAnimationFrame(frame); pendingFrames.delete(frame); };
  onDestroy(() => {
    for (const frame of pendingFrames) cancelAnimationFrame(frame);
    pendingFrames.clear();
  });
  const onGameEvent = (name, callback) => {
    const listener = (...args) => { if (!destroyed) callback(...args); };
    if (!localEvents.has(name)) localEvents.set(name, new Set());
    localEvents.get(name).add(listener);
    bridge.events.on(name, listener);
    onDestroy(() => {
      bridge.events.off(name, listener);
      localEvents.get(name)?.delete(listener);
    });
  };
  const emitLocal = (name, ...args) => {
    for (const listener of localEvents.get(name) || []) listener(...args);
  };
  const watchFields = (paths, callback) => {
    const getters = paths.map(path => () => path.split('.').reduce((value, key) => value?.[key], view));
    const stop = watch(getters, values => { if (!destroyed) callback(values); }, { flush: 'post' });
    onDestroy(stop);
    scheduleUi(() => callback(getters.map(get => get())));
    return stop;
  };
  const destroy = () => {
    if (destroyed) return;
    destroyed = true;
    // Dispose every owned resource, even if an external bridge has already closed.
    let firstError;
    for (const dispose of disposers.splice(0).reverse()) {
      try { dispose(); } catch (error) { firstError ||= error; }
    }
    localEvents.clear();
    if (firstError) console.error('TaxiDriverHUD: cleanup failed', firstError);
  };
  try {
    // window.TaxiDriverExternalPhoneMode is set by external.js, which only ever
    // bootstraps this app for the Connected Phone browser client. Prefer it over
    // beamng.ingame: that flag's availability/timing for external WS clients has
    // shifted across BeamNG versions (e.g. 0.39's UI/menu engine rewrite), and a
    // silent misdetection here disables the external map canvases with no error.
    const externalPhoneMode = externalMode === undefined ? window.TaxiDriverExternalPhoneMode === true ||
      (typeof beamng !== "undefined" && beamng.ingame === false) : externalMode === true;
    const externalSessionToken = externalPhoneMode
      ? (new URLSearchParams(window.location.search).get("token") || "").replace(/[^a-fA-F0-9]/g, "")
      : "";
    view.externalPhoneMode = externalPhoneMode;
    view.vehicleConfigSuspended = false;
    view.nativeUiSuspended = !externalPhoneMode;
    // BeamNG recreates UI apps when switching layouts (map, deliveries, etc.).
    // Keep this presentation choice within the CEF session, separate from
    // gameplay settings shared with Connected Phone.
    const viewStateKey = "taxiDriverHUD.view.v1";
    let savedView = {};
    if (!externalPhoneMode) {
      try { savedView = JSON.parse(session.getItem(viewStateKey) || "{}") || {}; }
      catch (_) { savedView = {}; }
    }
    const persistView = () => {
      if (externalPhoneMode) return;
      try {
        session.setItem(viewStateKey, JSON.stringify({
          minimized: view.phoneMinimized, superMinimized: view.phoneSuperMinimized,
        }));
      } catch (_) { /* Storage may be unavailable in an embedded browser. */ }
    };
    const normalizeInitialFuelPercent = value => Math.max(5, Math.min(30,
      Math.round(Number.isFinite(Number(value)) ? Number(value) : 5)));
    const i18n = reactive({ en: {} });
    const i18nPromise = loadTaxiDriverI18n();
    const settingsKey = "taxiDriverHUD.settings.v1";
    const languages = [
      { code: "en", label: "English" }, { code: "de", label: "Deutsch" },
      { code: "fr", label: "Français" }, { code: "es", label: "Español" },
      { code: "it", label: "Italiano" }, { code: "pl", label: "Polski" },
      { code: "uk", label: "Українська" },
      { code: "ru", label: "Русский" },
      { code: "pt-BR", label: "Português (Brasil)" },
      { code: "zh-CN", label: "简体中文" },
    ];
    const difficulties = ["elementary", "easy", "standard", "professional", "custom"];
    const homeDifficultyPresets = difficulties.filter(preset => preset !== "custom");
    const homePenaltyKeys = ["speeding", "collision", "aggression", "pickupDelay", "fuelStop", "cargoDamage"];
    const aiDriverPresetNames = ["novice", "cautious", "balanced", "assertive", "racer", "custom"];
    const aiDriverDefaults = {
      enabled: false,
      aggressionPercent: 40, followingTimeGap: 2.3, minimumFollowingDistance: 4,
      brakingDeceleration: 3.5, trafficWaitSeconds: 3,
      obeySpeedLimits: true, laneDiscipline: true, strictGpsRoute: false,
    };
    const aiDriverPresetValues = {
      novice: Object.assign({}, aiDriverDefaults, {
        aggressionPercent: 30, followingTimeGap: 3.4, minimumFollowingDistance: 7,
        brakingDeceleration: 2.5, trafficWaitSeconds: 6,
      }),
      cautious: Object.assign({}, aiDriverDefaults, {
        aggressionPercent: 35, followingTimeGap: 2.8, minimumFollowingDistance: 5.5,
        brakingDeceleration: 3, trafficWaitSeconds: 4,
      }),
      balanced: Object.assign({}, aiDriverDefaults),
      assertive: Object.assign({}, aiDriverDefaults, {
        aggressionPercent: 50, followingTimeGap: 1.9, minimumFollowingDistance: 3.2,
        brakingDeceleration: 4.2, trafficWaitSeconds: 2,
      }),
      racer: Object.assign({}, aiDriverDefaults, {
        aggressionPercent: 85, followingTimeGap: 1.3, minimumFollowingDistance: 2,
        brakingDeceleration: 6, trafficWaitSeconds: 1,
        obeySpeedLimits: false, laneDiscipline: false,
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
      const obeySpeedLimits = settings.obeySpeedLimits === undefined
        ? settings.obeyTrafficRules !== false : settings.obeySpeedLimits !== false;
      return {
        enabled: value.enabled === true,
        preset,
        aggressionPercent: clampNumber(settings.aggressionPercent, base.aggressionPercent, 30, 100),
        followingTimeGap: clampNumber(settings.followingTimeGap, base.followingTimeGap, 1, 4),
        minimumFollowingDistance: clampNumber(settings.minimumFollowingDistance,
          base.minimumFollowingDistance, 2, 10),
        brakingDeceleration: clampNumber(settings.brakingDeceleration,
          base.brakingDeceleration, 2, 8),
        trafficWaitSeconds: clampNumber(settings.trafficWaitSeconds,
          base.trafficWaitSeconds, 1, 10),
        obeySpeedLimits,
        laneDiscipline: settings.laneDiscipline !== false,
        strictGpsRoute: value.strictGpsRoute === true,
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
    const randomEventDefaults = {
      cancellation: 8,
      destinationChange: 10,
      additionalStop: 10,
      tip: 30,
      fragileCargo: 28,
      policeCheck: 9,
      passengerNoShow: 7,
      vipQuietRide: 12,
      forgottenItem: 8,
      roadClosure: 10,
    };
    const normalizeRandomEvents = (source) => {
      const value = source && typeof source === "object" ? source : {};
      return Object.keys(randomEventDefaults).reduce((result, key) => {
        const event = value[key] && typeof value[key] === "object" ? value[key] : {};
        const chance = Number(event.chancePercent);
        const policeConfirmed = key === "policeCheck" && event.preloadConfirmed === true;
        result[key] = {
          enabled: key === "policeCheck"
            ? event.enabled === true && policeConfirmed
            : event.enabled !== false,
          chancePercent: Math.round(Math.max(0, Math.min(100,
            Number.isFinite(chance) ? chance : randomEventDefaults[key]
          ))),
          ...(key === "policeCheck" ? { preloadConfirmed: policeConfirmed } : {}),
        };
        return result;
      }, {});
    };
    let persisted = {};
    let legacySettingsFound = false;
    try {
      const legacyValue = storage.getItem(settingsKey);
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
    const supportsLanguage = code => languages.some(language => language.code === code);
    const initialLanguage = persisted.rememberLanguage && supportsLanguage(persisted.language) ? persisted.language : "en";
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
    const initialLanManualAddress = typeof persisted.lanManualAddress === "string"
      ? persisted.lanManualAddress : "";
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

    view.languages = languages;
    view.difficulties = difficulties;
    view.aiDriverPresets = aiDriverPresetNames;
    view.homeDifficultyPresets = homeDifficultyPresets;
    view.isHomeDifficultySelected = preset => view.settings.difficulty === preset &&
      (preset === "elementary" || homePenaltyKeys.every(key => view.settings.penaltyToggles[key] !== false));
    view.hasHomeDifficultyPreset = () => homeDifficultyPresets.some(view.isHomeDifficultySelected);
    view.language = initialLanguage;
    view.settingsOpen = false;
    view.fleetOpen = false;
    view.settingsSaved = false;
    view.settingsSections = {
      general: true, gameplay: false, randomEvents: false, aiDriver: false, fleet: false, navigation: false, audio: false, connectivity: false, cheats: false,
    };
    view.settingsNavigation = [
      { key: "general", label: "settingsGeneral", icon: "Aa" },
      { key: "gameplay", label: "settingsGameplay", icon: "!" },
      { key: "randomEvents", label: "randomEvents", icon: "⚡" },
      { key: "aiDriver", label: "settingsAiDriver", icon: "AI" },
      { key: "fleet", label: "settingsFleet", icon: "F" },
      { key: "navigation", label: "settingsNavigation", icon: "→" },
      { key: "audio", label: "settingsAudio", icon: "♫" },
      { key: "connectivity", label: "settingsConnectivity", icon: "▤" },
      { key: "cheats", label: "settingsCheats", icon: "!", danger: true },
    ];
    view.customDifficultyGroups = [
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
    view.penaltyToggleOptions = [
      { key: "speeding", label: "penalty_speeding", help: "penaltyToggleSpeedingHelp" },
      { key: "collision", label: "penalty_collision", help: "penaltyToggleCollisionHelp" },
      { key: "aggression", label: "penalty_aggression", help: "penaltyToggleAggressionHelp" },
      { key: "pickupDelay", label: "penalty_pickupDelay", help: "penaltyTogglePickupHelp" },
      { key: "fuelStop", label: "penalty_fuelStop", help: "penaltyToggleFuelStopHelp" },
      { key: "rushBonus", label: "penalty_bonus", help: "penaltyToggleRushHelp" },
      { key: "cargoDamage", label: "penalty_cargoDamage", help: "penaltyToggleCargoHelp" },
    ];
    view.randomEventOptions = [
      { key: "cancellation", label: "randomEventCancellation", help: "randomEventCancellationHelp" },
      { key: "destinationChange", label: "randomEventDestinationChange", help: "randomEventDestinationChangeHelp" },
      { key: "additionalStop", label: "randomEventAdditionalStop", help: "randomEventAdditionalStopHelp" },
      { key: "tip", label: "randomEventTip", help: "randomEventTipHelp" },
      { key: "fragileCargo", label: "randomEventFragileCargo", help: "randomEventFragileCargoHelp" },
      { key: "policeCheck", label: "randomEventPoliceCheck", help: "randomEventPoliceCheckHelp" },
      { key: "passengerNoShow", label: "randomEventPassengerNoShow", help: "randomEventPassengerNoShowHelp" },
      { key: "vipQuietRide", label: "randomEventVipQuietRide", help: "randomEventVipQuietRideHelp" },
      { key: "forgottenItem", label: "randomEventForgottenItem", help: "randomEventForgottenItemHelp" },
      { key: "roadClosure", label: "randomEventRoadClosure", help: "randomEventRoadClosureHelp" },
    ];
    view.soundToggleOptions = [
      { key: "click", label: "sound_click" },
      { key: "newRide", label: "sound_newRide" },
      { key: "online", label: "sound_online" },
      { key: "offline", label: "sound_offline" },
      { key: "violation", label: "sound_violation" },
      { key: "message", label: "sound_message" },
      { key: "overspeed", label: "sound_overspeed" },
    ];
    view.cheatRating = 5;
    view.cheatEnergyPercent = 0;
    view.cheatEnergyDraft = 0;
    view.cheatResetArmed = false;
    view.profileOpen = false;
    view.profileTab = "identity";
    view.profileSaved = false;
    view.reviewPage = 1;
    view.reviewsPerPage = 6;
    view.expandedReviewId = null;
    view.offlineHoldProgress = 0;
    view.offlineConfirmOpen = false;
    view.policeCheckConfirmOpen = false;
    view.aiDriverConfirmOpen = false;
    view.phoneMinimized = savedView.minimized === true;
    view.phoneSuperMinimized = savedView.superMinimized === true;
    view.collapseAttention = false;
    view.localPhoneOpen = true;
    view.phoneToast = null;
    view.passengerChat = null;
    view.passengerMoodFlash = "";
    view.nextOfferAcceptedVisible = false;
    view.fuelStationOpen = false;
    view.shiftHistoryOpen = false;
    view.shiftHistoryVisibleCount = 30;
    view.newShiftSheenActive = true;
    let newShiftSheenFallback = setTimeout(() => {
      scheduleUi(() => { view.newShiftSheenActive = false; });
      newShiftSheenFallback = null;
    }, 1250);
    const handleNewShiftAnimationEnd = (event) => {
      if (!event || event.animationName !== "taxi-start-sheen") return;
      scheduleUi(() => { view.newShiftSheenActive = false; });
      if (newShiftSheenFallback) {
        clearTimeout(newShiftSheenFallback);
        newShiftSheenFallback = null;
      }
    };
    listen(host, "animationend", handleNewShiftAnimationEnd);
    onDestroy(() => {
      host.removeEventListener("animationend", handleNewShiftAnimationEnd);
      if (newShiftSheenFallback) clearTimeout(newShiftSheenFallback);
    });
    view.selectedFuelType = "";
    view.refuel = { amount: 0 };
    view.settings = {
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
      lanManualAddress: initialLanManualAddress,
      externalMapEnabled: initialExternalMapEnabled,
      externalTerrainEnabled: initialExternalTerrainEnabled,
      externalMapQuality: initialExternalMapQuality,
      silentMode: initialSilentMode,
      showRouteGuidance: initialShowRouteGuidance,
      realisticMode: initialRealisticMode,
      initialFuelPercent: normalizeInitialFuelPercent(persisted.initialFuelPercent),
      randomEventsEnabled: initialRandomEventsEnabled,
      randomEvents: normalizeRandomEvents(persisted.randomEvents),
      aiDebugLogging: persisted.aiDebugLogging === true,
      aiDriver: normalizeAiDriver(persisted.aiDriver),
      fleet: normalizeFleet(persisted.fleet),
      godMode: persisted.godMode === true,
      debugLogging: persisted.debugLogging !== false,
    };
    view.driverProfile = { fullName: "John Doe", birthDate: "", avatar: "🙂" };
    view.profileDraft = Object.assign({}, view.driverProfile);
    view.profileProgress = {
      reviews: [], ratingHistory: [], balanceHistory: [], aiRideHistory: [],
      balance: 0, rating: 5, completedRides: 0, aiRideCount: 0,
    };
    view.profileReviews = [];
    view.profileVehicles = [];
    view.vehicleSort = "distance";
    view.vehicleSortMenuOpen = false;
    view.vehicleSortOptions = [
      { value: "distance", label: "distance" },
      { value: "income", label: "vehicleIncome" },
      { value: "rides", label: "vehicleTrips" },
    ];
    view.offerSort = "fare";
    view.offerSortMenuOpen = false;
    view.offerSortOptions = [
      { value: "fare", label: "sortFare" },
      { value: "pickup", label: "sortPickup" },
      { value: "distance", label: "sortDistance" },
      { value: "duration", label: "sortDuration" },
      { value: "perKm", label: "sortPerKm" },
    ];
    view.penaltiesExpanded = false;
    view.avatarOptions = [
      "🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔",
      "👨‍🦰", "👩‍🦰", "👨‍🦱", "👩‍🦱", "👨‍🦳", "👩‍🦳", "🧑‍✈️", "🧑‍💼",
      "🧑‍🔧", "🦸", "🥷", "🤠", "🧢", "🎩", "🚕", "🏁",
      "🐻", "🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐧",
    ];

    view.t = (key, values) => {
      const dictionary = i18n[view.language] || i18n.en;
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

    view.state = {
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
      repairStation: {
        available: false, id: "", vehicleStopped: false, damagePercent: 0, price: 0, canRepair: false, balance: 0,
        repairing: { active: false, completing: false, cost: 0, duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0 },
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
    view.stars = [1, 2, 3, 4, 5];

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
    let trackedNextOfferDeadline = 0;
    const expiredNextOfferIds = new Set();
    view.nextOfferUiRemaining = 0;
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
    let offlineHoldTimer = null;
    let offlineHoldButton = null;
    let activeFuelStationId = "";
    let activeRepairStationId = "";
    let settingsSaveTimer = null;
    let pendingSettingsFingerprint = "";
    let pendingSettingsDeadline = 0;
    let overspeedWarningActive = false;
    view.overspeedWarningActive = false;

    const clampAudioVolume = (value) => Math.max(0, Math.min(1, Number(value) || 0));
    const applyGameUiVolume = () => {
      const appVolume = clampAudioVolume(view.settings.appVolume);
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
      pool.baseVolume * gameUiVolume * clampAudioVolume(view.settings.appVolume)
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
        listen(externalAudioContext, "statechange", handleExternalAudioStateChange);
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
          pool.baseVolume * gameUiVolume * clampAudioVolume(view.settings.appVolume)
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
      if (view.settings.silentMode) return;
      if (view.settings.soundToggles && view.settings.soundToggles[soundId] === false) return;
      if (!externalPhoneMode && view.state && view.state.lan &&
          Number(view.state.lan.connected || 0) > 0) return;
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
      view.state.active === true &&
      view.state.phase === "toPickup" &&
      view.state.isDelivery !== true &&
      Number(view.state.activeTripId || 0) > 0 &&
      String(view.state.passengerName || "").length > 0;
    const dismissPassengerChat = () => {
      if (passengerChatHideTimer) clearTimeout(passengerChatHideTimer);
      passengerChatHideTimer = null;
      view.passengerChat = null;
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
      passengerChatTimer = setTimeout(() => scheduleUi(() => {
        passengerChatTimer = null;
        if (generation !== passengerChatGeneration || !isPassengerChatEligible()) return;
        if (view.settingsOpen || view.profileOpen || view.phoneMinimized || view.phoneToast) {
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
        view.passengerChat = {
          passengerName: passengerChatPassenger,
          sentAt: new Date().toLocaleTimeString([], {
            hour: "2-digit", minute: "2-digit", hour12: view.settings.timeFormat !== "24h",
          }),
          content: messages[messageIndex],
          mood: passengerChatMood.id,
        };
        playAppSound("message");
        passengerChatHideTimer = setTimeout(() => scheduleUi(() => {
          passengerChatHideTimer = null;
          view.passengerChat = null;
          if (generation === passengerChatGeneration && isPassengerChatEligible() &&
              passengerChatMessageCount < passengerChatMessageTarget) {
            schedulePassengerChat(false);
          }
        }), passengerChatDisplayMs);
      }), delay);
    };
    const syncPassengerChat = () => {
      if (!isPassengerChatEligible()) {
        if (passengerChatPassenger || passengerChatTimer || view.passengerChat) stopPassengerChat();
        return;
      }
      const tripId = Number(view.state.activeTripId || 0);
      const passengerName = String(view.state.passengerName || "");
      if (tripId === passengerChatTripId && passengerName === passengerChatPassenger && passengerChatMood) {
        if (!passengerChatTimer && !view.passengerChat &&
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

    const appRoot = host;
    if (!externalPhoneMode) {
      const textInputTypes = new Set(['text', 'search', 'email', 'password', 'tel', 'url', 'number',
        'date', 'datetime-local', 'month', 'time', 'week']);
      const editableElement = element => {
        if (!element || element.disabled || element.readOnly) return null;
        const tag = String(element.tagName || '').toLowerCase();
        if (tag === 'input') return textInputTypes.has(String(element.type || 'text').toLowerCase()) ? element : null;
        if (tag === 'textarea') return element;
        const editable = element.closest?.('[contenteditable]');
        return editable && editable.getAttribute('contenteditable') !== 'false' ? editable : null;
      };
      let nativeTypingOwned = false;
      let typingWindowActive = true;
      const releaseNativeTyping = () => {
        if (!nativeTypingOwned) return;
        nativeTypingOwned = false;
        const focused = editableElement(document.activeElement);
        // A native editor outside this HUD manages its own typing lifecycle.
        if (focused && !appRoot.contains(focused)) return;
        bngApi.engineLua('if setCEFTyping then setCEFTyping(false) end');
      };
      const syncNativeTyping = () => {
        const focused = editableElement(document.activeElement);
        if (focused && appRoot.contains(focused) && !document.hidden && typingWindowActive) {
          if (!nativeTypingOwned) {
            nativeTypingOwned = true;
            bngApi.engineLua('if setCEFTyping then setCEFTyping(true) end');
          }
        } else releaseNativeTyping();
      };
      listen(appRoot, 'focusin', syncNativeTyping, true);
      listen(appRoot, 'focusout', () => scheduleUi(syncNativeTyping), true);
      const stopTypingKeyPropagation = event => {
        if (editableElement(event.target)) event.stopPropagation();
      };
      listen(appRoot, 'keydown', stopTypingKeyPropagation);
      listen(appRoot, 'keyup', stopTypingKeyPropagation);
      listen(window, 'blur', () => { typingWindowActive = false; releaseNativeTyping(); });
      listen(window, 'focus', () => { typingWindowActive = true; syncNativeTyping(); });
      listen(document, 'visibilitychange', () => document.hidden ? releaseNativeTyping() : syncNativeTyping());
      onGameEvent('CEFTypingLostFocus', () => {
        const focused = editableElement(document.activeElement);
        if (nativeTypingOwned && focused && appRoot.contains(focused)) focused.blur();
        releaseNativeTyping();
      });
      const typingObserver = typeof window.MutationObserver === 'function'
        ? new window.MutationObserver(() => { if (nativeTypingOwned) syncNativeTyping(); }) : null;
      typingObserver?.observe(appRoot, { childList: true, subtree: true });
      onDestroy(() => { typingObserver?.disconnect(); releaseNativeTyping(); });
    }
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
      listen(appRoot, "pointerdown", handleExternalAudioUnlock, true);
      listen(appRoot, "touchend", handleExternalAudioUnlock, true);
      listen(appRoot, "keydown", handleExternalAudioUnlock, true);
      listen(document, "visibilitychange", handleExternalAudioVisibility);
      listen(window, "pageshow", handleExternalAudioPageShow);
      listen(window, "focus", handleExternalAudioPageShow);
    }
    let lastLanQrUrl = "";
    const renderLanQr = () => {
      if (!view.settingsOpen || !view.settings.lanEnabled) return;
      const target = appRoot.querySelector(".taxi-lan__qr-code");
      if (!target) return;
      const url = String(view.state.lan && view.state.lan.url || "");
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
    const scheduleLanQr = () => scheduleUi(() => requestFrame(renderLanQr));
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
    listen(appRoot, "click", handleAppClick, true);

    const callTaxiDriver = (functionName, ...args) => {
      bngApi.engineLua(
        `if not taxiDriver_taxiDriver then extensions.load("taxiDriver_taxiDriver") end; taxiDriver_taxiDriver.${functionName}(${args.map(value => bngApi.serializeToLua(value)).join(', ')})`
      );
    };

    const emptyEarthField = () => ({ query: '', selected: null, results: [], searching: false, error: '' });
    const normalizeEarthField = field => ({ ...emptyEarthField(), ...field,
      results: Array.isArray(field?.results) ? field.results.slice(0, 8) : [],
    });
    const normalizeEarth = snapshot => ({
      available: false, status: 'absent', mode: 'vehicle', error: '', canNavigate: false, gps: null, owner: '',
      maxRandomKm: 50, randomAttempt: 0, startedTripId: 0,
      withoutPassenger: false, location: '', freeRoute: {active: false},
      ...snapshot,
      a: normalizeEarthField(snapshot?.a), b: normalizeEarthField(snapshot?.b),
      route: { status: 'idle', distanceM: 0, durationS: 0, from: null, to: null, error: '', ...snapshot?.route },
    });
    view.earth = normalizeEarth();
    view.earthOpen = false;
    view.earthStarting = false;
    view.earthActive = { a: -1, b: -1 };
    view.earthExpanded = { a: false, b: false };
    const earthDirty = { a: false, b: false };
    const earthEditTimers = { a: null, b: null };
    const earthOwner = `hud-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    let earthHeartbeat = null;
    let earthAwaitingOwnerAck = false;
    let earthStartTimer = null;
    const earthCommand = (action, args = {}) => callTaxiDriver('earthCommand', action, { ...args, owner: earthOwner });
    const cancelEarthEdits = () => {
      for (const field of ['a', 'b']) {
        if (earthEditTimers[field]) clearTimeout(earthEditTimers[field]);
        earthEditTimers[field] = null;
      }
    };
    const stopEarthWork = () => {
      cancelEarthEdits();
      if (earthStartTimer !== null) clearTimeout(earthStartTimer);
      earthStartTimer = null;
      view.earthStarting = false;
      if (earthHeartbeat !== null) clearInterval(earthHeartbeat);
      earthHeartbeat = null;
      earthAwaitingOwnerAck = false;
      view.earthOpen = false;
      view.earthExpanded = { a: false, b: false };
    };
    onDestroy(() => {
      const wasOpen = view.earthOpen;
      stopEarthWork();
      if (wasOpen) earthCommand('close');
    });
    const applyEarth = snapshot => {
      if (!snapshot || typeof snapshot !== 'object') return;
      const incoming = normalizeEarth(snapshot);
      const hasOwner = typeof snapshot.owner === 'string';
      if (view.earthOpen && !incoming.available) {
        stopEarthWork();
        earthDirty.a = earthDirty.b = false;
        if (incoming.owner === earthOwner) earthCommand('close');
        scheduleMinimapUpdate();
      }
      if (view.earthOpen && earthAwaitingOwnerAck && hasOwner && incoming.owner !== earthOwner) return;
      if (incoming.owner === earthOwner) earthAwaitingOwnerAck = false;
      if (view.earthOpen && hasOwner && incoming.owner !== earthOwner) {
        stopEarthWork();
        earthDirty.a = earthDirty.b = false;
        scheduleMinimapUpdate();
      }
      for (const field of ['a', 'b']) {
        if (earthDirty[field] && incoming[field].query !== view.earth[field].query) {
          incoming[field] = { ...view.earth[field] };
          incoming.route = { status: 'idle', distanceM: 0, durationS: 0, error: '' };
        } else {
          earthDirty[field] = false;
        }
      }
      const personalRouteChanged = Boolean(view.earth.freeRoute?.active) !== Boolean(incoming.freeRoute?.active);
      const streetLayoutChanged = Boolean(view.earth.location) !== Boolean(incoming.location);
      view.earth = incoming;
      if (personalRouteChanged || streetLayoutChanged) scheduleMinimapUpdate();
      if (view.earthStarting && (Number(incoming.startedTripId) > 0 || incoming.error || incoming.route.error)) {
        if (earthStartTimer !== null) clearTimeout(earthStartTimer);
        earthStartTimer = null;
        view.earthStarting = false;
        if (Number(incoming.startedTripId) > 0) hud.closeEarth();
      }
    };
    onGameEvent('TaxiDriverEarthState', applyEarth);
    view.earthResults = field => view.earth[field].results.slice(0, 8);
    view.earthOfferRoute = offer => [offer?.pickupAddress || offer?.pickupName,
      offer?.destinationAddress || offer?.destinationName].filter(Boolean).join(' → ');
    view.canPreviewEarth = () => !view.earthStarting && view.earth.status === 'ready' && !!view.earth.b.selected &&
      (view.earth.mode === 'vehicle' || !!view.earth.a.selected) && view.earth.route.status !== 'pending';
    view.canNavigateEarth = target => !view.earthStarting && view.earth.status === 'ready' && view.earth.canNavigate &&
      !!view.earth[target]?.selected;
    view.canRandomEarth = () => !view.earthStarting && view.earth.status === 'ready' && view.earth.route.status !== 'pending' &&
      (view.earth.mode === 'vehicle' || !!view.earth.a.selected);
    view.canStartEarthTrip = () => view.earthOpen && !view.earthStarting && view.earth.status === 'ready' &&
      view.earth.route.status === 'ready' && (!view.state.active || view.state.phase === 'searching');
    hud.earthStartTrip = () => {
      if (!view.canStartEarthTrip()) return;
      view.earthStarting = true;
      view.earth.error = '';
      view.earth.route.error = '';
      earthStartTimer = setTimeout(() => {
        earthStartTimer = null;
        view.earthStarting = false;
        view.earth.error = view.t('earthStartTimeout');
      }, 15000);
      earthCommand('startTrip', {withoutPassenger: view.earth.withoutPassenger === true});
    };
    hud.setEarthWithoutPassenger = () => earthCommand('setWithoutPassenger', {value: view.earth.withoutPassenger === true});
    hud.stopEarthFreeRoute = () => earthCommand('stopFreeRoute');
    view.hasPersonalRoute = () => view.earth.available && view.earth.freeRoute?.active === true;
    view.canUseFuelService = () => view.hasPersonalRoute() || (view.state.active && view.state.realisticMode);
    view.getNavigationRemaining = () => view.hasPersonalRoute() ? view.earth.freeRoute.remainingM : view.state.distanceToTarget;
    view.getNavigationEta = () => view.hasPersonalRoute() ? view.earth.freeRoute.etaS / 60 : view.state.etaMinutes;
    hud.setEarthRandomLimit = value => {
      const number = Number(value);
      const maxRandomKm = Math.max(1, Math.min(600, Math.round(Number.isFinite(number) ? number : 50)));
      view.earth.maxRandomKm = maxRandomKm;
      earthCommand('setRandomLimit', { maxRandomKm });
    };
    hud.teleportEarthA = () => {
      if (view.earth.mode === 'points' && view.canNavigateEarth('a')) earthCommand('teleport', { target: 'a' });
    };
    hud.randomEarth = () => {
      if (!view.canRandomEarth()) return;
      cancelEarthEdits();
      earthDirty.a = earthDirty.b = false;
      view.earth.b = emptyEarthField();
      view.earthExpanded.b = false;
      view.earth.randomAttempt = 0;
      view.earth.route = { ...normalizeEarth().route, status: 'pending' };
      earthCommand('randomPreview');
    };
    hud.closeEarth = () => {
      if (!view.earthOpen) return;
      // Flush pending local invalidations before cancelling backend work.
      for (const field of ['a', 'b']) {
        if (earthDirty[field]) earthCommand('edit', { field, query: view.earth[field].query });
      }
      stopEarthWork();
      earthCommand('close');
      scheduleMinimapUpdate();
    };
    hud.openEarth = () => {
      if (!view.earth.available || view.earthOpen) return;
      if (settingsSaveTimer) persistSettingsNow();
      view.settingsOpen = view.profileOpen = view.fleetOpen = view.fuelStationOpen = false;
      view.shiftHistoryOpen = view.offlineConfirmOpen = false;
      earthAwaitingOwnerAck = true;
      view.earth.startedTripId = 0;
      view.earthOpen = true;
      dismissPassengerChat();
      hideMinimap();
      earthCommand('open');
      earthHeartbeat = setInterval(() => earthCommand('heartbeat'), 2500);
    };
    hud.setEarthMode = mode => {
      if (view.earthStarting) return;
      if (!['vehicle', 'points'].includes(mode) || mode === view.earth.mode) return;
      view.earth.mode = mode;
      view.earth.route = normalizeEarth().route;
      earthCommand('mode', { mode });
    };
    hud.editEarth = (field, query) => {
      if (view.earthStarting) return;
      if (!['a', 'b'].includes(field)) return;
      view.earth[field] = { ...emptyEarthField(), query: String(query || '') };
      view.earth.route = normalizeEarth().route;
      view.earthActive[field] = -1;
      view.earthExpanded[field] = false;
      earthDirty[field] = true;
      if (earthEditTimers[field]) clearTimeout(earthEditTimers[field]);
      earthEditTimers[field] = setTimeout(() => {
        earthEditTimers[field] = null;
        earthCommand('edit', { field, query: view.earth[field].query });
      }, 250);
    };
    hud.searchEarth = field => {
      if (view.earthStarting) return;
      if (!['a', 'b'].includes(field) || view.earth.status !== 'ready' || !view.earth[field].query.trim() || view.earth[field].searching) return;
      if (earthEditTimers[field]) clearTimeout(earthEditTimers[field]);
      earthEditTimers[field] = null;
      view.earth[field].query = view.earth[field].query.trim();
      view.earth[field].searching = true;
      view.earth[field].error = '';
      view.earthExpanded[field] = true;
      view.earthActive[field] = -1;
      earthCommand('search', { field, query: view.earth[field].query });
    };
    hud.selectEarth = (field, index) => {
      if (view.earthStarting) return;
      const point = view.earthResults(field)[index];
      if (!point || !Number.isInteger(index)) return;
      earthDirty[field] = false;
      view.earth[field].selected = point;
      view.earth[field].query = point.name || view.earth[field].query;
      view.earthExpanded[field] = false;
      view.earthActive[field] = -1;
      view.earth.route = normalizeEarth().route;
      earthCommand('select', { field, index: index + 1 });
    };
    hud.earthKeydown = (field, event) => {
      const count = view.earthResults(field).length;
      if (event.key === 'Escape') {
        view.earthExpanded[field] = false; view.earthActive[field] = -1;
      } else if (['ArrowDown', 'ArrowUp'].includes(event.key) && count) {
        event.preventDefault();
        view.earthExpanded[field] = true;
        view.earthActive[field] = view.earthActive[field] < 0
          ? (event.key === 'ArrowDown' ? 0 : count - 1)
          : (view.earthActive[field] + (event.key === 'ArrowDown' ? 1 : count - 1)) % count;
      } else if (event.key === 'Enter') {
        event.preventDefault();
        if (view.earthExpanded[field] && view.earthActive[field] >= 0) hud.selectEarth(field, view.earthActive[field]);
        else hud.searchEarth(field);
      }
    };
    hud.previewEarth = () => {
      if (!view.canPreviewEarth()) return;
      view.earth.route.status = 'pending';
      earthCommand('preview');
    };
    hud.navigateEarth = target => {
      if (view.canNavigateEarth(target)) earthCommand('navigate', { target });
    };

    const clearNextOfferCountdown = () => {
      trackedNextOfferId = null;
      trackedNextOfferDeadline = 0;
      view.nextOfferUiRemaining = 0;
    };

    const expireNextOfferLocally = (offerId, dismissedByDriver = false) => {
      const id = Math.floor(Number(offerId || 0));
      if (id <= 0 || expiredNextOfferIds.has(id)) return;
      expiredNextOfferIds.add(id);
      clearNextOfferCountdown();
      if (view.state.nextOffer && Number(view.state.nextOffer.id) === id &&
          !view.state.nextOffer.accepted) {
        view.state = Object.assign({}, view.state, { nextOffer: null });
      }
      const closeFunction = dismissedByDriver ? "dismissNextOffer" : "expireNextOffer";
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.${closeFunction}(${id}) end`
      );
    };

    const syncNextOfferCountdown = (offer) => {
      if (!offer || offer.accepted) {
        clearNextOfferCountdown();
        return;
      }
      const id = Math.floor(Number(offer.id || 0));
      if (id <= 0 || expiredNextOfferIds.has(id)) {
        clearNextOfferCountdown();
        return;
      }
      const reportedRemaining = Number(offer.timeRemaining);
      const remaining = Math.max(0, Number.isFinite(reportedRemaining)
        ? reportedRemaining
        : Number(offer.duration || 5));
      const candidateDeadline = Date.now() + remaining * 1000;
      if (trackedNextOfferId !== id || trackedNextOfferDeadline <= 0) {
        trackedNextOfferId = id;
        trackedNextOfferDeadline = candidateDeadline;
      } else {
        // Never extend a local deadline from a repeated stale HUD packet.
        trackedNextOfferDeadline = Math.min(trackedNextOfferDeadline, candidateDeadline);
      }
      view.nextOfferUiRemaining = Math.max(0,
        (trackedNextOfferDeadline - Date.now()) / 1000);
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
        language: supportsLanguage(value.language) ? value.language : "en",
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
        lanManualAddress: typeof value.lanManualAddress === "string" ? value.lanManualAddress : "",
        externalMapEnabled: value.externalMapEnabled !== false,
        externalTerrainEnabled: value.externalTerrainEnabled !== false,
        externalMapQuality: ["eco", "balanced", "smooth"].includes(value.externalMapQuality)
          ? value.externalMapQuality : "balanced",
        silentMode: value.silentMode === true,
        showRouteGuidance: value.showRouteGuidance !== false,
        realisticMode: value.realisticMode === true,
        initialFuelPercent: normalizeInitialFuelPercent(value.initialFuelPercent),
        randomEventsEnabled: value.randomEventsEnabled === true,
        randomEvents: normalizeRandomEvents(value.randomEvents),
        aiDebugLogging: value.aiDebugLogging === true,
        aiDriver: normalizeAiDriver(value.aiDriver),
        fleet: normalizeFleet(value.fleet),
        godMode: value.godMode === true,
        debugLogging: value.debugLogging !== false,
      };
    };

    const settingsFingerprint = (source) => JSON.stringify(normalizeSettings(source));
    const retainLocalSettingsUntilAcknowledged = () => {
      const normalized = normalizeSettings(view.settings);
      view.settings = normalized;
      view.language = normalized.language;
      if (view.state) view.state.settings = Object.assign({}, normalized);
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

    const normalizeRepairStation = (source) => {
      const value = source && typeof source === "object" ? source : {};
      const repairingSource = value.repairing && typeof value.repairing === "object"
        ? value.repairing : {};
      return {
        available: value.available === true,
        id: String(value.id || ""),
        vehicleStopped: value.vehicleStopped === true,
        damagePercent: Math.max(0, Math.min(100, Number(value.damagePercent || 0))),
        price: Math.max(0, Number(value.price || 0)),
        canRepair: value.canRepair === true,
        balance: Math.max(0, Number(value.balance || 0)),
        repairing: {
          active: repairingSource.active === true,
          completing: repairingSource.completing === true,
          cost: Math.max(0, Number(repairingSource.cost || 0)),
          duration: Math.max(0, Number(repairingSource.duration || 0)),
          elapsed: Math.max(0, Number(repairingSource.elapsed || 0)),
          progress: Math.max(0, Math.min(1, Number(repairingSource.progress || 0))),
          remainingSeconds: Math.max(0, Number(repairingSource.remainingSeconds || 0)),
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
      const source = station || view.state.fuelStation || {};
      const options = Array.isArray(source.options) ? source.options : [];
      return options.find((option) => option.energyType === energyType) || null;
    };

    const clampRefuelAmount = () => {
      const option = getFuelOption(view.selectedFuelType);
      const maximum = option ? Math.max(0, Number(option.affordableQuantity || 0)) : 0;
      const amount = Math.max(0, Number(view.refuel.amount || 0));
      view.refuel.amount = Math.min(maximum, amount);
    };

    const syncFuelStation = (station, repairStation) => {
      repairStation = repairStation || { available: false, id: "" };
      if (!station.available && !repairStation.available) {
        activeFuelStationId = "";
        activeRepairStationId = "";
        view.fuelStationOpen = false;
        view.selectedFuelType = "";
        view.refuel.amount = 0;
        return;
      }

      const stationId = station.available ? station.id : repairStation.id;
      const previousStationId = station.available ? activeFuelStationId : activeRepairStationId;
      const isNewStation = stationId !== previousStationId;
      if (station.available) activeFuelStationId = station.id;
      if (repairStation.available) activeRepairStationId = repairStation.id;
      if (isNewStation) {
        view.refuel.amount = 0;
        if (!view.settingsOpen && !view.profileOpen && !view.offlineConfirmOpen) {
          view.fuelStationOpen = true;
          view.collapseAttention = view.phoneMinimized || view.phoneSuperMinimized;
          dismissPassengerChat();
          hideMinimap();
        }
      }

      if (!station.available) return;
      if (!getFuelOption(view.selectedFuelType, station)) {
        view.selectedFuelType = station.options.length ? station.options[0].energyType : "";
        view.refuel.amount = 0;
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
      saveSettingsToLua(view.settings);
      view.settingsSaved = true;
    };

    const queueSettingsSave = (delay) => {
      view.settingsSaved = false;
      retainLocalSettingsUntilAcknowledged();
      if (settingsSaveTimer) clearTimeout(settingsSaveTimer);
      settingsSaveTimer = setTimeout(() => scheduleUi(() => {
        persistSettingsNow();
      }), delay === undefined ? 180 : Math.max(0, delay));
    };

    const normalizeProfile = (source) => {
      const value = source && typeof source === "object" ? source : {};
      const fullName = String(value.fullName || "John Doe").trim().replace(/\s+/g, " ");
      const birthDate = /^\d{4}-\d{2}-\d{2}$/.test(String(value.birthDate || ""))
        ? String(value.birthDate)
        : "";
      const avatar = view.avatarOptions.includes(value.avatar) ? value.avatar : "🙂";
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
      if (offlineHoldTimer) clearTimeout(offlineHoldTimer);
      offlineHoldTimer = null;
      if (offlineHoldButton) offlineHoldButton.classList.remove("taxi-offline-hold--holding");
      offlineHoldButton = null;
      view.offlineHoldProgress = 0;
    };

    const completeOfflineHold = () => {
      stopOfflineHold();
      if (view.state.passengerOnboard) {
        view.offlineConfirmOpen = true;
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

    view.getChartPoints = (history, chartType) => {
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

    view.getAge = (birthDate) => {
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

    view.getReviewPageCount = () => Math.max(
      1,
      Math.ceil(view.profileReviews.length / view.reviewsPerPage)
    );
    view.getPagedReviews = () => {
      const maximumPage = view.getReviewPageCount();
      view.reviewPage = Math.max(1, Math.min(maximumPage, view.reviewPage));
      const offset = (view.reviewPage - 1) * view.reviewsPerPage;
      return view.profileReviews.slice(offset, offset + view.reviewsPerPage);
    };
    let reviewPaginationFrame = 0;
    let reviewPaginationRetry = 0;
    const updateReviewPagination = () => {
      reviewPaginationFrame = 0;
      if (!view.profileOpen || view.profileTab !== "reviews" || !view.profileReviews.length) return;
      const content = appRoot.querySelector(".taxi-profile__content");
      const panel = appRoot.querySelector(".taxi-profile__panel--reviews");
      const regularMeasure = panel && panel.querySelector('[data-review-measure="regular"]');
      const aiMeasure = panel && panel.querySelector('[data-review-measure="ai"]');
      const pager = panel && panel.querySelector(".taxi-profile__pager");
      if (!content || !panel || !regularMeasure || !aiMeasure || !pager) {
        if (reviewPaginationRetry < 3) {
          reviewPaginationRetry += 1;
          reviewPaginationFrame = requestFrame(updateReviewPagination);
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
      const reviewHeights = view.profileReviews.map((review) =>
        review && review.usedAutopilot ? aiRowHeight : regularRowHeight
      );
      const maximumCandidate = Math.min(50, reviewHeights.length);
      let nextPerPage = 1;
      if (view.expandedReviewId !== null) {
        if (view.reviewsPerPage !== 1) scheduleUi(() => { view.reviewsPerPage = 1; });
        return;
      }
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
      if (nextPerPage === view.reviewsPerPage) return;
      const firstVisibleIndex = (view.reviewPage - 1) * view.reviewsPerPage;
      scheduleUi(() => {
        view.reviewsPerPage = nextPerPage;
        view.reviewPage = Math.floor(firstVisibleIndex / nextPerPage) + 1;
        scheduleReviewPagination();
      });
    };
    const scheduleReviewPagination = () => {
      if (destroyed) return;
      if (reviewPaginationFrame) cancelFrame(reviewPaginationFrame);
      reviewPaginationRetry = 0;
      reviewPaginationFrame = requestFrame(updateReviewPagination);
    };
    const stopReviewPaginationWatch = watchFields([
      "profileOpen", "profileTab", "profileReviews.length", "settings.uiScalePercent",
    ], scheduleReviewPagination);
    const reviewResizeObserver = typeof ResizeObserver === "function"
      ? new ResizeObserver(scheduleReviewPagination) : null;
    if (reviewResizeObserver) {
      onDestroy(() => reviewResizeObserver.disconnect());
      reviewResizeObserver.observe(appRoot);
    }
    view.formatReviewDate = (timestamp) => {
      const value = Number(timestamp || 0);
      if (!value) return "—";
      return new Date(value * 1000).toLocaleDateString(view.language || "en", {
        year: "numeric", month: "short", day: "numeric",
      });
    };
    view.getReviewRatingClass = (review) => {
      const orderRating = Number(review && review.orderRating || 0);
      const profileRating = Number(review && review.rating || 0);
      if (Math.abs(orderRating - profileRating) < 0.005) return "equal";
      return orderRating > profileRating ? "higher" : "lower";
    };
    const randomEventLabelKeys = {
      cancellation: "randomEventCancellation", destinationChange: "randomEventDestinationChange",
      additionalStop: "randomEventAdditionalStop", tip: "randomEventTip",
      fragileCargo: "randomEventFragileCargo", policeCheck: "randomEventPoliceCheck",
      passengerNoShow: "randomEventPassengerNoShow", vipQuietRide: "randomEventVipQuietRide",
      forgottenItem: "randomEventForgottenItem", roadClosure: "randomEventRoadClosure",
    };
    view.getRandomEventLabel = (event) =>
      view.t(randomEventLabelKeys[String(event && event.kind || "")] || "randomEventUnknown");
    view.getRandomEventStatus = (event) => {
      const status = String(event && event.status || "notTriggered");
      const key = `randomEventStatus_${status}`;
      const translated = view.t(key);
      return translated === key ? status : translated;
    };
    view.getPenaltyHistoryLabel = (penalty) => {
      const kind = String(penalty && penalty.kind || "unknown");
      const key = `penalty_${kind}`;
      const translated = view.t(key);
      return translated === key && randomEventLabelKeys[kind]
        ? view.t(randomEventLabelKeys[kind]) : translated;
    };
    view.formatPenaltyHistory = (penalty) => {
      const fareAmount = Math.max(0, Number(penalty && penalty.fareAmount || 0));
      if (fareAmount > 0) return `−${view.formatMoney(fareAmount)}`;
      return `−${(Math.max(0, Number(penalty && penalty.penalty || 0)) * 100).toFixed(1)}%`;
    };

    let lastMinimapRect = "";
    let minimapVisible = false;
    let uiVisible = externalPhoneMode;
    let cefVisible = true;
    let appsVisible = true;
    let routeAppsVisible = true;
    let drivingRoute = externalPhoneMode;
    let nativeRouteVersion = 0;
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
    let mapZoomFactor = 1;
    let mapDrag = null;
    view.mapFollowing = true;
    let externalRoadRevision = 0;
    let externalPollTimer = 0;
    let externalPollInFlight = false;
    let externalPollGeneration = 0;
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
      !view.earthOpen &&
      view.settings.externalMapEnabled !== false && (view.fleetOpen || minimapPhases.has(view.state.phase)) &&
      !view.settingsOpen && !view.profileOpen && !view.offlineConfirmOpen &&
      !view.fuelStationOpen;
    const getExternalView = () => {
      if (!externalPhoneMode) return "hidden";
      if (view.earthOpen) return "status";
      if (view.settingsOpen) return "settings";
      if (view.profileOpen) return "profile";
      if (view.fuelStationOpen) return "fuel";
      if (view.fleetOpen) return "fleet";
      if (!view.settings.externalMapEnabled && minimapPhases.has(view.state.phase)) return "status";
      if (view.phoneMinimized && minimapPhases.has(view.state.phase)) return "compact";
      if (view.state.phase === "toFuelStation") return "fuelRoute";
      if (["toPickup", "toStop", "toDestination"].includes(view.state.phase)) return "trip";
      if (view.state.phase === "searching") return "orders";
      return view.state.active ? "status" : "home";
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
    const canRenderMinimap = (hudState) => !externalPhoneMode && !view.phoneSuperMinimized && !view.earthOpen &&
      uiVisible && !view.vehicleConfigSuspended && hudState &&
      (!(hudState.lan && Number(hudState.lan.connected || 0) > 0) || view.localPhoneOpen) &&
      (view.phoneMinimized || view.hasPersonalRoute() || view.fleetOpen || (hudState.active === true && minimapPhases.has(hudState.phase))) &&
      (view.phoneMinimized || (
        !view.settingsOpen && !view.profileOpen && !view.offlineConfirmOpen &&
        !view.fuelStationOpen
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
      if (!canRenderMinimap(view.state)) {
        hideMinimap();
        return;
      }

      const surface = host.querySelector(
        view.fleetOpen
          ? ".taxi-fleet .taxi-minimap-surface"
          : (view.phoneMinimized
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
      const routeInfoValues = normalizeRect(host.querySelector(
        view.phoneMinimized ? ".taxi-compact__route-info" : ".taxi-map__route-info"
      ));
      const speedLimitValues = normalizeRect(host.querySelector(
        view.phoneMinimized ? ".taxi-compact__speed" : ".taxi-map__speed"
      ));
      const autopilotValues = view.phoneMinimized
        ? [0, 0, 0, 0]
        : normalizeRect(host.querySelector(".taxi-map__autopilot"));
      const notificationValues = view.phoneMinimized
        ? [0, 0, 0, 0]
        : normalizeRect(host.querySelector(".taxi-phone-toast"));
      const fleetStatusValues = view.fleetOpen
        ? normalizeRect(host.querySelector(".taxi-fleet__map-status"))
        : (view.phoneMinimized
          ? [0, 0, 0, 0]
          : normalizeRect(host.querySelector(".taxi-map__fleet")));
      const mapControlsValues = normalizeRect(surface.parentElement.querySelector(".taxi-map-controls"));
      const layoutKey = values
        .concat(routeInfoValues, speedLimitValues, notificationValues, autopilotValues, fleetStatusValues, mapControlsValues)
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

      const allowFleetMap = view.fleetOpen || view.phoneMinimized || view.hasPersonalRoute() ? "true" : "false";
      const forceFullTextureClear = view.phoneMinimized ? "false" : "true";
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapTransform(${rectKey}, ${allowFleetMap}, ${forceFullTextureClear}); taxiDriver_taxiDriver.setMinimapOcclusions(${occlusionKey}, ${allowFleetMap}, ${mapControlsValues.map(value => value.toFixed(5)).join(",")}) end`
      );
    };

    const getExternalMapFrameInterval = () => {
      const quality = view.settings.externalMapQuality;
      return quality === "eco" ? 1000 / 6 : (quality === "smooth" ? 1000 / 30 : 1000 / 15);
    };
    const scheduleExternalMapDraw = () => {
      if (destroyed || !externalMapVisible() || externalMapFrame || externalMapDelayTimer) return;
      const remaining = Math.max(0,
        getExternalMapFrameInterval() - (performance.now() - externalMapLastDrawAt)
      );
      const requestDraw = () => {
        externalMapDelayTimer = 0;
        externalMapFrame = requestFrame((timestamp) => {
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
      else scheduleUi(() => requestFrame(updateMinimap));
    };

    hud.zoomMap = factor => {
      const next = Math.max(0.25, Math.min(4, mapZoomFactor * factor));
      factor = next / mapZoomFactor;
      mapZoomFactor = next;
      if (!externalPhoneMode) bngApi.engineLua(`if taxiDriver_taxiDriver then taxiDriver_taxiDriver.zoomMinimap(${factor}) end`);
      else scheduleExternalMapDraw();
    };
    hud.followMap = () => {
      view.mapFollowing = true;
      mapZoomFactor = 1;
      externalCameraCenter = null;
      externalCameraHeading = null;
      externalCameraRadius = null;
      if (!externalPhoneMode) callTaxiDriver("resetMinimapView");
      else scheduleExternalMapDraw();
    };
    const startMapDrag = event => {
      const surface = event.target.closest && event.target.closest(".taxi-map-interaction");
      if (!surface || event.button !== 0) return;
      event.preventDefault();
      event.stopPropagation();
      mapDrag = { id: event.pointerId, x: event.clientX, y: event.clientY, surface };
      surface.setPointerCapture(event.pointerId);
    };
    const moveMapDrag = event => {
      if (!mapDrag || event.pointerId !== mapDrag.id) return;
      const rect = mapDrag.surface.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      const dx = (event.clientX - mapDrag.x) / rect.width;
      const dy = (event.clientY - mapDrag.y) / rect.height;
      mapDrag.x = event.clientX;
      mapDrag.y = event.clientY;
      if (!dx && !dy) return;
      event.preventDefault();
      scheduleUi(() => { view.mapFollowing = false; });
      if (!externalPhoneMode) bngApi.engineLua(`if taxiDriver_taxiDriver then taxiDriver_taxiDriver.panMinimap(${dx}, ${dy}) end`);
      else if (externalCameraCenter && externalCameraRadius !== null) {
        const scale = Math.min(rect.width, rect.height) / (externalCameraRadius * 2);
        const right = -dx * rect.width / scale;
        const forward = dy * rect.height / scale;
        const sin = Math.sin(externalCameraHeading || 0);
        const cos = Math.cos(externalCameraHeading || 0);
        externalCameraCenter[0] += right * cos + forward * sin;
        externalCameraCenter[1] += -right * sin + forward * cos;
        scheduleExternalMapDraw();
      }
    };
    const stopMapDrag = event => {
      if (!mapDrag || (event.pointerId !== undefined && event.pointerId !== mapDrag.id)) return;
      if (mapDrag.surface.hasPointerCapture(mapDrag.id)) mapDrag.surface.releasePointerCapture(mapDrag.id);
      mapDrag = null;
    };
    listen(host, "pointerdown", startMapDrag);
    listen(window, "pointermove", moveMapDrag);
    listen(window, "pointerup", stopMapDrag);
    listen(window, "pointercancel", stopMapDrag);
    listen(window, "blur", stopMapDrag);

    const drawExternalMap = () => {
      if (!externalMapVisible() || !externalVehicleState ||
          !externalVehicleState.position || (!view.fleetOpen && !minimapPhases.has(view.state.phase))) {
        externalCameraCenter = null;
        externalCameraHeading = null;
        externalCameraRadius = null;
        externalCameraZoomUpdatedAt = 0;
        return;
      }
      const surfaces = host.querySelectorAll("canvas.taxi-external-minimap");
      const targetCenter = externalVehicleState.position.map((value) => Number(value) || 0);
      const direction = externalVehicleState.direction || [0, 1];
      const targetHeading = Math.atan2(Number(direction[0]) || 0, Number(direction[1]) || 1);
      if (!externalCameraCenter) externalCameraCenter = targetCenter.slice();
      if (externalCameraHeading === null) externalCameraHeading = targetHeading;
      const centerDeltaX = view.mapFollowing ? targetCenter[0] - externalCameraCenter[0] : 0;
      const centerDeltaY = view.mapFollowing ? targetCenter[1] - externalCameraCenter[1] : 0;
      externalCameraCenter[0] += centerDeltaX * 0.32;
      externalCameraCenter[1] += centerDeltaY * 0.32;
      const headingDelta = view.mapFollowing ? Math.atan2(
        Math.sin(targetHeading - externalCameraHeading),
        Math.cos(targetHeading - externalCameraHeading)
      ) : 0;
      externalCameraHeading += headingDelta * 0.25;
      const center = externalCameraCenter;
      const headingSin = Math.sin(externalCameraHeading);
      const headingCos = Math.cos(externalCameraHeading);
      const speed = Math.max(0, Number(view.state.currentSpeed || 0));
      const intensity = Math.max(0, Math.min(2, Number(
        view.settings.dynamicZoomIntensity
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
      )) * mapZoomFactor;
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
        const quality = view.settings.externalMapQuality;
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
        canvas.dataset.mapCenterX = center[0].toFixed(2);
        canvas.dataset.mapCenterY = center[1].toFixed(2);
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
        const visibleTerrainTiles = view.settings.externalTerrainEnabled === false
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
        const fleetMarkers = view.state.fleet && Array.isArray(view.state.fleet.markers)
          ? view.state.fleet.markers : [];
        fleetMarkers.forEach((marker) => {
          if (!Array.isArray(marker.position)) return;
          const point = project(marker.position);
          if (point[0] < -12 || point[0] > w + 12 || point[1] < -12 || point[1] > h + 12) return;
          ctx.fillStyle = "#211432"; ctx.beginPath(); ctx.arc(point[0], point[1], 8, 0, Math.PI * 2); ctx.fill();
          ctx.fillStyle = "#9a4aff"; ctx.beginPath(); ctx.arc(point[0], point[1], 5, 0, Math.PI * 2); ctx.fill();
        });
        const pointerScale = Math.max(0.72, Math.min(1, Math.min(w, h) / 300));
        const vehiclePoint = project(targetCenter);
        ctx.save(); ctx.translate(vehiclePoint[0], vehiclePoint[1]);
        ctx.rotate(targetHeading - externalCameraHeading); ctx.scale(pointerScale, pointerScale);
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
      view.currentClock = new Date().toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        hour12: view.settings.timeFormat !== "24h",
      });
    };

    hud.startMode = () => {
      if (settingsSaveTimer) persistSettingsNow();
      callTaxiDriver("startMode");
    };
    hud.toggleFleet = () => {
      hud.closeEarth();
      view.fleetOpen = !view.fleetOpen;
      view.shiftHistoryOpen = false;
      lastMinimapRect = "";
      if (view.fleetOpen) dismissPassengerChat();
      scheduleMinimapUpdate();
      syncExternalView();
    };
    hud.fleetCommand = (action, args) => {
      const luaAction = bngApi.serializeToLua(String(action || ""));
      const luaArgs = bngApi.serializeToLua(args || {});
      bngApi.engineLua(`if taxiDriver_taxiDriver then taxiDriver_taxiDriver.fleetCommand(${luaAction}, ${luaArgs}) end`);
    };
    hud.toggleShiftHistory = () => {
      if (view.state.shiftHistory && view.state.shiftHistory.restoring) return;
      view.shiftHistoryOpen = !view.shiftHistoryOpen;
      if (view.shiftHistoryOpen) view.shiftHistoryVisibleCount = 30;
    };
    hud.loadMoreShifts = () => {
      view.shiftHistoryVisibleCount = Math.min(
        Number(view.shiftHistoryVisibleCount || 30) + 30,
        (view.state.shiftHistory && view.state.shiftHistory.items || []).length
      );
    };
    hud.resumeShift = (shiftId) => {
      const id = Math.max(1, Math.floor(Number(shiftId) || 0));
      view.profileOpen = false;
      view.fleetOpen = false;
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.resumeShift(${id}) end`
      );
    };
    hud.openVehicleSelector = () => callTaxiDriver("openVehicleSelector");
    hud.toggleAutopilot = () => callTaxiDriver("toggleAutopilot");
    hud.stopMode = () => callTaxiDriver("stopMode");
    hud.toggleOfferSortMenu = () => {
      view.offerSortMenuOpen = !view.offerSortMenuOpen;
    };
    hud.selectOfferSort = (value) => {
      if (view.offerSortOptions.some((option) => option.value === value)) {
        view.offerSort = value;
      }
      view.offerSortMenuOpen = false;
    };
    hud.toggleVehicleSortMenu = () => {
      view.vehicleSortMenuOpen = !view.vehicleSortMenuOpen;
    };
    hud.selectVehicleSort = (value) => {
      if (view.vehicleSortOptions.some((option) => option.value === value)) {
        view.vehicleSort = value;
      }
      view.vehicleSortMenuOpen = false;
    };
    hud.beginOfflineHold = (event) => {
      if (view.offlineConfirmOpen || offlineHoldTimer) return;
      if (event && event.button !== undefined && event.button !== 0) return;
      if (event) event.preventDefault();
      offlineHoldButton = event && findOfflineHoldButton(event.target);
      if (offlineHoldButton) offlineHoldButton.classList.add("taxi-offline-hold--holding");
      view.offlineHoldProgress = 1;
      // CSS animates transform on the pressed button; only completion needs a digest.
      const timer = setTimeout(() => {
        scheduleUi(() => {
          if (offlineHoldTimer === timer) completeOfflineHold();
        });
      }, 2000);
      offlineHoldTimer = timer;
    };
    hud.cancelOfflineHold = () => stopOfflineHold();
    hud.cancelOfflineConfirmation = () => {
      view.offlineConfirmOpen = false;
      scheduleMinimapUpdate();
    };
    hud.confirmOfflineWithPassenger = () => {
      view.offlineConfirmOpen = false;
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.confirmDriverAbandonment() end'
      );
    };
    hud.toggleMinimized = () => {
      view.phoneMinimized = !view.phoneMinimized;
      persistView();
      if (view.phoneMinimized) {
        dismissPassengerChat();
      } else {
        view.collapseAttention = false;
      }
      lastMinimapRect = "";
      scheduleMinimapUpdate();
    };
    hud.toggleSuperMinimized = () => {
      view.phoneSuperMinimized = !view.phoneSuperMinimized;
      persistView();
      if (view.phoneSuperMinimized) {
        dismissPassengerChat();
        hideMinimap(true);
      } else {
        view.collapseAttention = false;
      }
      lastMinimapRect = "";
      scheduleMinimapUpdate();
    };
    hud.toggleLocalPhone = () => {
      view.localPhoneOpen = !view.localPhoneOpen;
      if (!view.localPhoneOpen) {
        dismissPassengerChat();
        hideMinimap(true);
      }
      lastMinimapRect = "";
      scheduleMinimapUpdate();
    };
    hud.toggleSettings = () => {
      hud.closeEarth();
      if (view.settingsOpen && settingsSaveTimer) persistSettingsNow();
      view.settingsOpen = !view.settingsOpen;
      view.profileOpen = false;
      view.fleetOpen = false;
      view.fuelStationOpen = false;
      view.offlineConfirmOpen = false;
      view.settingsSaved = view.settingsOpen;
      if (view.settingsOpen) {
        view.cheatRating = Number(view.state.rating || 5);
        view.cheatEnergyPercent = Math.max(0, Math.min(100,
          Number(view.state.vehicleEnergy && view.state.vehicleEnergy.percent || 0)
        ));
        view.cheatEnergyDraft = view.cheatEnergyPercent;
        view.cheatResetArmed = false;
        dismissPassengerChat();
        hideMinimap();
        scheduleLanQr();
      }
      else scheduleMinimapUpdate();
    };
    hud.toggleProfile = () => {
      hud.closeEarth();
      view.profileOpen = !view.profileOpen;
      view.settingsOpen = false;
      view.fleetOpen = false;
      view.fuelStationOpen = false;
      view.offlineConfirmOpen = false;
      view.profileSaved = false;
      stopOfflineHold();
      if (view.profileOpen) {
        dismissPassengerChat();
        hideMinimap();
        requestProfileData();
        scheduleReviewPagination();
      } else {
        scheduleMinimapUpdate();
      }
    };
    hud.selectProfileTab = (tab) => {
      if (!["identity", "reviews", "analytics", "vehicles", "shifts"].includes(tab)) return;
      view.profileTab = tab;
      if (tab === "reviews") {
        const content = appRoot.querySelector(".taxi-profile__content");
        if (content) content.scrollTop = 0;
        scheduleReviewPagination();
      }
    };
    hud.selectAvatar = (avatar) => {
      if (view.avatarOptions.includes(avatar)) view.profileDraft.avatar = avatar;
      view.profileSaved = false;
    };
    hud.saveProfile = () => {
      view.profileDraft = normalizeProfile(view.profileDraft);
      saveProfileToLua(view.profileDraft);
      view.profileSaved = true;
    };
    hud.previousReviewPage = () => {
      view.expandedReviewId = null;
      view.reviewPage = Math.max(1, view.reviewPage - 1);
    };
    hud.nextReviewPage = () => {
      view.expandedReviewId = null;
      view.reviewPage = Math.min(view.getReviewPageCount(), view.reviewPage + 1);
    };
    hud.toggleReviewDetails = (review) => {
      const id = review && review.id;
      if (id === undefined || id === null) return;
      if (view.expandedReviewId === id) {
        view.expandedReviewId = null;
      } else {
        const index = view.profileReviews.findIndex((item) => item.id === id);
        view.expandedReviewId = id;
        view.reviewsPerPage = 1;
        if (index >= 0) view.reviewPage = index + 1;
      }
      scheduleReviewPagination();
    };
    hud.selectLanguage = (languageCode) => {
      if (!supportsLanguage(languageCode)) return;
      view.settings.language = languageCode;
      view.language = languageCode;
      queueSettingsSave();
    };
    hud.selectDifficulty = (preset) => {
      if (difficulties.includes(preset)) view.settings.difficulty = preset;
      queueSettingsSave();
    };
    hud.selectHomeDifficulty = preset => {
      if (!homeDifficultyPresets.includes(preset) || view.state.active) return;
      view.settings.difficulty = preset;
      for (const key of homePenaltyKeys) view.settings.penaltyToggles[key] = preset !== "elementary";
      // Presets are discrete choices, not slider input. Submit immediately so
      // closing the game/phone before a debounce cannot discard the selection.
      persistSettingsNow();
    };
    hud.selectAiDriverPreset = (preset) => {
      if (!aiDriverPresetNames.includes(preset)) return;
      const strictGpsRoute = view.settings.aiDriver.strictGpsRoute === true;
      const enabled = view.settings.aiDriver.enabled === true;
      const source = preset === "custom"
        ? Object.assign({}, view.settings.aiDriver, { preset: "custom" })
        : Object.assign({}, aiDriverPresetValues[preset], { preset, strictGpsRoute, enabled });
      view.settings.aiDriver = normalizeAiDriver(source);
      queueSettingsSave();
    };
    hud.requestAiDriverToggle = () => {
      if (view.settings.aiDriver.enabled === true) {
        view.settings.aiDriver.enabled = false;
        view.aiDriverConfirmOpen = false;
        hud.settingsChanged();
        return;
      }
      view.aiDriverConfirmOpen = true;
    };
    hud.aiDriverToggleChanged = () => {
      if (view.settings.aiDriver.enabled === true) {
        // Enabling remains opt-in: immediately return the model and the
        // native checkbox to OFF until the warning is confirmed.
        view.settings.aiDriver.enabled = false;
        view.aiDriverConfirmOpen = true;
        return;
      }
      view.aiDriverConfirmOpen = false;
      hud.settingsChanged();
    };
    hud.cancelAiDriverEnable = () => {
      view.settings.aiDriver.enabled = false;
      view.aiDriverConfirmOpen = false;
    };
    hud.confirmAiDriverEnable = () => {
      view.settings.aiDriver.enabled = true;
      view.aiDriverConfirmOpen = false;
      hud.settingsChanged();
    };
    hud.toggleSettingsSection = (section) => {
      if (!Object.prototype.hasOwnProperty.call(view.settingsSections, section)) return;
      const open = !view.settingsSections[section];
      if (view.externalPhoneMode) {
        Object.keys(view.settingsSections).forEach((key) => {
          view.settingsSections[key] = false;
        });
      }
      view.settingsSections[section] = open;
      if (section !== "cheats") view.cheatResetArmed = false;
    };
    hud.settingsChanged = () => {
      applyGameUiVolume();
      updateClock();
      scheduleMinimapUpdate();
      scheduleReviewPagination();
      queueSettingsSave();
    };
    hud.toggleRandomEvent = (option) => {
      if (!option || option.key !== "policeCheck") {
        hud.settingsChanged();
        return;
      }
      const police = view.settings.randomEvents.policeCheck;
      if (police.enabled === true) {
        police.enabled = false;
        police.preloadConfirmed = false;
        view.policeCheckConfirmOpen = true;
        return;
      }
      police.preloadConfirmed = false;
      hud.settingsChanged();
    };
    hud.cancelPoliceCheckEnable = () => {
      const police = view.settings.randomEvents.policeCheck;
      police.enabled = false;
      police.preloadConfirmed = false;
      view.policeCheckConfirmOpen = false;
    };
    hud.confirmPoliceCheckEnable = () => {
      const police = view.settings.randomEvents.policeCheck;
      police.enabled = true;
      police.preloadConfirmed = true;
      view.policeCheckConfirmOpen = false;
      hud.settingsChanged();
    };

    const findOfflineHoldButton = (target) => {
      let node = target;
      while (node && node !== appRoot) {
        if (node.classList && node.classList.contains("taxi-offline-hold")) return node;
        node = node.parentElement;
      }
      return null;
    };
    const handleOfflineHoldStart = (event) => {
      if (!findOfflineHoldButton(event.target)) return;
      hud.beginOfflineHold(event);
    };
    const handleOfflineHoldEnd = () => hud.cancelOfflineHold();
    const handleOfflineHoldVisibility = () => {
      if (document.hidden || document.visibilityState === "hidden") stopOfflineHold();
    };
    const handleOfflineHoldKeydown = (event) => {
      if (!findOfflineHoldButton(event.target)) return;
      if (event.key !== " " && event.key !== "Enter") return;
      if (!event.repeat) hud.beginOfflineHold(event);
      event.preventDefault();
    };
    const handleOfflineHoldKeyup = (event) => {
      if (event.key !== " " && event.key !== "Enter") return;
      if (!offlineHoldTimer) return;
      hud.cancelOfflineHold();
      event.preventDefault();
    };

    let dialogRestoreFocus = null;
    let dialogFocusTimer = null;
    const getOpenDialog = () => appRoot.querySelector('.taxi-offline-confirm[role="dialog"]');
    const getDialogControls = (dialog) => Array.prototype.slice.call(
      dialog.querySelectorAll('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')
    );
    const closeOpenDialog = () => {
      if (view.offlineConfirmOpen) hud.cancelOfflineConfirmation();
      else if (view.policeCheckConfirmOpen) hud.cancelPoliceCheckEnable();
      else if (view.aiDriverConfirmOpen) hud.cancelAiDriverEnable();
    };
    const handleDialogKeydown = (event) => {
      const dialog = getOpenDialog();
      if (!dialog) return;
      if (event.key === "Escape" || event.key === "Esc") {
        event.preventDefault();
        scheduleUi(closeOpenDialog);
        return;
      }
      if (event.key !== "Tab") return;
      const controls = getDialogControls(dialog);
      if (!controls.length) {
        event.preventDefault();
        dialog.querySelector(".taxi-offline-confirm__card").focus();
        return;
      }
      const first = controls[0];
      const last = controls[controls.length - 1];
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        first.focus();
      }
    };
    const stopDialogWatch = watchFields([
      "offlineConfirmOpen",
      "policeCheckConfirmOpen",
      "aiDriverConfirmOpen",
    ], (values) => {
      const isOpen = values.some(Boolean);
      if (dialogFocusTimer) clearTimeout(dialogFocusTimer);
      dialogFocusTimer = null;
      if (isOpen) {
        if (!dialogRestoreFocus) dialogRestoreFocus = document.activeElement;
        dialogFocusTimer = setTimeout(() => {
          const dialog = getOpenDialog();
          if (!dialog) return;
          const controls = getDialogControls(dialog);
          const target = controls[0] || dialog.querySelector(".taxi-offline-confirm__card");
          if (target) target.focus();
        }, 0);
      } else if (dialogRestoreFocus) {
        const target = dialogRestoreFocus;
        dialogRestoreFocus = null;
        if (target && document.documentElement.contains(target) && typeof target.focus === "function") {
          target.focus();
        }
      }
    });
    listen(appRoot, "pointerdown", handleOfflineHoldStart, true);
    listen(appRoot, "pointerup", handleOfflineHoldEnd, true);
    listen(appRoot, "pointercancel", handleOfflineHoldEnd, true);
    listen(appRoot, "touchstart", handleOfflineHoldStart, true);
    listen(appRoot, "touchend", handleOfflineHoldEnd, true);
    listen(appRoot, "touchcancel", handleOfflineHoldEnd, true);
    listen(appRoot, "keydown", handleOfflineHoldKeydown, true);
    listen(appRoot, "keyup", handleOfflineHoldKeyup, true);
    listen(window, "pointerup", handleOfflineHoldEnd, true);
    listen(window, "pointercancel", handleOfflineHoldEnd, true);
    listen(window, "touchend", handleOfflineHoldEnd, true);
    listen(window, "touchcancel", handleOfflineHoldEnd, true);
    listen(window, "blur", handleOfflineHoldEnd);
    listen(window, "keyup", handleOfflineHoldKeyup, true);
    listen(document, "visibilitychange", handleOfflineHoldVisibility);
    listen(appRoot, "keydown", handleDialogKeydown, true);
    hud.selectExternalMapQuality = (quality) => {
      if (!["eco", "balanced", "smooth"].includes(quality)) return;
      view.settings.externalMapQuality = quality;
      hud.settingsChanged();
    };
    hud.selectUnitSystem = (unitSystem) => {
      view.settings.unitSystem = unitSystem === "imperial" ? "imperial" : "metric";
      hud.settingsChanged();
    };
    hud.selectTimeFormat = (timeFormat) => {
      view.settings.timeFormat = timeFormat === "24h" ? "24h" : "12h";
      hud.settingsChanged();
    };
    hud.previewAppVolume = () => {
      view.settings.appVolume = Math.max(
        0,
        Math.min(1, Number(view.settings.appVolume) || 0)
      );
      applyGameUiVolume();
      queueSettingsSave();
    };
    hud.testAppVolume = () => {
      hud.previewAppVolume();
      const soundIds = ["click", "newRide", "offline", "online", "violation", "message", "overspeed"];
      const enabledSounds = soundIds.filter((soundId) =>
        !view.settings.soundToggles || view.settings.soundToggles[soundId] !== false
      );
      if (enabledSounds.length) {
        playAppSound(enabledSounds[Math.floor(Math.random() * enabledSounds.length)]);
      }
    };
    hud.toggleRealisticMode = () => {
      view.settings.realisticMode = view.settings.realisticMode === true;
      persistSettingsNow();
    };
    hud.toggleRandomEvents = () => {
      view.settings.randomEventsEnabled = view.settings.randomEventsEnabled === true;
      persistSettingsNow();
    };
    hud.cheatSetRating = () => {
      const rating = Math.max(0, Math.min(5, Number(view.cheatRating) || 0));
      view.cheatRating = rating;
      // Reflect the explicit cheat immediately. Lua remains authoritative
      // and publishes the same canonical value back in the next snapshot.
      view.state.rating = rating;
      view.profileProgress.rating = rating;
      const serializedRating = bngApi.serializeToLua(rating.toFixed(2));
      // This is deliberately a plain statement without `if`/`return` or a
      // callback. BeamNG wraps callback commands as Lua expressions, which
      // makes a conditional statement invalid and raises a Fatal Lua Error.
      // cheatSetRating publishes the authoritative HUD/profile snapshots.
      bngApi.engineLua(`taxiDriver_taxiDriver.cheatSetRating(${serializedRating})`);
    };
    hud.cheatSetEnergyPercent = (event) => {
      const input = event && event.currentTarget && event.currentTarget.parentElement
        ? event.currentTarget.parentElement.querySelector('input[type="range"]')
        : null;
      const selectedValue = input ? input.value : view.cheatEnergyDraft;
      const percent = Math.max(0, Math.min(100,
        Math.round(Number(selectedValue) || 0)
      ));
      view.cheatEnergyPercent = percent;
      view.cheatEnergyDraft = percent;
      bngApi.engineLua(`taxiDriver_taxiDriver.cheatSetEnergyPercent(${percent})`);
    };
    hud.cheatEnergyChanged = () => {
      view.cheatEnergyDraft = Math.max(0, Math.min(100,
        Math.round(Number(view.cheatEnergyPercent) || 0)
      ));
    };
    hud.cheatRepairVehicle = () => bngApi.engineLua(
      "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatRepairVehicle() end"
    );
    hud.cheatAddMoney = (amount) => {
      const allowed = [1, 5, 10, 50];
      const value = Number(amount);
      if (!allowed.includes(value)) return;
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatAddMoney(${value}) end`
      );
    };
    hud.cheatAddRandomReview = () => bngApi.engineLua(
      "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatAddRandomReview() end"
    );
    hud.armCheatReset = () => {
      view.cheatResetArmed = true;
    };
    hud.cancelCheatReset = () => {
      view.cheatResetArmed = false;
    };
    hud.confirmCheatReset = () => {
      view.cheatResetArmed = false;
      view.cheatRating = 5;
      bngApi.engineLua(
        "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cheatResetProgress() end"
      );
    };
    hud.openFuelStation = () => {
      if (!view.state.fuelStation.available && !view.state.repairStation.available) return;
      view.fuelStationOpen = true;
      view.settingsOpen = false;
      view.profileOpen = false;
      view.offlineConfirmOpen = false;
      dismissPassengerChat();
      hideMinimap();
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestRealisticFuelData() end'
      );
    };
    hud.handleFuelAction = () => {
      if (!view.canUseFuelService()) return;
      if (view.phoneMinimized) hud.toggleMinimized();
      if (view.state.fuelStation.available || view.state.repairStation.available) {
        hud.openFuelStation();
        return;
      }
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestFuelStop() end'
      );
    };
    hud.closeFuelStation = () => {
      if (view.state.fuelStation.refueling.active || view.state.repairStation.repairing.active) return;
      view.fuelStationOpen = false;
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.completeFuelStop() end'
      );
      scheduleMinimapUpdate();
    };
    hud.cancelFuelRoute = () => {
      if (view.state.fuelStation.refueling.active) return;
      view.fuelStationOpen = false;
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.cancelFuelStop() end'
      );
      scheduleMinimapUpdate();
    };
    hud.selectFuelType = (energyType) => {
      if (view.state.fuelStation.refueling.active) return;
      if (!getFuelOption(energyType)) return;
      view.selectedFuelType = energyType;
      view.refuel.amount = 0;
    };
    hud.updateRefuelAmount = () => clampRefuelAmount();
    hud.setRefuelPreset = (preset) => {
      const option = getFuelOption(view.selectedFuelType);
      if (!option || view.state.fuelStation.refueling.active) return;
      const affordable = Math.max(0, Number(option.affordableQuantity || 0));
      if (preset === "half") {
        view.refuel.amount = Math.max(0,
          Number(option.maxQuantity || 0) * 0.5 - Number(option.currentQuantity || 0));
      } else if (preset === "full") {
        view.refuel.amount = affordable;
      } else {
        view.refuel.amount = Number(view.refuel.amount || 0) + Math.max(0, Number(preset || 0));
      }
      clampRefuelAmount();
    };
    hud.purchaseFuel = () => {
      if (view.state.fuelStation.refueling.active || view.state.repairStation.repairing.active ||
        !view.state.fuelStation.vehicleStopped) return;
      const option = getFuelOption(view.selectedFuelType);
      clampRefuelAmount();
      const quantity = Number(view.refuel.amount || 0);
      if (!option || quantity <= 0) return;
      const energyType = bngApi.serializeToLua(option.energyType);
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.purchaseRealisticFuel(${energyType}, ${quantity.toFixed(3)}) end`
      );
    };
    hud.purchaseRepair = () => {
      const repairStation = view.state.repairStation;
      if (repairStation.repairing.active || view.state.fuelStation.refueling.active ||
        !repairStation.vehicleStopped ||
        !repairStation.canRepair || repairStation.balance < repairStation.price) return;
      bngApi.engineLua(
        'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.purchaseRepair() end'
      );
    };
    hud.acceptOrder = (offerId) => {
      const id = Math.floor(Number(offerId || 0));
      if (id <= 0) return;
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptOrder(${id}) end`
      );
    };
    hud.acceptNextOffer = (offerId) => {
      const id = Math.floor(Number(offerId || 0));
      if (id <= 0) return;
      if (view.nextOfferUiRemaining <= 0) {
        expireNextOfferLocally(id);
        return;
      }
      clearNextOfferCountdown();
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.acceptNextOffer(${id}) end`
      );
    };
    hud.dismissNextOffer = (offerId) => {
      const id = Math.floor(Number(offerId || 0));
      if (id > 0) expireNextOfferLocally(id, true);
    };

    const formatCompactMagnitude = (value, decimals = 1) => {
      const numeric = Number(value || 0);
      const absolute = Math.abs(numeric);
      if (absolute < 1000) return numeric.toFixed(0);
      const scales = [
        { value: 1e9, suffix: "B" },
        { value: 1e6, suffix: "M" },
        { value: 1e3, suffix: "K" },
      ];
      const scale = scales.find((entry) => absolute >= entry.value) || scales[2];
      const scaled = numeric / scale.value;
      return `${scaled.toFixed(Math.abs(scaled) >= 100 ? 0 : decimals)}${scale.suffix}`;
    };
    view.formatCount = (value) => {
      const numeric = Math.max(0, Math.floor(Number(value || 0)));
      return numeric > 999 ? "999+" : String(numeric);
    };
    view.formatAggregateNumber = (value) => {
      const numeric = Math.max(0, Math.floor(Number(value || 0)));
      return numeric < 1000 ? String(numeric) : formatCompactMagnitude(numeric, 1);
    };
    view.formatMoneyFull = (value) => {
      const numeric = Number(value || 0);
      const sign = numeric < 0 ? "−" : "";
      const amount = Math.abs(numeric).toLocaleString(view.language || "en", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
      return `${sign}$${amount}`;
    };
    view.formatMoney = (value) => {
      const numeric = Number(value || 0);
      if (Math.abs(numeric) < 100000) return view.formatMoneyFull(numeric);
      const sign = numeric < 0 ? "−" : "";
      return `${sign}$${formatCompactMagnitude(Math.abs(numeric), 2)}`;
    };
    view.formatOdometer = (meters) => {
      const distance = Math.max(0, Number(meters || 0));
      const value = view.settings.unitSystem === "imperial"
        ? distance / 1609.344 : distance / 1000;
      if (value >= 1000) return `${formatCompactMagnitude(value, 1)} ${view.t(view.settings.unitSystem === "imperial" ? "unitMile" : "unitKm")}`;
      const fixed = value.toFixed(1).split(".");
      const decimalSeparator = view.language === "en" || view.language === "zh-CN" ? "." : ",";
      const unit = view.t(view.settings.unitSystem === "imperial" ? "unitMile" : "unitKm");
      return `${fixed[0].padStart(4, "0")}${decimalSeparator}${fixed[1]} ${unit}`;
    };
    view.formatShiftDate = (timestamp) => {
      const value = Math.max(0, Number(timestamp || 0));
      if (!value) return "";
      return new Date(value * 1000).toLocaleString(view.language || "en", {
        year: "numeric", month: "short", day: "numeric",
        hour: "2-digit", minute: "2-digit",
        hour12: view.settings.timeFormat !== "24h",
      });
    };
    view.formatDistance = (meters) => {
      const value = Math.max(0, Number(meters || 0));
      if (view.settings.unitSystem === "imperial") {
        const miles = value / 1609.344;
        return value >= 1609.344
          ? `${miles >= 1000 ? formatCompactMagnitude(miles, 1) : miles.toFixed(1)} ${view.t("unitMile")}`
          : `${Math.round(value * 3.28084)} ${view.t("unitFoot")}`;
      }
      const kilometers = value / 1000;
      return value >= 1000
        ? `${kilometers >= 1000 ? formatCompactMagnitude(kilometers, 1) : kilometers.toFixed(1)} ${view.t("unitKm")}`
        : `${Math.round(value)} ${view.t("unitMeter")}`;
    };
    view.formatSpeed = (kmh) => view.settings.unitSystem === "imperial"
      ? `${Math.round(Math.max(0, Number(kmh || 0)) * 0.621371)} ${view.t("unitMph")}`
      : `${Math.round(Math.max(0, Number(kmh || 0)))} ${view.t("unitKmh")}`;
    view.formatSpeedValue = (kmh) => view.settings.unitSystem === "imperial"
      ? Math.round(Math.max(0, Number(kmh || 0)) * 0.621371)
      : Math.round(Math.max(0, Number(kmh || 0)));
    view.getSpeedUnit = () => view.t(
      view.settings.unitSystem === "imperial" ? "unitMph" : "unitKmh"
    );
    view.formatEta = (minutes) => {
      const value = Math.max(0, Number(minutes || 0));
      if (value < 1) return `< 1 ${view.t("unitMin")}`;
      if (value < 60) return `${Math.ceil(value)} ${view.t("unitMin")}`;
      const hours = Math.floor(value / 60);
      return `${hours} ${view.t("unitHour")} ${Math.ceil(value - hours * 60)} ${view.t("unitMin")}`;
    };
    view.formatCountdown = (seconds) => {
      const value = Math.max(0, Math.ceil(Number(seconds || 0)));
      const minutes = Math.floor(value / 60);
      return `${minutes}:${String(value % 60).padStart(2, "0")}`;
    };
    view.getArrivalTime = (minutes) => {
      const arrival = new Date(Date.now() + Math.max(0, Number(minutes || 0)) * 60000);
      return arrival.toLocaleTimeString([], {
        hour: "2-digit", minute: "2-digit", hour12: view.settings.timeFormat !== "24h",
      });
    };
    view.getInitials = (name) =>
      String(name || "P")
        .split(/\s+/)
        .slice(0, 2)
        .map((part) => part.charAt(0).toUpperCase())
        .join("");
    view.getCalmnessEmoji = (value) => {
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
    view.getOfferName = (offer) => offer && offer.isDelivery
      ? view.t("deliveryOrder")
      : String(offer && offer.passengerName || "");
    view.formatCargoWeight = (value) => {
      const kilograms = Math.max(0, Number(value || 0));
      if (view.settings.unitSystem === "imperial") {
        const pounds = kilograms * 2.20462;
        return `${pounds >= 1000 ? formatCompactMagnitude(pounds, 1) : pounds.toFixed(0)} ${view.t("unitPound")}`;
      }
      const weight = kilograms >= 1000 ? formatCompactMagnitude(kilograms, 1) : kilograms.toFixed(0);
      return view.t("cargoWeightValue", { weight });
    };
    view.getProgressPercent = () =>
      Math.max(0, Math.min(100, Number(view.hasPersonalRoute() ? view.earth.freeRoute.progress : view.state.routeProgress || 0) * 100));
    view.getStarFill = (star) => {
      const rating = Number(view.state.rating || 0);
      return Math.max(0, Math.min(100, (rating - (star - 1)) * 100));
    };
    view.getRatingPercent = () =>
      Math.max(0, Math.min(100, Number(view.state.rating || 0) / 5 * 100));
    view.getUiScalePercent = () => Math.max(80, Math.min(
      180,
      Math.round((Number(view.settings.uiScalePercent) || 100) / 10) * 10
    ));
    view.getUiScaleClass = () => {
      const percent = view.getUiScalePercent();
      let tier = "regular";
      if (percent >= 160) tier = "accessibility";
      else if (percent >= 140) tier = "large";
      else if (percent >= 110) tier = "reduced";
      return `taxi-ui-scale--${percent} taxi-ui-tier--${tier}`;
    };
    view.getAppVolumePercent = () => Math.round(
      Math.max(0, Math.min(1, Number(view.settings.appVolume) || 0)) * 100
    );
    view.formatCustomDifficultyValue = (control) => {
      const value = Number(view.settings.customDifficulty[control.key] || 0);
      if (control.unit === "kmh") return view.formatSpeed(value);
      if (control.unit === "percent") return `${value.toFixed(control.decimals)}%`;
      if (control.unit === "seconds") return `${value.toFixed(control.decimals)} ${view.t("unitSeconds")}`;
      if (control.unit === "g") return `${value.toFixed(control.decimals)} g`;
      return value.toFixed(control.decimals);
    };
    view.getPassengerOrderShare = () =>
      Math.max(0, 100 - Number(view.settings.deliveryOrderSharePercent || 0));
    view.formatEconomyMultiplier = () =>
      `${Number(view.settings.economyMultiplier || 1).toFixed(2)}×`;
    view.formatRating = (value) => Number(value || 0).toFixed(2);
    view.formatBonusPercent = (value) => Number(value || 0).toFixed(1).replace(/\.0$/, "");
    view.getOfferIncomePerMinute = (offer) => Number(offer && offer.estimatedFare || 0) /
      Math.max(0.1, Number(offer && offer.etaMinutes || 0));
    view.getOfferIncomePerKm = (offer) => Number(offer && offer.estimatedFare || 0) /
      Math.max(0.1, Number(offer && offer.rideDistance || 0) / 1000) *
      (view.settings.unitSystem === "imperial" ? 1.609344 : 1);
    view.getVehicleProfitPerDistance = (vehicle) => Number(vehicle && vehicle.profitPerKm || 0) *
      (view.settings.unitSystem === "imperial" ? 1.609344 : 1);
    view.getOfferSortLabel = () => {
      const selected = view.offerSortOptions.find((option) => option.value === view.offerSort);
      return view.t(selected ? selected.label : "sortFare");
    };
    view.getVehicleSortLabel = () => {
      const selected = view.vehicleSortOptions.find((option) => option.value === view.vehicleSort);
      return view.t(selected ? selected.label : "distance");
    };
    // HUD packets replace offer/profile arrays. Reuse their sorted views between
    // packets rather than allocating and sorting during every Vue render.
    const emptyOffers = [];
    let sortedOffersSource, sortedOffersKey, sortedOffers;
    view.getSortedOffers = () => {
      const source = view.state.offers || emptyOffers;
      const key = view.offerSort;
      if (source === sortedOffersSource && key === sortedOffersKey) return sortedOffers;
      sortedOffersSource = source;
      sortedOffersKey = key;
      sortedOffers = source.slice().sort((left, right) => {
        if (key === "pickup") return Number(left.pickupDistance || 0) - Number(right.pickupDistance || 0);
        if (key === "distance") return Number(left.rideDistance || 0) - Number(right.rideDistance || 0);
        if (key === "duration") return Number(left.etaMinutes || 0) - Number(right.etaMinutes || 0);
        if (key === "perKm") return view.getOfferIncomePerKm(right) - view.getOfferIncomePerKm(left);
        return Number(right.estimatedFare || 0) - Number(left.estimatedFare || 0);
      });
      return sortedOffers;
    };
    view.getPenaltyFareLoss = () => Math.max(
      0,
      Number(view.state.estimatedFare || 0) - Number(view.state.adjustedFare || 0)
    );
    let sortedVehiclesSource, sortedVehiclesKey, sortedVehicles;
    view.getSortedProfileVehicles = () => {
      const source = view.profileVehicles;
      const key = view.vehicleSort;
      if (source === sortedVehiclesSource && key === sortedVehiclesKey) return sortedVehicles;
      sortedVehiclesSource = source;
      sortedVehiclesKey = key;
      sortedVehicles = source.slice().sort((left, right) => {
        if (key === "income") return Number(right.income || 0) - Number(left.income || 0);
        if (key === "rides") return Number(right.completedRides || 0) - Number(left.completedRides || 0);
        return Number(right.distanceMeters || 0) - Number(left.distanceMeters || 0);
      });
      return sortedVehicles;
    };
    view.getSelectedFuelOption = () => getFuelOption(view.selectedFuelType);
    view.getFuelDisplayUnit = (option) => option && option.unit === "L" &&
      view.settings.unitSystem === "imperial" ? view.t("unitGallon") : String(option && option.unit || "");
    view.getFuelDisplayQuantity = (quantity, option) => option && option.unit === "L" &&
      view.settings.unitSystem === "imperial" ? Number(quantity || 0) / 3.785411784 : Number(quantity || 0);
    view.getFuelDisplayPrice = (option) => {
      if (!option) return 0;
      return option.unit === "L" && view.settings.unitSystem === "imperial"
        ? Number(option.pricePerUnit || 0) * 3.785411784
        : Number(option.pricePerUnit || 0);
    };
    view.formatEnergyRange = (kilometers) => {
      const metric = Math.max(0, Number(kilometers || 0));
      const value = view.settings.unitSystem === "imperial" ? metric * 0.621371 : metric;
      return `${value >= 1000 ? formatCompactMagnitude(value, 1) : Math.round(value)} ${view.t(view.settings.unitSystem === "imperial" ? "unitMile" : "unitKm")}`;
    };
    view.formatDashboardEnergy = () => {
      const energy = view.state.vehicleEnergy || {};
      return `${view.getFuelDisplayQuantity(energy.quantity, energy).toFixed(2)} ${view.getFuelDisplayUnit(energy)}`;
    };
    view.getRouteFuelPercent = () => {
      const energy = view.state.vehicleEnergy || {};
      const suppliedPercent = Number(energy.percent);
      if (Number.isFinite(suppliedPercent) && suppliedPercent > 0) {
        return Math.max(0, Math.min(100, suppliedPercent));
      }
      const quantity = Math.max(0, Number(energy.quantity || 0));
      const maximum = Math.max(0, Number(energy.maxQuantity || 0));
      return maximum > 0 ? Math.max(0, Math.min(100, quantity / maximum * 100)) : 0;
    };
    view.getRouteFuelGaugeBackground = () => {
      const percent = view.getRouteFuelPercent().toFixed(2);
      return `conic-gradient(var(--taxi-accent) ${percent}%, rgba(255,255,255,.1) ${percent}% 100%)`;
    };
    view.getRefuelMaximum = () => {
      const option = getFuelOption(view.selectedFuelType);
      return option ? Math.max(0, Number(option.affordableQuantity || 0)) : 0;
    };
    view.getRefuelCost = () => {
      const option = getFuelOption(view.selectedFuelType);
      return option ? Number(view.refuel.amount || 0) * Number(option.pricePerUnit || 0) : 0;
    };
    view.getRefuelSelectionPercent = () => {
      const maximum = view.getRefuelMaximum();
      return maximum > 0
        ? Math.max(0, Math.min(100, Number(view.refuel.amount || 0) / maximum * 100))
        : 0;
    };
    view.getProjectedFuelPercent = () => {
      const option = getFuelOption(view.selectedFuelType);
      if (!option) return 0;
      const maximum = Number(option.maxQuantity || 0);
      const added = maximum > 0 ? Number(view.refuel.amount || 0) / maximum * 100 : 0;
      return Math.max(0, Math.min(100, Number(option.currentPercent || 0) + added));
    };
    view.getProjectedFuelRange = () => {
      const option = getFuelOption(view.selectedFuelType);
      if (!option || Number(option.consumptionPer100Km || 0) <= 0) return 0;
      return (Number(option.currentQuantity || 0) + Number(view.refuel.amount || 0)) /
        Number(option.consumptionPer100Km) * 100;
    };
    view.isProjectedFuelEnough = () => view.getProjectedFuelRange() * 1000 >=
      Math.max(0, Number(view.state.distanceToTarget || 0));
    view.getDisplayedFuelPercent = () => {
      const option = getFuelOption(view.selectedFuelType);
      if (!option) return 0;
      const session = view.state.fuelStation.refueling;
      const addedPercent = session.active && session.energyType === option.energyType &&
        Number(option.maxQuantity || 0) > 0
        ? Number(session.quantity || 0) / Number(option.maxQuantity) * 100 *
          Number(session.progress || 0)
        : 0;
      return Math.max(0, Math.min(100, Number(option.currentPercent || 0) + addedPercent));
    };
    view.shouldShowNextOffer = () => {
      const offer = view.state.nextOffer;
      if (!externalPhoneMode && view.phoneSuperMinimized) return false;
      if (view.settingsOpen || view.profileOpen || view.offlineConfirmOpen || view.fuelStationOpen) return false;
      if (!offer || view.state.phase !== "toDestination") return false;
      return offer.accepted ? view.nextOfferAcceptedVisible : view.nextOfferUiRemaining > 0;
    };
    view.shouldShowQueuedOrder = () => {
      const offer = view.state.nextOffer;
      if (!offer || offer.accepted !== true) return false;
      const activeTripId = Number(view.state.activeTripId || 0);
      const queuedTripIsCurrent = activeTripId > 0 && Number(offer.id || 0) === activeTripId;
      return !queuedTripIsCurrent || view.state.phase === "toPickup";
    };
    view.getPhaseLabel = () => {
      if (view.hasPersonalRoute()) return view.t(view.earth.freeRoute.leg === 'a' ? 'earthNavigateA' : 'earthPersonalRoute');
      if (view.state.isDelivery && view.state.phase === "toPickup") return view.t("phase_deliveryPickup");
      if (view.state.isDelivery && view.state.phase === "toDestination") return view.t("phase_deliveryDestination");
      if (view.state.isDelivery && view.state.phase === "boarding") return view.t("loadingCargo");
      if (view.state.isDelivery && view.state.phase === "alighting") return view.t("unloadingCargo");
      return view.t(`phase_${view.state.phase || "inactive"}`);
    };
    view.isNavigationPhase = () => view.hasPersonalRoute() || minimapPhases.has(view.state.phase);
    view.getCompactTitle = () => {
      if (view.hasPersonalRoute()) return view.earth.freeRoute.name || view.t('earthPersonalRoute');
      if (!view.state.active) return "TaxiDriver";
      if (view.state.phase === "toFuelStation") {
        return view.state.fuelDetour.stationName || view.t("fuelRouteTitle");
      }
      if (view.state.isDelivery) return view.t("deliveryOrder");
      return view.state.passengerName || view.getPhaseLabel();
    };
    view.getProgressLabel = () => {
      const map = {
        toPickup: view.state.isDelivery ? "progress_deliveryPickup" : "progress_pickup",
        boarding: "progress_boarding",
        toStop: "progress_stop", stopWaiting: "progress_stopWaiting",
        toDestination: view.state.isDelivery ? "progress_delivery" : "progress_ride",
        toFuelStation: "progress_fuel",
        alighting: "progress_alighting",
      };
      return view.t(map[view.state.phase] || "progress_route");
    };
    view.getStatusText = () => {
      if (view.state.phase === "searching") {
        return view.state.offers.length
          ? view.t("offersDynamic", {
              count: view.state.offers.length,
              target: view.state.offerTargetCount,
            })
          : view.t("connecting");
      }
      return view.t("followRoute");
    };
    view.getPenaltyLabel = (event) => view.t(`penalty_${event.kind || "speeding"}`);
    view.getPhoneNotificationText = () => {
      if (!view.phoneToast) return "";
      const values = Object.assign({}, view.phoneToast.values || {});
      if (view.phoneToast.key === "notify_deliveryLoaded" && values.weight !== undefined) {
        values.weight = view.formatCargoWeight(values.weight);
      }
      return view.t(view.phoneToast.key, values);
    };
    view.getPenaltyDetail = (event) => {
      if (event.kind === "speeding") return view.t("detail_speeding", {
        speed: view.formatSpeedValue(event.speedExcess || 0),
        unit: view.getSpeedUnit(),
        duration: Number(event.duration || 0).toFixed(1),
      });
      if (event.kind === "collision") return view.t("detail_collision", {
        damage: Number(event.damage || 0).toFixed(0),
      });
      if (event.kind === "cargoDamage") return view.t("detail_cargoDamage", {
        damage: Number(event.cargoDamagePercent || 0).toFixed(1),
      });
      if (event.kind === "aggression") return view.t("detail_aggression", {
        g: Number(event.peakG || 0).toFixed(2),
      });
      if (event.kind === "bonus") return view.t("detail_bonus");
      if (event.kind === "pickupDelay") return view.t("detail_pickupDelay", {
        time: view.formatCountdown(event.lateSeconds || 0),
      });
      if (event.kind === "fuelStop") return view.t("detail_fuelStop", {
        station: event.stationName || view.t("refuelTitle"),
      });
      return event.detail || "";
    };
    view.getQuality = () => Math.max(
      view.state.isDelivery ? 0 : 50,
      100 - Number(view.state.penaltyPercent || 0)
    );

    const requestHudResync = () => {
      const now = Date.now();
      if (now - hudResyncRequestedAt < 750) return;
      hudResyncRequestedAt = now;
      bngApi.engineLua(
        "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestExternalHudState() end"
      );
    };

    onGameEvent("TaxiDriverHUDPatch", (patch) => {
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
      const merged = Object.assign({}, view.state, patch.values || {});
      (Array.isArray(patch.removed) ? patch.removed : []).forEach((key) => {
        merged[key] = null;
      });
      if (versioned) {
        merged.hudEpoch = patchEpoch;
        merged.hudRevision = patchRevision;
      }
      emitLocal("TaxiDriverHUDState", merged);
    });
    onGameEvent("TaxiDriverHUDState", (data) => {
      if (!data) return;
      const incomingEpoch = String(data.hudEpoch || "");
      const incomingRevision = Number(data.hudRevision);
      if (incomingEpoch && Number.isFinite(incomingRevision)) {
        if (incomingEpoch === hudEpoch && incomingRevision <= hudRevision) return;
        if (incomingEpoch !== hudEpoch) {
          hudEpoch = incomingEpoch;
          hudRevision = 0;
          // Offer/notification ids and their deadlines belong to one backend
          // session. Reloading the extension can reuse the same numeric ids.
          expiredNextOfferIds.clear();
          clearNextOfferCountdown();
          lastPhoneNotificationId = 0;
          lastAnnouncedNextOfferId = null;
        }
        hudRevision = incomingRevision;
        hudResyncRequestedAt = 0;
      }
      const previousMapPhase = view.state.phase;
      if (data.earth) applyEarth(data.earth);
      const previousMapSpeed = Number(view.state.currentSpeed || 0);
      // Lua omits nil fields from full snapshots. Patches already merge their
      // unchanged values before reaching this handler, so absence means clear.
      data.nextOffer = data.nextOffer || null;
      data.notification = data.notification || null;
      data.currentVehicle = Object.assign(
        { available: false, key: "", name: "", preview: "", distanceMeters: 0, completedRides: 0, income: 0 },
        data.currentVehicle || {}
      );
      data.vehicleEnergy = Object.assign(
        { available: false, energyType: "", quantity: 0, maxQuantity: 0, percent: 0, unit: "", estimatedRangeKm: 0 },
        data.vehicleEnergy || {}
      );
      data.fuelStation = normalizeFuelStation(data.fuelStation);
      data.repairStation = normalizeRepairStation(data.repairStation);
      data.fuelDetour = normalizeFuelDetour(data.fuelDetour);
      data.autopilot = Object.assign(
        { available: false, enabled: false, suspended: false, status: "off", reason: "", stuckSeconds: 0, recoveryAttempt: 0 },
        data.autopilot || {}
      );
      const refuelingJustCompleted = hudStateReceived &&
        data.fuelStation.refueling.completionId >
          Number(view.state.fuelStation.refueling.completionId || 0);
      const passengerMoodChanged = hudStateReceived &&
        Number(data.activeTripId || 0) > 0 &&
        Number(data.activeTripId || 0) === Number(view.state.activeTripId || 0) &&
        Number(data.passengerMoodChangeId || 0) >
          Number(view.state.passengerMoodChangeId || 0);
      if (!data.active || data.phase === "driverAbandoning") {
        stopOfflineHold();
        view.offlineConfirmOpen = false;
      }
      const pickupJustStarted = data.phase === "boarding" && view.state.phase === "toPickup";
      if (pickupJustStarted) {
        view.nextOfferAcceptedVisible = false;
        if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
        acceptedOfferTimer = null;
        if (view.phoneToast && ["notify_orderAccepted", "notify_deliveryAccepted"].includes(view.phoneToast.key)) {
          view.phoneToast = null;
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
            data.settings = Object.assign({}, view.settings);
          } else {
            if (backendFingerprint === pendingSettingsFingerprint || !pendingIsCurrent) {
              pendingSettingsFingerprint = "";
              pendingSettingsDeadline = 0;
            }
            view.settings = backendSettings;
            view.language = backendSettings.language;
            data.settings = backendSettings;
            applyGameUiVolume();
          }
          if (!settingsInitializedFromBackend) {
            settingsInitializedFromBackend = true;
            try { storage.removeItem(settingsKey); } catch (_) {}
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
        (!view.state.nextOffer || !view.state.nextOffer.accepted);
      const hasNewNotification = data.notification && data.notification.id !== lastPhoneNotificationId &&
        !(pickupJustStarted && ["notify_orderAccepted", "notify_deliveryAccepted"].includes(data.notification.key));
      const becameOnline = hudStateReceived && data.active === true && view.state.active !== true;
      const becameOffline = hudStateReceived && data.active === false && view.state.active === true;
      const navigationPhase = ["toPickup", "toStop", "toDestination", "toFuelStation"].includes(data.phase);
      const overspeedThreshold = Number(data.speedLimit || 0) +
        Number(view.settings.overspeedWarningKmh || 0);
      const isOverspeedWarning = data.active === true && navigationPhase &&
        Number(data.speedLimit || 0) > 0 && Number(data.currentSpeed || 0) > overspeedThreshold;
      if (becameOnline) playAppSound("online");
      if (becameOffline) playAppSound("offline");
      if (hasNewNextOffer) playAppSound("newRide");
      if (isOverspeedWarning && !overspeedWarningActive) playAppSound("overspeed");
      overspeedWarningActive = isOverspeedWarning;
      view.overspeedWarningActive = isOverspeedWarning;
      if ((hasNewNextOffer || hasNewNotification) &&
          (view.phoneMinimized || view.phoneSuperMinimized) &&
          !(data.lan && Number(data.lan.connected || 0) > 0)) {
        view.collapseAttention = true;
      }
      if (hasNewNotification) {
        dismissPassengerChat();
        lastPhoneNotificationId = data.notification.id;
        view.phoneToast = data.notification;
        if (phoneToastTimer) clearTimeout(phoneToastTimer);
        phoneToastTimer = setTimeout(() => scheduleUi(() => {
          view.phoneToast = null;
          phoneToastTimer = null;
        }), 3600);
      }
      if (hasNewAcceptedOffer) {
        view.nextOfferAcceptedVisible = true;
        if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
        acceptedOfferTimer = setTimeout(() => scheduleUi(() => {
          view.nextOfferAcceptedVisible = false;
          acceptedOfferTimer = null;
        }), 1200);
      }
      // Empty Lua tables are serialized as objects, not JavaScript arrays.
      // Normalize list fields before array operations and template rendering.
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
      if (data.active) view.shiftHistoryOpen = false;
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
      const wasRemotelyConnected = Number(view.state.lan && view.state.lan.connected || 0) > 0;
      const isRemotelyConnected = Number(data.lan.connected || 0) > 0;
      if (!wasRemotelyConnected && isRemotelyConnected) {
        view.localPhoneOpen = false;
        view.collapseAttention = false;
        dismissPassengerChat();
      } else if (wasRemotelyConnected && !isRemotelyConnected) {
        view.localPhoneOpen = true;
      }
      view.state = Object.assign({}, view.state, data);
      scheduleLanQr();
      syncFuelStation(view.state.fuelStation, view.state.repairStation);
      if (passengerMoodChanged) {
        const moodDirection = data.passengerMoodChangeDirection === "up" ? "up" : "down";
        const moodVariant = Number(data.passengerMoodChangeId || 0) % 2 ? "a" : "b";
        view.passengerMoodFlash = `${moodDirection}-${moodVariant}`;
        if (passengerMoodFlashTimer) clearTimeout(passengerMoodFlashTimer);
        passengerMoodFlashTimer = setTimeout(() => scheduleUi(() => {
          view.passengerMoodFlash = "";
          passengerMoodFlashTimer = null;
        }), 950);
      }
      if (refuelingJustCompleted) {
        view.fuelStationOpen = false;
        view.refuel.amount = 0;
        bngApi.engineLua(
          'if taxiDriver_taxiDriver then taxiDriver_taxiDriver.completeFuelStop() end'
        );
      }
      syncPassengerChat();
      hudStateReceived = true;
      syncExternalView();
      if (externalPhoneMode) {
        if (previousMapPhase !== data.phase ||
            Math.abs(previousMapSpeed - Number(data.currentSpeed || 0)) >= 0.5) {
          scheduleMinimapUpdate();
        }
      } else if (canRenderMinimap(view.state)) scheduleMinimapUpdate();
      else hideMinimap(minimapVisible);
    });
    // BeamNG 0.39 stopped delivering the guihooks.trigger("TaxiDriverExternal...")
    // pushes lanBridge.lua used to send this data (no error either side - the
    // events just never arrive), so the external client polls for it instead,
    // over the same bngApi.engineLua channel used for view/heartbeat calls.
    const getExternalPollInterval = () => {
      const quality = view.settings.externalMapQuality;
      return quality === "eco" ? 500 : (quality === "smooth" ? 125 : 250);
    };
    const scheduleExternalPoll = () => {
      if (uiShuttingDown || externalPollTimer) return;
      externalPollTimer = setTimeout(() => {
        externalPollTimer = 0;
        pollExternalState();
      }, getExternalPollInterval());
    };
    const pollExternalState = () => {
      if (uiShuttingDown || !externalPhoneMode) return;
      if (externalPollInFlight || !externalMapVisible()) {
        scheduleExternalPoll();
        return;
      }
      externalPollInFlight = true;
      const generation = ++externalPollGeneration;
      // A disconnected bridge can lose a callback. Retry without letting a
      // delayed reply from that request overwrite the current map state.
      const replyTimeout = setTimeout(() => {
        if (uiShuttingDown || generation !== externalPollGeneration) return;
        externalPollGeneration += 1;
        externalPollInFlight = false;
        scheduleExternalPoll();
      }, 5000);
      bngApi.engineLua(
        `taxiDriver_taxiDriver and taxiDriver_taxiDriver.pollExternalState(${externalRoadRevision}, ${Number(externalMapData.revision) || 0})`,
        (data) => {
          if (destroyed || uiShuttingDown || generation !== externalPollGeneration) return;
          clearTimeout(replyTimeout);
          externalPollInFlight = false;
          if (data && data.available !== false) {
            if (data.vehicle) {
              const previous = externalVehicleState;
              externalVehicleState = data.vehicle;
              const previousPosition = previous && previous.position || [];
              const position = data.vehicle.position || [];
              const previousDirection = previous && previous.direction || [];
              const direction = data.vehicle.direction || [];
              const moved = Math.hypot(
                Number(position[0] || 0) - Number(previousPosition[0] || 0),
                Number(position[1] || 0) - Number(previousPosition[1] || 0)
              ) > 0.05;
              const turned = Math.hypot(
                Number(direction[0] || 0) - Number(previousDirection[0] || 0),
                Number(direction[1] || 0) - Number(previousDirection[1] || 0)
              ) > 0.001;
              if (!previous || moved || turned) scheduleExternalMapDraw();
            }
            if (Array.isArray(data.roads)) {
              externalRoadRevision = Number(data.roadRevision || 0);
              if (Array.isArray(data.terrainTiles)) setExternalTerrainTiles(data.terrainTiles);
              addExternalRoads(data.roads, true);
              scheduleExternalMapDraw();
            }
            if (data.map) {
              externalMapData = {
                revision: Number(data.mapRevision || 0),
                route: Array.isArray(data.map.route) ? data.map.route : [],
                roads: [],
              };
              scheduleExternalMapDraw();
            }
          }
          scheduleExternalPoll();
        }
      );
    };
    onGameEvent("TaxiDriverProfileData", (data) => {
      if (!data) return;
      if (Array.isArray(data.avatarOptions) && data.avatarOptions.length) {
        view.avatarOptions = data.avatarOptions;
      }
      const profile = normalizeProfile(data.profile);
      const progress = data.progress && typeof data.progress === "object" ? data.progress : {};
      const vehicles = Array.isArray(data.vehicles) ? data.vehicles : [];
      progress.reviews = Array.isArray(progress.reviews) ? progress.reviews : [];
      progress.ratingHistory = Array.isArray(progress.ratingHistory) ? progress.ratingHistory : [];
      progress.balanceHistory = Array.isArray(progress.balanceHistory) ? progress.balanceHistory : [];
      progress.aiRideHistory = Array.isArray(progress.aiRideHistory) ? progress.aiRideHistory : [];
      view.driverProfile = profile;
      view.profileDraft = Object.assign({}, profile);
      view.profileProgress = Object.assign({
        balance: 0, rating: 5, completedRides: 0, aiRideCount: 0,
        reviews: [], ratingHistory: [], balanceHistory: [], aiRideHistory: [],
      }, progress);
      view.profileReviews = progress.reviews.slice().reverse().map((review) => Object.assign({}, review, {
        penalties: Array.isArray(review && review.penalties) ? review.penalties : [],
        randomEvents: Array.isArray(review && review.randomEvents) ? review.randomEvents : [],
      }));
      if (!view.profileReviews.some((review) => review.id === view.expandedReviewId)) {
        view.expandedReviewId = null;
      }
      view.profileVehicles = vehicles.map((vehicle) => ({
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
      view.reviewPage = Math.min(view.reviewPage, view.getReviewPageCount());
      scheduleReviewPagination();
    });
    onGameEvent("TaxiDriverMinimapInvalidated", () => {
      lastMinimapRect = "";
      minimapVisible = false;
      if (uiVisible) scheduleMinimapUpdate();
    });
    onGameEvent("TaxiDriverUiSuspended", (data) => {
      if (externalPhoneMode) return;
      const suspended = !!(data && data.suspended === true);
      if (view.vehicleConfigSuspended === suspended) return;
      view.vehicleConfigSuspended = suspended;
      lastMinimapRect = "";
      if (suspended) hideMinimap(true);
      else if (uiVisible) scheduleMinimapUpdate();
    });
    const syncNativeVisibility = () => {
      if (externalPhoneMode) return;
      uiVisible = cefVisible && appsVisible && routeAppsVisible && drivingRoute;
      view.nativeUiSuspended = !uiVisible;
      bngApi.engineLua(
        `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapAppVisibility(${uiVisible ? "true" : "false"}) end`
      );
      if (uiVisible) {
        refreshGameUiVolume();
        scheduleMinimapUpdate();
      }
      else hideMinimap();
    };
    onGameEvent("onCefVisibilityChanged", (visible) => {
      cefVisible = visible !== false;
      syncNativeVisibility();
    });
    onGameEvent("ShowApps", (shown) => {
      appsVisible = shown !== false;
      syncNativeVisibility();
    });
    onGameEvent("UiAppsRouteUpdate", (data) => {
      if (!data || typeof data.shown !== "boolean") return;
      routeAppsVisible = data.shown;
      syncNativeVisibility();
    });
    // BeamNG 0.39 routes use `play` for driving; other routes own input
    // and may still retain the current apps layout underneath their page.
    onGameEvent("ui_router_afterRouteChange", (data) => {
      const name = data && data.request && data.request.name;
      if (typeof name !== "string") return;
      nativeRouteVersion += 1;
      drivingRoute = name === "play";
      syncNativeVisibility();
    });
    onGameEvent("SettingsChanged", (data) => {
      const value = data && data.values ? data.values.AudioUiVol : undefined;
      if (value === undefined) refreshGameUiVolume();
      else setGameUiVolume(value);
    });

    updateClock();
    refreshGameUiVolume();
    if (!externalPhoneMode) {
      syncNativeVisibility();
      bngApi.engineLua(
        "if taxiDriver_taxiDriver and taxiDriver_taxiDriver.resetMinimapView then taxiDriver_taxiDriver.resetMinimapView() end"
      );
    }
    const clockTimer = setInterval(() => scheduleUi(updateClock), 30000);
    const nextOfferCountdownTimer = setInterval(() => {
      if (!trackedNextOfferId || trackedNextOfferDeadline <= 0) return;
      scheduleUi(() => {
        if (!trackedNextOfferId || trackedNextOfferDeadline <= 0) return;
        view.nextOfferUiRemaining = Math.max(0,
          (trackedNextOfferDeadline - Date.now()) / 1000);
        if (view.nextOfferUiRemaining <= 0) expireNextOfferLocally(trackedNextOfferId);
      });
    }, 100);
    const minimapTimer = externalPhoneMode ? null : setInterval(updateMinimap, 500);
    const resizeMap = () => {
      scheduleMinimapUpdate();
      scheduleReviewPagination();
    };
    listen(window, "resize", resizeMap);
    let externalHeartbeatTimer = null;
    let nativeHudHeartbeatTimer = null;
    let sendNativeHudHeartbeat = null;
    let uiShuttingDown = false;
    i18nPromise.then(data => {
      if (uiShuttingDown) return;
      scheduleUi(() => { if (!uiShuttingDown) Object.assign(i18n, data); });
    });
    if (!externalPhoneMode) {
      const requestedRouteVersion = nativeRouteVersion;
      bngApi.engineLua(
        "(function() if ui_router and ui_router.getCurrent then local route = ui_router.getCurrent(); return route and route.request and route.request.name end end)()",
        name => scheduleUi(() => {
          if (uiShuttingDown || requestedRouteVersion !== nativeRouteVersion) return;
          // Older game versions do not expose the new route service.
          drivingRoute = typeof name !== "string" || name === "play";
          syncNativeVisibility();
        })
      );
    }
    const clearHudHeartbeatTimers = () => {
      if (externalHeartbeatTimer) clearInterval(externalHeartbeatTimer);
      if (nativeHudHeartbeatTimer) clearInterval(nativeHudHeartbeatTimer);
      if (externalPollTimer) clearTimeout(externalPollTimer);
      externalHeartbeatTimer = null;
      nativeHudHeartbeatTimer = null;
      externalPollTimer = 0;
    };
    const stopHudHeartbeats = () => {
      if (uiShuttingDown) return;
      uiShuttingDown = true;
      clearHudHeartbeatTimers();
    };
    const handleHeartbeatPageHide = (event) => {
      if (!event || event.persisted !== true) stopHudHeartbeats();
    };
    listen(window, "pagehide", handleHeartbeatPageHide);
    listen(window, "beforeunload", stopHudHeartbeats);
    const suspendNativeHudHeartbeat = () => {
      if (nativeHudHeartbeatTimer) clearInterval(nativeHudHeartbeatTimer);
      nativeHudHeartbeatTimer = null;
    };
    const resumeNativeHudHeartbeat = () => {
      if (externalPhoneMode || uiShuttingDown || nativeHudHeartbeatTimer || !sendNativeHudHeartbeat) return;
      sendNativeHudHeartbeat();
      nativeHudHeartbeatTimer = setInterval(sendNativeHudHeartbeat, 2500);
    };
    const handleNativeHeartbeatVisibility = () => {
      if (document.visibilityState === "hidden") suspendNativeHudHeartbeat();
      else resumeNativeHudHeartbeat();
    };
    const stopExternalMapWork = () => {
      if (externalMapFrame) cancelFrame(externalMapFrame);
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
      ? watchFields([
          "settingsOpen", "profileOpen", "fuelStationOpen", "offlineConfirmOpen", "earthOpen",
          "fleetOpen", "phoneMinimized", "state.phase", "state.active", "settings.externalMapEnabled",
        ], syncExternalView)
      : null;
    if (externalPhoneMode) {
      sendExternalHeartbeat = () => {
        if (uiShuttingDown) return;
        const view = getExternalView();
        const visible = view !== "hidden";
        bngApi.engineLua(
          `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.externalPhoneHeartbeat("${externalSessionToken}", "${view}", ${visible ? "true" : "false"}, "${hudEpoch}", ${hudRevision}) end`
        );
      };
      sendExternalHeartbeat();
      externalHeartbeatTimer = setInterval(sendExternalHeartbeat, 2500);
      listen(document, "visibilitychange", handleExternalDocumentVisibility);
      bngApi.engineLua(
        "if taxiDriver_taxiDriver then taxiDriver_taxiDriver.requestExternalHudState() end"
      );
      syncExternalView();
      scheduleExternalPoll();
    } else {
      sendNativeHudHeartbeat = () => {
        if (uiShuttingDown || document.visibilityState === "hidden") return;
        bngApi.engineLua(
          `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.hudClientHeartbeat("${hudEpoch}", ${hudRevision}) end`
        );
      };
      resumeNativeHudHeartbeat();
      listen(document, "visibilitychange", handleNativeHeartbeatVisibility);
      listen(window, "blur", suspendNativeHudHeartbeat);
      listen(window, "focus", resumeNativeHudHeartbeat);
    }
    onDestroy(() => {
      stopHudHeartbeats();
      stopMapDrag({});
      host.removeEventListener("pointerdown", startMapDrag);
      window.removeEventListener("pointermove", moveMapDrag);
      window.removeEventListener("pointerup", stopMapDrag);
      window.removeEventListener("pointercancel", stopMapDrag);
      window.removeEventListener("blur", stopMapDrag);
      if (settingsSaveTimer) persistSettingsNow();
      clearInterval(clockTimer);
      clearInterval(nextOfferCountdownTimer);
      if (minimapTimer) clearInterval(minimapTimer);
      window.removeEventListener("pagehide", handleHeartbeatPageHide);
      window.removeEventListener("beforeunload", stopHudHeartbeats);
      document.removeEventListener("visibilitychange", handleNativeHeartbeatVisibility);
      window.removeEventListener("blur", suspendNativeHudHeartbeat);
      window.removeEventListener("focus", resumeNativeHudHeartbeat);
      stopExternalMapWork();
      if (stopExternalViewWatch) stopExternalViewWatch();
      if (phoneToastTimer) clearTimeout(phoneToastTimer);
      if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
      if (passengerMoodFlashTimer) clearTimeout(passengerMoodFlashTimer);
      stopOfflineHold();
      stopPassengerChat();
      appRoot.removeEventListener("click", handleAppClick, true);
      appRoot.removeEventListener("pointerdown", handleOfflineHoldStart, true);
      appRoot.removeEventListener("pointerup", handleOfflineHoldEnd, true);
      appRoot.removeEventListener("pointercancel", handleOfflineHoldEnd, true);
      appRoot.removeEventListener("touchstart", handleOfflineHoldStart, true);
      appRoot.removeEventListener("touchend", handleOfflineHoldEnd, true);
      appRoot.removeEventListener("touchcancel", handleOfflineHoldEnd, true);
      appRoot.removeEventListener("keydown", handleOfflineHoldKeydown, true);
      appRoot.removeEventListener("keyup", handleOfflineHoldKeyup, true);
      window.removeEventListener("pointerup", handleOfflineHoldEnd, true);
      window.removeEventListener("pointercancel", handleOfflineHoldEnd, true);
      window.removeEventListener("touchend", handleOfflineHoldEnd, true);
      window.removeEventListener("touchcancel", handleOfflineHoldEnd, true);
      window.removeEventListener("blur", handleOfflineHoldEnd);
      window.removeEventListener("keyup", handleOfflineHoldKeyup, true);
      document.removeEventListener("visibilitychange", handleOfflineHoldVisibility);
      appRoot.removeEventListener("keydown", handleDialogKeydown, true);
      if (dialogFocusTimer) clearTimeout(dialogFocusTimer);
      stopDialogWatch();
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
      if (reviewPaginationFrame) cancelFrame(reviewPaginationFrame);
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
    callTaxiDriver("requestEarthState");
    scheduleMinimapUpdate();

    return { view, hud, destroy };
  } catch (error) {
    destroy();
    throw error;
  }
}
