<#
.SYNOPSIS
    Starts the Laravel HTTP API server with multi-worker support.
#>

$backendDir = Join-Path $PSScriptRoot "..\backend"

if (-not (Test-Path $backendDir)) {
    Write-Host "[ERROR] Backend folder not found at: $backendDir" -ForegroundColor Red
    exit 1
}

Push-Location $backendDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Starting Laravel HTTP API Server              " -ForegroundColor Cyan
Write-Host "  Listening on: http://0.0.0.0:8000                      " -ForegroundColor Cyan
Write-Host "  Multi-worker: Enabled (PHP_CLI_SERVER_WORKERS=4)        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$env:PHP_CLI_SERVER_WORKERS = "4"
php artisan serve --host=0.0.0.0 --port=8000 --no-reload

Pop-Location
