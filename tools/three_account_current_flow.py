#!/usr/bin/env python3
"""Frozen causal tick-flow descriptor for actual FP entries; no order decisions."""

import csv
import json
import statistics
from collections import Counter, defaultdict

try:
    from tools.three_account_first_move import BASE, read_deals, quotes
except ModuleNotFoundError:
    from three_account_first_move import BASE, read_deals, quotes


RULE_ID = "CURRENT_FLOW_QUOTE_V1_PREDECLARED_20261001"


def classify(pre_entry, execution_msc):
    """Use only <=execution quotes; fixed minimum evidence and thresholds."""
    thirty = [q for q in pre_entry if execution_msc - 30_000 <= q["ms"] <= execution_msc]
    five = [q for q in thirty if q["ms"] >= execution_msc - 5_000]
    if len(thirty) < 6 or len(five) < 3 or execution_msc - five[-1]["ms"] > 2_000:
        return {"flow": "UNAVAILABLE", "strong": False, "pressure_5s": None,
                "velocity_5s": None, "burst_5v30": None, "spread_ratio_30s": None}
    mids = [(q["bid"] + q["ask"]) / 2 for q in five]
    changes = [b - a for a, b in zip(mids, mids[1:])]
    nonzero = sum(x != 0 for x in changes)
    pressure = sum((x > 0) - (x < 0) for x in changes) / nonzero if nonzero else 0.0
    velocity = mids[-1] - mids[0]
    rate_5 = len(five) / 5
    rate_30 = len(thirty) / 30
    burst = rate_5 / rate_30 if rate_30 else None
    spreads = [q["ask"] - q["bid"] for q in thirty]
    median_spread = statistics.median(spreads)
    spread_ratio = spreads[-1] / median_spread if median_spread > 0 else None
    clean_spread = spread_ratio is not None and spread_ratio <= 1.5
    flow = "NEUTRAL"
    if clean_spread and pressure >= 0.25 and velocity > 0:
        flow = "LONG"
    elif clean_spread and pressure <= -0.25 and velocity < 0:
        flow = "SHORT"
    strong = flow != "NEUTRAL" and abs(pressure) >= 0.5 and burst is not None and burst >= 1.2
    return {"flow": flow, "strong": strong, "pressure_5s": pressure,
            "velocity_5s": velocity, "burst_5v30": burst, "spread_ratio_30s": spread_ratio}


def run(deals_path, ticks_dir, scores_path):
    with scores_path.open(newline="") as handle:
        recorded = {r["position_id"]: r for r in csv.DictReader(handle)}
    rows = []
    for position, legs in read_deals(deals_path).items():
        opening = [r for r in legs if r["entry"] == "0"]
        closes = [r for r in legs if r["entry"] == "1"]
        tick_path = ticks_dir / f"ticks-fp-entry-{position}.csv"
        if len(opening) != 1 or not closes or not tick_path.exists():
            continue
        first = opening[0]
        entry_msc = int(first["time_msc"])
        q = quotes(tick_path)
        descriptor = classify(q, entry_msc)
        production = "LONG" if first["type"] == "0" else "SHORT"
        actual = recorded.get(position, {})
        net = sum(float(r[k]) for r in legs for k in ("profit", "commission", "swap", "fee"))
        flow = descriptor["flow"]
        rows.append({
            "account": "FP 7404213", "position_id": position, "symbol": first["symbol"],
            "entry_server_msc": entry_msc, "production_direction": production,
            "flow_direction": flow,
            "flow_agrees": flow == production if flow in ("LONG", "SHORT") else None,
            "strong_opposite": descriptor["strong"] and flow != production,
            "pressure_5s": descriptor["pressure_5s"], "velocity_5s": descriptor["velocity_5s"],
            "burst_5v30": descriptor["burst_5v30"], "spread_ratio_30s": descriptor["spread_ratio_30s"],
            "actual_baseline_net_cash": round(net, 2), "actual_baseline_r_if_recorded": actual.get("final_r") or None,
            "actual_bank1_if_recorded": actual.get("bank1_confirmed") if actual else None,
            "actual_initial_stop_if_recorded": actual.get("exit_class") == "INITIAL_STRUCTURAL_STOP_EXIT" if actual else None,
            "model_id": RULE_ID, "feature_cutoff_server_msc": entry_msc,
            "status": "CAUSAL_DESCRIPTOR_ONLY__ALTERNATIVE_ACCOUNT_PATH_UNRESOLVED",
        })
    return sorted(rows, key=lambda r: (r["entry_server_msc"], r["position_id"]))


def summarize(rows):
    summary = {}
    for group in ("AGREES", "OPPOSES", "NEUTRAL", "UNAVAILABLE"):
        cohort = [r for r in rows if (
            (group == "AGREES" and r["flow_agrees"] is True) or
            (group == "OPPOSES" and r["flow_agrees"] is False) or
            (group == "NEUTRAL" and r["flow_direction"] == "NEUTRAL") or
            (group == "UNAVAILABLE" and r["flow_direction"] == "UNAVAILABLE"))]
        summary[group] = {"n": len(cohort), "wins": sum(r["actual_baseline_net_cash"] > 0 for r in cohort),
                          "losses": sum(r["actual_baseline_net_cash"] < 0 for r in cohort),
                          "actual_net_cash": round(sum(r["actual_baseline_net_cash"] for r in cohort), 2),
                          "recorded_r_n": sum(r["actual_baseline_r_if_recorded"] is not None for r in cohort),
                          "recorded_net_r": sum(float(r["actual_baseline_r_if_recorded"] or 0) for r in cohort)}
    return summary


def main():
    rows = run(BASE / "broker-refresh-fp/deals.csv", BASE / "fp-entry-window-ticks", BASE / "fp-score-trades.csv")
    with (BASE / "fp-current-flow-entries.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    result = {
        "schema": "FP_CURRENT_FLOW_ENTRY_DESCRIPTOR_V1", "rule_id": RULE_ID,
        "frozen_rule": "Last <=entry 30s needs >=6 quotes; last <=entry 5s needs >=3 and freshest <=2s. Direction requires 5s nonzero quote pressure >=+0.25 and positive mid velocity (LONG), or <=-0.25 and negative velocity (SHORT), with current spread <=1.5x 30s median. Strong needs |pressure|>=0.5 and 5s/30s tick-rate ratio >=1.2. Otherwise NEUTRAL/UNAVAILABLE.",
        "leakage_guard": "Only broker ticks with server_msc <= actual deal execution msc are passed to classifier.",
        "summary": summarize(rows),
        "interpretation": "Actual-outcome association for entered trades only. The four requested flow policy arms require alternative fills, stops, manager and propagated account sizing; they are not computed from this descriptor.",
    }
    (BASE / "fp-current-flow-summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["summary"]))


if __name__ == "__main__":
    main()
