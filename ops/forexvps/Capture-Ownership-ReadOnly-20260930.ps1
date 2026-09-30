$ErrorActionPreference='Continue'
$out=Join-Path $PSScriptRoot 'remote-output\full-readonly-audit-20260930'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$root='C:\SolTrade'
$start=[DateTime]::UtcNow.ToString('o')
Get-ChildItem "$common\SolTradeFastMultiMarketV2" -File -Filter 'lifecycle-202609*.csv' | Where-Object {$_.Name -ge 'lifecycle-20260924.csv'} | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $out $_.Name) }
$tasks=@(Get-ScheduledTask | Where-Object {$_.TaskName -like '*SolTrade*'} | ForEach-Object {
 $t=$_;$i=Get-ScheduledTaskInfo -InputObject $t
 [ordered]@{name=$t.TaskName;state=[string]$t.State;last_result=$i.LastTaskResult;last_run=[string]$i.LastRunTime;next_run=[string]$i.NextRunTime;priority=$t.Settings.Priority;execution_time_limit=$t.Settings.ExecutionTimeLimit;multiple_instances=[string]$t.Settings.MultipleInstances;actions=@($t.Actions|Select-Object Execute,Arguments,WorkingDirectory)}
})
$tasks|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $out 'all-soltrade-tasks.json')
foreach($dir in @("$root\state","$root\logs","$common\SolTradeFastMultiMarketV2")){
 Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -match 'ownership|lease|permit'} | Select-Object FullName,Length,LastWriteTimeUtc | Export-Csv -Append -NoTypeInformation -Encoding UTF8 (Join-Path $out 'ownership-file-inventory.csv')
}
Get-Process terminal64 -ErrorAction SilentlyContinue|Select-Object Id,StartTime,CPU,WorkingSet64,MainWindowHandle,MainWindowTitle|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'terminal-windows.json')
Get-Process|Sort-Object CPU -Descending|Select-Object -First 20 Id,ProcessName,CPU,StartTime,WorkingSet64|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'resource-processes.json')
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational';StartTime=(Get-Date).AddDays(-1)} -MaxEvents 300 -ErrorAction SilentlyContinue|Where-Object {$_.Message -match 'SolTrade'}|Select-Object TimeCreated,Id,LevelDisplayName,Message|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $out 'scheduler-events.json')
[ordered]@{started_utc=$start;completed_utc=[DateTime]::UtcNow.ToString('o');read_only=$true;orders_sent=0}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $out 'ownership-capture-receipt.json')
