[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$share='\\tsclient\SolTrade\ops\forexvps'
$root='C:\SolTrade'
$fp=Join-Path $root 'MT5-FP-DEMO'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$expert=Join-Path $fp 'MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2'
function Hash([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Runtime([string]$name){
    $path=Join-Path $common "$name\runtime.csv"
    Get-Content -LiteralPath $path -TotalCount 2 | ConvertFrom-Csv | Select-Object -First 1
}
function TerminalProcesses([string]$terminalHome){
    @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $terminalHome 'terminal64.exe')})
}
$fpRuntime=Runtime 'SolTradeFastMultiMarketV2'
$fx10=Runtime 'SolTradeFastMultiMarketV2F10'
$fx100=Runtime 'SolTradeFastMultiMarketV2F100'
$watchdog=Get-ScheduledTask -TaskName 'SolTrade-Watchdog'
$authority=Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213'
$report=[ordered]@{
    captured_utc=[DateTime]::UtcNow.ToString('o')
    fp_runtime=$fpRuntime
    fp_source_sha256=Hash "$expert.mq5"
    fp_binary_sha256=Hash "$expert.ex5"
    fp_process_ids=@(TerminalProcesses $fp | ForEach-Object {$_.Id})
    watchdog_state=[string]$watchdog.State
    ownership_task_state=[string]$authority.State
    fxify_10k_runtime=$fx10
    fxify_100k_runtime=$fx100
}
$report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $share 'remote-output\fp-bank1r-giveback-inspect.json')
