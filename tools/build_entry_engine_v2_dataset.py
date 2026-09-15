#!/usr/bin/env python3
"""Build the pre-holdout ENTRY_ENGINE_V2 dataset from preserved native files."""
from __future__ import annotations

import csv
import gzip
import hashlib
import json
import argparse
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

from entry_engine_v2_common import evidence_features, epoch, number

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "reports/fast-multi-market-v2/validation-20260907/baseline-summer-2026-b/raw"
OUT = ROOT / "reports/fast-multi-market-v2/entry-engine-v2-clean-rebuild-20260915"
HORIZON_SECONDS = 4 * 3600


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_entries(evidence: Path) -> list[dict[str, str]]:
    with gzip.open(evidence, "rt", newline="", encoding="utf-8-sig") as handle:
        return [row for row in csv.DictReader(handle) if row.get("event") == "ENTRY"]


def update_bar(bars: deque[dict[str, float]], minute: str, bid: float) -> None:
    if bars and bars[-1]["minute"] == minute:
        bars[-1]["high"] = max(bars[-1]["high"], bid)
        bars[-1]["low"] = min(bars[-1]["low"], bid)
        bars[-1]["close"] = bid
        return
    bars.append({"minute": minute, "epoch": float(epoch(minute + ":00")), "open": bid,
                 "high": bid, "low": bid, "close": bid})


def touch(record: dict[str, Any], stamp: str, r: float) -> None:
    record["samples"] += 1
    record["mfe_r"] = max(record["mfe_r"], r)
    record["mae_r"] = min(record["mae_r"], r)
    was_stopped = record.get("time_minus_1") is not None
    if not was_stopped:
        record["mfe_before_stop_r"] = max(record["mfe_before_stop_r"], r)
        record["mae_before_stop_r"] = min(record["mae_before_stop_r"], r)
    for name, level, relation in (("plus_0_5", .5, r >= .5), ("plus_1", 1, r >= 1),
                                  ("minus_0_5", -.5, r <= -.5), ("minus_1", -1, r <= -1),
                                  ("plus_2", 2, r >= 2), ("plus_3", 3, r >= 3), ("plus_5", 5, r >= 5)):
        if relation and record.get("time_" + name) is None:
            record["time_" + name] = stamp
    if record.get("time_plus_1") is not None:
        record["maximum_continuation_after_plus_1_r"] = max(record["maximum_continuation_after_plus_1_r"], r)
        if not was_stopped:
            record["maximum_tradable_continuation_after_plus_1_r"] = max(record["maximum_tradable_continuation_after_plus_1_r"], r)
    record["terminal_r"] = r
    record["last_quote_utc"] = stamp


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--dataset", default="development-dataset.csv")
    parser.add_argument("--manifest", default="dataset-manifest.json")
    args = parser.parse_args()
    evidence = (args.source / "evidence.csv.gz").resolve()
    scans = (args.source / "scans.csv.gz").resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    entries = load_entries(evidence)
    by_key: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in entries:
        by_key[(row["utc"], row["symbol"])].append(row)
    event_queues: dict[str, deque[tuple[str, list[dict[str, str]]]]] = defaultdict(deque)
    for (stamp, symbol), rows in sorted(by_key.items()):
        event_queues[symbol].append((stamp, rows))
    bars: dict[str, deque[dict[str, float]]] = defaultdict(lambda: deque(maxlen=720))
    pending = {(row["utc"], row["symbol"], row["ticket"]): row for row in entries}
    active: dict[str, list[dict[str, Any]]] = defaultdict(list)
    score_history: dict[str, deque[tuple[int, float, float]]] = defaultdict(deque)
    completed: list[dict[str, Any]] = []
    matched: set[str] = set()

    last_stamp = ""
    now = 0
    with gzip.open(scans, "rt", newline="", encoding="utf-8-sig", errors="replace") as handle:
        for scan in csv.DictReader(handle):
            stamp, symbol = scan.get("utc", ""), scan.get("symbol", "")
            if not stamp or not symbol:
                continue
            bid, ask = number(scan.get("bid")), number(scan.get("ask"))
            if bid <= 0 or ask <= 0:
                continue
            update_bar(bars[symbol], stamp[:16], bid)
            if stamp != last_stamp:
                last_stamp, now = stamp, epoch(stamp)
            score_history[symbol].append((now, number(scan.get("buy_score")), number(scan.get("sell_score"))))
            while score_history[symbol] and score_history[symbol][0][0] < now - 600:
                score_history[symbol].popleft()

            # First scan at/after the evidence timestamp materializes the entry;
            # all feature bars end before the evidence timestamp.
            queue = event_queues[symbol]
            while queue and queue[0][0] <= stamp:
                event_stamp, events = queue.popleft()
                if now - epoch(event_stamp) > 15:
                    continue
                for event in events:
                    direction = 1 if event["direction"] == "BUY" else -1
                    current_buy, current_sell = number(scan.get("buy_score")), number(scan.get("sell_score"))
                    prior_score = next((item for item in score_history[symbol] if item[0] >= now-300), score_history[symbol][0])
                    current_proposed, current_opposing = (current_buy, current_sell) if direction > 0 else (current_sell, current_buy)
                    prior_proposed, prior_opposing = (prior_score[1], prior_score[2]) if direction > 0 else (prior_score[2], prior_score[1])
                    elapsed = max(1.0, (now-prior_score[0])/60.0)
                    scan_context = {"proposed_score_rate_5m": (current_proposed-prior_proposed)/elapsed,
                                    "opposing_score_rate_5m": (current_opposing-prior_opposing)/elapsed}
                    try:
                        features = evidence_features(event, list(bars[symbol]), scan_context)
                    except ValueError:
                        continue
                    entry_price = number(event["entry"])
                    spread = number(event["spread"])
                    nonspread = max(0.0, number(event["expected_cost_move"]) - spread)
                    price_risk = abs(entry_price - number(event["stop"]))
                    denominator = price_risk + nonspread
                    record: dict[str, Any] = {
                        "position_id": event["ticket"], "entry_utc": event["utc"], "symbol": symbol,
                        "direction": event["direction"], "entry_price": entry_price,
                        "original_stop": number(event["stop"]), "price_risk": price_risk,
                        "nonspread_cost": nonspread, "risk_including_cost": denominator,
                        "horizon_seconds": HORIZON_SECONDS, "feature_status": "COMPLETE", **features,
                        "samples": 0, "mfe_r": 0.0, "mae_r": 0.0, "mfe_before_stop_r": 0.0,
                        "mae_before_stop_r": 0.0, "terminal_r": 0.0,
                        "last_quote_utc": event["utc"], "maximum_continuation_after_plus_1_r": 0.0,
                        "maximum_tradable_continuation_after_plus_1_r": 0.0,
                    }
                    for field in ("plus_0_5", "plus_1", "minus_0_5", "minus_1", "plus_2", "plus_3", "plus_5"):
                        record["time_" + field] = None
                    record["end_epoch"] = epoch(event["utc"]) + HORIZON_SECONDS
                    record["entry_epoch"] = epoch(event["utc"])
                    record["_direction"] = direction
                    active[symbol].append(record)
                    matched.add(event["ticket"])

            keep = []
            for record in active[symbol]:
                if now <= record["entry_epoch"]:
                    keep.append(record)
                    continue
                if now <= record["end_epoch"]:
                    exit_price = bid if record["_direction"] > 0 else ask
                    net_move = record["_direction"] * (exit_price - record["entry_price"]) - record["nonspread_cost"]
                    touch(record, stamp, net_move / record["risk_including_cost"])
                    keep.append(record)
                else:
                    record["horizon_complete"] = epoch(record["last_quote_utc"]) >= record["end_epoch"] - 60
                    completed.append(record)
            active[symbol] = keep

    for records in active.values():
        for record in records:
            record["horizon_complete"] = epoch(record["last_quote_utc"]) >= record["end_epoch"] - 60
            completed.append(record)

    for record in completed:
        plus, minus = record["time_plus_1"], record["time_minus_1"]
        if plus is not None and (minus is None or plus < minus):
            record["primary_label"] = "WIN_1R_BEFORE_STOP"
            record["resolved_payoff_r"] = 1.0
        elif minus is not None and (plus is None or minus < plus):
            record["primary_label"] = "LOSS_STOP_BEFORE_1R"
            record["resolved_payoff_r"] = -1.0
        else:
            record["primary_label"] = "CENSORED_NO_BOUNDARY"
            record["resolved_payoff_r"] = None
        record["available_plus_2r"] = record["time_plus_2"] is not None and (minus is None or record["time_plus_2"] < minus)
        record["available_plus_3r"] = record["time_plus_3"] is not None and (minus is None or record["time_plus_3"] < minus)
        record["available_plus_5r"] = record["time_plus_5"] is not None and (minus is None or record["time_plus_5"] < minus)
        for field in ("plus_0_5", "plus_1", "minus_0_5", "minus_1", "plus_2", "plus_3", "plus_5"):
            record["seconds_to_" + field] = epoch(record["time_" + field]) - epoch(record["entry_utc"]) if record["time_" + field] else None
        for field in ("entry_epoch", "end_epoch", "_direction", "m1_atr", "m5_atr"):
            record.pop(field, None)
    completed.sort(key=lambda row: row["entry_utc"])
    omitted_ids = sorted({row["ticket"] for row in entries} - {row["position_id"] for row in completed})
    if not completed:
        raise SystemExit("no entries had complete causal feature coverage")

    fields = list(completed[0])
    with (OUT / args.dataset).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader(); writer.writerows(completed)
    manifest = {
        "schema": "ENTRY_ENGINE_V2_DATASET_MANIFEST_V1", "created_from_existing_artifacts_only": True,
        "orders_possible": False, "development_start_utc": completed[0]["entry_utc"],
        "development_end_utc": completed[-1]["entry_utc"], "locked_holdout_start": "2026.09.08 00:00:00",
        "label_horizon_seconds": HORIZON_SECONDS, "source_entries": len(entries),
        "entries": len(completed), "omitted_incomplete_feature_ids": omitted_ids,
        "resolved": sum(row["primary_label"] != "CENSORED_NO_BOUNDARY" for row in completed),
        "wins": sum(row["primary_label"] == "WIN_1R_BEFORE_STOP" for row in completed),
        "losses": sum(row["primary_label"] == "LOSS_STOP_BEFORE_1R" for row in completed),
        "censored": sum(row["primary_label"] == "CENSORED_NO_BOUNDARY" for row in completed),
        "sources": [{"path": str(evidence.relative_to(ROOT)), "sha256": sha256(evidence)},
                    {"path": str(scans.relative_to(ROOT)), "sha256": sha256(scans)}],
        "label": "+1.00 net executable R before -1.00 net executable R; entry ask/bid and exit bid/ask; recorded expected non-spread cost included; fixed 4h horizon",
        "feature_cutoff": "completed M1/M5/M15 bars and entry evidence available strictly before/at candidate entry; forming minute excluded",
    }
    (OUT / args.manifest).write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
