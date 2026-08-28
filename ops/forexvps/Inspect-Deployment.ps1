$ErrorActionPreference = 'SilentlyContinue'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$instances = @('MT5-FP-DEMO','MT5-FXIFY-10K','MT5-FXIFY-100K')
$detail = foreach ($name in $instances) {
    $instanceRoot = Join-Path $root $name
    $terminalPath = Join-Path $instanceRoot 'terminal64.exe'
    $expertPath = Join-Path $instanceRoot 'MQL5\Experts\SolTrade'
    $presetPath = Join-Path $instanceRoot 'MQL5\Presets'
    [ordered]@{
        name=$name
        instance_root=$instanceRoot
        instance_root_exists=[bool](Test-Path -LiteralPath $instanceRoot)
        terminal_path=$terminalPath
        terminal=[bool](Test-Path -LiteralPath $terminalPath)
        experts=@(Get-ChildItem -LiteralPath $expertPath -File -ErrorAction SilentlyContinue | Select-Object Name,Length)
        presets=@(Get-ChildItem -LiteralPath $presetPath -File -ErrorAction SilentlyContinue | Where-Object Name -Like '*SolTrade*' | Select-Object Name,Length)
    }
}
[ordered]@{
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    instances=$detail
    state_present=Test-Path (Join-Path $root 'state\instances.json')
    watchdog_present=Test-Path (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
    status_present=Test-Path (Join-Path $root 'status.ps1')
    task=Get-ScheduledTask -TaskName 'SolTrade-Watchdog' | Select-Object TaskName,State
    terminal_processes=@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Select-Object ProcessId,ExecutablePath,CommandLine)
    root_children=@(Get-ChildItem -LiteralPath $root -Force | Select-Object Name,FullName,PSIsContainer)
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\deployment-inspection.json')
