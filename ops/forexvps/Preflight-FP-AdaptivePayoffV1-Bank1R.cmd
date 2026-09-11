@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\tsclient\SolTrade\Preflight-FP-AdaptivePayoffV1-Bank1R.ps1" > "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-bank1r-preflight-console.txt" 2>&1
echo %ERRORLEVEL%> "\\tsclient\SolTrade\remote-output\fp-adaptive-payoff-v1-bank1r-preflight-exit.txt"
