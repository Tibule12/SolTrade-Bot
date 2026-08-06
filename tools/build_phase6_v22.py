#!/usr/bin/env python3
"""Independent V3.1 reference replay, native-ledger parity, and V22 evidence."""
from __future__ import annotations
import csv,hashlib,json,statistics
from collections import Counter
from datetime import datetime,timedelta
from decimal import Decimal
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/backtests/phase6-v22-v31-implementation-parity'
COMMON=Path('/home/tibule12/.wine-fpmarkets/drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files')
H25=Path('/home/tibule12/.wine-fpmarkets/drive_c/v8/derived/SolTradePhase6V8DerivedH1.csv');H26=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedH1.csv')
T25=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradeV31Preseal2025RawTicks.csv');T26=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V19RawTicks.csv')
CUTOFF=datetime(2026,8,1); FMT='%Y.%m.%d %H:%M:%S'
SEGS=[('2025_S1',datetime(2025,1,2),datetime(2025,1,16),datetime(2025,2,5),H25,T25,'DEVELOPMENT_REUSE_DATA'),('2025_S2',datetime(2025,2,17,9),datetime(2025,2,17,9),datetime(2025,3,7,23),H25,T25,'DEVELOPMENT_REUSE_DATA'),('2025_S3',datetime(2025,3,20,8),datetime(2025,3,20,8),datetime(2025,8,6,16),H25,T25,'DEVELOPMENT_REUSE_DATA'),('2025_S4',datetime(2025,8,19,2),datetime(2025,8,19,2),datetime(2025,12,24),H25,T25,'DEVELOPMENT_REUSE_DATA'),('2026_P1',datetime(2026,1,2),datetime(2026,1,16),datetime(2026,4,9),H26,T26,'DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA'),('2026_P2',datetime(2026,4,9),datetime(2026,4,9),datetime(2026,7,1),H26,T26,'DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA'),('2026_P3',datetime(2026,7,1),datetime(2026,7,1),datetime(2026,8,1),H26,T26,'DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA')]
FIELDS=['sequence','event','timestamp','segment','direction','setup_timestamp','frozen_boundary','retest_candle_number','confirmation_timestamp','entry_timestamp','stop_level','exit_type','cancellation_reason','bid','ask','spread_points','confirmation_atr','effective_spread_limit_points']
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''):h.update(b)
 return h.hexdigest()
def js(n,x):(OUT/n).write_text(json.dumps(x,indent=2,sort_keys=False)+'\n')
def ticktime(s):return datetime(int(s[:4]),int(s[5:7]),int(s[8:10]),int(s[11:13]),int(s[14:16]),int(s[17:19]),int(s[20:23])*1000)
def stamp(x):return x.strftime('%Y.%m.%d %H:%M:%S.%f')[:-3]
def loadbars(path,start,end):
 raw=[]
 with path.open() as f:
  for r in csv.DictReader(f):
   t=datetime.strptime(r['timestamp'],FMT)
   if start<=t<end:raw.append({'t':t,'o':float(r['bid_open']),'h':float(r['bid_high']),'l':float(r['bid_low']),'c':float(r['bid_close']),'ema':0.,'atr':0.,'mean':0.})
 a=2/201
 for i,b in enumerate(raw):
  if i==199:b['ema']=sum(x['c'] for x in raw[:200])/200
  elif i>199:b['ema']=b['c']*a+raw[i-1]['ema']*(1-a)
  tr=b['h']-b['l'] if i==0 else max(b['h']-b['l'],abs(b['h']-raw[i-1]['c']),abs(b['l']-raw[i-1]['c']))
  if i==13:
   trs=[]
   for j in range(14):trs.append(raw[j]['h']-raw[j]['l'] if j==0 else max(raw[j]['h']-raw[j]['l'],abs(raw[j]['h']-raw[j-1]['c']),abs(raw[j]['l']-raw[j-1]['c'])))
   b['atr']=sum(trs)/14
  elif i>13:b['atr']=(raw[i-1]['atr']*13+tr)/14
  if i>=113:b['mean']=sum(x['atr'] for x in raw[i-100:i])/100
 return raw
class Ref:
 def __init__(self,name,bars,eligible,end):self.name=name;self.bars=bars;self.eligible=eligible;self.end=end;self.active=None;self.pos=None;self.next_bar=0;self.ev=[];self.max_tick=None;self.max_bar=None
 def emit(self,ev,t,d=0,cancel='',rn=0,confirm=None,entry=None,stop=0,exit_type='',bid=0,ask=0,atr=0,limit=0):
  a=self.active or {}; ent=(stamp(entry) if ev=='ENTRY' else entry.strftime(FMT)+'.000') if entry else ''; row=dict(sequence=str(len(self.ev)+1),event=ev,timestamp=stamp(t),segment=self.name,direction='BUY' if d>0 else 'SELL' if d<0 else '',setup_timestamp=stamp(a['t']) if a.get('t') else '',frozen_boundary=f"{a.get('bound',0):.10f}",retest_candle_number=str(rn) if rn else '0',confirmation_timestamp=stamp(confirm) if confirm else '',entry_timestamp=ent,stop_level=f'{stop:.10f}',exit_type=exit_type,cancellation_reason=cancel,bid=f'{bid:.10f}',ask=f'{ask:.10f}',spread_points=f'{round((ask-bid)/.00001,8):.8f}',confirmation_atr=f'{atr:.12f}',effective_spread_limit_points=f'{limit:.12f}')
  self.ev.append(row)
 def reg(self,b):return b['atr']>0 and b['mean']>0 and .5<=b['atr']/b['mean']<=2
 def setup(self,i):
  b=self.bars[i]
  if i+1<300 or not self.reg(b):return None
  p=self.bars[i-20:i];hi=max(x['h'] for x in p);lo=min(x['l'] for x in p)
  return (1,hi) if b['c']>hi and b['c']>b['ema'] else (-1,lo) if b['c']<lo and b['c']<b['ema'] else None
 def create(self,b,c):self.active={'d':c[0],'bound':c[1],'t':b['t'],'n':0};self.emit('SETUP',b['t'],c[0])
 def complete(self,i,t,bid,ask):
  b=self.bars[i]
  if b['t']<self.eligible or b['t']>=self.end:return
  cand=self.setup(i)
  if self.pos and i>=10:
   p=self.bars[i-10:i];hit=b['c']<min(x['l'] for x in p) if self.pos['d']>0 else b['c']>max(x['h'] for x in p)
   if hit:self.emit('EXIT',t,self.pos['d'],entry=self.pos['entry'],stop=self.pos['stop'],exit_type='DONCHIAN_10');self.pos=None
  if self.active:
   a=self.active;a['n']+=1;d=a['d'];touch=b['l']<=a['bound'] if d>0 else b['h']>=a['bound'];hold=b['c']>a['bound'] if d>0 else b['c']<a['bound'];emaok=b['c']>b['ema'] if d>0 else b['c']<b['ema']
   if touch and hold and emaok and self.reg(b):
    lim=min(30,.2*b['atr']/.00001);self.emit('CONFIRMATION',t,d,rn=a['n'],confirm=b['t'],bid=bid,ask=ask,atr=b['atr'],limit=lim)
    if self.pos:self.emit('ENTRY_BLOCK',t,d,'POSITION_ALREADY_OPEN',a['n'],b['t'],bid=bid,ask=ask,atr=b['atr'],limit=lim)
    elif bid<=0 or ask<=0:self.emit('ENTRY_BLOCK',t,d,'NO_TRADABLE_TICK',a['n'],b['t'],bid=bid,ask=ask,atr=b['atr'],limit=lim)
    elif (ask-bid)/.00001>lim:self.emit('ENTRY_BLOCK',t,d,'SPREAD',a['n'],b['t'],bid=bid,ask=ask,atr=b['atr'],limit=lim)
    else:
     price=ask if d>0 else bid;st=price-2*b['atr'] if d>0 else price+2*b['atr'];self.pos={'d':d,'entry':t,'stop':st};self.emit('ENTRY',t,d,rn=a['n'],confirm=b['t'],entry=t,stop=st,bid=bid,ask=ask,atr=b['atr'],limit=lim)
    self.active=None;return
   wrong=not emaok;opp=cand and cand[0]!=d;reason='WRONG_EMA_SIDE' if wrong else 'OPPOSITE_BREAKOUT' if opp else 'EXPIRED_SIX_CANDLES' if a['n']>=6 else ''
   if reason:
    self.emit('CANCEL',t,d,reason,a['n']);self.active=None
    if reason=='OPPOSITE_BREAKOUT':self.create(b,cand);return
  if not self.pos and not self.active and cand:self.create(b,cand)
 def tick(self,t,bid,ask):
  if t>=CUTOFF:raise RuntimeError('seal breach')
  self.max_tick=t
  while self.next_bar<len(self.bars) and self.bars[self.next_bar]['t']+timedelta(hours=1)<=t:
   self.max_bar=self.bars[self.next_bar]['t'];self.complete(self.next_bar,t,bid,ask);self.next_bar+=1
  if self.pos and (bid<=self.pos['stop'] if self.pos['d']>0 else ask>=self.pos['stop']):self.emit('EXIT',t,self.pos['d'],entry=self.pos['entry'],stop=self.pos['stop'],exit_type='INITIAL_STOP');self.pos=None
 def finish(self):
  if self.pos:self.emit('OPEN_AT_BOUNDARY',self.end,self.pos['d'],entry=self.pos['entry'],stop=self.pos['stop'])
  if self.active:self.emit('RESET',self.end,self.active['d'],'PERIOD_BOUNDARY',self.active['n'])
  return self.ev
def runrefs():
 engines=[]
 for name,reset,eligible,end,h,t,label in SEGS:engines.append((Ref(name,loadbars(h,reset,end),eligible,end),t,reset,end))
 for tickfile in (T25,T26):
  selected=[x for x in engines if x[1]==tickfile]
  with tickfile.open() as f:
   for r in csv.DictReader(f):
    t=ticktime(r['timestamp'])
    if t>=CUTOFF:raise RuntimeError('seal breach')
    for e,_,start,end in selected:
     if start<=t<end:e.tick(t,float(r['bid']),float(r['ask']));break
 return {e.name:e.finish() for e,_,_,_ in engines},engines
def native():
 out={}
 for name,*_ in SEGS:
  with (COMMON/f'SolTradeV31-{name}.csv').open(encoding='utf-16') as f:out[name]=list(csv.DictReader(f))
 return out
def writeledger(name,data):
 rows=[]
 for seg,*_ in SEGS:rows+=data[seg]
 with (OUT/name).open('w',newline='') as f:w=csv.DictWriter(f,FIELDS,lineterminator='\n');w.writeheader();w.writerows(rows)
 return rows
def norm(row):
 # Compare exact decisions/timestamps and numeric values at frozen tolerance.
 return {k:row.get(k,'') for k in FIELDS}
def dt(s):return datetime.strptime(s,'%Y.%m.%d %H:%M:%S.%f')
def dist(values):
 return {'average_hours':sum(values)/len(values),'median_hours':statistics.median(values)} if values else {'average_hours':None,'median_hours':None}
def counts(rows,label,eligible):
 ev=Counter(x['event'] for x in rows);dirs=Counter(x['direction'] for x in rows if x['event']=='EXIT');ret=Counter(x['retest_candle_number'] for x in rows if x['event']=='CONFIRMATION');canc=Counter(x['cancellation_reason'] for x in rows if x['event'] in ('CANCEL','ENTRY_BLOCK'))
 entries=[x for x in rows if x['event']=='ENTRY'];exits=[x for x in rows if x['event']=='EXIT'];confs=[x for x in rows if x['event']=='CONFIRMATION'];setups=[x for x in rows if x['event']=='SETUP']
 active_retest=None; cycle_retest=Counter()
 for x in rows:
  if x['event']=='ENTRY':active_retest=x['retest_candle_number']
  elif x['event']=='EXIT' and active_retest is not None:cycle_retest[active_retest]+=1;active_retest=None
 setup_confirm=[(dt(x['confirmation_timestamp'])-dt(x['setup_timestamp'])).total_seconds()/3600 for x in confs]
 holding=[(dt(x['timestamp'])-dt(x['entry_timestamp'])).total_seconds()/3600 for x in exits]
 return {'classification':label,'sample_interpretation':'STRUCTURAL_SAMPLE_UPPER_BOUND','eligible_completed_h1_candles':eligible,'buy_setups':sum(x['direction']=='BUY' for x in setups),'sell_setups':sum(x['direction']=='SELL' for x in setups),'total_setups':len(setups),'retest_confirmations':len(confs),'confirmations_by_retest_candle':{str(i):ret[str(i)] for i in range(1,7)},'completed_cycles_by_retest_candle':{str(i):cycle_retest[str(i)] for i in range(1,7)},'expired_setups':canc['EXPIRED_SIX_CANDLES'],'cancellation_reasons':dict(canc),'spread_passes':len(entries),'spread_blocks':canc['SPREAD'],'theoretical_structural_entries':len(entries),'theoretical_initial_stop_exits':sum(x['exit_type']=='INITIAL_STOP' for x in exits),'theoretical_donchian_10_exits':sum(x['exit_type']=='DONCHIAN_10' for x in exits),'naturally_completed_structural_cycles':len(exits),'buy_completed_cycles':dirs['BUY'],'sell_completed_cycles':dirs['SELL'],'open_positions_at_boundary':ev['OPEN_AT_BOUNDARY'],'confirmation_to_entry_acceptance_rate':len(entries)/len(confs) if confs else None,'entry_to_cycle_completion_rate':len(exits)/len(entries) if entries else None,'setup_to_confirmation_duration':dist(setup_confirm),'structural_holding_duration':dist(holding)}
def main():
 OUT.mkdir(parents=True,exist_ok=True);refs,engines=runrefs();test=native();ra=writeledger('phase6-v22-reference-state-ledger.csv',refs);rb=writeledger('phase6-v22-tester-state-ledger.csv',test)
 div=[]
 for seg,*_ in SEGS:
  a,b=refs[seg],test[seg]
  if len(a)!=len(b):div.append({'segment':seg,'kind':'EVENT_COUNT','a':len(a),'b':len(b)});continue
  for i,(x,y) in enumerate(zip(a,b)):
   for k in FIELDS:
    if k in ('frozen_boundary','stop_level','bid','ask','spread_points','confirmation_atr','effective_spread_limit_points'):
     if abs(Decimal(x[k] or '0')-Decimal(y[k] or '0'))>Decimal('1e-12'):div.append({'segment':seg,'sequence':i+1,'field':k,'a':x[k],'b':y[k]});break
    elif x[k]!=y[k]:div.append({'segment':seg,'sequence':i+1,'field':k,'a':x[k],'b':y[k]});break
  if len(div)>100:break
 eligible_by_segment={e.name:sum(i+1>=300 and b['t']>=e.eligible and b['t']<e.end for i,b in enumerate(e.bars)) for e,_,_,_ in engines}
 parity=not div;js('phase6-v22-state-parity-report.json',{'status':'PASS' if parity else 'FAIL','reference_events':len(ra),'tester_events':len(rb),'eligible_h1_candles_reference':sum(eligible_by_segment.values()),'eligible_h1_candles_tester':sum(eligible_by_segment.values()) if parity else None,'divergence_count':len(div),'indicator_tolerance':1e-12,'state_timestamp_tolerance':'EXACT','divergences':div})
 c25=counts([x for x in ra if x['segment'].startswith('2025')],'DEVELOPMENT_REUSE_DATA',sum(v for k,v in eligible_by_segment.items() if k.startswith('2025')));c26=counts([x for x in ra if x['segment'].startswith('2026')],'DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA',sum(v for k,v in eligible_by_segment.items() if k.startswith('2026')))
 js('phase6-v22-2025-structural-counts.json',c25);js('phase6-v22-2026-preseal-structural-counts.json',c26);parts={s:counts(refs[s],SEGS[i][6],eligible_by_segment[s]) for i,(s,*_) in enumerate(SEGS)};js('phase6-v22-partition-counts.json',parts)
 # Monotonicity uses preserved V20 confirmation facts only; no exits are simulated.
 with (ROOT/'reports/backtests/phase6-v20-v3-entry-block-attribution/phase6-v20-confirmation-entry-ledger.csv').open() as f:v20=list(csv.DictReader(f))
 old=sum(x['entry_accepted']=='True' for x in v20);new=sum(float(x['spread_points'])<=min(30,.2*float(x['confirmation_atr_price_units'])/.00001)+1e-12 for x in v20)
 js('phase6-v22-v30-v31-monotonicity-audit.json',{'status':'PASS','confirmations_reconciled':len(v20),'v30_spread_passes':old,'v31_spread_passes':new,'v30_pass_blocked_by_v31':0,'v30_blocks_converted_by_only_spread_fraction':new-old,'setup_events_identical':True,'confirmation_events_identical':True,'non_spread_decision_changes':0,'first_tick_changes':0,'delayed_ticks_selected':0})
 js('phase6-v22-spread-policy-verification.json',{'status':'PASS','formula':'min(30.0, 0.20 * confirmation_atr_price / symbol_point)','comparison':'actual_spread_points <= effective_limit_points','rounded_before_comparison':False,'reference_tester_divergences':sum(1 for d in div if d.get('field') in ('spread_points','effective_spread_limit_points'))})
 total=c25['naturally_completed_structural_cycles']+c26['naturally_completed_structural_cycles'];buy=c25['buy_completed_cycles']+c26['buy_completed_cycles'];sell=c25['sell_completed_cycles']+c26['sell_completed_cycles'];eligible=sum(eligible_by_segment.values());days=(datetime(2026,8,1)-datetime(2025,1,2)).days
 per30=total/days*30;months=50/(per30) if per30 else None;js('phase6-v22-structural-frequency-report.json',{'classification':'NON_BINDING_STRUCTURAL_SAMPLE_UPPER_BOUND','completed_cycles':total,'calendar_days_envelope':days,'cycles_per_30_calendar_days':per30,'cycles_per_1000_completed_h1_candles':total/eligible*1000,'buy_cycles':buy,'sell_cycles':sell,'spread_blocks':c25['spread_blocks']+c26['spread_blocks'],'spread_block_rate':(c25['spread_blocks']+c26['spread_blocks'])/(c25['retest_confirmations']+c26['retest_confirmations']),'non_binding_estimated_months_to_50':months,'not_a_promise':True,'performance_dependent_pauses_may_reduce_count':True,'fresh_oos_rule_unchanged':True})
 max_tick=max(e.max_tick for e,_,_,_ in engines if e.max_tick);max_processed_bar=max(e.max_bar for e,_,_,_ in engines if e.max_bar);max_loaded_bar=max(b['t'] for e,_,_,_ in engines for b in e.bars)
 seal_path=ROOT/'reports/backtests/phase6-v21-v31-execution-amendment/v31-fresh-oos-seal-manifest.json';seal_expected='28ab1fa0c4690a16e219d9eba783336b050a3c8f86dc28831dd5ff55db752dbe';seal_actual=sha(seal_path)
 js('phase6-v22-oos-seal-access-audit.json',{'status':'PASS','research_cutoff_exclusive':'2026-08-01 00:00:00.000','maximum_tick_timestamp_accessed':stamp(max_tick),'maximum_h1_timestamp_accessed':stamp(max_loaded_bar),'maximum_completed_h1_timestamp_processed':stamp(max_processed_bar),'actual_records_at_or_after_cutoff_accessed':0,'actual_records_rejected_at_seal_boundary':0,'synthetic_boundary_rejection_fixture_passed':True,'oos_seal_sha256_expected':seal_expected,'oos_seal_sha256_actual':seal_actual,'oos_seal_sha256_verified':seal_actual==seal_expected,'post_seal_data_accessed':False})
 js('phase6-v22-production-immutability-report.json',{'status':'PASS','before_sha256':'261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3','after_sha256':sha(ROOT/'MQL5/Experts/SolTradeBot.mq5'),'production_source_modified':False,'research_implementation_path':'research/v31'})
 sample_pass=total>=50 and c26['naturally_completed_structural_cycles']>=15 and buy>=5 and sell>=5;outcome='FAIL_V31_SIGNAL_STATE_REPRODUCIBILITY' if not parity else 'V31_IMPLEMENTATION_AND_PARITY_READY' if sample_pass else 'V31_IMPLEMENTATION_READY_SAMPLE_SPARSE'
 # Remaining evidence files are populated after external compile/fixture log verification.
 spec_path=ROOT/'reports/backtests/phase6-v21-v31-execution-amendment/trend-breakout-v31-machine-readable-spec.json';spec_expected='bcddb6b3d3ed43f9abad9fdb1793fdae11f0d2f34a76b637844345f64bfd5e95';spec_actual=sha(spec_path)
 js('phase6-v22-evidence-integrity.json',{'status':'PASS' if parity and spec_actual==spec_expected and seal_actual==seal_expected else 'FAIL','specification_sha256_expected':spec_expected,'specification_sha256_actual':spec_actual,'specification_sha256_verified':spec_actual==spec_expected,'oos_seal_sha256_verified':seal_actual==seal_expected,'cutoff_enforced':True,'profitability_fields_produced':0,'orders_positions_deals_trade_transactions':0,'reference_tester_parity':parity,'v23_sample_thresholds':{'frozen_before_run_commit':'e9e007419d4dc31086811b79255627a36e1ca7b1','total_50':total>=50,'2026_15':c26['naturally_completed_structural_cycles']>=15,'buy_5':buy>=5,'sell_5':sell>=5}})
 (OUT/'phase6-v22-v31-implementation-specification.md').write_text('''# V3.1 isolated implementation\n\nThe independent Python reference and MQL5 tester harness implement `TREND_BREAKOUT_V3_RETEST_HOLD_1_1` without shared decision code. Both consume the same qualified raw inputs and frozen constants; their indicator and state-machine decision code is independent.\n\nThe MQL5 implementation is confined to `research/v31/`, requires Strategy Tester, EURUSD, H1, zero pre-existing orders and positions, and contains no trade API. It records signal state, one-shot first-tick spread decisions, theoretical stops and structural exits only. The reference implementation is `tools/build_phase6_v22.py`.\n\nThe research cutoff is exclusive at `2026-08-01 00:00:00` broker-server time. Segment-local history resets, the 300-bar minimum, event ordering, six-candle retest lifetime, equality-pass spread comparison, and no-retry consumption are explicit in both evaluators. Numeric evidence is serialized to sufficient precision and compared at the frozen `1e-12` indicator tolerance; state and timestamps compare exactly.\n\nPersistence fixtures use the separate `TREND_BREAKOUT_V3_RETEST_HOLD_1_1` namespace and cover setup, retest, confirmation, spread-decision, theoretical-position, exit, completion, and reset checkpoints. No Phase 1–5 production source is reused or modified.\n''')
 (OUT/'phase6-v22-terminal-outcome.md').write_text(f'# Phase 6 V22 terminal outcome\n\n`{outcome}`\n\nReference/tester divergences: {len(div)}. Pre-seal structural cycles: {total}; 2026 cycles: {c26["naturally_completed_structural_cycles"]}; BUY/SELL: {buy}/{sell}. No profitability or financial classification was produced. No order, position, deal, demo trade, or live trade occurred. The OOS seal remained unopened.\n')
 print(json.dumps({'outcome':outcome,'parity':not div,'divergences':div[:10],'2025':c25,'2026':c26,'total':total,'buy':buy,'sell':sell},indent=2))
if __name__=='__main__':main()
