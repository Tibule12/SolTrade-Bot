@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-FP-M1-Shadow.ps1" > "%~dp0remote-output\fp-m1-shadow-deploy-console.txt" 2>&1
exit /b %errorlevel%
