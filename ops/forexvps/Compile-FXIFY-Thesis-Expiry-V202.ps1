[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $share 'remote-output\fxify-thesis-expiry-compile.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$instances = @(
    @{ id='f10'; home='C:\SolTrade\MT5-FXIFY-10K'; folder='payload\fxify-10k'; expert='SolTradeFastMultiMarketV202F10' },
    @{ id='f100'; home='C:\SolTrade\MT5-FXIFY-100K'; folder='payload\fxify-100k'; expert='SolTradeFastMultiMarketV202F100' }
)

function Get-Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$results = @()
foreach ($instance in $instances) {
    $metaEditor = Join-Path $instance.home 'metaeditor64.exe'
    $sharedSource = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5"
    if (-not (Test-Path -LiteralPath $metaEditor)) { throw "MetaEditor missing: $metaEditor" }
    if (-not (Test-Path -LiteralPath $sharedSource)) { throw "Source missing: $sharedSource" }

    $stage = Join-Path $instance.home "MQL5\Experts\_thesis_expiry_compile_$stamp"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $source = Join-Path $stage "$($instance.expert).mq5"
    $binary = Join-Path $stage "$($instance.expert).ex5"
    $log = Join-Path $stage "$($instance.expert)-compile.log"
    Copy-Item -Force -LiteralPath $sharedSource -Destination $source

    $process = Start-Process -FilePath $metaEditor -ArgumentList @("/compile:$source", "/log:$log", "/inc:$($instance.home)\MQL5") -PassThru
    $logText = ''
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $log) {
            $logText = Get-Content -Raw -LiteralPath $log
            if ($logText -match 'Result:\s+\d+ errors, \d+ warnings') { break }
        }
    }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($logText -notmatch 'Result:\s+0 errors, 0 warnings') { throw "Compile failed for $($instance.id): $logText" }
    if (-not (Test-Path -LiteralPath $binary)) { throw "Compiled EX5 missing for $($instance.id)" }

    $sharedBinary = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5"
    $sharedLog = Join-Path (Join-Path $share $instance.folder) "$($instance.expert)-thesis-expiry-compile.log"
    Copy-Item -Force -LiteralPath $binary -Destination $sharedBinary
    Copy-Item -Force -LiteralPath $log -Destination $sharedLog
    $results += [ordered]@{
        id=$instance.id
        result='0 errors, 0 warnings'
        source_sha256=Get-Sha $source
        binary_sha256=Get-Sha $binary
        shared_binary_sha256=Get-Sha $sharedBinary
    }
}

[ordered]@{
    schema='SOLTRADE_FXIFY_V202_THESIS_EXPIRY_COMPILE_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    strategy_version='2.202'
    fp_touched=$false
    results=$results
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $output
