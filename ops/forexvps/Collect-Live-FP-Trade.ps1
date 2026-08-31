[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$outputRoot = '\\tsclient\SolTrade\remote-output\live-fp-trade'
$terminalRoot = 'C:\SolTrade\MT5-FP-DEMO'
$commonRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\SolTradeFastMultiMarketV2'
$expertRoot = Join-Path $terminalRoot 'MQL5\Experts\SolTrade'
$today = Get-Date -Format 'yyyyMMdd'

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$runtimePath = Join-Path $commonRoot 'runtime.csv'
$evidencePath = Join-Path $commonRoot 'evidence.csv'
$lifecyclePath = Join-Path $commonRoot "lifecycle-$today.csv"
$expertLogPath = Join-Path $terminalRoot "MQL5\Logs\$today.log"
$expertPath = Join-Path $expertRoot 'SolTradeFastMultiMarketV2.ex5'
$sourcePath = Join-Path $expertRoot 'SolTradeFastMultiMarketV2.mq5'

$copied = @()
foreach ($item in @(
    @{ Source=$runtimePath; Name='runtime.csv' },
    @{ Source=$evidencePath; Name='evidence.csv' },
    @{ Source=$lifecyclePath; Name='lifecycle.csv' },
    @{ Source=$expertLogPath; Name='expert.log' }
)) {
    if (Test-Path -LiteralPath $item.Source) {
        $destination = Join-Path $outputRoot $item.Name
        Copy-Item -LiteralPath $item.Source -Destination $destination -Force
        $copied += [ordered]@{
            source=$item.Source
            destination=$destination
            length=(Get-Item -LiteralPath $destination).Length
            sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
        }
    }
}

$runtimeHeader = $null
if (Test-Path -LiteralPath $runtimePath) {
    $runtimeLines = @(Get-Content -LiteralPath $runtimePath -TotalCount 2)
    if ($runtimeLines.Count -eq 2) {
        $runtimeHeader = $runtimeLines | ConvertFrom-Csv | Select-Object -First 1
    }
}

$ger40Events = @()
if (Test-Path -LiteralPath $evidencePath) {
    $ger40Events = @(Import-Csv -LiteralPath $evidencePath |
        Where-Object { $_.symbol -like 'GER40*' -or $_.symbol -like 'DE30*' } |
        Select-Object -Last 40)
}

$terminal = Join-Path $terminalRoot 'terminal64.exe'
$process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1

$document = [ordered]@{
    schema='SOLTRADE_FP_LIVE_TRADE_INSPECTION_V1'
    captured_utc=[DateTime]::UtcNow.ToString('o')
    host=$env:COMPUTERNAME
    account=7404213
    server='FPMarketsSC-Demo'
    read_only=$true
    terminal_process_running=[bool]$process
    terminal_pid=if ($process) { $process.ProcessId } else { $null }
    source_sha256=if (Test-Path -LiteralPath $sourcePath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant() } else { $null }
    expert_sha256=if (Test-Path -LiteralPath $expertPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $expertPath).Hash.ToLowerInvariant() } else { $null }
    runtime=$runtimeHeader
    ger40_events=$ger40Events
    copied_files=$copied
    strategy_changed=$false
    order_attempted=$false
    position_modified=$false
}

$temporary = Join-Path $outputRoot 'inspection.json.tmp'
$final = Join-Path $outputRoot 'inspection.json'
$document | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -Force -LiteralPath $temporary -Destination $final

