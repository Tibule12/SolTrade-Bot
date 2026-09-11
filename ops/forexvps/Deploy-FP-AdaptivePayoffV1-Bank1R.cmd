@echo off
copy /y "\\tsclient\SolTrade\Deploy-FP-AdaptivePayoffV1-Bank1R.ps1" "C:\SolTrade\staging\Deploy-FP-AdaptivePayoffV1-Bank1R.ps1" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SolTrade\staging\Deploy-FP-AdaptivePayoffV1-Bank1R.ps1" > "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-bank1r-deploy-console.txt" 2>&1
echo %ERRORLEVEL%> "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-bank1r-deploy-exit.txt"
