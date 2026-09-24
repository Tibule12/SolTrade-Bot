[CmdletBinding()]
param([switch]$ReuseValidatedRun)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$evaluatorHome='C:\SolTrade\Research\SolTrade-Forward-Evidence-Evaluator-V1'
$taskName='SolTrade-V3-Forward-Evidence-Evaluator-V1'
$source=Join-Path $PSScriptRoot 'Run-V3-Forward-Evidence-Evaluator.ps1'
$destination=Join-Path $evaluatorHome 'Run-V3-Forward-Evidence-Evaluator.ps1'
$out=Join-Path $PSScriptRoot 'remote-output\evaluator-repair-20260924'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$backup="C:\SolTrade\backups\forward-evaluator-repair-$stamp"
$receipt=[ordered]@{schema='SOLTRADE_EVALUATOR_REPAIR_20260924_V1';status='PREPARING';started_utc=[DateTime]::UtcNow.ToString('o');orders_sent_by_repair=0;positions_modified_by_repair=0;trading_logic_changed=$false;backup=$backup}
$taskDisabled=$false;$replaced=$false;$priorityChanged=$false
function Sha([string]$Path){if(Test-Path -LiteralPath $Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}else{$null}}
function Json([string]$Path){if(Test-Path -LiteralPath $Path){Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json}else{$null}}
function Pair([string]$Path){if(Test-Path -LiteralPath $Path){$lines=@(Get-Content -LiteralPath $Path -TotalCount 2);if($lines.Count-eq 2){$lines|ConvertFrom-Csv|Select-Object -First 1}}}
function Save{$receipt|ConvertTo-Json -Depth 30|Set-Content -Encoding UTF8 -LiteralPath "$out\deployment.json"}
function Snapshot{
 $processes=@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'")
 $identities=[ordered]@{}
 foreach($item in @(
  @('fp','C:\SolTrade\MT5-FP-DEMO','MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5'),
  @('collector','C:\SolTrade\Research\SolTrade-Brain-Collector-V1','MQL5\Experts\SolTradeBrainCollectorV1.mq5'),
  @('tracker','C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1','MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5'))){
  $p=Join-Path $item[1] $item[2]
  $identities[$item[0]]=[ordered]@{source_sha256=Sha $p;binary_sha256=Sha ($p.Replace('.mq5','.ex5'));pids=@($processes|Where-Object{$_.ExecutablePath-eq (Join-Path $item[1] 'terminal64.exe')}|ForEach-Object ProcessId)}
 }
 $identities.tracker.model_include_sha256=Sha 'C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Experts\SolTradeV3TrackingModel.mqh'
 $identities.tracker.candidates_sha256=Sha 'C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Files\SolTradeFullLifetimeTrackerV1\frozen-invalidation-candidates.csv'
 $config=[ordered]@{}
 foreach($dir in @('C:\SolTrade\state','C:\SolTrade\MT5-FP-DEMO\MQL5\Profiles\Presets','C:\SolTrade\MT5-FXIFY-10K\MQL5\Profiles\Presets','C:\SolTrade\MT5-FXIFY-100K\MQL5\Profiles\Presets','C:\SolTrade\Research\SolTrade-Brain-Collector-V1\MQL5\Profiles\Presets','C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Profiles\Presets')){
  if(Test-Path -LiteralPath $dir){foreach($f in @(Get-ChildItem -LiteralPath $dir -File|Where-Object{$_.Extension-in @('.ini','.set')})){$config[$f.FullName]=Sha $f.FullName}}
 }
 $fx=@();foreach($name in @('fxify-10k','fxify-100k')){$p="C:\SolTrade\state\$name.ini";$text=[IO.File]::ReadAllText($p);$fx+=[ordered]@{name=$name;sha256=Sha $p;enabled_zero=($text-match '(?m)^Enabled=0\r?$');allow_live_zero=($text-match '(?m)^AllowLiveTrading=0\r?$')}}
 [ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');identities=$identities;configuration_hashes=$config;fxify=$fx;collector_heartbeat=Pair 'C:\SolTrade\Research\SolTrade-Brain-Collector-V1\MQL5\Files\SolTradeBrainCollectorV1\status\heartbeat.csv';tracker_heartbeat=Pair 'C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1\MQL5\Files\SolTradeFullLifetimeTrackerV1\status\heartbeat.csv';expected_identity_sha256=Sha "$evaluatorHome\expected-identities.json";model_json_sha256=Sha "$evaluatorHome\frozen-tracking-model.json";schema_sha256=Sha "$evaluatorHome\output-schema.json"}
}
try{
 $before=Snapshot;$receipt.before=$before
 $ids=Json "$evaluatorHome\expected-identities.json"
 foreach($component in @('fp','collector','tracker')){foreach($kind in @('source','binary')){$property=$component+'_'+$kind+'_sha256';if($before.identities[$component][$kind+'_sha256']-ne $ids.$property){throw "Frozen $property mismatch"}}}
 if($before.identities.tracker.model_include_sha256-ne $ids.tracker_model_include_sha256 -or $before.identities.tracker.candidates_sha256-ne $ids.candidate_receipt_sha256){throw 'Frozen tracker model or candidate identity mismatch'}
 foreach($fx in $before.fxify){if(-not $fx.enabled_zero -or -not $fx.allow_live_zero){throw 'FXIFY is not paused'}}
 foreach($hb in @($before.collector_heartbeat,$before.tracker_heartbeat)){if($null-eq $hb -or $hb.order_capability-ne 'false' -or $hb.terminal_trade_allowed-ne 'false' -or $hb.mql_trade_allowed-ne 'false'){throw 'Orderless invariant failed'}}
 $receipt.previous_source_sha256=Sha $destination
 if($receipt.previous_source_sha256-ne '04d183c3c6d26b2199e780757cf480acdc58bdaa6240271ccc591f817155316b'){throw 'Evaluator is not the reviewed pre-repair version'}
 $task=Get-ScheduledTask -TaskName $taskName
 $priorityBefore=$task.Settings.Priority;$receipt.task_priority_before=$priorityBefore
 $receipt.task_xml_before_sha256=$null
 New-Item -ItemType Directory -Force -Path $backup|Out-Null
 Export-ScheduledTask -TaskName $taskName|Set-Content -Encoding UTF8 "$backup\task.xml"
 $receipt.task_xml_before_sha256=Sha "$backup\task.xml"
 Copy-Item -LiteralPath $destination -Destination "$backup\Run-V3-Forward-Evidence-Evaluator.ps1"
 $stage=Join-Path $backup 'tested-payload';New-Item -ItemType Directory -Force -Path $stage|Out-Null
 Copy-Item -LiteralPath $source -Destination "$stage\evaluator.ps1"
 Copy-Item -LiteralPath (Join-Path $repo 'tests\Test-ForwardEvidenceEvaluator.ps1') -Destination "$stage\regression.ps1"
 $receipt.status='TESTING';Save
 & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$stage\evaluator.ps1" -SelfTest|Set-Content -Encoding UTF8 "$out\self-test.json"
 if($LASTEXITCODE-ne 0){throw 'Evaluator self-test failed'}
 $priorRegression=Json "$out\powershell-regression.json"
 if($ReuseValidatedRun -and $null-ne $priorRegression -and $priorRegression.status-eq 'PASS' -and $priorRegression.tests_passed-ge 31 -and $priorRegression.source_sha256-eq (Sha "$stage\evaluator.ps1")){$receipt.regression_receipt_reused=$true}else{
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$stage\regression.ps1" -EvaluatorPath "$stage\evaluator.ps1" -OutputPath "$out\powershell-regression.json" -ObservationCount 1000
  if($LASTEXITCODE-ne 0){throw 'Windows PowerShell regression failed'}
 }
 Disable-ScheduledTask -TaskName $taskName|Out-Null;$taskDisabled=$true
 Stop-ScheduledTask -TaskName $taskName
 $deadline=[DateTime]::UtcNow.AddSeconds(15)
 while((Get-ScheduledTask -TaskName $taskName).State-eq 'Running' -and [DateTime]::UtcNow-lt $deadline){Start-Sleep -Milliseconds 250}
 if((Get-ScheduledTask -TaskName $taskName).State-eq 'Running'){throw 'Evaluator task did not stop'}
 foreach($dir in @('output','state','status')){Copy-Item -LiteralPath "$evaluatorHome\$dir" -Destination "$backup\$dir" -Recurse}
 $sequenceBefore=Json "$evaluatorHome\state\sequence.json";$receipt.sequence_before=$sequenceBefore
 Copy-Item -LiteralPath "$stage\evaluator.ps1" -Destination "$destination.next"
 Move-Item -Force -LiteralPath "$destination.next" -Destination $destination;$replaced=$true
 $receipt.source_sha256=Sha $destination
 if($receipt.source_sha256-ne (Sha $source)){throw 'Deployed evaluator hash differs from source'}
 $receipt.status='RUNNING_REPAIRED_EVALUATOR';Save
 $priorHeartbeat=Json "$evaluatorHome\status\heartbeat.json"
 if($ReuseValidatedRun -and $null-ne $priorHeartbeat -and $priorHeartbeat.PSObject.Properties.Name-contains 'evaluator_source_sha256' -and $priorHeartbeat.evaluator_source_sha256-eq $receipt.source_sha256 -and $priorHeartbeat.integrity_status-eq 'CLEAN' -and ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$priorHeartbeat.utc)-lt 1800){$receipt.manual_run_seconds=[double]$priorHeartbeat.run_elapsed_ms/1000.0;$receipt.validated_manual_run_reused=$true}else{
  $timer=[Diagnostics.Stopwatch]::StartNew()
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $destination
  $timer.Stop();$receipt.manual_run_seconds=$timer.Elapsed.TotalSeconds
  if($LASTEXITCODE-ne 0){throw "Repaired evaluator returned $LASTEXITCODE"}
 }
 if($receipt.manual_run_seconds-ge 240){throw 'Evaluator exceeded existing four-minute task budget'}
 $heartbeat=Json "$evaluatorHome\status\heartbeat.json";$integrity=Json "$evaluatorHome\output\integrity-receipt.json"
 if($heartbeat.integrity_status-ne 'CLEAN' -or $integrity.status-ne 'CLEAN'){throw 'Evaluator did not publish clean results'}
 $sequenceAfter=Json "$evaluatorHome\state\sequence.json"
 if($sequenceAfter.sequence_id-ne $sequenceBefore.sequence_id -or $sequenceAfter.started_utc-ne $sequenceBefore.started_utc){throw 'Existing evidence sequence was reset'}
 $receipt.sequence_after=$sequenceAfter;$receipt.manual_heartbeat=$heartbeat
 # The default task priority 7 is BelowNormal. On this CPU-saturated host
 # scheduled PowerShell received almost no CPU before the four-minute timeout.
 # Normal priority 6 matches the successful interactive verification runs.
 $settings=(Get-ScheduledTask -TaskName $taskName).Settings;$settings.Priority=6;$settings.ExecutionTimeLimit='PT8M'
 Set-ScheduledTask -TaskName $taskName -Settings $settings|Out-Null;$priorityChanged=$true
 Enable-ScheduledTask -TaskName $taskName|Out-Null;$taskDisabled=$false
 $runStart=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();Start-ScheduledTask -TaskName $taskName
 $deadline=[DateTime]::UtcNow.AddSeconds(490)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $taskName;$info=Get-ScheduledTaskInfo -TaskName $taskName}while($task.State-eq 'Running' -and [DateTime]::UtcNow-lt $deadline)
 if($task.State-eq 'Running' -or $info.LastTaskResult-ne 0){throw "Scheduled evaluator failed: $($task.State) / $($info.LastTaskResult)"}
 $finalHeartbeat=Json "$evaluatorHome\status\heartbeat.json"
 if([long]$finalHeartbeat.utc-lt $runStart -or $finalHeartbeat.integrity_status-ne 'CLEAN'){throw 'Scheduled evaluator did not publish a fresh clean heartbeat'}
 $after=Snapshot;$receipt.after=$after
 foreach($key in @('identities','configuration_hashes','fxify','expected_identity_sha256','model_json_sha256','schema_sha256')){if(($before[$key]|ConvertTo-Json -Depth 15 -Compress)-cne ($after[$key]|ConvertTo-Json -Depth 15 -Compress)){throw "Protected state changed: $key"}}
 Export-ScheduledTask -TaskName $taskName|Set-Content -Encoding UTF8 "$out\task-after.xml"
 $oldXml=([IO.File]::ReadAllText("$backup\task.xml") -replace '<Priority>\d+</Priority>','<Priority>6</Priority>') -replace '<ExecutionTimeLimit>[^<]+</ExecutionTimeLimit>','<ExecutionTimeLimit>PT8M</ExecutionTimeLimit>'
 if($oldXml-cne [IO.File]::ReadAllText("$out\task-after.xml")){throw 'Evaluator task changed beyond intended priority/runtime allowance'}
 $receipt.schedule=[ordered]@{task_name=$taskName;state=[string]$task.State;last_result=$info.LastTaskResult;last_run_utc=$info.LastRunTime.ToUniversalTime().ToString('o');next_run_utc=$info.NextRunTime.ToUniversalTime().ToString('o');execution_time_limit=[string]$task.Settings.ExecutionTimeLimit;triggers=$task.Triggers;principal=$task.Principal;priority=$task.Settings.Priority;only_priority_and_runtime_limit_changed=$true}
 foreach($file in @('per-trade-evidence.csv','rolling-invalidation-summary.csv','rolling-invalidation-summary.json','rolling-v3-entry-summary.json','integrity-receipt.json')){Copy-Item -Force -LiteralPath "$evaluatorHome\output\$file" -Destination "$out\$file"}
 Copy-Item -Force -LiteralPath "$evaluatorHome\status\heartbeat.json" -Destination "$out\heartbeat.json"
 Copy-Item -Force -LiteralPath "$evaluatorHome\state\sequence.json" -Destination "$out\sequence.json"
 $receipt.status='REPAIRED_AND_SCHEDULED_CLEAN';$receipt.protected_state_unchanged=$true;$receipt.heartbeat=$finalHeartbeat
}catch{
 $receipt.status='FAILED';$receipt.error=$_.Exception.Message;$receipt.error_detail=[string]$_
 if($replaced){Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;Copy-Item -Force -LiteralPath "$backup\Run-V3-Forward-Evidence-Evaluator.ps1" -Destination $destination;$receipt.source_rolled_back=$true}
 if($priorityChanged){$settings=(Get-ScheduledTask -TaskName $taskName).Settings;$settings.Priority=$priorityBefore;$settings.ExecutionTimeLimit='PT4M';Set-ScheduledTask -TaskName $taskName -Settings $settings|Out-Null;$receipt.priority_rolled_back=$true}
}finally{
 if($taskDisabled){Enable-ScheduledTask -TaskName $taskName|Out-Null}
 $receipt.completed_utc=[DateTime]::UtcNow.ToString('o');Save
}
if($receipt.status-ne 'REPAIRED_AND_SCHEDULED_CLEAN'){throw $receipt.error}
