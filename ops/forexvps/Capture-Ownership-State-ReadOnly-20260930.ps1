$ErrorActionPreference='Continue'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$root='C:\SolTrade'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\SolTradeFastMultiMarketV2'
function Save($name,$value){$value|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $out $name)}
$s="$root\ownership\lease-7404213.json"
if(Test-Path -LiteralPath $s){Copy-Item -LiteralPath $s -Destination (Join-Path $out 'fp-ownership-state.json') -Force}
$a="$root\ownership\lease-7404213-audit.jsonl"
if(Test-Path -LiteralPath $a){Get-Content -LiteralPath $a -Tail 1000|Set-Content -Encoding UTF8 (Join-Path $out 'fp-ownership-audit-tail.jsonl')}
$exchange="$root\MT5-FP-DEMO\MQL5\Files\SolTradeOwnership"
$files=@(Get-ChildItem -LiteralPath $exchange -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -notmatch '^claim-secret|secret'}|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 30|ForEach-Object{[ordered]@{name=$_.Name;bytes=$_.Length;modified_utc=$_.LastWriteTimeUtc.ToString('o');contents=@(Get-Content -LiteralPath $_.FullName|Where-Object{$_ -notmatch '^(claim_secret|secret|password)='})}})
Save 'fp-ownership-exchange.json' $files
$actual=@(Get-ChildItem -LiteralPath "$root\MT5-FP-DEMO\MQL5\Files" -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '^(positions|position|account|deals|history).*\.(csv|json)$'}|Select-Object FullName,Length,LastWriteTimeUtc)
Save 'fp-export-file-inventory.json' $actual
$task=Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -ErrorAction SilentlyContinue
if($task){$i=Get-ScheduledTaskInfo -InputObject $task;Save 'fp-ownership-task.json' ([ordered]@{state=[string]$task.State;last_result=$i.LastTaskResult;last_run=[string]$i.LastRunTime;next_run=[string]$i.NextRunTime;priority=$task.Settings.Priority;actions=@($task.Actions|Select-Object Execute,Arguments)})}
Save 'fp-ownership-followup-receipt.json' ([ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');read_only=$true;orders_sent=0;position_modifications=0})
