$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$common = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$events = @()
$stateDirectories = @{
    'fp-demo'='SolTradeFastMultiMarketV2'
    'fxify-10k'='SolTradeFastMultiMarketV2F10'
    'fxify-100k'='SolTradeFastMultiMarketV2F100'
}

foreach ($account in @(7404213,7196820,7198096)) {
    $taskName = "SolTrade-AccountOwnership-$account"
    $ownershipTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $ownershipTask) {
        throw "Account ownership authority $taskName is not installed; watchdog fails closed."
    }
    if ($ownershipTask.State -ne 'Running') {
        Start-ScheduledTask -TaskName $taskName
        $events += [ordered]@{ id="ownership-$account"; action='AUTHORITY_STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } else {
        $events += [ordered]@{ id="ownership-$account"; action='AUTHORITY_HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $escaped = $terminal.Replace('\','\\')
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $startup = Join-Path $root "state\$($instance.id).ini"
    $runtime = Join-Path (Join-Path $common $stateDirectories[$instance.id]) 'runtime.csv'
    $runtimeFresh = (Test-Path -LiteralPath $runtime) -and
        (([DateTime]::UtcNow - (Get-Item -LiteralPath $runtime).LastWriteTimeUtc).TotalSeconds -le 45)
    if (-not $process -and (Test-Path $terminal)) {
        # Launch one fully configured process. Starting a second copy later to
        # "reattach" the EA is unsafe across Windows sessions because MT5's
        # portable single-instance guard is session-local, not machine-global.
        $arguments = @('/portable', "/login:$($instance.account)", "/profile:$($instance.profile)", "/config:$startup")
        Start-Process -FilePath $terminal -ArgumentList $arguments -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } elseif ($process -and -not $runtimeFresh) {
        # Never launch a second process against the same portable directory.
        # Cross-session MT5 duplicates contend for history/config files and can
        # each believe they are the directory's primary process. Ownership still
        # fails closed, but resource usage and scanner health are damaged. Leave
        # the existing process untouched and make the stale condition auditable.
        $events += [ordered]@{ id=$instance.id; action='RUNTIME_STALE_EXISTING_PROCESS_FAIL_CLOSED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } else {
        $events += [ordered]@{ id=$instance.id; action='HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

$events | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $root 'logs\watchdog-last.json')
