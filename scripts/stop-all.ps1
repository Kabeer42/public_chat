<#
.SYNOPSIS
    Stops all ChatAPP running services (API, Reverb, Frontend devices) and HotKey listener.
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Stopping All Running Services                 " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Stop Laravel API & Reverb by Port (8000, 8080)
$pids = Get-NetTCPConnection -LocalPort 8000, 8080 -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique

if ($pids) {
    foreach ($p in $pids) {
        Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Stopped server process (PID: $p)" -ForegroundColor Green
    }
} else {
    Write-Host "[*] No active server processes found on ports 8000/8080." -ForegroundColor Gray
}

# 2. Close terminal windows titled ChatAPP
Get-Process cmd, powershell -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like "ChatAPP*" } |
    ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Closed terminal: $($_.MainWindowTitle)" -ForegroundColor Green
    }

# 3. Stop ChatAppHotKey background listener
$hotkeyProc = Get-Process "ChatAppHotKey" -ErrorAction SilentlyContinue
if ($hotkeyProc) {
    Stop-Process -Id $hotkeyProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Stopped ChatAppHotKey background listener." -ForegroundColor Green
} else {
    Write-Host "[*] HotKey listener is not currently running." -ForegroundColor Gray
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  All ChatAPP services have been stopped successfully!    " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
