@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Capture-FP-M1-Shadow-Status.ps1" > "%~dp0remote-output\fp-m1-shadow-status-console.txt" 2>&1
exit /b %errorlevel%
