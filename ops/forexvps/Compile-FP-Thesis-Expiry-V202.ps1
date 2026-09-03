[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$fpHome = 'C:\SolTrade\MT5-FP-DEMO'
$expert = 'SolTradeFastMultiMarketV2'
$sharedSource = Join-Path $share "payload\fp-demo\$expert.mq5"
$sharedBinary = Join-Path $share "payload\fp-demo\$expert.ex5"
$output = Join-Path $share 'remote-output\fp-thesis-expiry-compile.json'
$expectedSource = 'dfb83209dbbee9a2ca511c9f3cd436f3268e479a427e60f670e37c6637932e24'

function Get-Sha([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if ((Get-Sha $sharedSource) -ne $expectedSource) { throw 'Reviewed FP source hash mismatch' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $fpHome "MQL5\Experts\_thesis_expiry_compile_$stamp"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$source = Join-Path $stage "$expert.mq5"
$binary = Join-Path $stage "$expert.ex5"
$log = Join-Path $stage "$expert-compile.log"
Copy-Item -Force -LiteralPath $sharedSource -Destination $source
$process = Start-Process -FilePath (Join-Path $fpHome 'metaeditor64.exe') -ArgumentList @("/compile:$source", "/log:$log", "/inc:$fpHome\MQL5") -PassThru
$logText = ''
for ($attempt=0; $attempt -lt 90; $attempt++) {
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $log) {
        $logText = Get-Content -Raw -LiteralPath $log
        if ($logText -match 'Result:\s+\d+ errors, \d+ warnings') { break }
    }
}
if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
if ($logText -notmatch 'Result:\s+0 errors, 0 warnings') { throw "FP compile failed: $logText" }
if (-not (Test-Path -LiteralPath $binary)) { throw 'Compiled FP EX5 missing' }
Copy-Item -Force -LiteralPath $binary -Destination $sharedBinary
Copy-Item -Force -LiteralPath $log -Destination (Join-Path $share "payload\fp-demo\$expert-thesis-expiry-compile.log")
[ordered]@{
    schema='SOLTRADE_FP_V202_THESIS_EXPIRY_COMPILE_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    result='0 errors, 0 warnings'
    source_sha256=Get-Sha $source
    binary_sha256=Get-Sha $binary
    shared_binary_sha256=Get-Sha $sharedBinary
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $output
