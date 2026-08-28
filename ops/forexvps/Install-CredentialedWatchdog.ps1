$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$securePassword = Read-Host 'VPS account password (stored encrypted by Task Scheduler)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $identity = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\SolTrade\watchdogs\Watch-SolTrade.ps1'
    $startup = New-ScheduledTaskTrigger -AtStartup
    $recurring = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName 'SolTrade-Watchdog' -Action $action -Trigger @($startup,$recurring) -User $identity -Password $plainPassword -RunLevel Highest -Force | Out-Null
    [ordered]@{
        timestamp_utc=[DateTime]::UtcNow.ToString('o')
        task='SolTrade-Watchdog'
        run_as=$identity
        logon_mode='PASSWORD_STORED_ENCRYPTED_BY_TASK_SCHEDULER'
        status='REGISTERED'
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\watchdog-registration.json')
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $plainPassword = $null
    $securePassword.Dispose()
}
