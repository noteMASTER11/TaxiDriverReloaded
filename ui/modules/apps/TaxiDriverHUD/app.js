const loadTaxiDriverI18n = () => {
  try {
    const request = new XMLHttpRequest();
    request.open("GET", "/ui/modules/apps/TaxiDriverHUD/locales.json", false);
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
    return {
      templateUrl: "/ui/modules/apps/TaxiDriverHUD/app.html",
      replace: false,
      restrict: "E",
      scope: true,
      controllerAs: "hud",
      controller: function ($scope, $element) {
        const i18n = loadTaxiDriverI18n();
        const settingsKey = "taxiDriverHUD.settings.v1";
        const languages = [
          { code: "en", label: "English" }, { code: "de", label: "Deutsch" },
          { code: "fr", label: "Français" }, { code: "es", label: "Español" },
          { code: "pl", label: "Polski" }, { code: "uk", label: "Українська" },
          { code: "ru", label: "Русский" },
        ];
        const difficulties = ["elementary", "easy", "standard", "professional"];
        let persisted = {};
        let legacySettingsFound = false;
        try {
          const legacyValue = localStorage.getItem(settingsKey);
          if (legacyValue) {
            const parsed = JSON.parse(legacyValue);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              persisted = parsed;
              legacySettingsFound = true;
            }
          }
        } catch (_) { persisted = {}; }
        const initialLanguage = persisted.rememberLanguage && i18n[persisted.language] ? persisted.language : "en";
        const initialDifficulty = difficulties.includes(persisted.difficulty) ? persisted.difficulty : "standard";
        const savedFontBoost = persisted.fontBoost === undefined ? 2 : persisted.fontBoost;
        const initialFontBoost = Math.max(0, Math.min(5, Number(savedFontBoost)));
        const savedAppVolume = persisted.appVolume === undefined ? 0.65 : Number(persisted.appVolume);
        const initialAppVolume = Math.max(0, Math.min(1, Number.isFinite(savedAppVolume) ? savedAppVolume : 0.65));
        const initialSilentMode = persisted.silentMode === true;
        const initialShowRouteGuidance = persisted.showRouteGuidance !== false;
        const initialRealisticMode = persisted.realisticMode === true;

        $scope.languages = languages;
        $scope.difficulties = difficulties;
        $scope.language = initialLanguage;
        $scope.settingsOpen = false;
        $scope.settingsSaved = false;
        $scope.profileOpen = false;
        $scope.profileTab = "identity";
        $scope.profileSaved = false;
        $scope.reviewPage = 1;
        $scope.reviewsPerPage = 6;
        $scope.offlineHoldProgress = 0;
        $scope.offlineConfirmOpen = false;
        $scope.phoneMinimized = false;
        $scope.phoneToast = null;
        $scope.passengerChat = null;
        $scope.passengerMoodFlash = "";
        $scope.nextOfferAcceptedVisible = false;
        $scope.fuelStationOpen = false;
        $scope.selectedFuelType = "";
        $scope.refuel = { amount: 0 };
        $scope.settings = {
          language: initialLanguage,
          rememberLanguage: persisted.rememberLanguage === true,
          difficulty: initialDifficulty,
          fontBoost: initialFontBoost,
          appVolume: initialAppVolume,
          silentMode: initialSilentMode,
          showRouteGuidance: initialShowRouteGuidance,
          realisticMode: initialRealisticMode,
        };
        $scope.driverProfile = { fullName: "John Doe", birthDate: "", avatar: "🙂" };
        $scope.profileDraft = Object.assign({}, $scope.driverProfile);
        $scope.profileProgress = {
          reviews: [], ratingHistory: [], balanceHistory: [],
          balance: 0, rating: 5, completedRides: 0,
        };
        $scope.profileReviews = [];
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
          passengerOnboard: false,
          deliveryOnboard: false,
          realisticMode: false,
          vehicleEnergy: { available: false, energyType: "", quantity: 0, unit: "", estimatedRangeKm: 0 },
          fuelStation: {
            available: false, id: "", name: "", options: [], balance: 0,
            refueling: { active: false, completing: false, energyType: "", quantity: 0, cost: 0, duration: 0, elapsed: 0, progress: 0, remainingSeconds: 0, completionId: 0 },
          },
          fuelDetour: { active: false, hadTrip: false, passengerOnboard: false, stationName: "", routeDistance: 0, penaltyPercent: 0, arrived: false },
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
          speedLimit: 0,
          currentSpeed: 0,
          nextOffer: null,
          penalties: emptyPenalties(),
        };
        $scope.stars = [1, 2, 3, 4, 5];

        const createAppAudioPool = (fileName, volume, size) => {
          const players = [];
          for (let index = 0; index < size; index += 1) {
            const audio = new Audio(`/ui/modules/apps/TaxiDriverHUD/sounds/${fileName}`);
            audio.preload = "auto";
            audio.volume = volume;
            players.push(audio);
          }
          return { players, cursor: 0, baseVolume: volume };
        };
        const appAudio = {
          click: createAppAudioPool("taxidriver_ui_click.mp3", 0.52, 3),
          newRide: createAppAudioPool("taxidriver_new_ride.mp3", 0.78, 2),
          offline: createAppAudioPool("taxidriver_offline.mp3", 0.75, 2),
          online: createAppAudioPool("taxidriver_online.mp3", 0.75, 2),
          violation: createAppAudioPool("taxidriver_violation_ping.mp3", 0.7, 3),
          message: createAppAudioPool("taxidriver_passenger_message.mp3", 0.72, 3),
        };
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

        const playAppSound = (soundId) => {
          if ($scope.settings.silentMode) return;
          const pool = appAudio[soundId];
          if (!pool || !pool.players.length) return;
          const audio = pool.players[pool.cursor];
          pool.cursor = (pool.cursor + 1) % pool.players.length;
          try {
            audio.volume = clampAudioVolume(
              pool.baseVolume * gameUiVolume * clampAudioVolume($scope.settings.appVolume)
            );
            audio.currentTime = 0;
            const playback = audio.play();
            if (playback && playback.catch) playback.catch(() => {});
          } catch (_) {}
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
              sentAt: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
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
          const fontBoost = value.fontBoost === undefined ? 2 : Number(value.fontBoost);
          const appVolume = value.appVolume === undefined ? 0.65 : Number(value.appVolume);
          return {
            language: i18n[value.language] ? value.language : "en",
            rememberLanguage: value.rememberLanguage === true,
            difficulty: difficulties.includes(value.difficulty) ? value.difficulty : "standard",
            fontBoost: Math.max(0, Math.min(5, Math.round(Number.isFinite(fontBoost) ? fontBoost : 2))),
            appVolume: Math.max(0, Math.min(1, Number.isFinite(appVolume) ? appVolume : 0.65)),
            silentMode: value.silentMode === true,
            showRouteGuidance: value.showRouteGuidance !== false,
            realisticMode: value.realisticMode === true,
          };
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
          })).filter((option) => option.energyType) : [];
          return {
            available: value.available === true,
            id: String(value.id || ""),
            name: String(value.name || ""),
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
        $scope.formatReviewDate = (timestamp) => {
          const value = Number(timestamp || 0);
          if (!value) return "—";
          return new Date(value * 1000).toLocaleDateString($scope.language || "en", {
            year: "numeric", month: "short", day: "numeric",
          });
        };

        let lastMinimapRect = "";
        let minimapVisible = false;
        let uiVisible = true;
        const minimapPhases = new Set(["toPickup", "toStop", "toDestination", "toFuelStation"]);
        const canRenderMinimap = (hudState) => uiVisible && hudState &&
          hudState.active === true && minimapPhases.has(hudState.phase) &&
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
            $scope.phoneMinimized
              ? ".taxi-compact .taxi-minimap-surface"
              : ".taxi-phone .taxi-minimap-surface"
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
          const notificationValues = $scope.phoneMinimized
            ? [0, 0, 0, 0]
            : normalizeRect($element[0].querySelector(".taxi-phone-toast"));
          const layoutKey = values
            .concat(routeInfoValues, speedLimitValues, notificationValues)
            .map((value) => value.toFixed(5))
            .join(",");
          if (layoutKey === lastMinimapRect) return;
          lastMinimapRect = layoutKey;
          minimapVisible = true;

          const rectKey = values.map((value) => value.toFixed(5)).join(",");
          const occlusionKey = routeInfoValues
            .concat(speedLimitValues, notificationValues)
            .map((value) => value.toFixed(5))
            .join(",");

          bngApi.engineLua(
            `if taxiDriver_taxiDriver then taxiDriver_taxiDriver.setMinimapTransform(${rectKey}); taxiDriver_taxiDriver.setMinimapOcclusions(${occlusionKey}) end`
          );
        };

        const scheduleMinimapUpdate = () =>
          $scope.$evalAsync(() => requestAnimationFrame(updateMinimap));

        const updateClock = () => {
          $scope.currentClock = new Date().toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          });
        };

        this.startMode = () => callTaxiDriver("startMode");
        this.stopMode = () => callTaxiDriver("stopMode");
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
        this.toggleSettings = () => {
          $scope.settingsOpen = !$scope.settingsOpen;
          $scope.profileOpen = false;
          $scope.fuelStationOpen = false;
          $scope.offlineConfirmOpen = false;
          $scope.settingsSaved = false;
          if ($scope.settingsOpen) {
            dismissPassengerChat();
            hideMinimap();
          }
          else scheduleMinimapUpdate();
        };
        this.toggleProfile = () => {
          $scope.profileOpen = !$scope.profileOpen;
          $scope.settingsOpen = false;
          $scope.fuelStationOpen = false;
          $scope.offlineConfirmOpen = false;
          $scope.profileSaved = false;
          stopOfflineHold();
          if ($scope.profileOpen) {
            dismissPassengerChat();
            hideMinimap();
            requestProfileData();
          } else {
            scheduleMinimapUpdate();
          }
        };
        this.selectProfileTab = (tab) => {
          if (["identity", "reviews", "analytics"].includes(tab)) $scope.profileTab = tab;
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
          $scope.settingsSaved = false;
        };
        this.selectDifficulty = (preset) => {
          if (difficulties.includes(preset)) $scope.settings.difficulty = preset;
          $scope.settingsSaved = false;
        };
        this.previewAppVolume = () => {
          $scope.settings.appVolume = Math.max(
            0,
            Math.min(1, Number($scope.settings.appVolume) || 0)
          );
          $scope.settingsSaved = false;
          applyGameUiVolume();
        };
        this.testAppVolume = () => {
          this.previewAppVolume();
          const soundIds = ["click", "newRide", "offline", "online", "violation", "message"];
          playAppSound(soundIds[Math.floor(Math.random() * soundIds.length)]);
        };
        this.saveSettings = () => {
          $scope.settings = normalizeSettings($scope.settings);
          $scope.language = $scope.settings.language;
          applyGameUiVolume();
          saveSettingsToLua($scope.settings);
          $scope.settingsSaved = true;
          $scope.settingsOpen = false;
          scheduleMinimapUpdate();
        };
        this.toggleRealisticMode = () => {
          $scope.settings.realisticMode = $scope.settings.realisticMode === true;
          saveSettingsToLua($scope.settings);
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
        this.purchaseFuel = () => {
          if ($scope.state.fuelStation.refueling.active) return;
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
        $scope.formatDistance = (meters) => {
          const value = Number(meters || 0);
          return value >= 1000
            ? `${(value / 1000).toFixed(1)} ${$scope.t("unitKm")}`
            : `${Math.max(0, Math.round(value))} ${$scope.t("unitMeter")}`;
        };
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
          return arrival.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
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
        $scope.formatCargoWeight = (value) =>
          $scope.t("cargoWeightValue", { weight: Number(value || 0).toFixed(0) });
        $scope.getProgressPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.routeProgress || 0) * 100));
        $scope.getStarFill = (star) => {
          const rating = Number($scope.state.rating || 0);
          return Math.max(0, Math.min(100, (rating - (star - 1)) * 100));
        };
        $scope.getRatingPercent = () =>
          Math.max(0, Math.min(100, Number($scope.state.rating || 0) / 5 * 100));
        $scope.getFontPercent = () => 100 + Number($scope.settings.fontBoost || 0) * 10;
        $scope.getAppVolumePercent = () => Math.round(
          Math.max(0, Math.min(1, Number($scope.settings.appVolume) || 0)) * 100
        );
        $scope.formatRating = (value) => Number(value || 0).toFixed(2);
        $scope.formatBonusPercent = (value) => Number(value || 0).toFixed(1).replace(/\.0$/, "");
        $scope.getSelectedFuelOption = () => getFuelOption($scope.selectedFuelType);
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
        $scope.getPhoneNotificationText = () => $scope.phoneToast
          ? $scope.t($scope.phoneToast.key, $scope.phoneToast.values || {})
          : "";
        $scope.getPenaltyDetail = (event) => {
          if (event.kind === "speeding") return $scope.t("detail_speeding", {
            speed: Number(event.speedExcess || 0).toFixed(0),
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

        $scope.$on("TaxiDriverHUDState", (_, data) => {
          if (!data) return;
          data.vehicleEnergy = Object.assign(
            { available: false, energyType: "", quantity: 0, unit: "", estimatedRangeKm: 0 },
            data.vehicleEnergy || {}
          );
          data.fuelStation = normalizeFuelStation(data.fuelStation);
          data.fuelDetour = normalizeFuelDetour(data.fuelDetour);
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
            if (data.settingsNeedsLegacyImport && !legacyImportRequested) {
              legacyImportRequested = true;
              saveSettingsToLua(legacySettingsFound ? persisted : backendSettings);
            } else if (!data.settingsNeedsLegacyImport && !settingsInitializedFromBackend) {
              if (!backendSettings.rememberLanguage) backendSettings.language = "en";
              $scope.settings = backendSettings;
              $scope.language = backendSettings.language;
              applyGameUiVolume();
              settingsInitializedFromBackend = true;
              try { localStorage.removeItem(settingsKey); } catch (_) {}
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
          if (becameOnline) playAppSound("online");
          if (becameOffline) playAppSound("offline");
          if (hasNewNextOffer) playAppSound("newRide");
          if ((hasNewNextOffer || hasNewNotification) && $scope.phoneMinimized) {
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
          $scope.state = Object.assign({}, $scope.state, data);
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
          if (canRenderMinimap($scope.state)) scheduleMinimapUpdate();
          else hideMinimap(minimapVisible);
        });
        $scope.$on("TaxiDriverProfileData", (_, data) => {
          if (!data) return;
          if (Array.isArray(data.avatarOptions) && data.avatarOptions.length) {
            $scope.avatarOptions = data.avatarOptions;
          }
          const profile = normalizeProfile(data.profile);
          const progress = data.progress && typeof data.progress === "object" ? data.progress : {};
          progress.reviews = Array.isArray(progress.reviews) ? progress.reviews : [];
          progress.ratingHistory = Array.isArray(progress.ratingHistory) ? progress.ratingHistory : [];
          progress.balanceHistory = Array.isArray(progress.balanceHistory) ? progress.balanceHistory : [];
          $scope.driverProfile = profile;
          $scope.profileDraft = Object.assign({}, profile);
          $scope.profileProgress = Object.assign({
            balance: 0, rating: 5, completedRides: 0,
            reviews: [], ratingHistory: [], balanceHistory: [],
          }, progress);
          $scope.profileReviews = progress.reviews.slice().reverse();
          $scope.reviewPage = Math.min($scope.reviewPage, $scope.getReviewPageCount());
        });
        $scope.$on("onCefVisibilityChanged", (_, visible) => {
          uiVisible = visible !== false;
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
        const clockTimer = setInterval(() => $scope.$evalAsync(updateClock), 30000);
        const minimapTimer = setInterval(updateMinimap, 500);
        window.addEventListener("resize", updateMinimap);
        $scope.$on("$destroy", () => {
          clearInterval(clockTimer);
          clearInterval(minimapTimer);
          if (phoneToastTimer) clearTimeout(phoneToastTimer);
          if (acceptedOfferTimer) clearTimeout(acceptedOfferTimer);
          if (passengerMoodFlashTimer) clearTimeout(passengerMoodFlashTimer);
          stopOfflineHold();
          stopPassengerChat();
          appRoot.removeEventListener("click", handleAppClick, true);
          window.removeEventListener("resize", updateMinimap);
          hideMinimap();
        });
        callTaxiDriver("requestHudState");
        scheduleMinimapUpdate();
      },
    };
  },
]);
