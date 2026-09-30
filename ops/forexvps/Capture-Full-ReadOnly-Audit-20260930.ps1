[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
New-Item -ItemType Directory -Force -Path $out|Out-Null
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$fp=Join-Path $root 'MT5-FP-DEMO'
$collector=Join-Path $root 'Research\SolTrade-Brain-Collector-V1'
$tracker=Join-Path $root 'Research\SolTrade-Full-Lifetime-Tracker-V1'
$evaluator=Join-Path $root 'Research\SolTrade-Forward-Evidence-Evaluator-V1'
$cd=Join-Path $collector 'MQL5\Files\SolTradeBrainCollectorV1'
$td=Join-Path $tracker 'MQL5\Files\SolTradeFullLifetimeTrackerV1'
$started=[DateTime]::UtcNow.ToString('o')
$issues=New-Object Collections.Generic.List[string]
function Save($n,$v){$v|ConvertTo-Json -Depth 18|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out $n)}
function Progress($stage){Save 'capture-progress.json' ([ordered]@{started_utc=$started;updated_utc=[DateTime]::UtcNow.ToString('o');stage=$stage;read_only=$true;order_capability=$false;issues=@($issues|ForEach-Object{$_})})}
function Hash([string]$p){if(Test-Path -LiteralPath $p){(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}else{$null}}
function Pair([string]$p){if(Test-Path -LiteralPath $p){$l=@(Get-Content -LiteralPath $p -TotalCount 2);if($l.Count-eq 2){$l|ConvertFrom-Csv|Select-Object -First 1}}}
function Json([string]$p){if(Test-Path -LiteralPath $p){Get-Content -Raw -LiteralPath $p|ConvertFrom-Json}}
function Copy-Evidence($from,$to){if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination (Join-Path $out $to) -Force}else{$issues.Add("Missing: $from")}}
function Task($name){try{$t=Get-ScheduledTask -TaskName $name -ErrorAction Stop;$i=Get-ScheduledTaskInfo -TaskName $name;[ordered]@{name=$name;state=[string]$t.State;last_result=$i.LastTaskResult;last_run_utc=$i.LastRunTime.ToUniversalTime().ToString('o');next_run_utc=$i.NextRunTime.ToUniversalTime().ToString('o');execution_time_limit=$t.Settings.ExecutionTimeLimit;priority=$t.Settings.Priority;multiple_instances=[string]$t.Settings.MultipleInstances}}catch{[ordered]@{name=$name;error=$_.Exception.Message}}}
function Snapshot{
 $procs=@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Select-Object ProcessId,ExecutablePath,CreationDate,UserModeTime,KernelModeTime,WorkingSetSize)
 $identities=[ordered]@{}
 foreach($a in @(@('fp',$fp,'MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5'),@('collector',$collector,'MQL5\Experts\SolTradeBrainCollectorV1.mq5'),@('tracker',$tracker,'MQL5\Experts\SolTradeFullLifetimeTrackerV1.mq5'))){$p=Join-Path $a[1] $a[2];$identities[$a[0]]=[ordered]@{source_sha256=Hash $p;binary_sha256=Hash ($p.Replace('.mq5','.ex5'));pids=@($procs|Where-Object{$_.ExecutablePath-eq (Join-Path $a[1] 'terminal64.exe')}|ForEach-Object ProcessId)}}
 $identities.tracker.model_include_sha256=Hash (Join-Path $tracker 'MQL5\Experts\SolTradeV3TrackingModel.mqh')
 $identities.tracker.candidates_sha256=Hash (Join-Path $td 'frozen-invalidation-candidates.csv')
 $config=[ordered]@{}
 foreach($dir in @("$root\state","$fp\MQL5\Profiles\Presets","$root\MT5-FXIFY-10K\MQL5\Profiles\Presets","$root\MT5-FXIFY-100K\MQL5\Profiles\Presets","$collector\MQL5\Profiles\Presets","$tracker\MQL5\Profiles\Presets")){foreach($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension-in @('.ini','.set')})){$config[$f.FullName]=Hash $f.FullName}}
 $fx=@();foreach($a in @(@('7196820','fxify-10k','SolTradeFastMultiMarketV2F10'),@('7198096','fxify-100k','SolTradeFastMultiMarketV2F100'))){$p="$root\state\$($a[1]).ini";$s=[IO.File]::ReadAllText($p);$fx+=[ordered]@{account=$a[0];startup_hash=Hash $p;enabled_zero=($s-match '(?m)^Enabled=0\r?$');allow_live_zero=($s-match '(?m)^AllowLiveTrading=0\r?$');last_runtime=Pair (Join-Path $common "$($a[2])\runtime.csv")}}
 [ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');identities=$identities;configuration_hashes=$config;processes=$procs;fp_runtime=Pair (Join-Path $common 'SolTradeFastMultiMarketV2\runtime.csv');fxify=$fx;collector_heartbeat=Pair "$cd\status\heartbeat.csv";tracker_heartbeat=Pair "$td\status\heartbeat.csv";evaluator_heartbeat=Json "$evaluator\status\heartbeat.json";evaluator_progress=Json "$evaluator\status\run-progress.json";evaluator_source_sha256=Hash "$evaluator\Run-V3-Forward-Evidence-Evaluator.ps1";evaluator_expected_identity_sha256=Hash "$evaluator\expected-identities.json";tasks=@(Task 'SolTrade-Watchdog';Task 'SolTrade-Brain-Collector-V1-Watchdog';Task 'SolTrade-Full-Lifetime-Tracker-V1-Watchdog';Task 'SolTrade-V3-Forward-Evidence-Evaluator-V1';Task 'SolTrade-AccountOwnership-7404213');disk=@(Get-PSDrive -Name C|Select-Object Name,Used,Free);orders_sent_by_audit=0;positions_modified_by_audit=0;trading_logic_changed=$false}
}
try{
 Progress 'SNAPSHOT_BEFORE';Save 'snapshot-before.json' (Snapshot)
 Progress 'COPY_FP_AND_STATUS'
 foreach($a in @(@('SolTradeFastMultiMarketV2','fp'),@('SolTradeFastMultiMarketV2F10','fxify-10k'),@('SolTradeFastMultiMarketV2F100','fxify-100k'))){foreach($n in @('evidence.csv','runtime.csv')){Copy-Evidence (Join-Path $common "$($a[0])\$n") "$($a[1])-$n"}}
 foreach($a in @(@($cd,'collector'),@($td,'tracker'))){foreach($n in @('heartbeat.csv','state.csv')){Copy-Evidence "$($a[0])\status\$n" "$($a[1])-$n"};Copy-Evidence "$($a[0])\manifest.csv" "$($a[1])-manifest.csv"}
 Copy-Evidence "$td\frozen-invalidation-candidates.csv" 'frozen-invalidation-candidates.csv'
 foreach($n in @('per-trade-evidence.csv','rolling-invalidation-summary.csv','rolling-invalidation-summary.json','rolling-v3-entry-summary.json','integrity-receipt.json')){Copy-Evidence "$evaluator\output\$n" $n}
 foreach($n in @('heartbeat.json','run-progress.json')){Copy-Evidence "$evaluator\status\$n" "evaluator-$n"}
 Copy-Evidence "$evaluator\state\sequence.json" 'sequence.json'
 Copy-Evidence "$evaluator\expected-identities.json" 'expected-identities.json'
 $daily=Get-ChildItem "$evaluator\output\daily" -File -Filter '*.json'|Sort-Object Name -Descending|Select-Object -First 1
 if($daily){Copy-Evidence $daily.FullName 'latest-daily-snapshot.json'}
 Progress 'TRACKER_EVENTS_AND_OUTCOMES'
 foreach($kind in @('events','outcomes')){
  Get-ChildItem -LiteralPath "$td\$kind" -Filter '*.csv' -Recurse -File|Sort-Object FullName|ForEach-Object{Import-Csv -LiteralPath $_.FullName}|Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $out "tracker-$kind-all.csv")
 }
 Progress 'STORAGE_INVENTORY'
 foreach($a in @(@($cd,'collector'),@($td,'tracker'))){Get-ChildItem -LiteralPath $a[0] -File -Recurse|Where-Object{$_.Extension-eq '.csv'}|Select-Object @{n='relative_path';e={$_.FullName.Substring($a[0].Length+1)}},Length,@{n='last_write_utc';e={$_.LastWriteTimeUtc.ToString('o')}}|Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $out "$($a[1])-inventory.csv")}
 foreach($kind in @('raw_ticks','features')){
  $latest=Get-ChildItem "$cd\$kind" -Recurse -File|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
  if($latest){$header=Get-Content -LiteralPath $latest.FullName -TotalCount 1;$tail=Get-Content -LiteralPath $latest.FullName -Tail 100;@($header)+@($tail)|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out "collector-latest-$kind.csv")}
 }
 Progress 'ZIP_LIFETIME_EVIDENCE'
 Add-Type -AssemblyName System.IO.Compression
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zipPath=Join-Path $out 'tracker-lifetimes.zip'
 $stream=[IO.File]::Open($zipPath,[IO.FileMode]::Create)
 $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
 try{foreach($f in @(Get-ChildItem -LiteralPath "$td\lifetime_observations" -File -Recurse -Filter '*.csv' -ErrorAction SilentlyContinue)){
  $entry=$zip.CreateEntry($f.FullName.Substring($td.Length+1).Replace('\','/'),[IO.Compression.CompressionLevel]::Fastest)
  $src=[IO.File]::Open($f.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $dst=$entry.Open();try{$src.CopyTo($dst)}finally{$dst.Dispose();$src.Dispose()}
 }}finally{$zip.Dispose();$stream.Dispose()}
 Progress 'LOG_TAILS'
 foreach($a in @(@($fp,'fp'),@("$root\MT5-FXIFY-10K",'fxify-10k'),@("$root\MT5-FXIFY-100K",'fxify-100k'),@($collector,'collector'),@($tracker,'tracker'))){foreach($kind in @('logs','MQL5\Logs')){$f=Get-ChildItem (Join-Path $a[0] $kind) -File -Filter '*.log' -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1;if($f){Get-Content -LiteralPath $f.FullName -Tail 150|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out ("$($a[1])-"+$kind.Replace('\','-')+'-tail.log'))}}}
 Save 'snapshot-after.json' (Snapshot)
 Save 'capture-receipt.json' ([ordered]@{started_utc=$started;completed_utc=[DateTime]::UtcNow.ToString('o');status='CAPTURED';read_only=$true;orders_sent=0;positions_modified=0;issues=@($issues|ForEach-Object{$_});files=@(Get-ChildItem $out -File|Where-Object{$_.Name-ne 'capture-receipt.json'}|ForEach-Object{[ordered]@{name=$_.Name;bytes=$_.Length;sha256=Hash $_.FullName}})})
 Progress 'COMPLETE'
}catch{Save 'capture-error.json' ([ordered]@{utc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.Message;line=$_.InvocationInfo.ScriptLineNumber});throw}
