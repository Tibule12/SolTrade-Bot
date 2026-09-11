[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$share='\\tsclient\SolTrade'
$root='C:\SolTrade';$fp=Join-Path $root 'MT5-FP-DEMO'
$release=Join-Path $share 'releases\fp-adaptive-payoff-v1-bank1r-20260911'
$output=Join-Path $share 'remote-output\fp-adaptive-payoff-v1-bank1r-deployment.json'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$expert=Join-Path $fp 'MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2'
$watchdogName='SolTrade-Watchdog';$authorityName='SolTrade-AccountOwnership-7404213'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Processes([string]$terminalHome){@(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $terminalHome 'terminal64.exe')})}
function Runtime {
    $p=Join-Path $common 'SolTradeFastMultiMarketV2\runtime.csv'
    for($i=0;$i -lt 10;$i++) {
        try {
            $r=Get-Content -LiteralPath $p -TotalCount 2 | ConvertFrom-Csv | Select-Object -First 1
            if($r.login) {
                $plain=@{};foreach($property in $r.PSObject.Properties){$plain[$property.Name]=[string]$property.Value}
                return $plain
            }
        }catch{}
        Start-Sleep -Milliseconds 200
    }
    throw 'FP runtime unreadable'
}
function Fresh($r) {
    $t=[DateTime]::ParseExact($r.timestamp_utc,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    return (([DateTime]::UtcNow-$t).TotalSeconds -ge -2 -and ([DateTime]::UtcNow-$t).TotalSeconds -le 45)
}
function Flat($r) {
    if(-not (Fresh $r) -or $r.login -ne '7404213' -or $r.server -ne 'FPMarketsSC-Demo' -or $r.account_mode_demo -ne 'true' -or $r.connected -ne 'true') {throw 'FP identity/freshness/connection check failed'}
    if([int]$r.positions -ne 0 -or [int]$r.orders -ne 0){throw 'FP_NOT_FLAT: deployment waits for natural flat state; no positions closed'}
}
function FxSnapshot {
    $values=@{}
    foreach($id in @('fxify-10k','fxify-100k')) {
        $terminalHome=Join-Path $root $(if($id -eq 'fxify-10k'){'MT5-FXIFY-10K'}else{'MT5-FXIFY-100K'})
        foreach($dir in @('MQL5\Experts\SolTrade','MQL5\Presets','MQL5\Profiles\Presets')) {
            $p=Join-Path $terminalHome $dir
            if(Test-Path $p){foreach($file in Get-ChildItem -LiteralPath $p -Recurse -File){if($file.Extension -in @('.ex5','.mq5','.set')){$values[$file.FullName]=Hash $file.FullName}}}
        }
        $p=Join-Path $root "state\$id.ini";$values[$p]=Hash $p
        $values["process-$id"]=(@(Processes $terminalHome | ForEach-Object {$_.Id} | Sort-Object) -join ',')
        $runtimeName=if($id -eq 'fxify-10k'){'SolTradeFastMultiMarketV2F10'}else{'SolTradeFastMultiMarketV2F100'}
        $runtimePath=Join-Path $common "$runtimeName\runtime.csv"
        $runtime=Get-Content -LiteralPath $runtimePath -TotalCount 2 | ConvertFrom-Csv | Select-Object -First 1
        $values["paused-$id"]="$($runtime.login)|$($runtime.entry_permission)|$($runtime.autonomous_entry)|$($runtime.positions)|$($runtime.orders)"
        if($runtime.entry_permission -ne 'DISABLED_DRY_RUN' -or $runtime.autonomous_entry -ne 'false' -or
           [int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0){throw "FXIFY_NOT_PAUSED_$id"}
    }
    foreach($p in @('state\instances.json','Watch-SolTrade.ps1')) {
        $path=Join-Path $root $p;if(Test-Path $path){$values[$path]=Hash $path}
    }
    return $values
}
function PatchRisk([string]$path) {
    $bytes=[IO.File]::ReadAllBytes($path)
    $unicode=$bytes.Length -gt 1 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254
    $encoding=if($unicode){[Text.Encoding]::Unicode}else{[Text.UTF8Encoding]::new($false)}
    $text=$encoding.GetString($bytes)
    $matches=[regex]::Matches($text,'(?m)^RiskPerTradePercent=([^\r\n]+)')
    if($matches.Count -eq 0){return $false}
    foreach($match in $matches){if($match.Groups[1].Value -notin @('0.25','1.00')){throw "Unexpected FP risk override in $path"}}
    $updated=[regex]::Replace($text,'(?m)^RiskPerTradePercent=0\.25(?=\r?$)','RiskPerTradePercent=1.00')
    $relative=$path.Substring($fp.Length).TrimStart('\')
    $saved=Join-Path $backup $relative;New-Item -ItemType Directory -Force -Path (Split-Path $saved) | Out-Null
    Copy-Item -LiteralPath $path -Destination $saved
    $script:backups+=@{path=$path;saved=$saved;before_sha256=Hash $path}
    # Encoding.GetString retains a BOM character; GetBytes preserves it exactly.
    [IO.File]::WriteAllBytes($path,$encoding.GetBytes($updated))
    $script:changed+=@{path=$path;before_sha256=Hash $saved;after_sha256=Hash $path;change='RiskPerTradePercent 0.25 -> 1.00 only'}
    return $true
}
function StartFP {
    Start-ScheduledTask -TaskName $authorityName
    Start-Process -FilePath (Join-Path $fp 'terminal64.exe') -WorkingDirectory $fp -ArgumentList @('/portable','/login:7404213','/profile:SolTradeV202FP',"/config:$root\state\fp-demo.ini")
}
$manifest=Get-Content -Raw (Join-Path $release 'manifest.json') | ConvertFrom-Json
$tests=Get-Content -Raw (Join-Path $release 'tests.json') | ConvertFrom-Json
if(-not $tests.passed -or $manifest.compile -ne '0 errors, 0 warnings'){throw 'Build/test gate failed'}
$before=Runtime;Flat $before
if(@(Processes $fp).Count -ne 1){throw 'Expected exactly one VPS FP process'}
if((Hash "$expert.mq5") -ne $manifest.installed_base_source_sha256){throw 'Installed FP source is not reviewed current FP base'}
$fxBefore=FxSnapshot
$stage=Join-Path $root 'staging\fp-adaptive-payoff-v1-bank1r-20260911'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach($ext in @('mq5','ex5')){Copy-Item -LiteralPath (Join-Path $release "SolTradeFastMultiMarketV2.$ext") -Destination $stage -Force}
if((Hash (Join-Path $stage 'SolTradeFastMultiMarketV2.mq5')) -ne $manifest.source_sha256 -or
   (Hash (Join-Path $stage 'SolTradeFastMultiMarketV2.ex5')) -ne $manifest.binary_sha256){throw 'Staging hash mismatch'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$backup=Join-Path $root "backups\fp-adaptive-payoff-v1-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$backups=@();$changed=@();$stopped=$false;$success=$false;$failure=$null
$originalPid=@(Processes $fp)[0].Id
$watchdogWasEnabled=(Get-ScheduledTask -TaskName $watchdogName).State -ne 'Disabled'
if(-not $watchdogWasEnabled){throw 'Watchdog was disabled before deployment'}
try {
    Disable-ScheduledTask -TaskName $watchdogName | Out-Null
    Stop-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName $authorityName
    Start-Sleep -Seconds 18
    $leaseDeadline=[DateTime]::UtcNow.AddSeconds(60)
    do {
        $lastFlat=Runtime;Flat $lastFlat
        if($lastFlat.ownership_permit -ne 'GRANTED' -and [long]$lastFlat.lease_expires_epoch -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()){break}
        Start-Sleep -Seconds 2
    }while([DateTime]::UtcNow -lt $leaseDeadline)
    if($lastFlat.ownership_permit -eq 'GRANTED'){throw 'FP ownership still granted after lease expiry'}
    Processes $fp | Stop-Process -Force
    $stopped=$true;Start-Sleep -Seconds 3
    if(@(Processes $fp).Count -ne 0){throw 'FP terminal did not stop'}
    foreach($ext in @('mq5','ex5')) {
        $path="$expert.$ext";$saved=Join-Path $backup "SolTradeFastMultiMarketV2.$ext"
        Copy-Item -LiteralPath $path -Destination $saved
        $backups+=@{path=$path;saved=$saved;before_sha256=Hash $path}
        Copy-Item -LiteralPath (Join-Path $stage "SolTradeFastMultiMarketV2.$ext") -Destination $path -Force
        $changed+=@{path=$path;before_sha256=Hash $saved;after_sha256=Hash $path;change='FP ADAPTIVE_PAYOFF_V1 bank trigger 2R -> 1R; entries, structural stop, sizing, probation and runner structure preserved'}
    }
    StartFP
    $deadline=[DateTime]::UtcNow.AddMinutes(4)
    do {
        Start-Sleep -Seconds 5
        $after=Runtime
        $healthy=(Fresh $after) -and $after.login -eq '7404213' -and $after.connected -eq 'true' -and
            $after.scanner_active -eq 'true' -and $after.autonomous_entry -eq 'true' -and
            $after.manager_version -eq 'ADAPTIVE_PAYOFF_V1_BANK1R' -and $after.portfolio_risk_known -eq 'true' -and
            $after.ownership_permit -eq 'GRANTED' -and $after.owner_instance_id -eq 'vps-fp-prod' -and
            $after.owner_host -eq $env:COMPUTERNAME -and @(Processes $fp).Count -eq 1 -and @(Processes $fp)[0].Id -ne $originalPid
    }while(-not $healthy -and [DateTime]::UtcNow -lt $deadline)
    if(-not $healthy){throw 'FP post-deployment health failed'}
    if((Hash "$expert.mq5") -ne $manifest.source_sha256 -or (Hash "$expert.ex5") -ne $manifest.binary_sha256){throw 'Installed FP hash mismatch'}
    $utc=[DateTime]::UtcNow
    $sast=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($utc,'South Africa Standard Time')
    $baseline=[ordered]@{schema='FP_ADAPTIVE_PAYOFF_V1_BANK1R_FORWARD_BASELINE';timestamp_utc=$utc.ToString('o');timestamp_sast=$sast.ToString('o');account=7404213;server='FPMarketsSC-Demo';balance=[double]$after.equity;equity=[double]$after.equity;balance_basis='FP was flat, so equity equals balance';positions=[int]$after.positions;orders=[int]$after.orders;source_sha256=$manifest.source_sha256;binary_sha256=$manifest.binary_sha256;source_commit=$manifest.source_commit;manager_version='ADAPTIVE_PAYOFF_V1_BANK1R';initial_risk_percent=1.00;aggregate_risk_cap_percent=1.50;bank_at_r=1.00;bank_original_volume_fraction=0.50;fxify_unchanged=$false;fxify_before=$fxBefore;older_cohort_excluded=$true}
    $baselinePath=Join-Path $root 'state\fp-adaptive-payoff-v1-bank1r-baseline.json'
    $baseline | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $baselinePath
    $baseline | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $share 'remote-output\fp-adaptive-payoff-v1-bank1r-baseline.json')
    $publisherSource=Join-Path $share 'Publish-FP-AdaptivePayoffV1-Bank1R-Scoreboard.ps1'
    $publisherInstalled=Join-Path $root 'Publish-FP-AdaptivePayoffV1-Bank1R-Scoreboard.ps1'
    Copy-Item -Force -LiteralPath $publisherSource -Destination $publisherInstalled
    $taskCommand="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$publisherInstalled`""
    & schtasks.exe /Delete /TN 'SolTrade-FP-AdaptivePayoffV1-Scoreboard' /F 2>$null | Out-Null
    & schtasks.exe /Create /TN 'SolTrade-FP-AdaptivePayoffV1-Bank1R-Scoreboard' /SC MINUTE /MO 1 /TR $taskCommand /F | Out-Null
    & schtasks.exe /Run /TN 'SolTrade-FP-AdaptivePayoffV1-Bank1R-Scoreboard' | Out-Null
    $success=$true
}catch {
    $failure=$_.Exception.Message
    if($stopped) {
        # Only rollback while flat. Never kill a manager if autonomous trading
        # has already opened a position after restart.
        $r=Runtime
        if([int]$r.positions -eq 0 -and [int]$r.orders -eq 0) {
            Stop-ScheduledTask -TaskName $authorityName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 18
            $r=Runtime;Flat $r
            Processes $fp | Stop-Process -Force;Start-Sleep -Seconds 2
            foreach($b in $backups){Copy-Item -LiteralPath $b.saved -Destination $b.path -Force}
            StartFP
        }else{$failure+='; open exposure: manager left running; no rollback attempted'}
    }else{Start-ScheduledTask -TaskName $authorityName}
}finally{
    Enable-ScheduledTask -TaskName $watchdogName | Out-Null
    Start-ScheduledTask -TaskName $watchdogName
}
Start-Sleep -Seconds 10
$fxAfter=FxSnapshot;$fxUnchanged=$true
if($fxBefore.Count -ne $fxAfter.Count){$fxUnchanged=$false}
foreach($key in $fxBefore.Keys){if($fxBefore[$key] -ne $fxAfter[$key]){$fxUnchanged=$false}}
if($success -and $null -ne $baseline) {
    $baseline.fxify_unchanged=$fxUnchanged
    $baseline.fxify_after=$fxAfter
    $baseline | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $root 'state\fp-adaptive-payoff-v1-bank1r-baseline.json')
    $baseline | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $share 'remote-output\fp-adaptive-payoff-v1-bank1r-baseline.json')
}
$after=Runtime
$task=Get-ScheduledTask -TaskName $watchdogName;$info=Get-ScheduledTaskInfo -TaskName $watchdogName
$events=Get-Content -Raw (Join-Path $root 'logs\watchdog-last.json') | ConvertFrom-Json
$fpEvent=@($events | Where-Object {$_.id -eq 'fp-demo'})[-1]
$watchdogHealthy=$task.State -ne 'Disabled' -and $fpEvent.action -eq 'HEALTHY'
$granted=@();$nowEpoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
foreach($file in Get-ChildItem -LiteralPath (Join-Path $fp 'MQL5\Files\SolTradeOwnership') -Filter 'permit-*.txt' -File) {
    $values=@{};foreach($line in Get-Content -LiteralPath $file.FullName){if($line -match '^([^=]+)=(.*)$'){$values[$matches[1]]=$matches[2]}}
    if($values.state -eq 'GRANTED' -and [long]$values.expires_epoch -gt $nowEpoch){$granted+=[string]$values.runtime_id}
}
$activeOwners=@($granted | Sort-Object -Unique)
$singleOwner=$activeOwners.Count -eq 1 -and $activeOwners[0] -eq $after.owner_runtime_id
$report=[ordered]@{
    status=if($success -and $fxUnchanged -and $watchdogHealthy -and $singleOwner){'DEPLOYED_AND_VERIFIED'}else{'FAILED_OR_ROLLED_BACK'}
    captured_utc=[DateTime]::UtcNow.ToString('o');failure=$failure;account=7404213;runtime=$after
    source_sha256=Hash "$expert.mq5";binary_sha256=Hash "$expert.ex5";target_risk_percent=1.00;scope='FP_7404213_ONLY'
    manager_version='ADAPTIVE_PAYOFF_V1_BANK1R';sizing_verification='Unchanged CalculateLots body + pinned 1.00% OnInit guard + installed hashes.'
    structural_stop_logic_unchanged=$true;entry_logic_unchanged=$true;management_changed=$true;portfolio_cap_percent=1.50
    fp_flat_before=$before;fp_flat_after_lease_expiry=$lastFlat;changed_files=$changed;backup=$backup
    fp_process_count=@(Processes $fp).Count;fp_pid=@(Processes $fp)[0].Id
    active_granted_runtime_ids=$activeOwners;duplicate_sender_count=[Math]::Max(0,$activeOwners.Count-1);single_active_owner=$singleOwner
    fxify_unchanged=$fxUnchanged;fxify_before=$fxBefore;fxify_after=$fxAfter
    watchdog_healthy=$watchdogHealthy;watchdog_state=[string]$task.State;watchdog_last_result=[long]$info.LastTaskResult
    baseline='FP_ADAPTIVE_PAYOFF_V1_BANK1R_FORWARD_BASELINE';fake_or_forced_orders_sent=$false
}
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $output
if($report.status -ne 'DEPLOYED_AND_VERIFIED'){throw 'FP deployment did not pass all final checks'}
