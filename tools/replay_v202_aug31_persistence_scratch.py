#!/usr/bin/env python3
"""Replay the 31-Aug-2026 FP V2.202 entries under the proposed two fixes.

The input is the immutable 10-second scan/structure archive. Scratch timing is
therefore a conservative first-observed bound, not a claim about intratick data.
No terminal, account, configuration, or deployed file is touched.
"""

from __future__ import annotations

import csv
import io
import json
import re
import zipfile
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "ops/forexvps/remote-output/v202-audit-20260831.zip"
DT = "%Y.%m.%d %H:%M:%S"
MAX_SLIPPAGE_POINTS = 12


@dataclass(frozen=True)
class Trade:
    name: str
    market: str
    direction: int
    entry_sast: str
    fill: float
    original_net: float
    original_r: float
    original_exit_sast: str


TRADES = (
    Trade("US100 SELL", "USTEC", -1, "2026.08.31 02:13:40", 29314.90, -247.13, -1.0000, "2026.08.31 02:31:30"),
    Trade("XAUUSD SELL", "XAUUSD", -1, "2026.08.31 04:54:30", 4416.57, -234.78, -1.0000, "2026.08.31 07:24:47"),
    Trade("GER40 BUY", "DE30", 1, "2026.08.31 08:02:20", 26531.75, -246.04, -0.9999, "2026.08.31 08:03:29"),
    Trade("EURUSD BUY", "EURUSD", 1, "2026.08.31 10:17:10", 1.15984, -245.18, -1.0000, "2026.08.31 10:56:05"),
    Trade("GER40 SELL", "DE30", -1, "2026.08.31 17:06:30", 26303.25, 37.97, 0.15512, "2026.08.31 17:27:15"),
)


def as_bool(value: str) -> bool:
    return value.lower() == "true"


def number(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def embedded(text: str, field: str) -> float:
    match = re.search(rf"(?:^|;){re.escape(field)}=(-?[0-9.]+)", text)
    return float(match.group(1)) if match else 0.0


def quote(row: dict[str, str]) -> tuple[float, float]:
    entry, spread = number(row["entry"]), number(row["raw_spread"])
    if row["candidate_direction"] == "BUY":
        return entry - spread, entry
    return entry, entry + spread


def structure_identity(row: dict[str, str], structure: dict[str, str]) -> tuple[str, ...]:
    return (
        row["setup_key"],
        structure["stop_anchor_time_server"],
        structure["opposing_structure_time_server"],
        structure["stop_anchor_timeframe"],
        structure["opposing_structure_timeframe"],
    )


def complete_gate_reason(row: dict[str, str], reference_entry: float) -> str:
    direction = 1 if row["candidate_direction"] == "BUY" else -1
    spread = number(row["raw_spread"])
    spread_atr_pct = number(row["spread_to_m5_atr_percent"])
    atr = 100.0 * spread / spread_atr_pct if spread_atr_pct > 0 else 0.0
    drift = direction * (number(row["entry"]) - reference_entry) / atr if atr > 0 else 999.0
    confirmation = max(0.0, direction * (number(row["entry"]) - reference_entry))
    consumed = confirmation / max(confirmation + number(row["available_move"]), number(row["raw_spread"]), 1e-12)
    final_score = embedded(row["absolute_admission_components"], "final")
    impulse = embedded(row["extension_state"], "impulse_atr")
    breakout = embedded(row["extension_state"], "breakout_atr")
    gates = (
        (row["tick_state"] == "FRESH", "STALE_TICK"),
        (as_bool(row["spread_baseline_ready"]), "SPREAD_BASELINE_WARMUP"),
        (row["spread_filter_result"] == "PASS", "ABNORMAL_SPREAD"),
        (spread_atr_pct <= 8.0, "HIGH_SPREAD_RELATIVE_TO_M5_ATR"),
        (number(row["movement_to_spread"]) >= 5.0, "MOVEMENT_WEAK_RELATIVE_TO_SPREAD"),
        (as_bool(row["directional_core_qualified"]), "DIRECTIONAL_CORE_INVALID"),
        (number(row["expected_net_move"]) > 0 and number(row["cost_multiple"]) >= 3.0,
         "EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS"),
        (number(row["reward_r"]) >= 1.15, "INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS"),
        (final_score >= 60.0, "ABSOLUTE_ADMISSION_SCORE_BELOW_NO_TRADE_THRESHOLD"),
        (drift <= 0.60, "LATE_ENTRY_SIGNAL_DRIFT_EXCEEDED"),
        (consumed <= 0.35, "CONFIRMATION_CONSUMED_TOO_MUCH_REMAINING_OPPORTUNITY"),
        (impulse <= 1.75, "LATE_ENTRY_M5_IMPULSE_EXTENSION_EXCEEDED"),
        (breakout <= 0.75, "EXHAUSTED_BREAKOUT_EXTENSION_EXCEEDED"),
    )
    return next((reason for passed, reason in gates if not passed), "PASS")


def replay_admission(rows: list[dict[str, str]], structures: dict[tuple[str, str], dict[str, str]]):
    state = None
    count = 0
    first = None
    last = None
    reference = None
    outcomes = {}
    for row in rows:
        now = datetime.strptime(row["sast"], DT)
        structure = structures[(row["scan_sequence"], row["intended_market"])]
        identity = structure_identity(row, structure)
        state_key = (row["completed_m5_bar_time"], row["candidate_direction"], identity)
        same = count > 0 and state == state_key and last is not None and (now - last).total_seconds() <= 30
        candidate_reference = reference if same else number(row["entry"])
        reason = complete_gate_reason(row, candidate_reference)
        complete = reason == "PASS"
        if not complete:
            state, count, first, reference = None, 0, None, None
            elapsed = 0
        else:
            if same:
                count += 1
            else:
                state, count, first, reference = state_key, 1, now, number(row["entry"])
            elapsed = int((now - first).total_seconds())
        last = now
        admitted = complete and count >= 3 and elapsed >= 30
        outcomes[row["sast"]] = {
            "admitted": admitted,
            "complete": complete,
            "reason": "QUALIFIED_CONTEXT_COST_STRUCTURE" if admitted else
                      ("COMPLETE_ADMISSION_PERSISTENCE_PENDING" if complete else reason),
            "complete_scans": count,
            "complete_seconds": elapsed,
            "reference_entry": reference,
            "row": row,
            "structure": structure,
        }
    return outcomes


def scratch_replay(trade: Trade, entry_row: dict[str, str], later_rows: list[dict[str, str]],
                   structure: dict[str, str], fill: float):
    entry_spread = number(entry_row["raw_spread"])
    reference = fill - entry_spread if trade.direction > 0 else fill + entry_spread
    trigger = None
    for row in later_rows:
        if datetime.strptime(row["sast"], DT) <= datetime.strptime(entry_row["sast"], DT):
            continue
        bid, ask = quote(row)
        executable = bid if trade.direction > 0 else ask
        if (trade.direction > 0 and executable < reference) or (trade.direction < 0 and executable > reference):
            trigger = (row, executable)
            break
    if trigger is None:
        return None
    row, scratch_price = trigger
    point = entry_spread / number(entry_row["spread_points"])
    volume = number(structure["proposed_volume"])
    tick_value = number(structure["tick_value_loss"])
    money_per_price = tick_value * volume / point
    modeled_exit = scratch_price - MAX_SLIPPAGE_POINTS * point if trade.direction > 0 else scratch_price + MAX_SLIPPAGE_POINTS * point
    gross = trade.direction * (modeled_exit - fill) * money_per_price
    commission = number(structure["commission_cost_move"]) * money_per_price
    net = gross - commission
    risk = number(structure["proposed_risk_usd"])
    realized_r = net / risk if risk else 0.0
    recovery_deadline = datetime.strptime(row["sast"], DT) + timedelta(minutes=30)
    raw_reclaim_at = None
    profitable_at = None
    for future in later_rows:
        future_time = datetime.strptime(future["sast"], DT)
        if future_time <= datetime.strptime(row["sast"], DT) or future_time > recovery_deadline:
            continue
        bid, ask = quote(future)
        close = bid if trade.direction > 0 else ask
        if raw_reclaim_at is None and trade.direction * (close - fill) > 0:
            raw_reclaim_at = future["sast"]
        modeled = close - MAX_SLIPPAGE_POINTS * point if trade.direction > 0 else close + MAX_SLIPPAGE_POINTS * point
        future_net = trade.direction * (modeled - fill) * money_per_price - commission
        if future_net > 0:
            profitable_at = future["sast"]
            break
    return {
        "trigger_sast": row["sast"],
        "scratch_price": round(scratch_price, 10),
        "reference_close_price": round(reference, 10),
        "estimated_net_pl": round(net, 2),
        "realized_r": round(realized_r, 5),
        "loss_avoided_vs_original": round(net - trade.original_net, 2),
        "profitable_recovery_within_30m": profitable_at is not None,
        "profitable_recovery_sast": profitable_at,
        "raw_fill_reclaim_within_30m": raw_reclaim_at is not None,
        "raw_fill_reclaim_sast": raw_reclaim_at,
        "sampling_limit": "first adverse observation at 10-second scan resolution",
    }


def main() -> None:
    markets = {trade.market for trade in TRADES}
    with zipfile.ZipFile(ARCHIVE) as archive:
        with archive.open("structure-telemetry-v6-20260831.csv") as raw:
            structures = {
                (row["scan_sequence"], row["intended_market"]): row
                for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""))
                if row["intended_market"] in markets
            }
        with archive.open("scan-history-v5-20260831.csv") as raw:
            rows = [row for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""))
                    if row["intended_market"] in markets]

    result = {"archive": str(ARCHIVE.relative_to(ROOT)), "scan_resolution_seconds": 10, "trades": []}
    for trade in TRADES:
        symbol_rows = [row for row in rows if row["intended_market"] == trade.market]
        outcomes = replay_admission(symbol_rows, structures)
        original = outcomes[trade.entry_sast]
        entry_time = datetime.strptime(trade.entry_sast, DT)
        first_later_admission = next(
            (out for stamp, out in outcomes.items()
             if entry_time <= datetime.strptime(stamp, DT) <= entry_time + timedelta(minutes=10) and out["admitted"]),
            None,
        )
        original_scratch = scratch_replay(
            trade, original["row"], symbol_rows,
            original["structure"], trade.fill,
        )
        delayed = None
        if first_later_admission is not None:
            delayed_row = first_later_admission["row"]
            delayed = {
                "admission_sast": delayed_row["sast"],
                "fill_model": number(delayed_row["entry"]),
                "scratch": scratch_replay(
                    trade, delayed_row, symbol_rows,
                    first_later_admission["structure"], number(delayed_row["entry"]),
                ),
            }
        result["trades"].append({
            "trade": trade.name,
            "original_v202": {"net_pl": trade.original_net, "realized_r": trade.original_r},
            "new_decision_at_original_entry": original["reason"],
            "complete_scans_at_original_entry": original["complete_scans"],
            "complete_seconds_at_original_entry": original["complete_seconds"],
            "first_admission_within_10m": delayed,
            "original_entry_counterfactual_scratch": original_scratch,
        })
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
