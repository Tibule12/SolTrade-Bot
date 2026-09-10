[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$share='\\tsclient\SolTrade'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\SolTradeFastMultiMarketV2'
$baselinePath='C:\SolTrade\state\fp-adaptive-payoff-v1-baseline.json'
$equityPath='C:\SolTrade\state\fp-adaptive-payoff-v1-equity.csv'
$output=Join-Path $share 'remote-output\fp-adaptive-payoff-v1-scoreboard.json'
function DetailValue($detail,$name){$m=[regex]::Match([string]$detail,"(?:^|;)$name=([^;]+)");if($m.Success){return $m.Groups[1].Value};return $null}
function NumberValue($detail,$name){$v=DetailValue $detail $name;if($null -eq $v){return $null};return [double]::Parse($v,[Globalization.CultureInfo]::InvariantCulture)}
function AverageOrNull($values){$a=@($values);if($a.Count -eq 0){return $null};return [Math]::Round(($a | Measure-Object -Average).Average,5)}
function RatioOrNull($numerator,$denominator){if($denominator -le 0){return $null};return [Math]::Round($numerator/$denominator,5)}
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
 $exits=@($events | Where-Object {$_.event -eq 'EXIT'} | Group-Object {DetailValue $_.detail 'position_id'} | ForEach-Object {$_.Group | Sort-Object utc | Select-Object -Last 1} | Sort-Object utc)
 $banks=@($events | Where-Object {$_.event -eq 'PARTIAL_BANK_2R'} | Group-Object {DetailValue $_.detail 'position_id'} | ForEach-Object {$_.Group | Sort-Object utc | Select-Object -Last 1})
 $exitReasons=@{};$net=0.0;$netR=0.0;$banked=0.0;$bankedR=0.0;$runnerCash=0.0;$runnerR=0.0
 $winnerR=@();$loserR=@();$mfeR=@();$maeR=@();$positiveR=0.0;$negativeR=0.0
 $wins=0;$losses=0;$reached1=0;$reached2=0;$reached3=0;$reached5=0;$winnerCash=0.0;$winnerPeak=0.0
 foreach($e in $exits){
  $reason=DetailValue $e.detail 'exit_class';if(-not $reason){$reason='UNKNOWN'};$exitReasons[$reason]=1+[int]$exitReasons[$reason]
  $cash=NumberValue $e.detail 'final_total_cash';$r=NumberValue $e.detail 'final_total_r';$risk=NumberValue $e.detail 'initial_dollar_risk'
  if($null -eq $cash){$cash=0};if($null -eq $r){$r=0};$net+=$cash;$netR+=$r
  if($cash -gt 0){$wins++;$winnerR+=,$r;$positiveR+=$r}elseif($cash -lt 0){$losses++;$loserR+=,$r;$negativeR+=$r}
  $mfe=NumberValue $e.detail 'mfe';$mae=NumberValue $e.detail 'mae'
  if($risk -gt 0 -and $null -ne $mfe){$mfeR+=,($mfe/$risk)};if($risk -gt 0 -and $null -ne $mae){$maeR+=,($mae/$risk)}
  $v=NumberValue $e.detail 'banked_cash';if($null -ne $v){$banked+=$v};$v=NumberValue $e.detail 'banked_r';if($null -ne $v){$bankedR+=$v}
  $v=NumberValue $e.detail 'runner_cash';if($null -ne $v){$runnerCash+=$v};$v=NumberValue $e.detail 'runner_r';if($null -ne $v){$runnerR+=$v}
  if((DetailValue $e.detail 'reached_1r') -eq 'true'){$reached1++};if((DetailValue $e.detail 'reached_2r') -eq 'true'){$reached2++}
  $peak=NumberValue $e.detail 'RUNNER_PEAK_R';if($peak -ge 3){$reached3++};if($peak -ge 5){$reached5++}
  if($cash -gt 0 -and $mfe -gt 0){$winnerCash+=$cash;$winnerPeak+=$mfe}
 }
 $states=@($events | Where-Object {$_.event -in @('PAYOFF_STATE_TRANSITION','HALF_RISK_DAMAGE_AREA_REACHED','ENTRY_PROBATION_FAILED','PRE_BANK_PROFIT_DERIORATION_EXIT','RUNNER_STRUCTURAL_EXIT','ENTRY_PROBATION_SHADOW_COMPLETE')})
 $probation=@($exits | Where-Object {(DetailValue $_.detail 'exit_class') -eq 'ENTRY_PROBATION_FAILED'})
 $shadows=@($events | Where-Object {$_.event -eq 'ENTRY_PROBATION_SHADOW_COMPLETE'})
 $recovered=@($shadows | Where-Object {(DetailValue $_.detail 'recovered_entry') -eq 'true'})
 $realizedPeak=[double]$baseline.equity;$realized=[double]$baseline.equity;$realizedDd=0.0
 foreach($e in $exits){$v=NumberValue $e.detail 'final_total_cash';if($null -ne $v){$realized+=$v};$realizedPeak=[Math]::Max($realizedPeak,$realized);$realizedDd=[Math]::Max($realizedDd,$realizedPeak-$realized)}
 if(-not (Test-Path -LiteralPath $equityPath)){
  'timestamp_utc,equity' | Set-Content -Encoding ASCII -LiteralPath $equityPath
  ('{0},{1}' -f $baseline.timestamp_utc,([double]$baseline.equity).ToString('F2',[Globalization.CultureInfo]::InvariantCulture)) | Add-Content -Encoding ASCII -LiteralPath $equityPath
 }
 ('{0},{1}' -f ([DateTime]::UtcNow.ToString('o')),([double]$runtime.equity).ToString('F2',[Globalization.CultureInfo]::InvariantCulture)) | Add-Content -Encoding ASCII -LiteralPath $equityPath
 $equityPeak=[double]$baseline.equity;$equityDd=0.0
 foreach($sample in @(Import-Csv -LiteralPath $equityPath)){$v=[double]$sample.equity;$equityPeak=[Math]::Max($equityPeak,$v);$equityDd=[Math]::Max($equityDd,$equityPeak-$v)}
 $report=[ordered]@{schema='FP_ADAPTIVE_PAYOFF_V1_SCOREBOARD';updated_utc=[DateTime]::UtcNow.ToString('o');baseline=$baseline;runtime=$runtime;
   configuration=[ordered]@{manager='ADAPTIVE_PAYOFF_V1';initial_risk_percent=1.00;aggregate_risk_cap_percent=1.50;bank_at_r=2.00;bank_original_volume_fraction=0.50;runner_management='COMPLETED_M5_M15_STRUCTURE_ONLY';monetary_peak_floor=$false};
   closed_positions=$exits.Count;wins=$wins;losses=$losses;net_cash=[Math]::Round($net,2);net_r=[Math]::Round($netR,5);cumulative_r=[Math]::Round($netR,5);
   average_winner_r=(AverageOrNull $winnerR);average_loser_r=(AverageOrNull $loserR);winner_loss_ratio=(RatioOrNull ((AverageOrNull $winnerR)) ([Math]::Abs((AverageOrNull $loserR))));profit_factor_r=(RatioOrNull $positiveR ([Math]::Abs($negativeR)));
   realized_balance_drawdown_cash=[Math]::Round($realizedDd,2);sampled_equity_drawdown_cash=[Math]::Round($equityDd,2);sampled_equity_drawdown_percent=[Math]::Round(100*$equityDd/[double]$baseline.equity,5);
   average_mae_r=(AverageOrNull $maeR);average_mfe_r=(AverageOrNull $mfeR);probation_exits=$probation.Count;probation_exits_with_completed_shadow=$shadows.Count;probation_exits_that_recovered=$recovered.Count;probation_exits_pending_shadow=[Math]::Max(0,$probation.Count-$shadows.Count);
   full_structural_losses=[int]$exitReasons['INITIAL_STRUCTURAL_STOP_EXIT'];pre_bank_deterioration_exits=[int]$exitReasons['PRE_BANK_PROFIT_DERIORATION_EXIT'];trades_reaching_1r=$reached1;trades_reaching_2r=$reached2;trades_reaching_3r=$reached3;trades_reaching_5r=$reached5;
   partial_banking_count=$banks.Count;banked_cash=[Math]::Round($banked,2);banked_r=[Math]::Round($bankedR,5);runner_cash=[Math]::Round($runnerCash,2);runner_r=[Math]::Round($runnerR,5);total_winner_peak_capture_ratio=(RatioOrNull $winnerCash $winnerPeak);
   exit_reasons=$exitReasons;state_and_diagnostic_events=$states.Count;recent_events=@($events | Select-Object -Last 200);
   evidence_is_live_broker_record=$true;orders_sent_by_reporter=$false}
 $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath ($output+'.tmp')
 Move-Item -Force -LiteralPath ($output+'.tmp') -Destination $output
} catch {
 @{schema='FP_ADAPTIVE_PAYOFF_V1_SCOREBOARD';updated_utc=[DateTime]::UtcNow.ToString('o');status='ERROR';error=$_.Exception.Message;orders_sent_by_reporter=$false} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $output
 exit 1
}
