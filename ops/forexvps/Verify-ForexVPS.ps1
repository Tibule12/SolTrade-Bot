$ErrorActionPreference = 'Stop'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$instances = Get-Content -Raw (Join-Path $root 'state\instances.json') | ConvertFrom-Json
$expected = @{
    'fp-demo'='ea21afe11bdff4b16de6d3fe09b62d251fd11ea868b4d5a979a5b6b0ef4a222b'
    'fxify-10k'='ed686d27edd652dcba604599d5365bb8758cc9dbf56a9b85659cbaec6e628b55'
    'fxify-100k'='8e1773adcda33e47af238d94c204a18bf1ee9783f1f4b09f8d628483efaa70eb'
}

$checks = foreach ($instance in $instances) {
    $terminal = Join-Path $instance.home 'terminal64.exe'
    $expert = Join-Path $instance.home "MQL5\Experts\SolTrade\$($instance.expert).ex5"
    $presetName = Split-Path $instance.preset -Leaf
    $preset = Join-Path $instance.home "MQL5\Presets\$presetName"
    $startup = Join-Path $root "state\$($instance.id).ini"
    $process = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
        Where-Object { $_.ExecutablePath -eq $terminal } | Select-Object -First 1
    $presetText = if (Test-Path $preset) { Get-Content -Raw $preset } else { '' }
    [ordered]@{
        id=$instance.id
        terminal_root=$instance.home
        terminal_present=[bool](Test-Path $terminal)
        process_running=[bool]$process
        process_id=if ($process) { $process.ProcessId } else { $null }
        command_line=if ($process) { $process.CommandLine } else { $null }
        expert_present=[bool](Test-Path $expert)
        expert_sha256=if (Test-Path $expert) { (Get-FileHash -Algorithm SHA256 $expert).Hash.ToLowerInvariant() } else { $null }
        expert_hash_matches=if (Test-Path $expert) { (Get-FileHash -Algorithm SHA256 $expert).Hash.ToLowerInvariant() -eq $expected[$instance.id] } else { $false }
        preset_present=[bool](Test-Path $preset)
        startup_present=[bool](Test-Path $startup)
        magic=[long]$instance.magic
        order_permission=$instance.order_permission
        dry_run=if ($instance.id -like 'fxify-*') { $presetText -match '(?m)^DryRunOnly=true$' } else { $presetText -match '(?m)^DryRunOnly=false$' }
        min_reward_1_20=if ($instance.id -like 'fxify-*') { $presetText -match '(?m)^MinRewardRisk=1.20$' } else { $null }
        min_reward_1_15=if ($instance.id -eq 'fp-demo') { $presetText -match '(?m)^MinRewardRisk=1.15$' } else { $null }
    }
}

$task = Get-ScheduledTask -TaskName 'SolTrade-Watchdog'
$document = [ordered]@{
    schema='SOLTRADE_FOREXVPS_VERIFICATION_V1'
    timestamp_utc=[DateTime]::UtcNow.ToString('o')
    host=$env:COMPUTERNAME
    os=(Get-CimInstance Win32_OperatingSystem).Caption
    isolated_terminal_roots=(@($instances.home | Select-Object -Unique).Count -eq 3)
    isolated_magics=(@($instances.magic | Select-Object -Unique).Count -eq 3)
    checks=$checks
    watchdog=[ordered]@{
        task_name=$task.TaskName
        state=[string]$task.State
        user_id=$task.Principal.UserId
        logon_type=[string]$task.Principal.LogonType
        run_level=[string]$task.Principal.RunLevel
        trigger_count=@($task.Triggers).Count
    }
    paid_order_paths_enabled=$false
    account_connectivity=[ordered]@{
        fp_demo='BLOCKED_PASSWORD_NOT_AVAILABLE_EMAIL_IS_MASKED'
        fxify_10k='BROKER_REJECTED_INVALID_ACCOUNT'
        fxify_100k='BROKER_REJECTED_INVALID_ACCOUNT'
    }
}
$document | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $shareRoot 'remote-output\verification.json')
