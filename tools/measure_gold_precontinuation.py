#!/usr/bin/env python3
"""Adverse gold movement strictly before a winning M1 Monday price boundary."""

import argparse
import json
import math
from datetime import date, timedelta
from pathlib import Path
from statistics import median

from analyze_gold_weekend_expanded import load, extremes


def measure(history, weekend_rows):
    days, _, _ = load(history)
    result = {}
    for threshold in (5, 10, 20):
        values = []
        first_bar = 0
        for row in weekend_rows:
            side = row["signals"]["M1"]
            if not side:
                continue
            path = row["paths"][side]["REOPEN"]
            if path[f"barrier_{threshold}"] != "FAVORABLE_FIRST":
                continue
            monday = days[date.fromisoformat(row["monday"])]
            entry = path["entry_price_estimate"]
            beginning = monday[0][0]
            prior_low = 0.0
            found = False
            for i, bar in enumerate(monday):
                if bar[0] > beginning+timedelta(hours=4):
                    break
                favorable, adverse = extremes(side, entry, bar)
                if favorable >= threshold:
                    # Exclude this bar: its high and low have unknown order.
                    values.append(max(0.0, -prior_low))
                    first_bar += i == 0
                    found = True
                    break
                prior_low = min(prior_low, adverse)
            if not found:
                raise ValueError("Favorable-first receipt has no corresponding M1 crossing")
        ordered = sorted(values)
        result[str(threshold)] = {"favorable_first_paths":len(values),
            "first_bar_favorable_paths":first_bar,
            "median_prior_adverse_usd":round(median(values),4) if values else None,
            "p90_prior_adverse_usd":round(ordered[math.ceil(.9*len(ordered))-1],4) if values else None,
            "definition":"Worst executable-side adverse quote on completed bars strictly before the first favorable-boundary bar; boundary bar excluded because M1 high/low order is unknown"}
    return result


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("history", type=Path)
    p.add_argument("weekends", type=Path)
    p.add_argument("output", type=Path)
    a = p.parse_args()
    rows = [json.loads(line) for line in a.weekends.open()]
    a.output.write_text(json.dumps(measure(a.history, rows), indent=2)+"\n")
