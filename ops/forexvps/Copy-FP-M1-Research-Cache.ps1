$ErrorActionPreference = 'Stop'

$sourceRoot = 'C:\SolTrade\MT5-FP-DEMO\Bases\FPMarketsSC-Demo\ticks'
$destinationRoot = '\\tsclient\SolTrade\remote-output\v202-m1-research-cache'
$symbols = @(
    'US100',
    'XAUUSD.r',
    'GER40',
    'EURUSD.r',
    'GBPJPY.r',
    'EURJPY.r',
    'US500',
    'US500.r',
    'USDJPY.r'
)
$months = @('202608.tkc', '202609.tkc')

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$manifest = @()

foreach ($symbol in $symbols) {
    foreach ($month in $months) {
        $source = Join-Path (Join-Path $sourceRoot $symbol) $month
        if (-not (Test-Path $source)) {
            $manifest += [pscustomobject]@{
                symbol = $symbol
                month = $month
                copied = $false
                bytes = 0
                sha256 = $null
                error = 'SOURCE_NOT_FOUND'
            }
            continue
        }

        $symbolDestination = Join-Path $destinationRoot $symbol
        New-Item -ItemType Directory -Force -Path $symbolDestination | Out-Null
        $destination = Join-Path $symbolDestination $month
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $item = Get-Item -LiteralPath $destination
        $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest += [pscustomobject]@{
            symbol = $symbol
            month = $month
            copied = $true
            bytes = $item.Length
            sha256 = $hash
            error = $null
        }
    }
}

$manifestPath = Join-Path $destinationRoot 'manifest.json'
[ordered]@{
    schema = 'SOLTRADE_FP_M1_RESEARCH_CACHE_V1'
    captured_utc = [DateTime]::UtcNow.ToString('o')
    source = $sourceRoot
    destination = $destinationRoot
    files = $manifest
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "SOLTRADE_FP_M1_RESEARCH_CACHE_COMPLETE manifest=$manifestPath copied=$(@($manifest | Where-Object copied).Count) missing=$(@($manifest | Where-Object { -not $_.copied }).Count)"
