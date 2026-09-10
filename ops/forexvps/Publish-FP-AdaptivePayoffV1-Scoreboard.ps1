[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$share='\\tsclient\SolTrade'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\SolTradeFastMultiMarketV2'
$baselinePath='C:\SolTrade\state\fp-adaptive-payoff-v1-baseline.json'
$output=Join-Path $share 'remote-output\fp-adaptive-payoff-v1-scoreboard.json'
function DetailValue($detail,$name){$m=[regex]::Match([string]$detail,"(?:^|;)$name=([^;]+)");if($m.Success){return $m.Groups[1].Value};return $null}
try {
 $baseline=Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json
 $runtime=Get-Content -LiteralPath (Join-Path $common 'runtime.csv') -TotalCount 2 | ConvertFrom-Csv | Select-Object -First 1
 if($runtime.login -ne '7404213' -or $runtime.server -ne 'FPMarketsSC-Demo' -or $runtime.manager_version -ne 'ADAPTIVE_PAYOFF_V1'){throw 'FP adaptive runtime identity mismatch'}
 $start=[DateTime]::Parse([string]$baseline.timestamp_utc).ToUniversalTime()
 $events=@()
 $evidence=Join-Path $common 'evidence.csv'
 if(Test-Path $evidence){
  $events=@(Import-Csv -LiteralPath $evidence | Where-Object {
    try{([DateTime]::ParseExact($_.utc,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal)).ToUniversalTime() -ge $start}catch{$false}
  })
 }
 $exits=@($events | Where-Object {$_.event -eq 'EXIT'})
 $banks=@($events | Where-Object {$_.event -eq 'PARTIAL_BANK_2R'})
 $exitReasons=@{};$net=0.0;$netR=0.0;$banked=0.0
 foreach($e in $exits){$reason=DetailValue $e.detail 'exit_class';if(-not $reason){$reason='UNKNOWN'};$exitReasons[$reason]=1+[int]$exitReasons[$reason];$v=DetailValue $e.detail 'final_total_cash';if($v){$net+=[double]$v};$v=DetailValue $e.detail 'final_total_r';if($v){$netR+=[double]$v};$v=DetailValue $e.detail 'banked_cash';if($v){$banked+=[double]$v}}
 $states=@($events | Where-Object {$_.event -in @('PAYOFF_STATE_TRANSITION','HALF_RISK_DAMAGE_AREA_REACHED','ENTRY_PROBATION_FAILED','PRE_BANK_PROFIT_DERIORATION_EXIT','RUNNER_STRUCTURAL_EXIT','ENTRY_PROBATION_SHADOW_COMPLETE')})
 $report=[ordered]@{schema='FP_ADAPTIVE_PAYOFF_V1_SCOREBOARD';updated_utc=[DateTime]::UtcNow.ToString('o');baseline=$baseline;runtime=$runtime;
   closed_positions=$exits.Count;net_cash=[Math]::Round($net,2);net_r=[Math]::Round($netR,5);bank_events=$banks.Count;banked_cash=[Math]::Round($banked,2);
   exit_reasons=$exitReasons;state_and_diagnostic_events=$states.Count;recent_events=@($events | Select-Object -Last 200);
   evidence_is_live_broker_record=$true;orders_sent_by_reporter=$false}
 $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath ($output+'.tmp')
 Move-Item -Force -LiteralPath ($output+'.tmp') -Destination $output
} catch {
 @{schema='FP_ADAPTIVE_PAYOFF_V1_SCOREBOARD';updated_utc=[DateTime]::UtcNow.ToString('o');status='ERROR';error=$_.Exception.Message;orders_sent_by_reporter=$false} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $output
 exit 1
}
