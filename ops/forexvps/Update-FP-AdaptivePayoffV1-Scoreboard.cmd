@echo off
copy /y "\\tsclient\SolTrade\Publish-FP-AdaptivePayoffV1-Scoreboard.ps1" "C:\SolTrade\Publish-FP-AdaptivePayoffV1-Scoreboard.ps1" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\SolTrade\Publish-FP-AdaptivePayoffV1-Scoreboard.ps1" > "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-scoreboard-update-console.txt" 2>&1
echo %ERRORLEVEL%> "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-scoreboard-update-exit.txt"
