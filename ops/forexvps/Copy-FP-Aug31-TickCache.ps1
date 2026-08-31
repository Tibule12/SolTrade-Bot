[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = 'C:\SolTrade\MT5-FP-DEMO\Bases\FPMarketsSC-Demo\ticks'
$destinationRoot = '\\tsclient\SolTrade\remote-output\v202-vps-ticks'
$symbols = @('US100', 'XAUUSD.r', 'GER40', 'EURUSD.r')

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$evidence = foreach ($symbol in $symbols) {
    $source = Join-Path (Join-Path $sourceRoot $symbol) '202608.tkc'
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing FP tick cache: $source"
    }
    $destination = Join-Path $destinationRoot "$symbol-202608.tkc"
    Copy-Item -LiteralPath $source -Destination $destination -Force
    [ordered]@{
        symbol = $symbol
        source = $source
        destination = $destination
        length = (Get-Item -LiteralPath $destination).Length
        source_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
        copied_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
    }
}

[ordered]@{
    schema = 'SOLTRADE_FP_VPS_TICK_CACHE_COPY_V1'
    captured_utc = [DateTime]::UtcNow.ToString('o')
    source_terminal = 'C:\SolTrade\MT5-FP-DEMO'
    account_scope = 7404213
    files = @($evidence)
    strategy_changed = $false
    terminal_stopped = $false
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $destinationRoot 'manifest.json')
