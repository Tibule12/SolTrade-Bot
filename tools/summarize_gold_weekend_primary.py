#!/usr/bin/env python3
"""M1-first summary and sizing arithmetic from the frozen orderless experiment."""

import argparse
import json
import math
from pathlib import Path
from statistics import mean, median

from analyze_gold_weekend_expanded import METHODS, boot, wilson


def describe(values):
    return {"n": len(values), "mean": round(mean(values), 4) if values else None,
            "median": round(median(values), 4) if values else None, "mean_ci95": boot(values)}


def primary(rows, split, side=None):
    records = [r for r in rows if r["signals"]["M1"] and (split == "ALL" or r["split"] == split)
               and (side is None or r["signals"]["M1"] == side)]
    values = [r["paths"][r["signals"]["M1"]]["REOPEN"] for r in records]
    returns = [p["return_240m"] for p in values if p["return_240m"] is not None]
    results = {"n":len(records),"buy":sum(r["signals"]["M1"]=="BUY" for r in records),
               "sell":sum(r["signals"]["M1"]=="SELL" for r in records),
               "same_direction_gap_count":sum((r["gap_bid"]>0 if r["signals"]["M1"]=="BUY" else r["gap_bid"]<0) for r in records),
               "four_hour_net_usd_per_ounce":describe(returns),
               "four_hour_positive_count":sum(x>0 for x in returns),
               "four_hour_positive_ci95":wilson(sum(x>0 for x in returns),len(returns))}
    random_differences = [r["paths"][r["signals"]["M1"]]["REOPEN"]["return_240m"]
                          -(r["paths"]["BUY"]["REOPEN"]["return_240m"]
                            +r["paths"]["SELL"]["REOPEN"]["return_240m"])/2 for r in records]
    results["paired_edge_vs_50_50_random_usd_per_ounce"] = describe(random_differences)
    results["same_direction_gap_ci95"] = wilson(results["same_direction_gap_count"],len(records))
    for d in (5,10,20):
        states = [p[f"barrier_{d}"] for p in values]
        fav,adv = states.count("FAVORABLE_FIRST"),states.count("ADVERSE_FIRST")
        results[f"race_{d}"]={"favorable_first":fav,"adverse_first":adv,
            "ambiguous_same_bar":states.count("AMBIGUOUS_SAME_BAR"),"neither":states.count("NEITHER"),
            "censored":states.count("CENSORED"),"resolved_favorable_rate":round(fav/(fav+adv),4) if fav+adv else None,
            "resolved_favorable_ci95":wilson(fav,fav+adv),
            "unconditional_favorable_fraction":round(fav/len(states),4) if states else None}
        for name in ("favorable","adverse"):
            times=[p[f"time_{name}_{d}m"] for p in values if p[f"time_{name}_{d}m"] is not None]
            results[f"race_{d}"][f"median_minutes_to_{name}"]=round(median(times),2) if times else None
    all_adverse=sorted(-p["mae_4h"] for p in values if p["mae_4h"] is not None)
    winners_adverse=sorted(-p["mae_4h"] for p in values if p["mae_4h"] is not None and p["return_240m"] is not None and p["return_240m"]>0)
    for label, data in (("all",all_adverse),("four_hour_winners",winners_adverse)):
        results[f"adverse_excursion_{label}"]={"n":len(data),"median":round(median(data),4) if data else None,
            "p90":round(data[math.ceil(.9*len(data))-1],4) if data else None}
    return results


def methods(rows):
    out=[]
    for split in ("ALL","IN_SAMPLE","OUT_OF_SAMPLE"):
        records=[r for r in rows if r["signals"]["M1"] and (split=="ALL" or r["split"]==split)]
        for method in METHODS:
            chosen=[(r,r["paths"][r["signals"]["M1"]][method]) for r in records]
            entered=[(r,p) for r,p in chosen if p is not None and p["return_240m"] is not None]
            immediate=[r["paths"][r["signals"]["M1"]]["REOPEN"]["return_240m"] for r,p in entered]
            delayed=[p["return_240m"] for r,p in entered]
            out.append({"split":split,"method":method,"eligible":len(records),"entered":len(entered),
                        "entry_coverage":round(len(entered)/len(records),4) if records else None,
                        "conditional_return":describe(delayed),
                        "paired_immediate_return":describe(immediate),
                        "paired_change":describe([a-b for a,b in zip(delayed,immediate)]),
                        "zero_for_no_entry_mean":round(sum(delayed)/len(records),4) if records else None})
    return out


def risk(rows):
    records=[r["paths"][r["signals"]["M1"]]["REOPEN"] for r in rows if r["signals"]["M1"]]
    spread=median(p["entry_spread_usd"] for p in records)
    adverse=sorted(-p["mae_4h"] for p in records if p["mae_4h"] is not None)
    p90=adverse[math.ceil(.9*len(adverse))-1]
    balances={"10K_nominal":10000.0,"10K_last_known_2026_09_16":9660.24,
              "100K_nominal":100000.0,"100K_last_known_2026_09_16":96405.60}
    rows_out=[]
    for account,balance in balances.items():
        for fraction in (.0025,.005,.01):
            for stop in (5.0,10.0,20.0,round(p90,2)):
                # Broker-specific spread at the future entry and gap slippage are unknown.
                theoretical=balance*fraction/(100*(stop+spread))
                rows_out.append({"account_reference":account,"balance_reference":balance,"risk_fraction":fraction,
                    "risk_cash":round(balance*fraction,2),"stop_move_usd":stop,"assumed_spread_usd":round(spread,4),
                    "theoretical_max_lots":round(theoretical,4),
                    "rounded_down_0_01_lot":math.floor(theoretical*100+1e-9)/100})
    return {"contract_ounces_per_lot":100,"median_reopen_spread_usd":spread,"observed_m1_reopen_4h_mae_p90":p90,
            "cash_change_by_move_per_lot":{str(d):100*d for d in (.5,1,2,5,10)},
            "limitations":"Historical 4h MAE is not a stop; future spread, commission, margin and gap slippage unknown; last-known balances are stale.",
            "rows":rows_out}


def secondary(rows):
    names = list(rows[0]["signals"])
    out = []
    for name in names:
        if name == "M1":
            continue
        for split in ("ALL", "IN_SAMPLE", "OUT_OF_SAMPLE"):
            chosen = [r for r in rows if r["signals"].get(name) and (split == "ALL" or r["split"] == split)]
            paths = [r["paths"][r["signals"][name]]["REOPEN"] for r in chosen]
            values = [p["return_240m"] for p in paths if p["return_240m"] is not None]
            state = [p["barrier_10"] for p in paths]
            out.append({"signal": name, "split": split, "n": len(chosen),
                        "four_hour": describe(values), "plus_10_first": state.count("FAVORABLE_FIRST"),
                        "minus_10_first": state.count("ADVERSE_FIRST"),
                        "ambiguous_or_censored": state.count("AMBIGUOUS_SAME_BAR")+state.count("CENSORED")})
    return out


def main(source, output):
    rows=[json.loads(line) for line in source.open()]
    result={"primary_signal":"last completed Friday M1 bid open-to-close direction",
            "primary":{split:{key:primary(rows,split,side) for key,side in (("combined",None),("BUY","BUY"),("SELL","SELL"))}
                       for split in ("ALL","IN_SAMPLE","OUT_OF_SAMPLE")},
            "entry_method_comparison":methods(rows),"risk_sizing":risk(rows),
            "secondary_signals_and_threshold_sensitivity":secondary(rows)}
    output.write_text(json.dumps(result,indent=2)+"\n")
    return result


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("source",type=Path);p.add_argument("output",type=Path)
    a=p.parse_args();main(a.source,a.output)
