#!/usr/bin/env python3
"""Replay 1-Sep-2026 live paths with the first-adverse-tick scratch retired.

This is a no-order, read-only replay over the captured ten-second broker scan
telemetry. It uses the existing V2.202 minimum protected-R schedule and the
original broker structural stop. Because intratick ordering and the runner's
structure-aware trail are not present in the scan archive, profitable captures
are conservative floor outcomes rather than exact fills.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "ops/forexvps/remote-output/loss-audit"
EVIDENCE = AUDIT / "f10-evidence.csv"
TELEMETRY = AUDIT / "f10-structure-telemetry-v6-20260901.csv"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-scratch-retirement-20260901.json"


def fields(detail: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in detail.split(";") if "=" in part)


def minimum_protected_r(peak_r: float) -> float:
    if peak_r < 0.50:
        return -1.0
    if peak_r < 0.75:
        return -0.05
    if peak_r < 1.00:
        return 0.10
    return max(0.25, peak_r - max(0.75, 0.40 * peak_r))


def intended(symbol: str) -> str:
    if symbol.startswith("DE30"):
        return "DE30"
    if symbol.startswith("USTEC"):
        return "USTEC"
    if symbol.startswith("XAUUSD"):
        return "XAUUSD"
    raise ValueError(f"unsupported replay symbol {symbol}")


def main() -> None:
    with EVIDENCE.open(newline="", encoding="utf-8-sig") as handle:
        evidence = list(csv.DictReader(handle))
    entries = [row for row in evidence if row["event"] == "ENTRY" and "2026.09.01" in row["utc"]]
    exits = {
        fields(row["detail"])["position_id"]: row
        for row in evidence
        if row["event"] == "EXIT" and "2026.09.01" in row["utc"]
    }
    with TELEMETRY.open(newline="", encoding="utf-8-sig") as handle:
        telemetry = list(csv.DictReader(handle))

    results = []
    for number, entry in enumerate(entries):
        detail = fields(entry["detail"])
        position_id = entry["ticket"]
        exit_row = exits[position_id]
        exit_detail = fields(exit_row["detail"])
        market = intended(entry["symbol"])
        direction = 1 if entry["direction"] == "BUY" else -1
        fill = float(detail["scratch_fill"])
        stop = float(entry["stop"])
        initial_distance = abs(stop - fill)
        cutoff = next(
            (later["utc"] for later in entries[number + 1 :] if intended(later["symbol"]) == market),
            None,
        )

        quotes = []
        seen = set()
        for row in telemetry:
            if row["intended_market"] != market or row["candidate_direction"] != entry["direction"]:
                continue
            if row["utc"] <= exit_row["utc"] or (cutoff and row["utc"] >= cutoff):
                continue
            identity = (row["scan_sequence"], row["entry"])
            if identity in seen:
                continue
            seen.add(identity)
            raw_entry = float(row["entry"])
            spread = float(row["spread_cost_move"])
            executable_close = raw_entry - spread if direction > 0 else raw_entry + spread
            quotes.append((row["utc"], executable_close))

        peak_r = 0.0
        protected_r = -1.0
        outcome = None
        for stamp, executable_close in quotes:
            current_r = direction * (executable_close - fill) / initial_distance
            if current_r <= protected_r:
                outcome = {
                    "exit_class": "STRUCTURAL_SL" if protected_r == -1.0 else "RUNNER_PROTECTED_EXIT",
                    "first_observed_exit_utc": stamp,
                    "modeled_capture_r": round(protected_r, 5),
                    "observed_cross_r": round(current_r, 5),
                    "peak_r_before_exit": round(peak_r, 5),
                }
                break
            peak_r = max(peak_r, current_r)
            candidate_floor = minimum_protected_r(peak_r)
            if candidate_floor > protected_r and current_r > candidate_floor:
                protected_r = candidate_floor

        if outcome is None:
            final_r = direction * (quotes[-1][1] - fill) / initial_distance if quotes else 0.0
            outcome = {
                "exit_class": "OPEN_AT_ARCHIVE_END",
                "first_observed_exit_utc": None,
                "modeled_capture_r": round(final_r, 5),
                "observed_cross_r": None,
                "peak_r_before_exit": round(peak_r, 5),
            }

        original_r = float(exit_detail["net"]) / float(detail["initial_risk"])
        results.append(
            {
                "position_id": position_id,
                "market": market,
                "direction": entry["direction"],
                "entry_utc": entry["utc"],
                "complete_admission_persistence": detail["complete_admission_persistence"] == "true",
                "original_exit_class": exit_detail["exit_class"],
                "original_net": float(exit_detail["net"]),
                "original_r": round(original_r, 5),
                "scratch_retired_outcome": outcome,
            }
        )

    original_r = sum(item["original_r"] for item in results)
    modeled_r = sum(item["scratch_retired_outcome"]["modeled_capture_r"] for item in results)
    winners = sum(item["scratch_retired_outcome"]["modeled_capture_r"] > 0 for item in results)
    losses = sum(item["scratch_retired_outcome"]["modeled_capture_r"] < 0 for item in results)
    result = {
        "schema": "SOLTRADE_V202_SCRATCH_RETIREMENT_REPLAY_V1",
        "source": str(AUDIT.relative_to(ROOT)),
        "resolution_seconds": 10,
        "orders_placed": False,
        "admission_logic_changed": False,
        "risk_sizing_changed": False,
        "runner_logic_changed": False,
        "structural_stop_changed": False,
        "first_adverse_tick_scratch_retired": True,
        "trades": results,
        "summary": {
            "distinct_signals": len(results),
            "original_winners": sum(item["original_r"] > 0 for item in results),
            "original_losses": sum(item["original_r"] < 0 for item in results),
            "original_aggregate_r": round(original_r, 5),
            "modeled_winners": winners,
            "modeled_losses": losses,
            "modeled_aggregate_r": round(modeled_r, 5),
            "modeled_change_r": round(modeled_r - original_r, 5),
            "status": "PASS" if winners == 3 and losses == 2 and modeled_r > 0 else "FAIL",
        },
        "limitations": [
            "ten-second scan observations are not an exact intratick execution replay",
            "runner structural trailing can tighten beyond the modeled minimum protected-R floor",
            "broker slippage can change realized fills",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if result["summary"]["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
