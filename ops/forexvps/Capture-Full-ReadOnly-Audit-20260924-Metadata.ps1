[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade'
$out=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'remote-output\full-readonly-audit-20260924'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$fp=Join-Path $root 'MT5-FP-DEMO'
$collector=Join-Path $root 'Research\SolTrade-Brain-Collector-V1'
$tracker=Join-Path $root 'Research\SolTrade-Full-Lifetime-Tracker-V1'
$evaluator=Join-Path $root 'Research\SolTrade-Forward-Evidence-Evaluator-V1'
function Hash([string]$p){if(Test-Path -LiteralPath $p){(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}else{$null}}
function Pair([string]$p){if(-not(Test-Path -LiteralPath $p)){return $null};$l=@(Get-Content -LiteralPath $p -TotalCount 2);if($l.Count -ne 2){return $null};$l|ConvertFrom-Csv|Select-Object -First 1}
function Proc([string]$p){@((Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'")|Where-Object{$_.ExecutablePath -eq $p}|ForEach-Object{$_.ProcessId})}
function Task([string]$n){try{$t=Get-ScheduledTask -TaskName $n -ErrorAction Stop;$i=Get-ScheduledTaskInfo -TaskName $n;[ordered]@{state=[string]$t.State;last_result=$i.LastTaskResult;last_run_utc=$i.LastRunTime.ToUniversalTime().ToString('o');next_run_utc=$i.NextRunTime.ToUniversalTime().ToString('o');enabled=$t.Settings.Enabled}}catch{$null}}
$f=$fp+'\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5'
$c=$collector+'\MQL5\Experts\SolTradeBrainCollectorV1.mq5'
$t=$tracker+'\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5'
$fx=@();foreach($x in @(@('7196820','fxify-10k.ini','MT5-FXIFY-10K','SolTradeFastMultiMarketV2F10'),@('7198096','fxify-100k.ini','MT5-FXIFY-100K','SolTradeFastMultiMarketV2F100'))){$p=Join-Path $root ('state\'+$x[1]);$s=if(Test-Path -LiteralPath $p){[IO.File]::ReadAllText($p)}else{''};$fx+=[ordered]@{account=$x[0];startup_hash=Hash $p;enabled_zero=($s -match '(?m)^Enabled=0\r?$');allow_live_zero=($s -match '(?m)^AllowLiveTrading=0\r?$');pid=Proc (Join-Path (Join-Path $root $x[2]) 'terminal64.exe');last_runtime=Pair (Join-Path (Join-Path $common $x[3]) 'runtime.csv')}}
$r=[ordered]@{schema='SOLTRADE_FULL_READONLY_AUDIT_20260924_METADATA_V1';captured_utc=[DateTime]::UtcNow.ToString('o');orders_sent_by_audit=0;positions_modified_by_audit=0;fp=[ordered]@{runtime=Pair (Join-Path (Join-Path $common 'SolTradeFastMultiMarketV2') 'runtime.csv');pid=Proc (Join-Path $fp 'terminal64.exe');source_hash=Hash $f;binary_hash=Hash $f.Replace('.mq5','.ex5');ownership=Task 'SolTrade-AccountOwnership-7404213'};fxify=$fx;collector=[ordered]@{heartbeat=Pair (Join-Path $collector 'MQL5\Files\SolTradeBrainCollectorV1\status\heartbeat.csv');pid=Proc (Join-Path $collector 'terminal64.exe');source_hash=Hash $c;binary_hash=Hash $c.Replace('.mq5','.ex5');watchdog=Task 'SolTrade-Brain-Collector-V1-Watchdog'};tracker=[ordered]@{heartbeat=Pair (Join-Path $tracker 'MQL5\Files\SolTradeFullLifetimeTrackerV1\status\heartbeat.csv');pid=Proc (Join-Path $tracker 'terminal64.exe');source_hash=Hash $t;binary_hash=Hash $t.Replace('.mq5','.ex5');model_hash=Hash (Join-Path $tracker 'MQL5\Experts\SolTradeV3TrackingModel.mqh');candidate_hash=Hash (Join-Path $tracker 'MQL5\Files\SolTradeFullLifetimeTrackerV1\frozen-invalidation-candidates.csv');watchdog=Task 'SolTrade-Full-Lifetime-Tracker-V1-Watchdog'};evaluator=[ordered]@{heartbeat=if(Test-Path (Join-Path $evaluator 'status\heartbeat.json')){Get-Content -Raw (Join-Path $evaluator 'status\heartbeat.json')|ConvertFrom-Json}else{$null};task=Task 'SolTrade-V3-Forward-Evidence-Evaluator-V1'};fp_watchdog=Task 'SolTrade-Watchdog'}
$r|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'snapshot.json')
