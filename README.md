<p align="center">
  <img src="ui/modules/apps/TaxiDriverHUD/app.png" width="96" height="96" alt="TaxiDriver Reloaded icon">
</p>

<h1 align="center">TaxiDriver Reloaded</h1>

<p align="center">
  <strong>Your city. Your shift. Your reputation.</strong><br>
  A universal free-roam taxi mode for BeamNG.drive, presented as an immersive mobile driver app.
</p>

<p align="center">
  <a href="https://github.com/noteMASTER11/TaxiDriverReloaded/releases/latest"><img src="https://img.shields.io/github/v/release/noteMASTER11/TaxiDriverReloaded?display_name=tag&style=flat-square&color=ffd11a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/BeamNG.drive-0.38.6-f28c28?style=flat-square" alt="BeamNG.drive 0.38.6">
  <img src="https://img.shields.io/badge/mode-free%20roam-5de18d?style=flat-square" alt="Free-roam mode">
  <img src="https://img.shields.io/badge/UI-TaxiDriverHUD-55c7e8?style=flat-square" alt="TaxiDriverHUD UI App">
</p>

<p align="center">
  <a href="https://github.com/noteMASTER11/TaxiDriverReloaded/releases/latest"><strong>Download the latest release</strong></a>
</p>

---

TaxiDriver Reloaded turns ordinary free roam into a complete taxi-driving loop. Go online from the in-game phone, choose a passenger request, drive to a realistic roadside pickup point, complete the fare, protect your rating, and continue into the next queued ride.

It is not a fixed scenario and does not depend on hardcoded pickup lists for one map. Orders are generated from the current road network, making the mode usable across compatible official and community maps.

## Highlights

### A taxi app inside the game

- Start and stop taxi work directly from the `TaxiDriverHUD` UI App.
- Use a phone-inspired interface with animated screens, loaders, notifications, settings, and minimization.
- Keep dispatch messages, penalties, passenger chat, and order confirmations inside the phone instead of the global game notification tray.
- Scale interface text to suit the size of your UI layout.

### A living dispatcher

- Browse a gradually populated pool of **10–12 mixed requests**.
- Compare passenger, pickup deadline, trip time, distance, fare, rating bonus, Calmness, and scheduled stops.
- Choose between regular, rush, and multi-stop work.
- Rush requests offer additional pay but impose a tighter arrival target.
- Multi-stop requests create longer routes and require a **10-second stationary wait** at every intermediate stop.
- Sparse maps automatically avoid multi-stop orders when there are not enough safe route points.

### Universal and more believable destinations

- Pickup and drop-off points are generated dynamically from the active map.
- Trips are designed around practical route distances of approximately **1–25 km**.
- The generator prefers suitable roadside locations near buildings and bus stops when map data is available.
- Lane-aware placement aims for the road edge instead of dropping passengers into inner traffic lanes.
- Controlled positional variation reduces visibly repeated pickup locations.

### Passengers with personality

- Passenger names are generated from English first-name and surname pools.
- The selected passenger may send **one to three emoji-only messages** while you drive to pickup.
- Each short conversation keeps a coherent randomly chosen mood and needs no language-specific message text.
- Every passenger receives a random **Calmness** value, shown as an expressive emoji with a percentage.
- Calm passengers may ignore some penalty events; sensitive passengers react more strongly to poor driving.
- A passenger who becomes critically dissatisfied can demand an immediate stop and end the ride early.

### Driving quality that affects the fare

- The phone calculates an estimated fare before the trip.
- Speeding, collisions, harsh maneuvers, and late pickup can reduce the final payment.
- Every applied reduction appears in the in-phone **Penalties** list with its value and event details.
- Total fare reduction is capped at **50%**.
- Difficulty presets range from **Elementary** to **Professional**.
- A strong driver rating increases earnings, reaching a **15% rating bonus at 5.00**.
- The persistent driver rating is displayed on a five-star progress scale from `0.00` to `5.00`.

### Navigation built for the phone

- A rectangular native minimap appears only during active driving phases.
- The map zooms in at low speeds and pulls back more aggressively at higher speeds.
- ETA is calculated using a city-driving reference speed of **40 km/h**.
- Arrival time, remaining distance, route progress, speed limit, stop markers, and trip metrics remain visible around the map.
- Road-surface route arrows can be disabled in settings.

### Pickup, stops, and continuous work

- Reaching a pickup or destination opens a dedicated boarding or alighting screen.
- The mod attempts to open and close a passenger-side door for extra immersion; unsupported vehicles continue safely without it.
- Pickup deadlines can produce a gradually increasing late-arrival penalty.
- When a trip is more than 90% complete, another offer may appear for a limited time.
- Accepted offers enter a queue and never overwrite the current passenger.
- Expired offers disappear and another may arrive after a short delay.
- Vehicle reset clears both the active trip and the queued request to prevent stale state.

## Settings

Open the gear icon in the TaxiDriver phone to configure:

- language;
- difficulty preset;
- text size;
- silent mode;
- road-surface route guidance.

The interface includes English, German, French, Spanish, Polish, Russian, and Ukrainian. English is used by default unless another language is explicitly saved.

Settings are stored outside the mod at:

```text
%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\settings\TaxiDriver\settings.json
```

If the file is missing, invalid, or uses an unsupported schema, safe defaults are restored and saved automatically.

All application sounds—including clicks, online/offline cues, passenger messages, penalties, and new offers—follow BeamNG.drive's **Interface Volume** setting in real time.

## Installation

1. Download `taxidriver.zip` from the [latest GitHub release](https://github.com/noteMASTER11/TaxiDriverReloaded/releases/latest).
2. Place the archive directly in:

   ```text
   %LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\
   ```

3. Start BeamNG.drive and open a free-roam session.
4. Open the UI Apps editor and add **TaxiDriverHUD**.
5. Press **Start Ride** on the phone and wait for dispatch to populate the order list.

> Do not keep packed and unpacked copies of the same mod version active at the same time. Duplicate Lua and UI files may cause loading conflicts.

## Compatibility

- Target game version: **BeamNG.drive 0.38.6**.
- Designed for official and community maps with a usable road network.
- Best results are obtained on maps with detailed road, building, and bus-stop data.
- Vehicle door animation is best-effort and depends on the selected vehicle.

## Repository structure

```text
lua/ge/extensions/taxiDriver/       Main taxi-mode logic
lua/vehicle/extensions/auto/        Vehicle telemetry bridge
ui/modules/apps/TaxiDriverHUD/      Phone UI App, assets, and sounds
mod_info/TaxiDriver/                BeamNG mod metadata
```

Packaged builds are distributed through [GitHub Releases](https://github.com/noteMASTER11/TaxiDriverReloaded/releases) and are intentionally excluded from the source tree.

## Credits

Special thanks to **Incognito**, creator of the original [TaxiDriver mod](https://www.beamng.com/resources/taxidriver.28763/).

The original concept of a dedicated BeamNG.drive taxi experience—including passenger rides, an economy, and a driver-rating system—belongs to Incognito. TaxiDriver Reloaded is an independent reimagining and technical redevelopment for modern free roam. It is not an official update to, or replacement for, the original resource.
