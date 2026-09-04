#!/usr/bin/env python3
"""Find rejected FP candidates that subsequently moved before their stop.

The audit uses only recorded ten-second scan quotes. It reports conservative
observed MFE; it does not infer unseen highs/lows between scans and never sends
or modifies orders.
"""

from __future__ import annotations

import bisect
import csv
import io
import json
import re
import zipfile
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "ops/forexvps/remote-output/fp-scan-20260904.zip"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-missed-moves-20260904.json"
TIME_FORMAT = "%Y.%m.%d %H:%M:%S"
FINAL_SCORE = re.compile(r"(?:^|;)final=([-0-9.]+)")
HORIZON = timedelta(minutes=60)


def quote(row: dict[str, str]) -> tuple[float, float]:
    entry = float(row["entry"])
    spread = float(row["raw_spread"])
    if row["candidate_direction"] == "BUY":
        return entry - spread, entry
    return entry, entry + spread


def observed_path(
    side: str,
    fill: float,
    stop_distance: float,
    future: list[tuple[datetime, float, float]],
) -> dict[str, object]:
    peak = float("-inf")
    first_half = None
    first_one = None
    stop_utc = None
    for utc, bid, ask in future:
        current_r = (bid - fill) / stop_distance if side == "BUY" else (fill - ask) / stop_distance
        peak = max(peak, current_r)
        if first_half is None and current_r >= 0.50:
            first_half = utc
        if first_one is None and current_r >= 1.00:
            first_one = utc
        if current_r <= -1.00:
            stop_utc = utc
            break
    return {
        "observed_mfe_r_before_stop": round(peak, 5) if peak != float("-inf") else None,
        "reached_0_5r_before_stop": first_half is not None,
        "reached_1r_before_stop": first_one is not None,
        "first_0_5r_utc": first_half.strftime(TIME_FORMAT) if first_half else None,
        "first_1r_utc": first_one.strftime(TIME_FORMAT) if first_one else None,
        "observed_stop_utc": stop_utc.strftime(TIME_FORMAT) if stop_utc else None,
    }


def main() -> int:
    with zipfile.ZipFile(ARCHIVE) as archive:
        member = next(name for name in archive.namelist() if name.endswith(".csv"))
        with archive.open(member) as raw:
            rows = list(csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")))

    series: dict[str, list[tuple[datetime, float, float]]] = defaultdict(list)
    for row in rows:
        try:
            utc = datetime.strptime(row["utc"], TIME_FORMAT)
            bid, ask = quote(row)
        except (ValueError, KeyError):
            continue
        series[row["intended_market"]].append((utc, bid, ask))
    for values in series.values():
        values.sort(key=lambda item: item[0])

    candidates = []
    for row in rows:
        if row["eligible"] == "true" or row["candidate_direction"] not in ("BUY", "SELL"):
            continue
        if not (
            row["directional_core_qualified"] == "true"
            and row["m5_confirmed"] == "true"
            and row["m15_confirmed"] == "true"
            and row["tick_state"] == "FRESH"
        ):
            continue
        try:
            stop_distance = float(row["stop_distance"])
            if stop_distance <= 0:
                continue
            utc = datetime.strptime(row["utc"], TIME_FORMAT)
            bid, ask = quote(row)
        except (ValueError, KeyError):
            continue
        score_match = FINAL_SCORE.search(row["absolute_admission_components"])
        candidates.append({
            "utc": utc,
            "market": row["intended_market"],
            "symbol": row["resolved_broker_symbol"],
            "side": row["candidate_direction"],
            "fill": ask if row["candidate_direction"] == "BUY" else bid,
            "stop": float(row["stop"]),
            "stop_distance": stop_distance,
            "reason": row["primary_rejection_reason"],
            "setup_key": row["setup_key"],
            "score": float(score_match.group(1)) if score_match else None,
            "reward_r": float(row["reward_r"]),
            "spread_filter": row["spread_filter_result"],
            "spread_atr_percent": float(row["spread_to_m5_atr_percent"]),
            "cost_multiple": float(row["cost_multiple"]),
        })

    # Collapse repeated ten-second observations of the same structural episode.
    episodes = []
    last_seen: dict[tuple[str, str, str, str], datetime] = {}
    for item in sorted(candidates, key=lambda x: x["utc"]):
        key = (item["market"], item["side"], item["reason"], item["setup_key"])
        previous = last_seen.get(key)
        last_seen[key] = item["utc"]
        if previous is not None and item["utc"] - previous <= timedelta(minutes=5):
            continue
        values = series[item["market"]]
        times = [value[0] for value in values]
        start = bisect.bisect_right(times, item["utc"])
        end = bisect.bisect_right(times, item["utc"] + HORIZON)
        path = observed_path(item["side"], item["fill"], item["stop_distance"], values[start:end])
        episodes.append({
            **{key: (value.strftime(TIME_FORMAT) if key == "utc" else value) for key, value in item.items()},
            **path,
        })

    winners_half = [item for item in episodes if item["reached_0_5r_before_stop"]]
    winners_one = [item for item in episodes if item["reached_1r_before_stop"]]
    # A safe near miss already passed stale-tick and spread protection. It may
    # still have failed structure/reward, which remains visible in ``reason``.
    safe_half = [item for item in winners_half if item["spread_filter"] == "PASS"]
    report = {
        "schema": "SOLTRADE_V202_SEP04_MISSED_MOVE_AUDIT_V1",
        "orders_placed": False,
        "strategy_changed": False,
        "deployment_performed": False,
        "source": str(ARCHIVE.relative_to(ROOT)),
        "resolution_seconds": 10,
        "horizon_minutes": 60,
        "candidate_definition": "rejected; directional core, M5, M15 and fresh tick all valid",
        "summary": {
            "raw_qualified_rejected_rows": len(candidates),
            "collapsed_episodes": len(episodes),
            "episodes_observed_0_5r_before_stop": len(winners_half),
            "episodes_observed_1r_before_stop": len(winners_one),
            "safe_spread_pass_0_5r_episodes": len(safe_half),
            "safe_spread_pass_1r_episodes": sum(x["reached_1r_before_stop"] for x in safe_half),
            "missed_0_5r_by_gate": dict(Counter(x["reason"] for x in safe_half).most_common()),
            "missed_1r_by_gate": dict(Counter(x["reason"] for x in safe_half if x["reached_1r_before_stop"]).most_common()),
        },
        "safe_spread_pass_winners": sorted(
            safe_half,
            key=lambda item: item["observed_mfe_r_before_stop"] or -999,
            reverse=True,
        ),
        "all_episodes": episodes,
        "limitations": [
            "MFE uses sampled executable quotes, so it is conservative between scans",
            "episodes are correlated and are not independent trades",
            "a favorable excursion alone does not prove a deployable profitable strategy",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
