$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$terminalRoot = 'C:\SolTrade\MT5-FP-DEMO'
$terminal = Join-Path $terminalRoot 'terminal64.exe'
$source = Join-Path $shareRoot 'secret-transfer\fp-config'
$config = Join-Path $terminalRoot 'Config'
$backup = 'C:\SolTrade\backups\FP-DEMO-config-before-session-transfer'

Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $_.ExecutablePath -eq $terminal } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path $config,$backup | Out-Null
@('accounts.dat','servers.dat','common.ini','terminal.ini') | ForEach-Object {
    Copy-Item -Force -ErrorAction SilentlyContinue (Join-Path $config $_) $backup
    Copy-Item -Force (Join-Path $source $_) $config
}
Start-Process -FilePath $terminal -ArgumentList '/portable' -WorkingDirectory $terminalRoot
[ordered]@{
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status='TRANSFERRED_AND_STARTED'
    account_file_sha256=(Get-FileHash -Algorithm SHA256 (Join-Path $config 'accounts.dat')).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\fp-session-transfer.json')
