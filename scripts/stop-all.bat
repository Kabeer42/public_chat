@echo off
title ChatAPP - Stop All Services
powershell -ExecutionPolicy Bypass -File "%~dp0stop-all.ps1"
pause
