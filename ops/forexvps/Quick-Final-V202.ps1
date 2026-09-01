$ErrorActionPreference='Stop'
$share=Split-Path -Parent $MyInvocation.MyCommand.Path
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$items=@(
 @{id='fp';state='SolTradeFastMultiMarketV2'},
 @{id='f10';state='SolTradeFastMultiMarketV2F10'},
 @{id='f100';state='SolTradeFastMultiMarketV2F100'}
)
$rows=@()
foreach($item in $items){
 $path=Join-Path (Join-Path $common $item.state) 'runtime.csv'
 $lines=@(Get-Content -LiteralPath $path -TotalCount 2)
 $runtime=if($lines.Count -eq 2){$lines|ConvertFrom-Csv|Select-Object -First 1}else{$null}
 $rows += [ordered]@{id=$item.id;last_write_utc=(Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString('o');runtime=$runtime}
}
$watchdog=Get-ScheduledTask -TaskName 'SolTrade-Watchdog'
[ordered]@{
 schema='SOLTRADE_V202_SCRATCH_RETIREMENT_FINAL_STATUS_V1'
 captured_utc=[DateTime]::UtcNow.ToString('o')
 terminal_process_count=@(Get-Process terminal64 -ErrorAction SilentlyContinue).Count
 watchdog_state=$watchdog.State.ToString()
 instances=$rows
}|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $share 'remote-output\scratch-retired-v202-final-status.json')
