[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade'
$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$repo=(Resolve-Path (Join-Path $share '..\..')).Path
$payload=Join-Path $repo 'tools\mql\full-lifetime-tracker-v1'
$output=Join-Path $share 'remote-output\full-lifetime-tracker-v1'
$iso="$root\Research\SolTrade-Full-Lifetime-Tracker-V1"
$data=Join-Path $iso 'MQL5\Files\SolTradeFullLifetimeTrackerV1'
$stateIni="$root\state\full-lifetime-tracker-v1.ini"
$taskName='SolTrade-Full-Lifetime-Tracker-V1-Watchdog'
$fp="$root\MT5-FP-DEMO"
$collector="$root\Research\SolTrade-Brain-Collector-V1"
$collectorData=Join-Path $collector 'MQL5\Files\SolTradeBrainCollectorV1'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$receipt=[ordered]@{schema='SOLTRADE_V3_FULL_LIFETIME_DEPLOYMENT_V1';status='PREPARING';started_utc=[DateTime]::UtcNow.ToString('o');orders_sent=$false;positions_modified=$false;production_files_modified=$false;fxify_files_modified=$false;entry_specification_changed=$false;error=$null}

function Sha([string]$p){if(-not(Test-Path -LiteralPath $p)){return $null};(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}
function Save-Receipt{$receipt|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $output 'deployment.json')}
function Process-For([string]$path){@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object{$_.ExecutablePath -eq $path})}
function Runtime([string]$state){$p=Join-Path $common "$state\runtime.csv";if(-not(Test-Path $p)){return $null};$lines=@(Get-Content -LiteralPath $p -TotalCount 2);if($lines.Count -ne 2){return $null};$lines|ConvertFrom-Csv|Select-Object -First 1}
function Read-CsvPair([string]$path){if(-not(Test-Path $path)){return $null};$lines=@(Get-Content -LiteralPath $path -TotalCount 2);if($lines.Count -ne 2){return $null};$lines|ConvertFrom-Csv|Select-Object -First 1}
function FP-Snapshot{
 $r=Runtime 'SolTradeFastMultiMarketV2';$source="$fp\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5";$binary=$source.Replace('.mq5','.ex5')
 [ordered]@{runtime=$r;source_sha256=Sha $source;binary_sha256=Sha $binary;pids=@(Process-For "$fp\terminal64.exe"|ForEach-Object ProcessId);source_last_write_utc=(Get-Item $source).LastWriteTimeUtc.ToString('o');binary_last_write_utc=(Get-Item $binary).LastWriteTimeUtc.ToString('o')}
}
function FX-State([string]$id,[string]$login,[string]$homePath,[string]$runtimeState){
 $ini="$root\state\$id.ini";$text=[IO.File]::ReadAllText($ini);$r=Runtime $runtimeState
 [ordered]@{id=$id;login=$login;startup_path=$ini;startup_sha256=Sha $ini;enabled_zero=($text -match '(?m)^Enabled=0\r?$');allow_live_zero=($text -match '(?m)^AllowLiveTrading=0\r?$');runtime=$r;pids=@(Process-For "$homePath\terminal64.exe"|ForEach-Object ProcessId)}
}
function Tracker-Heartbeat{Read-CsvPair (Join-Path $data 'status\heartbeat.csv')}
function Start-Tracker{Start-Process -FilePath "$iso\terminal64.exe" -WorkingDirectory $iso -ArgumentList @('/portable',"/config:$stateIni")|Out-Null}

New-Item -ItemType Directory -Force -Path $output|Out-Null
try{
 $fpBefore=FP-Snapshot;$fx10Before=FX-State 'fxify-10k' '7196820' "$root\MT5-FXIFY-10K" 'SolTradeFastMultiMarketV2F10';$fx100Before=FX-State 'fxify-100k' '7198096' "$root\MT5-FXIFY-100K" 'SolTradeFastMultiMarketV2F100';$collectorBefore=Read-CsvPair (Join-Path $collectorData 'status\heartbeat.csv')
 $receipt.fp_before=$fpBefore;$receipt.fxify_before=@($fx10Before,$fx100Before);$receipt.collector_before=$collectorBefore
 if($fpBefore.source_sha256 -ne '4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e' -or $fpBefore.binary_sha256 -ne 'fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea'){throw 'FP frozen baseline hash mismatch'}
 if(@($fpBefore.pids).Count -ne 1){throw 'FP process count is not one'}
 foreach($x in @($fx10Before,$fx100Before)){if(-not $x.enabled_zero -or -not $x.allow_live_zero){throw "FXIFY startup pause missing: $($x.login)"}}
 if(-not $collectorBefore -or $collectorBefore.order_capability -ne 'false' -or $collectorBefore.terminal_trade_allowed -ne 'false' -or $collectorBefore.mql_trade_allowed -ne 'false'){throw 'Existing collector orderless invariant failed'}

 $source=Join-Path $payload 'SolTradeFullLifetimeTrackerV1.mq5';$include=Join-Path $payload 'SolTradeV3TrackingModel.mqh';$preset=Join-Path $payload 'SolTradeFullLifetimeTrackerV1.set'
 foreach($p in @($source,$include,$preset)){if(-not(Test-Path -LiteralPath $p)){throw "Payload missing: $p"}}
 $text=Get-Content -Raw -LiteralPath $source
 foreach($pattern in @('#include\s*<Trade/','\bCTrade\b','\bOrderSend(?:Async)?\s*\(','\bMqlTradeRequest\b','\bTRADE_ACTION_','\bPositionClose\s*\(','\bPositionModify\s*\(','\bOrderDelete\s*\(')){if($text -match $pattern){throw "Forbidden trade capability matched: $pattern"}}
 if($text -notmatch 'const bool ORDER_CAPABILITY=false'){throw 'Order capability marker absent'}

 if(Test-Path -LiteralPath $iso){
  if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue;Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue|Out-Null}
  Process-For "$iso\terminal64.exe"|ForEach-Object{Stop-Process -Id $_.ProcessId -Force}
  Start-Sleep -Seconds 2
  $backup="$root\backups\full-lifetime-tracker-update-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))";New-Item -ItemType Directory -Force -Path $backup|Out-Null
  foreach($p in @("$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5","$iso\MQL5\Experts\SolTradeV3TrackingModel.mqh","$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.ex5")){if(Test-Path $p){Copy-Item -Force $p $backup}}
  $receipt.backup=$backup
 } else {
  New-Item -ItemType Directory -Force -Path "$iso\Config","$iso\MQL5\Experts","$iso\MQL5\Presets","$iso\MQL5\Profiles\Presets","$iso\Profiles\Presets","$iso\MQL5\Files"|Out-Null
  foreach($name in @('terminal64.exe','metaeditor64.exe','metatester64.exe')){Copy-Item -Force -LiteralPath (Join-Path $fp $name) -Destination (Join-Path $iso $name)}
  foreach($name in @('accounts.dat','servers.dat')){$p=Join-Path $fp "Config\$name";if(Test-Path $p){Copy-Item -Force -LiteralPath $p -Destination (Join-Path $iso "Config\$name")}}
 }
 $freshnessMarker=Join-Path $iso 'freshness-gate-v1.applied'
 if(-not(Test-Path $freshnessMarker) -and (Test-Path $data)){
  $invalidBackup="$root\backups\full-lifetime-invalid-stale-state-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
  New-Item -ItemType Directory -Force -Path $invalidBackup|Out-Null
  Copy-Item -Recurse -Force -LiteralPath $data -Destination $invalidBackup
  Remove-Item -Recurse -Force -LiteralPath $data
  New-Item -ItemType Directory -Force -Path $data|Out-Null
  'Tracker records created before the 10-second symbol-freshness gate were isolated as invalid.'|Set-Content -Encoding UTF8 -LiteralPath $freshnessMarker
  $receipt.invalid_stale_state_reset=[ordered]@{status='COMPLETED';backup=$invalidBackup;production_data_touched=$false;collector_data_touched=$false}
 }
 Copy-Item -Force $source "$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5";Copy-Item -Force $include "$iso\MQL5\Experts\SolTradeV3TrackingModel.mqh"
 foreach($dest in @("$iso\MQL5\Profiles\Presets\SolTradeFullLifetimeTrackerV1.set","$iso\MQL5\Presets\SolTradeFullLifetimeTrackerV1.set","$iso\Profiles\Presets\SolTradeFullLifetimeTrackerV1.set")){Copy-Item -Force $preset $dest}
 $compileLog="$iso\compile.log";$editor=Start-Process -FilePath "$iso\metaeditor64.exe" -ArgumentList @("/compile:$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5","/log:$compileLog","/inc:$iso\MQL5") -PassThru
 if(-not $editor.WaitForExit(180000)){Stop-Process -Id $editor.Id -Force;throw 'Tracker compilation timed out'}
 Copy-Item -Force $compileLog (Join-Path $output 'compile.log')
 $compileText=Get-Content -Raw $compileLog;if($compileText -notmatch '0 errors, 0 warnings'){throw 'Tracker compilation failed'}
 $binary="$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.ex5";if(-not(Test-Path $binary)){throw 'Tracker binary absent'}
 Copy-Item -Force $source (Join-Path $output 'SolTradeFullLifetimeTrackerV1.mq5');Copy-Item -Force $include (Join-Path $output 'SolTradeV3TrackingModel.mqh');Copy-Item -Force $binary (Join-Path $output 'SolTradeFullLifetimeTrackerV1.ex5')
 $receipt.compile=[ordered]@{result='0 errors, 0 warnings';source_sha256=Sha "$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5";model_include_sha256=Sha "$iso\MQL5\Experts\SolTradeV3TrackingModel.mqh";binary_sha256=Sha $binary;static_trade_api_scan='PASS';order_capability=$false}

 @"
[Common]
Login=7404213
Server=FPMarketsSC-Demo
KeepPrivate=1
NewsEnable=1
CertInstall=0

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=0
Account=7404213
Profile=0

[StartUp]
Symbol=XAUUSD.r
Period=M1
Expert=SolTradeFullLifetimeTrackerV1
ExpertParameters=SolTradeFullLifetimeTrackerV1.set
"@|Set-Content -Encoding ASCII -LiteralPath $stateIni

 @"
`$ErrorActionPreference='SilentlyContinue'
`$trackerHome='$iso'
`$terminal=Join-Path `$trackerHome 'terminal64.exe'
`$config='$stateIni'
`$process=@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object{`$_.ExecutablePath -eq `$terminal})
if(`$process.Count -eq 0){Start-Process -FilePath `$terminal -WorkingDirectory `$trackerHome -ArgumentList @('/portable',"/config:`$config")}
"@|Set-Content -Encoding UTF8 -LiteralPath "$iso\Watch-FullLifetimeTracker.ps1"
 if(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}
 $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$iso\Watch-FullLifetimeTracker.ps1`"";$startup=New-ScheduledTaskTrigger -AtStartup;$minute=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
 Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($startup,$minute) -RunLevel Highest -User 'SYSTEM' -Force|Out-Null
 Start-Tracker
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$hb=$null
do{Start-Sleep -Seconds 2;$hb=Tracker-Heartbeat}while((-not $hb -or $hb.status -ne 'COLLECTING_FULL_LIFETIMES') -and [DateTime]::UtcNow -lt $deadline)
 if(-not $hb){throw 'Tracker heartbeat absent'}
 if($hb.order_capability -ne 'false' -or $hb.terminal_trade_allowed -ne 'false' -or $hb.mql_trade_allowed -ne 'false'){throw 'Tracker trade permissions not disabled'}
 $stateBefore=Sha (Join-Path $data 'status\state.csv');$restartBefore=[int]$hb.restart_count
 Process-For "$iso\terminal64.exe"|ForEach-Object{Stop-Process -Id $_.ProcessId -Force};Start-Sleep -Seconds 3;Start-Tracker
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$afterRestart=$null
do{Start-Sleep -Seconds 2;$afterRestart=Tracker-Heartbeat}while((-not $afterRestart -or [int]$afterRestart.restart_count -le $restartBefore) -and [DateTime]::UtcNow -lt $deadline)
 if(-not $afterRestart -or [int]$afterRestart.restart_count -le $restartBefore){throw 'Tracker restart persistence failed'}
 $receipt.restart_test=[ordered]@{status='PASS';before_restart_count=$restartBefore;after_restart_count=[int]$afterRestart.restart_count;state_before_sha256=$stateBefore;state_after_sha256=Sha (Join-Path $data 'status\state.csv');tracker_only_process_restarted=$true}
 Start-ScheduledTask -TaskName $taskName;Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $taskName;$taskInfo=Get-ScheduledTaskInfo -TaskName $taskName
 $receipt.watchdog=[ordered]@{task=$taskName;state=[string]$task.State;last_result=$taskInfo.LastTaskResult}

 $fpAfter=FP-Snapshot;$fx10After=FX-State 'fxify-10k' '7196820' "$root\MT5-FXIFY-10K" 'SolTradeFastMultiMarketV2F10';$fx100After=FX-State 'fxify-100k' '7198096' "$root\MT5-FXIFY-100K" 'SolTradeFastMultiMarketV2F100';$collectorAfter=Read-CsvPair (Join-Path $collectorData 'status\heartbeat.csv')
 $receipt.fp_after=$fpAfter;$receipt.fxify_after=@($fx10After,$fx100After);$receipt.collector_after=$collectorAfter;$receipt.tracker=[ordered]@{home=$iso;storage=$data;startup=$stateIni;heartbeat=$afterRestart;pids=@(Process-For "$iso\terminal64.exe"|ForEach-Object ProcessId);source_sha256=Sha "$iso\MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5";model_include_sha256=Sha "$iso\MQL5\Experts\SolTradeV3TrackingModel.mqh";binary_sha256=Sha $binary;manifest=Read-CsvPair (Join-Path $data 'manifest.csv');candidates=@(Import-Csv (Join-Path $data 'frozen-invalidation-candidates.csv'))}
 if($fpAfter.source_sha256 -ne $fpBefore.source_sha256 -or $fpAfter.binary_sha256 -ne $fpBefore.binary_sha256 -or ($fpAfter.pids -join ',') -ne ($fpBefore.pids -join ',') -or $fpAfter.runtime.autonomous_entry -ne $fpBefore.runtime.autonomous_entry -or $fpAfter.runtime.entry_permission -ne $fpBefore.runtime.entry_permission){throw 'FP changed during tracker deployment'}
 foreach($pair in @(@($fx10Before,$fx10After),@($fx100Before,$fx100After))){if($pair[1].startup_sha256 -ne $pair[0].startup_sha256 -or -not $pair[1].enabled_zero -or -not $pair[1].allow_live_zero){throw "FXIFY pause changed: $($pair[1].login)"}}
 if($collectorAfter.order_capability -ne 'false' -or $collectorAfter.terminal_trade_allowed -ne 'false' -or $collectorAfter.mql_trade_allowed -ne 'false'){throw 'Collector changed orderless state'}
 if(@($receipt.tracker.pids).Count -ne 1){throw 'Tracker process count is not one'}
 if(Test-Path (Join-Path $data 'status\heartbeat.csv')){Copy-Item -Force (Join-Path $data 'status\heartbeat.csv') (Join-Path $output 'heartbeat.csv')};if(Test-Path (Join-Path $data 'manifest.csv')){Copy-Item -Force (Join-Path $data 'manifest.csv') (Join-Path $output 'manifest.csv')};if(Test-Path (Join-Path $data 'frozen-invalidation-candidates.csv')){Copy-Item -Force (Join-Path $data 'frozen-invalidation-candidates.csv') (Join-Path $output 'frozen-invalidation-candidates.csv')}
 $receipt.fp_untouched=$true;$receipt.fxify_remained_paused=$true;$receipt.collector_untouched=$true;$receipt.order_capability=$false;$receipt.orders_sent=$false;$receipt.positions_modified=$false;$receipt.production_files_modified=$false;$receipt.status='DEPLOYED_ORDERLESS_TRACKER_VERIFIED'
}catch{$receipt.status='FAILED';$receipt.error=$_.Exception.Message}
finally{$receipt.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Receipt}
if($receipt.status -ne 'DEPLOYED_ORDERLESS_TRACKER_VERIFIED'){throw $receipt.error}
$receipt|ConvertTo-Json -Depth 20
