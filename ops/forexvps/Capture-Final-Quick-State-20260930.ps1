$ErrorActionPreference='Continue'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$root='C:\SolTrade'
function Pair($p){if(Test-Path -LiteralPath $p){$l=@(Get-Content -LiteralPath $p -TotalCount 2);if($l.Count-eq 2){$l|ConvertFrom-Csv|Select-Object -First 1}}}
function Json($p){if(Test-Path -LiteralPath $p){Get-Content -Raw -LiteralPath $p|ConvertFrom-Json}}
function Task($name){try{$t=Get-ScheduledTask -TaskName $name -ErrorAction Stop;$i=Get-ScheduledTaskInfo -InputObject $t;[ordered]@{name=$name;state=[string]$t.State;last_result=$i.LastTaskResult;last_run=[string]$i.LastRunTime;next_run=[string]$i.NextRunTime}}catch{[ordered]@{name=$name;error=$_.Exception.Message}}}
$c="$root\Research\SolTrade-Brain-Collector-V1\MQL5\Files\SolTradeBrainCollectorV1"
$t="$root\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Files\SolTradeFullLifetimeTrackerV1"
$e="$root\Research\SolTrade-Forward-Evidence-Evaluator-V1"
$fx=@();foreach($a in @(@('7196820','fxify-10k'),@('7198096','fxify-100k'))){$s=[IO.File]::ReadAllText("$root\state\$($a[1]).ini");$fx+=@{account=$a[0];enabled_zero=$s-match '(?m)^Enabled=0\r?$';allow_live_zero=$s-match '(?m)^AllowLiveTrading=0\r?$'}}
[ordered]@{utc=[DateTime]::UtcNow.ToString('o');fp_runtime=Pair "$common\SolTradeFastMultiMarketV2\runtime.csv";fxify=$fx;collector=Pair "$c\status\heartbeat.csv";tracker=Pair "$t\status\heartbeat.csv";evaluator=Json "$e\status\heartbeat.json";evaluator_progress=Json "$e\status\run-progress.json";ownership_state=Json "$root\ownership\lease-7404213.json";tasks=@(Task 'SolTrade-AccountOwnership-7404213';Task 'SolTrade-V3-Forward-Evidence-Evaluator-V1';Task 'SolTrade-Watchdog';Task 'SolTrade-Full-Lifetime-Tracker-V1-Watchdog');read_only=$true;orders_sent=0;positions_modified=0}|ConvertTo-Json -Depth 16|Set-Content -Encoding UTF8 (Join-Path $out 'final-quick-state.json')
