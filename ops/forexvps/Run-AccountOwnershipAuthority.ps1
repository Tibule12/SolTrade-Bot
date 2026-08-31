[CmdletBinding()]
param(
    [string]$Root = 'C:\SolTrade',
    [long]$Account = 7404213,
    [string]$TerminalHome = 'MT5-FP-DEMO',
    [string]$ExpectedInstanceId = 'vps-fp-prod',
    [string]$ExpectedHost = $env:COMPUTERNAME,
    [int]$LeaseTtlSeconds = 15,
    [int]$PollMilliseconds = 500,
    [switch]$Once,
    [Nullable[long]]$NowEpoch
)

$ErrorActionPreference = 'Stop'
if ($LeaseTtlSeconds -lt 10 -or $LeaseTtlSeconds -gt 60) {
    throw 'Lease TTL must be between 10 and 60 seconds.'
}

$ownershipRoot = Join-Path $Root 'ownership'
$exchangeRoot = Join-Path $Root "$TerminalHome\MQL5\Files\SolTradeOwnership"
$statePath = Join-Path $ownershipRoot "lease-$Account.json"
$auditPath = Join-Path $ownershipRoot "lease-$Account-audit.jsonl"
$secretPath = Join-Path $ownershipRoot "claim-secret-$Account.txt"
New-Item -ItemType Directory -Force -Path $ownershipRoot,$exchangeRoot | Out-Null
if (-not (Test-Path -LiteralPath $secretPath)) { throw "Ownership secret missing: $secretPath" }
$expectedSecret = (Get-Content -Raw -LiteralPath $secretPath).Trim()
if ($expectedSecret.Length -lt 32) { throw 'Ownership secret is too short.' }

function Get-Epoch {
    if ($null -ne $NowEpoch) { return [long]$NowEpoch }
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Read-KeyValueFile([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $values[$line.Substring(0,$separator)] = $line.Substring($separator + 1)
    }
    return $values
}

function Write-AtomicText([string]$Path,[string[]]$Lines) {
    $temporary = "$Path.$PID.tmp"
    [IO.File]::WriteAllLines($temporary,$Lines,[Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporary -Destination $Path
}

function Write-Audit([string]$Event,[hashtable]$Lease,[string]$PermitState,[string]$Detail) {
    $record = [ordered]@{
        schema = 'SOLTRADE_ACCOUNT_OWNERSHIP_AUDIT_V1'
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        timestamp_epoch = Get-Epoch
        event = $Event
        account = $Account
        owner_instance_id = if ($Lease) { $Lease.instance_id } else { '' }
        owner_runtime_id = if ($Lease) { $Lease.runtime_id } else { '' }
        owner_host = if ($Lease) { $Lease.host } else { '' }
        lease_id = if ($Lease) { $Lease.lease_id } else { '' }
        acquired_epoch = if ($Lease) { $Lease.acquired_epoch } else { 0 }
        renewed_epoch = if ($Lease) { $Lease.renewed_epoch } else { 0 }
        expires_epoch = if ($Lease) { $Lease.expires_epoch } else { 0 }
        permit_state = $PermitState
        detail = $Detail
    }
    Add-Content -LiteralPath $auditPath -Encoding UTF8 -Value ($record | ConvertTo-Json -Compress)
}

function Save-State([hashtable]$Lease) {
    $document = [ordered]@{
        schema = 'SOLTRADE_ACCOUNT_OWNERSHIP_STATE_V1'
        account = $Account
        lease = $Lease
    }
    Write-AtomicText $statePath @(($document | ConvertTo-Json -Depth 6))
}

function Load-State {
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try {
        $document = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        if ($document.schema -ne 'SOLTRADE_ACCOUNT_OWNERSHIP_STATE_V1' -or [long]$document.account -ne $Account -or -not $document.lease) { return $null }
        return @{
            account = [long]$document.lease.account
            instance_id = [string]$document.lease.instance_id
            host = [string]$document.lease.host
            runtime_id = [string]$document.lease.runtime_id
            lease_id = [string]$document.lease.lease_id
            acquired_epoch = [long]$document.lease.acquired_epoch
            renewed_epoch = [long]$document.lease.renewed_epoch
            expires_epoch = [long]$document.lease.expires_epoch
            last_audit_renew_epoch = [long]$document.lease.last_audit_renew_epoch
        }
    } catch {
        Write-Audit 'STATE_RECOVERY_FAILED' $null 'BLOCKED' $_.Exception.Message
        return $null
    }
}

function Permit-Path([string]$RuntimeId) { return Join-Path $exchangeRoot "permit-$RuntimeId.txt" }

function Write-Permit([hashtable]$Lease,[string]$State,[string]$Reason) {
    $lines = @(
        'schema=SOLTRADE_ACCOUNT_OWNERSHIP_PERMIT_V1',
        "state=$State",
        "account=$Account",
        "instance_id=$($Lease.instance_id)",
        "host=$($Lease.host)",
        "runtime_id=$($Lease.runtime_id)",
        "lease_id=$($Lease.lease_id)",
        "acquired_epoch=$($Lease.acquired_epoch)",
        "renewed_epoch=$($Lease.renewed_epoch)",
        "expires_epoch=$($Lease.expires_epoch)",
        "reason=$Reason"
    )
    Write-AtomicText (Permit-Path $Lease.runtime_id) $lines
}

function Claim-IsAuthorized([hashtable]$Claim,[long]$Now) {
    if ($Claim.schema -ne 'SOLTRADE_ACCOUNT_OWNERSHIP_V1' -or $Claim.state -ne 'CLAIM') { return $false }
    if ([long]$Claim.account -ne $Account -or $Claim.instance_id -ne $ExpectedInstanceId -or $Claim.host -ne $ExpectedHost) { return $false }
    if ($Claim.claim_secret -cne $expectedSecret) { return $false }
    $requested = [long]$Claim.requested_epoch
    return $requested -le $Now + 5 -and $Now - $requested -le $LeaseTtlSeconds
}

function Invoke-LeaseCycle {
    $now = Get-Epoch
    $mutex = [Threading.Mutex]::new($false,"Global\SolTradeOwnership-$Account")
    if (-not $mutex.WaitOne(5000)) { throw 'Ownership mutex acquisition timed out; fail closed.' }
    try {
        $lease = Load-State
        $claims = @()
        foreach ($file in Get-ChildItem -LiteralPath $exchangeRoot -Filter 'claim-*.txt' -File -ErrorAction SilentlyContinue) {
            try {
                $claim = Read-KeyValueFile $file.FullName
                $claim['_path'] = $file.FullName
                if (Claim-IsAuthorized $claim $now) { $claims += ,$claim }
                else {
                    $denied = @{
                        instance_id = [string]$claim.instance_id; host = [string]$claim.host; runtime_id = [string]$claim.runtime_id
                        lease_id = ''; acquired_epoch = 0; renewed_epoch = $now; expires_epoch = $now
                    }
                    Write-Permit $denied 'DENIED' 'UNAUTHORIZED_OR_STALE_CLAIM'
                }
            } catch {
                Write-Audit 'MALFORMED_CLAIM_DENIED' $null 'DENIED' $file.Name
            }
        }

        foreach ($releaseFile in Get-ChildItem -LiteralPath $exchangeRoot -Filter 'release-*.txt' -File -ErrorAction SilentlyContinue) {
            try {
                $release = Read-KeyValueFile $releaseFile.FullName
                if ($lease -and $release.claim_secret -ceq $expectedSecret -and $release.runtime_id -eq $lease.runtime_id) {
                    Write-Audit 'RELEASED' $lease 'RELEASED' 'owner_requested_release=true'
                    Remove-Item -Force -ErrorAction SilentlyContinue (Permit-Path $lease.runtime_id)
                    $lease = $null
                    Save-State $null
                }
            } finally {
                Remove-Item -Force -ErrorAction SilentlyContinue $releaseFile.FullName
            }
        }

        $ownerClaim = $null
        if ($lease) { $ownerClaim = $claims | Where-Object { $_.runtime_id -eq $lease.runtime_id } | Select-Object -First 1 }
        if ($lease -and (([long]$lease.expires_epoch -le $now) -or -not $ownerClaim)) {
            if ([long]$lease.expires_epoch -le $now) {
                Write-Audit 'STALE_LEASE_EXPIRED' $lease 'EXPIRED' "bounded_recovery_seconds=$LeaseTtlSeconds"
                Remove-Item -Force -ErrorAction SilentlyContinue (Permit-Path $lease.runtime_id)
                $lease = $null
                Save-State $null
            }
        }

        if ($lease -and $ownerClaim) {
            $lease.renewed_epoch = $now
            $lease.expires_epoch = $now + $LeaseTtlSeconds
            if ($now - [long]$lease.last_audit_renew_epoch -ge 5) {
                $lease.last_audit_renew_epoch = $now
                Write-Audit 'RENEWED' $lease 'GRANTED' "ttl_seconds=$LeaseTtlSeconds"
            }
            Save-State $lease
            Write-Permit $lease 'GRANTED' 'CURRENT_OWNER'
        }

        if (-not $lease -and $claims.Count -gt 0) {
            $winner = $claims | Sort-Object @{Expression={ [long]$_.requested_epoch }},runtime_id | Select-Object -First 1
            $lease = @{
                account = $Account; instance_id = $ExpectedInstanceId; host = $ExpectedHost
                runtime_id = [string]$winner.runtime_id; lease_id = [Guid]::NewGuid().ToString('N')
                acquired_epoch = $now; renewed_epoch = $now; expires_epoch = $now + $LeaseTtlSeconds
                last_audit_renew_epoch = $now
            }
            Save-State $lease
            Write-Permit $lease 'GRANTED' 'ATOMIC_ACQUIRE'
            Write-Audit 'ACQUIRED' $lease 'GRANTED' "ttl_seconds=$LeaseTtlSeconds;race_candidates=$($claims.Count)"
        }

        foreach ($claim in $claims) {
            if (-not $lease -or $claim.runtime_id -eq $lease.runtime_id) { continue }
            $denied = @{
                instance_id = [string]$claim.instance_id; host = [string]$claim.host; runtime_id = [string]$claim.runtime_id
                lease_id = [string]$lease.lease_id; acquired_epoch = [long]$lease.acquired_epoch
                renewed_epoch = $now; expires_epoch = [long]$lease.expires_epoch
            }
            Write-Permit $denied 'DENIED' "OWNED_BY_RUNTIME_$($lease.runtime_id)"
        }
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

do {
    Invoke-LeaseCycle
    if (-not $Once) { Start-Sleep -Milliseconds $PollMilliseconds }
} while (-not $Once)
