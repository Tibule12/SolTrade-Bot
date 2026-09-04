@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compile-Evidence-Exit-V202.ps1" > "%~dp0remote-output\evidence-exit-v202-compile-console.txt" 2>&1
exit /b %errorlevel%
