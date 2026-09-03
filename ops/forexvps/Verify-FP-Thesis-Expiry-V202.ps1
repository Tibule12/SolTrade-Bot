[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$fpHome = 'C:\SolTrade\MT5-FP-DEMO'
$expert = 'SolTradeFastMultiMarketV2'
$expectedSource = 'dfb83209dbbee9a2ca511c9f3cd436f3268e479a427e60f670e37c6637932e24'
$expectedBinary = '219b6204c9c2e1d52092db61b1e56be3c834d71f8b940409e7b78dd066521c0c'
$output = Join-Path $share 'remote-output\fp-thesis-expiry-verification.json'

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
function Get-Processes([string]$TerminalHome) {
    $terminal = Join-Path $TerminalHome 'terminal64.exe'
    @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal })
}

$runtime = Read-Runtime 'SolTradeFastMultiMarketV2'
$expertRoot = Join-Path $fpHome 'MQL5\Experts\SolTrade'
$sourceSha = Get-Sha (Join-Path $expertRoot "$expert.mq5")
$binarySha = Get-Sha (Join-Path $expertRoot "$expert.ex5")
$fpProcesses = @(Get-Processes $fpHome)
$fx10Processes = @(Get-Processes 'C:\SolTrade\MT5-FXIFY-10K')
$fx100Processes = @(Get-Processes 'C:\SolTrade\MT5-FXIFY-100K')
$watchdog = Get-ScheduledTask -TaskName 'SolTrade-Watchdog' -ErrorAction SilentlyContinue
$ownershipTask = Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -ErrorAction SilentlyContinue
$healthy = $runtime -and $fpProcesses.Count -eq 1 -and $sourceSha -eq $expectedSource -and $binarySha -eq $expectedBinary -and
    [long]$runtime.login -eq 7404213 -and $runtime.server -eq 'FPMarketsSC-Demo' -and
    $runtime.connected -eq 'true' -and $runtime.scanner_active -eq 'true' -and
    $runtime.autonomous_entry -eq 'true' -and $runtime.ownership_permit -eq 'GRANTED' -and
    $runtime.owner_instance_id -eq 'vps-fp-prod' -and $runtime.owner_account -eq '7404213' -and
    -not [string]::IsNullOrWhiteSpace($runtime.lease_id) -and [int]$runtime.positions -eq 0 -and [int]$runtime.orders -eq 0 -and
    $fx10Processes.Count -eq 1 -and $fx100Processes.Count -eq 1 -and $watchdog -and $watchdog.State -ne 'Disabled' -and $ownershipTask

$report = [ordered]@{
    schema='SOLTRADE_FP_V202_THESIS_EXPIRY_VERIFICATION_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if ($healthy) { 'VERIFIED' } else { 'FAILED' }
    source_sha256=$sourceSha
    binary_sha256=$binarySha
    fp_process_count=$fpProcesses.Count
    fxify_10k_process_count=$fx10Processes.Count
    fxify_100k_process_count=$fx100Processes.Count
    watchdog_state=if ($watchdog) { [string]$watchdog.State } else { 'MISSING' }
    ownership_task_state=if ($ownershipTask) { [string]$ownershipTask.State } else { 'MISSING' }
    runtime=$runtime
    test_orders_placed=$false
}
$report | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $output
if (-not $healthy) { throw 'FP independent verification failed' }
