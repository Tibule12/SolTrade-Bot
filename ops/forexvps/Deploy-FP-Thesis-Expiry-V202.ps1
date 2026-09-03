[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$fpHome = 'C:\SolTrade\MT5-FP-DEMO'
$expert = 'SolTradeFastMultiMarketV2'
$state = 'SolTradeFastMultiMarketV2'
$account = 7404213
$expectedSource = 'dfb83209dbbee9a2ca511c9f3cd436f3268e479a427e60f670e37c6637932e24'
$expectedBinary = '219b6204c9c2e1d52092db61b1e56be3c834d71f8b940409e7b78dd066521c0c'
$output = Join-Path $share 'remote-output\fp-thesis-expiry-deployment.json'
$watchdogName = 'SolTrade-Watchdog'

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
function Get-TerminalProcesses([string]$TerminalHome) {
    $terminal = Join-Path $TerminalHome 'terminal64.exe'
    @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal })
}
function Test-FpHealthy($Runtime,[int]$ProcessCount,[string]$SourceSha,[string]$BinarySha) {
    $Runtime -and $ProcessCount -eq 1 -and $SourceSha -eq $expectedSource -and $BinarySha -eq $expectedBinary -and
    [long]$Runtime.login -eq $account -and $Runtime.server -eq 'FPMarketsSC-Demo' -and
    $Runtime.connected -eq 'true' -and $Runtime.scanner_active -eq 'true' -and
    $Runtime.autonomous_entry -eq 'true' -and $Runtime.ownership_permit -eq 'GRANTED'
}

$sharedSource = Join-Path $share "payload\fp-demo\$expert.mq5"
$sharedBinary = Join-Path $share "payload\fp-demo\$expert.ex5"
if ((Get-Sha $sharedSource) -ne $expectedSource -or (Get-Sha $sharedBinary) -ne $expectedBinary) {
    throw 'Reviewed FP release hash mismatch'
}
$before = Read-Runtime $state
if (-not $before -or [long]$before.login -ne $account -or $before.server -ne 'FPMarketsSC-Demo') { throw 'FP runtime identity mismatch' }
if ([int]$before.positions -ne 0 -or [int]$before.orders -ne 0) { throw 'FP deployment blocked: exposure is open' }
$fpBefore = @(Get-TerminalProcesses $fpHome)
if ($fpBefore.Count -ne 1) { throw "Expected one FP terminal, found $($fpBefore.Count)" }
$fxHomes = @('C:\SolTrade\MT5-FXIFY-10K','C:\SolTrade\MT5-FXIFY-100K')
$fxBefore = @($fxHomes | ForEach-Object { Get-TerminalProcesses $_ } | Select-Object ProcessId,ExecutablePath)

$watchdog = Get-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
if (-not $watchdog) { throw 'SolTrade watchdog task missing' }
$watchdogWasEnabled = $watchdog.State -ne 'Disabled'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backups\fp-thesis-expiry-v202-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$success = $false
try {
    Disable-ScheduledTask -TaskName $watchdogName | Out-Null
    Stop-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SolTrade-AccountOwnership-$account" -ErrorAction SilentlyContinue

    $lastFlat = Read-Runtime $state
    if (-not $lastFlat -or [int]$lastFlat.positions -ne 0 -or [int]$lastFlat.orders -ne 0) { throw 'FP deployment blocked at final exposure check' }
    Get-TerminalProcesses $fpHome | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep -Seconds 3

    $expertRoot = Join-Path $fpHome 'MQL5\Experts\SolTrade'
    foreach ($extension in @('mq5','ex5')) {
        $installed = Join-Path $expertRoot "$expert.$extension"
        if (Test-Path -LiteralPath $installed) { Copy-Item -Force -LiteralPath $installed -Destination $backup }
        Copy-Item -Force -LiteralPath (Join-Path $share "payload\fp-demo\$expert.$extension") -Destination $installed
    }
    Start-ScheduledTask -TaskName "SolTrade-AccountOwnership-$account"
    Start-Process -FilePath (Join-Path $fpHome 'terminal64.exe') -WorkingDirectory $fpHome -ArgumentList @(
        '/portable', "/login:$account", '/profile:SolTradeV202FP', "/config:$root\state\fp-demo.ini"
    )

    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 5
        $runtime = Read-Runtime $state
        $processes = @(Get-TerminalProcesses $fpHome)
        $sourceSha = Get-Sha (Join-Path $expertRoot "$expert.mq5")
        $binarySha = Get-Sha (Join-Path $expertRoot "$expert.ex5")
        $healthy = Test-FpHealthy $runtime $processes.Count $sourceSha $binarySha
    } while (-not $healthy -and (Get-Date) -lt $deadline)
    if (-not $healthy) { throw 'FP post-deployment verification timed out' }
    $success = $true
} finally {
    if ($watchdogWasEnabled) { Enable-ScheduledTask -TaskName $watchdogName | Out-Null }
    Start-ScheduledTask -TaskName $watchdogName -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 20
$after = Read-Runtime $state
$fpAfter = @(Get-TerminalProcesses $fpHome)
$fxAfter = @($fxHomes | ForEach-Object { Get-TerminalProcesses $_ } | Select-Object ProcessId,ExecutablePath)
$watchdogAfter = Get-ScheduledTask -TaskName $watchdogName
$finalHealthy = Test-FpHealthy $after $fpAfter.Count (Get-Sha (Join-Path $expertRoot "$expert.mq5")) (Get-Sha (Join-Path $expertRoot "$expert.ex5"))
$fxUnchanged = (@($fxBefore.ProcessId) -join ',') -eq (@($fxAfter.ProcessId) -join ',')
$report = [ordered]@{
    schema='SOLTRADE_FP_V202_THESIS_EXPIRY_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if ($success -and $finalHealthy -and $fxUnchanged -and $watchdogAfter.State -ne 'Disabled') { 'DEPLOYED_AND_VERIFIED' } else { 'FAILED' }
    source_sha256=Get-Sha (Join-Path $expertRoot "$expert.mq5")
    binary_sha256=Get-Sha (Join-Path $expertRoot "$expert.ex5")
    fp_process_count=$fpAfter.Count
    fxify_processes_unchanged=$fxUnchanged
    watchdog_state=[string]$watchdogAfter.State
    test_orders_placed=$false
    runtime=$after
    backup=$backup
}
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $output
if ($report.status -ne 'DEPLOYED_AND_VERIFIED') { throw 'FP final verification failed' }
