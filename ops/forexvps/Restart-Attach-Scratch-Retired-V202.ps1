[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$out = Join-Path $share 'remote-output\scratch-retired-v202-restart-attach.json'
$started = [DateTime]::UtcNow
$items = @(
    @{ id='fp-demo'; account=7404213; home='C:\SolTrade\MT5-FP-DEMO'; profile='SolTradeV202FP'; state='SolTradeFastMultiMarketV2'; ini='fp-demo.ini' },
    @{ id='fxify-10k'; account=7196820; home='C:\SolTrade\MT5-FXIFY-10K'; profile='SolTradeV202F10'; state='SolTradeFastMultiMarketV2F10'; ini='fxify-10k.ini' },
    @{ id='fxify-100k'; account=7198096; home='C:\SolTrade\MT5-FXIFY-100K'; profile='SolTradeV202F100'; state='SolTradeFastMultiMarketV2F100'; ini='fxify-100k.ini' }
)

function Read-Runtime([string]$State) {
    $path = Join-Path (Join-Path $common $State) 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

$before = @()
foreach ($item in $items) {
    $runtime = Read-Runtime $item.state
    if (-not $runtime) { throw "Missing last broker runtime for $($item.id)" }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Last broker runtime was not flat for $($item.id)"
    }
    $before += [ordered]@{ id=$item.id; runtime=$runtime }
    $source = Join-Path $share "runtime\$($item.ini)"
    if ((Get-Content -LiteralPath $source) -notcontains 'AllowLiveTrading=1') {
        throw "Autonomous trading is not preserved in $source"
    }
    Copy-Item -Force -LiteralPath $source -Destination (Join-Path $root "state\$($item.ini)")
}
Copy-Item -Force -LiteralPath (Join-Path $share 'Watch-SolTrade.ps1') -Destination (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')

Disable-ScheduledTask -TaskName 'SolTrade-Watchdog' | Out-Null
Stop-ScheduledTask -TaskName 'SolTrade-Watchdog' -ErrorAction SilentlyContinue
Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 5

$launched = @()
foreach ($item in $items) {
    $terminal = Join-Path $item.home 'terminal64.exe'
    $startup = Join-Path $root "state\$($item.ini)"
    $process = Start-Process -FilePath $terminal -WorkingDirectory $item.home -ArgumentList @(
        '/portable', "/login:$($item.account)", "/profile:$($item.profile)", "/config:$startup"
    ) -PassThru
    $launched += [ordered]@{ id=$item.id; pid=$process.Id }
}

Start-Sleep -Seconds 90
$after = @()
foreach ($item in $items) {
    $runtimePath = Join-Path (Join-Path $common $item.state) 'runtime.csv'
    $runtime = Read-Runtime $item.state
    $after += [ordered]@{
        id=$item.id
        runtime_last_write_utc=if (Test-Path -LiteralPath $runtimePath) { (Get-Item -LiteralPath $runtimePath).LastWriteTimeUtc.ToString('o') } else { $null }
        runtime=$runtime
    }
}

$failures = @($after | Where-Object {
    -not $_.runtime -or -not $_.runtime_last_write_utc -or
    ([DateTime]$_.runtime_last_write_utc) -le $started -or
    $_.runtime.connected -ne 'true' -or $_.runtime.scanner_active -ne 'true' -or
    $_.runtime.autonomous_entry -ne 'true' -or $_.runtime.ownership_permit -ne 'GRANTED'
})

Enable-ScheduledTask -TaskName 'SolTrade-Watchdog' | Out-Null
Start-ScheduledTask -TaskName 'SolTrade-Watchdog'
Start-Sleep -Seconds 35

$final = @()
foreach ($item in $items) {
    $runtimePath = Join-Path (Join-Path $common $item.state) 'runtime.csv'
    $runtime = Read-Runtime $item.state
    $final += [ordered]@{
        id=$item.id
        runtime_last_write_utc=if (Test-Path -LiteralPath $runtimePath) { (Get-Item -LiteralPath $runtimePath).LastWriteTimeUtc.ToString('o') } else { $null }
        runtime=$runtime
    }
}

$report = [ordered]@{
    schema='SOLTRADE_V202_SCRATCH_RETIREMENT_RESTART_ATTACH_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if ($failures.Count -eq 0) { 'ACTIVE_AND_WATCHDOG_VERIFIED' } else { 'ATTACH_FAILED' }
    autonomous_trading_preserved=$true
    test_orders_placed=$false
    before=$before
    launched=$launched
    after_attach=$after
    after_watchdog=$final
    failures=@($failures | ForEach-Object { $_.id })
}
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $out
$report | ConvertTo-Json -Depth 12
if ($failures.Count -gt 0) { exit 2 }
