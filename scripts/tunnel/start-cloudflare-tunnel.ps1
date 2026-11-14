<#
.SYNOPSIS
    Starts Cloudflare Tunnel for ChatAPP (API on 8000, Reverb on 8080)
.DESCRIPTION
    Checks if cloudflared is installed and launches the tunnel.
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  ChatAPP - Cloudflare Tunnel Launcher                   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue

if (-not $cloudflared) {
    Write-Host "[ERROR] 'cloudflared' CLI is not found in your PATH." -ForegroundColor Red
    Write-Host "Download it from: https://github.com/cloudflare/cloudflared/releases" -ForegroundColor Yellow
    Write-Host "Or install via winget: winget install Cloudflare.cloudflared" -ForegroundColor Yellow
    exit 1
}

$configFile = Join-Path $PSScriptRoot "config.yml"

if (Test-Path $configFile) {
    Write-Host "[INFO] Starting named Cloudflare Tunnel with config.yml..." -ForegroundColor Green
    & cloudflared tunnel --config $configFile run
} else {
    Write-Host "[INFO] No config.yml found. Starting quick ad-hoc HTTP tunnel for port 8000..." -ForegroundColor Yellow
    Write-Host "[TIP] Copy cloudflared-config.example.yml to config.yml for full WebSocket routing!" -ForegroundColor DarkGray
    & cloudflared tunnel --url http://127.0.0.1:8000
}
