$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$names=@('Capture-Full-ReadOnly-Audit-20260930.ps1','Capture-Ownership-State-ReadOnly-20260930.ps1')
$stopped=@()
foreach($p in (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")){
 $cmd=[string]$p.CommandLine
 if($names|Where-Object{$cmd.Contains($_)}){
  $stopped+=@{pid=$p.ProcessId;matched=@($names|Where-Object{$cmd.Contains($_)})}
  Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
 }
}
[ordered]@{utc=[DateTime]::UtcNow.ToString('o');stopped=$stopped;scope='OWN_READ_ONLY_CAPTURE_PROCESSES_ONLY';production_changed=$false;orders_sent=0}|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $out 'own-capture-stop-receipt.json')
