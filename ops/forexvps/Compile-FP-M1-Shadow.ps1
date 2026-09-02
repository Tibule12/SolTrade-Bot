[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $share 'remote-output\fp-m1-shadow-compile.json'
$terminalHome = 'C:\SolTrade\MT5-FP-DEMO'
$metaEditor = Join-Path $terminalHome 'metaeditor64.exe'
$sharedSource = Join-Path $share 'payload\fp-demo\SolTradeFastMultiMarketV2.mq5'
$sharedBinary = Join-Path $share 'payload\fp-demo\SolTradeFastMultiMarketV2.ex5'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $terminalHome "MQL5\Experts\_fp_m1_shadow_compile_$stamp"
$source = Join-Path $stage 'SolTradeFastMultiMarketV2.mq5'
$binary = Join-Path $stage 'SolTradeFastMultiMarketV2.ex5'
$log = Join-Path $stage 'SolTradeFastMultiMarketV2-compile.log'

function Get-Sha([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $metaEditor)) { throw "MetaEditor missing: $metaEditor" }
if (-not (Test-Path -LiteralPath $sharedSource)) { throw "FP shadow source missing: $sharedSource" }
$sourceText = Get-Content -Raw -LiteralPath $sharedSource
if ($sourceText -notmatch 'NONE_SHADOW_TELEMETRY_ONLY' -or $sourceText -notmatch 'AppendM1EntryEvidenceShadow') {
    throw 'Source does not contain the fail-closed M1 shadow instrumentation.'
}

New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -Force -LiteralPath $sharedSource -Destination $source
$arguments = @("/compile:$source", "/log:$log", "/inc:$terminalHome\MQL5")
$process = Start-Process -FilePath $metaEditor -ArgumentList $arguments -PassThru
$logText = ''
for ($attempt = 0; $attempt -lt 90; $attempt++) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $log) {
        $logText = Get-Content -Raw -LiteralPath $log
        if ($logText -match 'Result:\s+\d+ errors, \d+ warnings') { break }
    }
}
if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
if (-not (Test-Path -LiteralPath $log)) { throw 'FP compile log was not created.' }
if ($logText -notmatch 'Result:\s+0 errors, 0 warnings') { throw "FP compile failed: $logText" }
if (-not (Test-Path -LiteralPath $binary)) { throw 'FP compiled EX5 was not created.' }
Copy-Item -Force -LiteralPath $binary -Destination $sharedBinary
Copy-Item -Force -LiteralPath $log -Destination (Join-Path $share 'payload\fp-demo\SolTradeFastMultiMarketV2-m1-shadow-compile.log')

$report = [ordered]@{
    schema='SOLTRADE_FP_V202_M1_SHADOW_COMPILE_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    account=7404213
    version='2.202'
    result='0 errors, 0 warnings'
    source_sha256=Get-Sha $source
    binary_sha256=Get-Sha $binary
    shared_binary_sha256=Get-Sha $sharedBinary
    strategy_admission_changed=$false
    order_path_changed=$false
    fxify_touched=$false
    runtime_files_changed=$false
    terminals_restarted=$false
    staging_directory=$stage
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $output
$report | ConvertTo-Json -Depth 8
