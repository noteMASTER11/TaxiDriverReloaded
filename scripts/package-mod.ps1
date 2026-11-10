param(
  [string]$InstallDirectory = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& node (Join-Path $PSScriptRoot "build-ui.mjs")
if ($LASTEXITCODE -ne 0) { throw "Vue UI build failed" }
$dist = Join-Path $root "dist"
$zipPath = Join-Path $dist "taxidriver.zip"

if (-not (Test-Path -LiteralPath $dist)) {
  New-Item -ItemType Directory -Path $dist | Out-Null
}
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
  $zipPath,
  [System.IO.Compression.ZipArchiveMode]::Create
)
try {
  $files = @((Join-Path $root "CREDITS.txt"), (Join-Path $root "README.md"))
  foreach ($directoryName in @("lua", "mod_info", "settings", "ui")) {
    $directory = Join-Path $root $directoryName
    $files += [System.IO.Directory]::GetFiles(
      $directory,
      "*",
      [System.IO.SearchOption]::AllDirectories
    )
  }
  foreach ($file in ($files | Sort-Object)) {
    $entryName = $file.Substring($root.Length + 1).Replace("\", "/")
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $archive,
      $file,
      $entryName,
      [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
  }
}
finally {
  $archive.Dispose()
}

$requiredEntries = @(
  "README.md",
  "lua/ge/extensions/taxiDriver/taxiDriver.lua",
  "lua/ge/extensions/taxiDriver/autopilot.lua",
  "lua/ge/extensions/taxiDriver/aiDriverRoute.lua",
  "lua/ge/extensions/taxiDriver/aiLogger.lua",
  "lua/ge/extensions/taxiDriver/networkAddress.lua",
  "lua/ge/extensions/taxiDriver/nextOfferGuard.lua",
  "lua/ge/extensions/taxiDriver/fleetManager.lua",
  "lua/ge/extensions/taxiDriver/fleetWorker.lua",
  "lua/ge/extensions/taxiDriver/faultBoundary.lua",
  "lua/ge/extensions/taxiDriver/offerPlan.lua",
  "lua/ge/extensions/taxiDriver/optionalLanBridge.lua",
  "lua/ge/extensions/taxiDriver/earthRouting.lua",
  "lua/ge/extensions/taxiDriver/earthTransport.lua",
  "lua/ge/extensions/taxiDriver/earthCandidates.lua",
  "lua/ge/extensions/taxiDriver/earthDispatcher.lua",
  "lua/ge/extensions/taxiDriver/earthTripSupport.lua",
  "lua/ge/extensions/taxiDriver/earthAddresses.lua",
  "lua/ge/extensions/taxiDriver/autopilotPerception.lua",
  "lua/ge/extensions/taxiDriver/persistence.lua",
  "lua/ge/extensions/taxiDriver/fuelPersistence.lua",
  "lua/ge/extensions/taxiDriver/stopSafety.lua",
  "lua/ge/extensions/taxiDriver/physicalPickup.lua",
  "lua/ge/extensions/taxiDriver/policeCheckEvent.lua",
  "lua/ge/extensions/taxiDriver/routeCache.lua",
  "lua/ge/extensions/taxiDriver/routePlanner.lua",
  "lua/ge/extensions/taxiDriver/rideRules.lua",
  "lua/ge/extensions/taxiDriver/hudPublisher.lua",
  "lua/ge/extensions/taxiDriver/logger.lua",
  "lua/ge/extensions/taxiDriver/navigationUi.lua",
  "lua/ge/extensions/taxiDriver/nativeMinimap.lua",
  "lua/ge/extensions/taxiDriver/shiftTracker.lua",
  "lua/ge/extensions/taxiDriver/shiftHistory.lua",
  "lua/ge/extensions/taxiDriver/tripEvents.lua",
  "lua/ge/extensions/taxiDriver/tripHistory.lua",
  "lua/ge/extensions/taxiDriver/vehicleControl.lua",
  "lua/ge/extensions/taxiDriver/vehicleHistory.lua",
  "lua/ge/extensions/taxiDriver/vehicleScanGuard.lua",
  "lua/ge/extensions/taxiDriver/vehicleBridgeGuard.lua",
  "lua/ge/extensions/taxiDriver/repairPricing.lua",
  "lua/ge/extensions/taxiDriver/vehicleRepair.lua",
  "lua/vehicle/extensions/taxiDriverTelemetry.lua",
  "lua/vehicle/extensions/taxiDriverAutopilotRecovery.lua",
  "lua/vehicle/extensions/taxiDriverStockAiObserver.lua",
  "lua/vehicle/extensions/taxiDriverCargo.lua",
  "ui/modules/apps/TaxiDriverHUD/app.vue",
  "ui/modules/apps/TaxiDriverHUD/hud-model.js",
  "ui/modules/apps/TaxiDriverHUD/hud-render.js",
  "ui/modules/apps/TaxiDriverHUD/hud-component.js",
  "ui/modules/apps/TaxiDriverHUD/game-bridge.js",
  "ui/modules/apps/TaxiDriverHUD/external/hud.bundle.js",
  "ui/modules/apps/TaxiDriverHUD/external/THIRD-PARTY-NOTICES.txt",
  "ui/modules/apps/TaxiDriverHUD/locales.json",
  "mod_info/TaxiDriver/info.json",
  "mod_info/TaxiDriver/icon.jpg"
)
$readArchive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $entries = @($readArchive.Entries)
  foreach ($entryName in $requiredEntries) {
    if (-not ($entries | Where-Object FullName -eq $entryName)) {
      throw "Missing archive entry: $entryName"
    }
  }
  if ($entries | Where-Object FullName -like "lua/vehicle/extensions/auto/taxiDriver*") {
    throw "TaxiDriver vehicle extensions must remain lazy-loaded, not automatic"
  }
  if ($entries.Count -ne $files.Count) {
    throw "Unexpected archive entry count: $($entries.Count)"
  }
}
finally {
  $readArchive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
if ($InstallDirectory) {
  $resolvedInstallDirectory = (Resolve-Path -LiteralPath $InstallDirectory).Path
  $installedPath = Join-Path $resolvedInstallDirectory "taxidriver.zip"
  Copy-Item -LiteralPath $zipPath -Destination $installedPath -Force
  $installedHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
  if ($hash -ne $installedHash) {
    throw "Installed archive hash mismatch"
  }
  Write-Output "Installed: $installedPath"
}

Write-Output "Archive: $zipPath"
Write-Output "Entries: $($entries.Count)"
Write-Output "SHA256: $hash"
