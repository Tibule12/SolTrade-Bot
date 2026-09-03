[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$output = Join-Path $share 'remote-output\fxify-thesis-expiry-verification.json'
$instances = @(
    [ordered]@{ id='f10'; account=7196820; home='C:\SolTrade\MT5-FXIFY-10K'; state='SolTradeFastMultiMarketV2F10'; expert='SolTradeFastMultiMarketV202F10'; source_sha='f10374a87626f8e3eb575408438c153744bb62cd7b7ce98e501c8a0eb45e0fac'; binary_sha='3b6756ca69fd0cc67dee8123cab1e769cf4e372b8e6eea8798f304abcd5a02d3' },
    [ordered]@{ id='f100'; account=7198096; home='C:\SolTrade\MT5-FXIFY-100K'; state='SolTradeFastMultiMarketV2F100'; expert='SolTradeFastMultiMarketV202F100'; source_sha='c1408703cc621d94c77f0100f5f6c57337e9137b77536f4059bba3ef72e10dcc'; binary_sha='42e4508c1584d4d42f3529da103e0314b090410f56849e36c63599a83a39b876' }
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

$results = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $instance.state
    $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $instance.home 'terminal64.exe') })
    $sourceSha = Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")
    $binarySha = Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")
    $healthy = $processes.Count -eq 1 -and $sourceSha -eq $instance.source_sha -and $binarySha -eq $instance.binary_sha -and
        $runtime -and [long]$runtime.login -eq $instance.account -and $runtime.server -eq 'FXIFY-Server' -and
        $runtime.connected -eq 'true' -and $runtime.scanner_active -eq 'true' -and
        $runtime.autonomous_entry -eq 'true' -and $runtime.ownership_permit -eq 'GRANTED'
    $results += [ordered]@{
        id=$instance.id
        account=$instance.account
        healthy=$healthy
        process_count=$processes.Count
        source_sha256=$sourceSha
        binary_sha256=$binarySha
        runtime=$runtime
    }
}

$fpHome = 'C:\SolTrade\MT5-FP-DEMO'
$fpProcesses = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq (Join-Path $fpHome 'terminal64.exe') })
$watchdog = Get-ScheduledTask -TaskName 'SolTrade-Watchdog' -ErrorAction SilentlyContinue
$report = [ordered]@{
    schema='SOLTRADE_FXIFY_V202_THESIS_EXPIRY_VERIFICATION_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if (@($results | Where-Object { -not $_.healthy }).Count -eq 0 -and $watchdog -and $watchdog.State -ne 'Disabled' -and $fpProcesses.Count -eq 1) { 'VERIFIED' } else { 'FAILED' }
    strategy_version='2.202'
    results=$results
    watchdog_state=if ($watchdog) { [string]$watchdog.State } else { 'MISSING' }
    fp_process_count=$fpProcesses.Count
    fp_touched=$false
    test_orders_placed=$false
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $output
if ($report.status -ne 'VERIFIED') { throw 'FXIFY post-deployment verification failed' }
