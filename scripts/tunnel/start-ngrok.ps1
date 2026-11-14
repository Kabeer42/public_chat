<#
.SYNOPSIS
    Starts Ngrok Tunnels for ChatAPP (API on 8000, Reverb on 8080)
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Ngrok Multi-Port Tunnel Launcher             " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ngrok = Get-Command ngrok -ErrorAction SilentlyContinue

if (-not $ngrok) {
    Write-Host "[ERROR] 'ngrok' CLI is not found in your PATH." -ForegroundColor Red
    Write-Host "Install via winget: winget install Inconshreveable.Ngrok" -ForegroundColor Yellow
    exit 1
}

$configFile = Join-Path $PSScriptRoot "ngrok-config.yml"

if (Test-Path $configFile) {
    Write-Host "[INFO] Starting Ngrok tunnels defined in ngrok-config.yml..." -ForegroundColor Green
    & ngrok start --all --config $configFile
} else {
    Write-Host "[INFO] No ngrok-config.yml found. Starting tunnel on port 8000..." -ForegroundColor Yellow
    Write-Host "[TIP] Copy ngrok-config.example.yml to ngrok-config.yml to tunnel both HTTP (8000) and WebSockets (8080)!" -ForegroundColor DarkGray
    & ngrok http 8000
}
