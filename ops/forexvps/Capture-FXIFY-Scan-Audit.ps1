[CmdletBinding()]
param([string]$Day = '2026.09.03')

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$compact = $Day.Replace('.', '')
$output = Join-Path $share 'remote-output\fxify-scan-audit'
New-Item -ItemType Directory -Force -Path $output | Out-Null

$instances = @(
    @{ id='f10'; state='SolTradeFastMultiMarketV2F10' },
    @{ id='f100'; state='SolTradeFastMultiMarketV2F100' }
)

$captured = @()
foreach ($instance in $instances) {
    $root = Join-Path $common $instance.state
    foreach ($name in @(
        "scan-history-v5-$compact.csv",
        "structure-telemetry-v6-$compact.csv",
        "m1-entry-evidence-shadow-v1-$compact.csv"
    )) {
        $source = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $source)) { continue }
        $destination = Join-Path $output ("{0}-{1}" -f $instance.id, $name)
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $item = Get-Item -LiteralPath $destination
        $captured += [ordered]@{
            instance=$instance.id
            file=$name
            bytes=$item.Length
            modified_utc=$item.LastWriteTimeUtc.ToString('o')
        }
    }
}

[ordered]@{
    schema='SOLTRADE_FXIFY_SCAN_CAPTURE_V1'
    captured_utc=[DateTime]::UtcNow.ToString('o')
    day_utc=$Day
    files=$captured
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $output 'manifest.json')
