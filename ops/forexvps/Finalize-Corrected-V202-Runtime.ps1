[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$commonRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$outputRoot = Join-Path $shareRoot 'remote-output'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $root "backups\runtime-profile-$stamp"

$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$profiles = @{
    'fp-demo'='SolTradeV202FP'
    'fxify-10k'='SolTradeV202F10'
    'fxify-100k'='SolTradeV202F100'
}
$stateDirs = @{
    'fp-demo'='SolTradeFastMultiMarketV2'
    'fxify-10k'='SolTradeFastMultiMarketV2F10'
    'fxify-100k'='SolTradeFastMultiMarketV2F100'
}
$expected = @{
    'fp-demo'=@{ source='58649a396dff714ebc3901eb03c90715eba305e6986bc58a2f7446c6a3dbe525'; binary='0b37e5c4cc4383a310003625c40ce7931aabdf2c4031b19222af58585a19b70e' }
    'fxify-10k'=@{ source='6d5f98582ec5dd365823e32917eec84816f364b3a2920c45527f3441ca81152f'; binary='7292b4413e19cb0bb5f3ca80b7e99b19f1c9377687ecc8622e9919dc34aaba4c' }
    'fxify-100k'=@{ source='6fe6e116124b163e9505a4341e76ffb3253a48a90c7c561b2cc3e9278dec1e8d'; binary='1ae399c8a3f41ec50729f892b73e1c140888c19a08d80e0ad74ff695125086c9' }
}

function Read-Runtime([string]$StateDir) {
    $path = Join-Path (Join-Path $commonRoot $StateDir) 'runtime.csv'
    if (-not (Test-Path $path)) { return $null }
    $lines = @(Get-Content $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

function Get-Sha([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLowerInvariant()
}

New-Item -ItemType Directory -Force -Path $backupRoot,$outputRoot | Out-Null

# A runtime-profile change is permitted only with no open exposure.
foreach ($instance in $instances) {
    $runtime = Read-Runtime $stateDirs[$instance.id]
    if (-not $runtime) {
        # FXIFY may not yet have created the new V2.202 state directory. Its old
        # scanner telemetry is acceptable for this one-time attachment repair.
        if ($instance.id -eq 'fp-demo') { throw 'FP runtime telemetry is missing.' }
        $oldState = if ($instance.id -eq 'fxify-10k') { 'SolTradeFastMultiMarketV2F10' } else { 'SolTradeFastMultiMarketV2F100' }
        $runtime = Read-Runtime $oldState
    }
    if (-not $runtime) { throw "Runtime telemetry missing for $($instance.id)." }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Exposure is open on $($instance.id); attachment repair aborted."
    }
}

$terminalPaths = @($instances | ForEach-Object { Join-Path $_.home 'terminal64.exe' })
Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $terminalPaths -contains $_.ExecutablePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 4

foreach ($instance in $instances) {
    $profileName = $profiles[$instance.id]
    $chartRoot = Join-Path $instance.home 'Profiles\Charts'
    $targetProfile = Join-Path $chartRoot $profileName
    $profileBackup = Join-Path $backupRoot $instance.id
    New-Item -ItemType Directory -Force -Path $chartRoot,$profileBackup | Out-Null
    if (Test-Path $targetProfile) {
        Move-Item -Force $targetProfile (Join-Path $profileBackup $profileName)
    }
    New-Item -ItemType Directory -Force -Path $targetProfile | Out-Null
    $defaultProfile = Join-Path $chartRoot 'Default'
    if (Test-Path $defaultProfile) {
        Copy-Item -Recurse -Force (Join-Path $defaultProfile '*') $targetProfile
    }
    $instance | Add-Member -NotePropertyName profile -NotePropertyValue $profileName -Force

    $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    if ((Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")) -ne $expected[$instance.id].source) {
        throw "Source hash changed before runtime attachment for $($instance.id)."
    }
    if ((Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")) -ne $expected[$instance.id].binary) {
        throw "Binary hash changed before runtime attachment for $($instance.id)."
    }
}

$instances | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $root 'state\instances.json')
Copy-Item -Force (Join-Path $shareRoot 'Watch-SolTrade.ps1') (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
Start-ScheduledTask -TaskName 'SolTrade-Watchdog'
Start-Sleep -Seconds 50

$post = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $stateDirs[$instance.id]
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $taskName = "SolTrade-AccountOwnership-$($instance.account)"
    $leasePath = Join-Path $root "ownership\lease-$($instance.account).json"
    $lease = if (Test-Path $leasePath) { Get-Content -Raw $leasePath | ConvertFrom-Json } else { $null }
    $expertRoot = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    $post += [ordered]@{
        id=$instance.id
        profile=$instance.profile
        process_running=[bool]$process
        pid=if ($process) { $process.ProcessId } else { $null }
        source_hash_matches=((Get-Sha (Join-Path $expertRoot "$($instance.expert).mq5")) -eq $expected[$instance.id].source)
        binary_hash_matches=((Get-Sha (Join-Path $expertRoot "$($instance.expert).ex5")) -eq $expected[$instance.id].binary)
        ownership_task_state=(Get-ScheduledTask -TaskName $taskName).State.ToString()
        lease=if ($lease) { $lease } else { $null }
        runtime=$runtime
    }
}

$result = [ordered]@{
    schema='SOLTRADE_CORRECTED_V202_RUNTIME_FINAL_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    backup_root=$backupRoot
    instances=$post
    fp_order_permission_enabled=$true
    fxify_order_sending_enabled=$false
    test_orders_placed=$false
}
$result | ConvertTo-Json -Depth 14 | Set-Content -Encoding UTF8 (Join-Path $outputRoot 'corrected-v202-runtime-final.json')
$result | ConvertTo-Json -Depth 14

