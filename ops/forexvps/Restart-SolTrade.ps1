$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$paths = @($instances | ForEach-Object { Join-Path $_.home 'terminal64.exe' })
Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $paths -contains $_.ExecutablePath } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName 'SolTrade-Watchdog'
Start-Sleep -Seconds 15
$processes = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $paths -contains $_.ExecutablePath } |
    Select-Object ProcessId,ExecutablePath,CommandLine
[ordered]@{
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status=if (@($processes).Count -eq 3) { 'THREE_INSTANCES_RUNNING' } else { 'INSTANCE_COUNT_MISMATCH' }
    processes=@($processes)
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\restart-result.json')
