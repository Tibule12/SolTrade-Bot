[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$output = Join-Path $share 'remote-output\fxify-thesis-expiry-deployment.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backups\fxify-thesis-expiry-v202-$stamp"
$watchdogName = 'SolTrade-Watchdog'
$instances = @(
    [ordered]@{ id='f10'; account=7196820; server='FXIFY-Server'; home='C:\SolTrade\MT5-FXIFY-10K'; profile='SolTradeV202F10'; ini='fxify-10k.ini'; state='SolTradeFastMultiMarketV2F10'; expert='SolTradeFastMultiMarketV202F10'; folder='payload\fxify-10k'; source_sha='f10374a87626f8e3eb575408438c153744bb62cd7b7ce98e501c8a0eb45e0fac'; binary_sha='3b6756ca69fd0cc67dee8123cab1e769cf4e372b8e6eea8798f304abcd5a02d3' },
    [ordered]@{ id='f100'; account=7198096; server='FXIFY-Server'; home='C:\SolTrade\MT5-FXIFY-100K'; profile='SolTradeV202F100'; ini='fxify-100k.ini'; state='SolTradeFastMultiMarketV2F100'; expert='SolTradeFastMultiMarketV202F100'; folder='payload\fxify-100k'; source_sha='c1408703cc621d94c77f0100f5f6c57337e9137b77536f4059bba3ef72e10dcc'; binary_sha='42e4508c1584d4d42f3529da103e0314b090410f56849e36c63599a83a39b876' }
)

function Get-Sha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Runtime([string]$State) {
    $path = Join-Path (Join-Path $common $State) 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    $lines | ConvertFrom-Csv | Select-Object -First 1
}

function Assert-FlatHealthy($Instance) {
    $runtime = Read-Runtime $Instance.state
    if (-not $runtime) { throw "Missing runtime telemetry for $($Instance.id)" }
    if ([long]$runtime.login -ne [long]$Instance.account -or [string]$runtime.server -ne [string]$Instance.server) {
        throw "Identity mismatch for $($Instance.id)"
    }
    if ($runtime.connected -ne 'true' -or $runtime.scanner_active -ne 'true') {
        throw "Runtime not healthy for $($Instance.id)"
    }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Exposure open on $($Instance.id): positions=$($runtime.positions), orders=$($runtime.orders)"
    }
    $runtime
}

$fpHome = 'C:\SolTrade\MT5-FP-DEMO'
$fpBefore = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $fpHome 'terminal64.exe') } | Select-Object ProcessId,ExecutablePath)
$preflight = @()
foreach ($instance in $instances) {
    $runtime = Assert-FlatHealthy $instance
    $sharedSource = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5"
    $sharedBinary = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5"
    if ((Get-Sha $sharedSource) -ne $instance.source_sha) { throw "Reviewed source hash mismatch for $($instance.id)" }
    if ((Get-Sha $sharedBinary) -ne $instance.binary_sha) { throw "Reviewed binary hash mismatch for $($instance.id)" }
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $instance.home 'terminal64.exe') })
    if ($processes.Count -ne 1) { throw "Expected one terminal for $($instance.id), found $($processes.Count)" }
    $preflight += [ordered]@{ id=$instance.id; pid=$processes[0].ProcessId; runtime=$runtime }
}

New-Item -ItemType Directory -Force -Path $backup,(Split-Path -Parent $output) | Out-Null
$watchdog = Get-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
if (-not $watchdog) { throw 'SolTrade watchdog task missing' }
$watchdogWasEnabled = $watchdog.State -ne 'Disabled'
$post = @()
$success = $false
try {
    Disable-ScheduledTask -TaskName $watchdogName | Out-Null
    Stop-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
    foreach ($instance in $instances) { Stop-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($instance.account)" -ErrorAction SilentlyContinue }

    foreach ($instance in $instances) { [void](Assert-FlatHealthy $instance) }
    foreach ($instance in $instances) {
        $terminal = Join-Path $instance.home 'terminal64.exe'
        Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
            Where-Object { $_.ExecutablePath -eq $terminal } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    }
    Start-Sleep -Seconds 3

    foreach ($instance in $instances) {
        $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
        $instanceBackup = Join-Path $backup $instance.id
        New-Item -ItemType Directory -Force -Path $instanceBackup | Out-Null
        foreach ($extension in @('mq5','ex5')) {
            $installed = Join-Path $expertRoot "$($instance.expert).$extension"
            if (Test-Path -LiteralPath $installed) { Copy-Item -Force -LiteralPath $installed -Destination $instanceBackup }
            Copy-Item -Force -LiteralPath (Join-Path (Join-Path $share $instance.folder) "$($instance.expert).$extension") -Destination $installed
        }
    }

    foreach ($instance in $instances) { Start-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($instance.account)" }
    foreach ($instance in $instances) {
        Start-Process -FilePath (Join-Path $instance.home 'terminal64.exe') -WorkingDirectory $instance.home -ArgumentList @(
            '/portable', "/login:$($instance.account)", "/profile:$($instance.profile)", "/config:$root\state\$($instance.ini)"
        )
    }
    # Terminal startup, history warm-up and ownership acquisition can take over
    # a minute on this VPS. Poll the final state instead of sampling once.
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $post = @()
        $failed = @()
        foreach ($instance in $instances) {
            $runtime = Read-Runtime $instance.state
            $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
            $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $instance.home 'terminal64.exe') })
            $sourceSha = Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")
            $binarySha = Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")
            $healthy = $processes.Count -eq 1 -and $sourceSha -eq $instance.source_sha -and $binarySha -eq $instance.binary_sha -and
                $runtime -and $runtime.connected -eq 'true' -and $runtime.scanner_active -eq 'true' -and
                $runtime.autonomous_entry -eq 'true' -and $runtime.ownership_permit -eq 'GRANTED'
            $post += [ordered]@{
                id=$instance.id
                healthy=$healthy
                process_count=$processes.Count
                source_sha256=$sourceSha
                binary_sha256=$binarySha
                runtime=$runtime
            }
            if (-not $healthy) { $failed += $instance.id }
        }
        if ($failed.Count -eq 0) { break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    if ($failed.Count -gt 0) { throw "Post-deployment verification timed out for $($failed -join ',')" }
    $success = $true
} finally {
    if ($watchdogWasEnabled) { Enable-ScheduledTask -TaskName $watchdogName | Out-Null }
    Start-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 20
$fpAfter = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $fpHome 'terminal64.exe') } | Select-Object ProcessId,ExecutablePath)
$watchdogPost = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $instance.state
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $instance.home 'terminal64.exe') })
    $watchdogPost += [ordered]@{ id=$instance.id; process_count=$processes.Count; runtime=$runtime }
}

[ordered]@{
    schema='SOLTRADE_FXIFY_V202_THESIS_EXPIRY_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if ($success) { 'DEPLOYED_AND_RUNTIME_VERIFIED' } else { 'FAILED' }
    strategy_version='2.202'
    change='OPPOSITE_THESIS_EXPIRES_AFTER_86400_SECONDS'
    admission_thresholds_changed=$false
    risk_sizing_changed=$false
    runner_logic_changed=$false
    ownership_logic_changed=$false
    test_orders_placed=$false
    fp_process_unchanged=(@($fpBefore.ProcessId) -join ',') -eq (@($fpAfter.ProcessId) -join ',')
    fp_before=$fpBefore
    fp_after=$fpAfter
    backup=$backup
    preflight=$preflight
    post_deployment=$post
    post_watchdog=$watchdogPost
} | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $output
