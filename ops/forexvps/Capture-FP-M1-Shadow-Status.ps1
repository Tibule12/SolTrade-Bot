[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$runtimePath = Join-Path $common 'SolTradeFastMultiMarketV2\runtime.csv'
$shadowPath = Join-Path $common ("SolTradeFastMultiMarketV2\m1-entry-evidence-shadow-v1-" + (Get-Date).ToUniversalTime().ToString('yyyyMMdd') + '.csv')
$leasePath = 'C:\SolTrade\ownership\lease-7404213.json'
$lines = @(Get-Content -LiteralPath $runtimePath -TotalCount 2)
$runtime = $lines | ConvertFrom-Csv | Select-Object -First 1
$lease = if (Test-Path -LiteralPath $leasePath) { Get-Content -Raw -LiteralPath $leasePath | ConvertFrom-Json } else { $null }
$terminals = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | ForEach-Object {
    [ordered]@{ path=$_.ExecutablePath; pid=$_.ProcessId }
})
$shadowRows = if (Test-Path -LiteralPath $shadowPath) { [Math]::Max(0,@(Get-Content -LiteralPath $shadowPath).Count-1) } else { 0 }
$report = [ordered]@{
    schema='SOLTRADE_FP_V202_M1_SHADOW_STATUS_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    runtime=$runtime
    lease=$lease
    terminals=$terminals
    shadow_path=$shadowPath
    shadow_rows=$shadowRows
    pass=([string]$runtime.login -eq '7404213' -and [string]$runtime.connected -eq 'true' -and
          [string]$runtime.scanner_active -eq 'true' -and [string]$runtime.ownership_permit -eq 'GRANTED' -and
          [string]$runtime.autonomous_entry -eq 'true' -and $shadowRows -gt 0 -and
          @($terminals | Where-Object path -eq 'C:\SolTrade\MT5-FP-DEMO\terminal64.exe').Count -eq 1)
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $share 'remote-output\fp-m1-shadow-status.json')
$report | ConvertTo-Json -Depth 12
