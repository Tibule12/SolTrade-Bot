[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$destination = Join-Path $share 'remote-output\post-fix-cross-account-audit.zip'
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$day = [DateTime]::UtcNow.ToString('yyyyMMdd')
$cutoffUtc = '2026.09.03 17:15:20'
$bundle = Join-Path $root ("state\post-fix-audit-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $bundle | Out-Null

$instances = @(
    [ordered]@{ id='fp'; account=7404213; state='SolTradeFastMultiMarketV2'; home='C:\SolTrade\MT5-FP-DEMO' },
    [ordered]@{ id='f10'; account=7196820; state='SolTradeFastMultiMarketV2F10'; home='C:\SolTrade\MT5-FXIFY-10K' },
    [ordered]@{ id='f100'; account=7198096; state='SolTradeFastMultiMarketV2F100'; home='C:\SolTrade\MT5-FXIFY-100K' }
)

function Copy-OpenFile([string]$Source, [string]$Destination) {
    $sourceStream = [IO.FileStream]::new($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $destinationStream = [IO.FileStream]::new($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $sourceStream.CopyTo($destinationStream) } finally { $destinationStream.Dispose() }
    } finally { $sourceStream.Dispose() }
}

function Read-Runtime([string]$StateRoot) {
    $path = Join-Path $StateRoot 'runtime.csv'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -TotalCount 2)
    if ($lines.Count -ne 2) { return $null }
    $lines | ConvertFrom-Csv | Select-Object -First 1
}

$status = @()
foreach ($instance in $instances) {
    $stateRoot = Join-Path $common $instance.state
    foreach ($name in @('runtime.csv','evidence.csv',"lifecycle-$day.csv",'spread-audit.csv')) {
        $source = Join-Path $stateRoot $name
        if (Test-Path -LiteralPath $source) {
            Copy-OpenFile $source (Join-Path $bundle "$($instance.id)-$name")
        }
    }

    $scan = Join-Path $stateRoot "scan-history-v5-$day.csv"
    if (Test-Path -LiteralPath $scan) {
        $header = Get-Content -LiteralPath $scan -TotalCount 1
        $tail = @(Get-Content -LiteralPath $scan -Tail 3500)
        @($header) + @($tail | Where-Object { $_ -ne $header }) |
            Set-Content -Encoding UTF8 -LiteralPath (Join-Path $bundle "$($instance.id)-scan-tail.csv")
    }

    $log = Get-ChildItem -LiteralPath (Join-Path $instance.home 'MQL5\Logs') -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) { Copy-OpenFile $log.FullName (Join-Path $bundle "$($instance.id)-expert.log") }

    $terminal = Join-Path $instance.home 'terminal64.exe'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal })
    $leasePath = Join-Path $root "ownership\lease-$($instance.account).json"
    $lease = if (Test-Path -LiteralPath $leasePath) { Get-Content -Raw -LiteralPath $leasePath | ConvertFrom-Json } else { $null }
    if (Test-Path -LiteralPath $leasePath) { Copy-OpenFile $leasePath (Join-Path $bundle "$($instance.id)-lease.json") }
    $taskName = "SolTrade-AccountOwnership-$($instance.account)"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $taskInfo = if ($task) { Get-ScheduledTaskInfo -TaskName $taskName } else { $null }
    $status += [ordered]@{
        id=$instance.id
        account=$instance.account
        process_count=$processes.Count
        process_ids=@($processes | ForEach-Object { $_.ProcessId })
        runtime=Read-Runtime $stateRoot
        lease=$lease
        ownership_task_state=if ($task) { $task.State.ToString() } else { 'MISSING' }
        ownership_last_result=if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
    }
}

$watchdog = Get-ScheduledTask -TaskName 'SolTrade-Watchdog' -ErrorAction SilentlyContinue
$watchdogInfo = if ($watchdog) { Get-ScheduledTaskInfo -TaskName 'SolTrade-Watchdog' } else { $null }
[ordered]@{
    schema='SOLTRADE_POST_FIX_CROSS_ACCOUNT_AUDIT_BUNDLE_V1'
    captured_utc=[DateTime]::UtcNow.ToString('o')
    cutoff_utc=$cutoffUtc
    read_only=$true
    orders_placed=$false
    watchdog=[ordered]@{
        state=if ($watchdog) { $watchdog.State.ToString() } else { 'MISSING' }
        last_run=if ($watchdogInfo) { $watchdogInfo.LastRunTime.ToString('o') } else { $null }
        last_result=if ($watchdogInfo) { $watchdogInfo.LastTaskResult } else { $null }
    }
    instances=$status
} | ConvertTo-Json -Depth 14 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $bundle 'manifest.json')

$zip = "$bundle.zip"
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -CompressionLevel Optimal
Copy-Item -Force -LiteralPath $zip -Destination $destination
