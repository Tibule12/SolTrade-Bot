#!/usr/bin/env python3
"""Measure FP broker quote movement after actual fills; diagnostic, never an entry rule."""

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
HORIZONS = (5, 15, 30, 60, 120, 300)
OFFSET_MS = 3 * 60 * 60 * 1000


def read_deals(path):
    grouped = defaultdict(list)
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["position_id"] != "0":
                grouped[row["position_id"]].append(row)
    return grouped


def quotes(path):
    with path.open(newline="") as handle:
        result = [dict(ms=int(r["time_msc"]), bid=float(r["bid"]), ask=float(r["ask"])) for r in csv.DictReader(handle)]
    return sorted((r for r in result if r["bid"] > 0 and r["ask"] >= r["bid"]), key=lambda r: r["ms"])


def first_move(quote_rows, entry_msc, direction, horizon_seconds, max_stale_ms=2000):
    previous = [r for r in quote_rows if entry_msc - max_stale_ms <= r["ms"] <= entry_msc]
    if not previous:
        return {"status": "NO_FRESH_ENTRY_QUOTE", "first_direction": None, "first_move_ms": None,
                "mid_move_at_horizon": None, "spread_at_entry": None}
    anchor = previous[-1]
    anchor_mid = (anchor["bid"] + anchor["ask"]) / 2
    side = 1 if direction == "BUY" else -1
    end = entry_msc + horizon_seconds * 1000
    later = [r for r in quote_rows if entry_msc < r["ms"] <= end]
    if not later:
        return {"status": "NO_POST_ENTRY_QUOTE", "first_direction": None, "first_move_ms": None,
                "mid_move_at_horizon": None, "spread_at_entry": anchor["ask"] - anchor["bid"]}
    first = next((r for r in later if side * (((r["bid"] + r["ask"]) / 2) - anchor_mid) != 0), None)
    last = later[-1]
    final_move = side * (((last["bid"] + last["ask"]) / 2) - anchor_mid)
    return {
        "status": "OBSERVED", "first_direction": (
            "WITH_ENTRY" if side * (((first["bid"] + first["ask"]) / 2) - anchor_mid) > 0 else "AGAINST_ENTRY"
        ) if first else "NO_MOVE",
        "first_move_ms": first["ms"] - entry_msc if first else None,
        "mid_move_at_horizon": final_move,
        "spread_at_entry": anchor["ask"] - anchor["bid"],
        "last_quote_lag_ms": end - last["ms"],
    }


def run(deals, ticks_dir, scores):
    score_by_id = {}
    if scores.exists():
        with scores.open(newline="") as handle:
            score_by_id = {r["position_id"]: r for r in csv.DictReader(handle)}
    rows = []
    coverage = defaultdict(int)
    for position, legs in sorted(read_deals(deals).items()):
        opening = [r for r in legs if r["entry"] == "0"]
        closing = [r for r in legs if r["entry"] == "1"]
        tick_path = ticks_dir / f"ticks-fp-entry-{position}.csv"
        if not tick_path.exists():
            continue
        if len(opening) != 1:
            coverage["entry_leg_not_unique"] += 1
            continue
        entry = opening[0]
        entry_msc = int(entry["time_msc"])
        q = quotes(tick_path)
        anchors = [tick for tick in q if entry_msc - 2000 <= tick["ms"] <= entry_msc]
        entry_side = "ask" if entry["type"] == "0" else "bid"
        fill_delta = float(entry["price"]) - anchors[-1][entry_side] if anchors else None
        total_cash = sum(float(r[k]) for r in legs for k in ("profit", "commission", "swap", "fee")) if closing else None
        known = score_by_id.get(position, {})
        entry_utc = datetime.fromtimestamp((entry_msc - OFFSET_MS) / 1000, timezone.utc).isoformat()
        for horizon in HORIZONS:
            move = first_move(q, entry_msc, "BUY" if entry["type"] == "0" else "SELL", horizon)
            record = {
                "account": "FP 7404213", "position_id": position, "symbol": entry["symbol"],
                "entry_utc": entry_utc, "direction": "BUY" if entry["type"] == "0" else "SELL",
                "horizon_seconds": horizon, "status": move["status"],
                "first_direction": move["first_direction"], "first_move_ms": move["first_move_ms"],
                "mid_move_at_horizon": move["mid_move_at_horizon"], "spread_at_entry": move["spread_at_entry"],
                "last_quote_lag_ms": move.get("last_quote_lag_ms"),
                "broker_fill_minus_pre_entry_quote": fill_delta,
                "broker_fill_matches_pre_entry_quote": abs(fill_delta) < 1e-9 if fill_delta is not None else None,
                "actual_closed": bool(closing) and abs(sum(float(r["volume"]) for r in opening) - sum(float(r["volume"]) for r in closing)) < 1e-6,
                "actual_final_cash": total_cash,
                "actual_final_r": known.get("final_r") or None,
                "bank1_confirmed": known.get("bank1_confirmed") if known else None,
                "exit_class": known.get("exit_class") or None,
                "peak_price_r": known.get("peak_price_r") or None,
                "source_tick_file": str(tick_path.relative_to(ROOT)),
            }
            rows.append(record)
            coverage[move["status"]] += 1
    return rows, dict(coverage)


def summaries(rows):
    output = []
    for horizon in HORIZONS:
        for direction in ("WITH_ENTRY", "AGAINST_ENTRY", "NO_MOVE"):
            group = [r for r in rows if r["horizon_seconds"] == horizon and r["status"] == "OBSERVED" and r["first_direction"] == direction and r["actual_closed"]]
            known_r = [r for r in group if r["actual_final_r"] not in (None, "")]
            known_bank = [r for r in group if r["bank1_confirmed"] not in (None, "")]
            output.append({
                "horizon_seconds": horizon, "first_direction": direction, "closed_n": len(group),
                "wins": sum(float(r["actual_final_cash"]) > 0 for r in group),
                "losses": sum(float(r["actual_final_cash"]) < 0 for r in group),
                "net_cash": sum(float(r["actual_final_cash"]) for r in group),
                "r_known_n": len(known_r), "net_r_known_subset": sum(float(r["actual_final_r"]) for r in known_r),
                "bank_known_n": len(known_bank),
                "bank1_confirmed": sum(r["bank1_confirmed"] == "True" for r in known_bank),
                "full_initial_stop_known_subset": sum(r["exit_class"] == "INITIAL_STRUCTURAL_STOP_EXIT" for r in known_r),
                "peak_price_3r_known_subset": sum(float(r["peak_price_r"] or 0) >= 3 for r in known_r),
                "peak_price_5r_known_subset": sum(float(r["peak_price_r"] or 0) >= 5 for r in known_r),
            })
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deals", type=Path, default=BASE / "broker-refresh-fp/deals.csv")
    parser.add_argument("--ticks", type=Path, default=BASE / "fp-entry-window-ticks")
    parser.add_argument("--scores", type=Path, default=BASE / "fp-score-trades.csv")
    parser.add_argument("--output", type=Path, default=BASE)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    rows, coverage = run(args.deals, args.ticks, args.scores)
    with (args.output / "fp-first-move-rows.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    result = {
        "schema": "FP_POST_ENTRY_FIRST_MOVE_DIAGNOSTIC_V1",
        "interpretation": "Uses broker quote mid after actual fill, solely to diagnose later outcome. Entry decisions cannot use these future ticks. Price-peak R is not a confirmed cash milestone. No broker execution costs are applied to quote movement; actual outcome cash includes recorded charges.",
        "server_utc_offset_minutes": 180,
        "coverage": coverage,
        "entry_quote_reconciliation": {
            "positions_with_fresh_pre_entry_quote": sum(r["broker_fill_minus_pre_entry_quote"] is not None for r in rows if r["horizon_seconds"] == 5),
            "exact_entry_side_quote_matches": sum(r["broker_fill_matches_pre_entry_quote"] is True for r in rows if r["horizon_seconds"] == 5),
            "missing_fresh_pre_entry_quote": sum(r["broker_fill_minus_pre_entry_quote"] is None for r in rows if r["horizon_seconds"] == 5),
        },
        "summary": summaries(rows),
    }
    (args.output / "fp-first-move-summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"position_windows": len(rows), "coverage": coverage}))


if __name__ == "__main__":
    main()
