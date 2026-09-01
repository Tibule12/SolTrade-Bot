[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $share 'remote-output\scratch-retired-v202-compile.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$instances = @(
    @{ id='fp'; home='C:\SolTrade\MT5-FP-DEMO'; folder='payload\fp-demo'; expert='SolTradeFastMultiMarketV2' },
    @{ id='f10'; home='C:\SolTrade\MT5-FXIFY-10K'; folder='payload\fxify-10k'; expert='SolTradeFastMultiMarketV202F10' },
    @{ id='f100'; home='C:\SolTrade\MT5-FXIFY-100K'; folder='payload\fxify-100k'; expert='SolTradeFastMultiMarketV202F100' }
)

function Get-Sha([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$results = @()
foreach ($instance in $instances) {
    $metaEditor = Join-Path $instance.home 'metaeditor64.exe'
    $sharedSource = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5"
    if (-not (Test-Path -LiteralPath $metaEditor)) { throw "MetaEditor missing: $metaEditor" }
    if (-not (Test-Path -LiteralPath $sharedSource)) { throw "Source missing: $sharedSource" }

    $stage = Join-Path $instance.home "MQL5\Experts\_scratch_retired_compile_$stamp"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $source = Join-Path $stage "$($instance.expert).mq5"
    $binary = Join-Path $stage "$($instance.expert).ex5"
    $log = Join-Path $stage "$($instance.expert)-compile.log"
    Copy-Item -Force -LiteralPath $sharedSource -Destination $source

    $arguments = @("/compile:$source", "/log:$log", "/inc:$($instance.home)\MQL5")
    $process = Start-Process -FilePath $metaEditor -ArgumentList $arguments -PassThru
    $logText = ''
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $log) {
            $logText = Get-Content -Raw -LiteralPath $log
            if ($logText -match 'Result:\s+\d+ errors, \d+ warnings') { break }
        }
    }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (-not (Test-Path -LiteralPath $log)) { throw "Compile log missing for $($instance.id)" }
    if ($logText -notmatch 'Result:\s+0 errors, 0 warnings') {
        throw "Compile failed for $($instance.id): $logText"
    }
    if (-not (Test-Path -LiteralPath $binary)) { throw "Compiled EX5 missing for $($instance.id)" }

    $sharedBinary = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5"
    $sharedLog = Join-Path (Join-Path $share $instance.folder) "$($instance.expert)-scratch-retired-compile.log"
    Copy-Item -Force -LiteralPath $binary -Destination $sharedBinary
    Copy-Item -Force -LiteralPath $log -Destination $sharedLog
    $results += [ordered]@{
        id=$instance.id
        metaeditor=$metaEditor
        process_exit_code=$process.ExitCode
        result='0 errors, 0 warnings'
        source_sha256=Get-Sha $source
        binary_sha256=Get-Sha $binary
        shared_binary_sha256=Get-Sha $sharedBinary
        staging_directory=$stage
    }
}

$report = [ordered]@{
    schema='SOLTRADE_V202_SCRATCH_RETIREMENT_COMPILE_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    strategy_version='2.202'
    runtime_files_changed=$false
    terminals_restarted=$false
    results=$results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $output
$report | ConvertTo-Json -Depth 8
