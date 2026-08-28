$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$status = foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $expert = Join-Path $instance.home "MQL5\Experts\SolTrade\$($instance.expert).ex5"
    [ordered]@{
        id=$instance.id
        account=$instance.account
        server=$instance.server
        version=$instance.version
        order_permission=$instance.order_permission
        process_running=[bool]$process
        pid=if ($process) { $process.ProcessId } else { $null }
        terminal_present=Test-Path $terminal
        expert_present=Test-Path $expert
        expert_sha256=if (Test-Path $expert) { (Get-FileHash -Algorithm SHA256 $expert).Hash.ToLowerInvariant() } else { $null }
    }
}
$document = [ordered]@{
    schema='SOLTRADE_FOREXVPS_STATUS_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    host=$env:COMPUTERNAME
    instances=$status
}
$document | ConvertTo-Json -Depth 6
$document | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $root 'state\status-last.json')
