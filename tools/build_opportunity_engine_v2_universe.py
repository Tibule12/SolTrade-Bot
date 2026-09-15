#!/usr/bin/env python3
"""Build independent dual-direction opportunities from preserved raw scans."""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
from collections import Counter, defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from opportunity_engine_v2_common import FEATURES, epoch, event_and_features, number

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/fast-multi-market-v2/opportunity-engine-v2-raw-rebuild-20260915"
HORIZON = 4 * 3600
EVALUATION_INTERVAL = 5 * 60
EPISODE_COOLDOWN = HORIZON


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()


def update_bar(bars: deque[dict[str, float]], minute: str, bid: float, minute_epoch: int | None = None) -> bool:
    if bars and bars[-1]["minute"] == minute:
        bars[-1]["high"] = max(bars[-1]["high"], bid); bars[-1]["low"] = min(bars[-1]["low"], bid); bars[-1]["close"] = bid
        return False
    opened = epoch(minute + ":00") if minute_epoch is None else minute_epoch
    bars.append({"minute": minute, "epoch": float(opened), "open": bid, "high": bid, "low": bid, "close": bid})
    return True


def new_path() -> dict[str, Any]:
    item = {"samples": 0, "mfe_r": 0.0, "mae_r": 0.0, "terminal_r": 0.0, "last_utc": "",
            "time_plus_0_5": "", "time_plus_1": "", "time_minus_0_5": "", "time_minus_1": "",
            "time_plus_2": "", "time_plus_3": "", "time_plus_5": ""}
    return item


def touch(path: dict[str, Any], stamp: str, r: float) -> None:
    path["samples"] += 1; path["mfe_r"] = max(path["mfe_r"], r); path["mae_r"] = min(path["mae_r"], r)
    for name, hit in (("plus_0_5", r >= .5), ("plus_1", r >= 1), ("minus_0_5", r <= -.5),
                      ("minus_1", r <= -1), ("plus_2", r >= 2), ("plus_3", r >= 3), ("plus_5", r >= 5)):
        if hit and not path["time_" + name]: path["time_" + name] = stamp
    path["terminal_r"] = r; path["last_utc"] = stamp


def finish(record: dict[str, Any]) -> dict[str, Any]:
    def result(prefix: str) -> str:
        plus, minus = record[prefix]["time_plus_1"], record[prefix]["time_minus_1"]
        if plus and (not minus or plus < minus): return "WIN_1R_BEFORE_STOP"
        if minus and (not plus or minus < plus): return "LOSS_STOP_BEFORE_1R"
        return "NO_BOUNDARY"
    long_result, short_result = result("long"), result("short")
    horizon_complete = bool(record["long"]["last_utc"]) and epoch(record["long"]["last_utc"]) >= record["end_epoch"] - 60
    if not horizon_complete: direction_label = "CENSORED"
    elif long_result.startswith("WIN") and short_result.startswith("WIN"): direction_label = "AMBIGUOUS"
    elif long_result.startswith("WIN"): direction_label = "LONG_EDGE"
    elif short_result.startswith("WIN"): direction_label = "SHORT_EDGE"
    else: direction_label = "NO_EDGE"
    output = {k: v for k, v in record.items() if k not in {"long", "short", "end_epoch", "entry_epoch", "nonspread_cost"}}
    output.update({"horizon_complete": horizon_complete, "direction_label": direction_label,
                   "long_primary_label": long_result, "short_primary_label": short_result})
    for prefix in ("long", "short"):
        path = record[prefix]
        for field in ("mfe_r", "mae_r", "terminal_r", "samples"):
            output[f"{prefix}_{field}"] = path[field]
        for level in ("plus_0_5", "plus_1", "minus_0_5", "minus_1", "plus_2", "plus_3", "plus_5"):
            stamp = path["time_" + level]
            output[f"{prefix}_seconds_to_{level}"] = epoch(stamp) - record["entry_epoch"] if stamp else ""
        output[f"{prefix}_plus_2_available"] = bool(path["time_plus_2"] and (not path["time_minus_1"] or path["time_plus_2"] < path["time_minus_1"]))
        output[f"{prefix}_plus_3_available"] = bool(path["time_plus_3"] and (not path["time_minus_1"] or path["time_plus_3"] < path["time_minus_1"]))
        output[f"{prefix}_plus_5_available"] = bool(path["time_plus_5"] and (not path["time_minus_1"] or path["time_plus_5"] < path["time_minus_1"]))
    return output


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--source", type=Path, required=True); ap.add_argument("--name", required=True); args = ap.parse_args()
    source = args.source.resolve(); scans = source / "scans.csv.gz"; OUT.mkdir(parents=True, exist_ok=True)
    bars: dict[str, deque[dict[str, float]]] = defaultdict(lambda: deque(maxlen=1900))
    active: dict[str, list[dict[str, Any]]] = defaultdict(list); last_evaluation: dict[str, int] = {}; last_event: dict[str, int] = {}; completed=[]; counter=0
    last_stamp = ""; now = 0
    with gzip.open(scans, "rt", newline="", encoding="utf-8-sig", errors="replace") as f:
        for row in csv.DictReader(f):
            stamp, symbol = row.get("utc", ""), row.get("symbol", ""); bid, ask = number(row.get("bid")), number(row.get("ask"))
            if not stamp or not symbol or bid <= 0 or ask <= 0: continue
            if stamp != last_stamp:
                last_stamp, now = stamp, epoch(stamp)
            is_new = update_bar(bars[symbol], stamp[:16], bid, now // 60 * 60)
            keep=[]
            for record in active[symbol]:
                if now > record["entry_epoch"] and now <= record["end_epoch"]:
                    touch(record["long"], stamp, (bid - record["long_entry"] - record["nonspread_cost"]) / record["long_risk"])
                    touch(record["short"], stamp, (record["short_entry"] - ask - record["nonspread_cost"]) / record["short_risk"])
                    keep.append(record)
                elif now <= record["entry_epoch"]: keep.append(record)
                else: completed.append(finish(record))
            active[symbol] = keep
            if not is_new or now - last_evaluation.get(symbol, -10**12) < EVALUATION_INTERVAL: continue
            last_evaluation[symbol] = now
            if now - last_event.get(symbol, -10**12) < EPISODE_COOLDOWN: continue
            completed_bars = list(bars[symbol])[:-1]
            event = event_and_features(completed_bars, now, bid, ask, number(row.get("expected_cost_move")))
            if event is None: continue
            family, event_direction, values = event; counter += 1; last_event[symbol] = now
            record: dict[str, Any] = {"opportunity_id": f"{args.name}-{counter:06d}", "source_partition": args.name,
                "symbol": symbol, "event_family": family, "first_observed_utc": stamp, "causal_entry_utc": stamp,
                "event_direction_hypothesis": "LONG" if event_direction > 0 else "SHORT",
                "structure_context": json.dumps({"trend_m1":values["trend_m1"],"trend_m5":values["trend_m5"],
                    "trend_m15":values["trend_m15"],"trend_h1":values["trend_h1"],
                    "event_direction":event_direction},separators=(",",":")),
                "expiry_utc": datetime.fromtimestamp(now + HORIZON, tz=timezone.utc).strftime("%Y.%m.%d %H:%M:%S"),
                "expiry_utc_epoch": now + HORIZON,
                **values, "entry_epoch": now, "end_epoch": now + HORIZON, "nonspread_cost": values["nonspread_cost"],
                "long": new_path(), "short": new_path()}
            active[symbol].append(record)
    for records in active.values():
        completed.extend(finish(record) for record in records)
    completed.sort(key=lambda x: x["causal_entry_utc"])
    path = OUT / f"opportunities-{args.name}.csv"; fields=list(completed[0])
    with path.open("w", newline="", encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=fields,lineterminator="\n");w.writeheader();w.writerows(completed)
    distribution=Counter(x["event_family"] for x in completed); labels=Counter(x["direction_label"] for x in completed)
    manifest={"schema":"OPPORTUNITY_ENGINE_V2_PARTITION_V1","source":str(scans.relative_to(ROOT)),"source_sha256":sha(scans),
              "partition":args.name,"opportunities":len(completed),"event_family_distribution":dict(distribution),
              "direction_labels":dict(labels),"evaluation_interval_seconds":EVALUATION_INTERVAL,
              "episode_cooldown_seconds":EPISODE_COOLDOWN,"horizon_seconds":HORIZON,
              "production_scores_used":False,"production_direction_used":False,"orders_possible":False,
              "features":list(FEATURES),"first_utc":completed[0]["causal_entry_utc"],"last_utc":completed[-1]["causal_entry_utc"],
              "dataset":str(path.relative_to(ROOT)),"dataset_sha256":sha(path)}
    (OUT/f"manifest-{args.name}.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print(json.dumps(manifest,indent=2)); return 0


if __name__ == "__main__": raise SystemExit(main())
