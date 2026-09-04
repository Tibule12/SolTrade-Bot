[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$share = Split-Path -Parent $MyInvocation.MyCommand.Path
$all = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | ForEach-Object {
    [ordered]@{
        process_id=$_.ProcessId
        session_id=$_.SessionId
        executable_path=$_.ExecutablePath
        command_line=$_.CommandLine
        creation_date=[string]$_.CreationDate
    }
})
[ordered]@{
    schema='SOLTRADE_TERMINAL_PROCESS_INSPECTION_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    count=$all.Count
    processes=$all
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $share 'remote-output\terminal-process-inspection.json')
