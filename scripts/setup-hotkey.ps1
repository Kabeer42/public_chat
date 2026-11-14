<#
.SYNOPSIS
    Installs and launches the ChatAPP HotKey service (Win + Shift + K).
    Adds it to Windows Startup so it persists after reboot.
#>

$scriptsDir = $PSScriptRoot
$exePath = Join-Path $scriptsDir "ChatAppHotKey.exe"
$startupFolder = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
$shortcutPath = Join-Path $startupFolder "ChatAPP-HotKey.lnk"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Registering Shortcut: Win + Shift + K         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Stop any existing listener process
Get-Process "ChatAppHotKey" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$oldPs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*hotkey-listener.ps1*" }
if ($oldPs) {
    $oldPs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# 2. Create shortcut in Windows Startup directory and Desktop
try {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $scriptsDir
    $shortcut.Description = "ChatAPP Win+Shift+K HotKey Listener"
    $shortcut.Save()
    Write-Host "[+] Startup shortcut created: $shortcutPath" -ForegroundColor Green

    $desktopFolder = [System.Environment]::GetFolderPath('Desktop')
    $deskShortcut = $wsh.CreateShortcut((Join-Path $desktopFolder "ChatAPP - Start All.lnk"))
    $deskShortcut.TargetPath = (Join-Path $scriptsDir "start-all.bat")
    $deskShortcut.WorkingDirectory = $scriptsDir
    $deskShortcut.Hotkey = "Ctrl+Alt+K"
    $deskShortcut.Description = "Launch ChatAPP Backend, Reverb Socket, and Frontend Devices"
    $deskShortcut.Save()
    Write-Host "[+] Desktop shortcut created (also supports Ctrl+Alt+K natively)" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not create shortcuts: $_" -ForegroundColor Yellow
}

# 3. Start the hotkey executable now detached
Write-Host "[+] Starting ChatAppHotKey.exe now..." -ForegroundColor Green
Start-Process cmd.exe -ArgumentList "/c start `"`" `"$exePath`"" -WorkingDirectory $scriptsDir

Start-Sleep -Milliseconds 800

$logPath = Join-Path $scriptsDir "hotkey.log"
if (Test-Path $logPath) {
    Write-Host "--- HotKey Service Status ---" -ForegroundColor Yellow
    Get-Content $logPath -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  SUCCESS! Hotkey [Win + Shift + K] is now ACTIVE!       " -ForegroundColor Green
Write-Host "  Press Win + Shift + K anywhere to launch ChatAPP.       " -ForegroundColor Green
Write-Host "  (Fallback: Ctrl + Shift + K or double click tray icon) " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
