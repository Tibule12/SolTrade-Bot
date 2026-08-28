$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
foreach ($instance in $instances) {
    $target = Join-Path $instance.home 'MQL5\Presets'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Force (Join-Path $shareRoot $instance.preset) (Join-Path $target (Split-Path $instance.preset -Leaf))
}
[ordered]@{
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status='PRESET_PATHS_CORRECTED'
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\preset-path-fix.json')
