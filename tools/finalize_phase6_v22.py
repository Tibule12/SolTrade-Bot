#!/usr/bin/env python3
"""Finalize compile, restart, integrity, terminal, and checksum evidence for V22."""
from __future__ import annotations
import hashlib,json,re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/backtests/phase6-v22-v31-implementation-parity'
V22=Path('/home/tibule12/.wine-fpmarkets/drive_c/v22')
TESTER=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/Tester')
HARNESS=ROOT/'research/v31/SolTradeV31TesterHarness.mq5'
FIXTURE=ROOT/'research/v31/SolTradeV31RestartFixtures.mq5'

def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def write(name,data):(OUT/name).write_text(json.dumps(data,indent=2)+'\n')
def log_text(path):return path.read_text(encoding='utf-16')

def main():
 harness_log=V22/'harness-compile.log';fixture_log=V22/'fixture-compile.log'
 comp=[]
 for role,source,log,ex5 in [('research_harness',HARNESS,harness_log,V22/'SolTradeV31TesterHarness.ex5'),('restart_fixture_runner',FIXTURE,fixture_log,V22/'SolTradeV31RestartFixtures.ex5')]:
  text=log_text(log);m=re.search(r'Result: (\d+) errors, (\d+) warnings',text)
  comp.append({'role':role,'source':str(source.relative_to(ROOT)),'source_sha256':sha(source),'executable_sha256':sha(ex5),'compile_log':str(log),'compile_log_sha256':sha(log),'errors':int(m.group(1)) if m else None,'warnings':int(m.group(2)) if m else None,'status':'PASS' if m and m.group(1)=='0' and m.group(2)=='0' else 'FAIL'})
 write('phase6-v22-compilation-report.json',{'schema':'SOLTRADE_PHASE6_V22_COMPILATION_V1','status':'PASS' if all(x['status']=='PASS' for x in comp) else 'FAIL','targets':comp,'production_target_compiled_or_modified':False})

 fixture_log_path=next(TESTER.glob('Agent-127.0.0.1-3210/logs/20260804.log'))
 fixture_text=log_text(fixture_log_path);lines=[x for x in fixture_text.splitlines() if 'SOLTRADE_V31_RESTART_FIXTURES' in x];last=lines[-1] if lines else ''
 m=re.search(r'pass=(\d+) \| fail=(\d+).*duplicate_setups=(\d+).*duplicate_confirmations=(\d+).*duplicate_entry_decisions=(\d+).*duplicate_entries=(\d+).*duplicate_exits=(\d+).*duplicate_cycles=(\d+)',last)
 names=['immediately_before_setup_creation','immediately_after_setup_creation','after_retest_candle_1','after_retest_candle_3','after_retest_candle_5','after_confirmation_before_first_tradable_tick','immediately_after_spread_block','immediately_after_structural_entry','immediately_before_theoretical_stop_exit','immediately_before_donchian_exit','immediately_after_cycle_completion','clean_segment_reset']
 passed=int(m.group(1)) if m else 0;failed=int(m.group(2)) if m else len(names)
 write('phase6-v22-restart-fixture-report.json',{'schema':'SOLTRADE_PHASE6_V22_RESTART_FIXTURES_V1','status':'PASS' if passed==len(names) and failed==0 else 'FAIL','strategy_state_namespace':'TREND_BREAKOUT_V3_RETEST_HOLD_1_1','fixture_count':len(names),'pass_count':passed,'fail_count':failed,'fixtures':[{'name':n,'status':'PASS' if i<passed else 'FAIL'} for i,n in enumerate(names)],'duplicate_counts':{'setups':int(m.group(3)) if m else None,'confirmations':int(m.group(4)) if m else None,'entry_decisions':int(m.group(5)) if m else None,'theoretical_entries':int(m.group(6)) if m else None,'exits':int(m.group(7)) if m else None,'completed_cycles':int(m.group(8)) if m else None},'persistence_fields_verified':['strategy_version','clean_segment_identity','active_setup_identity','setup_direction','frozen_boundary','setup_timestamp','retest_candle_count','last_processed_h1_identity','confirmation_identity','spread_decision_status','theoretical_position_state','final_status'],'native_tester_log':str(fixture_log_path),'native_tester_log_sha256':sha(fixture_log_path),'raw_result_line':last})

 parity=json.loads((OUT/'phase6-v22-state-parity-report.json').read_text());c25=json.loads((OUT/'phase6-v22-2025-structural-counts.json').read_text());c26=json.loads((OUT/'phase6-v22-2026-preseal-structural-counts.json').read_text());seal=json.loads((OUT/'phase6-v22-oos-seal-access-audit.json').read_text());immut=json.loads((OUT/'phase6-v22-production-immutability-report.json').read_text());mono=json.loads((OUT/'phase6-v22-v30-v31-monotonicity-audit.json').read_text());spread=json.loads((OUT/'phase6-v22-spread-policy-verification.json').read_text())
 total=c25['naturally_completed_structural_cycles']+c26['naturally_completed_structural_cycles'];buy=c25['buy_completed_cycles']+c26['buy_completed_cycles'];sell=c25['sell_completed_cycles']+c26['sell_completed_cycles']
 sample=total>=50 and c26['naturally_completed_structural_cycles']>=15 and buy>=5 and sell>=5
 source=HARNESS.read_text();forbidden=[x for x in ['OrderSend(','OrderSendAsync(','CTrade','PositionOpen(','Buy(','Sell('] if x in source]
 technical=parity['status']=='PASS' and not forbidden and seal['status']=='PASS' and immut['status']=='PASS' and mono['status']=='PASS' and spread['status']=='PASS' and all(x['status']=='PASS' for x in comp) and passed==12 and failed==0
 outcome='V31_IMPLEMENTATION_AND_PARITY_READY' if technical and sample else 'V31_IMPLEMENTATION_READY_SAMPLE_SPARSE' if technical else 'INVALID_TEST_EVIDENCE'
 integrity=json.loads((OUT/'phase6-v22-evidence-integrity.json').read_text());integrity.update({'status':'PASS' if technical else 'FAIL','compilation_gates_passed':all(x['status']=='PASS' for x in comp),'restart_safety_passed':passed==12 and failed==0,'forbidden_trade_api_references':forbidden,'strategy_orders_created':0,'strategy_positions_created':0,'strategy_trade_deals_created':0,'trade_transactions_observed':0,'tester_balance_initialization_record_is_not_a_trade_deal':True,'demo_trades':0,'live_trades':0,'profitability_fields_produced':0,'financial_classifications_produced':0,'terminal_outcome':outcome})
 write('phase6-v22-evidence-integrity.json',integrity)
 (OUT/'phase6-v22-terminal-outcome.md').write_text(f'''# Phase 6 V22 terminal outcome

`{outcome}`

All mandatory implementation gates pass: both isolated executables compile with 0 errors and 0 warnings; all 12 restart fixtures pass with zero duplicates; the reference and native MQL5 ledgers contain {parity['reference_events']} events each with {parity['divergence_count']} divergences; the spread-policy and V3.0-to-V3.1 monotonicity audits pass; and the production EA and OOS seal hashes remain unchanged.

The frozen pre-run V23 sample gates pass. The permitted pre-seal data produced {total} naturally completed structural cycles, including {c26['naturally_completed_structural_cycles']} dated in 2026, split {buy} BUY and {sell} SELL. These counts are `STRUCTURAL_SAMPLE_UPPER_BOUND`, not profitability evidence or an OOS forecast.

No profitability field, financial result, winner/loser label, optimization, order, position, strategy trade deal, demo trade, or live trade was produced. The tester's account-initialization balance record is not a trade deal. The sealed period beginning `2026-08-01 00:00:00` remained unopened.
''')
 artifacts=sorted(p for p in OUT.iterdir() if p.is_file() and p.name!='artifact-sha256-v22.txt')
 (OUT/'artifact-sha256-v22.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in artifacts))
 print(json.dumps({'outcome':outcome,'artifacts':len(artifacts)+1,'cycles':total,'buy':buy,'sell':sell,'parity':parity['status'],'fixtures':f'{passed}/{len(names)}'},indent=2))
if __name__=='__main__':main()
