[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$outputRoot = Join-Path $shareRoot 'remote-output'
$commonRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $root "backups\corrected-v202-$stamp"

$instances = @(
    [ordered]@{
        id='fp-demo'; account=7404213; server='FPMarketsSC-Demo'; version='2.202';
        home='C:\SolTrade\MT5-FP-DEMO'; terminal_home='MT5-FP-DEMO'; expert='SolTradeFastMultiMarketV2';
        source='payload\fp-demo\SolTradeFastMultiMarketV2.mq5';
        binary='payload\fp-demo\SolTradeFastMultiMarketV2.ex5';
        preset='payload\fp-demo\SolTradeFastMultiMarketV2-FPMarkets-demo.set';
        startup='runtime\fp-demo.ini'; state_dir='SolTradeFastMultiMarketV2';
        magic=2108202601; order_permission='ENABLED_FP_DEMO'; ownership_instance='vps-fp-prod'; profile='SolTradeV202FP';
        expected_source_sha='099d7eefca731abc72c4b140e72671496184dbee88f948b7841f6e48324f2d95';
        expected_binary_sha='9a7ac91da81975f9950e6ec3952076e24e787954af5af1c1ac722331eb8f1398'
    },
    [ordered]@{
        id='fxify-10k'; account=7196820; server='FXIFY-Server'; version='2.202';
        home='C:\SolTrade\MT5-FXIFY-10K'; terminal_home='MT5-FXIFY-10K'; expert='SolTradeFastMultiMarketV202F10';
        source='payload\fxify-10k\SolTradeFastMultiMarketV202F10.mq5';
        binary='payload\fxify-10k\SolTradeFastMultiMarketV202F10.ex5';
        preset='payload\fxify-10k\SolTradeFastMultiMarketV202F10-FINAL-ALGO-OFF.set';
        startup='runtime\fxify-10k.ini'; state_dir='SolTradeFastMultiMarketV2F10';
        magic=2108202610; order_permission='ENABLED_USER_ACTIVATED'; ownership_instance='vps-fxify-10k-prod'; profile='SolTradeV202F10';
        expected_source_sha='0a69d32560761153e78379fcca05e29cda0c285264a34894935a47a2605c570f';
        expected_binary_sha='db188505fb586eab6d0af907cbff07328f30d2c0ff4d7564bdeb4fedd6c566a5'
    },
    [ordered]@{
        id='fxify-100k'; account=7198096; server='FXIFY-Server'; version='2.202';
        home='C:\SolTrade\MT5-FXIFY-100K'; terminal_home='MT5-FXIFY-100K'; expert='SolTradeFastMultiMarketV202F100';
        source='payload\fxify-100k\SolTradeFastMultiMarketV202F100.mq5';
        binary='payload\fxify-100k\SolTradeFastMultiMarketV202F100.ex5';
        preset='payload\fxify-100k\SolTradeFastMultiMarketV202F100-FINAL-ALGO-OFF.set';
        startup='runtime\fxify-100k.ini'; state_dir='SolTradeFastMultiMarketV2F100';
        magic=2108202620; order_permission='ENABLED_USER_ACTIVATED'; ownership_instance='vps-fxify-100k-prod'; profile='SolTradeV202F100';
        expected_source_sha='961add4899821fd2bb03d3d11d6075a086aaedf3b7059c4fb635a0e1a3041ea2';
        expected_binary_sha='a7fcbf3b68e5c7955a4cf363f551e67d8da51f59a52dfd337355f0587f3c4b55'
    }
)

function Get-Sha([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Runtime([string]$StateDir) {
    $path = Join-Path (Join-Path $commonRoot $StateDir) 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    return ($lines | ConvertFrom-Csv | Select-Object -First 1)
}

function Write-AtomicText([string]$Path,[string[]]$Lines) {
    $temporary = "$Path.$PID.tmp"
    [IO.File]::WriteAllLines($temporary,$Lines,[Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporary -Destination $Path
}

New-Item -ItemType Directory -Force -Path $outputRoot,$backupRoot,(Join-Path $root 'state'),(Join-Path $root 'logs'),(Join-Path $root 'ownership'),(Join-Path $root 'watchdogs') | Out-Null

# Fail closed if any runtime currently reports an open position or order.
$preflight = @()
foreach ($instance in $instances) {
    $runtime = Read-Runtime $instance.state_dir
    if (-not $runtime) { throw "Missing runtime telemetry for $($instance.id); refusing a blind restart." }
    if ([long]$runtime.login -ne [long]$instance.account) { throw "Account mismatch for $($instance.id): runtime=$($runtime.login), expected=$($instance.account)." }
    if ([int]$runtime.positions -ne 0 -or [int]$runtime.orders -ne 0) {
        throw "Open exposure on $($instance.id): positions=$($runtime.positions), orders=$($runtime.orders). Deployment aborted."
    }
    $preflight += [ordered]@{
        id=$instance.id; login=[long]$runtime.login; server=[string]$runtime.server;
        positions=[int]$runtime.positions; orders=[int]$runtime.orders;
        scanner_active=[string]$runtime.scanner_active; connected=[string]$runtime.connected;
        timestamp_utc=[string]$runtime.timestamp_utc
    }
}

# Verify the exact reviewed artifacts before stopping a terminal.
foreach ($instance in $instances) {
    $sourcePath = Join-Path $shareRoot $instance.source
    $binaryPath = Join-Path $shareRoot $instance.binary
    $presetPath = Join-Path $shareRoot $instance.preset
    $startupPath = Join-Path $shareRoot $instance.startup
    foreach ($path in @($sourcePath,$binaryPath,$presetPath,$startupPath)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Required deployment artifact missing: $path" }
    }
    if ((Get-Sha $sourcePath) -ne $instance.expected_source_sha) { throw "Source hash mismatch for $($instance.id)." }
    if ((Get-Sha $binaryPath) -ne $instance.expected_binary_sha) { throw "Binary hash mismatch for $($instance.id)." }
}

# Stop only the three isolated SolTrade terminals. Preflight above proves zero exposure.
$terminalPaths = @($instances | ForEach-Object { Join-Path $_.home 'terminal64.exe' })
Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $terminalPaths -contains $_.ExecutablePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 3

# Back up the files that are about to be replaced and deploy reviewed artifacts.
foreach ($instance in $instances) {
    $expertDir = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    $presetDir = Join-Path $instance.home 'MQL5\Presets'
    $instanceBackup = Join-Path $backupRoot $instance.id
    New-Item -ItemType Directory -Force -Path $expertDir,$presetDir,$instanceBackup,(Join-Path $instance.home 'MQL5\Files\SolTradeOwnership') | Out-Null

    foreach ($existing in @(
        (Join-Path $expertDir "$($instance.expert).mq5"),
        (Join-Path $expertDir "$($instance.expert).ex5"),
        (Join-Path $presetDir (Split-Path $instance.preset -Leaf)),
        (Join-Path $root "state\$($instance.id).ini")
    )) {
        if (Test-Path -LiteralPath $existing) { Copy-Item -Force -LiteralPath $existing -Destination $instanceBackup }
    }

    Copy-Item -Force -LiteralPath (Join-Path $shareRoot $instance.source) -Destination (Join-Path $expertDir "$($instance.expert).mq5")
    Copy-Item -Force -LiteralPath (Join-Path $shareRoot $instance.binary) -Destination (Join-Path $expertDir "$($instance.expert).ex5")
    Copy-Item -Force -LiteralPath (Join-Path $shareRoot $instance.preset) -Destination (Join-Path $presetDir (Split-Path $instance.preset -Leaf))
    Copy-Item -Force -LiteralPath (Join-Path $shareRoot $instance.startup) -Destination (Join-Path $root "state\$($instance.id).ini")
    New-Item -ItemType File -Force -Path (Join-Path $instance.home 'portable.txt') | Out-Null

    # A dedicated clean profile prevents a saved V2.201 chart from being
    # restored alongside the reviewed V2.202 startup EA.
    $chartRoot = Join-Path $instance.home 'Profiles\Charts'
    $targetProfile = Join-Path $chartRoot $instance.profile
    New-Item -ItemType Directory -Force -Path $chartRoot | Out-Null
    if (Test-Path -LiteralPath $targetProfile) {
        Move-Item -Force -LiteralPath $targetProfile -Destination (Join-Path $instanceBackup $instance.profile)
    }
    New-Item -ItemType Directory -Force -Path $targetProfile | Out-Null
    $defaultProfile = Join-Path $chartRoot 'Default'
    if (Test-Path -LiteralPath $defaultProfile) {
        Copy-Item -Recurse -Force (Join-Path $defaultProfile '*') -Destination $targetProfile
    }
}

$instances | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $root 'state\instances.json')
Copy-Item -Force -LiteralPath (Join-Path $shareRoot 'Watch-SolTrade.ps1') -Destination (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
Copy-Item -Force -LiteralPath (Join-Path $shareRoot 'Run-AccountOwnershipAuthority.ps1') -Destination (Join-Path $root 'ownership\Run-AccountOwnershipAuthority.ps1')

# Install an isolated ownership authority for every account and inject credentials only on the VPS.
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$trigger = New-ScheduledTaskTrigger -AtStartup
foreach ($instance in $instances) {
    $secretPath = Join-Path $root "ownership\claim-secret-$($instance.account).txt"
    if (-not (Test-Path -LiteralPath $secretPath)) {
        $bytes = [byte[]]::new(48)
        $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
        [IO.File]::WriteAllText($secretPath,[Convert]::ToBase64String($bytes),[Text.UTF8Encoding]::new($false))
    }
    $secret = (Get-Content -Raw -LiteralPath $secretPath).Trim()
    if ($secret.Length -lt 32) { throw "Ownership secret invalid for $($instance.account)." }

    $presetPath = Join-Path $instance.home "MQL5\Presets\$(Split-Path $instance.preset -Leaf)"
    $preset = @(Get-Content -LiteralPath $presetPath)
    $preset = @($preset -replace '^OwnershipHost=.*$',("OwnershipHost=" + $env:COMPUTERNAME))
    $preset = @($preset -replace '^OwnershipClaimSecret=.*$',("OwnershipClaimSecret=" + $secret))
    Write-AtomicText $presetPath $preset

    $taskName = "SolTrade-AccountOwnership-$($instance.account)"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File C:\SolTrade\ownership\Run-AccountOwnershipAuthority.ps1 -Account $($instance.account) -TerminalHome $($instance.terminal_home) -ExpectedInstanceId $($instance.ownership_instance) -ExpectedHost $env:COMPUTERNAME"
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $arguments
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
}

& icacls.exe (Join-Path $root 'ownership') /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'trader:(OI)(CI)F' | Out-Null

# Preserve the existing watchdog identity/triggers but make its new code active.
$watchdog = Get-ScheduledTask -TaskName 'SolTrade-Watchdog' -ErrorAction SilentlyContinue
if (-not $watchdog) {
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\SolTrade\watchdogs\Watch-SolTrade.ps1'
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $minuteTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    $watchdogPrincipal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
    Register-ScheduledTask -TaskName 'SolTrade-Watchdog' -Action $action -Trigger @($startupTrigger,$minuteTrigger) -Principal $watchdogPrincipal -Force | Out-Null
}
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName 'SolTrade-Watchdog'
Start-Sleep -Seconds 35

$post = @()
foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $expertDir = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    $runtime = Read-Runtime $instance.state_dir
    $taskName = "SolTrade-AccountOwnership-$($instance.account)"
    $leasePath = Join-Path $root "ownership\lease-$($instance.account).json"
    $lease = if (Test-Path -LiteralPath $leasePath) { Get-Content -Raw -LiteralPath $leasePath | ConvertFrom-Json } else { $null }
    $post += [ordered]@{
        id=$instance.id; account=$instance.account; server_expected=$instance.server; version=$instance.version;
        process_running=[bool]$process; pid=if ($process) { $process.ProcessId } else { $null };
        source_sha256=Get-Sha (Join-Path $expertDir "$($instance.expert).mq5");
        binary_sha256=Get-Sha (Join-Path $expertDir "$($instance.expert).ex5");
        source_hash_matches=((Get-Sha (Join-Path $expertDir "$($instance.expert).mq5")) -eq $instance.expected_source_sha);
        binary_hash_matches=((Get-Sha (Join-Path $expertDir "$($instance.expert).ex5")) -eq $instance.expected_binary_sha);
        preset_sha256=Get-Sha (Join-Path $instance.home "MQL5\Presets\$(Split-Path $instance.preset -Leaf)");
        configured_order_permission=$instance.order_permission;
        ownership_task_state=(Get-ScheduledTask -TaskName $taskName).State.ToString();
        lease_account=if ($lease) { [long]$lease.account } else { $null };
        lease_instance=if ($lease -and $lease.lease) { [string]$lease.lease.instance_id } else { $null };
        lease_host=if ($lease -and $lease.lease) { [string]$lease.lease.host } else { $null };
        lease_expires_epoch=if ($lease -and $lease.lease) { [long]$lease.lease.expires_epoch } else { $null };
        runtime=$runtime
    }
}

$result = [ordered]@{
    schema='SOLTRADE_CORRECTED_V202_DEPLOYMENT_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    host=$env:COMPUTERNAME
    status=if (@($post | Where-Object { -not $_.process_running -or -not $_.source_hash_matches -or -not $_.binary_hash_matches }).Count -eq 0) { 'DEPLOYED_HASH_VERIFIED' } else { 'POST_DEPLOYMENT_CHECK_FAILED' }
    backup_root=$backupRoot
    preflight=$preflight
    instances=$post
    fp_order_permission_enabled=$true
    fxify_order_sending_enabled=$true
    test_orders_placed=$false
    strategy_thresholds_changed=$false
}
$result | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $outputRoot 'corrected-v202-deployment.json')
$result | ConvertTo-Json -Depth 12
