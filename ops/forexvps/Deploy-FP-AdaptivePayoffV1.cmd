@echo off
copy /y "\\tsclient\SolTrade\Deploy-FP-AdaptivePayoffV1.ps1" "C:\SolTrade\staging\Deploy-FP-AdaptivePayoffV1.ps1" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SolTrade\staging\Deploy-FP-AdaptivePayoffV1.ps1" > "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-deploy-console.txt" 2>&1
echo %ERRORLEVEL%> "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-deploy-exit.txt"
