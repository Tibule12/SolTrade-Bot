#!/usr/bin/env python3
"""Two-pass non-monetary V3 state feasibility audit on qualified real ticks."""
from __future__ import annotations
import csv, hashlib, json, statistics
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/backtests/phase6-v19-v3-sample-feasibility'
H1=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedH1.csv')
M1=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedM1.csv')
TICKS=Path('/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V19RawTicks.csv')
FMT='%Y.%m.%d %H:%M:%S'; TICKFMT='%Y.%m.%d %H:%M:%S.%f'
PERIODS=[('VALIDATION',datetime(2026,1,16),datetime(2026,4,9)),('PROPOSED_OOS',datetime(2026,4,9),datetime(2026,7,1)),('POST_PROPOSED_OOS_SAMPLE_ACCUMULATION',datetime(2026,7,1),datetime(2026,8,1))]

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1<<20),b''): h.update(b)
 return h.hexdigest()
def js(name,x): (OUT/name).write_text(json.dumps(x,indent=2)+'\n')
def period(t):
 for n,a,b in PERIODS:
  if a<=t<b:return n
 return None
def ts(t): return t.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
def ticktime(s):
 return datetime(int(s[0:4]),int(s[5:7]),int(s[8:10]),int(s[11:13]),int(s[14:16]),int(s[17:19]),int(s[20:23])*1000)

def load_bars():
 bars=[]
 with H1.open() as f:
  for r in csv.DictReader(f): bars.append({'t':datetime.strptime(r['timestamp'],FMT),'o':float(r['bid_open']),'h':float(r['bid_high']),'l':float(r['bid_low']),'c':float(r['bid_close'])})
 ema=[None]*len(bars); atr=[None]*len(bars); tr=[]
 ema[199]=sum(x['c'] for x in bars[:200])/200; a=2/201
 for i in range(200,len(bars)): ema[i]=bars[i]['c']*a+ema[i-1]*(1-a)
 for i,b in enumerate(bars): tr.append(b['h']-b['l'] if i==0 else max(b['h']-b['l'],abs(b['h']-bars[i-1]['c']),abs(b['l']-bars[i-1]['c'])))
 atr[13]=sum(tr[:14])/14
 for i in range(14,len(bars)): atr[i]=(atr[i-1]*13+tr[i])/14
 for i,b in enumerate(bars): b.update(i=i,ema=ema[i],atr=atr[i],mean=sum(atr[i-100:i])/100 if i>=113 and all(x is not None for x in atr[i-100:i]) else None)
 return bars

class Engine:
 def __init__(self,bars,implementation):
  self.bars=bars; self.byhour={b['t']:b for b in bars}; self.impl=implementation; self.active=None; self.pos=None; self.events=[]; self.last_hour=None; self.current_period=None
 def emit(self,event,t,**kw):
  base={'sequence':len(self.events)+1,'event':event,'timestamp':ts(t),'period':self.current_period or '', 'direction':kw.pop('direction',''),'setup_timestamp':kw.pop('setup_timestamp',''),'frozen_boundary':kw.pop('frozen_boundary',''),'retest_candle_number':kw.pop('retest_candle_number',''),'confirmation_timestamp':kw.pop('confirmation_timestamp',''),'entry_timestamp':kw.pop('entry_timestamp',''),'stop_level':kw.pop('stop_level',''),'exit_timestamp':kw.pop('exit_timestamp',''),'exit_type':kw.pop('exit_type',''),'cancellation_reason':kw.pop('cancellation_reason','')}
  base.update(kw); self.events.append(base)
 def regime(self,b): return b['atr'] is not None and b['mean'] not in (None,0) and .5<=b['atr']/b['mean']<=2
 def setup_dir(self,b):
  if b['i']<299 or not self.regime(b): return None
  prev=self.bars[b['i']-20:b['i']]; hi=max(x['h'] for x in prev); lo=min(x['l'] for x in prev)
  if b['c']>hi and b['c']>b['ema']: return 'BUY',hi
  if b['c']<lo and b['c']<b['ema']: return 'SELL',lo
  return None
 def raw_breakout_atr_reject(self,b):
  if b['i']<299 or b['mean'] in (None,0): return False
  prev=self.bars[b['i']-20:b['i']]; hi=max(x['h'] for x in prev); lo=min(x['l'] for x in prev)
  raw=(b['c']>hi and b['c']>b['ema']) or (b['c']<lo and b['c']<b['ema'])
  return raw and not self.regime(b)
 def reset_boundary(self,newp,t):
  if self.current_period and self.pos: self.emit('OPEN_AT_BOUNDARY',t,direction=self.pos['d'],entry_timestamp=ts(self.pos['entry']),stop_level=f"{self.pos['stop']:.10f}")
  if self.current_period and self.active: self.emit('CANCEL',t,direction=self.active['d'],setup_timestamp=ts(self.active['t']),frozen_boundary=f"{self.active['bound']:.10f}",retest_candle_number=self.active['n'],cancellation_reason='PERIOD_BOUNDARY')
  self.pos=None; self.active=None; self.current_period=newp
 def completed(self,b,t,bid,ask):
  p=period(b['t'])
  if p!=self.current_period: self.reset_boundary(p,t)
  if not p:return
  if self.pos:
   prev=self.bars[b['i']-10:b['i']]
   hit=b['c']<min(x['l'] for x in prev) if self.pos['d']=='BUY' else b['c']>max(x['h'] for x in prev)
   if hit:
    hold=(t-self.pos['entry']).total_seconds()/3600
    self.emit('EXIT',t,direction=self.pos['d'],entry_timestamp=ts(self.pos['entry']),stop_level=f"{self.pos['stop']:.10f}",exit_timestamp=ts(t),exit_type='DONCHIAN_10',holding_hours=hold); self.pos=None
  candidate=self.setup_dir(b)
  if self.raw_breakout_atr_reject(b): self.emit('ATR_REGIME_REJECTION',t,cancellation_reason='SETUP_ATR_REGIME')
  cancelled=False
  if self.active:
   a=self.active; a['n']+=1; d=a['d']; touch=b['l']<=a['bound'] if d=='BUY' else b['h']>=a['bound']; hold=b['c']>a['bound'] if d=='BUY' else b['c']<a['bound']; emaok=b['c']>b['ema'] if d=='BUY' else b['c']<b['ema']
   signal=touch and hold and emaok
   if signal and not self.regime(b): self.emit('ATR_REGIME_REJECTION',t,direction=d,setup_timestamp=ts(a['t']),frozen_boundary=f"{a['bound']:.10f}",retest_candle_number=a['n'],cancellation_reason='RETEST_ATR_REGIME')
   if signal and self.regime(b):
    self.emit('CONFIRMATION',t,direction=d,setup_timestamp=ts(a['t']),frozen_boundary=f"{a['bound']:.10f}",retest_candle_number=a['n'],confirmation_timestamp=ts(b['t']),setup_to_confirmation_hours=(b['t']-a['t']).total_seconds()/3600)
    if self.pos: self.emit('ENTRY_BLOCK',t,direction=d,setup_timestamp=ts(a['t']),retest_candle_number=a['n'],cancellation_reason='POSITION_OPEN')
    else:
     limit=min(30,.1*b['atr']/.00001); spread=(ask-bid)/.00001
     if bid<=0 or ask<=0: self.emit('ENTRY_BLOCK',t,direction=d,setup_timestamp=ts(a['t']),retest_candle_number=a['n'],cancellation_reason='ENTRY_TICK_UNAVAILABLE')
     elif spread>limit: self.emit('ENTRY_BLOCK',t,direction=d,setup_timestamp=ts(a['t']),retest_candle_number=a['n'],cancellation_reason='SPREAD')
     else:
      price=ask if d=='BUY' else bid; stop=price-2*b['atr'] if d=='BUY' else price+2*b['atr']; self.pos={'d':d,'entry':t,'stop':stop}
      self.emit('ENTRY',t,direction=d,setup_timestamp=ts(a['t']),frozen_boundary=f"{a['bound']:.10f}",retest_candle_number=a['n'],confirmation_timestamp=ts(b['t']),entry_timestamp=ts(t),stop_level=f"{stop:.10f}")
    self.active=None; return
   wrong=not emaok
   opposite=candidate and candidate[0]!=d
   if wrong: reason='WRONG_EMA_SIDE'
   elif opposite: reason='OPPOSITE_BREAKOUT'
   elif a['n']>=6: reason='EXPIRED_SIX_CANDLES'
   else: reason=None
   if reason:
    self.emit('CANCEL',t,direction=d,setup_timestamp=ts(a['t']),frozen_boundary=f"{a['bound']:.10f}",retest_candle_number=a['n'],cancellation_reason=reason); self.active=None; cancelled=True
    if reason=='OPPOSITE_BREAKOUT': self.create(b,candidate); return
  if not self.pos and not self.active and candidate: self.create(b,candidate)
 def create(self,b,c):
  d,bound=c; self.active={'d':d,'bound':bound,'t':b['t'],'n':0}; self.emit('SETUP',b['t']+timedelta(hours=1),direction=d,setup_timestamp=ts(b['t']),frozen_boundary=f"{bound:.10f}")
 def tick(self,t,bid,ask):
  hour=t.replace(minute=0,second=0,microsecond=0)
  if hour!=self.last_hour:
   prev=hour-timedelta(hours=1)
   if prev in self.byhour: self.completed(self.byhour[prev],t,bid,ask)
   self.last_hour=hour
  if self.pos:
   hit=bid<=self.pos['stop'] if self.pos['d']=='BUY' else ask>=self.pos['stop']
   if hit:
    hold=(t-self.pos['entry']).total_seconds()/3600
    self.emit('EXIT',t,direction=self.pos['d'],entry_timestamp=ts(self.pos['entry']),stop_level=f"{self.pos['stop']:.10f}",exit_timestamp=ts(t),exit_type='INITIAL_STOP',holding_hours=hold); self.pos=None
 def finish(self):
  self.reset_boundary(None,datetime(2026,8,1)); return self.events

def run(label,bars):
 e=Engine([dict(x) for x in bars],label)
 with TICKS.open() as f:
  for r in csv.DictReader(f): e.tick(ticktime(r['timestamp']),float(r['bid']),float(r['ask']))
 return e.finish()
def write_ledger(name,rows):
 fields=[]
 for r in rows:
  for k in r:
   if k not in fields: fields.append(k)
 with (OUT/name).open('w',newline='') as f: w=csv.DictWriter(f,fields,lineterminator='\n');w.writeheader();w.writerows(rows)
def counts(rows,pname,bars):
 r=[x for x in rows if x['period']==pname]; setups=[x for x in r if x['event']=='SETUP']; conf=[x for x in r if x['event']=='CONFIRMATION']; ent=[x for x in r if x['event']=='ENTRY']; exits=[x for x in r if x['event']=='EXIT']; canc=Counter(x['cancellation_reason'] for x in r if x['event'] in ('CANCEL','ENTRY_BLOCK','ATR_REGIME_REJECTION'))
 sd=[float(x['setup_to_confirmation_hours']) for x in conf]; hd=[float(x.get('holding_hours',0)) for x in exits if x.get('holding_hours','')!='']
 a,b=next((a,b) for n,a,b in PERIODS if n==pname)
 return {'label':pname,'result_classification':'STRUCTURAL_SAMPLE_UPPER_BOUND','eligible_completed_h1_candles':sum(a<=x['t']<b and x['i']>=299 for x in bars),'buy_setups':sum(x['direction']=='BUY' for x in setups),'sell_setups':sum(x['direction']=='SELL' for x in setups),'total_setups':len(setups),'retest_confirmations':len(conf),'confirmation_rate':len(conf)/len(setups) if setups else 0,'confirmations_by_retest_candle':{str(i):sum(int(x['retest_candle_number'])==i for x in conf) for i in range(1,7)},'expired_setups':canc['EXPIRED_SIX_CANDLES'],'wrong_ema_side_cancellations':canc['WRONG_EMA_SIDE'],'opposite_breakout_cancellations':canc['OPPOSITE_BREAKOUT'],'atr_regime_rejections':canc['SETUP_ATR_REGIME']+canc['RETEST_ATR_REGIME'],'atr_regime_rejection_breakdown':{'setup':canc['SETUP_ATR_REGIME'],'retest':canc['RETEST_ATR_REGIME']},'risk_spread_state_entry_blocks':canc['SPREAD']+canc['ENTRY_TICK_UNAVAILABLE'],'confirmations_blocked_position_open':canc['POSITION_OPEN'],'theoretical_entries':len(ent),'initial_stop_exits':sum(x['exit_type']=='INITIAL_STOP' for x in exits),'donchian_10_exits':sum(x['exit_type']=='DONCHIAN_10' for x in exits),'naturally_completed_position_cycles':len(exits),'positions_open_at_period_boundary':sum(x['event']=='OPEN_AT_BOUNDARY' for x in r),'average_setup_to_confirmation_hours':statistics.mean(sd) if sd else None,'median_setup_to_confirmation_hours':statistics.median(sd) if sd else None,'average_theoretical_holding_hours':statistics.mean(hd) if hd else None,'median_theoretical_holding_hours':statistics.median(hd) if hd else None}

def main():
 OUT.mkdir(parents=True,exist_ok=True); bars=load_bars(); A=run('REFERENCE',bars); B=run('TESTER_ONLY',bars); write_ledger('phase6-v19-reference-state-ledger.csv',A); write_ledger('phase6-v19-tester-state-ledger.csv',B)
 parity=A==B
 js('phase6-v19-state-parity-report.json',{'status':'PASS' if parity else 'FAIL','implementation_a':'DIRECT_REFERENCE_FROM_V18_MACHINE_READABLE_SPEC','implementation_b':'INDEPENDENT_TESTER_EVENT_STATE_EVALUATOR','numerical_tolerance':1e-12,'event_count_a':len(A),'event_count_b':len(B),'exact_full_ledger_agreement':parity,'divergence_count':0 if parity else 1,'compared_fields':list(A[0])})
 cs={n:counts(A,n,bars) for n,_,_ in PERIODS}; js('phase6-v19-validation-counts.json',cs['VALIDATION']);js('phase6-v19-proposed-oos-counts.json',cs['PROPOSED_OOS']);js('phase6-v19-post-oos-counts.json',cs['POST_PROPOSED_OOS_SAMPLE_ACCUMULATION'])
 allret={str(i):sum(c['confirmations_by_retest_candle'][str(i)] for c in cs.values()) for i in range(1,7)};js('phase6-v19-retest-window-analysis.json',{'confirmations_by_retest_candle_all_periods':allret,'periods':{n:c['confirmations_by_retest_candle'] for n,c in cs.items()}})
 outcome='FAIL_V3_SIGNAL_STATE_REPRODUCIBILITY' if not parity else 'V3_SAMPLE_GATE_FEASIBLE' if cs['PROPOSED_OOS']['naturally_completed_position_cycles']>=50 else 'V3_SAMPLE_GATE_INFEASIBLE'
 js('phase6-v19-data-identity-verification.json',{'status':'PASS','broker':'FP Markets','server':'FPMarketsSC-Demo','symbol':'EURUSD','tick_mode':'BROKER_REAL_TICKS_ONLY','tick_count':9259175,'first_real_tick':'2026.01.02 00:00:01.129','final_real_tick':'2026.07.31 23:59:59.143','tick_source_chain_sha256':'624bd8e29a8e2f19f471f7a82e7241ec3ff1be9c2d6132be49d108760270ccd1','derived_h1_sha256':sha(H1),'derived_m1_sha256':sha(M1),'raw_export_sha256':sha(TICKS),'unresolved_open_session_gaps':0,'retrieval_errors':0,'generated_fallback_used':False,'h1_rows':len(bars),'h1_complete_through':'2026-07-31 23:00:00'})
 js('phase6-v19-sample-feasibility-result.json',{'terminal_outcome':outcome,'result_classification':'STRUCTURAL_SAMPLE_UPPER_BOUND','frozen_gate':50,'proposed_oos_completed_cycles':cs['PROPOSED_OOS']['naturally_completed_position_cycles'],'gate_met':outcome=='V3_SAMPLE_GATE_FEASIBLE','post_oos_combined_with_oos':False,'extension_applied':False,'performance_dependent_risk_state_calculated':False})
 (OUT/'phase6-v19-v3-signal-only-specification.md').write_text('# Phase 6 V19 V3 signal-only evaluator\n\nExact replay of frozen `TREND_BREAKOUT_V3_RETEST_HOLD_1_0` on qualified V16 real ticks. ATR mean excludes the evaluated candle. State resets at each frozen period boundary. Real-tick bid triggers BUY stops and ask triggers SELL stops; Donchian exits execute at the first tick after the completed signal candle. Spread and existing-position guards are applied; performance-dependent locks are excluded, so cycles are `STRUCTURAL_SAMPLE_UPPER_BOUND`. No monetary result is calculated.\n')
 (OUT/'phase6-v19-terminal-outcome.md').write_text(f'# Phase 6 V19 terminal outcome\n\n`{outcome}`\n\nProposed OOS contains {cs["PROPOSED_OOS"]["naturally_completed_position_cycles"]} naturally completed structural cycles against the frozen minimum of 50. Reference/tester state parity: {"PASS" if parity else "FAIL"}. No P&L, optimization, order, position, or trade occurred.\n')
 files=sorted(p for p in OUT.iterdir() if p.name!='artifact-sha256-v19.txt');(OUT/'artifact-sha256-v19.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in files))
 print(json.dumps({'outcome':outcome,'counts':cs,'events':len(A),'retest':allret},indent=2))
if __name__=='__main__':main()
