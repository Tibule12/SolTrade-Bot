#!/usr/bin/env python3
"""Evaluate the September 3 locked M1 timing rule on later FP executions."""

from __future__ import annotations

import csv
import ctypes
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.audit_v202_m1_setup_timing import TIME_FORMAT, decisions, feature_set


BARS = ROOT / "reports/fast-multi-market-v2/fp-m1-forward-gate-20260915/m1-bars.csv"
EARLY = ROOT / "reports/fast-multi-market-v2/fp-status-20260909-1204/recent-trades-snapshot.json"
CURRENT = ROOT / "reports/fast-multi-market-v2/all-three-live-damage-20260915/raw-fp-events.csv"
OUT = ROOT / "reports/fast-multi-market-v2/fp-m1-forward-gate-20260915"

CASES = {
    "20260908_AUDJPY_SELL": (-246.97, 247.06),
    "20260908_NZDUSD_SELL": (93.67, 246.50),
    "20260908_GER40_SELL": (-246.60, 246.64),
    "20260909_USDJPY_SELL": (-246.28, 246.28),
    "20260909_XAUUSD_BUY": (1088.10, 980.85),
    "20260909_GER40_SELL": (198.79, 993.66),
    "20260914_XAUUSD_SELL": (-990.00, 990.00),
    "20260914_USDJPY_SELL": (-985.77, 985.78),
    "20260915_US100_SELL": (-975.83, 975.83),
    "20260915_GER40_SELL": (-965.49, 965.83),
}

BEHAVIOUR_BASES = {
    "BREAKOUT_UP": 11,
    "BREAKOUT_DOWN": 12,
    "BULL_REJECTION": 21,
    "BEAR_REJECTION": 22,
    "FAILED_BREAKOUT_UP": 31,
    "FAILED_BREAKOUT_DOWN": 32,
    "STRUCTURE_INSIDE": 40,
}


def details(value: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


def decode_behaviour(setup_key: int, direction: int) -> str:
    encoded = direction * setup_key
    candidates = []
    for name, code in BEHAVIOUR_BASES.items():
        base = ctypes.c_int32(code * 100_000_000).value
        zone = encoded - base
        if 0 <= zone < 100_000_000:
            candidates.append((zone, name))
    if not candidates:
        raise ValueError(f"cannot decode setup key {setup_key} for direction {direction}")
    return min(candidates)[1]


def load_entry_metadata() -> list[dict[str, str]]:
    result = []
    early = json.loads(EARLY.read_text(encoding="utf-8-sig"))
    for row in early["events"]:
        if row["event"] == "ENTRY":
            result.append(row)
    with CURRENT.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if row["event"] == "ENTRY":
                result.append(row)
    return result


def find_entry(events: list[dict[str, str]], symbol: str, direction: str, expected_utc: datetime) -> dict[str, str]:
    matches = [
        row
        for row in events
        if row["symbol"] == symbol
        and row["direction"] == direction
        and abs((datetime.strptime(row["utc"], TIME_FORMAT) - expected_utc).total_seconds()) <= 2
    ]
    if len(matches) != 1:
        raise ValueError(f"expected one entry for {symbol} {direction} near {expected_utc}, got {len(matches)}")
    return matches[0]


def main() -> None:
    grouped = defaultdict(list)
    bar_metadata = {}
    with BARS.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            bar_metadata[row["case"]] = row
            grouped[row["case"]].append(
                {
                    "time": datetime.strptime(row["bar_broker_time"], "%Y.%m.%d %H:%M"),
                    "open": float(row["bid_open"]),
                    "high": float(row["bid_high"]),
                    "low": float(row["bid_low"]),
                    "close": float(row["bid_close"]),
                }
            )

    metadata = load_entry_metadata()
    rows = []
    for name, bars in grouped.items():
        record = bar_metadata[name]
        direction = 1 if record["direction"] == "BUY" else -1
        entry = datetime.strptime(record["admission_broker_time"], TIME_FORMAT)
        event = find_entry(metadata, record["symbol"], record["direction"], entry - timedelta(hours=3))
        behaviour = decode_behaviour(int(event["setup_key"]), direction)
        features = feature_set(sorted(bars, key=lambda item: item["time"]), entry, direction, behaviour)
        if direction < 0:
            features["trend_m1"] *= -1
        decision = decisions(features)["SETUP_FAMILY_TIMING_V1"]
        net, risk = CASES[name]
        rows.append(
            {
                "case": name,
                "symbol": record["symbol"],
                "direction": record["direction"],
                "entry_broker_time": record["admission_broker_time"],
                "net": net,
                "realized_r": round(net / risk, 6),
                "outcome": "WIN" if net > 0 else "LOSS",
                "behaviour": behaviour,
                **{k: v for k, v in features.items() if k not in {"behaviour"}},
                "SETUP_FAMILY_TIMING_V1": decision,
            }
        )

    rows.sort(key=lambda item: item["entry_broker_time"])
    accepted = [row for row in rows if row["SETUP_FAMILY_TIMING_V1"]]
    winners = [row for row in rows if row["net"] > 0]
    losers = [row for row in rows if row["net"] <= 0]
    accepted_winners = [row for row in accepted if row["net"] > 0]
    accepted_losers = [row for row in accepted if row["net"] <= 0]
    winner_cash = sum(row["net"] for row in winners)
    metrics = {
        "trades": len(rows),
        "wins": len(winners),
        "losses": len(losers),
        "actual_net": round(sum(row["net"] for row in rows), 2),
        "accepted": len(accepted),
        "rejected": len(rows) - len(accepted),
        "accepted_net_fixed_ledger": round(sum(row["net"] for row in accepted), 2),
        "winner_count_retention": round(len(accepted_winners) / len(winners), 6),
        "winner_cash_retention": round(sum(row["net"] for row in accepted_winners) / winner_cash, 6),
        "loser_rejection": round(len([row for row in losers if not row["SETUP_FAMILY_TIMING_V1"]]) / len(losers), 6),
        "accepted_losers": [row["case"] for row in accepted_losers],
        "rejected_winners": [row["case"] for row in winners if not row["SETUP_FAMILY_TIMING_V1"]],
    }
    acceptance = {
        "minimum_independent_forward_trades": 8,
        "minimum_winner_cash_retention": 0.80,
        "minimum_loser_rejection": 0.50,
        "accepted_losers_allowed": 0,
    }
    passed = (
        len(rows) >= acceptance["minimum_independent_forward_trades"]
        and metrics["winner_cash_retention"] >= acceptance["minimum_winner_cash_retention"]
        and metrics["loser_rejection"] >= acceptance["minimum_loser_rejection"]
        and not accepted_losers
    )
    report = {
        "schema": "SOLTRADE_FP_M1_LOCKED_FORWARD_AUDIT_V1",
        "rule_frozen_utc": "2026-09-03",
        "evaluation_period": "2026-09-08 through 2026-09-15",
        "account": 7404213,
        "data_controls": {
            "completed_broker_m1_only": True,
            "forming_and_future_bars_excluded": True,
            "mt5_tester_or_replay_used": False,
            "trade_filtering_note": "fixed-ledger attribution; changed portfolio state and later admissions are not replayed",
        },
        "metrics": metrics,
        "acceptance": {**acceptance, "pass": passed},
        "decision": "PROMOTE" if passed else "DO_NOT_PROMOTE",
        "rows": rows,
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "audit.json").write_text(json.dumps(report, indent=2) + "\n")
    with (OUT / "trade-features.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({"decision": report["decision"], "metrics": metrics}, indent=2))


if __name__ == "__main__":
    main()
