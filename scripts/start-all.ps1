<#
.SYNOPSIS
    Starts backend API, Reverb WebSocket, and Flutter frontend with interactive device selection.
    Automatically connects to local emulators (MEmu, LDPlayer, Nox) and handles offline states.
#>

$scriptsDir = $PSScriptRoot
$backendDir = Join-Path $scriptsDir "..\backend"
$frontendDir = Join-Path $scriptsDir "..\frontend"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Master Multi-Service & Device Launcher        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Start Laravel HTTP API Server
Write-Host "[1/2] Launching Laravel API Server (Port 8000)..." -ForegroundColor Green
Start-Process cmd.exe -ArgumentList "/c title ChatAPP - API Server && cd /d `"$scriptsDir`" && call start-api.bat"
Start-Sleep -Milliseconds 400

# 2. Start Laravel Reverb WebSocket Server
Write-Host "[2/2] Launching Laravel Reverb WebSocket Server (Port 8080)..." -ForegroundColor Green
Start-Process cmd.exe -ArgumentList "/c title ChatAPP - Reverb WebSocket && cd /d `"$scriptsDir`" && call start-reverb.bat"
Start-Sleep -Milliseconds 400

# Function to auto-connect and detect devices
function Get-DevicesState {
    # 1. Auto-connect common emulator ports (MEmu, LDPlayer, Nox, BlueStacks)
    $emulatorPorts = @(21503, 21513, 21523, 5555, 5557, 62001, 62025)
    foreach ($p in $emulatorPorts) {
        $listen = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($listen) {
            adb connect "127.0.0.1:$p" 2>$null | Out-Null
        }
    }

    $online = @()
    $offline = @()

    try {
        $adbLines = adb devices -l 2>$null
        if ($adbLines) {
            foreach ($line in $adbLines) {
                if ($line -match '^([^\s]+)\s+device\s+(.*)$') {
                    $id = $Matches[1]
                    $rest = $Matches[2]
                    $model = if ($rest -match 'model:([^\s]+)') { $Matches[1] } else { "Android" }
                    $online += [PSCustomObject]@{
                        Id = $id
                        Name = $model
                        Info = "$model ($id)"
                    }
                } elseif ($line -match '^([^\s]+)\s+offline\b') {
                    $offId = $Matches[1]
                    # Attempt automatic reconnect
                    adb -s $offId reconnect 2>$null | Out-Null
                    $offline += $offId
                }
            }
        }
    } catch {}

    # If ADB found nothing, check flutter devices (excluding browsers/desktop)
    if ($online.Count -eq 0) {
        try {
            $flutterJson = flutter devices --machine 2>$null | ConvertFrom-Json
            $mobiles = @($flutterJson | Where-Object { $_.isSupported -and $_.id -notin @('chrome','edge','windows') })
            foreach ($m in $mobiles) {
                $online += [PSCustomObject]@{
                    Id = $m.id
                    Name = $m.name
                    Info = "$($m.name) ($($m.id))"
                }
            }
        } catch {}
    }

    return @{
        Online = $online
        Offline = $offline
    }
}

# Scan devices loop
$state = Get-DevicesState
$devices = $state.Online
$offlineDevs = $state.Offline

while ($devices.Count -eq 0) {
    Write-Host "`n==========================================================" -ForegroundColor Yellow
    Write-Host "  No Online Mobile Devices or Emulators Found!            " -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    
    if ($offlineDevs.Count -gt 0) {
        Write-Host "[!] Detected OFFLINE emulator(s): $($offlineDevs -join ', ')" -ForegroundColor Red
        Write-Host "    -> MEmu / Emulator window me ja kar us instance ko Restart karein ya unlock karein." -ForegroundColor Yellow
    } else {
        Write-Host "[!] Koi mobile device ya emulator connect nahi mila." -ForegroundColor Red
        Write-Host "    -> Phone connect karein (USB Debugging on) ya MEmu emulator start karein." -ForegroundColor Yellow
    }

    Write-Host ""
    $resp = Read-Host "Press ENTER to re-scan devices, or 'q' to skip frontend"
    if ($resp.Trim() -eq 'q') {
        Write-Host "Skipping frontend. API and Reverb servers are running." -ForegroundColor Cyan
        exit 0
    }

    $state = Get-DevicesState
    $devices = $state.Online
    $offlineDevs = $state.Offline
}

# Display Menu
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  Connected Devices Selection                             " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Found $($devices.Count) online device(s):`n" -ForegroundColor Green

# Show offline warning if any emulator is offline
if ($offlineDevs.Count -gt 0) {
    Write-Host "[!] Note: $($offlineDevs -join ', ') is currently OFFLINE in MEmu (Needs restart)." -ForegroundColor Yellow
    Write-Host ""
}

# Option 1: ALL Devices
Write-Host "  [1] ALL Online Devices (Run on all $($devices.Count) simultaneously)" -ForegroundColor Green

# Individual Options: 2, 3, 4...
for ($i = 0; $i -lt $devices.Count; $i++) {
    $optNum = $i + 2
    Write-Host "  [$optNum] $($devices[$i].Info)" -ForegroundColor White
}

Write-Host ""
$promptRange = if ($devices.Count -eq 1) { "1-2" } else { "1-$($devices.Count + 1)" }
$choice = Read-Host "Select an option [$promptRange] (Default: 1 for ALL)"

# Determine which devices to run
$selectedDevices = @()

if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim() -eq "1") {
    $selectedDevices = $devices
    Write-Host "`n[+] Selected: ALL ($($devices.Count)) online device(s)" -ForegroundColor Green
} else {
    $chosenIndices = $choice -split '[, ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    
    foreach ($num in $chosenIndices) {
        $devIndex = $num - 2
        if ($devIndex -ge 0 -and $devIndex -lt $devices.Count) {
            $selectedDevices += $devices[$devIndex]
        }
    }

    if ($selectedDevices.Count -eq 0) {
        Write-Host "[!] Invalid choice '$choice'. Defaulting to ALL devices." -ForegroundColor Yellow
        $selectedDevices = $devices
    }
}

# Launch Flutter on Selected Devices
Write-Host "`nLaunching Flutter on selected device(s)..." -ForegroundColor Cyan

foreach ($dev in $selectedDevices) {
    Write-Host "  -> Starting Flutter on $($dev.Info)..." -ForegroundColor Yellow
    Start-Process cmd.exe -ArgumentList "/k title ChatAPP - Frontend [$($dev.Id)] && cd /d `"$frontendDir`" && flutter run -d $($dev.Id)"
    
    if ($selectedDevices.Count -gt 1) {
        Start-Sleep -Milliseconds 2500
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  SUCCESS: All selected services and devices are running! " -ForegroundColor Green
Write-Host "  Press 'r' in each device terminal to trigger Hot Reload." -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
