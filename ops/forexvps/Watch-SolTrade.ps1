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

$deferredFxifyAttach = @()
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
        $arguments = @('/portable', "/profile:$($instance.profile)", "/config:$startup")
        if ($instance.id -like 'fxify-*') {
            # Reuse the credential saved interactively inside this isolated MT5
            # data directory.  The account selector prevents MT5 from reopening
            # the login dialog without putting a password in automation files.
            # FXIFY restores the broker session asynchronously. Start the clean
            # profile first, then attach the EA only after the terminal has had
            # time to authenticate; otherwise OnInit correctly fails closed.
            $arguments = @('/portable', "/login:$($instance.account)", "/profile:$($instance.profile)")
            $deferredFxifyAttach += [ordered]@{ instance=$instance; terminal=$terminal; startup=$startup }
        }
        Start-Process -FilePath $terminal -ArgumentList $arguments -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } elseif ($process -and -not $runtimeFresh) {
        # A terminal window without a fresh EA heartbeat is not healthy. MT5 is
        # single-instance per portable directory, so this command attaches the
        # configured EA to the existing authenticated terminal without creating
        # a second account sender. The EA still needs its ownership permit.
        $arguments = @('/portable', "/login:$($instance.account)", "/profile:$($instance.profile)", "/config:$startup")
        Start-Process -FilePath $terminal -ArgumentList $arguments -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='EA_REATTACH_REQUESTED_RUNTIME_STALE'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } else {
        $events += [ordered]@{ id=$instance.id; action='HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

if ($deferredFxifyAttach.Count -gt 0) {
    Start-Sleep -Seconds 20
    foreach ($pending in $deferredFxifyAttach) {
        $instance = $pending.instance
        $arguments = @('/portable', "/login:$($instance.account)", "/profile:$($instance.profile)", "/config:$($pending.startup)")
        Start-Process -FilePath $pending.terminal -ArgumentList $arguments -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='EA_ATTACHED_AFTER_AUTH_DELAY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

$events | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $root 'logs\watchdog-last.json')
