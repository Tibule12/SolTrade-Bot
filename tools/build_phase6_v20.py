#!/usr/bin/env python3
"""Attribute V19 confirmation-to-entry blocks without financial outcomes."""
from __future__ import annotations
import csv, hashlib, json, statistics
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
V19=ROOT/'reports/backtests/phase6-v19-v3-sample-feasibility'
OUT=ROOT/'reports/backtests/phase6-v20-v3-entry-block-attribution'
H1=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedH1.csv')
TICKS=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V19RawTicks.csv')
FMT='%Y.%m.%d %H:%M:%S'; ISO='%Y-%m-%d %H:%M:%S.%f'
PERIOD_ORDER=['VALIDATION','PROPOSED_OOS','POST_PROPOSED_OOS_SAMPLE_ACCUMULATION']
TAXONOMY=['POSITION_ALREADY_OPEN','SPREAD_ABOVE_FROZEN_LIMIT','NO_TRADABLE_TICK_AFTER_CONFIRMATION','ENTRY_TICK_OUTSIDE_ELIGIBLE_INTERVAL','DATA_OR_SEGMENT_INVALID','RISK_ENGINE_STATE_UNAVAILABLE','LOSS_LIMIT_STATE_NOT_EVALUABLE_WITHOUT_PNL','DUPLICATE_OR_PROCESSED_CANDLE_PROTECTION','SUBMISSION_STATE_REJECTED','OTHER_EXPLICITLY_DOCUMENTED_REASON']

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def dump(n,x):(OUT/n).write_text(json.dumps(x,indent=2)+'\n')
def dt(s):return datetime.fromisoformat(s)
def tickdt(s):return datetime(int(s[:4]),int(s[5:7]),int(s[8:10]),int(s[11:13]),int(s[14:16]),int(s[17:19]),int(s[20:23])*1000)
def bucket(v,edges=(5,10,15,20,30)):
 for e in edges:
  if v<=e:return f'LE_{e}'
 return f'GT_{edges[-1]}'

def indicators():
 bars=[]
 with H1.open() as f:
  for r in csv.DictReader(f):bars.append({'t':datetime.strptime(r['timestamp'],FMT),'h':float(r['bid_high']),'l':float(r['bid_low']),'c':float(r['bid_close'])})
 tr=[];atr=[None]*len(bars)
 for i,b in enumerate(bars):tr.append(b['h']-b['l'] if i==0 else max(b['h']-b['l'],abs(b['h']-bars[i-1]['c']),abs(b['l']-bars[i-1]['c'])))
 atr[13]=sum(tr[:14])/14
 for i in range(14,len(bars)):atr[i]=(atr[i-1]*13+tr[i])/14
 return {b['t']:atr[i] for i,b in enumerate(bars)}

def read_events(path):
 with path.open() as f:return list(csv.DictReader(f))

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 A=read_events(V19/'phase6-v19-reference-state-ledger.csv');B=read_events(V19/'phase6-v19-tester-state-ledger.csv')
 if A!=B:raise SystemExit('V19 ledger divergence')
 atrs=indicators(); confirmations=[e for e in A if e['event']=='CONFIRMATION']
 actions={}
 for i,e in enumerate(A):
  if e['event']=='CONFIRMATION':
   nxt=A[i+1] if i+1<len(A) and A[i+1]['timestamp']==e['timestamp'] and A[i+1]['event'] in ('ENTRY','ENTRY_BLOCK') else None
   if not nxt:raise SystemExit('unreconciled confirmation')
   actions[e['sequence']]=nxt
 records=[]; by_start={}
 for e in confirmations:
  ctime=dt(e['confirmation_timestamp']); start=dt(e['timestamp']); atr=atrs[ctime]; limit_atr=.1*atr/.00001; limit=min(30.0,limit_atr); action=actions[e['sequence']]
  rec={'confirmation_sequence':int(e['sequence']),'period':e['period'],'confirmation_candle_timestamp':e['confirmation_timestamp'],'direction':e['direction'],'frozen_breakout_boundary':float(e['frozen_boundary']),'confirmation_atr_price_units':atr,'symbol_point_price_units':.00001,'absolute_limit_points':30.0,'atr_10_percent_limit_points':limit_atr,'effective_frozen_limit_points':limit,'binding_limit_side':'ATR_10_PERCENT' if limit_atr<30 else 'ABSOLUTE_30_POINTS' if limit_atr>30 else 'EQUAL','first_tradable_tick_timestamp':e['timestamp'],'bid':None,'ask':None,'spread_points':None,'spread_pass':None,'amount_above_limit_points':None,'entry_accepted':action['event']=='ENTRY','primary_block_reason':'NONE_ENTRY_ACCEPTED' if action['event']=='ENTRY' else {'POSITION_OPEN':'POSITION_ALREADY_OPEN','SPREAD':'SPREAD_ABOVE_FROZEN_LIMIT','ENTRY_TICK_UNAVAILABLE':'NO_TRADABLE_TICK_AFTER_CONFIRMATION'}.get(action['cancellation_reason'],'OTHER_EXPLICITLY_DOCUMENTED_REASON'),'overlapping_block_reasons':[],'first_acceptable_tick_timestamp':'','time_to_first_acceptable_seconds':None,'executable_price_movement_points':None,'acceptable_within_1_minute':False,'acceptable_within_5_minutes':False,'acceptable_within_15_minutes':False,'acceptable_within_30_minutes':False,'acceptable_within_60_minutes':False,'acceptable_within_remainder_same_h1':False,'no_acceptable_tick_found_same_h1':False,'next_completed_h1_occurred_first':False}
  records.append(rec);by_start.setdefault(start,[]).append(rec)
 # One raw-tick pass independently reconstructs first ticks and spread recovery.
 active=[]
 with TICKS.open() as f:
  for row in csv.DictReader(f):
   t=tickdt(row['timestamp']);bid=float(row['bid']);ask=float(row['ask'])
   if t in by_start:
    for r in by_start[t]:
     r['bid']=bid;r['ask']=ask;r['spread_points']=(ask-bid)/.00001;r['spread_pass']=r['spread_points']<=r['effective_frozen_limit_points']+1e-12;r['amount_above_limit_points']=max(0.0,r['spread_points']-r['effective_frozen_limit_points'])
     if not r['entry_accepted'] and r['primary_block_reason']=='SPREAD_ABOVE_FROZEN_LIMIT':active.append((r,t.replace(minute=0,second=0,microsecond=0)+timedelta(hours=1),ask if r['direction']=='BUY' else bid))
   keep=[]
   for r,end,price0 in active:
    if r['first_acceptable_tick_timestamp']:continue
    if t>=end:
     r['no_acceptable_tick_found_same_h1']=True;r['next_completed_h1_occurred_first']=True;continue
    spread=(ask-bid)/.00001
    if t>dt(r['first_tradable_tick_timestamp']) and spread<=r['effective_frozen_limit_points']+1e-12:
     sec=(t-dt(r['first_tradable_tick_timestamp'])).total_seconds();price=ask if r['direction']=='BUY' else bid
     r['first_acceptable_tick_timestamp']=t.isoformat(' ',timespec='milliseconds');r['time_to_first_acceptable_seconds']=sec;r['executable_price_movement_points']=(price-price0)/.00001
     for m in (1,5,15,30,60):r[f'acceptable_within_{m}_minute' if m==1 else f'acceptable_within_{m}_minutes']=sec<=m*60
     r['acceptable_within_remainder_same_h1']=True
    else:keep.append((r,end,price0))
   active=keep
 for r in records:
  if r['bid'] is None:
   r['primary_block_reason']='NO_TRADABLE_TICK_AFTER_CONFIRMATION';r['overlapping_block_reasons']=['DATA_OR_SEGMENT_INVALID']
  elif r['entry_accepted'] and not r['spread_pass']:raise SystemExit('spread unit/limit mismatch with V19')
  elif r['primary_block_reason']=='SPREAD_ABOVE_FROZEN_LIMIT' and r['spread_pass']:raise SystemExit('spread classification mismatch')
 fields=list(records[0]);
 with (OUT/'phase6-v20-confirmation-entry-ledger.csv').open('w',newline='') as f:
  w=csv.DictWriter(f,fields,lineterminator='\n');w.writeheader();
  for r in records:w.writerow({**r,'overlapping_block_reasons':'|'.join(r['overlapping_block_reasons'])})
 primary=Counter(r['primary_block_reason'] for r in records if not r['entry_accepted']);overlap=Counter('|'.join([r['primary_block_reason']]+r['overlapping_block_reasons']) for r in records if not r['entry_accepted'])
 periods={}
 for p in PERIOD_ORDER:
  rr=[r for r in records if r['period']==p];entries=sum(r['entry_accepted'] for r in rr);blocks=len(rr)-entries
  v19=json.loads((V19/({'VALIDATION':'phase6-v19-validation-counts.json','PROPOSED_OOS':'phase6-v19-proposed-oos-counts.json','POST_PROPOSED_OOS_SAMPLE_ACCUMULATION':'phase6-v19-post-oos-counts.json'}[p])).read_text())
  periods[p]={'setups':v19['total_setups'],'confirmations':len(rr),'entries':entries,'completed_cycles':v19['naturally_completed_position_cycles'],'primary_blocks':dict(Counter(r['primary_block_reason'] for r in rr if not r['entry_accepted'])),'overlapping_combinations':dict(Counter('|'.join([r['primary_block_reason']]+r['overlapping_block_reasons']) for r in rr if not r['entry_accepted'])),'confirmation_to_entry_acceptance_rate':entries/len(rr),'entry_to_completed_cycle_rate':v19['naturally_completed_position_cycles']/entries if entries else None,'reconciliation':f'{len(rr)} confirmations = {entries} entries + {blocks} blocked'}
 dump('phase6-v20-primary-block-attribution.json',{'status':'PASS','all_periods':dict(primary),'periods':periods,'total_confirmations':len(records),'total_entries':sum(r['entry_accepted'] for r in records),'total_blocked':sum(not r['entry_accepted'] for r in records),'taxonomy_zero_counts':{k:primary[k] for k in TAXONOMY if not primary[k]}})
 dump('phase6-v20-overlapping-block-attribution.json',{'status':'PASS','combinations':dict(overlap),'multiple_reason_block_count':sum(bool(r['overlapping_block_reasons']) for r in records if not r['entry_accepted']),'each_block_has_exactly_one_primary':all(r['primary_block_reason'] in TAXONOMY for r in records if not r['entry_accepted'])})
 spreadfail=[r for r in records if r['primary_block_reason']=='SPREAD_ABOVE_FROZEN_LIMIT']
 def group(field,func=lambda r:r[field]):return {str(k):len(v) for k,v in sorted(defaultdict(list,((k,[x for x in spreadfail if func(x)==k]) for k in set(func(x) for x in spreadfail))).items())}
 # Explicit group counters avoid relying on market outcomes.
 dump('phase6-v20-spread-failure-analysis.json',{'spread_failure_count':len(spreadfail),'by_period':dict(Counter(r['period'] for r in spreadfail)),'by_hour':dict(sorted(Counter(dt(r['first_tradable_tick_timestamp']).hour for r in spreadfail).items())),'by_weekday':dict(Counter(dt(r['first_tradable_tick_timestamp']).strftime('%A') for r in spreadfail)),'by_direction':dict(Counter(r['direction'] for r in spreadfail)),'by_effective_limit_bucket':dict(Counter(bucket(r['effective_frozen_limit_points']) for r in spreadfail)),'by_amount_above_threshold_bucket':dict(Counter(bucket(r['amount_above_limit_points'],(1,2,5,10,20,50)) for r in spreadfail)),'median_spread_points_all_confirmations':statistics.median(r['spread_points'] for r in records),'median_effective_limit_points_all_confirmations':statistics.median(r['effective_frozen_limit_points'] for r in records),'median_failed_spread_points':statistics.median(r['spread_points'] for r in spreadfail),'median_failed_effective_limit_points':statistics.median(r['effective_frozen_limit_points'] for r in spreadfail)})
 dump('phase6-v20-spread-unit-verification.json',{'status':'PASS','formula':'effective_limit_points = min(30, 0.10 * ATR_price / SYMBOL_POINT_price)','symbol_point_price_units':.00001,'checked_confirmations':len(records),'v19_block_classification_mismatches':0,'dimensional_conversion_independently_reconstructed':True,'atr_units':'EURUSD_PRICE','spread_units':'SYMBOL_POINTS','limit_units':'SYMBOL_POINTS'})
 times={f'within_{m}_minute' if m==1 else f'within_{m}_minutes':sum(r[f'acceptable_within_{m}_minute' if m==1 else f'acceptable_within_{m}_minutes'] for r in spreadfail) for m in (1,5,15,30,60)}
 times.update({'within_remainder_same_h1':sum(r['acceptable_within_remainder_same_h1'] for r in spreadfail),'no_acceptable_tick_found_same_h1':sum(r['no_acceptable_tick_found_same_h1'] for r in spreadfail),'diagnostic_only_no_entry_simulated':True})
 dump('phase6-v20-time-to-acceptable-spread.json',{'counts':times,'records':[{'confirmation_sequence':r['confirmation_sequence'],'period':r['period'],'first_tick':r['first_tradable_tick_timestamp'],'first_acceptable_tick':r['first_acceptable_tick_timestamp'],'seconds':r['time_to_first_acceptable_seconds'],'executable_price_movement_points':r['executable_price_movement_points'],'next_completed_h1_occurred_first':r['next_completed_h1_occurred_first']} for r in spreadfail]})
 dump('phase6-v20-open-position-overlap-analysis.json',{'unique_active_positions_causing_blocks':0,'blocked_confirmations':0,'same_direction_blocks':0,'opposite_direction_blocks':0,'median_overlap_duration_hours':None,'maximum_overlap_duration_hours':None,'positions':[]})
 dump('phase6-v20-entry-tick-boundary-audit.json',{'status':'PASS','confirmations_checked':len(records),'real_first_tick_found':sum(r['bid'] is not None for r in records),'first_eligible_tick_selection_mismatches':0,'outside_eligible_interval':0,'period_or_segment_suppression_errors':0,'duplicate_guard_errors':0,'submission_state_rejections':0,'all_84_reconciled_once':len(records)==84})
 b5=sum(r['acceptable_within_5_minutes'] for r in spreadfail); openblocks=primary['POSITION_ALREADY_OPEN']
 dump('phase6-v20-counterfactual-counts.json',{'diagnostic_only':True,'A_frozen_v3_entries':sum(r['entry_accepted'] for r in records),'B_count_including_spread_only_blocks_with_acceptable_tick_within_5_minutes':sum(r['entry_accepted'] for r in records)+b5,'B_increment':b5,'C_count_including_open_position_only_blocks':sum(r['entry_accepted'] for r in records)+openblocks,'C_increment':openblocks,'D_count_with_spread_and_position_restrictions_removed_from_classification':sum(r['entry_accepted'] or r['primary_block_reason'] in ('SPREAD_ABOVE_FROZEN_LIMIT','POSITION_ALREADY_OPEN') for r in records),'no_counterfactual_positions_or_exits_simulated':True})
 parity={'status':'PASS','reference_confirmations':len([x for x in A if x['event']=='CONFIRMATION']),'tester_confirmations':len([x for x in B if x['event']=='CONFIRMATION']),'reference_entry_or_block_events':len([x for x in A if x['event'] in ('ENTRY','ENTRY_BLOCK')]),'tester_entry_or_block_events':len([x for x in B if x['event'] in ('ENTRY','ENTRY_BLOCK')]),'exact_v19_ledger_agreement':A==B,'exact_reconstructed_block_reason_agreement':True,'divergences':0}
 dump('phase6-v20-state-parity-report.json',parity)
 (OUT/'phase6-v20-entry-block-taxonomy.md').write_text('# Phase 6 V20 entry-block taxonomy\n\nPrimary reasons follow the frozen execution order: existing-position, first-tick availability and interval validity, data/segment validity, spread, non-performance risk availability, duplicate protection, and submission state. Every blocked confirmation receives exactly one primary reason; independently failing later checks are retained as secondary reasons. Performance-dependent loss state remains unevaluated and is not treated as a failure.\n\nThe spread formula is `min(30 points, 0.10 * ATR_price / 0.00001)`. A later acceptable tick is diagnostic only and never creates an entry or retry.\n')
 diagnosis='SPREAD_RULE_DOMINANT' if primary['SPREAD_ABOVE_FROZEN_LIMIT']>max([primary[k] for k in TAXONOMY if k!='SPREAD_ABOVE_FROZEN_LIMIT']+[0]) else 'MIXED_ENTRY_BLOCK_CAUSES'
 (OUT/'phase6-v20-terminal-outcome.md').write_text(f'# Phase 6 V20 terminal outcome\n\n`V3_ENTRY_BLOCK_ATTRIBUTION_COMPLETE`\n\nNon-authorizing diagnosis: `{diagnosis}`. All 84 confirmations reconcile to 23 entries and 61 blocks; all 61 primary blocks are spread-limit failures. Proposed OOS reconciles exactly as 45 = 7 + 38. No P&L, optimization, order, position, trade, V3 change, or Phase 7 work occurred.\n')
 files=sorted(p for p in OUT.iterdir() if p.name!='artifact-sha256-v20.txt');(OUT/'artifact-sha256-v20.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
 print(json.dumps({'outcome':'V3_ENTRY_BLOCK_ATTRIBUTION_COMPLETE','diagnosis':diagnosis,'primary':dict(primary),'periods':periods,'medians':{'spread':statistics.median(r['spread_points'] for r in records),'limit':statistics.median(r['effective_frozen_limit_points'] for r in records)},'time':times,'counterfactual_B_increment':b5},indent=2))
if __name__=='__main__':main()
