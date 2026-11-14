@echo off
title ChatAPP - Cloudflare Tunnel Launcher
powershell -ExecutionPolicy Bypass -File "%~dp0start-cloudflare-tunnel.ps1"
pause
