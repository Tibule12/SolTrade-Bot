[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$output = Join-Path $share 'remote-output\evidence-exit-v202-deployment.json'
$watchdogName = 'SolTrade-Watchdog'
$instances = @(
    @{ id='fp-demo'; account=7404213; server='FPMarketsSC-Demo'; terminalHome='C:\SolTrade\MT5-FP-DEMO'; state='SolTradeFastMultiMarketV2'; folder='payload\fp-demo'; expert='SolTradeFastMultiMarketV2'; source='97c7ac5f5f19969d02321c2ee75a21895524c77dbe358c8cca3c3173a87441a5'; binary='dd4fd88178004a4d518dde514238ae90f54162e6f951bcc7755d08dad97222b3'; profile='SolTradeV202FP'; config='fp-demo.ini' },
    @{ id='fxify-10k'; account=7196820; server='FXIFY-Server'; terminalHome='C:\SolTrade\MT5-FXIFY-10K'; state='SolTradeFastMultiMarketV2F10'; folder='payload\fxify-10k'; expert='SolTradeFastMultiMarketV202F10'; source='e33223dc24beb434dd361c9422e1324395bd366880e075f9d4b4f0ffd9999d9e'; binary='b2585ed06962957aa4c82f85a870c6c24985d79c26bd2b9c383ef9ecefee040c'; profile='SolTradeV202F10'; config='fxify-10k.ini' },
    @{ id='fxify-100k'; account=7198096; server='FXIFY-Server'; terminalHome='C:\SolTrade\MT5-FXIFY-100K'; state='SolTradeFastMultiMarketV2F100'; folder='payload\fxify-100k'; expert='SolTradeFastMultiMarketV202F100'; source='f4cf460097b529c009a2272df189211f6d6c3965ff413c16aa2050da6c12626d'; binary='ab22637b7a449ce96053e285ed1744c1ff8e2c3ed193b1f6edbbb2b210338c62'; profile='SolTradeV202F100'; config='fxify-100k.ini' }
)

function Get-Sha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function Get-Terminals($Instance) {
    $terminal = Join-Path $Instance.terminalHome 'terminal64.exe'
    return @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal })
}
function Get-Runtime($Instance) {
    $path = Join-Path (Join-Path $common $Instance.state) 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    for ($attempt=0; $attempt -lt 10; $attempt++) {
        $stream = $null
        $reader = $null
        try {
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            )
            $reader = New-Object System.IO.StreamReader($stream)
            $header = $reader.ReadLine()
            $data = $reader.ReadLine()
            if ($header -and $data) {
                return ("$header`r`n$data" | ConvertFrom-Csv | Select-Object -First 1)
            }
        } catch {
            Start-Sleep -Milliseconds 100
        } finally {
            if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
        }
    }
    return $null
}
function Start-Instance($Instance) {
    Start-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($Instance.account)"
    Start-Process -FilePath (Join-Path $Instance.terminalHome 'terminal64.exe') `
        -WorkingDirectory $Instance.terminalHome -ArgumentList @(
            '/portable', "/login:$($Instance.account)", "/profile:$($Instance.profile)",
            "/config:$root\state\$($Instance.config)"
        )
}
function Stop-Instance($Instance) {
    Stop-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($Instance.account)" -ErrorAction SilentlyContinue
    Get-Terminals $Instance | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}
function Test-Healthy($Instance) {
    $runtime = Get-Runtime $Instance
    $expertRoot = Join-Path $Instance.terminalHome 'MQL5\Experts\SolTrade'
    return $runtime -and (@(Get-Terminals $Instance)).Count -eq 1 -and
        (Get-Sha (Join-Path $expertRoot "$($Instance.expert).mq5")) -eq $Instance.source -and
        (Get-Sha (Join-Path $expertRoot "$($Instance.expert).ex5")) -eq $Instance.binary -and
        [long]$runtime.login -eq [long]$Instance.account -and $runtime.server -eq $Instance.server -and
        $runtime.connected -eq 'true' -and $runtime.scanner_active -eq 'true' -and
        $runtime.autonomous_entry -eq 'true' -and $runtime.ownership_permit -eq 'GRANTED'
}

foreach ($instance in $instances) {
    $runtime = Get-Runtime $instance
    if (-not $runtime -or [long]$runtime.login -ne [long]$instance.account -or $runtime.server -ne $instance.server) {
        throw "Preflight identity mismatch: $($instance.id)"
    }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Deployment blocked by exposure: $($instance.id)"
    }
    if ((@(Get-Terminals $instance)).Count -ne 1) { throw "Expected one terminal: $($instance.id)" }
    $sharedRoot = Join-Path $share $instance.folder
    if ((Get-Sha (Join-Path $sharedRoot "$($instance.expert).mq5")) -ne $instance.source -or
        (Get-Sha (Join-Path $sharedRoot "$($instance.expert).ex5")) -ne $instance.binary) {
        throw "Reviewed release hash mismatch: $($instance.id)"
    }
}

$watchdog = Get-ScheduledTask -TaskName $watchdogName -ErrorAction Stop
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backups\evidence-exit-v202-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$deployed = $false
$rolledBack = $false
$failure = $null
try {
    Disable-ScheduledTask -TaskName $watchdogName | Out-Null
    Stop-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
    foreach ($instance in $instances) {
        Stop-ScheduledTask -TaskName "SolTrade-AccountOwnership-$($instance.account)" -ErrorAction SilentlyContinue
    }
    # Wait beyond the 15-second lease TTL before the final flat check. This
    # prevents an old EA from sending while files are being replaced.
    Start-Sleep -Seconds 18
    foreach ($instance in $instances) {
        $runtime = Get-Runtime $instance
        if (-not $runtime -or [int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
            throw "Final flat check failed: $($instance.id)"
        }
    }
    foreach ($instance in $instances) { Stop-Instance $instance }
    Start-Sleep -Seconds 3

    foreach ($instance in $instances) {
        $backupInstance = Join-Path $backup $instance.id
        New-Item -ItemType Directory -Force -Path $backupInstance | Out-Null
        $expertRoot = Join-Path $instance.terminalHome 'MQL5\Experts\SolTrade'
        $sharedRoot = Join-Path $share $instance.folder
        foreach ($extension in @('mq5','ex5')) {
            $name = "$($instance.expert).$extension"
            $installed = Join-Path $expertRoot $name
            Copy-Item -Force -LiteralPath $installed -Destination (Join-Path $backupInstance $name)
            Copy-Item -Force -LiteralPath (Join-Path $sharedRoot $name) -Destination $installed
        }
    }
    foreach ($instance in $instances) { Start-Instance $instance }

    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 5
        $healthy = @($instances | Where-Object { Test-Healthy $_ }).Count
    } while ($healthy -ne $instances.Count -and (Get-Date) -lt $deadline)
    if ($healthy -ne $instances.Count) { throw "Post-deployment health timeout: $healthy/3" }
    $deployed = $true
} catch {
    $failure = $_.Exception.Message
    foreach ($instance in $instances) { Stop-Instance $instance }
    Start-Sleep -Seconds 3
    foreach ($instance in $instances) {
        $backupInstance = Join-Path $backup $instance.id
        $expertRoot = Join-Path $instance.terminalHome 'MQL5\Experts\SolTrade'
        foreach ($extension in @('mq5','ex5')) {
            $name = "$($instance.expert).$extension"
            $saved = Join-Path $backupInstance $name
            if (Test-Path -LiteralPath $saved) { Copy-Item -Force -LiteralPath $saved -Destination (Join-Path $expertRoot $name) }
        }
        Start-Instance $instance
    }
    $rolledBack = $true
} finally {
    Enable-ScheduledTask -TaskName $watchdogName | Out-Null
    Start-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 20
$results = @()
foreach ($instance in $instances) {
    $runtime = Get-Runtime $instance
    $expertRoot = Join-Path $instance.terminalHome 'MQL5\Experts\SolTrade'
    $results += [ordered]@{
        id=$instance.id
        account=$instance.account
        server=$instance.server
        process_count=(@(Get-Terminals $instance)).Count
        source_sha256=Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")
        binary_sha256=Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")
        connected=if ($runtime) { $runtime.connected } else { $null }
        scanner_active=if ($runtime) { $runtime.scanner_active } else { $null }
        autonomous_entry=if ($runtime) { $runtime.autonomous_entry } else { $null }
        ownership_permit=if ($runtime) { $runtime.ownership_permit } else { $null }
        positions=if ($runtime) { $runtime.positions } else { $null }
        orders=if ($runtime) { $runtime.orders } else { $null }
        status=if ($runtime) { $runtime.status } else { $null }
        healthy=if ($deployed) { Test-Healthy $instance } else { $false }
    }
}
$watchdogAfter = Get-ScheduledTask -TaskName $watchdogName
$status = if ($deployed -and @($results | Where-Object { -not $_.healthy }).Count -eq 0 -and
    $watchdogAfter.State -ne 'Disabled') { 'DEPLOYED_AND_VERIFIED' } elseif ($rolledBack) { 'FAILED_ROLLED_BACK' } else { 'FAILED' }
$report = [ordered]@{
    schema='SOLTRADE_V202_EVIDENCE_EXIT_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=$status
    strategy_version='2.202'
    admission_changed=$false
    risk_changed=$false
    min_reward_r_changed=$false
    test_orders_placed=$false
    backup=$backup
    failure=$failure
    watchdog_state=[string]$watchdogAfter.State
    instances=$results
}
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $output
if ($status -ne 'DEPLOYED_AND_VERIFIED') { throw "Deployment failed: $status; $failure" }
