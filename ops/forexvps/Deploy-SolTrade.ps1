[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$output = Join-Path $shareRoot 'remote-output'

$instances = @(
    [ordered]@{
        id='fp-demo'; account=7404213; server='FPMarketsSC-Demo'; version='2.202';
        home='C:\SolTrade\MT5-FP-DEMO'; expert='SolTradeFastMultiMarketV2';
        source='payload\fp-demo\SolTradeFastMultiMarketV2.mq5';
        binary='payload\fp-demo\SolTradeFastMultiMarketV2.ex5';
        preset='payload\fp-demo\SolTradeFastMultiMarketV2-FPMarkets-demo.set';
        startup='runtime\fp-demo.ini'; magic=2108202601; order_permission='ENABLED_AFTER_ACCOUNT_VERIFICATION'
    },
    [ordered]@{
        id='fxify-10k'; account=7196820; server='FXIFY-Server'; version='2.201';
        home='C:\SolTrade\MT5-FXIFY-10K'; expert='SolTradeFastMultiMarketV201F10';
        source='payload\fxify-10k\SolTradeFastMultiMarketV201F10.mq5';
        binary='payload\fxify-10k\SolTradeFastMultiMarketV201F10.ex5';
        preset='payload\fxify-10k\SolTradeFastMultiMarketV201F10-ORDER-DISABLED.set';
        startup='runtime\fxify-10k.ini'; magic=2108202610; order_permission='DISABLED_DRY_RUN'
    },
    [ordered]@{
        id='fxify-100k'; account=7198096; server='FXIFY-Server'; version='2.201';
        home='C:\SolTrade\MT5-FXIFY-100K'; expert='SolTradeFastMultiMarketV201F100';
        source='payload\fxify-100k\SolTradeFastMultiMarketV201F100.mq5';
        binary='payload\fxify-100k\SolTradeFastMultiMarketV201F100.ex5';
        preset='payload\fxify-100k\SolTradeFastMultiMarketV201F100-ORDER-DISABLED.set';
        startup='runtime\fxify-100k.ini'; magic=2108202620; order_permission='DISABLED_DRY_RUN'
    }
)

foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    if (-not (Test-Path $terminal)) { throw "Missing terminal for $($instance.id): $terminal" }
    $expertDir = Join-Path $instance.home 'MQL5\Experts\SolTrade'
    $presetDir = Join-Path $instance.home 'MQL5\Presets'
    New-Item -ItemType Directory -Force -Path $expertDir,$presetDir | Out-Null
    Copy-Item -Force (Join-Path $shareRoot $instance.source) (Join-Path $expertDir "$($instance.expert).mq5")
    Copy-Item -Force (Join-Path $shareRoot $instance.binary) (Join-Path $expertDir "$($instance.expert).ex5")
    Copy-Item -Force (Join-Path $shareRoot $instance.preset) (Join-Path $presetDir (Split-Path $instance.preset -Leaf))
    Copy-Item -Force (Join-Path $shareRoot $instance.startup) (Join-Path $root "state\$($instance.id).ini")
    New-Item -ItemType File -Force -Path (Join-Path $instance.home 'portable.txt') | Out-Null
}

$instances | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $root 'state\instances.json')
Copy-Item -Force (Join-Path $shareRoot 'Watch-SolTrade.ps1') (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
Copy-Item -Force (Join-Path $shareRoot 'status.ps1') (Join-Path $root 'status.ps1')
Copy-Item -Force (Join-Path $shareRoot 'Run-AccountOwnershipAuthority.ps1') (Join-Path $root 'ownership\Run-AccountOwnershipAuthority.ps1')

$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\SolTrade\watchdogs\Watch-SolTrade.ps1'
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerMinute = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Highest
Register-ScheduledTask -TaskName 'SolTrade-Watchdog' -Action $action -Trigger @($triggerStartup,$triggerMinute) -Principal $principal -Force | Out-Null

& (Join-Path $shareRoot 'Install-AccountOwnershipAuthority.ps1')

[ordered]@{
    schema='SOLTRADE_FOREXVPS_DEPLOY_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    status='ARTIFACTS_DEPLOYED'
    instances=$instances
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $output 'deploy-result.json')

    & (Join-Path $root 'watchdogs\Watch-SolTrade.ps1')
