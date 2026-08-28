$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    & (Join-Path $shareRoot 'Transfer-FP-Session.ps1')
} catch {
    [ordered]@{
        timestamp_utc=[DateTime]::UtcNow.ToString('o')
        status='FAILED'
        error=$_.Exception.Message
        line=$_.InvocationInfo.ScriptLineNumber
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\fp-session-transfer-error.json')
}
