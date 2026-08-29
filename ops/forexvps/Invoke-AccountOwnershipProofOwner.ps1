[CmdletBinding()]
param(
    [int]$DurationSeconds = 300,
    [string]$RuntimeId = 'vps-proof-owner'
)

$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$exchange = Join-Path $root 'MT5-FP-DEMO\MQL5\Files\SolTradeOwnership'
$secret = (Get-Content -Raw -LiteralPath (Join-Path $root 'ownership\claim-secret-7404213.txt')).Trim()
$claim = Join-Path $exchange "claim-$RuntimeId.txt"
$release = Join-Path $exchange "release-$RuntimeId.txt"
$proofOutput = '\\tsclient\SolTrade\remote-output\ownership-proof-owner-heartbeat.json'
$permitProofOutput = '\\tsclient\SolTrade\remote-output\ownership-vps-owner-proof.json'

function Write-Message([string]$Path,[string]$State) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lines = @(
        'schema=SOLTRADE_ACCOUNT_OWNERSHIP_V1',
        "state=$State",
        'account=7404213',
        'instance_id=vps-fp-prod',
        "host=$env:COMPUTERNAME",
        "runtime_id=$RuntimeId",
        "requested_epoch=$now",
        'requested_ttl_seconds=15',
        "claim_secret=$secret"
    )
    $temporary = "$Path.$PID.tmp"
    [IO.File]::WriteAllLines($temporary,$lines,[Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporary -Destination $Path
}

$until = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $DurationSeconds
try {
    while ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $until) {
        Write-Message $claim 'CLAIM'
        [ordered]@{
            schema='SOLTRADE_OWNERSHIP_PROOF_OWNER_HEARTBEAT_V1'
            timestamp_utc=[DateTime]::UtcNow.ToString('o')
            account=7404213
            instance_id='vps-fp-prod'
            host=$env:COMPUTERNAME
            runtime_id=$RuntimeId
            state='CLAIM_HEARTBEAT_ACTIVE'
            secret_logged=$false
            authority_task=(Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -ErrorAction SilentlyContinue).State.ToString()
            exchange_files=@(Get-ChildItem -LiteralPath $exchange -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTimeUtc)
            state_file_exists=(Test-Path -LiteralPath (Join-Path $root 'ownership\lease-7404213.json'))
            audit_file_exists=(Test-Path -LiteralPath (Join-Path $root 'ownership\lease-7404213-audit.jsonl'))
            permit=@(if (Test-Path -LiteralPath (Join-Path $exchange "permit-$RuntimeId.txt")) { Get-Content -LiteralPath (Join-Path $exchange "permit-$RuntimeId.txt") })
            lease_state=$(if (Test-Path -LiteralPath (Join-Path $root 'ownership\lease-7404213.json')) { Get-Content -Raw -LiteralPath (Join-Path $root 'ownership\lease-7404213.json') | ConvertFrom-Json })
            audit_tail=@(if (Test-Path -LiteralPath (Join-Path $root 'ownership\lease-7404213-audit.jsonl')) { Get-Content -LiteralPath (Join-Path $root 'ownership\lease-7404213-audit.jsonl') | Select-Object -Last 6 })
        } | ConvertTo-Json | Set-Content -Encoding UTF8 $proofOutput
        $permitPath = Join-Path $exchange "permit-$RuntimeId.txt"
        if (Test-Path -LiteralPath $permitPath) {
            [ordered]@{
                schema='SOLTRADE_VPS_OWNER_PROOF_V1'
                timestamp_utc=[DateTime]::UtcNow.ToString('o')
                status='PROVEN'
                permit=(Get-Content -LiteralPath $permitPath | Where-Object { $_ -notlike 'claim_secret=*' })
                state=(Get-Content -Raw -LiteralPath (Join-Path $root 'ownership\lease-7404213.json') | ConvertFrom-Json)
                audit_tail=(Get-Content -LiteralPath (Join-Path $root 'ownership\lease-7404213-audit.jsonl') | Select-Object -Last 8)
            } | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 $permitProofOutput
        }
        Start-Sleep -Seconds 2
    }
} finally {
    Write-Message $release 'RELEASE'
}
