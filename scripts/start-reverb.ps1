<#
.SYNOPSIS
    Starts the Laravel Reverb WebSocket server for ChatAPP.
#>

$backendDir = Join-Path $PSScriptRoot "..\backend"

if (-not (Test-Path $backendDir)) {
    Write-Host "[ERROR] Backend folder not found at: $backendDir" -ForegroundColor Red
    exit 1
}

Push-Location $backendDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Starting Laravel Reverb WebSocket Server      " -ForegroundColor Cyan
Write-Host "  Listening on: http://0.0.0.0:8080                      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

php artisan reverb:start --host=0.0.0.0 --port=8080 --debug

Pop-Location
