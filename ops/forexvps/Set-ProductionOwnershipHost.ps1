$ErrorActionPreference = 'Stop'
$presetPath = 'C:\SolTrade\MT5-FP-DEMO\MQL5\Presets\SolTradeFastMultiMarketV2-FPMarkets-demo.set'
$lines = Get-Content -LiteralPath $presetPath
$lines = $lines -replace '^OwnershipHost=.*$',('OwnershipHost=' + $env:COMPUTERNAME)
[IO.File]::WriteAllLines($presetPath,$lines,[Text.UTF8Encoding]::new($false))
[ordered]@{
    schema='SOLTRADE_PRODUCTION_OWNERSHIP_HOST_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    account=7404213
    host=$env:COMPUTERNAME
    configured=($lines -contains ('OwnershipHost=' + $env:COMPUTERNAME))
    secret_present=(($lines | Where-Object { $_ -like 'OwnershipClaimSecret=*' }) -ne 'OwnershipClaimSecret=')
    secret_logged=$false
} | ConvertTo-Json | Set-Content -Encoding UTF8 '\\tsclient\SolTrade\remote-output\ownership-host-fix.json'
