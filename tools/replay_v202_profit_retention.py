#!/usr/bin/env python3
"""Read-only replay of a tighter monotonic profit floor over live evidence.

This deliberately does not edit the EA or deploy anything. Recorded ``current_r``
observations are used in timestamp order; unobserved intratick prices are never
invented. Results are therefore bounded by the strategy's telemetry frequency.
"""

from __future__ import annotations

import csv
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "ops/forexvps/remote-output/live-evidence"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-profit-retention-replay-20260904.json"
CURRENT_R = re.compile(r"(?:^|;)current_r=([-0-9.]+)")


def details(value: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


def market(symbol: str) -> str:
    value = symbol.upper().split(".", 1)[0]
    return {"USTEC": "US100", "DE30": "GER40"}.get(value, value)


def candidate_floor(peak_r: float) -> float:
    """Predefined tighter floor; it never changes protection before +0.50R."""
    if peak_r < 0.50:
        return -1.0
    if peak_r < 0.75:
        return 0.20
    if peak_r < 1.00:
        return 0.35
    if peak_r < 1.50:
        return max(0.60, peak_r - 0.65)
    # Above 1.5R, preserve the existing runner's expansion allowance. A
    # permanently tight peak-minus-0.65R trail cut the observed 3.89R USDJPY
    # runner early in replay.
    current_floor = max(0.25, peak_r - max(0.75, 0.40 * peak_r))
    return max(0.84, current_floor)


def delayed_failure_trigger(
    entry_utc: str,
    observations: list[tuple[str, float]],
    *,
    minimum_age: timedelta = timedelta(minutes=15),
    maximum_peak_r: float = 0.15,
    failure_r: float = -0.35,
    confirmation: timedelta = timedelta(seconds=60),
) -> tuple[str, float] | None:
    """Return the first continuously confirmed delayed-failure observation.

    The clock resets as soon as either price recovers above the failure boundary
    or prior MFE reaches the disqualifying threshold.  This mirrors the durable
    terminal-global timer used by the EA and cannot fire from opening spread.
    """
    entered = datetime.strptime(entry_utc, "%Y.%m.%d %H:%M:%S")
    peak_r = 0.0
    failure_since: datetime | None = None
    for utc, current_r in sorted(observations):
        observed = datetime.strptime(utc, "%Y.%m.%d %H:%M:%S")
        peak_r = max(peak_r, current_r)
        qualifies = (
            observed - entered >= minimum_age
            and peak_r < maximum_peak_r
            and current_r <= failure_r
        )
        if not qualifies:
            failure_since = None
            continue
        if failure_since is None:
            failure_since = observed
        if observed - failure_since >= confirmation:
            return utc, current_r
    return None


@dataclass
class Replay:
    account: str
    ticket: str
    day: str
    entry_utc: str
    symbol: str
    market: str
    direction: str
    initial_risk: float
    actual_net: float
    actual_net_r: float
    recorded_peak_r: float
    candidate_exit_utc: str | None
    candidate_exit_reason: str | None
    candidate_floor_r: float | None
    observed_cross_r: float | None
    modeled_net_r: float
    change_r: float


def load(path: Path, account: str) -> list[Replay]:
    csv.field_size_limit(sys.maxsize)
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as handle:
        rows = list(csv.DictReader(handle))
    exits = {
        details(row["detail"]).get("position_id", ""): row
        for row in rows
        if row["event"] == "EXIT"
    }
    output: list[Replay] = []
    for entry in (row for row in rows if row["event"] == "ENTRY"):
        exit_row = exits.get(entry["ticket"])
        if not exit_row:
            continue
        entered = details(entry["detail"])
        exited = details(exit_row["detail"])
        risk = float(entered["initial_risk"])
        actual_net = float(exited["net"])
        actual_r = actual_net / risk
        commission_r = abs(float(exited.get("commission", "0"))) / risk
        path: list[tuple[str, float]] = []
        for row in rows:
            if row["ticket"] != entry["ticket"] or not (entry["utc"] <= row["utc"] <= exit_row["utc"]):
                continue
            match = CURRENT_R.search(row["detail"])
            if match:
                path.append((row["utc"], float(match.group(1))))
        path.sort()
        peak = 0.0
        trigger = None
        failure_since: datetime | None = None
        entered_utc = datetime.strptime(entry["utc"], "%Y.%m.%d %H:%M:%S")
        for utc, current_r in path:
            peak = max(peak, current_r)
            floor = candidate_floor(peak)
            if floor > -1.0 and current_r <= floor:
                trigger = (utc, floor, current_r, "TIGHTER_MONOTONIC_PROFIT_FLOOR")
                break
            age = datetime.strptime(utc, "%Y.%m.%d %H:%M:%S") - entered_utc
            failed = age >= timedelta(minutes=15) and peak < 0.15 and current_r <= -0.35
            if failed:
                if failure_since is None:
                    failure_since = datetime.strptime(utc, "%Y.%m.%d %H:%M:%S")
            else:
                failure_since = None
            observed = datetime.strptime(utc, "%Y.%m.%d %H:%M:%S")
            if failure_since is not None and observed - failure_since >= timedelta(seconds=60):
                trigger = (utc, current_r, current_r, "DELAYED_EARLY_FAILURE")
                break
        if trigger:
            modeled = trigger[1] - commission_r
            trigger_utc, floor_r, cross_r, trigger_reason = trigger
        else:
            modeled = actual_r
            trigger_utc = None
            trigger_reason = None
            floor_r = None
            cross_r = None
        recorded_peak = float(exited.get("RUNNER_PEAK_R", peak))
        output.append(Replay(
            account=account,
            ticket=entry["ticket"],
            day=entry["utc"][:10],
            entry_utc=entry["utc"],
            symbol=entry["symbol"],
            market=market(entry["symbol"]),
            direction=entry["direction"],
            initial_risk=risk,
            actual_net=actual_net,
            actual_net_r=round(actual_r, 6),
            recorded_peak_r=round(recorded_peak, 6),
            candidate_exit_utc=trigger_utc,
            candidate_exit_reason=trigger_reason,
            candidate_floor_r=round(floor_r, 6) if floor_r is not None else None,
            observed_cross_r=round(cross_r, 6) if cross_r is not None else None,
            modeled_net_r=round(modeled, 6),
            change_r=round(modeled - actual_r, 6),
        ))
    return output


def main() -> int:
    executions: list[Replay] = []
    for account in ("fp", "f10", "f100"):
        executions.extend(load(EVIDENCE / f"{account}-evidence.csv", account))
    # One market event copied to multiple accounts is one independent signal.
    clusters: list[list[Replay]] = []
    for item in sorted(executions, key=lambda value: value.entry_utc):
        item_time = datetime.strptime(item.entry_utc, "%Y.%m.%d %H:%M:%S")
        match = next((
            cluster for cluster in reversed(clusters)
            if cluster[0].market == item.market
            and cluster[0].direction == item.direction
            and item_time - datetime.strptime(cluster[0].entry_utc, "%Y.%m.%d %H:%M:%S") <= timedelta(minutes=2)
        ), None)
        if match is None:
            clusters.append([item])
        else:
            match.append(item)
    sample = [next((item for item in cluster if item.account == "fp"), cluster[0]) for cluster in clusters]
    report = {
        "schema": "SOLTRADE_V202_PROFIT_RETENTION_REPLAY_V1",
        "orders_placed": False,
        "strategy_changed": False,
        "deployment_performed": False,
        "resolution": "recorded evidence observations; no invented intratick prices",
        "candidate_floor": {
            "below_0.50R_peak": "unchanged",
            "0.50_to_0.75R_peak": "protect 0.20R",
            "0.75_to_1.00R_peak": "protect 0.35R",
            "1.00_to_1.50R_peak": "protect max(0.60R, peak-0.65R)",
            "1.50R_plus_peak": "resume existing expansion allowance; never below 0.84R",
        },
        "delayed_early_failure": {
            "minimum_age_minutes": 15,
            "maximum_prior_mfe_r": 0.15,
            "current_r_at_or_below": -0.35,
            "continuous_confirmation_seconds": 60,
        },
        "summary": {
            "account_executions": len(executions),
            "independent_signals": len(sample),
            "actual_independent_net_r": round(sum(x.actual_net_r for x in sample), 6),
            "modeled_independent_net_r": round(sum(x.modeled_net_r for x in sample), 6),
            "change_r": round(sum(x.change_r for x in sample), 6),
            "improved": sum(x.change_r > 1e-6 for x in sample),
            "regressed": sum(x.change_r < -1e-6 for x in sample),
            "unchanged": sum(abs(x.change_r) <= 1e-6 for x in sample),
            "early_failure_exits": sum(x.candidate_exit_reason == "DELAYED_EARLY_FAILURE" for x in sample),
        },
        "independent_signals": [x.__dict__ for x in sample],
        "account_executions": [x.__dict__ for x in executions],
        "limitations": [
            "telemetry is sampled rather than every tick",
            "modeled stop fills assume the protected floor less recorded round-trip commission",
            "future profit after an earlier candidate exit is intentionally not counted",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
