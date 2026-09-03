#!/usr/bin/env python3
"""Replay setup-family M1 timing gates from read-only FP broker tick aggregates."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


TIME_FORMAT = "%Y.%m.%d %H:%M:%S"

# Outcomes come from the immutable execution evidence ledger. US500 is one
# reference signal executed on FXIFY but evaluated against FP broker bars.
CASES = [
    ("20260831_US100_SELL", "2026.08.31 03:13:40", -1, -247.13, 247.13, "STRUCTURE_INSIDE", "FP"),
    ("20260831_XAUUSD_SELL", "2026.08.31 05:54:30", -1, -234.78, 234.78, "BREAKOUT_DOWN", "FP"),
    ("20260831_GER40_BUY", "2026.08.31 09:02:20", 1, -246.04, 246.06, "CLEAN_BULL_PULLBACK", "FP"),
    ("20260831_EURUSD_BUY", "2026.08.31 11:17:10", 1, -245.18, 245.18, "STRUCTURE_INSIDE", "FP"),
    ("20260831_GER40_SELL_1", "2026.08.31 18:06:30", -1, 37.97, 244.78, "BREAKOUT_DOWN", "FP"),
    ("20260831_GER40_SELL_2", "2026.08.31 20:49:10", -1, 260.45, 244.78, None, "FP"),
    ("20260901_XAUUSD_SELL_1", "2026.09.01 13:20:40", -1, -7.92, 243.00, "FAILED_BREAKOUT_UP", "FP"),
    ("20260901_GER40_SELL_1", "2026.09.01 13:21:30", -1, -11.64, 245.52, "CLEAN_BEAR_PULLBACK", "FP"),
    ("20260901_US100_SELL", "2026.09.01 13:22:10", -1, -7.81, 245.37, "CLEAN_BEAR_PULLBACK", "FP"),
    ("20260901_XAUUSD_SELL_2", "2026.09.01 16:35:50", -1, -3.52, 237.76, "STRUCTURE_INSIDE", "FP"),
    ("20260901_XAUUSD_SELL_3", "2026.09.01 21:25:40", -1, 365.28, 240.96, None, "FP"),
    ("20260901_GER40_SELL_2", "2026.09.01 22:04:10", -1, -12.34, 246.30, None, "FP"),
    ("20260902_GBPJPY_SELL", "2026.09.02 10:13:30", -1, -247.68, 246.27, "STRUCTURE_INSIDE", "FP"),
    ("20260902_EURJPY_SELL", "2026.09.02 10:16:50", -1, 30.03, 246.01, "STRUCTURE_INSIDE", "FP"),
    ("20260902_US500_BUY_REFERENCE", "2026.09.02 18:00:42", 1, 148.18, 246.14, "STRUCTURE_INSIDE", "FXIFY_SIGNAL_FP_BARS"),
    ("20260903_USDJPY_SELL", "2026.09.03 04:58:20", -1, 582.25, 245.74, "STRUCTURE_INSIDE", "FP"),
]


def mean(values):
    return sum(values) / len(values) if values else 0.0


def true_range(current, previous):
    return max(
        current["high"] - current["low"],
        abs(current["high"] - previous["close"]),
        abs(current["low"] - previous["close"]),
    )


def feature_set(ascending, entry, direction, logged_behaviour):
    completed = [bar for bar in ascending if bar["time"] + timedelta(minutes=1) <= entry]
    recent = list(reversed(completed))
    if len(recent) < 31:
        raise ValueError(f"only {len(recent)} completed M1 bars before {entry}")

    atr1 = mean([true_range(recent[i], recent[i + 1]) for i in range(20)])
    trend1 = (mean([x["close"] for x in recent[:8]]) - mean([x["close"] for x in recent[:30]])) / atr1
    travelled = sum(abs(recent[i]["close"] - recent[i + 1]["close"]) for i in range(20))
    efficiency1 = abs(recent[0]["close"] - recent[20]["close"]) / travelled if travelled else 0.0

    pullback_shift = 0
    reclaim_level = 0.0
    pullback_depth_atr = 0.0
    for shift in range(2, 5):
        bar = recent[shift - 1]
        older = recent[shift]
        signed_body = direction * (bar["close"] - bar["open"])
        retraced = bar["low"] < older["close"] if direction > 0 else bar["high"] > older["close"]
        if signed_body >= 0 or not retraced:
            continue
        pullback_shift = shift
        reclaim_level = bar["high"] if direction > 0 else bar["low"]
        adverse_extreme = bar["low"] if direction > 0 else bar["high"]
        pullback_depth_atr = direction * (older["close"] - adverse_extreme) / atr1
        break
    reclaim = bool(
        pullback_shift
        and direction * (recent[0]["close"] - reclaim_level) > 0
        and direction * (recent[0]["close"] - recent[0]["open"]) > 0
    )

    # Aggregate only completed M1 bars into M5; an M5 bucket is usable only if
    # all five constituent minutes ended before admission.
    buckets = defaultdict(list)
    for bar in completed:
        bucket = bar["time"].replace(minute=(bar["time"].minute // 5) * 5, second=0)
        if bucket + timedelta(minutes=5) <= entry:
            buckets[bucket].append(bar)
    m5 = []
    for bucket, bars in sorted(buckets.items()):
        bars.sort(key=lambda x: x["time"])
        if len(bars) != 5:
            continue
        m5.append({
            "time": bucket,
            "open": bars[0]["open"],
            "high": max(x["high"] for x in bars),
            "low": min(x["low"] for x in bars),
            "close": bars[-1]["close"],
        })
    m5_recent = list(reversed(m5))
    if len(m5_recent) < 22:
        raise ValueError(f"only {len(m5_recent)} complete M5 bars before {entry}")
    prior_high = max(x["high"] for x in m5_recent[1:21])
    prior_low = min(x["low"] for x in m5_recent[1:21])
    anchor = prior_high if direction > 0 else prior_low
    breakout_now = direction * (m5_recent[0]["close"] - anchor) > 0
    retention = 0
    if breakout_now:
        for bar in recent[:5]:
            if direction * (bar["close"] - anchor) <= 0:
                break
            retention += 1

    behaviour = logged_behaviour or ("BREAKOUT_UP" if direction > 0 and breakout_now else
                                     "BREAKOUT_DOWN" if direction < 0 and breakout_now else "STRUCTURE_INSIDE")
    if behaviour.startswith("BREAKOUT_"):
        family = "BREAKOUT"
    elif behaviour.startswith("FAILED_BREAKOUT_") or "PULLBACK" in behaviour or "REJECTION" in behaviour:
        family = "PULLBACK_REVERSAL"
    else:
        family = "CONTINUATION"

    body1 = direction * (recent[0]["close"] - recent[0]["open"])
    momentum3 = direction * (recent[0]["close"] - recent[2]["close"])
    return {
        "completed_m1_time": recent[0]["time"].strftime(TIME_FORMAT),
        "trend_m1": trend1,
        "path_efficiency_m1": efficiency1,
        "last_bar_directional": body1 > 0,
        "three_bar_directional": momentum3 > 0,
        "pullback_shift": pullback_shift,
        "pullback_depth_atr": pullback_depth_atr,
        "reclaim_confirmed": reclaim,
        "m5_breakout_at_entry": breakout_now,
        "breakout_anchor": anchor,
        "breakout_retention_bars": retention,
        "breakout_retained": retention >= 2,
        "behaviour": behaviour,
        "family": family,
    }


def decisions(features):
    continuation = features["last_bar_directional"] or features["three_bar_directional"]
    setup_timing = {
        "CONTINUATION": continuation,
        "PULLBACK_REVERSAL": features["reclaim_confirmed"],
        "BREAKOUT": features["breakout_retained"],
    }[features["family"]]
    return {
        "NO_M1_GATE": True,
        "UNIVERSAL_M1_TREND": features["trend_m1"] > 0.20 and features["path_efficiency_m1"] >= 0.24,
        "UNIVERSAL_RECLAIM_OR_RETENTION": features["reclaim_confirmed"] or features["breakout_retained"],
        "SETUP_FAMILY_TIMING_V1": setup_timing,
    }


def summarize(rows, split, rule):
    sample = [x for x in rows if x["split"] == split]
    accepted = [x for x in sample if x["decisions"][rule]]
    rejected = [x for x in sample if not x["decisions"][rule]]
    winners = [x for x in sample if x["net"] > 0]
    losers = [x for x in sample if x["net"] <= 0]
    return {
        "trades": len(sample),
        "accepted": len(accepted),
        "rejected": len(rejected),
        "accepted_net": round(sum(x["net"] for x in accepted), 2),
        "winner_retention": round(sum(x["net"] for x in accepted if x["net"] > 0) / sum(x["net"] for x in winners), 6) if winners else 0,
        "loser_rejection": round(len([x for x in losers if not x["decisions"][rule]]) / len(losers), 6) if losers else 0,
        "rejected_winners": [x["case"] for x in rejected if x["net"] > 0],
        "accepted_losers": [x["case"] for x in accepted if x["net"] <= 0],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bars", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--features-csv", type=Path, required=True)
    args = parser.parse_args()

    grouped = defaultdict(list)
    with args.bars.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            grouped[row["case"]].append({
                "time": datetime.strptime(row["bar_broker_time"], "%Y.%m.%d %H:%M"),
                "open": float(row["bid_open"]),
                "high": float(row["bid_high"]),
                "low": float(row["bid_low"]),
                "close": float(row["bid_close"]),
            })

    rows = []
    for name, timestamp, direction, net, risk, behaviour, source in CASES:
        entry = datetime.strptime(timestamp, TIME_FORMAT)
        features = feature_set(sorted(grouped[name], key=lambda x: x["time"]), entry, direction, behaviour)
        if direction < 0:
            features["trend_m1"] *= -1  # positive means aligned with the executed side
        item = {
            "case": name,
            "entry_broker_time": timestamp,
            "direction": "BUY" if direction > 0 else "SELL",
            "net": net,
            "realized_r": round(net / risk, 6),
            "outcome": "WIN" if net > 0 else "LOSS_OR_SCRATCH",
            "source": source,
            "split": "DEVELOPMENT" if entry.date().isoformat() < "2026-09-02" else "OUT_OF_SAMPLE",
            **features,
        }
        item["decisions"] = decisions(item)
        rows.append(item)

    rules = list(rows[0]["decisions"])
    metrics = {rule: {split: summarize(rows, split, rule) for split in ("DEVELOPMENT", "OUT_OF_SAMPLE")} for rule in rules}
    oos_independent_fp = [x for x in rows if x["split"] == "OUT_OF_SAMPLE" and x["source"] == "FP"]
    candidate = metrics["SETUP_FAMILY_TIMING_V1"]["OUT_OF_SAMPLE"]
    promotion_pass = (
        len(oos_independent_fp) >= 8
        and candidate["winner_retention"] >= 0.80
        and candidate["loser_rejection"] >= 0.50
        and not candidate["accepted_losers"]
    )
    report = {
        "schema": "SOLTRADE_V202_M1_SETUP_TIMING_AUDIT_V1",
        "scope": "FP V2.202 research only; FXIFY untouched; live strategy unchanged",
        "bar_source": str(args.bars),
        "data_controls": {
            "feature_cutoff": "completed broker M1 bars only; current/future bar excluded",
            "development_period": "2026-08-31 through 2026-09-01",
            "out_of_sample_period": "2026-09-02 through 2026-09-03",
            "us500_note": "one FXIFY signal evaluated on FP bars; excluded from independent-FP sample count",
        },
        "rules": {
            "UNIVERSAL_M1_TREND": "side-aligned M1 trend > 0.20 and path efficiency >= 0.24",
            "UNIVERSAL_RECLAIM_OR_RETENTION": "M1 pullback reclaim OR two closed M1 breakout-retention bars",
            "SETUP_FAMILY_TIMING_V1": {
                "CONTINUATION": "last completed M1 body or three-bar close change resumes trade direction",
                "PULLBACK_REVERSAL": "last completed M1 closes through the detected pullback reclaim level with a directional body",
                "BREAKOUT": "two consecutive completed M1 closes retain the M5 breakout anchor",
            },
        },
        "metrics": metrics,
        "out_of_sample_independent_fp_trades": len(oos_independent_fp),
        "promotion_acceptance": {
            "minimum_independent_fp_oos_trades": 8,
            "minimum_winner_retention": 0.80,
            "minimum_loser_rejection": 0.50,
            "accepted_losers_allowed": 0,
            "pass": promotion_pass,
        },
        "decision": "PROMOTE" if promotion_pass else "DO_NOT_PROMOTE_KEEP_SHADOW",
        "trades": rows,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    flat_keys = [key for key in rows[0] if key != "decisions"] + rules
    with args.features_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=flat_keys, lineterminator="\n")
        writer.writeheader()
        for item in rows:
            writer.writerow({**{k: v for k, v in item.items() if k != "decisions"}, **item["decisions"]})
    print(json.dumps({"decision": report["decision"], "metrics": metrics}, indent=2))


if __name__ == "__main__":
    main()
