[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $share 'remote-output\fp-m1-shadow-audit'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$state = Join-Path $common 'SolTradeFastMultiMarketV2'
$lease = 'C:\SolTrade\ownership\lease-7404213.json'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$days = @((Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyyMMdd'), (Get-Date).ToUniversalTime().ToString('yyyyMMdd'))
$copied = @()
foreach ($day in $days) {
    foreach ($name in @("m1-entry-evidence-shadow-v1-$day.csv", "scan-history-v5-$day.csv", "structure-telemetry-v6-$day.csv")) {
        $source = Join-Path $state $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -Force -LiteralPath $source -Destination (Join-Path $out $name)
            $copied += $name
        }
    }
}
foreach ($name in @('runtime.csv','evidence.csv','lifecycle.csv')) {
    $source = Join-Path $state $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -Force -LiteralPath $source -Destination (Join-Path $out $name)
        $copied += $name
    }
}
if (Test-Path -LiteralPath $lease) {
    Copy-Item -Force -LiteralPath $lease -Destination (Join-Path $out 'lease-7404213.json')
    $copied += 'lease-7404213.json'
}
$processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | ForEach-Object {
    [ordered]@{ path=$_.ExecutablePath; pid=$_.ProcessId }
})
[ordered]@{
    schema='SOLTRADE_FP_M1_SHADOW_AUDIT_CAPTURE_V1'
    captured_utc=[DateTime]::UtcNow.ToString('o')
    account=7404213
    files=$copied
    processes=$processes
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $out 'capture.json')
