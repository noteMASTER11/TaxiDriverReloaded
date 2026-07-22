param(
  [string]$InstallDirectory = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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
  $files = @((Join-Path $root "CREDITS.txt"))
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
  "lua/ge/extensions/taxiDriver/taxiDriver.lua",
  "lua/ge/extensions/taxiDriver/autopilot.lua",
  "lua/ge/extensions/taxiDriver/aiLogger.lua",
  "lua/ge/extensions/taxiDriver/networkAddress.lua",
  "lua/ge/extensions/taxiDriver/nextOfferGuard.lua",
  "lua/ge/extensions/taxiDriver/fleetManager.lua",
  "lua/ge/extensions/taxiDriver/fleetWorker.lua",
  "lua/ge/extensions/taxiDriver/autopilotPerception.lua",
  "lua/ge/extensions/taxiDriver/persistence.lua",
  "lua/ge/extensions/taxiDriver/routePlanner.lua",
  "lua/ge/extensions/taxiDriver/hudPublisher.lua",
  "lua/ge/extensions/taxiDriver/logger.lua",
  "lua/ge/extensions/taxiDriver/shiftTracker.lua",
  "lua/ge/extensions/taxiDriver/shiftHistory.lua",
  "lua/ge/extensions/taxiDriver/tripEvents.lua",
  "lua/ge/extensions/taxiDriver/vehicleControl.lua",
  "lua/ge/extensions/taxiDriver/vehicleHistory.lua",
  "lua/ge/extensions/taxiDriver/vehicleScanGuard.lua",
  "lua/vehicle/extensions/taxiDriverTelemetry.lua",
  "lua/vehicle/extensions/taxiDriverAutopilotRecovery.lua",
  "lua/vehicle/extensions/taxiDriverCargo.lua",
  "ui/modules/apps/TaxiDriverHUD/app.html",
  "ui/modules/apps/TaxiDriverHUD/app.js",
  "ui/modules/apps/TaxiDriverHUD/locales.json",
  "mod_info/TaxiDriver/info.json"
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
  if ($entries.Count -ne 49) {
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
