[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$root='C:\SolTrade'
$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$release=Join-Path $share 'releases\fxify-bank1r-giveback-20260913'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$output=Join-Path $share 'remote-output\fxify-bank1r-giveback-deployment.json'
$watchdog='SolTrade-Watchdog'
$expectedFpSource='4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e'
$expectedFpBinary='fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea'
$targets=@(
 [ordered]@{id='fxify-10k';login='7196820';home="$root\MT5-FXIFY-10K";state='SolTradeFastMultiMarketV2F10';profile='SolTradeV202F10';expert='SolTradeFastMultiMarketV202F10';source='055855e84ad7fe392932edc1c878f6ff66288360d148575c8dbc5a9692f2c1c3';binary='f1a527764b264b903ee54d4d9a890873bd7f0ceb38edca8b98f33df0f5715039';magic='2108202610';instance='vps-fxify-10k-prod'},
 [ordered]@{id='fxify-100k';login='7198096';home="$root\MT5-FXIFY-100K";state='SolTradeFastMultiMarketV2F100';profile='SolTradeV202F100';expert='SolTradeFastMultiMarketV202F100';source='b10d8a40f422cfba2dcb9c02b1b5b0d44dc9d669e4336d4c21601fbb17a483ef';binary='63bbbfa3a0fd81180d93cad558e5c841b2a5608aac2c921cf26aca13e7aad1f8';magic='2108202620';instance='vps-fxify-100k-prod'}
)

function Sha([string]$p){if(!(Test-Path -LiteralPath $p)){return $null};(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()}
function Procs([string]$terminalHome){@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object {$_.ExecutablePath -eq "$terminalHome\terminal64.exe"})}
function Runtime([string]$state){
 $p=Join-Path (Join-Path $common $state) 'runtime.csv'
 for($i=0;$i -lt 8;$i++){try{$r=@(Get-Content -LiteralPath $p -TotalCount 2)|ConvertFrom-Csv|Select-Object -First 1;if($r.login){return $r}}catch{};Start-Sleep -Milliseconds 250}
 return $null
}
function Fresh($r){if(!$r){return $false};try{$t=[DateTime]::ParseExact($r.timestamp_utc,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal);$age=([DateTime]::UtcNow-$t).TotalSeconds;return $age -ge -5 -and $age -le 90}catch{return $false}}
function ReadText([string]$p){
 $b=[IO.File]::ReadAllBytes($p)
 $enc=if($b.Length -ge 2 -and $b[0] -eq 255 -and $b[1] -eq 254){[Text.Encoding]::Unicode}else{[Text.UTF8Encoding]::new($false)}
 return @{encoding=$enc;text=$enc.GetString($b)}
}
function PatchLine([string]$text,[string]$name,[string]$value,[bool]$required=$true){
 $pattern='(?m)^'+[regex]::Escape($name)+'=[^\r\n]*(?=\r?$)'
 if($text -notmatch $pattern){if($required){throw "Missing $name"};return $text}
 return [regex]::Replace($text,$pattern,"$name=$value")
}
function SaveReceipt { $script:receipt | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath ($output+'.tmp'); Move-Item -Force -LiteralPath ($output+'.tmp') -Destination $output }
function SnapshotFP {
 $terminalHome="$root\MT5-FP-DEMO";$expert=Join-Path $terminalHome 'MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2'
 return [ordered]@{pids=@(Procs $terminalHome|ForEach-Object {$_.ProcessId});source_sha256=Sha($expert+'.mq5');binary_sha256=Sha($expert+'.ex5');runtime=Runtime 'SolTradeFastMultiMarketV2'}
}
function ExposurePresent {
 foreach($x in $targets){$r=Runtime $x.state;if(!$r -or [int]$r.positions -gt 0 -or [int]$r.orders -gt 0){return $true}}
 return $false
}

$receipt=[ordered]@{schema='SOLTRADE_FXIFY_BANK1R_GIVEBACK_DEPLOYMENT_V1';status='PREPARING';started_utc=[DateTime]::UtcNow.ToString('o');requested_accounts=@(7196820,7198096);orders_forced=$false;positions_closed=$false;backup=$null;preflight=@();changed=@();post=@();fp_before=$null;fp_after=$null;error=$null;rollback=$null}
$backup="$root\backups\fxify-bank1r-giveback-$(Get-Date -Format yyyyMMdd-HHmmss)"
$backed=@();$watchdogDisabled=$false;$tasksStopped=@();$mutated=$false;$newStarted=$false
try {
 $fp=SnapshotFP;$receipt.fp_before=$fp
 if($fp.source_sha256 -ne $expectedFpSource -or $fp.binary_sha256 -ne $expectedFpBinary -or @(Procs "$root\MT5-FP-DEMO").Count -ne 1 -or !(Fresh $fp.runtime) -or $fp.runtime.autonomous_entry -ne 'true' -or $fp.runtime.ownership_permit -ne 'GRANTED'){throw 'FP_HEALTH_OR_IDENTITY_FAILED'}
 foreach($x in $targets){
  $r=Runtime $x.state
  if(!(Fresh $r) -or $r.login -ne $x.login -or $r.server -ne 'FXIFY-Server' -or $r.connected -ne 'true' -or $r.scanner_active -ne 'true'){throw "FXIFY_PREFLIGHT_HEALTH_$($x.login)"}
  if([int]$r.positions -ne 0 -or [int]$r.orders -ne 0){throw "FXIFY_NOT_FLAT_$($x.login)"}
  if(@(Procs $x.home).Count -ne 1){throw "FXIFY_PROCESS_COUNT_$($x.login)"}
  $receipt.preflight+=@{account=$x.login;runtime=$r;pids=@(Procs $x.home|ForEach-Object {$_.ProcessId});source_sha256=Sha "$($x.home)\MQL5\Experts\SolTrade\$($x.expert).mq5";binary_sha256=Sha "$($x.home)\MQL5\Experts\SolTrade\$($x.expert).ex5"}
 }
 $receipt.status='PREFLIGHT_FLAT_HEALTHY';SaveReceipt
 New-Item -ItemType Directory -Force -Path $backup|Out-Null;$receipt.backup=$backup
 Disable-ScheduledTask -TaskName $watchdog|Out-Null;Stop-ScheduledTask -TaskName $watchdog -ErrorAction SilentlyContinue;$watchdogDisabled=$true
 foreach($x in $targets){$task="SolTrade-AccountOwnership-$($x.login)";Stop-ScheduledTask -TaskName $task -ErrorAction Stop;$tasksStopped+=$task}
 Start-Sleep -Seconds 20
 foreach($x in $targets){$r=Runtime $x.state;if([int]$r.positions -ne 0 -or [int]$r.orders -ne 0){throw "EXPOSURE_DURING_LEASE_DRAIN_$($x.login)"}}
 foreach($x in $targets){Procs $x.home|ForEach-Object {Stop-Process -Id $_.ProcessId -Force}}
 Start-Sleep -Seconds 3
 foreach($x in $targets){if(@(Procs $x.home).Count -ne 0){throw "TERMINAL_STOP_FAILED_$($x.login)"}}
 $mutated=$true

 foreach($x in $targets){
  $ini="$root\state\$($x.id).ini";$expertRoot="$($x.home)\MQL5\Experts\SolTrade";$src="$expertRoot\$($x.expert).mq5";$bin="$expertRoot\$($x.expert).ex5"
  $files=@($ini,$src,$bin)
  $iniData=ReadText $ini;$m=[regex]::Match($iniData.text,'(?m)^ExpertParameters=([^\r\n]+)');if(!$m.Success){throw "NO_PRESET_$($x.login)"};$presetName=[IO.Path]::GetFileName($m.Groups[1].Value)
  foreach($dir in @('MQL5\Presets','MQL5\Profiles\Presets')){$p=Join-Path (Join-Path $x.home $dir) $presetName;if(Test-Path -LiteralPath $p){$files+=$p}}
  foreach($dir in @("MQL5\Profiles\Charts\$($x.profile)","Profiles\Charts\$($x.profile)")){if(Test-Path (Join-Path $x.home $dir)){$files+=@(Get-ChildItem (Join-Path $x.home $dir) -Filter '*.chr' -File|Select-Object -ExpandProperty FullName)}}
  foreach($p in $files|Select-Object -Unique){$rel=$p.Substring($root.Length).TrimStart('\');$to=Join-Path $backup $rel;New-Item -ItemType Directory -Force -Path (Split-Path $to)|Out-Null;Copy-Item -Force -LiteralPath $p -Destination $to;$backed+=@{path=$p;backup=$to;before=Sha $p}}
  Copy-Item -Force -LiteralPath (Join-Path $release "$($x.id)\$($x.expert).mq5") -Destination $src
  Copy-Item -Force -LiteralPath (Join-Path $release "$($x.id)\$($x.expert).ex5") -Destination $bin
  if((Sha $src) -ne $x.source -or (Sha $bin) -ne $x.binary){throw "COPIED_HASH_MISMATCH_$($x.login)"}
  $it=ReadText $ini;$it.text=PatchLine $it.text 'AllowLiveTrading' '1';$it.text=PatchLine $it.text 'Enabled' '1';[IO.File]::WriteAllBytes($ini,$it.encoding.GetBytes($it.text))
  $presetCount=0
  foreach($p in $files|Where-Object {$_.EndsWith('.set')}){
   $d=ReadText $p;$t=$d.text
   foreach($kv in @(@('SetupEnabled','true'),@('DemoExecutionConfirmed','true'),@('DryRunOnly','false'),@('ApprovedDemoAccount',$x.login),@('ApprovedDemoServer','FXIFY-Server'),@('FastMagic',$x.magic),@('RiskPerTradePercent','1.00'),@('MaxPortfolioRiskPercent','1.50'),@('OwnershipLeaseRequired','true'),@('OwnershipEligible','true'),@('OwnershipInstanceId',$x.instance))){$t=PatchLine $t $kv[0] $kv[1]}
   if($t -notmatch '(?m)^OwnershipClaimSecret=.+$' -or $t -match '(?m)^OwnershipClaimSecret=__'){throw "OWNERSHIP_SECRET_INVALID_$($x.login)"}
   [IO.File]::WriteAllBytes($p,$d.encoding.GetBytes($t));$presetCount++
  }
  if($presetCount -lt 1){throw "NO_INSTALLED_PRESET_$($x.login)"}
  foreach($p in $files|Where-Object {$_.EndsWith('.chr')}){$d=ReadText $p;$t=$d.text;foreach($kv in @(@('SetupEnabled','true'),@('DemoExecutionConfirmed','true'),@('DryRunOnly','false'),@('RiskPerTradePercent','1.00'),@('MaxPortfolioRiskPercent','1.50'),@('OwnershipEligible','true'))){$t=PatchLine $t $kv[0] $kv[1] $false};[IO.File]::WriteAllBytes($p,$d.encoding.GetBytes($t))}
 }
 foreach($b in $backed){$receipt.changed+=@{path=$b.path;before_sha256=$b.before;after_sha256=Sha $b.path;backup=$b.backup}}
 $receipt.status='FILES_INSTALLED_STARTING';SaveReceipt
 foreach($task in $tasksStopped){Start-ScheduledTask -TaskName $task}
 foreach($x in $targets){Start-Process "$($x.home)\terminal64.exe" -WorkingDirectory $x.home -ArgumentList @('/portable',"/login:$($x.login)","/profile:$($x.profile)","/config:$root\state\$($x.id).ini")}
 $newStarted=$true
 $deadline=[DateTime]::UtcNow.AddMinutes(5);$ok=$false
 do {
  Start-Sleep -Seconds 5;$post=@();$ok=$true
  foreach($x in $targets){$r=Runtime $x.state;$pc=@(Procs $x.home).Count;$healthy=$pc -eq 1 -and (Fresh $r) -and $r.login -eq $x.login -and $r.server -eq 'FXIFY-Server' -and $r.connected -eq 'true' -and $r.scanner_active -eq 'true' -and $r.autonomous_entry -eq 'true' -and $r.ownership_permit -eq 'GRANTED' -and $r.manager_version -eq 'ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK';$post+=@{account=$x.login;healthy=$healthy;process_count=$pc;source_sha256=Sha "$($x.home)\MQL5\Experts\SolTrade\$($x.expert).mq5";binary_sha256=Sha "$($x.home)\MQL5\Experts\SolTrade\$($x.expert).ex5";runtime=$r};if(!$healthy){$ok=$false}}
 } while(!$ok -and [DateTime]::UtcNow -lt $deadline)
 $receipt.post=$post;if(!$ok){throw 'RUNTIME_VERIFICATION_TIMEOUT'}
 $fpAfter=SnapshotFP;$receipt.fp_after=$fpAfter
 if($fpAfter.source_sha256 -ne $expectedFpSource -or $fpAfter.binary_sha256 -ne $expectedFpBinary -or !(Fresh $fpAfter.runtime) -or $fpAfter.runtime.autonomous_entry -ne 'true' -or $fpAfter.runtime.ownership_permit -ne 'GRANTED'){throw 'FP_POST_CONTINUITY_FAILED'}
 $receipt.status='DEPLOYED_ALL_THREE_ACTIVE';$receipt.completed_utc=[DateTime]::UtcNow.ToString('o');SaveReceipt
} catch {
 $receipt.error=$_.Exception.Message;$receipt.status='FAILED'
 $canRollback=$mutated -and !(ExposurePresent)
 if($canRollback){
  try {foreach($x in $targets){Procs $x.home|ForEach-Object {Stop-Process -Id $_.ProcessId -Force}};Start-Sleep -Seconds 2;foreach($b in $backed){Copy-Item -Force -LiteralPath $b.backup -Destination $b.path};foreach($task in $tasksStopped){Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue};foreach($x in $targets){Start-Process "$($x.home)\terminal64.exe" -WorkingDirectory $x.home -ArgumentList @('/portable',"/login:$($x.login)","/profile:$($x.profile)","/config:$root\state\$($x.id).ini")};$receipt.rollback='RESTORED_PREVIOUS_PAUSED_FILES'}catch{$receipt.rollback='ROLLBACK_FAILED: '+$_.Exception.Message}
 } else {$receipt.rollback='NOT_ATTEMPTED_EXPOSURE_OR_PREMUTATION'}
 $receipt.completed_utc=[DateTime]::UtcNow.ToString('o');SaveReceipt
 throw
} finally {
 if($watchdogDisabled){Enable-ScheduledTask -TaskName $watchdog|Out-Null;Start-ScheduledTask -TaskName $watchdog -ErrorAction SilentlyContinue}
 foreach($task in $tasksStopped){Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue}
}
