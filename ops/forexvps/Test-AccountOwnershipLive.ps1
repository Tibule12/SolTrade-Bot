$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$exchange = Join-Path $root 'MT5-FP-DEMO\MQL5\Files\SolTradeOwnership'
$authority = Join-Path $root 'ownership\Run-AccountOwnershipAuthority.ps1'
$secret = (Get-Content -Raw -LiteralPath (Join-Path $root 'ownership\claim-secret-7404213.txt')).Trim()
$hostName = $env:COMPUTERNAME
$ttl = 15

function Write-Message([string]$Runtime,[string]$State,[Nullable[long]]$Epoch=$null) {
    $now = if ($null -ne $Epoch) { [long]$Epoch } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    $prefix = if ($State -eq 'RELEASE') { 'release' } else { 'claim' }
    $path = Join-Path $exchange "$prefix-$Runtime.txt"
    $lines = @(
        'schema=SOLTRADE_ACCOUNT_OWNERSHIP_V1',"state=$State",'account=7404213','instance_id=vps-fp-prod',
        "host=$hostName","runtime_id=$Runtime","requested_epoch=$now",'requested_ttl_seconds=15',"claim_secret=$secret"
    )
    $temporary = "$path.$PID.tmp"
    [IO.File]::WriteAllLines($temporary,$lines,[Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporary -Destination $path
}

function Invoke-Cycle { Start-Sleep -Milliseconds 1500 }

function Read-Permit([string]$Runtime) {
    $values = @{}
    $path = Join-Path $exchange "permit-$Runtime.txt"
    if (-not (Test-Path -LiteralPath $path)) { return @{ state='MISSING'; runtime_id=$Runtime } }
    foreach ($line in Get-Content -LiteralPath $path) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $values[$line.Substring(0,$separator)] = $line.Substring($separator+1) }
    }
    return @{
        state=$values.state; account=$values.account; instance_id=$values.instance_id; host=$values.host
        runtime_id=$values.runtime_id; lease_id=$values.lease_id; acquired_epoch=$values.acquired_epoch
        renewed_epoch=$values.renewed_epoch; expires_epoch=$values.expires_epoch; reason=$values.reason
    }
}

function Read-ClaimDiagnostic([string]$Runtime) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $exchange "claim-$Runtime.txt")) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $values[$line.Substring(0,$separator)] = $line.Substring($separator+1) }
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return [ordered]@{
        schema=$values.schema; state=$values.state; account_match=([long]$values.account -eq 7404213)
        instance_match=($values.instance_id -eq 'vps-fp-prod'); host_match=($values.host -eq $hostName)
        secret_match=($values.claim_secret -ceq $secret); requested_epoch=[long]$values.requested_epoch
        age_seconds=$now-[long]$values.requested_epoch; runtime_id=$values.runtime_id
    }
}

Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Invoke-AccountOwnershipProofOwner.ps1*'
} | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }

$testRuntimePattern = '^(vps-proof-owner|race-|restart-|crash-)'
$currentStatePath = Join-Path $root 'ownership\lease-7404213.json'
Get-ChildItem -LiteralPath $exchange -File | Where-Object {
    $_.Name -match '^(claim|permit|release)-(vps-proof-owner|race-|restart-|crash-)'
} | Remove-Item -Force -ErrorAction SilentlyContinue

for ($cleanupAttempt=0; $cleanupAttempt -lt 5; $cleanupAttempt++) {
    if (-not (Test-Path -LiteralPath $currentStatePath)) { break }
    $currentState = Get-Content -Raw -LiteralPath $currentStatePath | ConvertFrom-Json
    $currentRuntime = [string]$currentState.lease.runtime_id
    if (-not $currentRuntime) { break }
    if ($currentRuntime -notmatch $testRuntimePattern) { throw "Refusing to displace non-test owner $currentRuntime." }
    Write-Message $currentRuntime 'RELEASE'
    Invoke-Cycle
    Get-Item (Join-Path $exchange "claim-$currentRuntime.txt") -ErrorAction SilentlyContinue | Remove-Item -Force
    Start-Sleep -Seconds 1
}

# Simultaneous startup: same timestamp, atomic authority mutex, exactly one grant.
$raceEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Message 'race-b' 'CLAIM' $raceEpoch
Write-Message 'race-a' 'CLAIM' $raceEpoch
Invoke-Cycle
$raceA = Read-Permit 'race-a'
$raceB = Read-Permit 'race-b'
$raceGranted = @(@($raceA,$raceB) | Where-Object { $_.state -eq 'GRANTED' })
if ($raceGranted.Count -ne 1) {
    [ordered]@{schema='SOLTRADE_ACCOUNT_OWNERSHIP_LIVE_PROOF_V1';status='RACE_FAILED';race_a=$raceA;race_b=$raceB;claim_a=(Read-ClaimDiagnostic 'race-a');claim_b=(Read-ClaimDiagnostic 'race-b');state=(Get-Content -Raw $currentStatePath | ConvertFrom-Json)} |
        ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 '\\tsclient\SolTrade\remote-output\ownership-live-proof.json'
    throw "Race test expected exactly one grant; got $($raceGranted.Count)."
}
$raceWinner = [string]$raceGranted[0].runtime_id
Get-ChildItem -LiteralPath $exchange -File | Where-Object { $_.Name -match '^claim-race-' } | Remove-Item -Force
Write-Message $raceWinner 'RELEASE'
Invoke-Cycle
Get-ChildItem -LiteralPath $exchange -File | Where-Object { $_.Name -match '^(claim|permit|release)-race-' } | Remove-Item -Force

# Clean restart: explicit release followed by a different runtime and lease ID.
Write-Message 'restart-a' 'CLAIM'
Invoke-Cycle
$restartA = Read-Permit 'restart-a'
Get-Item (Join-Path $exchange 'claim-restart-a.txt') -ErrorAction SilentlyContinue | Remove-Item -Force
Write-Message 'restart-a' 'RELEASE'
Invoke-Cycle
Write-Message 'restart-b' 'CLAIM'
Invoke-Cycle
$restartB = Read-Permit 'restart-b'
if ($restartA.state -ne 'GRANTED' -or $restartB.state -ne 'GRANTED' -or $restartA.lease_id -eq $restartB.lease_id) {
    throw 'Clean restart did not reacquire a distinct lease.'
}
Get-Item (Join-Path $exchange 'claim-restart-b.txt') -ErrorAction SilentlyContinue | Remove-Item -Force
Write-Message 'restart-b' 'RELEASE'
Invoke-Cycle
Get-ChildItem -LiteralPath $exchange -File | Where-Object { $_.Name -match '^(claim|permit|release)-restart-' } | Remove-Item -Force

# Crash and stale-lock recovery: owner heartbeat disappears; contender remains
# denied until the bounded TTL, then becomes the only owner.
Write-Message 'crash-a' 'CLAIM'
Invoke-Cycle
$crashA = Read-Permit 'crash-a'
Get-Item (Join-Path $exchange 'claim-crash-a.txt') | Remove-Item -Force
Write-Message 'crash-b' 'CLAIM'
Invoke-Cycle
$crashBBefore = Read-Permit 'crash-b'
for ($elapsed=0; $elapsed -le $ttl+2; $elapsed+=2) {
    Start-Sleep -Seconds 2
    Write-Message 'crash-b' 'CLAIM'
    Invoke-Cycle
}
$crashBAfter = Read-Permit 'crash-b'
if ($crashA.state -ne 'GRANTED' -or $crashBBefore.state -ne 'DENIED' -or $crashBAfter.state -ne 'GRANTED') {
    throw 'Crash/stale-lock recovery contract failed.'
}

$audit = @(Get-Content -LiteralPath (Join-Path $root 'ownership\lease-7404213-audit.jsonl') | Select-Object -Last 30)
$staleEvent = @($audit | Where-Object { $_ -like '*"event":"STALE_LEASE_EXPIRED"*' }).Count -gt 0
if (-not $staleEvent) { throw 'No auditable stale lease expiration was recorded.' }

Get-Item (Join-Path $exchange 'claim-crash-b.txt') -ErrorAction SilentlyContinue | Remove-Item -Force
Write-Message 'crash-b' 'RELEASE'
Invoke-Cycle
Get-ChildItem -LiteralPath $exchange -File | Where-Object { $_.Name -match '^(claim|permit|release)-crash-' } | Remove-Item -Force

$finalState = Get-Content -Raw -LiteralPath (Join-Path $root 'ownership\lease-7404213.json') | ConvertFrom-Json
$proof = [ordered]@{
    schema='SOLTRADE_ACCOUNT_OWNERSHIP_LIVE_PROOF_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    account=7404213
    host=$hostName
    lease_ttl_seconds=$ttl
    simultaneous_race_exactly_one_granted=$true
    simultaneous_race_winner=$raceWinner
    simultaneous_race_a_state=[string]$raceA.state
    simultaneous_race_b_state=[string]$raceB.state
    clean_restart_first_state=[string]$restartA.state
    clean_restart_second_state=[string]$restartB.state
    clean_restart_first_lease_id=[string]$restartA.lease_id
    clean_restart_second_lease_id=[string]$restartB.lease_id
    clean_restart_distinct_lease_ids=$true
    crash_owner_state=[string]$crashA.state
    crash_contender_before_expiry_state=[string]$crashBBefore.state
    crash_contender_after_expiry_state=[string]$crashBAfter.state
    stale_recovery_audited=$staleEvent
    secret_logged=$false
    final_owner_runtime_id=[string]$finalState.lease.runtime_id
    final_owner_permit_state=$(if ($finalState.lease) { 'GRANTED' } else { 'RELEASED_NO_OWNER' })
    audit_tail=@($audit | ForEach-Object { [string]$_ })
}
$proof | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 '\\tsclient\SolTrade\remote-output\ownership-live-proof.json'
