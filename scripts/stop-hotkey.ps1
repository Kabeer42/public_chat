<#
.SYNOPSIS
    Stops the ChatAPP hotkey listener and removes it from Windows Startup.
#>

$startupFolder = [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup")
$shortcutPath = Join-Path $startupFolder "ChatAPP-HotKey.lnk"

# Stop running process
Get-Process "ChatAppHotKey" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$oldPs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*hotkey-listener.ps1*" }
if ($oldPs) {
    $oldPs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
Write-Host "[+] Stopped ChatAPP HotKey service." -ForegroundColor Green

# Remove startup and desktop shortcuts
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "[+] Removed shortcut from Startup folder." -ForegroundColor Green
}

$desktopShortcut = Join-Path ([System.Environment]::GetFolderPath('Desktop')) "ChatAPP - Start All.lnk"
if (Test-Path $desktopShortcut) {
    Remove-Item $desktopShortcut -Force
    Write-Host "[+] Removed shortcut from Desktop." -ForegroundColor Green
}
