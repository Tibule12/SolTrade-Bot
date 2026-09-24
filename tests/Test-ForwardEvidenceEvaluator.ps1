[CmdletBinding()]
param(
 [string]$EvaluatorPath=(Join-Path $PSScriptRoot '..\ops\forexvps\Run-V3-Forward-Evidence-Evaluator.ps1'),
 [string]$OutputPath='',
 [int]$ObservationCount=100000
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
# Load the real helper functions only. The scheduler/deployment entry point is never executed.
$source=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $EvaluatorPath))
$boundary=$source.IndexOf('if($SelfTest){Self-Test;exit 0}')
if($boundary -lt 0){throw 'Evaluator helper boundary missing'}
. ([scriptblock]::Create($source.Substring(0,$boundary)))
$checks=New-Object Collections.Generic.List[string]
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "FAILED: $Name"};$checks.Add($Name)}
function Near($Actual,[double]$Expected,[string]$Name){Check ([Math]::Abs([double]$Actual-$Expected)-lt 1e-10) $Name}
function Outcome([hashtable]$Updates=@{}){
 $h=@{outcome_status='TERMINAL';baseline_final_r_known='true';aftermath_complete='true';opportunity_id='one';candidate_id='FROZEN_V3_DIAGNOSTIC';symbol='EURUSD.r';session='LONDON';direction='LONG';entry_utc='1000';terminal_utc='20000';lifetime_seconds='19000';initial_risk='0.001';baseline_final_r='-1.02124703';causal_final_r='-0.41336189';mfe_r='0.1';mae_r='1.02124703';bank1_reached='false';terminal_reason='INITIAL_STRUCTURAL_STOP';causal_exit_triggered='true';causal_exit_utc='1100';causal_exit_r='-0.41336189';recovered_to_breakeven='false';reached_bank1_after_exit='false';reached_plus_2_after_exit='false';reached_plus_3_after_exit='false';reached_plus_5_after_exit='false';order_capability='false';completed_bars_only='true'}
 foreach($k in $Updates.Keys){$h[$k]=$Updates[$k]};[pscustomobject]$h
}
function Event([string]$Kind,[hashtable]$Updates=@{}){
 $h=@{opportunity_id='one';event=$Kind;utc_msc='1000000';candidate_id='';transition_score='-0.875';detail='expected_net_r=0.45;full_loss_probability=0.3;bank1_probability=0.6';direction='LONG';order_capability='false'}
 foreach($k in $Updates.Keys){$h[$k]=$Updates[$k]};[pscustomobject]$h
}
function Observation([hashtable]$Updates=@{}){
 $h=@{opportunity_id='one';observation_utc_msc='1100000';pressure_reversal='true';pullback_expanding='true';resumption_evidence='false';m1_state='-1';m5_state='1';transition_score='-0.875';order_capability='false';completed_bars_only='true';feature_window_ready='true'}
 foreach($k in $Updates.Keys){$h[$k]=$Updates[$k]};[pscustomobject]$h
}
$expected=[pscustomobject]@{sequence_id='REGRESSION_ONLY';model_id='ENTRY_ENGINE_V3_TRACKING_DIAGNOSTIC_20260918';quality_bands=@(@(0,0.5),@(0.5,0.55),@(0.55,0.60),@(0.60,0.65),@(0.65,0.70),@(0.70,0.80),@(0.80,1.01))}
$events=@((Event 'ENTRY_TRIGGERED'),(Event 'CAUSAL_INVALIDATION' @{utc_msc='1100000';candidate_id='FROZEN_V3_DIAGNOSTIC';detail='FROZEN_CANDIDATE'}))
$rows=@(Build-PerTrade -Outcomes @((Outcome)) -Events $events -Observations @((Observation)) -Expected $expected -Status 'CLEAN')
Check ($rows.Count-eq 1) 'one completed comparison'
Near $rows[0].r_saved_vs_baseline 0.60788514 'fractional saved R retained'
Near $rows[0].r_lost_vs_baseline_if_interrupted 0.0 'no loss fabricated on improvement'
$winner=Outcome @{baseline_final_r='3.12345678';causal_final_r='-0.41336189';mfe_r='5.25';bank1_reached='true';terminal_reason='RUNNER_STRUCTURAL_STOP';recovered_to_breakeven='true';reached_bank1_after_exit='true';reached_plus_2_after_exit='true';reached_plus_3_after_exit='true';reached_plus_5_after_exit='true'}
$winningRows=@(Build-PerTrade @($winner) $events @((Observation)) $expected 'CLEAN')
Near $winningRows[0].r_lost_vs_baseline_if_interrupted 3.53681867 'fractional interrupted winner cost retained'
Near $winningRows[0].r_saved_vs_baseline 0.0 'interrupted winner not counted as saving'
Check ($winningRows[0].recovered_to_breakeven-and $winningRows[0].reached_plus_1_after_exit-and $winningRows[0].reached_plus_2_after_exit-and $winningRows[0].reached_plus_3_after_exit-and $winningRows[0].reached_plus_5_after_exit) 'all post-invalidation recovery flags preserved'
Check ($winningRows[0].runner_stop_utc-eq 20000-and $winningRows[0].lifetime_seconds-eq 19000) 'runner terminal beyond four hours preserved'
Near (Median @(-3,-1,-2)) -2 'odd three value median'
Near (Median @(-7,-1,-4,-6,-2,-5,-3)) -4 'odd seven value median'
Near (Median @(-4,-1,-3,-2)) -2.5 'even median'
Check ($null-eq (Median @())) 'empty median remains unavailable'

# Shuffled duplicates must preserve the original earliest-entry/earliest-fire/latest-row semantics.
$duplicateEvents=@((Event 'ENTRY_TRIGGERED' @{utc_msc='1000500';detail='expected_net_r=9'}),$events[1],$events[0],(Event 'CAUSAL_INVALIDATION' @{utc_msc='1100500';candidate_id='FROZEN_V3_DIAGNOSTIC';transition_score='-0.5'}))
$duplicateObservations=@((Observation @{opportunity_id='different'}),(Observation @{observation_utc_msc='1100500';transition_score='-0.5'}),(Observation @{pressure_reversal='old'}),(Observation))
$older=Outcome @{terminal_utc='19000';baseline_final_r='-9'}
$matched=@(Build-PerTrade @((Outcome),$older) $duplicateEvents $duplicateObservations $expected 'CLEAN')
Check ($matched.Count-eq 1) 'duplicate terminal candidates collapse to latest result'
Near $matched[0].baseline_final_r -1.02124703 'latest terminal selected independent of input order'
Near $matched[0].entry_expected_net_r 0.45 'earliest entry event selected'
Near $matched[0].invalidation_transition_score -0.875 'earliest matching invalidation selected'
Check ($matched[0].causal_evidence_state-match 'pressure_reversal=true;') 'last exact opportunity and timestamp observation selected'
$fallback=@(Build-PerTrade @((Outcome)) $events @() $expected 'CLEAN')
Check ($fallback[0].causal_evidence_state-match 'event_detail=FROZEN_CANDIDATE;transition_score=-0.875') 'missing observation retains event evidence fallback'
$excluded=@((Outcome @{outcome_status='RIGHT_CENSORED';baseline_final_r_known='false';aftermath_complete='false';baseline_final_r=''}),(Outcome @{opportunity_id='unknown';baseline_final_r_known='false'}),(Outcome @{opportunity_id='unfinished';aftermath_complete='false'}))
$known=@(Build-PerTrade $excluded $events @() $expected 'CLEAN')
Check ($known.Count-eq 0) 'censored and incomplete outcomes excluded from known results'
$summary=Candidate-Summary -Rows $winningRows -CandidateId 'FROZEN_V3_DIAGNOSTIC' -SequenceId 'REGRESSION_ONLY' -Status 'CLEAN'
Check ($summary.interrupted_bank1_trades-eq 1-and $summary.interrupted_plus_5_trades-eq 1) 'summary reports interrupted recoveries and large winners'
Near $summary.total_r_saved_vs_baseline -3.53681867 'aggregate delta remains signed and fractional'

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('soltrade-evaluator-regression-'+[guid]::NewGuid().ToString('N'))
try{
 New-Item -ItemType Directory -Path (Join-Path $tempRoot '20260921'),(Join-Path $tempRoot '20260922') -Force|Out-Null
 @([pscustomobject]@{sequence=3;detail='later'})|Export-Csv -LiteralPath (Join-Path $tempRoot '20260922\b.csv') -NoTypeInformation
 @([pscustomobject]@{sequence=1;detail="quoted`nmultiline"},[pscustomobject]@{sequence=2;detail='earlier'})|Export-Csv -LiteralPath (Join-Path $tempRoot '20260921\a.csv') -NoTypeInformation
 $imported=@(Import-TreeCsv $tempRoot)
 Check ($imported.Count-eq 3-and $imported[0].sequence-eq '1'-and $imported[2].sequence-eq '3') 'streamed shard import preserves sorted file and row order'
 Check ($imported[0].detail-eq "quoted`nmultiline") 'streamed import retains quoted multiline fields'
 # Execute the runner's real input assignments against isolated shards. This
 # checks schema filtering, including case-insensitive property lookup, without
 # running the scheduler or reading production paths.
 $trackerData=Join-Path $tempRoot 'tracker-fixture'
 $ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
 foreach($fixture in @(@('outcomes','outcome_status'),@('events','event'),@('observations','observation_utc_msc'))){
  $variable=$fixture[0];$field=$fixture[1];$folder=if($variable-eq 'observations'){'lifetime_observations'}else{$variable}
  $dir=Join-Path $trackerData $folder;New-Item -ItemType Directory -Force -Path $dir|Out-Null
  @([pscustomobject]@{$field='valid'})|Export-Csv -LiteralPath (Join-Path $dir 'a.csv') -NoTypeInformation
  @([pscustomobject]@{$field.ToUpperInvariant()='case-insensitive'})|Export-Csv -LiteralPath (Join-Path $dir 'b.csv') -NoTypeInformation
  @([pscustomobject]@{unrelated='skip'})|Export-Csv -LiteralPath (Join-Path $dir 'c.csv') -NoTypeInformation
  $assignment=$ast.Find({param($node) $node-is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left-is [System.Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath-eq $variable},$true)
  Check ($null-ne $assignment) "$variable runner input assignment exists"
  $selected=@(& ([scriptblock]::Create($assignment.Right.Extent.Text)))
  Check ($selected.Count-eq 2-and $selected[0].$field-eq 'valid'-and $selected[1].$field-eq 'case-insensitive') "$variable actual loader preserves schema filtering"
 }
}finally{if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}}

# Representative workload, no production files: 250 completed trades, all four candidates,
# and 100,000 lifetime observations. Timing is measured, not an environment-dependent assertion.
$largeOutcomes=New-Object Collections.Generic.List[object]
$largeEvents=New-Object Collections.Generic.List[object]
$largeObservations=New-Object Collections.Generic.List[object]
for($i=0;$i-lt 250;$i++){
 $opp='perf-'+$i
 $largeEvents.Add((Event 'ENTRY_TRIGGERED' @{opportunity_id=$opp}))
 foreach($id in $CandidateIds){$largeOutcomes.Add((Outcome @{opportunity_id=$opp;candidate_id=$id}));$largeEvents.Add((Event 'CAUSAL_INVALIDATION' @{opportunity_id=$opp;candidate_id=$id;utc_msc='1100000'}))}
}
for($i=0;$i-lt $ObservationCount;$i++){$largeObservations.Add((Observation @{opportunity_id=('perf-'+($i%250));observation_utc_msc=[string](1100000+5000*[Math]::Floor($i/250))}))}
$watch=[Diagnostics.Stopwatch]::StartNew()
$largeRows=@(Build-PerTrade -Outcomes $largeOutcomes.ToArray() -Events $largeEvents.ToArray() -Observations $largeObservations.ToArray() -Expected $expected -Status 'CLEAN')
$watch.Stop()
Check ($largeRows.Count-eq 1000) 'large workload produces all 1000 candidate comparisons'
Check (@($largeRows|Where-Object{[Math]::Abs($_.r_saved_vs_baseline-0.60788514)-gt 1e-10}).Count-eq 0) 'large workload preserves fractional accounting'
Check (@($largeRows|Where-Object{$_.causal_evidence_state-notmatch 'pressure_reversal=true;'}).Count-eq 0) 'large workload retains exact invalidation observations'
$receipt=[ordered]@{schema='SOLTRADE_FORWARD_EVALUATOR_REGRESSION_V1';status='PASS';powershell_version=$PSVersionTable.PSVersion.ToString();source_sha256=(Get-FileHash -LiteralPath $EvaluatorPath -Algorithm SHA256).Hash.ToLowerInvariant();tests_passed=$checks.Count;checks=$checks.ToArray();benchmark=[ordered]@{observations=$ObservationCount;events=$largeEvents.Count;outcomes=$largeOutcomes.Count;comparisons=$largeRows.Count;build_per_trade_seconds=$watch.Elapsed.TotalSeconds};production_paths_read=$false;orders_sent=0;order_capability=$false}
$json=$receipt|ConvertTo-Json -Depth 8
if($OutputPath){[IO.File]::WriteAllText($OutputPath,$json,(New-Object Text.UTF8Encoding($false)))}
$json
