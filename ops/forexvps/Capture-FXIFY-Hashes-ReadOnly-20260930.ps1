$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$root='C:\SolTrade'
$values=[ordered]@{captured_utc=[DateTime]::UtcNow.ToString('o');order_capability=$false;orders_sent=0}
foreach($a in @(@('10k','MT5-FXIFY-10K','SolTradeFastMultiMarketV202F10'),@('100k','MT5-FXIFY-100K','SolTradeFastMultiMarketV202F100'))){
 $base=Join-Path $root "$($a[1])\MQL5\Experts\SolTrade\$($a[2])"
 $values[$a[0]]=[ordered]@{source_sha256=(Get-FileHash -LiteralPath ($base+'.mq5') -Algorithm SHA256).Hash.ToLowerInvariant();binary_sha256=(Get-FileHash -LiteralPath ($base+'.ex5') -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$values|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $out 'fxify-fresh-code-hashes.json')
