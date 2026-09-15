#!/usr/bin/env python3
"""Development-only joint opportunity/direction research for OPPORTUNITY_ENGINE_V2."""
from __future__ import annotations

import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/fast-multi-market-v2/opportunity-engine-v2-raw-rebuild-20260915"
MONTHS = ("2026.05", "2026.06", "2026.07", "2026.08")

DIRECTIONAL_FEATURES = (
    "event_alignment", "trend_m1_aligned", "trend_m5_aligned", "trend_m15_aligned", "trend_h1_aligned",
    "path_efficiency_m5", "path_efficiency_change", "impulse_aligned", "recent_momentum_aligned",
    "latest_impulse_aligned", "impulse_age_m5", "displacement_along_candidate_m5_atr",
    "acceleration_aligned", "volatility_expansion_m5", "m1_body_aligned", "m1_body_fraction",
    "favorable_wick_body", "opposing_wick_body", "directional_close_streak", "opposing_close_streak",
    "aligned_breakout", "opposing_breakout", "failed_opposing_breakout", "failed_aligned_breakout",
    "aligned_structure", "opposing_structure", "pullback_resume_aligned", "pullback_depth",
    "pullback_progress", "breakout_retest_aligned", "opposing_pressure", "rejection_aligned",
    "directional_range_location", "distance_favorable_extreme_m5_atr", "session_directional_location",
    "previous_day_directional_location", "room_r", "stop_m1_atr", "stop_m5_atr",
    "invalidation_distance_m5_atr", "spread_m1_atr", "cost_r", "compression_ratio_m1",
)


def number(value: Any) -> float:
    try: return float(value)
    except (TypeError, ValueError): return 0.0


def read_rows() -> list[dict[str, str]]:
    rows=[]
    for name in ("opportunities-april-may.csv", "opportunities-june-august.csv"):
        with (OUT/name).open(newline="", encoding="utf-8") as f: rows.extend(csv.DictReader(f))
    return sorted(rows, key=lambda x:x["causal_entry_utc"])


def directional(row: dict[str, str], direction: int) -> dict[str, float]:
    long = direction > 0
    return {
        "event_alignment": direction * number(row["event_direction"]),
        "trend_m1_aligned": direction * number(row["trend_m1"]), "trend_m5_aligned": direction * number(row["trend_m5"]),
        "trend_m15_aligned": direction * number(row["trend_m15"]), "trend_h1_aligned": direction * number(row["trend_h1"]),
        "path_efficiency_m5": number(row["path_efficiency_m5"]), "path_efficiency_change": number(row["path_efficiency_change"]),
        "impulse_aligned": direction * number(row["impulse_m5_atr"]),
        "latest_impulse_aligned": direction * number(row["latest_impulse_direction"]),
        "impulse_age_m5": number(row["impulse_age_m5"]),
        "displacement_along_candidate_m5_atr": direction * number(row["impulse_displacement_m5_atr"]),
        "recent_momentum_aligned": direction * number(row["recent_momentum_m5_atr"]),
        "acceleration_aligned": direction * number(row["acceleration_m5_atr"]),
        "volatility_expansion_m5": number(row["volatility_expansion_m5"]),
        "m1_body_aligned": direction * number(row["m1_body_atr"]), "m1_body_fraction": number(row["m1_body_fraction"]),
        "favorable_wick_body": number(row["m1_lower_wick_body"] if long else row["m1_upper_wick_body"]),
        "opposing_wick_body": number(row["m1_upper_wick_body"] if long else row["m1_lower_wick_body"]),
        "directional_close_streak": number(row["up_close_streak"] if long else row["down_close_streak"]),
        "opposing_close_streak": number(row["down_close_streak"] if long else row["up_close_streak"]),
        "aligned_breakout": number(row["breakout_up"] if long else row["breakout_down"]),
        "opposing_breakout": number(row["breakout_down"] if long else row["breakout_up"]),
        "failed_opposing_breakout": number(row["failed_breakout_down"] if long else row["failed_breakout_up"]),
        "failed_aligned_breakout": number(row["failed_breakout_up"] if long else row["failed_breakout_down"]),
        "aligned_structure": number(row["bull_structure"] if long else row["bear_structure"]),
        "opposing_structure": number(row["bear_structure"] if long else row["bull_structure"]),
        "pullback_resume_aligned": number(row["pullback_resume_up"] if long else row["pullback_resume_down"]),
        "pullback_depth": number(row["pullback_depth_long"] if long else row["pullback_depth_short"]),
        "pullback_progress": number(row["pullback_progress_long"] if long else row["pullback_progress_short"]),
        "breakout_retest_aligned": number(row["breakout_retest_up"] if long else row["breakout_retest_down"]),
        "opposing_pressure": -direction * number(row["opposing_pressure_signed_m1"]),
        "rejection_aligned": number(row["rejection_up"] if long else row["rejection_down"]),
        "directional_range_location": number(row["range_location"]) if long else 1-number(row["range_location"]),
        "distance_favorable_extreme_m5_atr": number(row["distance_high_m5_atr"] if long else row["distance_low_m5_atr"]),
        "session_directional_location": number(row["session_location"]) if long else 1-number(row["session_location"]),
        "previous_day_directional_location": number(row["previous_day_location"]) if long else 1-number(row["previous_day_location"]),
        "room_r": number(row["long_room_r"] if long else row["short_room_r"]),
        "stop_m1_atr": number(row["long_stop_m1_atr"] if long else row["short_stop_m1_atr"]),
        "stop_m5_atr": number(row["long_stop_m5_atr"] if long else row["short_stop_m5_atr"]),
        "invalidation_distance_m5_atr": number(row["long_invalidation_distance_m5_atr"] if long else row["short_invalidation_distance_m5_atr"]),
        "spread_m1_atr": number(row["spread_m1_atr"]), "cost_r": number(row["cost_long_r"] if long else row["cost_short_r"]),
        "compression_ratio_m1": number(row["compression_ratio_m1"]),
    }


def won(row: dict[str, str], direction: int) -> bool:
    return row["long_primary_label" if direction > 0 else "short_primary_label"] == "WIN_1R_BEFORE_STOP"


def resolved(row: dict[str, str], direction: int) -> bool:
    return row["long_primary_label" if direction > 0 else "short_primary_label"] != "NO_BOUNDARY"


class Logistic:
    def __init__(self, means: np.ndarray, scales: np.ndarray, weights: np.ndarray, l2: float):
        self.means,self.scales,self.weights,self.l2=means,scales,weights,l2
    def probability(self, values: dict[str,float]) -> float:
        x=np.asarray([values[k] for k in DIRECTIONAL_FEATURES]);z=float(self.weights[0]+np.dot(self.weights[1:],(x-self.means)/self.scales));z=max(-35,min(35,z));return 1/(1+math.exp(-z))
    def payload(self) -> dict[str,Any]:
        return {"kind":"PAIRWISE_REGULARIZED_LOGISTIC","features":list(DIRECTIONAL_FEATURES),"l2":self.l2,
                "means":dict(zip(DIRECTIONAL_FEATURES,self.means.tolist())),"scales":dict(zip(DIRECTIONAL_FEATURES,self.scales.tolist())),
                "intercept":float(self.weights[0]),"coefficients":dict(zip(DIRECTIONAL_FEATURES,self.weights[1:].tolist()))}


def fit_logistic(rows: list[dict[str,str]], l2: float) -> Logistic:
    samples=[];labels=[]
    for row in rows:
        for direction in (1,-1):
            if resolved(row,direction): samples.append([directional(row,direction)[k] for k in DIRECTIONAL_FEATURES]);labels.append(1.0 if won(row,direction) else 0.0)
    x=np.asarray(samples,float);y=np.asarray(labels,float);means=x.mean(0);scales=x.std(0);scales[scales<1e-8]=1;z=(x-means)/scales;design=np.column_stack([np.ones(len(z)),z]);w=np.zeros(design.shape[1]);
    positive=max(y.sum(),1);negative=max(len(y)-y.sum(),1);sample_weight=np.where(y>0,len(y)/(2*positive),len(y)/(2*negative))
    for _ in range(100):
        logits=np.clip(design@w,-35,35);p=1/(1+np.exp(-logits));grad=design.T@(sample_weight*(p-y));grad[1:]+=l2*w[1:]
        curvature=sample_weight*p*(1-p);hessian=design.T@(design*curvature[:,None]);hessian[1:,1:]+=l2*np.eye(len(w)-1)
        step=np.linalg.solve(hessian+1e-8*np.eye(len(w)),grad);w-=step
        if np.max(np.abs(step))<1e-8:break
    return Logistic(means,scales,w,l2)


def train_stumps(rows:list[dict[str,str]], count:int) -> list[dict[str,Any]]:
    samples=[];labels=[]
    for row in rows:
        for d in (1,-1):
            if resolved(row,d):samples.append([directional(row,d)[k] for k in DIRECTIONAL_FEATURES]);labels.append(1 if won(row,d) else -1)
    x=np.asarray(samples);y=np.asarray(labels);weights=np.ones(len(y))/len(y);model=[]
    for _ in range(count):
        best=None
        for j,name in enumerate(DIRECTIONAL_FEATURES):
            for split in np.unique(np.quantile(x[:,j],[.15,.3,.45,.55,.7,.85])):
                for polarity in (-1,1):
                    pred=np.where(x[:,j]>=split,polarity,-polarity);error=float(weights[pred!=y].sum());candidate=(error,j,name,float(split),polarity,pred)
                    if best is None or candidate[:5]<best[:5]:best=candidate
        error,j,name,split,polarity,pred=best;error=max(1e-6,min(.499999,error));alpha=.5*math.log((1-error)/error);model.append({"feature":name,"split":split,"polarity":polarity,"alpha":alpha});weights*=np.exp(-alpha*y*pred);weights/=weights.sum()
    return model


def stump_probability(model:list[dict[str,Any]],values:dict[str,float])->float:
    score=sum(x["alpha"]*(x["polarity"] if values[x["feature"]]>=x["split"] else -x["polarity"]) for x in model);return 1/(1+math.exp(-2*max(-20,min(20,score))))


def decision(p_long:float,p_short:float,threshold:float,margin:float)->tuple[str,int,float]:
    direction=1 if p_long>=p_short else -1;quality=max(p_long,p_short);opposite=min(p_long,p_short);no_trade=max(p_long*p_short,(1-p_long)*(1-p_short))
    if quality>=threshold and quality-opposite>=margin and quality-no_trade>=margin:return ("LONG" if direction>0 else "SHORT"),direction,no_trade
    if quality>=threshold-.12:return "WAIT",0,no_trade
    return "REJECT",0,no_trade


def maxdd(trades:list[tuple[dict[str,str],int]])->float:
    value=peak=dd=0.0
    for row,d in sorted(trades,key=lambda x:x[0]["causal_entry_utc"]):value+=1 if won(row,d) else -1;peak=max(peak,value);dd=max(dd,peak-value)
    return dd


def evaluate(scored:list[tuple[float,float,dict[str,str]]],threshold:float,margin:float)->dict[str,Any]:
    actions=Counter(); trades=[];directional_correct=directional_wrong=0
    by_month=defaultdict(lambda:[0,0,0]);by_symbol=defaultdict(lambda:[0,0,0]);by_family=defaultdict(lambda:[0,0,0])
    directional_edges=sum(r["direction_label"] in ("LONG_EDGE","SHORT_EDGE") for _,_,r in scored)
    for pl,ps,row in scored:
        action,d,_=decision(pl,ps,threshold,margin);actions[action]+=1
        if d and resolved(row,d):
            trades.append((row,d));win=won(row,d);bucket=1 if win else 2
            for key,target in ((row["causal_entry_utc"][:7],by_month),(row["symbol"],by_symbol),(row["event_family"],by_family)):
                target[key][0]+=1;target[key][bucket]+=1
            if row["direction_label"] in ("LONG_EDGE","SHORT_EDGE"):
                if (row["direction_label"]=="LONG_EDGE")==(d>0):directional_correct+=1
                else:directional_wrong+=1
    wins=sum(won(r,d) for r,d in trades);losses=len(trades)-wins;symbol_net={k:v[1]-v[2] for k,v in by_symbol.items()};month_net={k:v[1]-v[2] for k,v in by_month.items()}
    return {"opportunities":len(scored),"actions":dict(actions),"resolved_entries":len(trades),"wins":wins,"losses":losses,"net_r":wins-losses,
            "expectancy_r":(wins-losses)/len(trades) if trades else None,"max_drawdown_r":maxdd(trades),
            "directional_edges_available":directional_edges,"directional_edges_correct":directional_correct,"directional_edges_wrong":directional_wrong,
            "directional_accuracy":directional_correct/max(1,directional_correct+directional_wrong),
            "edge_retention":directional_correct/max(1,directional_edges),"monthly":dict(by_month),"symbols":dict(by_symbol),"families":dict(by_family),
            "largest_symbol_share":max((x[0] for x in by_symbol.values()),default=0)/max(1,len(trades)),
            "net_without_best_symbol":(wins-losses)-max(symbol_net.values(),default=0),"net_without_best_month":(wins-losses)-max(month_net.values(),default=0),
            "positive_months":sum(v>0 for v in month_net.values()),"months_with_entries":len(month_net)}


def benchmark(rows:list[dict[str,str]],inverse:bool=False)->dict[str,Any]:
    scored=[]
    for row in rows:
        d=1 if row["event_direction_hypothesis"]=="LONG" else -1
        if inverse:d=-d
        scored.append((.9 if d>0 else .1,.9 if d<0 else .1,row))
    return evaluate(scored,.5,.2)


def main()->int:
    rows=read_rows();resolved_rows=[r for r in rows if r["direction_label"]!="CENSORED"]
    experiments=[]
    configs=[("PAIRWISE_REGULARIZED_LOGISTIC",x) for x in (.3,1.,3.,10.)]+[("PAIRWISE_SHALLOW_STUMPS",x) for x in (3,5,8)]
    for kind,param in configs:
      fold_scores=[];models=[]
      for month in MONTHS:
        train=[r for r in resolved_rows if r["causal_entry_utc"][:7]<month];valid=[r for r in resolved_rows if r["causal_entry_utc"][:7]==month]
        if kind.startswith("PAIRWISE_REGULARIZED"):
            model=fit_logistic(train,float(param));values=[(model.probability(directional(r,1)),model.probability(directional(r,-1)),r) for r in valid];models.append(model.payload())
        else:
            model=train_stumps(train,int(param));values=[(stump_probability(model,directional(r,1)),stump_probability(model,directional(r,-1)),r) for r in valid];models.append({"kind":kind,"trees":model})
        fold_scores.append((month,len(train),values))
      for threshold in (.48,.55,.62):
       for margin in (.05,.12):
        scored=[];folds=[]
        for month,training_count,values in fold_scores:
            item=evaluate(values,threshold,margin);item["month"]=month;item["training_opportunities"]=training_count;folds.append(item);scored.extend(values)
        metrics=evaluate(scored,threshold,margin);base=benchmark([r for _,_,r in scored]);monthly_ok=all(f["net_r"]>=0 and f["resolved_entries"]>=10 for f in folds)
        gates={"positive_costed_expectancy":metrics["net_r"]>0 and metrics["expectancy_r"]>0,
               "directional_accuracy_at_least_55pct":metrics["directional_accuracy"]>=.55,
               "edge_retention_at_least_25pct":metrics["edge_retention"]>=.25,
               "loss_rate_below_event_benchmark":metrics["losses"]/max(1,metrics["resolved_entries"]) < base["losses"]/max(1,base["resolved_entries"]),
               "at_least_80_resolved_entries":metrics["resolved_entries"]>=80,"controlled_drawdown":metrics["max_drawdown_r"]<=base["max_drawdown_r"],
               "largest_symbol_below_40pct":metrics["largest_symbol_share"]<.40,"all_months_nonnegative_and_usable":monthly_ok,
               "positive_without_best_symbol":metrics["net_without_best_symbol"]>0,"positive_without_best_month":metrics["net_without_best_month"]>0,
               "positive_after_one_winner_removed":metrics["net_r"]-1>0}
        experiments.append({"kind":kind,"parameter":param,"threshold":threshold,"margin":margin,"metrics":metrics,"folds":folds,"gates":gates,"passed":all(gates.values()),"fold_models":models})
    passed=[x for x in experiments if x["passed"]];best=max(experiments,key=lambda x:(sum(x["gates"].values()),x["metrics"]["net_r"],x["metrics"]["resolved_entries"]))
    labels=Counter(r["direction_label"] for r in rows);families=Counter(r["event_family"] for r in rows)
    stop_audit={"hypotheses":2*len(rows),"inside_m1_noise":sum(number(r[x])<1 for r in rows for x in ("long_stop_m1_atr","short_stop_m1_atr")),
                "inside_m5_noise":sum(number(r[x])<1 for r in rows for x in ("long_stop_m5_atr","short_stop_m5_atr")),
                "median_stop_m1_atr":float(np.median([number(r[x]) for r in rows for x in ("long_stop_m1_atr","short_stop_m1_atr")])),
                "median_stop_m5_atr":float(np.median([number(r[x]) for r in rows for x in ("long_stop_m5_atr","short_stop_m5_atr")]))}
    payload={"schema":"OPPORTUNITY_ENGINE_V2_DEVELOPMENT_RESULT_V1","decision":"FROZEN_CANDIDATE_PASSED_DEVELOPMENT" if passed else "NO_DEMONSTRATED_MARKET_EDGE_IN_CURRENT_INFORMATION_SET",
             "holdout_opened":False,"holdout_evaluations":0,"opportunities":len(rows),"resolved_opportunities":len(resolved_rows),"direction_labels":dict(labels),
             "event_families":dict(families),"features":list(DIRECTIONAL_FEATURES),"experiments_tested":len(experiments),"passing_experiments":len(passed),
             "event_direction_benchmark":benchmark(resolved_rows),"inverse_direction_benchmark":benchmark(resolved_rows,True),"structural_stop_audit":stop_audit,
             "best_candidate" if passed else "best_nonpassing_diagnostic":max(passed,key=lambda x:x["metrics"]["net_r"]) if passed else best,
             "all_candidate_results":[{k:x[k] for k in ("kind","parameter","threshold","margin","metrics","gates","passed")} for x in experiments]}
    (OUT/"development-results.json").write_text(json.dumps(payload,indent=2)+"\n")
    (OUT/"feature-manifest.json").write_text(json.dumps({"schema":"OPPORTUNITY_ENGINE_V2_FEATURE_MANIFEST_V1","features":list(DIRECTIONAL_FEATURES),"production_scores_used":False,"production_direction_used":False,"future_features_used":False,"causal_cutoff":"completed M1/M5/M15/H1 bars before event; executable quote/cost at event"},indent=2)+"\n")
    freeze={"status":"MODEL_FROZEN" if passed else "NO_MODEL_FROZEN","holdout_must_remain_sealed":not bool(passed),"candidate":max(passed,key=lambda x:x["metrics"]["net_r"]) if passed else None,"stop_reason":None if passed else "No joint opportunity/direction formulation passed all development gates."}
    (OUT/"model-freeze.json").write_text(json.dumps(freeze,indent=2)+"\n")
    print(json.dumps({k:payload[k] for k in ("decision","opportunities","resolved_opportunities","direction_labels","event_families","experiments_tested","passing_experiments","event_direction_benchmark","inverse_direction_benchmark","structural_stop_audit")}|{"best":{k:best[k] for k in ("kind","parameter","threshold","margin","metrics","gates")}},indent=2));return 0


if __name__=="__main__":raise SystemExit(main())
