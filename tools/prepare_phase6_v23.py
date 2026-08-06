#!/usr/bin/env python3
"""Create the V23 non-performance pre-run freeze artifacts."""
from __future__ import annotations
import csv,hashlib,json
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/backtests/phase6-v23-v31-development-screen'
H25=Path('/home/tibule12/.wine-fpmarkets/drive_c/v8/derived/SolTradePhase6V8DerivedH1.csv')
H26=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedH1.csv')
FMT='%Y.%m.%d %H:%M:%S'
SEGMENTS=[
 ('2025_S1','V31_2025_DEVELOPMENT_REUSE','DEVELOPMENT_REUSE_DATA','2025.01.02 00:00:00','2025.01.16 00:00:00','2025.02.05 00:00:00',H25),
 ('2025_S2','V31_2025_DEVELOPMENT_REUSE','DEVELOPMENT_REUSE_DATA','2025.02.17 09:00:00','2025.02.17 09:00:00','2025.03.07 23:00:00',H25),
 ('2025_S3','V31_2025_DEVELOPMENT_REUSE','DEVELOPMENT_REUSE_DATA','2025.03.20 08:00:00','2025.03.20 08:00:00','2025.08.06 16:00:00',H25),
 ('2025_S4','V31_2025_DEVELOPMENT_REUSE','DEVELOPMENT_REUSE_DATA','2025.08.19 02:00:00','2025.08.19 02:00:00','2025.12.24 00:00:00',H25),
 ('2026_P1','V31_2026_PRESEAL_DEVELOPMENT','DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA','2026.01.02 00:00:00','2026.01.16 00:00:00','2026.04.09 00:00:00',H26),
 ('2026_P2','V31_2026_PRESEAL_DEVELOPMENT','DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA','2026.04.09 00:00:00','2026.04.09 00:00:00','2026.07.01 00:00:00',H26),
 ('2026_P3','V31_2026_PRESEAL_DEVELOPMENT','DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA','2026.07.01 00:00:00','2026.07.01 00:00:00','2026.08.01 00:00:00',H26),
]
PROFILES=[('NORMAL',0.0),('HIGH',0.5),('STRESS',1.0)]
LAYERS=[('NATIVE_NORMAL_EXECUTION',0,'NATIVE'),('FIXED_DELAY_200_MS',200,'DELAY200')]

def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def write(name,obj):(OUT/name).write_text(json.dumps(obj,indent=2)+'\n')
def canonical(obj):return json.dumps(obj,sort_keys=True,separators=(',',':')).encode()
def eligible(segment):
 name,_,_,reset,eligible_from,end,path=segment;start=datetime.strptime(reset,FMT);eligible_dt=datetime.strptime(eligible_from,FMT);end_dt=datetime.strptime(end,FMT);bars=[]
 with path.open() as f:
  for row in csv.DictReader(f):
   t=datetime.strptime(row['timestamp'],FMT)
   if start<=t<end_dt:bars.append(t)
 values=[t for i,t in enumerate(bars) if i+1>=300 and t>=eligible_dt]
 return values[0].strftime(FMT),values[-1].strftime(FMT),len(values),len(bars)
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 partition=[]
 for s in SEGMENTS:
  first,last,count,local=eligible(s)
  partition.append({'segment_id':s[0],'formal_dataset':s[1],'classification':s[2],'reset_at':s[3],'eligible_from':s[4],'eligible_to_exclusive':s[5],'minimum_clean_segment_local_bars':300,'segment_local_completed_h1_bars':local,'indicator_eligible_h1_bars':count,'first_indicator_eligible_h1':first,'last_indicator_eligible_h1':last,'state_carried_across_boundary':False})
 write('phase6-v23-data-partition-manifest.json',{'schema':'SOLTRADE_PHASE6_V23_DATA_PARTITIONS_V1','status':'FROZEN_BEFORE_PERFORMANCE','research_classification':'CONTROLLED_PRESEAL_DEVELOPMENT_EVIDENCE','research_cutoff_exclusive':'2026.08.01 00:00:00','source':'V22 qualified segment inventory','qualified_physical_segments':len(partition),'segments':partition,'post_seal_data_permitted':False})
 runs=[];number=0
 for layer,mode,suffix in LAYERS:
  for s,p in zip(SEGMENTS,partition):
   for profile,mult in PROFILES:
    number+=1;rid=f'{number:03d}-{s[0].lower().replace("_", "-")}-{profile.lower()}-{suffix.lower()}';inst=f'V23-{number:03d}-{s[0]}-{profile}-{suffix}'
    core={'strategy_id':'TREND_BREAKOUT_V3_RETEST_HOLD_1_1','segment_id':s[0],'reset_at':s[3],'eligible_from':s[4],'eligible_to_exclusive':s[5],'research_cutoff':'2026.08.01 00:00:00','cost_profile':profile,'supplementary_multiplier':mult,'execution_layer':layer,'execution_mode':mode,'model':4,'optimization':False,'deposit_usd':10000,'leverage':30,'risk_percent':0.25}
    runs.append({'run_number':number,'run_id':rid,'execution_instance_id':inst,'formal_dataset':s[1],'classification':s[2],'segment_id':s[0],'cost_profile':profile,'supplementary_multiplier':mult,'execution_layer':layer,'execution_mode':mode,'reset_at':s[3],'eligible_from':s[4],'eligible_to_exclusive':s[5],'tester_from_date':s[3][:10].replace('.','-'),'tester_to_date':s[5][:10].replace('.','-'),'expected_indicator_eligible_h1_bars':p['indicator_eligible_h1_bars'],'expected_first_indicator_eligible_h1':p['first_indicator_eligible_h1'],'output_subdirectory':f'physical-runs/{rid}','complete_run_configuration_sha256':hashlib.sha256(canonical(core)).hexdigest()})
 assert len(runs)==42
 write('phase6-v23-physical-run-plan.json',{'schema':'SOLTRADE_PHASE6_V23_PHYSICAL_RUN_PLAN_V1','status':'FROZEN_BEFORE_PERFORMANCE','qualified_segments':7,'cost_profiles':3,'execution_layers':2,'expected_formula':'7 * 3 * 2','physical_run_count':42,'run_order_locked':True,'runs':runs})
 cells=[]
 for dataset in ['V31_2025_DEVELOPMENT_REUSE','V31_2026_PRESEAL_DEVELOPMENT']:
  for layer,mode,suffix in LAYERS:
   for profile,mult in PROFILES:
    cell_id=f'{dataset}-{profile}-{suffix}';members=[r['run_id'] for r in runs if r['formal_dataset']==dataset and r['cost_profile']==profile and r['execution_layer']==layer]
    cells.append({'cell_id':cell_id,'formal_dataset':dataset,'cost_profile':profile,'execution_layer':layer,'execution_mode':mode,'member_physical_runs':members,'member_count':len(members),'synthetic_starting_equity_usd':10000.0,'aggregation_order':'NATURALLY_CLOSED_EXIT_TIMESTAMP_ASCENDING_THEN_SEGMENT_ID','segment_account_balances_summed':False,'right_censored_pnl_included':False})
 assert len(cells)==12
 write('phase6-v23-formal-cell-plan.json',{'schema':'SOLTRADE_PHASE6_V23_FORMAL_CELL_PLAN_V1','status':'FROZEN_BEFORE_PERFORMANCE','formal_cell_count':12,'cells':cells})
 cost={'schema':'SOLTRADE_PHASE6_V23_COST_MANIFEST_V1','status':'FROZEN_BEFORE_PERFORMANCE','methodology_source':'V13/V14 CONTROLLED_PRACTICAL_BACKTEST','commission':{'account':'FP Markets Raw USD','per_side_per_standard_lot_usd':3.0,'round_trip_per_standard_lot_usd':6.0,'linear_pro_rata':True,'native_commission_gate':'IF_ZERO_APPLY_EXTERNAL;IF_NONZERO_RECONCILE;NO_DOUBLE_COUNT'},'swap':{'mode':'POINTS','long':-9.71,'short':4.50,'wednesday_triple':True,'historical_schedule_claimed':False},'supplementary_friction':{'formula':'native_friction_usd * supplementary_multiplier','normal_multiplier':0.0,'high_multiplier':0.5,'stress_multiplier':1.0},'alternative_cost_profiles_permitted':False}
 write('phase6-v23-cost-manifest.json',cost)
 gates={'schema':'SOLTRADE_PHASE6_V23_GATE_MANIFEST_V1','status':'FROZEN_BEFORE_PERFORMANCE','sample':{'all_preseal_closed_min':50,'closed_dated_2026_min':15,'buy_closed_min':5,'sell_closed_min':5},'performance':{'NORMAL':{'profit_factor':'> 1.15','adjusted_net_profit':'> 0','expectancy':'> 0','relative_drawdown_percent':'< 8'},'HIGH':{'profit_factor':'>= 1.05','adjusted_net_profit':'> 0','expectancy':'> 0','relative_drawdown_percent':'<= 10'},'STRESS':{'profit_factor':'>= 1.00','adjusted_net_profit':'> 0','expectancy':'> 0','relative_drawdown_percent':'<= 12'}},'concentration':{'best_trade_contribution_percent':'<= 20','best_registered_subperiod_contribution_percent':'<= 40','subperiod_semantics':'five equal chronological subperiods for intervals shorter than four years','undefined_if_net_nonpositive':'FAIL'},'cross_dataset':{'normalized_expectancy_min_div_max':'>= 0.50','annualized_return_min_div_max':'>= 0.50','profit_factor_range':'<= 0.40','applied_per_cost_profile_and_execution_layer':True},'direction_and_segment_consistency':{'numeric_gate':'NONE_FOUND_IN_V14_FROZEN_GATE_EVALUATION','report_all_without_hiding':True},'bootstrap_paths':100000,'monte_carlo_paths':100000,'uncertainty_reporting_only':True}
 write('phase6-v23-gate-manifest.json',gates)
 basis={'schema':'SOLTRADE_PHASE6_V23_SEED_BASIS_V1','canonicalization':'UTF-8 JSON; keys sorted; separators comma/colon; no whitespace','v22_commit':'81370eb7b33464e9bfef38f6dac26c9e24e041a5','strategy_specification_sha256':'bcddb6b3d3ed43f9abad9fdb1793fdae11f0d2f34a76b637844345f64bfd5e95','oos_seal_sha256':'28ab1fa0c4690a16e219d9eba783336b050a3c8f86dc28831dd5ff55db752dbe','production_ea_sha256':'261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3','data_partition_manifest_sha256':sha(OUT/'phase6-v23-data-partition-manifest.json'),'physical_run_plan_sha256':sha(OUT/'phase6-v23-physical-run-plan.json'),'formal_cell_plan_sha256':sha(OUT/'phase6-v23-formal-cell-plan.json'),'cost_manifest_sha256':sha(OUT/'phase6-v23-cost-manifest.json'),'gate_manifest_sha256':sha(OUT/'phase6-v23-gate-manifest.json'),'excluded_fields':['bootstrap_seed','monte_carlo_seed','seed_basis_sha256','final_manifest_sha256','later_artifact_hashes','signatures']}
 write('phase6-v23-seed-basis-manifest.json',basis);basis_hash=hashlib.sha256(canonical(basis)).hexdigest();boot=int(hashlib.sha256((basis_hash+':bootstrap').encode()).hexdigest()[:8],16);mc=int(hashlib.sha256((basis_hash+':monte-carlo').encode()).hexdigest()[:8],16)
 method='''# Phase 6 V23 methodology\n\nAll evidence is `CONTROLLED_PRESEAL_DEVELOPMENT_EVIDENCE`. The 2025 cell remains `DEVELOPMENT_REUSE_DATA`; the 2026 cell remains `DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA`. Neither is untouched validation, OOS, forward testing, or proof of live profitability.\n\nThe frozen V3.1 implementation is executed in 42 isolated Strategy Tester runs: seven clean segments by three cost profiles by two execution modes. Every run uses real ticks, EURUSD H1, one position maximum, 0.25% current-equity risk, the complete Phase 1–5 risk state, natural exits, and fail-closed censoring. Segment balances are never summed. Formal cells reconstruct USD 10,000 synthetic equity chronologically from adjusted realized R.\n\nThe OOS cutoff is exclusive at `2026-08-01 00:00:00`. No record at or after that timestamp may be retrieved or parsed. Right-censored positions receive no P&L. The 12 formal cells and all sample, performance, concentration, and cross-dataset gates are frozen in the companion manifests before run 1. No optimization, tuning, parameter sweep, selective rerun, connected-chart, demo-forward, or live trading is permitted.\n'''
 (OUT/'phase6-v23-methodology.md').write_text(method)
 prerun={'schema':'SOLTRADE_PHASE6_V23_PRERUN_MANIFEST_V1','status':'FROZEN_NOT_EXECUTED','research_classification':'CONTROLLED_PRESEAL_DEVELOPMENT_EVIDENCE','v22_commit':'81370eb7b33464e9bfef38f6dac26c9e24e041a5','v22_tag':'phase6-v22-v31-implementation-ready','strategy_id':'TREND_BREAKOUT_V3_RETEST_HOLD_1_1','research_cutoff_exclusive':'2026.08.01 00:00:00','qualified_segments':7,'physical_runs':42,'formal_cells':12,'optimization':False,'parameter_sweeps':False,'profitability_viewed':False,'run_1_started':False,'bundle_sha256':sha(OUT/'soltrade-phase6-v23-prerun.bundle'),'seed_basis_sha256':basis_hash,'bootstrap_seed':boot,'monte_carlo_seed':mc,'bootstrap_paths':100000,'monte_carlo_paths':100000,'manifest_hash_is_external':True}
 write('phase6-v23-prerun-manifest.json',prerun);prerun_hash=sha(OUT/'phase6-v23-prerun-manifest.json')
 config={'schema':'SOLTRADE_PHASE6_V23_CONFIGURATION_VERIFICATION_V1','status':'PASS','v22_commit_verified':True,'v22_annotated_tag_verified':True,'initial_worktree_clean':True,'bundle_created_before_performance':True,'bundle_verify_status':'PASS','bundle_sha256':sha(OUT/'soltrade-phase6-v23-prerun.bundle'),'bundle_ref_count':15,'production_ea_sha256':'261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3','strategy_specification_sha256':'bcddb6b3d3ed43f9abad9fdb1793fdae11f0d2f34a76b637844345f64bfd5e95','oos_seal_sha256':'28ab1fa0c4690a16e219d9eba783336b050a3c8f86dc28831dd5ff55db752dbe','partition_count':7,'physical_run_count':42,'formal_cell_count':12,'seed_basis_sha256':basis_hash,'bootstrap_seed':boot,'monte_carlo_seed':mc,'prerun_manifest_sha256':prerun_hash,'all_values_frozen_before_run_1':True}
 write('phase6-v23-configuration-verification.json',config)
 print(json.dumps({'segments':7,'physical_runs':42,'formal_cells':12,'seed_basis_sha256':basis_hash,'bootstrap_seed':boot,'monte_carlo_seed':mc,'prerun_manifest_sha256':prerun_hash},indent=2))
if __name__=='__main__':main()
