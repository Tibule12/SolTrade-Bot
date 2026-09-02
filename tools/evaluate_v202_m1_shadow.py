#!/usr/bin/env python3
"""Summarize V2.202 M1 entry evidence without authorizing a live gate."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class Bar:
    time: str
    open: float
    high: float
    low: float
    close: float


def m1_entry_evidence(
    bars: list[Bar], *, direction: int, atr: float, aligned_breakout: bool, breakout_anchor: float
) -> dict[str, object]:
    """Python reference for the EA's completed-M1-bar shadow calculation.

    ``bars[0]`` is the most recently completed M1 bar (MQL shift 1).
    """
    if len(bars) < 5 or direction not in (-1, 1) or atr <= 0:
        raise ValueError("five completed bars, direction +/-1, and positive ATR are required")

    pullback_shift = 0
    pullback_time = ""
    pullback_depth_atr = 0.0
    reclaim_level = 0.0
    for mql_shift in range(2, 5):
        bar = bars[mql_shift - 1]
        prior_close = bars[mql_shift].close
        signed_body = direction * (bar.close - bar.open)
        retraced = bar.low < prior_close if direction > 0 else bar.high > prior_close
        if signed_body >= 0 or not retraced:
            continue
        pullback_shift = mql_shift
        pullback_time = bar.time
        reclaim_level = bar.high if direction > 0 else bar.low
        adverse_extreme = bar.low if direction > 0 else bar.high
        pullback_depth_atr = direction * (prior_close - adverse_extreme) / atr
        break

    reclaim_distance_atr = 0.0
    reclaim_confirmed = False
    newest = bars[0]
    if pullback_shift:
        reclaim_distance_atr = direction * (newest.close - reclaim_level) / atr
        reclaim_confirmed = (
            direction * (newest.close - reclaim_level) > 0
            and direction * (newest.close - newest.open) > 0
        )

    retention_bars = 0
    if aligned_breakout and breakout_anchor > 0:
        for bar in bars[:5]:
            if direction * (bar.close - breakout_anchor) <= 0:
                break
            retention_bars += 1
    breakout_retained = aligned_breakout and retention_bars >= 2
    breakout_failed = (
        aligned_breakout
        and breakout_anchor > 0
        and direction * (newest.close - breakout_anchor) <= 0
    )
    would_confirm = reclaim_confirmed or breakout_retained
    if reclaim_confirmed and breakout_retained:
        verdict = "PULLBACK_RECLAIM_AND_BREAKOUT_RETAINED"
    elif reclaim_confirmed:
        verdict = "PULLBACK_RECLAIM_CONFIRMED"
    elif breakout_retained:
        verdict = "BREAKOUT_RETAINED_TWO_COMPLETED_M1_BARS"
    elif breakout_failed:
        verdict = "BREAKOUT_FAILED_ON_COMPLETED_M1_CLOSE"
    elif pullback_shift:
        verdict = "PULLBACK_WITHOUT_RECLAIM"
    else:
        verdict = "NO_NEW_M1_CONFIRMATION"
    return {
        "pullback_shift": pullback_shift,
        "pullback_time": pullback_time,
        "pullback_depth_atr": pullback_depth_atr,
        "reclaim_level": reclaim_level,
        "reclaim_distance_atr": reclaim_distance_atr,
        "reclaim_confirmed": reclaim_confirmed,
        "breakout_retention_bars": retention_bars,
        "breakout_retained": breakout_retained,
        "breakout_failed": breakout_failed,
        "shadow_would_confirm": would_confirm,
        "shadow_evidence": verdict,
    }


def _truth(value: str) -> bool:
    return value.strip().lower() == "true"


def summarize(path: Path) -> dict[str, object]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    evidence = Counter(row["m1_shadow_evidence"] for row in rows)
    complete = [row for row in rows if _truth(row["complete_admission_qualified"])]
    eligible = [row for row in rows if _truth(row["live_eligible"])]
    independent = {
        (row["intended_market"], row["candidate_direction"], row["completed_m1_bar_time"], row["admission_state_key"])
        for row in complete
    }
    violations = [
        row for row in rows
        if row["live_admission_unchanged"] != "true"
        or row["order_influence"] != "NONE_SHADOW_TELEMETRY_ONLY"
    ]
    return {
        "schema": "SOLTRADE_V202_M1_SHADOW_SUMMARY_V1",
        "source": str(path),
        "rows": len(rows),
        "complete_admission_rows": len(complete),
        "live_eligible_rows": len(eligible),
        "independent_complete_admission_events": len(independent),
        "shadow_confirmed_complete_rows": sum(_truth(row["m1_shadow_would_confirm"]) for row in complete),
        "evidence_counts": dict(sorted(evidence.items())),
        "shadow_is_non_intervening": not violations,
        "outcome_labels_available": False,
        "safe_to_promote_to_live_gate": False,
        "decision": "COLLECT_REAL_TICK_OUTCOMES_BEFORE_ANY_LIVE_ADMISSION_CHANGE",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("telemetry", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = summarize(args.telemetry)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
