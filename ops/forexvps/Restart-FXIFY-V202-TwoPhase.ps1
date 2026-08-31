[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$out = Join-Path $shareRoot 'remote-output'
$allInstances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$instances = @($allInstances | Where-Object { $_.id -like 'fxify-*' })
$stateDirs = @{ 'fxify-10k'='SolTradeFastMultiMarketV2F10'; 'fxify-100k'='SolTradeFastMultiMarketV2F100' }

function Read-Runtime([string]$StateDir) {
    $path = Join-Path (Join-Path $common $StateDir) 'runtime.csv'
    if (-not (Test-Path $path)) { return $null }
    $lines = @(Get-Content $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

foreach ($instance in $instances) {
    $runtime = Read-Runtime $stateDirs[$instance.id]
    if (-not $runtime) { throw "Missing FXIFY telemetry for $($instance.id)." }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) { throw "Exposure open on $($instance.id); restart refused." }
}

$paths = @($instances | ForEach-Object { Join-Path $_.home 'terminal64.exe' })
Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $paths -contains $_.ExecutablePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 4

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    Start-Process -FilePath $terminal -WorkingDirectory $instance.home -ArgumentList @('/portable',"/login:$($instance.account)","/profile:$($instance.profile)")
}
Start-Sleep -Seconds 25

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $startup = Join-Path $root "state\$($instance.id).ini"
    Start-Process -FilePath $terminal -WorkingDirectory $instance.home -ArgumentList @('/portable',"/login:$($instance.account)","/profile:$($instance.profile)","/config:$startup")
}
Start-Sleep -Seconds 45

$result = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $stateDirs[$instance.id]
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $leasePath = Join-Path $root "ownership\lease-$($instance.account).json"
    $result += [ordered]@{
        id=$instance.id
        account=$instance.account
        process_running=[bool]$process
        runtime=$runtime
        lease=if (Test-Path $leasePath) { Get-Content -Raw $leasePath | ConvertFrom-Json } else { $null }
    }
    $runtimePath = Join-Path (Join-Path $common $stateDirs[$instance.id]) 'runtime.csv'
    if (Test-Path $runtimePath) { Copy-Item -Force $runtimePath (Join-Path $out "corrected-v202-$($instance.id)-runtime.csv") }
}

[ordered]@{
    schema='SOLTRADE_FXIFY_V202_TWO_PHASE_ATTACH_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    instances=$result
    order_sending_enabled=$false
    test_orders_placed=$false
} | ConvertTo-Json -Depth 14 | Set-Content -Encoding UTF8 (Join-Path $out 'corrected-v202-fxify-final.json')

Copy-Item -Force (Join-Path $shareRoot 'Watch-SolTrade.ps1') (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
