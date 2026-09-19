#!/usr/bin/env python3
"""Ratchet, causal invalidation, and production-vs-V3 comparison receipts."""
from __future__ import annotations

import argparse,csv,json
from collections import Counter,defaultdict
from datetime import datetime,timezone
from pathlib import Path
from statistics import median

from .common import max_drawdown,number,utc_seconds


def load(path:Path)->list[dict]:
    with path.open(newline="",encoding="utf-8") as f:return [dict(x) for x in csv.DictReader(f)]


def numeric(rows:list[dict])->list[dict]:
    keys=("first_detection_utc","observation_utc","wait_seconds","payoff_proxy_r","structural_manager_r","ratchet_loose_r",
          "ratchet_balanced_r","ratchet_capture_r","ratchet_loose_guaranteed_r","ratchet_balanced_guaranteed_r",
          "ratchet_capture_guaranteed_r","full_loss","bank1","plus_2","plus_3","plus_5","mfe_r","mae_r",
          "current_r_from_detection","transition_pressure_score","pullback_still_expanding","resumption_evidence")
    keys=keys+("maximum_continuation_r",)
    for row in rows:
        for k in keys:
            if k in row: row[k]=number(row[k])
    return rows


def ratchets(rows:list[dict])->dict:
    first={}
    for row in rows:
        if row.get("direction")!=row.get("direction_hypothesis") or number(row.get("censored")):continue
        key=row["opportunity_id"]
        if key not in first or row["observation_utc"]<first[key]["observation_utc"]:first[key]=row
    cohort=list(first.values());base=[r["structural_manager_r"] for r in cohort]
    result=[]
    for name in ("loose","balanced","capture"):
        vals=[r[f"ratchet_{name}_r"] for r in cohort]
        tails=[r for r in cohort if r["plus_3"]>=1]
        result.append({"name":name,"opportunities":len(vals),"net_r":sum(vals),"expectancy_r":sum(vals)/len(vals) if vals else 0,
            "maximum_drawdown_r":max_drawdown(vals),"improvement_vs_structural_r":sum(vals)-sum(base),
            "minimum_retained_r_on_banked":min((r[f"ratchet_{name}_r"] for r in cohort if r["bank1"]),default=None),
            "mean_peak_to_final_giveback_r":sum(max(0,.5+.5*r["maximum_continuation_r"]-r[f"ratchet_{name}_r"]) for r in cohort if r["bank1"])/max(1,sum(r["bank1"] for r in cohort)),
            "plus3_paths":len(tails),"plus3_mean_final_r":sum(r[f"ratchet_{name}_r"] for r in tails)/len(tails) if tails else None,
            "plus5_paths":sum(r["plus_5"] for r in cohort),"positive_days":sum(v>=0 for v in _day_net(cohort,f"ratchet_{name}_r").values()),
            "daily_net_r":_day_net(cohort,f"ratchet_{name}_r")})
    return {"schema":"WHOLE_TRADE_PROFIT_RATCHET_V1_RESEARCH","bank1_unchanged":True,"runner_volume_fraction":.5,
        "guarantee_formula":"banked 0.5R + half-volume runner stop R; guarantee is monotonic and stop is never widened",
        "baseline":{"opportunities":len(base),"net_r":sum(base),"expectancy_r":sum(base)/len(base) if base else 0,"maximum_drawdown_r":max_drawdown(base)},
        "predeclared_candidates":result,"production_change":False}


def _day_net(rows:list[dict],field:str)->dict:
    d=defaultdict(float)
    for r in rows:
        day=datetime.fromtimestamp(int(r["first_detection_utc"]),tz=timezone.utc).strftime("%Y-%m-%d");d[day]+=r[field]
    return dict(sorted(d.items()))


def invalidation(rows:list[dict],actions:list[dict])->dict:
    by_episode=defaultdict(list)
    for r in rows:by_episode[r["opportunity_id"]].append(r)
    entries=[x for x in actions if x.get("action","").startswith("ENTER")]
    candidates=[]
    for adverse in (-.25,-.40):
      for reverse in (-.25,-.50):
        results=[];exits=0;tail_interrupted=0;daily=defaultdict(float)
        for entry in entries:
            direction=entry["action"].split("_",1)[1];start=number(entry["current_r_from_detection"]);exit_r=None
            future=sorted((r for r in by_episode[entry["opportunity_id"]] if r["direction"]==direction and r["observation_utc"]>=number(entry["observation_utc"])),key=lambda r:r["observation_utc"])
            for r in future:
                movement=r["current_r_from_detection"]-start
                evidence_reversed=r["transition_pressure_score"]<=reverse and r["pullback_still_expanding"]>=1 and r["resumption_evidence"]<1
                if movement<=adverse and evidence_reversed:exit_r=movement;break
            if exit_r is None:result=number(entry["payoff_proxy_r"]);results.append(result)
            else:
                exits+=1;result=exit_r;results.append(result)
                if number(entry["plus_3"]):tail_interrupted+=1
            day=datetime.fromtimestamp(int(number(entry["first_detection_utc"])),tz=timezone.utc).strftime("%Y-%m-%d");daily[day]+=result
        base=sum(number(x["payoff_proxy_r"]) for x in entries)
        candidates.append({"adverse_r":adverse,"reversal_score_max":reverse,"entries":len(entries),"early_exits":exits,
            "net_r":sum(results),"improvement_r":sum(results)-base,"maximum_drawdown_r":max_drawdown(results),
            "tail_winners_interrupted":tail_interrupted,"validation_days":len(daily),"daily_net_r":dict(sorted(daily.items())),
            "passed":bool(len(entries)>=40 and len(daily)>=3 and exits>=5 and sum(results)>base and all(v>=0 for v in daily.values()) and tail_interrupted<=.1*max(1,sum(number(x["plus_3"]) for x in entries)))})
    return {"schema":"POST_ENTRY_CAUSAL_INVALIDATION_V1","rule":"adverse movement AND transition pressure reversal AND expanding pullback AND no resumption",
        "blind_fixed_r_exit":False,"observation_limit":"Causal reversal observations are available only inside the 15-minute WAIT trajectory in this first collector study.",
        "candidates":candidates,"passing_candidates":sum(x["passed"] for x in candidates),"production_change":False}


def production_entries(path:Path)->list[dict]:
    result=[]
    raw=load(path)
    if raw and "net_r" in raw[0]:
      for row in raw:
        peak=number(row.get("peak_r"));net=number(row.get("net_r"))
        result.append({"time":utc_seconds(row["entry_evidence_utc"]),"symbol":row["symbol"],
          "direction":"LONG" if row["direction"]=="BUY" else "SHORT","payoff_proxy_r":net,
          "full_loss":float(net<=-.75),"bank1":float(row.get("reached_1r","").lower()=="true"),
          "plus_3":float(peak>=3),"mfe_r":peak,"source":"ACTUAL_PRODUCTION_TRADE"})
      return result
    for row in raw:
        values=list(row.values())
        if len(values)>=6 and values[2]=="ENTRY":
            result.append({"time":utc_seconds(values[1]),"symbol":values[4],"direction":"LONG" if values[5]=="BUY" else "SHORT"})
    return result


def comparison(rows:list[dict],actions:list[dict],events:Path|None)->dict:
    b={r["opportunity_id"]:r for r in actions if r.get("action","").startswith("ENTER")};mapped=[];unmapped=[];outside=[]
    action_ids={r["opportunity_id"] for r in actions}
    episodes={}
    for row in rows: episodes.setdefault(row["opportunity_id"],{"opportunity_id":row["opportunity_id"],"symbol":row["symbol"],"detected":row["first_detection_utc"]})
    if events and events.exists():
      for event in production_entries(events):
        pool=[r for r in episodes.values() if r["symbol"]==event["symbol"] and 0<=event["time"]-r["detected"]<14400]
        if not pool:unmapped.append(event);continue
        episode=max(pool,key=lambda x:x["detected"]);event["opportunity_id"]=episode["opportunity_id"]
        if episode["opportunity_id"] not in action_ids:outside.append(event)
        else:mapped.append(event)
    a=defaultdict(list)
    for r in mapped:a[r["opportunity_id"]].append(r)
    shared=set(a)&set(b);exact=[];disagree=[]
    for eid in shared:
        bdir=b[eid]["action"].split("_",1)[1]
        for trade in a[eid]: (exact if trade["direction"]==bdir else disagree).append((trade,b[eid]))
    a_only=set(a)-shared;b_only=set(b)-shared
    def summary(items):
        vals=list(items);p=[number(x["payoff_proxy_r"]) for x in vals]
        return {"trades":len(vals),"net_r":sum(p),"full_losses":sum(number(x.get("full_loss")) for x in vals),
            "bank1":sum(number(x.get("bank1")) for x in vals),"plus_3":sum(number(x.get("plus_3")) for x in vals),
            "median_mfe_r":median([number(x.get("mfe_r")) for x in vals]) if vals else None,"maximum_drawdown_r":max_drawdown(p)}
    avals=[x for group in a.values() for x in group]
    return {"schema":"CURRENT_V1_VS_ENTRY_ENGINE_V3_V1","episode_mapping":"most recent same-symbol independent episode active at production entry",
        "production_entries_mapped_to_oof_stream":len(mapped),"production_entries_outside_oof_days":outside,"production_entries_unmapped":unmapped,
        "A_current_production":summary(avals),"B_v3_oof":summary(b.values()),
        "both_enter_same_direction_A_actual":summary(x[0] for x in exact),"both_enter_same_direction_B_counterfactual":summary(x[1] for x in exact),
        "direction_disagreement_A_actual":summary(x[0] for x in disagree),"direction_disagreement_B_counterfactual":summary(x[1] for x in disagree),
        "A_enters_B_rejects":summary(x for eid in a_only for x in a[eid]),"B_enters_A_rejects":summary(b[x] for x in b_only),
        "B_wait_then_enter":sum(number(x.get("wait_seconds"))>0 for x in b.values()),"B_wait_then_abandon":sum(x.get("action")=="OPPORTUNITY_ABANDONED" for x in actions),
        "limitation":"A uses actual realized production trade R/MFE. Only trades mapping to episodes in V3's chronological out-of-fold validation stream are compared; earlier training-day and unmatched trades are disclosed."}


def main()->int:
    p=argparse.ArgumentParser();p.add_argument("--dataset",type=Path,required=True);p.add_argument("--development",type=Path,required=True);p.add_argument("--output",type=Path,required=True);p.add_argument("--production-events",type=Path);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True);rows=numeric(load(a.dataset/"observations.csv"));actions=numeric(load(a.development/"oof-actions.csv")) if (a.development/"oof-actions.csv").exists() else []
    receipts={"ratchet-results.json":ratchets(rows),"post-entry-invalidation.json":invalidation(rows,actions),"v1-vs-v3-comparison.json":comparison(rows,actions,a.production_events)}
    for name,data in receipts.items():(a.output/name).write_text(json.dumps(data,indent=2)+"\n")
    print(json.dumps({k:{"bytes":(a.output/k).stat().st_size} for k in receipts},indent=2));return 0

if __name__=="__main__":raise SystemExit(main())
