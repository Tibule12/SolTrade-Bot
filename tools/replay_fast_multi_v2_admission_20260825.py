#!/usr/bin/env python3
"""Classify preserved Fast Multi entries against V2.200 admission gates.

The classifier discovers trades and their entry scans from supplied evidence.
It contains no trade timestamps, symbols, or prices and never uses post-entry
MFE/P&L to decide admission. Missing V2.200 fields produce UNKNOWN, not an
invented pass or reject.
"""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def classify(trades: list[dict[str, str]], scans: list[dict[str, str]]) -> list[dict[str, object]]:
    submitted = {
        (row["utc"], row["resolved_broker_symbol"]): row
        for row in scans
        if row["order_attempt_status"] == "BROKER_ORDER_SUBMITTED"
    }
    prior: dict[str, dict[str, str]] = {}
    results: list[dict[str, object]] = []
    for trade in sorted(trades, key=lambda row: parse_time(row["entry_timestamp_utc"])):
        key = (trade["entry_timestamp_utc"], trade["symbol"])
        scan = submitted[key]
        spread_atr = float(scan["spread_to_m5_atr_percent"])
        score = float(scan["score"])
        opposite = float(scan["sell_score"] if trade["direction"] == "BUY" else scan["buy_score"])
        no_trade = float(scan["no_trade_score"])
        reward_r = float(scan["reward_r"])
        cost_multiple = float(scan["cost_multiple"])
        previous = prior.get(trade["symbol"])
        rejection = ""
        if previous and (parse_time(trade["entry_timestamp_utc"]) - parse_time(previous["exit_timestamp_utc"])).total_seconds() < 1800:
            rejection = "SAME_SYMBOL_CHURN_COOLDOWN"
        elif spread_atr > 8.0:
            rejection = "HIGH_SPREAD_RELATIVE_TO_M5_ATR"
        elif cost_multiple < 3.0:
            rejection = "EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS"
        elif reward_r < 1.25:
            rejection = "OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS"
        elif score < 68.0:
            rejection = "DIRECTIONAL_EVIDENCE_WEAK"
        elif score < opposite + 12.0:
            rejection = "OPPOSITE_CASE_NOT_CLEARLY_DEFEATED"
        elif score < no_trade + 8.0:
            rejection = "NO_TRADE_CASE_DOMINATES"

        if rejection:
            decision = "REJECT"
            exact_gate = rejection
            missing = []
        else:
            decision = "UNKNOWN"
            exact_gate = "INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE"
            missing = [
                "V2.200 absolute admission components",
                "nearest opposing swing selected by V2.200",
                "M5 impulse and breakout extension",
                "setup-specific first/stable timestamps and confirmation movement",
            ]
        results.append({
            "trade": trade["trade"],
            "symbol": trade["symbol"],
            "direction": trade["direction"],
            "entry_timestamp_utc": trade["entry_timestamp_utc"],
            "classification": decision,
            "exact_gate": exact_gate,
            "candidate_score": score,
            "no_trade_score": no_trade,
            "spread_atr_percent": spread_atr,
            "reward_r": reward_r,
            "cost_multiple": cost_multiple,
            "mfe_r_observation_only_not_used_for_classification": float(trade["mfe_r"]),
            "missing_evidence": missing,
        })
        prior[trade["symbol"]] = trade
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trades", type=Path, required=True)
    parser.add_argument("--scans", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-markdown", type=Path, required=True)
    args = parser.parse_args()

    results = classify(read_rows(args.trades), read_rows(args.scans))
    payload = {
        "schema": "SOLTRADE_FAST_MULTI_V2_200_ADMISSION_REGRESSION_V1",
        "look_ahead_used": False,
        "classifier_embeds_trade_timestamps_symbols_or_prices": False,
        "counts": {state: sum(row["classification"] == state for row in results)
                   for state in ("ACCEPT", "REJECT", "UNKNOWN")},
        "rows": results,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Fast Multi V2.200 — preserved admission regression",
        "",
        "Classification uses only evidence available at entry. MFE is displayed as a regression observation and is never an input to a gate.",
        "",
        f"Counts: ACCEPT {payload['counts']['ACCEPT']}, REJECT {payload['counts']['REJECT']}, UNKNOWN {payload['counts']['UNKNOWN']}.",
        "",
        "| Trade | Symbol | Direction | Classification | Exact gate | Score / no-trade | Spread ATR % | Reward R | MFE R (unused) |",
        "|---:|---|---|---|---|---:|---:|---:|---:|",
    ]
    for row in results:
        lines.append(
            f"| {row['trade']} | {row['symbol']} | {row['direction']} | {row['classification']} | "
            f"{row['exact_gate']} | {row['candidate_score']:.2f} / {row['no_trade_score']:.2f} | "
            f"{row['spread_atr_percent']:.2f} | {row['reward_r']:.3f} | "
            f"{row['mfe_r_observation_only_not_used_for_classification']:.3f} |"
        )
    lines.extend([
        "",
        "UNKNOWN is mandatory where the old V3 audit did not retain the new absolute-score components, nearest-opposing-swing selection, impulse/breakout extension, or setup-specific confirmation timing. No future outcome was substituted.",
    ])
    args.output_markdown.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
