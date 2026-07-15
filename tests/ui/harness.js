(() => {
  "use strict";
  const params = new URLSearchParams(window.location.search);
  const scenarioName = params.get("scenario") || "home";
  const width = Math.max(330, Number(params.get("width")) || 520);
  const height = Math.max(616, Number(params.get("height")) || 900);
  document.documentElement.style.setProperty("--test-width", `${width}px`);
  document.documentElement.style.setProperty("--test-height", `${height}px`);

  const state = window.__taxiScenarios[scenarioName] || window.__taxiScenarios.home;
  const externalMode = params.get("external") === "1";
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
        scope.settingsSections = { general: true, gameplay: true, navigation: true, audio: true, connectivity: true, cheats: true };
      }
      if (scenarioName === "settingsConnection") {
        scope.settingsOpen = true;
        scope.settingsSections = { general: false, gameplay: false, navigation: false, audio: false, connectivity: true, cheats: false };
      }
      if (scenarioName === "profile") {
        scope.profileOpen = true;
        scope.profileTab = "reviews";
      }
      if (scenarioName === "compact") scope.phoneMinimized = true;
      if (scenarioName === "fuel") scope.fuelStationOpen = true;
    });
    rootScope.$broadcast("TaxiDriverProfileData", {
      profile: { fullName: "Alex Morgan", birthDate: "1991-05-17", avatar: "🙂" },
      progress: {
        balance: 75.15, rating: 4.37, completedRides: 18,
        reviews: Array.from({ length: 12 }, (_, index) => ({ id: index + 1, passengerName: `Passenger ${index + 1}`, emoji: index % 3 ? "😊" : "🤩", quality: 82 + index, timestamp: 1760000000 + index * 80000, rating: 4.1 + (index % 5) * 0.2 })),
        ratingHistory: [], balanceHistory: [],
      },
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
    const screen = document.querySelector(".taxi-phone__screen");
    const settingsPanel = document.querySelector(".taxi-settings");
    const qr = document.querySelector(".taxi-lan__qr");
    const stageRect = stage.getBoundingClientRect();
    const failures = [];
    const within = (outer, inner, tolerance = 1) => inner.left >= outer.left - tolerance &&
      inner.right <= outer.right + tolerance && inner.top >= outer.top - tolerance &&
      inner.bottom <= outer.bottom + tolerance;
    if (phone && !within(stageRect, phone.getBoundingClientRect(), 2)) failures.push("phone-outside-stage");
    if (document.documentElement.scrollWidth > window.innerWidth + 1) failures.push("document-horizontal-overflow");
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
