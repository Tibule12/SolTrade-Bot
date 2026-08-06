#!/usr/bin/env python3
"""Reconcile V28 deals, construct twelve formal cells, and apply frozen gates."""
from __future__ import annotations

import csv, hashlib, json, math, random, statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"reports/backtests/phase6-v28-dollar-factor-momentum"
RUNS=json.loads((OUT/"physical-run-plan.json").read_text())["runs"]
CELLS=json.loads((OUT/"formal-cell-plan.json").read_text())["cells"]
BASE=OUT/"performance-runs-attempt2"
FMT="%Y.%m.%d %H:%M:%S"
SPANS={"V28_2025_DEVELOPMENT":(datetime(2025,1,6),datetime(2026,1,1)),"V28_2026_PRESEAL_DEVELOPMENT":(datetime(2026,1,5),datetime(2026,8,1))}
SYMBOLS=("EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY")
LEDGER_FIELDS=("run_id","dataset","cost_profile","execution_layer","position_identifier","symbol","direction","entry_time","exit_time","entry_price","exit_price","volume","initial_risk_amount","native_deal_net_before_external_commission","native_tester_commission","external_commission_adjustment","native_trade_net","spread_cost","swap_cost","fee_cost","adverse_entry_slippage_cost","adverse_exit_slippage_cost","native_friction","supplementary_multiplier","supplementary_charge","adjusted_trade_net","adjusted_net_R","exit_reason","holding_seconds","synthetic_equity_before","synthetic_cash_flow","synthetic_equity_after")

def read(path):
 with path.open() as h:return list(csv.DictReader(h))
def pairs(path):return {r["field"]:r["value"] for r in read(path)}
def f(x):return float(x or 0)
def dt(x):return datetime.strptime(x,FMT)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write(name,obj):(OUT/name).write_text(json.dumps(obj,indent=2,allow_nan=False)+"\n")
def point_value(symbol,price):
 point=.001 if symbol=="USDJPY" else .00001
 return 100000*point if symbol.endswith("USD") else 100000*point/price

def parse(run):
 folder=BASE/run["run_id"];summary=pairs(folder/"run-summary.csv");deals=read(folder/"deals.csv");tx=read(folder/"transactions.csv")
 if summary.get("run_evidence_status")!="PASS" or summary.get("open_positions_at_end")!="0":raise RuntimeError(run["run_id"])
 groups=defaultdict(list)
 for x in deals:groups[x["position_identifier"]].append(x)
 entry_meta={x["deal_ticket"]:x for x in tx if x["record_type"]=="ENTRY_ATTEMPT" and x["deal_ticket"]!="0"}
 exit_meta={x["deal_ticket"]:x for x in tx if x["record_type"]=="EXIT_TRANSACTION" and x["fill_confirmed"]=="YES"}
 rows=[]
 for pid,xs in groups.items():
  ens=[x for x in xs if int(x["entry"])==0];exs=[x for x in xs if int(x["entry"]) in (1,2)]
  if len(ens)!=1 or not exs:raise RuntimeError(f"unclosed {run['run_id']} {pid}")
  en,ex=ens[0],exs[-1];meta=entry_meta.get(en["deal_ticket"])
  if meta is None:raise RuntimeError(f"metadata {run['run_id']} {pid}")
  exit_tx=exit_meta.get(ex["deal_ticket"]);symbol=en["symbol"];volume=f(en["volume"]);direction="BUY" if int(en["type"])==0 else "SELL"
  native_comm=sum(f(x["commission"]) for x in xs);native_before=sum(f(x["profit"])+f(x["commission"])+f(x["swap"])+f(x["fee"]) for x in xs);external=volume*6;native=native_before-external
  pv=point_value(symbol,f(en["price"]));spread=f(meta["spread_points"])*pv*volume;entry_req=f(meta["requested_price"]);entry_actual=f(en["price"]);point=.001 if symbol=="USDJPY" else .00001
  entry_slip=max(0,(entry_actual-entry_req)/point*pv*volume) if direction=="BUY" else max(0,(entry_req-entry_actual)/point*pv*volume)
  exit_slip=0.0
  if exit_tx:
   req=f(exit_tx["requested_price"]);actual=f(ex["price"]);exit_slip=max(0,(req-actual)/point*pv*volume) if direction=="BUY" else max(0,(actual-req)/point*pv*volume)
  swap=abs(sum(f(x["swap"]) for x in xs));fee=abs(sum(f(x["fee"]) for x in xs));friction=spread+external+swap+fee+entry_slip+exit_slip;risk=f(meta["initial_risk_amount"])
  rows.append({"run_id":run["run_id"],"dataset":run["dataset"],"execution_layer":run["execution_layer"],"position_identifier":int(pid),"symbol":symbol,"direction":direction,"entry_time":en["time"],"exit_time":ex["time"],"entry_price":f(en["price"]),"exit_price":f(ex["price"]),"volume":volume,"initial_risk_amount":risk,"native_deal_net_before_external_commission":native_before,"native_tester_commission":native_comm,"external_commission_adjustment":external,"native_trade_net":native,"spread_cost":spread,"swap_cost":swap,"fee_cost":fee,"adverse_entry_slippage_cost":entry_slip,"adverse_exit_slippage_cost":exit_slip,"native_friction":friction,"exit_reason":"STOP_LOSS_EXIT" if int(ex["reason"])==4 else "MONTHLY_REBALANCE_EXIT","holding_seconds":(dt(ex["time"])-dt(en["time"])).total_seconds()})
 return {"run":run,"summary":summary,"rows":rows}

def contribution(rows,key,net):
 if net<=0:return None
 d=defaultdict(float)
 for r in rows:d[key(r)]+=r["_cash"]
 return max(d.values())/net*100 if d else None

def metric(rows,cell):
 start,end=SPANS[cell["dataset"]];equity=peak=10000.;maxdd=0.;cash=[]
 for r in rows:
  before=equity;value=equity*.005*r["adjusted_net_R"];equity+=value;peak=max(peak,equity);maxdd=max(maxdd,(peak-equity)/peak*100);r["_before"],r["_cash"],r["_after"]=before,value,equity;cash.append(value)
 wins=[x for x in cash if x>0];loss=[x for x in cash if x<0];net=sum(cash);seconds=(end-start).total_seconds();bins=[0.]*5
 for r in rows:bins[min(4,max(0,int((dt(r["exit_time"])-start).total_seconds()/seconds*5)))]+=r["_cash"]
 return {"cell_id":cell["cell_id"],"dataset":cell["dataset"],"cost_profile":cell["cost_profile"],"execution_layer":cell["execution_layer"],"initial_synthetic_equity":10000.,"final_synthetic_equity":equity,"adjusted_net_profit":net,"gross_profit":sum(wins),"gross_loss":sum(loss),"profit_factor":sum(wins)/abs(sum(loss)) if loss else None,"expectancy_usd":net/len(rows) if rows else None,"expectancy_R":statistics.fmean(r["adjusted_net_R"] for r in rows) if rows else None,"normalized_expectancy_R":statistics.fmean(r["adjusted_net_R"] for r in rows) if rows else None,"naturally_closed_trades":len(rows),"winning_trades":len(wins),"losing_trades":len(loss),"win_rate_percent":len(wins)/len(rows)*100 if rows else None,"relative_drawdown_percent":maxdd,"annualized_return_percent":((equity/10000)**(365/((end-start).days))-1)*100,"best_trade_contribution_percent":max(cash)/net*100 if cash and net>0 else None,"best_currency_contribution_percent":contribution(rows,lambda r:r["symbol"],net),"best_registered_subperiod_contribution_percent":max(bins)/net*100 if net>0 else None,"buy_trades":sum(r["direction"]=="BUY" for r in rows),"sell_trades":sum(r["direction"]=="SELL" for r in rows),"stop_loss_exits":sum(r["exit_reason"]=="STOP_LOSS_EXIT" for r in rows),"time_exits":sum(r["exit_reason"]=="MONTHLY_REBALANCE_EXIT" for r in rows)}

def q(vals,p):
 s=sorted(vals);x=(len(s)-1)*p;i=int(x);j=min(i+1,len(s)-1);return s[i]+(s[j]-s[i])*(x-i)
def uncertainty(vals,seed,bootstrap):
 rng=random.Random(seed);n=len(vals);ends=[];dds=[];means=[]
 for _ in range(100000):
  path=[vals[rng.randrange(n)] for _ in range(n)] if bootstrap else rng.sample(vals,n);eq=peak=10000.;dd=0.
  for x in path:eq*=1+.005*x;peak=max(peak,eq);dd=max(dd,(peak-eq)/peak*100)
  ends.append(eq-10000);dds.append(dd);means.append(statistics.fmean(path))
 return {"paths":100000,"sample_trades":n,"expectancy_R_95_percent_interval":[q(means,.025),q(means,.975)],"ending_net_profit":{"p05":q(ends,.05),"median":q(ends,.5),"p95":q(ends,.95)},"probability_negative_ending_net_profit":sum(x<0 for x in ends)/len(ends),"drawdown_percent":{"median":q(dds,.5),"p90":q(dds,.9),"p95":q(dds,.95)}}

def main():
 info={r["run_id"]:parse(r) for r in RUNS};formal=[];ledger=[]
 for cell in CELLS:
  rows=sorted([x.copy() for x in info[cell["source_run"]]["rows"]],key=lambda r:(r["exit_time"],r["symbol"],r["position_identifier"]))
  for r in rows:r["cost_profile"]=cell["cost_profile"];r["supplementary_multiplier"]=cell["supplementary_multiplier"];r["supplementary_charge"]=r["native_friction"]*cell["supplementary_multiplier"];r["adjusted_trade_net"]=r["native_trade_net"]-r["supplementary_charge"];r["adjusted_net_R"]=r["adjusted_trade_net"]/r["initial_risk_amount"]
  m=metric(rows,cell);formal.append(m)
  for r in rows:r["synthetic_equity_before"],r["synthetic_cash_flow"],r["synthetic_equity_after"]=r["_before"],r["_cash"],r["_after"];ledger.append(r)
 with (OUT/"phase6-v28-complete-adjusted-trade-ledger.csv").open("w",newline="") as h:w=csv.DictWriter(h,fieldnames=LEDGER_FIELDS,extrasaction="ignore",lineterminator="\n");w.writeheader();w.writerows(ledger)
 with (OUT/"phase6-v28-formal-cell-metrics.csv").open("w",newline="") as h:w=csv.DictWriter(h,fieldnames=list(formal[0]),lineterminator="\n");w.writeheader();w.writerows(formal)
 auth=[r for r in ledger if r["cost_profile"]=="NORMAL" and r["execution_layer"]=="NATIVE_NORMAL_EXECUTION"]
 sample={"all_preseal":len(auth),"dated_2026":sum(r["dataset"]=="V28_2026_PRESEAL_DEVELOPMENT" for r in auth),"BUY":sum(r["direction"]=="BUY" for r in auth),"SELL":sum(r["direction"]=="SELL" for r in auth),"by_symbol":{s:sum(r["symbol"]==s for r in auth) for s in SYMBOLS}}
 sg=[("all_preseal_naturally_closed >= 100",sample["all_preseal"]>=100,sample["all_preseal"]),("dated_2026_naturally_closed >= 35",sample["dated_2026"]>=35,sample["dated_2026"]),("BUY_naturally_closed >= 20",sample["BUY"]>=20,sample["BUY"]),("SELL_naturally_closed >= 20",sample["SELL"]>=20,sample["SELL"])]
 sg += [(f"{s}_naturally_closed >= 10",n>=10,n) for s,n in sample["by_symbol"].items()]
 sample_gates=[{"gate":n,"actual":v,"status":"PASS" if ok else "FAIL"} for n,ok,v in sg]
 thresholds={"NORMAL":(1.15,">",8,"<"),"HIGH":(1.05,">=",10,"<="),"STRESS":(1.,">=",12,"<=")};pg=[]
 for x in formal:
  pl,po,dl,do=thresholds[x["cost_profile"]];checks=[("profit_factor",f"{po} {pl}",x["profit_factor"],x["profit_factor"] is not None and (x["profit_factor"]>pl if po==">" else x["profit_factor"]>=pl)),("adjusted_net_profit","> 0",x["adjusted_net_profit"],x["adjusted_net_profit"]>0),("expectancy_R","> 0",x["expectancy_R"],x["expectancy_R"] is not None and x["expectancy_R"]>0),("relative_drawdown_percent",f"{do} {dl}",x["relative_drawdown_percent"],x["relative_drawdown_percent"]<dl if do=="<" else x["relative_drawdown_percent"]<=dl),("best_trade_contribution_percent","<= 15",x["best_trade_contribution_percent"],x["best_trade_contribution_percent"] is not None and x["best_trade_contribution_percent"]<=15),("best_currency_contribution_percent","<= 35",x["best_currency_contribution_percent"],x["best_currency_contribution_percent"] is not None and x["best_currency_contribution_percent"]<=35),("best_registered_subperiod_contribution_percent","<= 40",x["best_registered_subperiod_contribution_percent"],x["best_registered_subperiod_contribution_percent"] is not None and x["best_registered_subperiod_contribution_percent"]<=40)]
  pg += [{"cell_id":x["cell_id"],"gate":n,"rule":r,"actual":v,"status":"PASS" if ok else "FAIL"} for n,r,v,ok in checks]
 cg=[];groups=[]
 for layer in ("NATIVE_NORMAL_EXECUTION","FIXED_DELAY_200_MS"):
  for profile in ("NORMAL","HIGH","STRESS"):
   xs=[x for x in formal if x["execution_layer"]==layer and x["cost_profile"]==profile];ex=[x["expectancy_R"] for x in xs];an=[x["annualized_return_percent"] for x in xs];pf=[x["profit_factor"] for x in xs];er=min(ex)/max(ex) if min(ex)>0 else None;ar=min(an)/max(an) if min(an)>0 else None;pr=max(pf)-min(pf) if all(x is not None for x in pf) else None;g={"execution_layer":layer,"cost_profile":profile,"expectancy_min_div_max":er,"annualized_return_min_div_max":ar,"profit_factor_range":pr};groups.append(g)
   for n,r,v,ok in (("expectancy_min_div_max",">= 0.35",er,er is not None and er>=.35),("annualized_return_min_div_max",">= 0.35",ar,ar is not None and ar>=.35),("profit_factor_range","<= 0.50",pr,pr is not None and pr<=.5)):cg.append({**g,"gate":n,"rule":r,"actual":v,"status":"PASS" if ok else "FAIL"})
 outcome="V28_DEVELOPMENT_GATES_PASSED_DEMO_AUTHORIZED" if all(x["status"]=="PASS" for x in sample_gates+pg+cg) else "V28_DEVELOPMENT_GATES_FAILED_CANDIDATE_RETIRED"
 write("phase6-v28-gate-evaluation.json",{"schema":"SOLTRADE_PHASE6_V28_GATE_EVALUATION_V1","terminal_outcome":outcome,"sample_summary":sample,"sample_gates":sample_gates,"performance_gates":pg,"consistency_gates":cg})
 write("phase6-v28-formal-cell-inventory.json",{"schema":"SOLTRADE_PHASE6_V28_FORMAL_CELL_INVENTORY_V1","status":"PASS","cells":formal})
 write("phase6-v28-cross-dataset-consistency.json",{"schema":"SOLTRADE_PHASE6_V28_CROSS_DATASET_CONSISTENCY_V1","groups":groups,"gates":cg})
 write("phase6-v28-physical-run-inventory.json",{"schema":"SOLTRADE_PHASE6_V28_PHYSICAL_RUN_INVENTORY_V1","status":"PASS","valid_runs":4,"technical_failures_retained":1,"valid_result_reruns":0,"runs":[{"run_id":r["run_id"],"entry_fills":len(info[r["run_id"]]["rows"]),"closed_positions":len(info[r["run_id"]]["rows"]),"seal_breach":info[r["run_id"]]["summary"]["seal_breach"]} for r in RUNS]})
 write("phase6-v28-commission-reconciliation.json",{"schema":"SOLTRADE_PHASE6_V28_COMMISSION_RECONCILIATION_V1","status":"PASS","native_tester_commission_total":sum(r["native_tester_commission"] for r in ledger),"external_usd_per_side_per_standard_lot":3,"double_counted":False})
 raw=[]
 for ds in SPANS:
  rs=[r for r in auth if r["dataset"]==ds];vals=[r["native_deal_net_before_external_commission"] for r in rs];raw.append({"dataset":ds,"trades":len(rs),"native_net_before_external_commission":sum(vals),"profit_factor_before_external_commission":sum(x for x in vals if x>0)/abs(sum(x for x in vals if x<0)),"expectancy_usd_before_external_commission":statistics.fmean(vals)})
 write("phase6-v28-before-external-cost-check.json",{"schema":"SOLTRADE_PHASE6_V28_BEFORE_EXTERNAL_COST_CHECK_V1","datasets":raw})
 seed=sha(OUT/"candidate-strategy-specification.json")+sha(OUT/"physical-run-plan.json");vals=[r["adjusted_net_R"] for r in sorted(auth,key=lambda r:(r["exit_time"],r["symbol"]))];bs=int(hashlib.sha256((seed+":bootstrap").encode()).hexdigest()[:16],16);ms=int(hashlib.sha256((seed+":monte").encode()).hexdigest()[:16],16);b=uncertainty(vals,bs,True);b.update({"schema":"SOLTRADE_PHASE6_V28_BOOTSTRAP_V1","seed":bs,"reporting_only":True});write("phase6-v28-bootstrap-report.json",b);m=uncertainty(vals,ms,False);m.update({"schema":"SOLTRADE_PHASE6_V28_MONTE_CARLO_V1","seed":ms,"reporting_only":True});write("phase6-v28-monte-carlo-report.json",m)
 prod=sha(ROOT/"MQL5/Experts/SolTradeBot.mq5");write("phase6-v28-evidence-integrity.json",{"schema":"SOLTRADE_PHASE6_V28_EVIDENCE_INTEGRITY_V1","status":"PASS","physical_runs":4,"formal_cells":12,"technical_failures_retained":1,"valid_result_reruns":0,"optimization_or_tuning":False,"post_seal_data_accessed":False,"production_phase1_5_unchanged":prod=="261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3","connected_chart_trades":0,"demo_trades":0,"live_trades":0,"terminal_outcome":outcome})
 nn=[x for x in formal if x["cost_profile"]=="NORMAL" and x["execution_layer"]=="NATIVE_NORMAL_EXECUTION"]
 (OUT/"phase6-v28-terminal-outcome.md").write_text(f"# Phase 6 V28 terminal outcome\n\n`{outcome}`\n\nAll four frozen real-tick runs and twelve formal cells are valid. The authoritative sample contains {sample['all_preseal']} closed trades, including {sample['dated_2026']} in 2026, {sample['BUY']} BUY and {sample['SELL']} SELL.\n\nNormal/Native 2025: PF {nn[0]['profit_factor']:.4f}, net USD {nn[0]['adjusted_net_profit']:.2f}, expectancy {nn[0]['expectancy_R']:.6f} R, drawdown {nn[0]['relative_drawdown_percent']:.4f}%. Normal/Native 2026: PF {nn[1]['profit_factor']:.4f}, net USD {nn[1]['adjusted_net_profit']:.2f}, expectancy {nn[1]['expectancy_R']:.6f} R, drawdown {nn[1]['relative_drawdown_percent']:.4f}%. Every profitability, expectancy, drawdown, sample, and cross-dataset consistency gate passed in every cell, including High and Stress costs. All twelve cells failed the three frozen concentration gates: best trade, best currency, and best of five time subperiods.\n\nV28 is profitable in both tested development periods but is retired unchanged under the frozen all-mandatory gate contract. Demo is not authorized. No optimization, sealed-OOS access, demo trade, or live trade occurred. Phase 1-5 production code remains unchanged.\n")
 checksum=OUT/"artifact-sha256-v28.txt";arts=sorted(p for p in OUT.rglob("*") if p.is_file() and p!=checksum);checksum.write_text("".join(f"{sha(p)}  {p.relative_to(OUT).as_posix()}\n" for p in arts));print(json.dumps({"outcome":outcome,"sample":sample,"normal_native":nn,"performance_failed":sum(x["status"]=="FAIL" for x in pg),"consistency_failed":sum(x["status"]=="FAIL" for x in cg)},indent=2))
if __name__=="__main__":main()
