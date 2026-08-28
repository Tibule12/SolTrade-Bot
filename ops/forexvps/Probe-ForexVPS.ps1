$ErrorActionPreference = 'Stop'

$outputRoot = '\\tsclient\SolTrade\remote-output'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$defender = $null
try {
    $defender = Get-MpComputerStatus
} catch {
    $defender = [pscustomobject]@{ AntivirusEnabled = $null; RealTimeProtectionEnabled = $null }
}

$probe = [ordered]@{
    schema = 'SOLTRADE_FOREXVPS_PROBE_V1'
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    computer_name = $env:COMPUTERNAME
    os_caption = $os.Caption
    os_version = $os.Version
    os_build = $os.BuildNumber
    last_boot_utc = $os.LastBootUpTime.ToUniversalTime().ToString('o')
    cpu_name = $cpu.Name
    logical_processors = $computer.NumberOfLogicalProcessors
    ram_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
    disk_c_total_gb = [math]::Round($disk.Size / 1GB, 2)
    disk_c_free_gb = [math]::Round($disk.FreeSpace / 1GB, 2)
    timezone = (Get-TimeZone).Id
    utc_now = (Get-Date).ToUniversalTime().ToString('o')
    defender_enabled = $defender.AntivirusEnabled
    defender_realtime = $defender.RealTimeProtectionEnabled
    firewall_profiles = @(Get-NetFirewallProfile | Select-Object Name, Enabled)
    powershell_version = $PSVersionTable.PSVersion.ToString()
    rdp_session = $env:SESSIONNAME
    user = $env:USERNAME
}

$temporary = Join-Path $outputRoot 'vps-probe.json.tmp'
$final = Join-Path $outputRoot 'vps-probe.json'
$probe | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
Move-Item -Force -LiteralPath $temporary -Destination $final
