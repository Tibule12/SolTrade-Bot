param([Parameter(Mandatory=$true)][ValidateSet('fp-demo','fxify-10k','fxify-100k')][string]$Id)
$paths = @{
    'fp-demo'='C:\SolTrade\MT5-FP-DEMO\terminal64.exe'
    'fxify-10k'='C:\SolTrade\MT5-FXIFY-10K\terminal64.exe'
    'fxify-100k'='C:\SolTrade\MT5-FXIFY-100K\terminal64.exe'
}
$target = $paths[$Id]
$processInfo = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
    Where-Object { $_.ExecutablePath -eq $target } | Select-Object -First 1
if (-not $processInfo) { throw "Instance is not running: $Id" }
$process = Get-Process -Id $processInfo.ProcessId
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SolTradeWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@
[SolTradeWindow]::ShowWindowAsync($process.MainWindowHandle, 9) | Out-Null
[SolTradeWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
