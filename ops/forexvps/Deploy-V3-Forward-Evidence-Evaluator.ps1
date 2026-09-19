[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade'
$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$repo=(Resolve-Path (Join-Path $share '..\..')).Path
$payload=Join-Path $repo 'tools\forward_evidence'
$output=Join-Path $share 'remote-output\v3-forward-evidence-evaluator-v1'
$evaluatorHome="$root\Research\SolTrade-Forward-Evidence-Evaluator-V1"
$tracker="$root\Research\SolTrade-Full-Lifetime-Tracker-V1"
$fp="$root\MT5-FP-DEMO"
$collector="$root\Research\SolTrade-Brain-Collector-V1"
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$taskName='SolTrade-V3-Forward-Evidence-Evaluator-V1'
$runner=Join-Path $share 'Run-V3-Forward-Evidence-Evaluator.ps1'
$expected=Join-Path $payload 'expected-identities.json'
$schema=Join-Path $payload 'output-schema.json'
$model=Join-Path $repo 'reports\fast-multi-market-v2\full-lifetime-causal-tracking-20260919\frozen-tracking-model.json'
$receipt=[ordered]@{schema='SOLTRADE_V3_FORWARD_EVALUATOR_DEPLOYMENT_V1';status='PREPARING';started_utc=[DateTime]::UtcNow.ToString('o');orders_sent=$false;positions_modified=$false;trading_logic_changed=$false;thresholds_changed=$false;candidate_selection_performed=$false;error=$null}

function Sha([string]$p){if(-not(Test-Path -LiteralPath $p)){return $null};(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}
function Save-Receipt{$receipt|ConvertTo-Json -Depth 30|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $output 'deployment.json')}
function Pair([string]$p){if(-not(Test-Path -LiteralPath $p)){return $null};$x=@(Get-Content -LiteralPath $p -TotalCount 2);if($x.Count -ne 2){return $null};$x|ConvertFrom-Csv|Select-Object -First 1}
function Processes([string]$path){@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object{$_.ExecutablePath -eq $path}|ForEach-Object ProcessId)}
function Runtime([string]$name){Pair (Join-Path $common "$name\runtime.csv")}
function Snapshot{
 $fpSource="$fp\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5";$fpBinary=$fpSource.Replace('.mq5','.ex5')
 $trackerSource="$tracker\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5";$trackerBinary=$trackerSource.Replace('.mq5','.ex5')
 $collectorSource="$collector\MQL5\Experts\SolTradeBrainCollectorV1.mq5";$collectorBinary=$collectorSource.Replace('.mq5','.ex5')
 [ordered]@{
  fp=[ordered]@{source_sha256=Sha $fpSource;binary_sha256=Sha $fpBinary;pids=Processes "$fp\terminal64.exe";runtime=Runtime 'SolTradeFastMultiMarketV2'}
  fxify=@(
   [ordered]@{account='7196820';startup="$root\state\fxify-10k.ini";startup_sha256=Sha "$root\state\fxify-10k.ini";text=[IO.File]::ReadAllText("$root\state\fxify-10k.ini");pids=Processes "$root\MT5-FXIFY-10K\terminal64.exe"},
   [ordered]@{account='7198096';startup="$root\state\fxify-100k.ini";startup_sha256=Sha "$root\state\fxify-100k.ini";text=[IO.File]::ReadAllText("$root\state\fxify-100k.ini");pids=Processes "$root\MT5-FXIFY-100K\terminal64.exe"}
  )
  collector=[ordered]@{source_sha256=Sha $collectorSource;binary_sha256=Sha $collectorBinary;pids=Processes "$collector\terminal64.exe";heartbeat=Pair "$collector\MQL5\Files\SolTradeBrainCollectorV1\status\heartbeat.csv"}
  tracker=[ordered]@{source_sha256=Sha $trackerSource;binary_sha256=Sha $trackerBinary;model_include_sha256=Sha "$tracker\MQL5\Experts\SolTradeV3TrackingModel.mqh";pids=Processes "$tracker\terminal64.exe";heartbeat=Pair "$tracker\MQL5\Files\SolTradeFullLifetimeTrackerV1\status\heartbeat.csv";candidate_sha256=Sha "$tracker\MQL5\Files\SolTradeFullLifetimeTrackerV1\frozen-invalidation-candidates.csv"}
 }
}

New-Item -ItemType Directory -Force -Path $output|Out-Null
try{
 foreach($p in @($runner,$expected,$schema,$model)){if(-not(Test-Path -LiteralPath $p)){throw "Missing payload: $p"}}
 $ids=Get-Content -Raw -LiteralPath $expected|ConvertFrom-Json
 if((Sha $model) -ne $ids.frozen_model_json_sha256){throw 'Frozen model JSON hash differs from expected identity'}
 $before=Snapshot;$receipt.before=$before
 if($before.fp.source_sha256 -ne $ids.fp_source_sha256 -or $before.fp.binary_sha256 -ne $ids.fp_binary_sha256){throw 'FP frozen hash mismatch before deployment'}
 if(@($before.fp.pids).Count -ne 1){throw 'FP process count is not one'}
 foreach($fx in $before.fxify){if($fx.text -notmatch '(?m)^Enabled=0\r?$' -or $fx.text -notmatch '(?m)^AllowLiveTrading=0\r?$'){throw "FXIFY is not disabled: $($fx.account)"}}
 if($before.collector.heartbeat.order_capability -ne 'false' -or $before.collector.heartbeat.terminal_trade_allowed -ne 'false' -or $before.collector.heartbeat.mql_trade_allowed -ne 'false'){throw 'Collector orderless invariant failed'}
 if($before.tracker.heartbeat.order_capability -ne 'false' -or $before.tracker.heartbeat.terminal_trade_allowed -ne 'false' -or $before.tracker.heartbeat.mql_trade_allowed -ne 'false'){throw 'Tracker orderless invariant failed'}
 if($before.tracker.source_sha256 -ne $ids.tracker_source_sha256 -or $before.tracker.binary_sha256 -ne $ids.tracker_binary_sha256 -or $before.tracker.model_include_sha256 -ne $ids.tracker_model_include_sha256 -or $before.tracker.candidate_sha256 -ne $ids.candidate_receipt_sha256){throw 'Tracker frozen identity mismatch before deployment'}
 $scriptText=[IO.File]::ReadAllText($runner);$operationalText=($scriptText -split "`r?`n"|Where-Object{$_ -notmatch '^\s*\$patterns='}) -join "`n"
 foreach($pattern in @('#include\s*<Trade/','\bCTrade\b','\bOrderSend(?:Async)?\s*\(','\bMqlTradeRequest\b','\bTRADE_ACTION_','\bPositionClose\s*\(','\bPositionModify\s*\(','\bOrderDelete\s*\(')){if($operationalText -match $pattern){throw "Evaluator contains forbidden trade API: $pattern"}}

 if(Test-Path -LiteralPath $evaluatorHome){$backup="$root\backups\v3-forward-evaluator-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))";New-Item -ItemType Directory -Force -Path $backup|Out-Null;Copy-Item -Recurse -Force -LiteralPath $evaluatorHome -Destination $backup;$receipt.backup=$backup}
 New-Item -ItemType Directory -Force -Path $evaluatorHome,"$evaluatorHome\output\daily","$evaluatorHome\status","$evaluatorHome\state"|Out-Null
 Copy-Item -Force -LiteralPath $runner -Destination "$evaluatorHome\Run-V3-Forward-Evidence-Evaluator.ps1"
 Copy-Item -Force -LiteralPath $expected -Destination "$evaluatorHome\expected-identities.json"
 Copy-Item -Force -LiteralPath $schema -Destination "$evaluatorHome\output-schema.json"
 Copy-Item -Force -LiteralPath $model -Destination "$evaluatorHome\frozen-tracking-model.json"
 $selfTest=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$evaluatorHome\Run-V3-Forward-Evidence-Evaluator.ps1" -SelfTest
 $self=$selfTest|ConvertFrom-Json;if($self.status -ne 'PASS'){throw 'Evaluator self-test failed'}
 $selfTest|Set-Content -Encoding UTF8 -LiteralPath "$output\self-test.json"
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$evaluatorHome\Run-V3-Forward-Evidence-Evaluator.ps1"
 if($LASTEXITCODE -ne 0){throw "Initial evaluator run failed with $LASTEXITCODE"}
 $heartbeat=Get-Content -Raw -LiteralPath "$evaluatorHome\status\heartbeat.json"|ConvertFrom-Json
 if($heartbeat.status -ne 'WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE' -or $heartbeat.integrity_status -ne 'CLEAN' -or $heartbeat.order_capability -ne $false){throw "Unexpected initial evaluator heartbeat: $($heartbeat.status)"}

 if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}
 $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$evaluatorHome\Run-V3-Forward-Evidence-Evaluator.ps1`""
 $startup=New-ScheduledTaskTrigger -AtStartup
 $repeating=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
 $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
 Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($startup,$repeating) -Settings $settings -RunLevel Highest -User 'SYSTEM' -Force|Out-Null
 Start-ScheduledTask -TaskName $taskName
 $deadline=[DateTime]::UtcNow.AddSeconds(30);do{Start-Sleep -Seconds 1;$task=Get-ScheduledTask -TaskName $taskName;$taskInfo=Get-ScheduledTaskInfo -TaskName $taskName}while($task.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
 if($task.State -eq 'Running' -or $taskInfo.LastTaskResult -ne 0){throw "Scheduled evaluator failed: state=$($task.State) result=$($taskInfo.LastTaskResult)"}
 $receipt.schedule=[ordered]@{task_name=$taskName;state=[string]$task.State;last_result=$taskInfo.LastTaskResult;run_as='SYSTEM';startup_trigger=$true;interval_minutes=5;multiple_instances='IgnoreNew';execution_time_limit_minutes=4;next_run_time=$taskInfo.NextRunTime.ToUniversalTime().ToString('o')}

 $after=Snapshot;$receipt.after=$after
 if($after.fp.source_sha256 -ne $before.fp.source_sha256 -or $after.fp.binary_sha256 -ne $before.fp.binary_sha256 -or ($after.fp.pids -join ',') -ne ($before.fp.pids -join ',')){throw 'FP changed during evaluator deployment'}
 for($i=0;$i -lt 2;$i++){if($after.fxify[$i].startup_sha256 -ne $before.fxify[$i].startup_sha256 -or $after.fxify[$i].text -notmatch '(?m)^Enabled=0\r?$' -or $after.fxify[$i].text -notmatch '(?m)^AllowLiveTrading=0\r?$'){throw "FXIFY changed or resumed: $($after.fxify[$i].account)"}}
 if($after.collector.source_sha256 -ne $before.collector.source_sha256 -or $after.collector.binary_sha256 -ne $before.collector.binary_sha256 -or ($after.collector.pids -join ',') -ne ($before.collector.pids -join ',') -or $after.collector.heartbeat.order_capability -ne 'false'){throw 'Original collector changed'}
 if($after.tracker.source_sha256 -ne $before.tracker.source_sha256 -or $after.tracker.binary_sha256 -ne $before.tracker.binary_sha256 -or $after.tracker.model_include_sha256 -ne $before.tracker.model_include_sha256 -or $after.tracker.candidate_sha256 -ne $before.tracker.candidate_sha256 -or ($after.tracker.pids -join ',') -ne ($before.tracker.pids -join ',') -or $after.tracker.heartbeat.order_capability -ne 'false'){throw 'Full-lifetime tracker changed'}
 $finalHeartbeat=Get-Content -Raw -LiteralPath "$evaluatorHome\status\heartbeat.json"|ConvertFrom-Json;$integrity=Get-Content -Raw -LiteralPath "$evaluatorHome\output\integrity-receipt.json"|ConvertFrom-Json
 if($finalHeartbeat.status -ne 'WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE' -or $integrity.status -ne 'CLEAN'){throw 'Final evaluator state is not clean and waiting'}
 foreach($p in @('Run-V3-Forward-Evidence-Evaluator.ps1','expected-identities.json','output-schema.json','frozen-tracking-model.json')){Copy-Item -Force -LiteralPath (Join-Path $evaluatorHome $p) -Destination (Join-Path $output $p)}
 Get-ChildItem -LiteralPath "$evaluatorHome\output" -Force|ForEach-Object{Copy-Item -Recurse -Force -LiteralPath $_.FullName -Destination $output}
 Copy-Item -Force -LiteralPath "$evaluatorHome\status\heartbeat.json" -Destination "$output\heartbeat.json"
 Copy-Item -Force -LiteralPath "$evaluatorHome\state\sequence.json" -Destination "$output\sequence.json"
 $receipt.evaluator=[ordered]@{home=$evaluatorHome;source_sha256=Sha "$evaluatorHome\Run-V3-Forward-Evidence-Evaluator.ps1";expected_identities_sha256=Sha "$evaluatorHome\expected-identities.json";output_schema_sha256=Sha "$evaluatorHome\output-schema.json";frozen_model_sha256=Sha "$evaluatorHome\frozen-tracking-model.json";heartbeat=$finalHeartbeat;integrity_status=$integrity.status;trade_api_scan='PASS';order_capability=$false;deployment_capability=$false;tuning_enabled=$false}
 $receipt.fp_untouched=$true;$receipt.fxify_remained_paused=$true;$receipt.original_collector_untouched=$true;$receipt.full_lifetime_tracker_untouched=$true;$receipt.production_files_modified=$false;$receipt.orders_sent=$false;$receipt.positions_modified=$false;$receipt.status='DEPLOYED_CLEAN_WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE'
}catch{$receipt.status='FAILED';$receipt.error=$_.Exception.Message}
finally{$receipt.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Receipt}
if($receipt.status -ne 'DEPLOYED_CLEAN_WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE'){throw $receipt.error}
$receipt|ConvertTo-Json -Depth 30
