[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$output = Join-Path $share 'remote-output\scratch-retired-v202-deployment.json'
$startedUtc = [DateTime]::UtcNow
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backups\scratch-retired-v202-$stamp"
$watchdogName = 'SolTrade-Watchdog'

$instances = @(
    [ordered]@{ id='fp'; account=7404213; server='FPMarketsSC-Demo'; home='C:\SolTrade\MT5-FP-DEMO'; profile='SolTradeV202FP'; ini='fp-demo.ini'; state='SolTradeFastMultiMarketV2'; expert='SolTradeFastMultiMarketV2'; preset='SolTradeFastMultiMarketV2-FPMarkets-demo.set'; folder='payload\fp-demo'; source_sha='7f9e64443853387de2fe3aef86879dceb5710f6cf04f05acb7cab87f0cdb5429'; binary_sha='b53a7e6d74cff2488b338a21017f3a7c1836b3bb6330ccb312547c5e4e1975a4' },
    [ordered]@{ id='f10'; account=7196820; server='FXIFY-Server'; home='C:\SolTrade\MT5-FXIFY-10K'; profile='SolTradeV202F10'; ini='fxify-10k.ini'; state='SolTradeFastMultiMarketV2F10'; expert='SolTradeFastMultiMarketV202F10'; preset='SolTradeFastMultiMarketV202F10-FINAL-ALGO-OFF.set'; folder='payload\fxify-10k'; source_sha='7efbe782ba6be7dbe98a114a0ba844430adbb6b5eafef5bf7d77e3491bc59aed'; binary_sha='23b2c42dc291f3ce7fe672f7cbfccad0e4d11b77a79e220638732dbe1d0bc0cc' },
    [ordered]@{ id='f100'; account=7198096; server='FXIFY-Server'; home='C:\SolTrade\MT5-FXIFY-100K'; profile='SolTradeV202F100'; ini='fxify-100k.ini'; state='SolTradeFastMultiMarketV2F100'; expert='SolTradeFastMultiMarketV202F100'; preset='SolTradeFastMultiMarketV202F100-FINAL-ALGO-OFF.set'; folder='payload\fxify-100k'; source_sha='3ea787c24884fac8696fabb266dd59b7ada17e95faaa9432a7b6a3e8ec2a7590'; binary_sha='c5855b89a57ecfa7770344955ec9f5a5bb9da09ae339426c40729c1939895ba5' }
)

function Get-Sha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Runtime([string]$State) {
    $path = Join-Path (Join-Path $common $State) 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

function Assert-FlatHealthy($Instance) {
    $runtime = Read-Runtime $Instance.state
    if (-not $runtime) { throw "Missing runtime telemetry for $($Instance.id)" }
    if ([long]$runtime.login -ne [long]$Instance.account -or [string]$runtime.server -ne [string]$Instance.server) {
        throw "Identity mismatch for $($Instance.id)"
    }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Exposure open on $($Instance.id): positions=$($runtime.positions), orders=$($runtime.orders)"
    }
    return $runtime
}

function Ensure-CorrectedPolicyPreset([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines -match '^ImmediateDirectionalScratchEnabled=') {
        $lines = @($lines -replace '^ImmediateDirectionalScratchEnabled=.*$', 'ImmediateDirectionalScratchEnabled=false')
    } else {
        $updated = @()
        foreach ($line in $lines) {
            $updated += $line
            if ($line -match '^MaxSlippagePoints=') { $updated += 'ImmediateDirectionalScratchEnabled=false' }
        }
        $lines = $updated
    }
    if ($lines -match '^ConfirmedProfitMinimumNetR=') {
        $lines = @($lines -replace '^ConfirmedProfitMinimumNetR=.*$', 'ConfirmedProfitMinimumNetR=0.10')
    } else {
        $updated = @()
        foreach ($line in $lines) {
            $updated += $line
            if ($line -match '^MaxSlippagePoints=') { $updated += 'ConfirmedProfitMinimumNetR=0.10' }
        }
        $lines = $updated
    }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Force -Path $backup,(Split-Path -Parent $output) | Out-Null
$preflight = @()
foreach ($instance in $instances) {
    $runtime = Assert-FlatHealthy $instance
    $sharedSource = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5"
    $sharedBinary = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5"
    if ((Get-Sha $sharedSource) -ne $instance.source_sha) { throw "Reviewed source hash mismatch for $($instance.id)" }
    if ((Get-Sha $sharedBinary) -ne $instance.binary_sha) { throw "Reviewed binary hash mismatch for $($instance.id)" }
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $instance.home 'terminal64.exe') })
    if ($processes.Count -ne 1) { throw "Expected one terminal for $($instance.id), found $($processes.Count)" }
    $preflight += [ordered]@{ id=$instance.id; runtime=$runtime; pid=$processes[0].ProcessId }
}

$watchdog = Get-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
if (-not $watchdog) { throw 'SolTrade watchdog task missing' }
$watchdogWasEnabled = $watchdog.State -ne 'Disabled'
$post = @()
$deploymentSucceeded = $false
try {
    Disable-ScheduledTask -TaskName $watchdogName | Out-Null
    Stop-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue

    foreach ($instance in $instances) {
        Stop-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($instance.account)" -ErrorAction SilentlyContinue
    }

    # Recheck immediately before the stop; no open exposure is ever interrupted.
    foreach ($instance in $instances) { [void](Assert-FlatHealthy $instance) }
    foreach ($instance in $instances) {
        $terminal = Join-Path $instance.home 'terminal64.exe'
        Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
            Where-Object { $_.ExecutablePath -eq $terminal } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    }
    Start-Sleep -Seconds 3

    Copy-Item -Force -LiteralPath (Join-Path $share 'Run-AccountOwnershipAuthority.ps1') -Destination (Join-Path $root 'ownership\Run-AccountOwnershipAuthority.ps1')

    foreach ($instance in $instances) {
        $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
        $presetPath = Join-Path $instance.home "MQL5\Presets\$($instance.preset)"
        $instanceBackup = Join-Path $backup $instance.id
        New-Item -ItemType Directory -Force -Path $instanceBackup | Out-Null
        foreach ($path in @((Join-Path $expertRoot "$($instance.expert).mq5"),(Join-Path $expertRoot "$($instance.expert).ex5"),$presetPath)) {
            if (Test-Path -LiteralPath $path) { Copy-Item -Force -LiteralPath $path -Destination $instanceBackup }
        }
        Copy-Item -Force -LiteralPath (Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5") -Destination (Join-Path $expertRoot "$($instance.expert).mq5")
        Copy-Item -Force -LiteralPath (Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5") -Destination (Join-Path $expertRoot "$($instance.expert).ex5")
        Ensure-CorrectedPolicyPreset $presetPath
        Copy-Item -Force -LiteralPath (Join-Path $share "runtime\$($instance.ini)") -Destination (Join-Path $root "state\$($instance.ini)")
    }

    foreach ($instance in $instances) {
        Start-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($instance.account)"
    }

    foreach ($instance in $instances) {
        $terminal = Join-Path $instance.home 'terminal64.exe'
        $startup = Join-Path $root "state\$($instance.ini)"
        Start-Process -FilePath $terminal -WorkingDirectory $instance.home -ArgumentList @('/portable',"/login:$($instance.account)","/profile:$($instance.profile)","/config:$startup")
    }
    Start-Sleep -Seconds 55

    foreach ($instance in $instances) {
        $runtime = Read-Runtime $instance.state
        $terminal = Join-Path $instance.home 'terminal64.exe'
        $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal })
        $post += [ordered]@{
            id=$instance.id
            account=$instance.account
            process_count=$processes.Count
            source_sha256=Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")
            binary_sha256=Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")
            source_hash_matches=((Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")) -eq $instance.source_sha)
            binary_hash_matches=((Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")) -eq $instance.binary_sha)
            scratch_input=((Get-Content -LiteralPath (Join-Path $instance.home "MQL5\Presets\$($instance.preset)") | Where-Object { $_ -match '^ImmediateDirectionalScratchEnabled=' }) -join '')
            confirmed_profit_floor_input=((Get-Content -LiteralPath (Join-Path $instance.home "MQL5\Presets\$($instance.preset)") | Where-Object { $_ -match '^ConfirmedProfitMinimumNetR=' }) -join '')
            runtime=$runtime
        }
    }
    $failed = @($post | Where-Object {
        $_.process_count -ne 1 -or -not $_.source_hash_matches -or -not $_.binary_hash_matches -or
        $_.scratch_input -ne 'ImmediateDirectionalScratchEnabled=false' -or
        $_.confirmed_profit_floor_input -ne 'ConfirmedProfitMinimumNetR=0.10' -or -not $_.runtime -or
        $_.runtime.connected -ne 'true' -or $_.runtime.scanner_active -ne 'true' -or
        $_.runtime.autonomous_entry -ne 'true' -or $_.runtime.ownership_permit -ne 'GRANTED'
    })
    if ($failed.Count -gt 0) { throw "Post-deployment runtime verification failed: $($failed.id -join ',')" }
    $deploymentSucceeded = $true
} finally {
    if ($watchdogWasEnabled) { Enable-ScheduledTask -TaskName $watchdogName | Out-Null }
    Start-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 20
$watchdogPost = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $instance.state
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal })
    $watchdogPost += [ordered]@{ id=$instance.id; process_count=$processes.Count; runtime=$runtime }
}

$report = [ordered]@{
    schema='SOLTRADE_V202_POSITIVE_CONFIRMED_PROFIT_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if ($deploymentSucceeded) { 'DEPLOYED_AND_RUNTIME_VERIFIED' } else { 'FAILED' }
    strategy_version='2.202'
    first_adverse_tick_scratch_enabled=$false
    confirmed_profit_minimum_net_r=0.10
    admission_logic_changed=$false
    risk_sizing_changed=$false
    min_reward_r_changed=$false
    runner_logic_changed=$true
    ownership_logic_changed=$true
    test_orders_placed=$false
    backup=$backup
    preflight=$preflight
    post_deployment=$post
    post_watchdog=$watchdogPost
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $output
$report | ConvertTo-Json -Depth 12
