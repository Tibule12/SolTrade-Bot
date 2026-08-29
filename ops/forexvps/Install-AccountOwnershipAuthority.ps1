[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = 'C:\SolTrade'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ownershipRoot = Join-Path $root 'ownership'
$secretPath = Join-Path $ownershipRoot 'claim-secret-7404213.txt'
$servicePath = Join-Path $ownershipRoot 'Run-AccountOwnershipAuthority.ps1'
New-Item -ItemType Directory -Force -Path $ownershipRoot,(Join-Path $root 'MT5-FP-DEMO\MQL5\Files\SolTradeOwnership') | Out-Null

if (-not (Test-Path -LiteralPath $secretPath)) {
    $bytes = [byte[]]::new(48)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    [IO.File]::WriteAllText($secretPath,[Convert]::ToBase64String($bytes),[Text.UTF8Encoding]::new($false))
}
Copy-Item -Force (Join-Path $sourceRoot 'Run-AccountOwnershipAuthority.ps1') $servicePath

$secret = (Get-Content -Raw -LiteralPath $secretPath).Trim()
$presetPath = Join-Path $root 'MT5-FP-DEMO\MQL5\Presets\SolTradeFastMultiMarketV2-FPMarkets-demo.set'
$preset = Get-Content -LiteralPath $presetPath
$preset = $preset -replace '^OwnershipClaimSecret=.*$',("OwnershipClaimSecret=" + $secret)
[IO.File]::WriteAllLines($presetPath,$preset,[Text.UTF8Encoding]::new($false))

& icacls.exe $ownershipRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'trader:(OI)(CI)F' | Out-Null
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\SolTrade\ownership\Run-AccountOwnershipAuthority.ps1'
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213'

[ordered]@{
    schema='SOLTRADE_ACCOUNT_OWNERSHIP_INSTALL_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    account=7404213
    expected_instance_id='vps-fp-prod'
    expected_host=$env:COMPUTERNAME
    lease_ttl_seconds=15
    task_state=(Get-ScheduledTask -TaskName 'SolTrade-AccountOwnership-7404213').State.ToString()
    secret_persisted=$true
    secret_value_logged=$false
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $root 'logs\ownership-install.json')
