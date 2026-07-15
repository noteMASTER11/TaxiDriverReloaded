(function () {
  "use strict";

  const loader = document.getElementById("taxi-loader");
  const title = document.getElementById("taxi-loader-title");
  const detail = document.getElementById("taxi-loader-detail");
  const progress = document.getElementById("taxi-loader-progress");
  const errorBox = document.getElementById("taxi-loader-error");
  const retryButton = document.getElementById("taxi-loader-retry");
  const steps = ["connection", "runtime", "assets", "state"];
  let completed = 0;
  let ready = false;
  let failed = false;

  const setStep = (name, status, label) => {
    const row = document.querySelector(`[data-step="${name}"]`);
    if (!row) return;
    row.classList.remove("is-active", "is-done", "is-failed");
    if (status) row.classList.add(`is-${status}`);
    const value = row.querySelector("b");
    if (value) value.textContent = label || status;
    completed = steps.filter((step) => document.querySelector(`[data-step="${step}"]`)?.classList.contains("is-done")).length;
    progress.style.width = `${Math.max(8, completed * 23)}%`;
  };

  const setStage = (heading, copy) => {
    title.textContent = heading;
    detail.textContent = copy;
  };

  const fail = (message) => {
    if (ready || failed) return;
    failed = true;
    loader.classList.add("is-error");
    setStage("Unable to open TaxiDriver", "The game connection did not become ready.");
    const active = steps.find((step) => document.querySelector(`[data-step="${step}"]`)?.classList.contains("is-active"));
    if (active) setStep(active, "failed", "Failed");
    errorBox.hidden = false;
    errorBox.textContent = message;
    retryButton.hidden = false;
  };

  const loadScript = (src) => new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = resolve;
    script.onerror = () => reject(new Error(`Could not load ${src}`));
    document.head.appendChild(script);
  });

  const warmAssets = async () => {
    const assets = [
      "/ui/modules/apps/TaxiDriverHUD/app.html",
      "/ui/modules/apps/TaxiDriverHUD/app.css",
      "/ui/modules/apps/TaxiDriverHUD/locales.json"
    ];
    const results = await Promise.all(assets.map((asset) => fetch(asset, { cache: "force-cache" })));
    if (results.some((response) => !response.ok)) throw new Error("One or more TaxiDriver assets are unavailable.");
  };

  const waitForConnection = () => new Promise((resolve, reject) => {
    const started = Date.now();
    const check = () => {
      if (typeof websocketCommGetConnectionState === "function" && websocketCommGetConnectionState() === "open") {
        resolve();
        return;
      }
      if (Date.now() - started > 12000) {
        reject(new Error("No response from BeamNG.drive. Check that the game is running and the address belongs to this computer."));
        return;
      }
      setTimeout(check, 150);
    };
    check();
  });

  const waitForHudState = (bridge) => new Promise((resolve, reject) => {
    let timeout = setTimeout(() => reject(new Error("Connected to BeamNG.drive, but TaxiDriver did not return its current state. Reload the mod or restart the game.")), 12000);
    bridge.events.on("TaxiDriverHUDState", () => {
      clearTimeout(timeout);
      timeout = null;
      resolve();
    });
  });

  const start = async () => {
    try {
      setStep("connection", "active", "Connecting");
      await waitForConnection();
      setStep("connection", "done", "Connected");

      setStep("runtime", "active", "Loading");
      setStage("Loading application runtime", "Preparing the lightweight TaxiDriver web app…");
      await loadScript("/ui/lib/ext/tiny-emitter/tinyemitter.js");
      await loadScript("/ui/lib/ext/angular/angular.js");
      await loadScript("/ui/lib/ext/qrcode.min.js");
      const bridgeModule = await import("/ui/ui-vue/src/bridge/index.js");
      bridgeModule.setBridgeDependencies({ Emitter: window.TinyEmitter, beamng: window.beamng });
      window.bridge = bridgeModule.useBridge();
      window.bngApi = window.bridge.api;
      window.StreamsManager = window.bridge.streams;
      window.vueEventBus = window.bridge.events;
      setStep("runtime", "done", "Ready");

      setStep("assets", "active", "Caching");
      setStage("Preparing the phone", "Loading the interface, translations and sounds into the browser cache…");
      await loadScript("/ui/modules/apps/TaxiDriverHUD/external/sounds-data.js");
      await warmAssets();
      angular.module("beamng.apps", []).run(["$rootScope", function ($rootScope) {
        window.globalAngularRootScope = $rootScope;
      }]);
      const hudStatePromise = waitForHudState(window.bridge);
      await loadScript("/ui/modules/apps/TaxiDriverHUD/app.js");
      document.getElementById("taxi-external-root").innerHTML = "<taxi-driver-hud></taxi-driver-hud>";
      angular.bootstrap(document.getElementById("taxi-external-root"), ["beamng.apps"]);
      setStep("assets", "done", "Cached");

      setStep("state", "active", "Syncing");
      setStage("Synchronizing live state", "Receiving your active shift, trip, settings and profile…");
      await hudStatePromise;
      setStep("state", "done", "Live");
      progress.style.width = "100%";
      setStage("TaxiDriver is ready", "The phone is synchronized with the game.");
      ready = true;
      setTimeout(() => loader.classList.add("is-ready"), 250);
    } catch (error) {
      console.error("TaxiDriver External UI:", error);
      fail(error && error.message ? error.message : "Unknown loading error.");
    }
  };

  retryButton.addEventListener("click", () => window.location.reload());
  start();
})();
