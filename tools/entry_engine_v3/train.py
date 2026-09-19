#!/usr/bin/env python3
"""Chronological, episode-weighted development for ENTRY_ENGINE_V3_TRANSITION_EXPECTANCY."""
from __future__ import annotations

import argparse, csv, json, math
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import median

import numpy as np

from .build_dataset import FEATURE_NAMES
from .common import fit_logistic, fit_regression, max_drawdown, number
from .state_machine import Estimate, State, TransitionMachine

L2_VALUES=(1.0,10.0)
MIN_EV_VALUES=(.10,.25)
MAX_FULL_LOSS_VALUES=(.45,.55)
MIN_BANK_VALUES=(.35,.45)
MIN_DIRECTION_MARGIN=.05
MODEL_FAMILIES=("LINEAR","TRANSITION_INTERACTIONS")
INTERACTIONS=(
    ("quote_pressure_5s","rate_burst_5v30"),("quote_pressure_5s","resumption_evidence"),
    ("transition_pressure_score","pullback_still_expanding"),("transition_pressure_score","correlated_return_aligned"),
    ("rate_burst_5v30","spread_5v30"),("transition_pressure_score","current_r_from_detection"),
    ("m1_trend_aligned","m5_trend_aligned"),("m5_trend_aligned","m15_trend_aligned"),
)


def load_rows(path:Path)->list[dict]:
    rows=[]
    with path.open(newline="",encoding="utf-8") as f:
        for raw in csv.DictReader(f):
            row=dict(raw)
            for key in FEATURE_NAMES+["full_loss","bank1","plus_2","plus_3","plus_5","payoff_proxy_r","mfe_r","mae_r","censored"]:
                row[key]=number(row.get(key))
            for key in ("first_detection_utc","observation_utc"):
                row[key]=int(number(row[key]))
            if not row["censored"]: rows.append(row)
    return rows


def day(epoch:int)->str:
    return datetime.fromtimestamp(epoch,tz=timezone.utc).strftime("%Y-%m-%d")


def matrix(rows:list[dict],family:str)->np.ndarray:
    base=np.asarray([[number(r.get(k)) for k in FEATURE_NAMES] for r in rows],dtype=float)
    if family=="LINEAR":return base
    index={name:i for i,name in enumerate(FEATURE_NAMES)}
    extra=np.column_stack([base[:,index[a]]*base[:,index[b]] for a,b in INTERACTIONS])
    return np.column_stack([base,extra])


def weights(rows:list[dict])->np.ndarray:
    counts=Counter(r["opportunity_id"] for r in rows)
    return np.asarray([1.0/counts[r["opportunity_id"]] for r in rows])


def fit_bundle(rows:list[dict],l2:float,family:str)->dict:
    x=matrix(rows,family);w=weights(rows)
    result={name:fit_logistic(x,np.asarray([r[name] for r in rows]),w,l2) for name in ("full_loss","bank1","plus_2","plus_3","plus_5")}
    result["expected_net_r"]=fit_regression(x,np.asarray([r["payoff_proxy_r"] for r in rows]),w,l2)
    return result


def predict(bundle:dict,rows:list[dict],family:str)->dict[str,np.ndarray]:
    x=matrix(rows,family)
    return {name:model.predict(x) for name,model in bundle.items()}


def actions(rows:list[dict],pred:dict[str,np.ndarray],cfg:dict,fold_day:str)->list[dict]:
    enriched=[]
    for i,row in enumerate(rows):
        item=dict(row)
        for name,values in pred.items(): item["p_"+name]=float(values[i])
        item["entry_quality"]=float(1/(1+math.exp(-2*item["p_expected_net_r"])))
        enriched.append(item)
    episodes=defaultdict(list)
    for row in enriched: episodes[row["opportunity_id"]].append(row)
    output=[]
    for episode_id,episode_rows in sorted(episodes.items(),key=lambda kv:min(x["observation_utc"] for x in kv[1])):
        by_time=defaultdict(list)
        for row in episode_rows: by_time[row["observation_utc"]].append(row)
        detected=min(x["first_detection_utc"] for x in episode_rows)
        machine=TransitionMachine(detected,detected+900,cfg["min_ev"],cfg["max_full_loss"],cfg["min_bank"],MIN_DIRECTION_MARGIN)
        machine.detect(detected);selected=None
        for observed,pair in sorted(by_time.items()):
            row=max(pair,key=lambda x:x["p_expected_net_r"])
            other=max((x["p_expected_net_r"] for x in pair if x["direction"]!=row["direction"]),default=-99)
            estimate=Estimate(row["direction"],row["p_expected_net_r"],row["p_full_loss"],row["p_bank1"],other)
            if machine.observe(observed,estimate) is State.ENTRY_TRIGGERED:selected=row;break
        base=min(episode_rows,key=lambda x:x["observation_utc"])
        if selected:
            output.append({"fold_day":fold_day,"opportunity_id":episode_id,"symbol":selected["symbol"],
                "first_detection_utc":selected["first_detection_utc"],"observation_utc":selected["observation_utc"],
                "wait_seconds":selected["observation_utc"]-selected["first_detection_utc"],"action":"ENTER_"+selected["direction"],
                **{k:selected[k] for k in ("entry_quality","p_expected_net_r","p_full_loss","p_bank1","p_plus_2","p_plus_3","p_plus_5",
                    "payoff_proxy_r","full_loss","bank1","plus_2","plus_3","plus_5","mfe_r","mae_r",
                    "current_r_from_detection","transition_pressure_score","pullback_still_expanding","resumption_evidence")}})
        else:
            machine.expire(detected+900)
            output.append({"fold_day":fold_day,"opportunity_id":episode_id,"symbol":base["symbol"],
                "first_detection_utc":base["first_detection_utc"],"observation_utc":"","wait_seconds":900,
                "action":"OPPORTUNITY_ABANDONED"})
    return output


def calibration(entries:list[dict])->list[dict]:
    bands=[(0,.50),(.50,.55),(.55,.60),(.60,.65),(.65,.70),(.70,.80),(.80,1.01)]
    out=[]
    for low,high in bands:
        group=[r for r in entries if low<=r["entry_quality"]<high]
        if not group: continue
        pays=[r["payoff_proxy_r"] for r in group]
        out.append({"quality_low":low,"quality_high":high,"opportunities":len(group),"average_net_r":sum(pays)/len(pays),
            "median_net_r":median(pays),"full_loss_rate":sum(r["full_loss"] for r in group)/len(group),
            "bank1_rate":sum(r["bank1"] for r in group)/len(group),"plus_2_rate":sum(r["plus_2"] for r in group)/len(group),
            "plus_3_rate":sum(r["plus_3"] for r in group)/len(group),"plus_5_rate":sum(r["plus_5"] for r in group)/len(group),
            "drawdown_contribution_r":sum(-min(0,r["payoff_proxy_r"]) for r in group)})
    return out


def metrics(all_actions:list[dict],all_rows:list[dict])->dict:
    entries=[r for r in all_actions if r["action"].startswith("ENTER")]
    pays=[r["payoff_proxy_r"] for r in entries]
    counts=Counter(r["symbol"] for r in entries)
    day_net=defaultdict(float)
    for r in entries: day_net[day(r["first_detection_utc"])]+=r["payoff_proxy_r"]
    cal=calibration(entries)
    stable=[x for x in cal if x["opportunities"]>=10]
    observed_monotonic=bool(len(cal)>=2 and all(cal[i]["average_net_r"]<=cal[i+1]["average_net_r"] for i in range(len(cal)-1)))
    supported_monotonic=bool(len(stable)>=3 and all(stable[i]["average_net_r"]<=stable[i+1]["average_net_r"] for i in range(len(stable)-1)))
    gross=sum(pays);best=max(pays,default=0);best_symbol=max(counts,key=counts.get) if counts else ""
    without_symbol=sum(r["payoff_proxy_r"] for r in entries if r["symbol"]!=best_symbol)
    best_day=max(day_net,key=day_net.get) if day_net else ""
    return {"validation_opportunities":len({r["opportunity_id"] for r in all_rows}),"entries":len(entries),
        "wait_then_enter":sum(r["wait_seconds"]>0 for r in entries),"abandoned":len(all_actions)-len(entries),
        "net_r":gross,"expectancy_r":gross/len(entries) if entries else 0,"maximum_drawdown_r":max_drawdown(pays),
        "full_losses":sum(r["full_loss"] for r in entries),"full_loss_rate":sum(r["full_loss"] for r in entries)/len(entries) if entries else 1,
        "bank1_count":sum(r["bank1"] for r in entries),"bank1_rate":sum(r["bank1"] for r in entries)/len(entries) if entries else 0,
        "plus_2_count":sum(r["plus_2"] for r in entries),"plus_3_count":sum(r["plus_3"] for r in entries),"plus_5_count":sum(r["plus_5"] for r in entries),
        "best_winner_fraction_of_net":best/gross if gross>0 else None,"largest_symbol_fraction":max(counts.values())/len(entries) if entries else 1,
        "net_without_best_symbol":without_symbol,"net_without_best_day":gross-day_net.get(best_day,0),"net_without_best_winner":gross-best,
        "validation_days":len(day_net),"daily_net_r":dict(sorted(day_net.items())),"calibration_observed_monotonic":observed_monotonic,
        "calibration_supported_bins":len(stable),"calibration_monotonic_and_supported":supported_monotonic,"calibration":cal}


def gates(m:dict,max_training_days:int)->dict:
    result={"at_least_4_training_days":max_training_days>=4,"at_least_3_validation_days":m["validation_days"]>=3,
        "at_least_150_independent_validation_opportunities":m["validation_opportunities"]>=150,"at_least_40_entries":m["entries"]>=40,
        "positive_costed_expectancy":m["expectancy_r"]>0,"full_loss_rate_below_45pct":m["full_loss_rate"]<.45,
        "tail_retention_at_least_5pct":m["plus_3_count"]>=max(2,.05*m["entries"]),"calibration_monotonic_with_3_supported_bins":m["calibration_monotonic_and_supported"],
        "symbol_concentration_below_40pct":m["largest_symbol_fraction"]<.40,"positive_without_best_symbol":m["net_without_best_symbol"]>0,
        "positive_without_best_day":m["net_without_best_day"]>0,"positive_without_best_winner":m["net_without_best_winner"]>0,
        "drawdown_below_12R":m["maximum_drawdown_r"]<12}
    result["passed"]=all(result.values());return result


def main()->int:
    p=argparse.ArgumentParser();p.add_argument("--dataset",type=Path,required=True);p.add_argument("--output",type=Path,required=True);a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=True);rows=load_rows(a.dataset/"observations.csv")
    days=sorted({day(r["first_detection_utc"]) for r in rows});folds=[]
    for validation_day in days[1:]:
        val_start=int(datetime.strptime(validation_day,"%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp())
        train=[r for r in rows if r["first_detection_utc"]<val_start-4*3600]
        valid=[r for r in rows if day(r["first_detection_utc"])==validation_day]
        if train and valid: folds.append((validation_day,train,valid))
    results=[];actions_by_cfg=defaultdict(list);valid_by_cfg=defaultdict(list);bundles={}
    for fold_day,train,valid in folds:
        for family in MODEL_FAMILIES:
         for l2 in L2_VALUES:
            bundle=fit_bundle(train,l2,family);pred=predict(bundle,valid,family);bundles[(fold_day,family,l2)]=bundle
            for min_ev in MIN_EV_VALUES:
              for max_loss in MAX_FULL_LOSS_VALUES:
               for min_bank in MIN_BANK_VALUES:
                cfg={"family":family,"l2":l2,"min_ev":min_ev,"max_full_loss":max_loss,"min_bank":min_bank,"direction_margin":MIN_DIRECTION_MARGIN}
                key=json.dumps(cfg,sort_keys=True);actions_by_cfg[key]+=actions(valid,pred,cfg,fold_day);valid_by_cfg[key]+=valid
    max_training_days=max((len({day(r["first_detection_utc"]) for r in train}) for _,train,_ in folds),default=0)
    for key,act in actions_by_cfg.items():
        cfg=json.loads(key);m=metrics(act,valid_by_cfg[key]);results.append({"configuration":cfg,"metrics":m,"gates":gates(m,max_training_days)})
    results.sort(key=lambda x:(x["gates"]["passed"],x["metrics"]["net_r"],x["metrics"]["entries"]),reverse=True)
    best=results[0] if results else None;best_actions=actions_by_cfg[json.dumps(best["configuration"],sort_keys=True)] if best else []
    if best_actions:
        fields=sorted({k for r in best_actions for k in r})
        with (a.output/"oof-actions.csv").open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(best_actions)
        with (a.output/"calibration.csv").open("w",newline="",encoding="utf-8") as f:
            cal=best["metrics"]["calibration"];w=csv.DictWriter(f,fieldnames=list(cal[0]) if cal else ["quality_low"]);w.writeheader();w.writerows(cal)
    payload={"schema":"ENTRY_ENGINE_V3_DEVELOPMENT_V1","declared_search":{"families":MODEL_FAMILIES,"transition_interactions":INTERACTIONS,"l2":L2_VALUES,"min_ev":MIN_EV_VALUES,"max_full_loss":MAX_FULL_LOSS_VALUES,"min_bank":MIN_BANK_VALUES,"direction_margin":MIN_DIRECTION_MARGIN},
        "chronological_days":days,"folds":[{"validation_day":d,"training_rows":len(t),"validation_rows":len(v),"training_episodes":len({x['opportunity_id'] for x in t}),"validation_episodes":len({x['opportunity_id'] for x in v})} for d,t,v in folds],
        "model_count":len(results),"passing_models":sum(x["gates"]["passed"] for x in results),"results":results}
    (a.output/"development-results.json").write_text(json.dumps(payload,indent=2)+"\n")
    freeze={"schema":"ENTRY_ENGINE_V3_FREEZE_V1","status":"FROZEN_REPLACEMENT" if best and best["gates"]["passed"] else "NOT_FROZEN",
        "reason":"ALL_PREDECLARED_PROMOTION_GATES_PASSED" if best and best["gates"]["passed"] else "NO_CANDIDATE_PASSED_PREDECLARED_GATES",
        "best_diagnostic_configuration":best["configuration"] if best else None,"best_diagnostic_metrics":best["metrics"] if best else None,
        "deployment_authorized":False,"shadow_forward_authorized":bool(best and best["gates"]["passed"])}
    (a.output/"model-freeze.json").write_text(json.dumps(freeze,indent=2)+"\n")
    print(json.dumps({"days":days,"folds":len(folds),"models":len(results),"passing":payload["passing_models"],"freeze":freeze["status"]},indent=2));return 0

if __name__=="__main__": raise SystemExit(main())
