$ErrorActionPreference = 'Stop'
$output = '\\tsclient\SolTrade\remote-output\ownership-vps-owner-proof.json'
try {
    $exchange = 'C:\SolTrade\MT5-FP-DEMO\MQL5\Files\SolTradeOwnership'
    $permitPath = Join-Path $exchange 'permit-vps-proof-owner.txt'
    $permit = Get-Content -LiteralPath $permitPath | Where-Object { $_ -notlike 'claim_secret=*' }
    $state = Get-Content -Raw -LiteralPath 'C:\SolTrade\ownership\lease-7404213.json' | ConvertFrom-Json
    $audit = Get-Content -LiteralPath 'C:\SolTrade\ownership\lease-7404213-audit.jsonl' | Select-Object -Last 8
    $document = [ordered]@{
        schema='SOLTRADE_VPS_OWNER_PROOF_V1'
        timestamp_utc=[DateTime]::UtcNow.ToString('o')
        status='PROVEN'
        permit=$permit
        state=$state
        audit_tail=$audit
    }
} catch {
    $document = [ordered]@{
        schema='SOLTRADE_VPS_OWNER_PROOF_V1'
        timestamp_utc=[DateTime]::UtcNow.ToString('o')
        status='FAILED'
        error=$_.Exception.Message
        authority_task=(Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -ErrorAction SilentlyContinue).State.ToString()
        exchange_files=@(Get-ChildItem 'C:\SolTrade\MT5-FP-DEMO\MQL5\Files\SolTradeOwnership' -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTimeUtc)
    }
}
$document | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 $output
