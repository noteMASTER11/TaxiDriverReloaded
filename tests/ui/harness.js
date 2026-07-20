(() => {
  "use strict";
  const params = new URLSearchParams(window.location.search);
  const scenarioName = params.get("scenario") || "home";
  const width = Math.max(240, Number(params.get("width")) || 520);
  const height = Math.max(320, Number(params.get("height")) || 900);
  document.documentElement.style.setProperty("--test-width", `${width}px`);
  document.documentElement.style.setProperty("--test-height", `${height}px`);

  const state = window.__taxiScenarios[scenarioName] || window.__taxiScenarios.home;
  const externalMode = params.get("external") === "1";
  const requestedLocale = params.get("locale");
  const uiScaleParam = params.get("uiScale");
  const requestedUiScale = uiScaleParam === null ? NaN : Number(uiScaleParam);
  if (requestedLocale) state.settings.language = requestedLocale;
  if (Number.isFinite(requestedUiScale)) {
    state.settings.uiScalePercent = Math.max(80, Math.min(180, Math.round(requestedUiScale / 10) * 10));
  }
  if (params.get("realistic") !== null) state.settings.realisticMode = params.get("realistic") === "1";
  if (params.get("events") !== null) state.settings.randomEventsEnabled = params.get("events") === "1";
  if (params.get("unlimitedRoutes") !== null) state.settings.unlimitedRouteDistance = params.get("unlimitedRoutes") === "1";
  if (params.get("extreme") === "1") {
    state.passengerName = "Alexandria-Cassandra Montgomery-Wellington";
    state.balance = 9876543.21;
    state.adjustedFare = 123456.78;
    state.estimatedFare = 130000.45;
    state.speedLimit = 130;
    state.distanceToTarget = 98765;
    state.driverProfile = { fullName: "Alexandria-Cassandra Montgomery-Wellington", avatar: "🙂" };
    (state.offers || []).forEach((item, index) => {
      if (!item.isDelivery) item.passengerName = `Alexandria-Cassandra Montgomery-Wellington ${index + 1}`;
      item.estimatedFare = 123456.78 + index;
    });
  }
  angular.bootstrap(document, ["beamng.apps"]);
  const rootScope = angular.element(document).injector().get("$rootScope");
  const emit = () => rootScope.$broadcast("TaxiDriverHUDState", angular.copy(state));
  window.__emitTaxiState = emit;
  window.__taxiSetState = (patch) => {
    Object.assign(state, patch || {});
    emit();
  };
  window.addEventListener("taxi-test-cheat-rating", (event) => {
    state.rating = Number(event.detail);
    setTimeout(emit, 0);
  });
  emit();

  setTimeout(() => {
    const appElement = document.querySelector("taxi-driver-hud");
    const scope = angular.element(appElement).scope();
    scope.$apply(() => {
      if (scenarioName === "settings") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: true, gameplay: true, aiDriver: true, navigation: true, audio: true, connectivity: true, cheats: true };
      }
      if (scenarioName === "settingsAi") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, aiDriver: true, navigation: false, audio: false, connectivity: false, cheats: false };
      }
      if (scenarioName === "settingsConnection") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, aiDriver: false, navigation: false, audio: false, connectivity: true, cheats: false };
      }
      if (scenarioName === "profile") {
        scope.profileOpen = true;
        scope.profileTab = "reviews";
      }
      if (scenarioName === "profileVehicles") {
        scope.profileOpen = true;
        scope.profileTab = "vehicles";
      }
      if (scenarioName === "profileShifts") {
        scope.profileOpen = true;
        scope.profileTab = "shifts";
      }
      if (scenarioName === "compact") scope.phoneMinimized = true;
      if (scenarioName === "fuel" || scenarioName === "magicFuel") scope.fuelStationOpen = true;
      if (scenarioName === "shiftHistory") scope.shiftHistoryOpen = true;
    });
    rootScope.$broadcast("TaxiDriverProfileData", {
      profile: { fullName: "Alex Morgan", birthDate: "1991-05-17", avatar: "🙂" },
      progress: {
        balance: 75.15, rating: 4.37, completedRides: 18, aiRideCount: 7,
        reviews: Array.from({ length: 12 }, (_, index) => ({ id: index + 1, passengerName: `Passenger ${index + 1}`, emoji: index % 3 ? "😊" : "🤩", quality: 82 + index, timestamp: 1760000000 + index * 80000, rating: 4.3, orderRating: 3.8 + (index % 4) * 0.3, usedAutopilot: index % 2 === 0 })),
        ratingHistory: [], balanceHistory: [], aiRideHistory: [{index: 1, value: 0}, {index: 6, value: 2}, {index: 12, value: 5}, {index: 18, value: 7}],
      },
      vehicles: [
        { key: "etk800|854t", name: "ETK 854t", preview: window.__taxiScenarios.home.currentVehicle.preview, distanceMeters: 12843.7, completedRides: 7, aiRides: 4, income: 184.25, passengerRides: 5, deliveryRides: 2, averageIncome: 26.32, averageRating: 4.72, penaltyLoss: 8.4, cargoDamageLoss: 2.1, fuelConsumed: 18.2, fuelCost: 16.9, rideDistanceMeters: 76500, profitPerKm: 2.41, lastSeen: 1784150000 },
        { key: "pickup|d35", name: "Gavril D35 V8 4WD", distanceMeters: 89431.2, completedRides: 24, income: 725.80, passengerRides: 14, deliveryRides: 10, averageIncome: 30.24, averageRating: 4.51, penaltyLoss: 34.2, cargoDamageLoss: 18.3, fuelConsumed: 92.5, fuelCost: 83.4, rideDistanceMeters: 318000, profitPerKm: 2.28, lastSeen: 1784100000 },
        { key: "covet|dx", name: "Ibishu Covet 1.5 DXi", distanceMeters: 2134.9, completedRides: 2, income: 41.55, passengerRides: 2, deliveryRides: 0, averageIncome: 20.78, averageRating: 4.91, penaltyLoss: 0, cargoDamageLoss: 0, fuelConsumed: 4.2, fuelCost: 3.9, rideDistanceMeters: 18200, profitPerKm: 2.28, lastSeen: 1784000000 },
      ],
      avatarOptions: ["🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔"],
    });
    if (externalMode) {
      rootScope.$broadcast("TaxiDriverExternalMapData", {
        revision: 1,
        route: [[0, 120], [0, 40], [0, -40], [45, -130]],
      });
      rootScope.$broadcast("TaxiDriverExternalRoadData", {
        revision: 1, chunkIndex: 1, chunkCount: 2, totalRoads: 6,
        reset: true, complete: false,
        roads: [
          [-180, 0, 180, 0, 8, 1], [0, -220, 0, 220, 8, 1],
          [-150, -130, 150, 130, 6, 1], [-160, 140, 160, -140, 5, 0.8],
        ],
      });
      rootScope.$broadcast("TaxiDriverExternalRoadData", {
        revision: 1, chunkIndex: 2, chunkCount: 2, totalRoads: 6,
        reset: false, complete: true,
        roads: [
          [-180, 90, 180, 90, 5, 1], [-180, -90, 180, -90, 5, 1],
        ],
      });
      rootScope.$broadcast("TaxiDriverExternalVehicleState", {
        position: [0, 0], direction: [0, 1],
      });
    }
    window.__taxiHarnessReady = true;
  }, 60);

  window.__taxiVisualAudit = () => {
    const stage = document.querySelector(".taxi-test-stage");
    const phone = document.querySelector(".taxi-phone");
    const compact = document.querySelector(".taxi-compact");
    const screen = document.querySelector(".taxi-phone__screen");
    const settingsPanel = document.querySelector(".taxi-settings");
    const qr = document.querySelector(".taxi-lan__qr");
    const stageRect = stage.getBoundingClientRect();
    const scaleStage = document.querySelector(".taxi-shell__scale-stage");
    const uiScale = scaleStage ? Math.max(0.8, Math.min(1.8,
      Number.parseFloat(getComputedStyle(scaleStage).zoom) || 1)) : 1;
    const failures = [];
    const within = (outer, inner, tolerance = 1) => inner.left >= outer.left - tolerance &&
      inner.right <= outer.right + tolerance && inner.top >= outer.top - tolerance &&
      inner.bottom <= outer.bottom + tolerance;
    if (phone && !within(stageRect, phone.getBoundingClientRect(), 2)) failures.push("phone-outside-stage");
    if (compact && !within(stageRect, compact.getBoundingClientRect(), 2)) failures.push("compact-outside-stage");
    if (document.documentElement.scrollWidth > window.innerWidth + 1) failures.push("document-horizontal-overflow");
    const title = document.querySelector(".taxi-appbar__title");
    if (title && title.getBoundingClientRect().width > 0 &&
        title.getBoundingClientRect().width < 48 * uiScale) failures.push("appbar-title-collapsed");
    const appbar = document.querySelector(".taxi-appbar");
    if (appbar) {
      const appbarRect = appbar.getBoundingClientRect();
      const children = Array.from(appbar.children).filter((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      });
      for (let index = 1; index < children.length; index += 1) {
        const previous = children[index - 1].getBoundingClientRect();
        const current = children[index].getBoundingClientRect();
        if (current.left < previous.right - 1) failures.push("appbar-items-overlap");
      }
      const contentPanels = Array.from(document.querySelectorAll(
        ".taxi-settings, .taxi-profile, .taxi-home, .taxi-orders, .taxi-transfer, " +
        ".taxi-fuel-route, .taxi-trip-layout, .taxi-fuel"
      )).filter((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      });
      contentPanels.forEach((panel) => {
        if (panel.getBoundingClientRect().top < appbarRect.bottom - 1) {
          failures.push(`content-under-appbar:${panel.className}`);
        }
      });
    }
    const compactMetrics = Array.from(document.querySelectorAll(".taxi-compact__metric"));
    if (compactMetrics.some((element) => element.scrollWidth > element.clientWidth + 1 || element.scrollHeight > element.clientHeight + 1)) {
      failures.push("compact-metric-clipped");
    }
    const rideFooter = document.querySelector(".taxi-ride-footer");
    if (rideFooter && screen && !within(screen.getBoundingClientRect(), rideFooter.getBoundingClientRect(), 2)) {
      failures.push("sticky-footer-outside-screen");
    }
    if (externalMode) {
      const controls = Array.from(document.querySelectorAll(".taxi-appbar button, .taxi-order-card__accept, .taxi-fuel__buy"));
      if (controls.some((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && rect.height < 40 * uiScale;
      })) failures.push("web-touch-target-too-small");
    } else {
      let smallTextValue = "";
      const smallText = Array.from(document.querySelectorAll(".taxi-phone *")).find((element) => {
        const rect = element.getBoundingClientRect();
        if (rect.width < 1 || rect.height < 1) return false;
        const ownText = Array.from(element.childNodes)
          .filter((node) => node.nodeType === Node.TEXT_NODE)
          .map((node) => node.textContent.trim())
          .join(" ");
        if (!/[0-9A-Za-zА-Яа-яЁёÀ-ÿ]/.test(ownText)) return false;
        const fontSize = Number.parseFloat(getComputedStyle(element).fontSize);
        if (fontSize > 0 && fontSize < 14) smallTextValue = ownText.slice(0, 28);
        return fontSize > 0 && fontSize < 14;
      });
      if (smallText) failures.push(`native-text-under-14:${smallText.className || smallText.tagName}:${smallTextValue}`);
    }
    const canvas = document.querySelector("canvas.taxi-external-minimap");
    if (canvas && window.devicePixelRatio > 1) {
      const rect = canvas.getBoundingClientRect();
      const expectedRatio = Math.min(2, window.devicePixelRatio);
      if (canvas.width + 1 < rect.width * expectedRatio || canvas.height + 1 < rect.height * expectedRatio) {
        failures.push("hidpi-canvas-underresolved");
      }
    }
    if (settingsPanel && screen) {
      const settingsRect = settingsPanel.getBoundingClientRect();
      const screenRect = screen.getBoundingClientRect();
      if (Math.abs(settingsRect.bottom - screenRect.bottom) > 2) failures.push("settings-does-not-fill-screen");
      if (settingsPanel.clientHeight < screen.clientHeight * 0.55) failures.push("settings-viewport-too-short");
    }
    if (qr) {
      const qrRect = qr.getBoundingClientRect();
      const card = qr.closest(".taxi-lan").getBoundingClientRect();
      if (!within(card, qrRect, 1)) failures.push("qr-outside-card");
      if (qrRect.width < 96 || qrRect.height < 96) failures.push("qr-too-small");
    }
    return {
      scenario: scenarioName, width, height, failures,
      settings: settingsPanel ? { clientHeight: settingsPanel.clientHeight, scrollHeight: settingsPanel.scrollHeight } : null,
    };
  };
})();
