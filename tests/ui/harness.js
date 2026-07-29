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
  const extremeMode = params.get("extreme") === "1";
  const motionEnabled = params.get("motion") === "1";
  const uiScaleParam = params.get("uiScale");
  const requestedUiScale = uiScaleParam === null ? NaN : Number(uiScaleParam);
  if (!motionEnabled) document.querySelector(".taxi-test-stage").classList.add("taxi-test-stage--motion-off");
  if (requestedLocale) state.settings.language = requestedLocale;
  if (Number.isFinite(requestedUiScale)) {
    state.settings.uiScalePercent = Math.max(80, Math.min(180, Math.round(requestedUiScale / 10) * 10));
  }
  if (params.get("realistic") !== null) state.settings.realisticMode = params.get("realistic") === "1";
  if (params.get("events") !== null) state.settings.randomEventsEnabled = params.get("events") === "1";
  if (params.get("unlimitedRoutes") !== null) state.settings.unlimitedRouteDistance = params.get("unlimitedRoutes") === "1";
  if (extremeMode) {
    state.passengerName = "Alexandria-Cassandra Montgomery-Wellington";
    state.balance = 9876543.21;
    state.completedRides = 987654;
    state.ratingCount = 987654;
    state.adjustedFare = 123456.78;
    state.estimatedFare = 130000.45;
    state.speedLimit = 130;
    state.distanceToTarget = 98765000;
    state.etaMinutes = 1234;
    state.ratingBonusPercent = 999.9;
    state.ratingBonusAmount = 123456.78;
    state.penaltyPercent = 999.9;
    state.driverProfile = { fullName: "Alexandria-Cassandra Montgomery-Wellington", avatar: "🙂" };
    state.currentVehicle.name = "Gavril Grand Marshal Luxe Touring Taxi Special Edition";
    state.currentVehicle.distanceMeters = 987654321.9;
    state.currentVehicle.completedRides = 987654;
    state.currentVehicle.income = 9876543.21;
    state.vehicleEnergy.quantity = 9999.99;
    state.vehicleEnergy.maxQuantity = 10000;
    state.vehicleEnergy.estimatedRangeKm = 999999;
    state.shift.last = { rides: 987654, netIncome: 9876543.21, averageRating: 4.99 };
    const savedShiftTemplate = state.shiftHistory.items[0];
    state.shiftHistory.items = Array.from({ length: 193 }, (_, index) => Object.assign({}, savedShiftTemplate, {
      id: index + 1,
      vehicleName: `Gavril Grand Marshal Luxe Touring Taxi Special Edition ${index + 1}`,
      rides: 987654 + index,
      aiRides: 193 + index,
      netIncome: 9876543.21 + index,
    }));
    state.fleet.activeDrivers = 193;
    state.fleet.maxDrivers = 999;
    state.fleet.stats = {
      rides: 987654, passengerRides: 654321, deliveryRides: 333333,
      grossRevenue: 9876543.21, ownerRevenue: 3456789.12,
      hiringFees: 1234567.89, wages: 2345678.9, netProfit: -9876543.21,
    };
    state.fleet.drivers.forEach((driver, index) => {
      driver.name = `Gavril Grand Marshal Luxe Touring Taxi Special Edition ${index + 1}`;
      driver.remainingMeters = 98765000 + index;
      driver.stats = { rides: 987654 + index, ownerRevenue: 1234567.89 + index };
    });
    (state.offers || []).forEach((item, index) => {
      if (!item.isDelivery) item.passengerName = `Alexandria-Cassandra Montgomery-Wellington ${index + 1}`;
      item.estimatedFare = 123456.78 + index;
      item.etaMinutes = 1234 + index;
      item.rideDistance = 98765000 + index;
      item.pickupWaitSeconds = 98765 + index;
      item.ratingBonusPercent = 999.9;
      item.ratingBonusAmount = 123456.78 + index;
      if (item.isDelivery) item.cargoWeightKg = 987654 + index;
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
        scope.settingsSections = externalMode
          ? { general: true, gameplay: false, randomEvents: false, aiDriver: false, fleet: false, navigation: false, audio: false, connectivity: false, cheats: false }
          : { general: true, gameplay: true, randomEvents: true, aiDriver: true, fleet: true, navigation: true, audio: true, connectivity: true, cheats: true };
      }
      if (scenarioName === "settingsAi") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, aiDriver: true, navigation: false, audio: false, connectivity: false, cheats: false };
      }
      if (scenarioName === "settingsFleet") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, randomEvents: false, aiDriver: false, fleet: true, navigation: false, audio: false, connectivity: false, cheats: false };
      }
      if (scenarioName === "settingsEvents") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, randomEvents: true, aiDriver: false, fleet: false, navigation: false, audio: false, connectivity: false, cheats: false };
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
      if (scenarioName === "fleet" || scenarioName === "fleetTrip") scope.fleetOpen = true;
    });
    rootScope.$broadcast("TaxiDriverProfileData", {
      profile: { fullName: extremeMode ? "Alexandria-Cassandra Montgomery-Wellington" : "Alex Morgan", birthDate: "1991-05-17", avatar: "🙂" },
      progress: {
        balance: extremeMode ? 9876543.21 : 75.15,
        rating: 4.37,
        completedRides: extremeMode ? 987654 : 18,
        aiRideCount: extremeMode ? 987654 : 7,
        reviews: Array.from({ length: 12 }, (_, index) => ({
          id: index + 1, passengerName: `Passenger ${index + 1}`,
          emoji: index % 3 ? "😊" : "🤩", quality: 82 + index,
          timestamp: 1760000000 + index * 80000, rating: 4.3,
          orderRating: 3.8 + (index % 4) * 0.3, usedAutopilot: index % 2 === 0,
          penalties: index === 11 ? [
            {kind: "speeding", detail: "18 km/h above the limit · 6.2 s", penalty: 0.025},
            {kind: "collision", detail: "Minor impact", penalty: 0.04},
          ] : [],
          randomEvents: index === 11 ? [
            {kind: "vipQuietRide", status: "conditionsFailed", amount: 0},
          ] : [],
        })),
        ratingHistory: [], balanceHistory: [], aiRideHistory: [{index: 1, value: 0}, {index: 6, value: 2}, {index: 12, value: 5}, {index: 18, value: 7}],
      },
      vehicles: [
        { key: "etk800|854t", name: "ETK 854t", preview: window.__taxiScenarios.home.currentVehicle.preview, distanceMeters: 12843.7, completedRides: 7, aiRides: 4, income: 184.25, passengerRides: 5, deliveryRides: 2, averageIncome: 26.32, averageRating: 4.72, penaltyLoss: 8.4, cargoDamageLoss: 2.1, fuelConsumed: 18.2, fuelCost: 16.9, rideDistanceMeters: 76500, profitPerKm: 2.41, lastSeen: 1784150000 },
        { key: "pickup|d35", name: "Gavril D35 V8 4WD", distanceMeters: 89431.2, completedRides: 24, income: 725.80, passengerRides: 14, deliveryRides: 10, averageIncome: 30.24, averageRating: 4.51, penaltyLoss: 34.2, cargoDamageLoss: 18.3, fuelConsumed: 92.5, fuelCost: 83.4, rideDistanceMeters: 318000, profitPerKm: 2.28, lastSeen: 1784100000 },
        { key: "covet|dx", name: "Ibishu Covet 1.5 DXi", distanceMeters: 2134.9, completedRides: 2, income: 41.55, passengerRides: 2, deliveryRides: 0, averageIncome: 20.78, averageRating: 4.91, penaltyLoss: 0, cargoDamageLoss: 0, fuelConsumed: 4.2, fuelCost: 3.9, rideDistanceMeters: 18200, profitPerKm: 2.28, lastSeen: 1784000000 },
      ],
      avatarOptions: ["🙂", "😊", "😎", "🤓", "🧑", "👨", "👩", "🧔"],
    });
    if (scenarioName === "settingsConnection") {
      requestAnimationFrame(() => {
        const target = document.querySelector(".taxi-lan__qr-code");
        if (target && !target.children.length && typeof window.QRCode === "function") {
          new window.QRCode(target, {
            text: String(scope.state.lan && scope.state.lan.url || "TaxiDriver"),
            width: 140,
            height: 140,
            correctLevel: window.QRCode.CorrectLevel.M,
          });
        }
      });
    }
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
    const uiScalePercent = Number.isFinite(requestedUiScale)
      ? Math.max(80, Math.min(180, Math.round(requestedUiScale / 10) * 10))
      : 100;
    const failures = [];
    const within = (outer, inner, tolerance = 1) => inner.left >= outer.left - tolerance &&
      inner.right <= outer.right + tolerance && inner.top >= outer.top - tolerance &&
      inner.bottom <= outer.bottom + tolerance;
    if (phone && !within(stageRect, phone.getBoundingClientRect(), 2)) failures.push("phone-outside-stage");
    if (compact && !within(stageRect, compact.getBoundingClientRect(), 2)) {
      const rect = compact.getBoundingClientRect();
      failures.push(`compact-outside-stage:${Math.round(rect.left)},${Math.round(rect.top)},${Math.round(rect.right)},${Math.round(rect.bottom)}`);
    }
    if (document.documentElement.scrollWidth > window.innerWidth + 1) failures.push("document-horizontal-overflow");
    if (scaleStage) {
      const zoom = Number.parseFloat(getComputedStyle(scaleStage).zoom) || 1;
      if (Math.abs(zoom - 1) > 0.001 || scaleStage.style.zoom) failures.push(`scale-stage-uses-zoom:${zoom}`);
      const expectedTier = uiScalePercent >= 160 ? "accessibility"
        : (uiScalePercent >= 140 ? "large" : (uiScalePercent >= 110 ? "reduced" : "regular"));
      if (!scaleStage.classList.contains(`taxi-ui-scale--${uiScalePercent}`)) {
        failures.push(`scale-stage-missing-exact-class:${uiScalePercent}`);
      }
      if (!scaleStage.classList.contains(`taxi-ui-tier--${expectedTier}`)) {
        failures.push(`scale-stage-missing-tier-class:${expectedTier}`);
      }
    }
    const title = document.querySelector(".taxi-appbar__title");
    if (title && title.getBoundingClientRect().width > 0 &&
        title.getBoundingClientRect().width < 48) failures.push("appbar-title-collapsed");
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
    const visible = (element) => {
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };
    const numericValues = Array.from(document.querySelectorAll(
      ".taxi-count-badge, .taxi-home__stats b, .taxi-home__last-shift b, " +
      ".taxi-order-card__metric b, .taxi-trip-dashboard__value strong, " +
      ".taxi-trip-dashboard__value small, .taxi-metric strong, .taxi-fleet__stats strong, " +
      ".taxi-fleet__driver-stats span, .taxi-fuel__metric strong, .taxi-next-offer__metric strong"
    )).filter(visible);
    if (extremeMode && (!Number.isFinite(requestedUiScale) || requestedUiScale <= 100)) {
      numericValues.forEach((element) => {
        if (element.scrollWidth > element.clientWidth + 1) {
          failures.push(`numeric-value-clipped:${element.className || element.tagName}:${element.textContent.trim().slice(0, 24)}`);
        }
      });
    }
    const truncatableText = Array.from(document.querySelectorAll(
      ".taxi-appbar__title, .taxi-home__vehicle-copy strong, .taxi-order-card__name strong, " +
      ".taxi-sheet__heading-text strong, .taxi-fleet__vehicle strong, " +
      ".taxi-fleet__candidate strong, .taxi-shift-card__copy strong"
    )).filter(visible);
    truncatableText.forEach((element) => {
      const clipped = element.scrollWidth > element.clientWidth + 1 || element.scrollHeight > element.clientHeight + 1;
      if (clipped && !element.getAttribute("title")) {
        failures.push(`truncated-text-without-title:${element.className || element.tagName}`);
      }
    });
    Array.from(document.querySelectorAll(".taxi-fleet-button, .taxi-shift-history-button"))
      .filter(visible)
      .forEach((button) => {
        const label = button.querySelector(".taxi-action-label");
        const badge = button.querySelector(".taxi-count-badge");
        if (label && badge && label.getBoundingClientRect().right > badge.getBoundingClientRect().left - 2) {
          failures.push(`action-label-badge-overlap:${button.className}`);
        }
      });
    if (extremeMode && (scenarioName === "shiftHistory" || scenarioName === "profileShifts")) {
      const renderedShifts = document.querySelectorAll(".taxi-shift-card").length;
      if (renderedShifts > 30) failures.push(`shift-history-not-bounded:${renderedShifts}`);
    }
    const rideFooter = document.querySelector(".taxi-ride-footer");
    if (rideFooter && screen) {
      const footerRect = rideFooter.getBoundingClientRect();
      const screenRect = screen.getBoundingClientRect();
      if (footerRect.left < screenRect.left - 2 || footerRect.right > screenRect.right + 2) {
        failures.push("trip-footer-horizontal-overflow");
      }
    }
    const tripSheet = document.querySelector(".taxi-trip-layout > .taxi-sheet");
    if (tripSheet && visible(tripSheet)) {
      const blocks = Array.from(tripSheet.children).filter(visible);
      for (let leftIndex = 0; leftIndex < blocks.length; leftIndex += 1) {
        const left = blocks[leftIndex].getBoundingClientRect();
        for (let rightIndex = leftIndex + 1; rightIndex < blocks.length; rightIndex += 1) {
          const right = blocks[rightIndex].getBoundingClientRect();
          const horizontalOverlap = Math.min(left.right, right.right) - Math.max(left.left, right.left);
          const verticalOverlap = Math.min(left.bottom, right.bottom) - Math.max(left.top, right.top);
          if (horizontalOverlap > 1 && verticalOverlap > 1) {
            failures.push(`trip-block-overlap:${blocks[leftIndex].className}:${blocks[rightIndex].className}`);
          }
        }
      }
      const priorityActionFirst = scaleStage && (
        scaleStage.classList.contains("taxi-ui-tier--large") ||
        scaleStage.classList.contains("taxi-ui-tier--accessibility")
      );
      const orderedRegionSelectors = priorityActionFirst ? [
        ["heading", ".taxi-sheet__heading"],
        ["dashboard", ".taxi-trip-dashboard"],
        ["progress", ".taxi-progress"],
        ["footer", ".taxi-ride-footer"],
        ["metrics", ".taxi-metrics"],
        ["penalties", ".taxi-penalty-log"],
      ] : [
        ["heading", ".taxi-sheet__heading"],
        ["dashboard", ".taxi-trip-dashboard"],
        ["progress", ".taxi-progress"],
        ["metrics", ".taxi-metrics"],
        ["penalties", ".taxi-penalty-log"],
        ["footer", ".taxi-ride-footer"],
      ];
      const orderedRegions = orderedRegionSelectors
        .map(([name, selector]) => [name, tripSheet.querySelector(selector)])
        .filter(([, element]) => element && visible(element));
      for (let index = 1; index < orderedRegions.length; index += 1) {
        const [previousName, previous] = orderedRegions[index - 1];
        const [currentName, current] = orderedRegions[index];
        if (current.getBoundingClientRect().top < previous.getBoundingClientRect().top - 1) {
          failures.push(`trip-region-order:${previousName}:${currentName}`);
        }
      }
      const tripLayout = tripSheet.closest(".taxi-trip-layout");
      const map = tripLayout && tripLayout.querySelector(":scope > .taxi-map");
      if (map && map.getBoundingClientRect().bottom > tripSheet.getBoundingClientRect().top + 1) {
        failures.push("trip-map-sheet-overlap");
      }
    }
    if (!externalMode && window.innerWidth <= 359 && window.innerHeight <= 600) {
      const startButton = document.querySelector(".taxi-home .taxi-start");
      if (startButton && visible(startButton) && screen &&
          !within(screen.getBoundingClientRect(), startButton.getBoundingClientRect(), 8)) {
        failures.push("low-height-primary-action-outside-screen");
      }
    }
    const fuelPanel = document.querySelector(".taxi-fuel");
    if (!externalMode && fuelPanel && visible(fuelPanel) && window.innerWidth <= 420 && window.innerHeight <= 640) {
      const buy = fuelPanel.querySelector(".taxi-fuel__buy");
      const preceding = Array.from(fuelPanel.children).filter((element) => element !== buy && visible(element));
      if (buy && visible(buy)) {
        const buyRect = buy.getBoundingClientRect();
        preceding.forEach((element) => {
          const rect = element.getBoundingClientRect();
          const horizontalOverlap = Math.min(rect.right, buyRect.right) - Math.max(rect.left, buyRect.left);
          const verticalOverlap = Math.min(rect.bottom, buyRect.bottom) - Math.max(rect.top, buyRect.top);
          if (horizontalOverlap > 1 && verticalOverlap > 1) {
            failures.push(`low-height-fuel-cta-overlap:${element.className || element.tagName}`);
          }
        });
      }
    }
    const calmnessMetric = document.querySelector(".taxi-trip-dashboard__metric--calmness");
    if (calmnessMetric && visible(calmnessMetric)) {
      const emoji = calmnessMetric.querySelector(".taxi-calmness-emoji");
      const percent = calmnessMetric.querySelector(".taxi-trip-dashboard__calmness-value");
      const metricRect = calmnessMetric.getBoundingClientRect();
      const emojiRect = emoji.getBoundingClientRect();
      if (Math.abs(emojiRect.left - metricRect.left) > 1) failures.push("trip-calmness-emoji-not-left-aligned");
      if (Math.abs(emojiRect.top - metricRect.top) > 1 || Math.abs(emojiRect.bottom - metricRect.bottom) > 1) {
        failures.push("trip-calmness-emoji-not-full-height");
      }
      if (Number.parseFloat(getComputedStyle(percent).fontSize) < 18) {
        failures.push("trip-calmness-percent-too-small");
      }
    }
    if (externalMode) {
      const controls = Array.from(document.querySelectorAll(".taxi-appbar button, .taxi-order-card__accept, .taxi-fuel__buy"));
      if (controls.some((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && rect.height < 44;
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
        if (fontSize > 0 && fontSize < 9) smallTextValue = ownText.slice(0, 28);
        return fontSize > 0 && fontSize < 9;
      });
      if (smallText) failures.push(`native-text-under-9:${smallText.className || smallText.tagName}:${smallTextValue}`);
    }
    const horizontalContainers = [scaleStage, screen, document.querySelector(".taxi-trip-layout"), tripSheet]
      .filter((element) => element && visible(element));
    horizontalContainers.forEach((element) => {
      if (element.scrollWidth > element.clientWidth + 1) {
        failures.push(`horizontal-overflow:${element.className || element.tagName}`);
      }
    });
    if (Number.isFinite(requestedUiScale)) {
      const actionSelectors = [
        ".taxi-action--primary", ".taxi-action--secondary", ".taxi-action--danger-secondary",
        ".taxi-map__autopilot", ".taxi-map__fleet",
      ].join(", ");
      const controls = Array.from(document.querySelectorAll(actionSelectors)).filter(visible);
      const targetFloor = externalMode ? 44 : 36;
      controls.forEach((element) => {
        const rect = element.getBoundingClientRect();
        const requiredHeight = element.classList.contains("taxi-action--primary")
          ? Math.max(40, targetFloor) : targetFloor;
        if (rect.height + 0.5 < requiredHeight) {
          failures.push(`control-target-too-small:${element.className}:${rect.height.toFixed(1)}<${requiredHeight}`);
        }
        const intersectsViewport = rect.right > 0 && rect.bottom > 0 &&
          rect.left < window.innerWidth && rect.top < window.innerHeight;
        if (intersectsViewport) {
          const x = Math.max(0, Math.min(window.innerWidth - 1, rect.left + rect.width / 2));
          const y = Math.max(0, Math.min(window.innerHeight - 1, rect.top + rect.height / 2));
          let centerInsideClip = true;
          for (let ancestor = element.parentElement; ancestor && centerInsideClip; ancestor = ancestor.parentElement) {
            const style = getComputedStyle(ancestor);
            if (/(auto|scroll|hidden|clip)/.test(`${style.overflow} ${style.overflowX} ${style.overflowY}`)) {
              const clip = ancestor.getBoundingClientRect();
              centerInsideClip = x >= clip.left && x <= clip.right && y >= clip.top && y <= clip.bottom;
            }
          }
          if (centerInsideClip) {
            const hit = document.elementFromPoint(x, y);
            if (!hit || (hit !== element && !element.contains(hit))) {
              failures.push(`control-center-obscured:${element.className}`);
            }
          }
        }
      });
      const controlFloors = {80: 12, 90: 12, 100: 13, 110: 14, 120: 15, 130: 16,
        140: 17, 150: 18, 160: 19, 170: 20, 180: 21};
      const metadataFloors = {80: 10, 90: 10, 100: 10, 110: 11, 120: 12, 130: 13,
        140: 14, 150: 15, 160: 16, 170: 17, 180: 18};
      const controlFloor = Math.max(externalMode ? 13 : 12, controlFloors[uiScalePercent]);
      controls.forEach((element) => {
        const fontSize = Number.parseFloat(getComputedStyle(element).fontSize) || 0;
        const labelledIconOnly = fontSize === 0 && Boolean(element.getAttribute("aria-label"));
        if (!labelledIconOnly && fontSize + 0.01 < controlFloor) {
          failures.push(`control-text-too-small:${element.className}:${fontSize}<${controlFloor}`);
        }
      });
      const metadataFloor = Math.max(externalMode ? 11 : 10, metadataFloors[uiScalePercent]);
      const metadata = Array.from(document.querySelectorAll(
        ".taxi-map__route-info span, .taxi-map__route-info small, .taxi-sheet__heading span, " +
        ".taxi-trip-dashboard__label, .taxi-progress__labels, .taxi-trip-notice"
      )).filter(visible);
      metadata.forEach((element) => {
        const fontSize = Number.parseFloat(getComputedStyle(element).fontSize) || 0;
        if (fontSize + 0.01 < metadataFloor) {
          failures.push(`metadata-text-too-small:${element.className}:${fontSize}<${metadataFloor}`);
        }
      });
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
