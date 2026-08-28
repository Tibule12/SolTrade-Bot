$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$events = @()

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $escaped = $terminal.Replace('\','\\')
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    if (-not $process -and (Test-Path $terminal)) {
        $startup = Join-Path $root "state\$($instance.id).ini"
        Start-Process -FilePath $terminal -ArgumentList @('/portable', "/config:$startup") -WorkingDirectory $instance.home
        $events += [ordered]@{ id=$instance.id; action='STARTED'; at_utc=[DateTime]::UtcNow.ToString('o') }
    } else {
        $events += [ordered]@{ id=$instance.id; action='HEALTHY'; at_utc=[DateTime]::UtcNow.ToString('o') }
    }
}

$events | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $root 'logs\watchdog-last.json')
