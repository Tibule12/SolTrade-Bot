[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $share 'remote-output\evidence-exit-v202-compile.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$instances = @(
    @{ id='fp'; home='C:\SolTrade\MT5-FP-DEMO'; folder='payload\fp-demo'; expert='SolTradeFastMultiMarketV2'; source='97c7ac5f5f19969d02321c2ee75a21895524c77dbe358c8cca3c3173a87441a5' },
    @{ id='f10'; home='C:\SolTrade\MT5-FXIFY-10K'; folder='payload\fxify-10k'; expert='SolTradeFastMultiMarketV202F10'; source='e33223dc24beb434dd361c9422e1324395bd366880e075f9d4b4f0ffd9999d9e' },
    @{ id='f100'; home='C:\SolTrade\MT5-FXIFY-100K'; folder='payload\fxify-100k'; expert='SolTradeFastMultiMarketV202F100'; source='f4cf460097b529c009a2272df189211f6d6c3965ff413c16aa2050da6c12626d' }
)

function Get-Sha([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$results = @()
foreach ($instance in $instances) {
    $metaEditor = Join-Path $instance.home 'metaeditor64.exe'
    $sharedSource = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).mq5"
    if ((Get-Sha $sharedSource) -ne $instance.source) { throw "Reviewed source hash mismatch: $($instance.id)" }
    $stage = Join-Path $instance.home "MQL5\Experts\_evidence_exit_compile_$stamp"
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $source = Join-Path $stage "$($instance.expert).mq5"
    $binary = Join-Path $stage "$($instance.expert).ex5"
    $log = Join-Path $stage "$($instance.expert)-compile.log"
    Copy-Item -Force -LiteralPath $sharedSource -Destination $source
    $process = Start-Process -FilePath $metaEditor -ArgumentList @("/compile:$source", "/log:$log", "/inc:$($instance.home)\MQL5") -PassThru
    $logText = ''
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $log) {
            $logText = Get-Content -Raw -LiteralPath $log
            if ($logText -match 'Result:\s+\d+ errors, \d+ warnings') { break }
        }
    }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($logText -notmatch 'Result:\s+0 errors, 0 warnings') { throw "Compile failed for $($instance.id): $logText" }
    if (-not (Test-Path -LiteralPath $binary)) { throw "Compiled EX5 missing: $($instance.id)" }
    $sharedBinary = Join-Path (Join-Path $share $instance.folder) "$($instance.expert).ex5"
    $sharedLog = Join-Path (Join-Path $share $instance.folder) "$($instance.expert)-evidence-exit-compile.log"
    Copy-Item -Force -LiteralPath $binary -Destination $sharedBinary
    Copy-Item -Force -LiteralPath $log -Destination $sharedLog
    $results += [ordered]@{
        id=$instance.id
        result='0 errors, 0 warnings'
        source_sha256=Get-Sha $source
        binary_sha256=Get-Sha $binary
        shared_binary_sha256=Get-Sha $sharedBinary
        staging_directory=$stage
    }
}

[ordered]@{
    schema='SOLTRADE_V202_EVIDENCE_EXIT_COMPILE_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    strategy_version='2.202'
    runtime_files_changed=$false
    terminals_restarted=$false
    results=$results
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $output
