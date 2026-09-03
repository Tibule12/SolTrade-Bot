$ErrorActionPreference = 'Stop'

$source = 'C:\SolTrade\MT5-FP-DEMO\Bases\FPMarketsSC-Demo\ticks\USDJPY.r\202609.tkc'
$destination = '\\tsclient\SolTrade\remote-output\v202-m1-research-cache\USDJPY.r\202609.tkc'
if (-not (Test-Path -LiteralPath $source)) { throw "SOURCE_NOT_FOUND: $source" }
Copy-Item -LiteralPath $source -Destination $destination -Force
$item = Get-Item -LiteralPath $destination
$result = [ordered]@{
    schema = 'SOLTRADE_FP_USDJPY_RESEARCH_CACHE_REFRESH_V1'
    captured_utc = [DateTime]::UtcNow.ToString('o')
    bytes = $item.Length
    sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result | ConvertTo-Json | Set-Content -LiteralPath '\\tsclient\SolTrade\remote-output\v202-m1-research-cache\usdjpy-refresh.json' -Encoding UTF8
Write-Host "SOLTRADE_FP_USDJPY_CACHE_REFRESH_COMPLETE bytes=$($result.bytes) sha256=$($result.sha256)"
