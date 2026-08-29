$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$events = @()

$ownershipTask = Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -ErrorAction SilentlyContinue
if (-not $ownershipTask) {
    throw 'Account ownership authority is not installed; watchdog fails closed before starting FP runtime.'
}
if ($ownershipTask.State -ne 'Running') {
    Start-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213'
    $events += [ordered]@{ id='ownership-7404213'; action='AUTHORITY_STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
} else {
    $events += [ordered]@{ id='ownership-7404213'; action='AUTHORITY_HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
}

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $escaped = $terminal.Replace('\','\\')
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    if (-not $process -and (Test-Path $terminal)) {
        $startup = Join-Path $root "state\$($instance.id).ini"
        $arguments = @('/portable', "/config:$startup")
        if ($instance.id -like 'fxify-*') {
            # Reuse the credential saved interactively inside this isolated MT5
            # data directory.  The account selector prevents MT5 from reopening
            # the login dialog without putting a password in automation files.
            $arguments = @('/portable', "/login:$($instance.account)", "/config:$startup")
        }
        Start-Process -FilePath $terminal -ArgumentList $arguments -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } else {
        $events += [ordered]@{ id=$instance.id; action='HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

$events | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $root 'logs\watchdog-last.json')
