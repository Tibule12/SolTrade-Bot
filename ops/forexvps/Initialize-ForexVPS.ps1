[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$shareRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = 'C:\SolTrade'
$output = Join-Path $shareRoot 'remote-output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$transcript = Join-Path $output 'initialize-transcript.txt'
Start-Transcript -Path $transcript -Force | Out-Null

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) { throw "SHA256 mismatch for $Path" }
}

function Install-MetaTrader([string]$Installer, [string]$Destination) {
    if (Test-Path (Join-Path $Destination 'terminal64.exe')) { return }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $process = Start-Process -FilePath $Installer -ArgumentList @('/auto', "/path:$Destination") -PassThru
    if (-not $process.WaitForExit(600000)) {
        $process.Kill()
        throw "Installer timed out for $Destination"
    }
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Path (Join-Path $Destination 'terminal64.exe')) { return }
        Start-Sleep -Seconds 2
    }
    throw "terminal64.exe was not installed in $Destination"
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator rights are required.'
    }

    @('repo','deploy','logs','state','watchdogs','backups','installers',
      'MT5-FP-DEMO','MT5-FXIFY-10K','MT5-FXIFY-100K') | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $_) | Out-Null
    }

    $fpInstaller = Join-Path $root 'installers\fpmarketssc5setup.exe'
    $fxInstaller = Join-Path $root 'installers\fxify5setup.exe'
    Copy-Item -Force (Join-Path $shareRoot 'installers\fpmarketssc5setup.exe') $fpInstaller
    Copy-Item -Force (Join-Path $shareRoot 'installers\fxify5setup.exe') $fxInstaller
    Assert-Sha256 $fpInstaller '993b992a5393f2e607d25ff1736ac2c321ac23249f37e9fef0ef44f463bd60cf'
    Assert-Sha256 $fxInstaller 'a57ed88089ba8fd955eb44ba07ddbe3d1811050e75b01437f1fbb1c3d8a1d473'

    Install-MetaTrader $fpInstaller (Join-Path $root 'MT5-FP-DEMO')
    Install-MetaTrader $fxInstaller (Join-Path $root 'MT5-FXIFY-10K')
    Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force
    if (-not (Test-Path (Join-Path $root 'MT5-FXIFY-100K\terminal64.exe'))) {
        Copy-Item -Path (Join-Path $root 'MT5-FXIFY-10K\*') -Destination (Join-Path $root 'MT5-FXIFY-100K') -Recurse -Force
    }

    $result = [ordered]@{
        schema = 'SOLTRADE_FOREXVPS_INITIALIZE_V1'
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        root = $root
        fp_terminal = Test-Path (Join-Path $root 'MT5-FP-DEMO\terminal64.exe')
        fxify_10k_terminal = Test-Path (Join-Path $root 'MT5-FXIFY-10K\terminal64.exe')
        fxify_100k_terminal = Test-Path (Join-Path $root 'MT5-FXIFY-100K\terminal64.exe')
        status = 'BASE_INSTALLED'
    }
    $result | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $output 'initialize-result.json')
} catch {
    [ordered]@{
        schema = 'SOLTRADE_FOREXVPS_INITIALIZE_V1'
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        status = 'FAILED'
        error = $_.Exception.Message
    } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $output 'initialize-result.json')
    throw
} finally {
    Stop-Transcript | Out-Null
}
