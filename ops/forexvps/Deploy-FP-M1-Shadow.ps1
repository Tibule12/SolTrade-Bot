[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $share 'remote-output\fp-m1-shadow-deployment.json'
$compileReportPath = Join-Path $share 'remote-output\fp-m1-shadow-compile.json'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$runtimePath = Join-Path $common 'SolTradeFastMultiMarketV2\runtime.csv'
$shadowPath = Join-Path $common ("SolTradeFastMultiMarketV2\m1-entry-evidence-shadow-v1-" + (Get-Date).ToUniversalTime().ToString('yyyyMMdd') + '.csv')
$terminalHome = 'C:\SolTrade\MT5-FP-DEMO'
$terminal = Join-Path $terminalHome 'terminal64.exe'
$expertDir = Join-Path $terminalHome 'MQL5\Experts\SolTrade'
$source = Join-Path $share 'payload\fp-demo\SolTradeFastMultiMarketV2.mq5'
$binary = Join-Path $share 'payload\fp-demo\SolTradeFastMultiMarketV2.ex5'
$targetSource = Join-Path $expertDir 'SolTradeFastMultiMarketV2.mq5'
$targetBinary = Join-Path $expertDir 'SolTradeFastMultiMarketV2.ex5'
$backup = "C:\SolTrade\backups\fp-m1-shadow-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Get-Sha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Runtime {
    if (-not (Test-Path -LiteralPath $runtimePath)) { return $null }
    $lines = @(Get-Content -LiteralPath $runtimePath -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

function Process-Snapshot {
    $items = @()
    foreach ($instance in @(
        @{ id='fp'; path='C:\SolTrade\MT5-FP-DEMO\terminal64.exe' },
        @{ id='f10'; path='C:\SolTrade\MT5-FXIFY-10K\terminal64.exe' },
        @{ id='f100'; path='C:\SolTrade\MT5-FXIFY-100K\terminal64.exe' }
    )) {
        $process = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $instance.path })
        $items += [ordered]@{ id=$instance.id; count=$process.Count; pids=@($process | ForEach-Object ProcessId) }
    }
    return $items
}

if (-not (Test-Path -LiteralPath $compileReportPath)) { throw 'FP compile report is missing.' }
$compile = Get-Content -Raw -LiteralPath $compileReportPath | ConvertFrom-Json
if ($compile.result -ne '0 errors, 0 warnings') { throw 'FP compile did not pass.' }
if ((Get-Sha $source) -ne [string]$compile.source_sha256 -or (Get-Sha $binary) -ne [string]$compile.binary_sha256) {
    throw 'FP source/binary no longer match the compiled artifacts.'
}
$sourceText = Get-Content -Raw -LiteralPath $source
if ($sourceText -notmatch 'NONE_SHADOW_TELEMETRY_ONLY') { throw 'Shadow-only marker missing.' }

$beforeRuntime = Read-Runtime
if (-not $beforeRuntime) { throw 'FP runtime telemetry missing; refusing blind restart.' }
if ([long]$beforeRuntime.login -ne 7404213) { throw "FP login mismatch: $($beforeRuntime.login)" }
if ([int]$beforeRuntime.positions -ne 0 -or [int]$beforeRuntime.orders -ne 0) {
    throw "FP exposure exists; deployment refused: positions=$($beforeRuntime.positions), orders=$($beforeRuntime.orders)"
}
$beforeProcesses = Process-Snapshot
$fxifyBefore = @{
    f10_source=Get-Sha 'C:\SolTrade\MT5-FXIFY-10K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F10.mq5'
    f10_binary=Get-Sha 'C:\SolTrade\MT5-FXIFY-10K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F10.ex5'
    f100_source=Get-Sha 'C:\SolTrade\MT5-FXIFY-100K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F100.mq5'
    f100_binary=Get-Sha 'C:\SolTrade\MT5-FXIFY-100K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F100.ex5'
}

New-Item -ItemType Directory -Force -Path $expertDir,$backup | Out-Null
foreach ($item in @($targetSource,$targetBinary)) {
    if (Test-Path -LiteralPath $item) { Copy-Item -Force -LiteralPath $item -Destination $backup }
}
$fpProcesses = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal })
if ($fpProcesses.Count -gt 1) { throw "Duplicate FP terminals already exist: $($fpProcesses.Count)" }
foreach ($process in $fpProcesses) { Stop-Process -Id $process.ProcessId -Force }
Start-Sleep -Seconds 3
Copy-Item -Force -LiteralPath $source -Destination $targetSource
Copy-Item -Force -LiteralPath $binary -Destination $targetBinary
if ((Get-Sha $targetSource) -ne [string]$compile.source_sha256 -or (Get-Sha $targetBinary) -ne [string]$compile.binary_sha256) {
    throw 'Deployed FP hashes do not match compiled artifacts.'
}
Start-Process -FilePath $terminal -ArgumentList @('/portable','/config:C:\SolTrade\state\fp-demo.ini') | Out-Null

$afterRuntime = $null
for ($attempt = 0; $attempt -lt 90; $attempt++) {
    Start-Sleep -Seconds 1
    $candidate = Read-Runtime
    if ($candidate -and [string]$candidate.timestamp_utc -ne [string]$beforeRuntime.timestamp_utc -and
        [string]$candidate.connected -eq 'true' -and [string]$candidate.scanner_active -eq 'true') {
        $afterRuntime = $candidate
        if (Test-Path -LiteralPath $shadowPath) { break }
    }
}
if (-not $afterRuntime) { throw 'FP runtime did not return connected/scanning after restart.' }
if (-not (Test-Path -LiteralPath $shadowPath)) { throw 'M1 shadow telemetry file was not created.' }
$shadowHeader = Get-Content -LiteralPath $shadowPath -TotalCount 1
if ($shadowHeader -notmatch 'm1_shadow_evidence' -or $shadowHeader -notmatch 'order_influence') {
    throw 'M1 shadow telemetry schema is invalid.'
}

$afterProcesses = Process-Snapshot
$fxifyAfter = @{
    f10_source=Get-Sha 'C:\SolTrade\MT5-FXIFY-10K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F10.mq5'
    f10_binary=Get-Sha 'C:\SolTrade\MT5-FXIFY-10K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F10.ex5'
    f100_source=Get-Sha 'C:\SolTrade\MT5-FXIFY-100K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F100.mq5'
    f100_binary=Get-Sha 'C:\SolTrade\MT5-FXIFY-100K\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV202F100.ex5'
}
$fxifyUntouched = ($fxifyBefore.f10_source -eq $fxifyAfter.f10_source -and $fxifyBefore.f10_binary -eq $fxifyAfter.f10_binary -and
                   $fxifyBefore.f100_source -eq $fxifyAfter.f100_source -and $fxifyBefore.f100_binary -eq $fxifyAfter.f100_binary)
$fpAfter = $afterProcesses | Where-Object id -eq 'fp' | Select-Object -First 1
if ([int]$fpAfter.count -ne 1) { throw "Expected exactly one FP terminal after deployment; found $($fpAfter.count)." }
if (-not $fxifyUntouched) { throw 'FXIFY artifact hash changed during FP-only deployment.' }

$report = [ordered]@{
    schema='SOLTRADE_FP_V202_M1_SHADOW_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status='DEPLOYED_TELEMETRY_ONLY'
    account=7404213
    version='2.202'
    source_sha256=Get-Sha $targetSource
    binary_sha256=Get-Sha $targetBinary
    backup=$backup
    compile_result=[string]$compile.result
    before_runtime=$beforeRuntime
    after_runtime=$afterRuntime
    before_processes=$beforeProcesses
    after_processes=$afterProcesses
    shadow_path=$shadowPath
    shadow_rows=[Math]::Max(0,@(Get-Content -LiteralPath $shadowPath).Count-1)
    shadow_schema_verified=$true
    strategy_admission_changed=$false
    order_path_changed=$false
    fxify_touched=$false
    fxify_hashes_unchanged=$fxifyUntouched
    test_orders_placed=$false
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $output
$report | ConvertTo-Json -Depth 12
