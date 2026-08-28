#!/usr/bin/env python3
"""Research-only shadow audit for the live Fast Multi V2.202 CSV feed.

This process never connects to MetaTrader and has no order path.  It consumes
the production audit CSVs, evaluates one-gate-at-a-time counterfactuals, and
tracks executable-price MFE/MAE after each rejected score-qualified decision.
Future observations are labelled research-only and never feed the EA.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
import os
import statistics
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


SAST = timezone(timedelta(hours=2))
UTC = timezone.utc
SCHEMA = "SOLTRADE_FAST_MULTI_V202_SHADOW_V1"
AUDIT_DIR = Path(
    "/home/tibule12/.wine-fpmarkets/drive_c/users/tibule12/AppData/Roaming/"
    "MetaQuotes/Terminal/Common/Files/SolTradeFastMultiMarketV2"
)
REPORT_DIR = Path("reports/fast-multi-market-v2/shadow-admission-20260827")

CURRENT = {
    "spread_atr": 8.0,
    "spread_median_ratio": 1.75,
    "movement_to_spread": 5.0,
    "min_reward_r": 1.15,
    "min_entry_score": 68.0,
    "directional_dominance": 12.0,
    "no_trade_dominance": 8.0,
    "min_expected_move_cost_multiple": 3.0,
    "absolute_score": 60.0,
    "persistence_scans": 3,
    "persistence_seconds": 30,
    "signal_drift": 0.60,
    "confirmation_consumed": 0.35,
    "impulse_extension": 1.75,
    "breakout_extension": 0.75,
}

PRIMARY_TO_GATE = {
    "POST_RECOVERY_HISTORY_WARMUP": "history_ready",
    "POST_RECOVERY_HISTORY_NOT_SYNCHRONISED": "history_ready",
    "STALE_TICK": "fresh_tick",
    "SPREAD_BASELINE_WARMUP": "spread_baseline",
    "ABNORMAL_SPREAD": "spread_median",
    "HIGH_SPREAD_RELATIVE_TO_M5_ATR": "spread_atr",
    "MOVEMENT_WEAK_RELATIVE_TO_SPREAD": "movement_to_spread",
    "MOVE_EXHAUSTED_OR_LATE_CHASE": "move_not_exhausted",
    "M5_M15_DIRECTIONAL_CONFLICT": "m5_m15_conflict",
    "M5_DIRECTION_UNCONFIRMED": "m5_direction",
    "M15_DIRECTION_UNCONFIRMED": "m15_direction",
    "RANGE_CHOP_WITHOUT_STRUCTURAL_TRIGGER": "not_range_chop",
    "NO_VALID_DIRECTIONAL_STRUCTURE_OR_TRIGGER": "directional_trigger",
    "EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS": "expected_move_cost",
    "OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS": "min_reward_r",
    "INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS": "min_reward_r",
    "DIRECTIONAL_EVIDENCE_WEAK": "entry_score",
    "OPPOSITE_CASE_NOT_CLEARLY_DEFEATED": "directional_dominance",
    "NO_TRADE_CASE_DOMINATES": "no_trade_dominance",
    "BUY_FIGHTS_OBVIOUS_M5_MOMENTUM": "m5_momentum",
    "SELL_FIGHTS_OBVIOUS_M5_MOMENTUM": "m5_momentum",
    "ABSOLUTE_ADMISSION_SCORE_BELOW_NO_TRADE_THRESHOLD": "absolute_score",
    "SETUP_SPECIFIC_CONFIRMATION_PENDING": "persistence",
    "LATE_ENTRY_SIGNAL_DRIFT_EXCEEDED": "signal_drift",
    "CONFIRMATION_CONSUMED_TOO_MUCH_REMAINING_OPPORTUNITY": "confirmation_consumed",
    "LATE_ENTRY_M5_IMPULSE_EXTENSION_EXCEEDED": "impulse_extension",
    "EXHAUSTED_BREAKOUT_EXTENSION_EXCEEDED": "breakout_extension",
}

GATE_ORDER = [
    "history_ready",
    "fresh_tick",
    "spread_baseline",
    "spread_median",
    "spread_atr",
    "movement_to_spread",
    "move_not_exhausted",
    "m5_m15_conflict",
    "m5_direction",
    "m15_direction",
    "not_range_chop",
    "directional_trigger",
    "expected_move_cost",
    "min_reward_r",
    "entry_score",
    "directional_dominance",
    "no_trade_dominance",
    "m5_momentum",
    "absolute_score",
    "persistence",
    "signal_drift",
    "confirmation_consumed",
    "impulse_extension",
    "breakout_extension",
]

ABLATIONS = {
    "LIVE_ALL_GATES": set(),
    "SHADOW_WITHOUT_SPREAD_ATR_GATE": {"spread_atr"},
    "SHADOW_WITHOUT_OPPOSING_STRUCTURE_GATE": {"opposing_structure"},
    "SHADOW_WITHOUT_MIN_RR_GATE": {"min_reward_r"},
    "SHADOW_WITHOUT_60_POINT_THRESHOLD": {"absolute_score"},
    "SHADOW_WITHOUT_EXTENSION_GATE": {"impulse_extension", "breakout_extension"},
    "SHADOW_WITHOUT_SIGNAL_DRIFT_GATE": {"signal_drift"},
    "SHADOW_WITHOUT_M5_M15_CONFLICT_GATE": {"m5_m15_conflict"},
}

OUTCOME_WINDOWS = (5, 15, 30, 60)
RR_THRESHOLDS = (1.00, 1.10, 1.15, 1.20, 1.25, 1.35, 1.50)
ROOM_REASONS = {
    "OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS",
    "INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS",
}


def f(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def i(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def b(value: Any) -> bool:
    return str(value).lower() == "true"


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S").replace(tzinfo=UTC)


def kv(value: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in value.split(";"):
        if "=" in item:
            key, val = item.split("=", 1)
            result[key] = val
    return result


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def median(values: Iterable[float]) -> float | None:
    data = list(values)
    return statistics.median(data) if data else None


def atomic_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def atomic_json(path: Path, payload: Any) -> None:
    atomic_text(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def atomic_csv(path: Path, fieldnames: list[str], rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", newline="", encoding="utf-8", dir=path.parent, delete=False) as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
        temporary = Path(handle.name)
    os.replace(temporary, path)


@dataclass
class Observation:
    row: dict[str, str]
    time: datetime
    direction: int
    admission: dict[str, str]
    confirmation: dict[str, str]
    extension: dict[str, str]
    admission_score: float
    atr5: float | None
    atr15: float | None
    executable_mid: float

    @classmethod
    def from_row(cls, row: dict[str, str]) -> "Observation":
        direction = 1 if row.get("candidate_direction") == "BUY" else -1
        spread = f(row.get("raw_spread"))
        entry = f(row.get("entry"))
        current_mid = entry - direction * spread / 2.0
        spread_atr = f(row.get("spread_to_m5_atr_percent"))
        atr5 = 100.0 * spread / spread_atr if spread > 0 and spread_atr > 0 else None
        m15_extension = f(row.get("m15_swing_extension_atr"))
        m15_swing = f(row.get("m15_invalidation_swing"))
        numerator = direction * (entry - m15_swing)
        atr15 = numerator / m15_extension if numerator > 0 and m15_extension > 0 else None
        return cls(
            row=row,
            time=parse_time(row["utc"]),
            direction=direction,
            admission=kv(row.get("absolute_admission_components", "")),
            confirmation=kv(row.get("confirmation_timing", "")),
            extension=kv(row.get("extension_state", "")),
            admission_score=f(kv(row.get("absolute_admission_components", "")).get("final")),
            atr5=atr5,
            atr15=atr15,
            executable_mid=current_mid,
        )

    @property
    def market(self) -> str:
        return self.row.get("intended_market", "")

    @property
    def reason(self) -> str:
        return self.row.get("primary_rejection_reason", "")

    @property
    def score_qualified(self) -> bool:
        return self.admission_score >= CURRENT["absolute_score"]

    @property
    def meaningful(self) -> bool:
        return self.admission_score >= 55.0 or b(self.row.get("directional_core_qualified"))

    def unopposed_projection(self) -> float | None:
        if self.atr5 is None:
            return None
        alternatives = [2.20 * self.atr5]
        if self.atr15 is not None:
            alternatives.append(0.75 * self.atr15)
        return max(alternatives)


def load_observations(audit_dir: Path) -> tuple[list[Observation], list[Path]]:
    paths = sorted(audit_dir.glob("scan-history-v5-*.csv"))
    observations: list[Observation] = []
    for path in paths:
        with path.open(newline="", encoding="utf-8", errors="replace") as handle:
            for row in csv.DictReader(handle):
                if not row.get("utc") or row.get("candidate_direction") not in {"BUY", "SELL"}:
                    continue
                try:
                    observations.append(Observation.from_row(row))
                except (ValueError, KeyError):
                    # A concurrently appended partial row is ignored until the next pass.
                    continue
    observations.sort(key=lambda item: (item.time, i(item.row.get("scan_sequence")), item.market))
    return observations, paths


def inferred_gate_status(obs: Observation) -> dict[str, bool | None]:
    row = obs.row
    component = obs.admission
    confirmation = obs.confirmation
    extension = obs.extension
    directional_core = b(row.get("directional_core_qualified"))
    conflict_penalty = f(component.get("conflict_penalty"))
    statuses: dict[str, bool | None] = {
        "history_ready": obs.reason not in {
            "POST_RECOVERY_HISTORY_WARMUP", "POST_RECOVERY_HISTORY_NOT_SYNCHRONISED"
        },
        "fresh_tick": row.get("tick_state") == "FRESH",
        "spread_baseline": b(row.get("spread_baseline_ready")),
        "spread_median": (
            row.get("spread_filter_result") == "PASS"
            and f(row.get("spread_median_ratio")) <= CURRENT["spread_median_ratio"]
        ),
        "spread_atr": f(row.get("spread_to_m5_atr_percent")) <= CURRENT["spread_atr"],
        "movement_to_spread": f(row.get("movement_to_spread")) >= CURRENT["movement_to_spread"],
        "move_not_exhausted": True if directional_core else None,
        "m5_m15_conflict": conflict_penalty < 99.0,
        "m5_direction": True if directional_core else None,
        "m15_direction": True if directional_core else None,
        "not_range_chop": component.get("range_chop") == "false",
        "directional_trigger": component.get("trigger") == "true",
        "expected_move_cost": (
            f(row.get("expected_net_move")) > 0
            and f(row.get("cost_multiple")) >= CURRENT["min_expected_move_cost_multiple"]
        ),
        "min_reward_r": f(row.get("reward_r")) >= CURRENT["min_reward_r"],
        "entry_score": f(row.get("score")) >= CURRENT["min_entry_score"],
        "directional_dominance": f(row.get("score")) >= (
            f(row.get("sell_score")) if obs.direction > 0 else f(row.get("buy_score"))
        ) + CURRENT["directional_dominance"],
        "no_trade_dominance": f(row.get("score")) >= f(row.get("no_trade_score")) + CURRENT["no_trade_dominance"],
        "m5_momentum": True if directional_core else None,
        "absolute_score": obs.admission_score >= CURRENT["absolute_score"],
        "persistence": (
            i(row.get("directional_persistence_count")) >= CURRENT["persistence_scans"]
            and i(row.get("directional_persistence_seconds")) >= CURRENT["persistence_seconds"]
        ),
        "signal_drift": f(row.get("entry_drift_m5_atr")) <= CURRENT["signal_drift"],
        "confirmation_consumed": f(confirmation.get("consumed")) <= CURRENT["confirmation_consumed"],
        "impulse_extension": f(extension.get("impulse_atr")) <= CURRENT["impulse_extension"],
        "breakout_extension": f(extension.get("breakout_atr")) <= CURRENT["breakout_extension"],
    }
    primary = PRIMARY_TO_GATE.get(obs.reason)
    if primary in statuses:
        primary_index = GATE_ORDER.index(primary)
        for gate in GATE_ORDER[:primary_index]:
            if statuses[gate] is None:
                statuses[gate] = True
        statuses[primary] = False
    if b(row.get("eligible")):
        statuses = {gate: True for gate in GATE_ORDER}
    return statuses


def score_adjustment(obs: Observation, removed: set[str]) -> tuple[float, dict[str, float]]:
    score = obs.admission_score
    overrides: dict[str, float] = {}
    if "spread_atr" in removed:
        contribution = 8.0 * clamp(f(obs.row.get("spread_to_m5_atr_percent")) / CURRENT["spread_atr"], 0.0, 1.5)
        score += contribution
    if "m5_m15_conflict" in removed:
        score += f(obs.admission.get("conflict_penalty"))
    if "impulse_extension" in removed or "breakout_extension" in removed:
        score += f(obs.admission.get("extension_penalty"))
    if "opposing_structure" in removed and obs.admission.get("opposing_structure") == "true":
        projection = obs.unopposed_projection()
        if projection is not None:
            cost = f(obs.row.get("expected_cost_move"))
            stop = f(obs.row.get("stop_distance"))
            old_room_score = f(obs.admission.get("remaining_room"))
            new_reward = (projection - cost) / stop if stop > 0 else -math.inf
            new_room_score = 20.0 * clamp(new_reward / 2.0, 0.0, 1.0)
            score += new_room_score - old_room_score
            overrides = {
                "available_move": projection,
                "expected_net_move": projection - cost,
                "cost_multiple": projection / max(cost, 1e-12),
                "reward_r": new_reward,
            }
    return score, overrides


def evaluate(obs: Observation, removed: set[str] | None = None) -> str:
    removed = removed or set()
    statuses = inferred_gate_status(obs)
    score, overrides = score_adjustment(obs, removed)
    if "opposing_structure" in removed:
        if overrides:
            statuses["expected_move_cost"] = (
                overrides["expected_net_move"] > 0 and overrides["cost_multiple"] >= 3.0
            )
            statuses["min_reward_r"] = overrides["reward_r"] >= CURRENT["min_reward_r"]
        elif obs.admission.get("opposing_structure") == "true":
            return "UNKNOWN:UNOPPOSED_PROJECTION_NOT_RECONSTRUCTABLE"
    statuses["absolute_score"] = score >= CURRENT["absolute_score"]
    for gate in removed:
        if gate in statuses:
            statuses[gate] = True
    failures = [gate for gate in GATE_ORDER if statuses[gate] is False]
    if failures:
        return "REJECTED:" + failures[0]
    unknown = [gate for gate in GATE_ORDER if statuses[gate] is None]
    if unknown:
        return "UNKNOWN:" + "|".join(unknown)
    return "ELIGIBLE"


def sensitivity_result(obs: Observation, gate: str, value: float) -> str:
    statuses = inferred_gate_status(obs)
    adjusted_score = obs.admission_score
    if gate == "spread_atr":
        old_penalty = 8.0 * clamp(f(obs.row.get("spread_to_m5_atr_percent")) / CURRENT["spread_atr"], 0.0, 1.5)
        new_penalty = 8.0 * clamp(f(obs.row.get("spread_to_m5_atr_percent")) / value, 0.0, 1.5)
        adjusted_score += old_penalty - new_penalty
        statuses["spread_atr"] = f(obs.row.get("spread_to_m5_atr_percent")) <= value
    elif gate == "absolute_score":
        statuses["absolute_score"] = adjusted_score >= value
    elif gate == "signal_drift":
        statuses["signal_drift"] = f(obs.row.get("entry_drift_m5_atr")) <= value
    elif gate == "min_reward_r":
        statuses["min_reward_r"] = f(obs.row.get("reward_r")) >= value
    elif gate == "impulse_extension":
        impulse = f(obs.extension.get("impulse_atr"))
        old = 12.0 * clamp((max(0.0, impulse) - 0.75) / max(CURRENT["impulse_extension"] - 0.75, 0.01), 0.0, 1.0)
        new = 12.0 * clamp((max(0.0, impulse) - 0.75) / max(value - 0.75, 0.01), 0.0, 1.0)
        adjusted_score += old - new
        statuses["impulse_extension"] = impulse <= value
    elif gate == "breakout_extension":
        breakout = f(obs.extension.get("breakout_atr"))
        old = 8.0 * clamp((breakout - 0.25) / max(CURRENT["breakout_extension"] - 0.25, 0.01), 0.0, 1.0)
        new = 8.0 * clamp((breakout - 0.25) / max(value - 0.25, 0.01), 0.0, 1.0)
        adjusted_score += old - new
        statuses["breakout_extension"] = breakout <= value
    statuses["absolute_score"] = adjusted_score >= (
        value if gate == "absolute_score" else CURRENT["absolute_score"]
    )
    failures = [name for name in GATE_ORDER if statuses[name] is False]
    unknown = [name for name in GATE_ORDER if statuses[name] is None]
    if failures:
        return "REJECTED:" + failures[0]
    return "UNKNOWN:" + "|".join(unknown) if unknown else "ELIGIBLE"


def candidate_row(obs: Observation) -> dict[str, Any]:
    row = obs.row
    projection = obs.unopposed_projection()
    opposing = obs.admission.get("opposing_structure") == "true"
    available = f(row.get("available_move"))
    exact_level_observable = bool(opposing and projection is not None and available < projection - max(1e-12, 0.0001 * projection))
    inferred_level = f(row.get("entry")) + obs.direction * available if exact_level_observable else None
    statuses = inferred_gate_status(obs)
    result: dict[str, Any] = {
        "schema": SCHEMA,
        "research_label": "SHADOW_COUNTERFACTUAL_ONLY_NO_ORDER_PATH",
        "timestamp_utc": row.get("utc"),
        "timestamp_sast": row.get("sast"),
        "scan_sequence": row.get("scan_sequence"),
        "symbol": obs.market,
        "broker_symbol": row.get("resolved_broker_symbol"),
        "direction": row.get("candidate_direction"),
        "setup_key": row.get("setup_key"),
        "live_decision": row.get("decision"),
        "live_eligible": row.get("eligible"),
        "exact_rejecting_gate": obs.reason,
        "final_admission_score": obs.admission_score,
        "no_trade_threshold": CURRENT["absolute_score"],
        "raw_directional_score": f(row.get("score")),
        "m5_state": "CONFIRMED_ABSOLUTE" if b(row.get("m5_confirmed")) else "UNCONFIRMED_ABSOLUTE",
        "m15_state": "CONFIRMED_ABSOLUTE" if b(row.get("m15_confirmed")) else "UNCONFIRMED_ABSOLUTE",
        "m5_m15_conflict": f(obs.admission.get("conflict_penalty")) >= 99.0,
        "spread_price": f(row.get("raw_spread")),
        "spread_points": f(row.get("spread_points")),
        "spread_cost_usd": row.get("expected_cost_usd") or "NOT_OBSERVABLE_FROM_V5_NO_TICK_VALUE_OR_PROPOSED_VOLUME",
        "m5_atr_price": obs.atr5,
        "m15_atr_price": obs.atr15,
        "spread_m5_atr_percent": f(row.get("spread_to_m5_atr_percent")),
        "signal_drift_atr": f(row.get("entry_drift_m5_atr")),
        "impulse_extension_atr": f(obs.extension.get("impulse_atr")),
        "breakout_extension_atr": f(obs.extension.get("breakout_atr")),
        "entry_candidate_price": f(row.get("entry")),
        "initial_structural_stop": f(row.get("stop")),
        "risk_distance_price": f(row.get("stop_distance")),
        "opposing_structure_found": opposing,
        "nearest_opposing_structure": inferred_level if exact_level_observable else "NOT_EXACTLY_OBSERVABLE_FROM_V5",
        "stop_anchor_price": row.get("stop_anchor_price") or row.get("selected_invalidation"),
        "stop_anchor_timeframe": row.get("stop_anchor_timeframe") or "NOT_RECORDED_IN_V5",
        "stop_anchor_created_utc": row.get("stop_anchor_time") or "NOT_RECORDED_IN_V5",
        "stop_anchor_age_seconds": row.get("stop_anchor_age_seconds") or "NOT_RECORDED_IN_V5",
        "opposing_structure_timeframe": row.get("opposing_structure_timeframe") or "NOT_RECORDED_IN_V5",
        "opposing_structure_created_utc": row.get("opposing_structure_time") or "NOT_RECORDED_IN_V5",
        "opposing_structure_age_seconds": row.get("opposing_structure_age_seconds") or "NOT_RECORDED_IN_V5",
        "opposing_structure_reactions": row.get("opposing_reaction_count") or "NOT_RECORDED_IN_V5",
        "opposing_structure_distance_price": available if opposing else None,
        "opposing_structure_distance_m5_atr": available / obs.atr5 if opposing and obs.atr5 else None,
        "remaining_room_price": available,
        "remaining_room_usd": "NOT_OBSERVABLE_FROM_V5" if not row.get("proposed_volume") else "DERIVABLE_FROM_V6_TICK_AND_VOLUME_FIELDS",
        "remaining_room_r_after_costs": f(row.get("reward_r")),
        "expected_reward_after_costs_price": f(row.get("expected_net_move")),
        "required_minimum_reward_r": f(row.get("initial_clean_room_required_r"), CURRENT["min_reward_r"]),
        "all_gate_states_json": json.dumps(statuses, sort_keys=True),
    }
    for name, removed in ABLATIONS.items():
        result[name.lower()] = (
            "ELIGIBLE" if name == "LIVE_ALL_GATES" and b(row.get("eligible"))
            else ("REJECTED:" + obs.reason if name == "LIVE_ALL_GATES" else evaluate(obs, removed))
        )
    return result


def episode_ids(candidates: list[Observation]) -> dict[int, str]:
    # A setup key can change several times inside one continuous market impulse.
    # Group by market/direction and require a 15-minute score-qualified gap so
    # one trend is not counted as many independent rejected opportunities.
    latest: dict[tuple[str, int], tuple[datetime, str, int]] = {}
    mapping: dict[int, str] = {}
    counters: Counter[tuple[str, int]] = Counter()
    for obs in candidates:
        key = (obs.market, obs.direction)
        previous = latest.get(key)
        if previous is None or obs.time - previous[0] > timedelta(minutes=15):
            counters[key] += 1
            episode = f"{obs.market}:{obs.direction}:{counters[key]}"
        else:
            episode = previous[1]
        latest[key] = (obs.time, episode, counters[key])
        mapping[id(obs)] = episode
    return mapping


def outcome_rows(all_observations: list[Observation], candidates: list[Observation]) -> list[dict[str, Any]]:
    by_market: dict[str, list[Observation]] = defaultdict(list)
    for obs in all_observations:
        by_market[obs.market].append(obs)
    market_times = {market: [obs.time for obs in items] for market, items in by_market.items()}
    episodes = episode_ids(candidates)
    first_in_episode: set[str] = set()
    latest_time = all_observations[-1].time if all_observations else datetime.now(UTC)
    results: list[dict[str, Any]] = []
    for candidate in candidates:
        episode = episodes[id(candidate)]
        is_anchor = episode not in first_in_episode
        first_in_episode.add(episode)
        entry = f(candidate.row.get("entry"))
        spread = f(candidate.row.get("raw_spread"))
        nonspread_cost = max(0.0, f(candidate.row.get("expected_cost_move")) - spread)
        risk = f(candidate.row.get("stop_distance")) + nonspread_cost
        items = by_market[candidate.market]
        times = market_times[candidate.market]
        start = bisect.bisect_right(times, candidate.time)
        end = bisect.bisect_right(times, candidate.time + timedelta(minutes=60))
        future = items[start:end]
        record: dict[str, Any] = {
            "schema": SCHEMA,
            "research_label": "POST_DECISION_RESEARCH_ONLY",
            "timestamp_utc": candidate.row.get("utc"),
            "symbol": candidate.market,
            "direction": candidate.row.get("candidate_direction"),
            "setup_key": candidate.row.get("setup_key"),
            "episode_id": episode,
            "episode_anchor": is_anchor,
            "rejecting_gate": candidate.reason,
            "entry_candidate_price": entry,
            "risk_distance_including_nonspread_cost": risk,
            "expected_cost_move": f(candidate.row.get("expected_cost_move")),
            "expected_cost_r": f(candidate.row.get("expected_cost_move")) / risk if risk > 0 else None,
        }
        path: list[tuple[datetime, float]] = []
        for item in future:
            future_spread = f(item.row.get("raw_spread"))
            exit_price = item.executable_mid - candidate.direction * future_spread / 2.0
            net_move = candidate.direction * (exit_price - entry) - nonspread_cost
            if risk > 0:
                path.append((item.time, net_move / risk))
        for minutes in OUTCOME_WINDOWS:
            values = [value for stamp, value in path if stamp <= candidate.time + timedelta(minutes=minutes)]
            complete = latest_time >= candidate.time + timedelta(minutes=minutes)
            record[f"window_{minutes}m_status"] = "COMPLETE" if complete else "PENDING"
            record[f"mfe_{minutes}m_r"] = max(values) if values else None
            record[f"mae_{minutes}m_r"] = min(values) if values else None
        plus_half = next((stamp for stamp, value in path if value >= 0.5), None)
        minus_one = next((stamp for stamp, value in path if value <= -1.0), None)
        record["failed_immediately"] = bool(minus_one and (plus_half is None or minus_one < plus_half))
        stop_index = next((index for index, (_, value) in enumerate(path) if value <= -1.0), len(path))
        tradable_path = path[: stop_index + 1]
        record["theoretical_stop_hit"] = stop_index < len(path)
        record["mfe_before_theoretical_stop_60m_r"] = (
            max(value for _, value in tradable_path) if tradable_path else None
        )
        record["mae_before_theoretical_stop_60m_r"] = (
            min(value for _, value in tradable_path) if tradable_path else None
        )
        record["terminal_60m_net_r"] = path[-1][1] if path else None
        record["terminal_60m_gross_r"] = (
            path[-1][1] + f(candidate.row.get("expected_cost_move")) / risk
            if path and risk > 0 else None
        )
        results.append(record)
    return results


def structure_probe_requests(
    candidates: list[Observation], outcomes: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    anchors = {
        (row["timestamp_utc"], row["symbol"], row["direction"])
        for row in outcomes if row["episode_anchor"]
    }
    rows: list[dict[str, Any]] = []
    for obs in candidates:
        key = (obs.row.get("utc"), obs.market, obs.row.get("candidate_direction"))
        if key not in anchors:
            continue
        rows.append({
            "request_id": f"{obs.market}-{obs.row.get('scan_sequence')}-{obs.row.get('setup_key')}",
            "decision_epoch_utc": int(obs.time.timestamp()),
            "timestamp_utc": obs.row.get("utc"),
            "intended_market": obs.market,
            "broker_symbol": obs.row.get("resolved_broker_symbol"),
            "direction": obs.direction,
            "entry": obs.row.get("entry"),
            "stop": obs.row.get("stop"),
            "stop_distance": obs.row.get("stop_distance"),
            "spread": obs.row.get("raw_spread"),
            "production_spread_m5_atr_percent": obs.row.get("spread_to_m5_atr_percent"),
            "expected_cost_move": obs.row.get("expected_cost_move"),
            "available_move": obs.row.get("available_move"),
            "reward_r": obs.row.get("reward_r"),
            "admission_score": obs.admission_score,
            "rejecting_gate": obs.reason,
            "production_opposing_structure_found": obs.admission.get("opposing_structure", ""),
        })
    return rows


def count_eligible(results: Iterable[str]) -> dict[str, int]:
    counts = Counter(results)
    return {
        "eligible": counts.get("ELIGIBLE", 0),
        "unknown": sum(value for key, value in counts.items() if key.startswith("UNKNOWN:")),
        "rejected": sum(value for key, value in counts.items() if key.startswith("REJECTED:")),
    }


def runtime_state(audit_dir: Path) -> dict[str, str]:
    path = audit_dir / "runtime.csv"
    if not path.exists():
        return {}
    with path.open(newline="", encoding="utf-8", errors="replace") as handle:
        reader = csv.DictReader(handle)
        return next(reader, {})


def make_summary(
    all_observations: list[Observation],
    candidate_rows: list[dict[str, Any]],
    outcomes: list[dict[str, Any]],
    paths: list[Path],
    runtime: dict[str, str],
) -> dict[str, Any]:
    meaningful_candidates = [obs for obs in all_observations if obs.meaningful]
    score_candidates = [obs for obs in all_observations if obs.score_qualified]
    rejected = [obs for obs in score_candidates if not b(obs.row.get("eligible"))]
    rejection = Counter(obs.reason for obs in rejected)
    top_gate, top_count = rejection.most_common(1)[0] if rejection else (None, 0)
    ablations: dict[str, dict[str, int]] = {}
    for key in ABLATIONS:
        column = key.lower()
        ablations[key] = count_eligible(row[column] for row in candidate_rows if f(row["final_admission_score"]) >= 60.0)
    sensitivity: dict[str, dict[str, dict[str, int]]] = {}
    settings = {
        "spread_atr": [6, 8, 10, 12, 15],
        "absolute_score": [55, 60, 65, 70],
        "impulse_extension": [1.50, 1.75, 2.00, 2.25],
        "breakout_extension": [0.60, 0.75, 0.90, 1.00],
        "signal_drift": [0.40, 0.60, 0.80, 1.00],
        "min_reward_r": list(RR_THRESHOLDS),
    }
    for gate, values in settings.items():
        sensitivity[gate] = {}
        pool = meaningful_candidates if gate == "absolute_score" else score_candidates
        for value in values:
            sensitivity[gate][str(value)] = count_eligible(sensitivity_result(obs, gate, value) for obs in pool)
    complete = [row for row in outcomes if row["window_60m_status"] == "COMPLETE"]
    anchor_complete = [row for row in complete if row["episode_anchor"]]

    outcome_by_observation = {id(obs): row for obs, row in zip(score_candidates, outcomes)}
    episode_by_observation = episode_ids(score_candidates)

    def is_london(obs: Observation) -> bool:
        local = obs.time.astimezone(SAST)
        minutes = local.hour * 60 + local.minute
        return 9 * 60 <= minutes < 18 * 60

    def selected_episode_outcomes(items: list[Observation]) -> dict[str, Any]:
        rows = [outcome_by_observation[id(obs)] for obs in items]
        complete_rows = [row for row in rows if row["window_60m_status"] == "COMPLETE"]
        count = len(complete_rows)
        false_rejections = [
            row for row in complete_rows
            if f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 0.5
            and not bool(row["failed_immediately"])
        ]
        stopped_outcome = [
            -1.0 if bool(row["theoretical_stop_hit"]) else f(row["terminal_60m_net_r"])
            for row in complete_rows
        ]
        gross_outcome = [
            value + f(row["expected_cost_r"])
            for value, row in zip(stopped_outcome, complete_rows)
        ]
        return {
            "admitted_episodes": len(items),
            "complete_60m_episodes": count,
            "mfe_ge_0_5r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 0.5 for row in complete_rows),
            "mfe_ge_1r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.0 for row in complete_rows),
            "mfe_ge_1_5r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.5 for row in complete_rows),
            "mfe_ge_2r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 2.0 for row in complete_rows),
            "mfe_ge_0_5r_rate": len(false_rejections) / count if count else None,
            "mfe_ge_1r_rate": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.0 for row in complete_rows) / count if count else None,
            "mfe_ge_1_5r_rate": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.5 for row in complete_rows) / count if count else None,
            "mfe_ge_2r_rate": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 2.0 for row in complete_rows) / count if count else None,
            "theoretical_stop_hits": sum(bool(row["theoretical_stop_hit"]) for row in complete_rows),
            "theoretical_stop_hit_rate": sum(bool(row["theoretical_stop_hit"]) for row in complete_rows) / count if count else None,
            "median_mfe_60m_r": median(f(row["mfe_before_theoretical_stop_60m_r"]) for row in complete_rows),
            "median_mae_60m_r": median(f(row["mae_before_theoretical_stop_60m_r"]) for row in complete_rows),
            "mean_60m_net_expectancy_r_proxy": statistics.mean(stopped_outcome) if stopped_outcome else None,
            "mean_60m_gross_expectancy_r_proxy": statistics.mean(gross_outcome) if gross_outcome else None,
            "median_expected_cost_move": median(f(row["expected_cost_move"]) for row in complete_rows),
            "median_expected_cost_r": median(f(row["expected_cost_r"]) for row in complete_rows),
            "false_rejection_count": len(false_rejections),
            "false_rejection_rate": len(false_rejections) / count if count else None,
        }

    threshold_episode_sensitivity: dict[str, Any] = {}
    for threshold in RR_THRESHOLDS:
        first_accepted: dict[str, Observation] = {}
        for obs in score_candidates:
            episode = episode_by_observation[id(obs)]
            if episode in first_accepted:
                continue
            if sensitivity_result(obs, "min_reward_r", threshold) == "ELIGIBLE":
                first_accepted[episode] = obs
        accepted = list(first_accepted.values())
        threshold_episode_sensitivity[str(threshold)] = {
            "all_sessions": selected_episode_outcomes(accepted),
            "london": selected_episode_outcomes([obs for obs in accepted if is_london(obs)]),
            "admitted_observations": sum(
                sensitivity_result(obs, "min_reward_r", threshold) == "ELIGIBLE"
                for obs in score_candidates
            ),
        }

    first_by_episode: dict[str, Observation] = {}
    for obs in score_candidates:
        first_by_episode.setdefault(episode_by_observation[id(obs)], obs)
    london_anchors = [obs for obs in first_by_episode.values() if is_london(obs)]
    london_rejection_groups = {
        "WIDE_STOP_1_25R_REJECTS": selected_episode_outcomes([
            obs for obs in london_anchors
            if obs.reason in ROOM_REASONS
            and obs.admission.get("opposing_structure") != "true"
        ]),
        "OPPOSING_STRUCTURE_REJECTS": selected_episode_outcomes([
            obs for obs in london_anchors
            if obs.reason in ROOM_REASONS
            and obs.admission.get("opposing_structure") == "true"
        ]),
    }

    def outcome_breakdown(rows: list[dict[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for gate, items in _group(rows, lambda row: row["rejecting_gate"]).items():
            result[gate] = {
                "n": len(items),
                "mfe_ge_0_5r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 0.5 for row in items),
                "mfe_ge_1r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.0 for row in items),
                "mfe_ge_1_5r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 1.5 for row in items),
                "mfe_ge_2r": sum(f(row["mfe_before_theoretical_stop_60m_r"], -math.inf) >= 2.0 for row in items),
                "failed_immediately": sum(bool(row["failed_immediately"]) for row in items),
            }
        return result

    possible = len(score_candidates) >= 50 and not any(b(obs.row.get("eligible")) for obs in score_candidates)
    assessment = "POSSIBLE_OVER_FILTERING" if possible else "NORMAL_SELECTIVITY"

    def session_name(obs: Observation) -> str:
        local = obs.time.astimezone(SAST)
        minutes = local.hour * 60 + local.minute
        if minutes < 9 * 60:
            return "ASIA_OVERNIGHT"
        if minutes < 11 * 60:
            return "LONDON_OPEN"
        if minutes < 14 * 60 + 30:
            return "LONDON_SESSION"
        if minutes < 16 * 60 + 30:
            return "NEW_YORK_OPEN_OVERLAP"
        if minutes < 18 * 60:
            return "LONDON_NEW_YORK_OVERLAP"
        return "NEW_YORK_LATE"

    def asset_class(obs: Observation) -> str:
        if obs.market in {"XAUUSD", "XAGUSD"}:
            return "METALS"
        if obs.market in {"USTEC", "US500", "DE30", "STOXX50", "UK100"}:
            return "INDICES"
        if obs.market.endswith("JPY"):
            return "JPY_FX"
        return "NON_JPY_FX"

    def spread_metrics(items: list[Observation]) -> dict[str, Any]:
        values = [f(obs.row.get("spread_to_m5_atr_percent")) for obs in items]
        return {
            "evaluations": len(items),
            "scans_approx": len(items) / 19.0,
            "score_qualified": sum(obs.score_qualified for obs in items),
            "eligible": sum(b(obs.row.get("eligible")) for obs in items),
            "median_spread_atr_percent": median(values),
            "p75_spread_atr_percent": statistics.quantiles(values, n=4)[2] if len(values) >= 4 else None,
            "spread_atr_gate_pass_percent": sum(value <= CURRENT["spread_atr"] for value in values) / len(values) if values else None,
            "high_spread_primary_rejects": sum(obs.reason == "HIGH_SPREAD_RELATIVE_TO_M5_ATR" for obs in items),
            "stale_tick_primary_rejects": sum(obs.reason == "STALE_TICK" for obs in items),
            "opposing_structure_primary_rejects": sum(obs.reason in ROOM_REASONS for obs in items),
        }

    sessions = {
        name: spread_metrics(items)
        for name, items in _group(all_observations, session_name).items()
    }
    classes = {
        name: spread_metrics(items)
        for name, items in _group(all_observations, asset_class).items()
    }
    return {
        "schema": SCHEMA,
        "generated_utc": datetime.now(UTC).isoformat(),
        "research_only": True,
        "production_parameters_changed": False,
        "source_files": [str(path) for path in paths],
        "data_start_utc": all_observations[0].time.isoformat() if all_observations else None,
        "data_end_utc": all_observations[-1].time.isoformat() if all_observations else None,
        "scans": len({i(obs.row.get("scan_sequence")) for obs in all_observations}),
        "evaluations": len(all_observations),
        "score_qualified_count": len(score_candidates),
        "live_eligible_count": sum(b(obs.row.get("eligible")) for obs in all_observations),
        "live_admission_rate": (
            sum(b(obs.row.get("eligible")) for obs in all_observations) / len(score_candidates)
            if score_candidates else 0.0
        ),
        "actual_order_attempts": sum(
            obs.row.get("order_attempt_status") not in {"", "NOT_ATTEMPTED"} for obs in all_observations
        ),
        "top_rejecting_gate": top_gate,
        "top_rejecting_gate_count": top_count,
        "top_rejecting_gate_percent": top_count / len(rejected) if rejected else 0.0,
        "median_score_of_rejected": median(obs.admission_score for obs in rejected),
        "median_remaining_r": median(f(obs.row.get("reward_r")) for obs in rejected),
        "median_spread_atr": median(f(obs.row.get("spread_to_m5_atr_percent")) for obs in rejected),
        "score_qualified_opposing_structure_found": sum(
            obs.admission.get("opposing_structure") == "true" for obs in score_candidates
        ),
        "rr_reject_with_opposing_structure": sum(
            obs.reason in ROOM_REASONS
            and obs.admission.get("opposing_structure") == "true" for obs in score_candidates
        ),
        "rr_reject_without_opposing_structure": sum(
            obs.reason in ROOM_REASONS
            and obs.admission.get("opposing_structure") != "true" for obs in score_candidates
        ),
        "score_qualified_rejection_distribution": dict(rejection.most_common()),
        "shadow_eligible_by_gate_ablation": ablations,
        "parameter_sensitivity": sensitivity,
        "session_spread_atr_metrics": sessions,
        "asset_class_spread_atr_metrics": classes,
        "post_decision_observation_outcomes": outcome_breakdown(complete),
        "post_decision_unique_episode_outcomes": outcome_breakdown(anchor_complete),
        "rr_threshold_episode_sensitivity": threshold_episode_sensitivity,
        "london_rejection_episode_groups": london_rejection_groups,
        "requested_gate_counts": {
            "TOTAL_EVALUATIONS": len(all_observations),
            "SCORE_QUALIFIED": len(score_candidates),
            "LIVE_ELIGIBLE": sum(b(obs.row.get("eligible")) for obs in all_observations),
            "ACTUAL_TRADES": sum(
                obs.row.get("order_attempt_status") not in {"", "NOT_ATTEMPTED"}
                for obs in all_observations
            ),
            "REWARD_ROOM_REJECTS": sum(rejection.get(reason, 0) for reason in ROOM_REASONS),
            "OPPOSING_STRUCTURE_REJECTS": sum(
                obs.reason in ROOM_REASONS
                and obs.admission.get("opposing_structure") == "true" for obs in score_candidates
            ),
            "WIDE_STOP_ONLY_REJECTS": sum(
                obs.reason in ROOM_REASONS
                and obs.admission.get("opposing_structure") != "true" for obs in score_candidates
            ),
            "SPREAD_REJECTS": rejection.get("HIGH_SPREAD_RELATIVE_TO_M5_ATR", 0)
                + rejection.get("ABNORMAL_SPREAD", 0),
            "M5_M15_CONFLICT_REJECTS": rejection.get("M5_M15_DIRECTIONAL_CONFLICT", 0),
            "EXTENSION_REJECTS": rejection.get("MOVE_EXHAUSTED_OR_LATE_CHASE", 0)
                + rejection.get("LATE_ENTRY_M5_IMPULSE_EXTENSION_EXCEEDED", 0)
                + rejection.get("EXHAUSTED_BREAKOUT_EXTENSION_EXCEEDED", 0),
            "DRIFT_REJECTS": rejection.get("LATE_ENTRY_SIGNAL_DRIFT_EXCEEDED", 0),
        },
        "complete_60m_observations": len(complete),
        "complete_60m_unique_episodes": len(anchor_complete),
        "assessment": assessment,
        "assessment_constraint": (
            "MFE is diagnostic only. CONFIRMED_OVER_FILTERING requires manual structural-entry review "
            "and sufficient liquid-session evidence."
        ),
        "runtime": runtime,
        "instrumentation_gaps": [
            "V5 does not record the selected opposing swing timeframe or creation timestamp.",
            "V5 does not record tick value or a proposed volume for rejected candidates, so exact USD costs are unavailable.",
            "V5 records M5/M15 confirmation booleans but not the underlying signed trend values/context labels.",
            "Exact opposing level is inferable only when actual room, rather than the unopposed ATR cap, limits available_move.",
        ],
        "implementation_review": {
            "opposing_direction": "PASS: BUY selects completed swing highs strictly above entry; SELL selects completed swing lows strictly below entry.",
            "spread_atr_units": "PASS: raw spread and completed-M5 ATR are both price distances; the ratio is dimensionless before percentage scaling.",
            "cost_subtraction": "PASS: expected_net_move subtracts expected_cost_move once; reward_r divides that net move by stop distance. Cost also affects the independent quality score, which is calibration rather than duplicate arithmetic subtraction.",
            "cross_asset_normalization": "PARTIAL: price-unit and point/tick reporting are internally consistent; exact rejected-candidate USD values need tick value and proposed volume instrumentation.",
            "structure_relevance": "OPEN: V5 lacks selected swing timeframe and creation time, so micro-swing/staleness claims cannot yet be proved from the immutable feed.",
        },
    }


def _group(items: Iterable[Any], key) -> dict[Any, list[Any]]:
    result: dict[Any, list[Any]] = defaultdict(list)
    for item in items:
        result[key(item)].append(item)
    return result


def pct(value: float | None) -> str:
    return "NA" if value is None else f"{100.0 * value:.2f}%"


def report_markdown(summary: dict[str, Any], title: str) -> str:
    runtime = summary.get("runtime", {})
    lines = [
        f"# {title}",
        "",
        f"Generated: {summary['generated_utc']}",
        "",
        "`SHADOW_COUNTERFACTUAL_ONLY_NO_ORDER_PATH` / `POST_DECISION_RESEARCH_ONLY`",
        "",
        "## Current verdict",
        "",
        f"**{summary['assessment']}**",
        "",
        summary["assessment_constraint"],
        "",
        "## Objective warning metrics",
        "",
        f"- SCORE_QUALIFIED_COUNT: {summary['score_qualified_count']}",
        f"- LIVE_ELIGIBLE_COUNT: {summary['live_eligible_count']}",
        f"- LIVE_ADMISSION_RATE: {pct(summary['live_admission_rate'])}",
        f"- ACTUAL_ORDER_ATTEMPTS: {summary['actual_order_attempts']}",
        f"- TOP_REJECTING_GATE: {summary['top_rejecting_gate']}",
        f"- TOP_REJECTING_GATE_PERCENT: {pct(summary['top_rejecting_gate_percent'])}",
        f"- MEDIAN_SCORE_OF_REJECTED: {summary['median_score_of_rejected']}",
        f"- MEDIAN_REMAINING_R: {summary['median_remaining_r']}",
        f"- MEDIAN_SPREAD_ATR: {summary['median_spread_atr']}",
        f"- SCORE_QUALIFIED_WITH_OPPOSING_STRUCTURE: {summary['score_qualified_opposing_structure_found']}",
        f"- RR_REJECT_WITH_OPPOSING_STRUCTURE: {summary['rr_reject_with_opposing_structure']}",
        f"- RR_REJECT_WITHOUT_OPPOSING_STRUCTURE: {summary['rr_reject_without_opposing_structure']}",
        "",
        "## Production runtime (read-only snapshot)",
        "",
        f"- Account: {runtime.get('login', 'NA')} / {runtime.get('server', 'NA')}",
        f"- Demo / real blocked: {runtime.get('account_mode_demo', 'NA')} / {runtime.get('real_accounts_blocked', 'NA')}",
        f"- Entry permission: {runtime.get('entry_permission', 'NA')}",
        f"- Scanner / autonomous / connected: {runtime.get('scanner_active', 'NA')} / {runtime.get('autonomous_entry', 'NA')} / {runtime.get('connected', 'NA')}",
        f"- Positions / orders: {runtime.get('positions', 'NA')} / {runtime.get('orders', 'NA')}",
        f"- Production parameters changed: {summary['production_parameters_changed']}",
        "",
        "## Score-qualified rejection distribution",
        "",
        "| Gate | Count |",
        "|---|---:|",
    ]
    lines.extend(f"| {gate} | {count} |" for gate, count in summary["score_qualified_rejection_distribution"].items())
    lines += ["", "## Requested current counters", ""]
    lines.extend(f"- {name}: {value}" for name, value in summary["requested_gate_counts"].items())
    lines += ["", "## One-gate ablation", "", "| Counterfactual | Eligible | Rejected | Unknown |", "|---|---:|---:|---:|"]
    for name, values in summary["shadow_eligible_by_gate_ablation"].items():
        lines.append(f"| {name} | {values['eligible']} | {values['rejected']} | {values['unknown']} |")
    lines += ["", "## Parameter sensitivity (shadow only)", "", "| Parameter | Value | Eligible | Rejected | Unknown |", "|---|---:|---:|---:|---:|"]
    for parameter, values_by_setting in summary["parameter_sensitivity"].items():
        for setting, values in values_by_setting.items():
            lines.append(
                f"| {parameter} | {setting} | {values['eligible']} | {values['rejected']} | {values['unknown']} |"
            )
    lines += [
        "", "## Deduplicated reward-room threshold outcomes", "",
        "The expectancy columns are 60-minute research proxies, capped at -1R after a theoretical stop; they are not a reconstruction of the production runner.", "",
        "| Min initial room | Observations | Episodes | Complete | >=0.5R | >=1R | >=1.5R | >=2R | Stop hit | Net expectancy | Gross expectancy | Cost R | False reject |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for threshold, result in summary["rr_threshold_episode_sensitivity"].items():
        values = result["all_sessions"]
        lines.append(
            f"| {threshold} | {result['admitted_observations']} | {values['admitted_episodes']} | "
            f"{values['complete_60m_episodes']} | {pct(values['mfe_ge_0_5r_rate'])} | "
            f"{pct(values['mfe_ge_1r_rate'])} | {pct(values['mfe_ge_1_5r_rate'])} | "
            f"{pct(values['mfe_ge_2r_rate'])} | {pct(values['theoretical_stop_hit_rate'])} | "
            f"{values['mean_60m_net_expectancy_r_proxy']} | {values['mean_60m_gross_expectancy_r_proxy']} | "
            f"{values['median_expected_cost_r']} | {pct(values['false_rejection_rate'])} |"
        )
    lines += [
        "", "## London rejected-episode outcomes", "",
        "| Group | Episodes | Complete | Median MFE R | Median MAE R | >=0.5R | >=1R | >=1.5R | >=2R | Stop hit |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for group, values in summary["london_rejection_episode_groups"].items():
        lines.append(
            f"| {group} | {values['admitted_episodes']} | {values['complete_60m_episodes']} | "
            f"{values['median_mfe_60m_r']} | {values['median_mae_60m_r']} | "
            f"{values['mfe_ge_0_5r']} | {values['mfe_ge_1r']} | {values['mfe_ge_1_5r']} | "
            f"{values['mfe_ge_2r']} | {values['theoretical_stop_hits']} |"
        )
    lines += ["", "## Spread/ATR by session", "", "| Session (SAST) | Evaluations | Score-qualified | Median % | P75 % | <=8% pass | High-spread rejects | Stale |", "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for session, values in summary["session_spread_atr_metrics"].items():
        lines.append(
            f"| {session} | {values['evaluations']} | {values['score_qualified']} | "
            f"{values['median_spread_atr_percent']} | {values['p75_spread_atr_percent']} | "
            f"{pct(values['spread_atr_gate_pass_percent'])} | {values['high_spread_primary_rejects']} | "
            f"{values['stale_tick_primary_rejects']} |"
        )
    lines += ["", "## Spread/ATR by asset class", "", "| Asset class | Evaluations | Median % | P75 % | <=8% pass | High-spread rejects |", "|---|---:|---:|---:|---:|---:|"]
    for asset, values in summary["asset_class_spread_atr_metrics"].items():
        lines.append(
            f"| {asset} | {values['evaluations']} | {values['median_spread_atr_percent']} | "
            f"{values['p75_spread_atr_percent']} | {pct(values['spread_atr_gate_pass_percent'])} | "
            f"{values['high_spread_primary_rejects']} |"
        )
    lines += [
        "",
        "## Post-decision outcomes (unique signal episodes, complete 60-minute windows)",
        "",
        "A later MFE is not treated as proof that a rejected trade was executable or profitable.",
        "",
        "| Initial rejecting gate | N | >=0.5R | >=1R | >=1.5R | >=2R | Failed before +0.5R |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for gate, values in summary["post_decision_unique_episode_outcomes"].items():
        lines.append(
            f"| {gate} | {values['n']} | {values['mfe_ge_0_5r']} | {values['mfe_ge_1r']} | "
            f"{values['mfe_ge_1_5r']} | {values['mfe_ge_2r']} | {values['failed_immediately']} |"
        )
    lines += ["", "## Instrumentation limits", ""]
    lines.extend(f"- {item}" for item in summary["instrumentation_gaps"])
    lines += [
        "",
        "The collector records these limits as missing evidence and does not fabricate swing ages, timeframes, or USD values.",
        "",
        "## Implementation review",
        "",
    ]
    lines.extend(f"- {key}: {value}" for key, value in summary["implementation_review"].items())
    lines += [
        "",
    ]
    return "\n".join(lines)


def freeze_checkpoint(report_dir: Path, summary: dict[str, Any], now_sast: datetime) -> None:
    day = now_sast.date().isoformat()
    thresholds = [
        ("checkpoint-a-london.md", datetime.strptime(day + " 14:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=SAST), "Checkpoint A — London session"),
        ("checkpoint-b-london-new-york.md", datetime.strptime(day + " 20:00:00", "%Y-%m-%d %H:%M:%S").replace(tzinfo=SAST), "Checkpoint B — London/New York overlap"),
    ]
    for filename, threshold, title in thresholds:
        path = report_dir / filename
        if now_sast >= threshold and not path.exists():
            atomic_text(path, report_markdown(summary, title))
            atomic_json(path.with_suffix(".json"), summary)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit-dir", type=Path, default=AUDIT_DIR)
    parser.add_argument("--report-dir", type=Path, default=REPORT_DIR)
    args = parser.parse_args()
    observations, paths = load_observations(args.audit_dir)
    if not observations:
        raise SystemExit("no complete V5 audit observations found")
    meaningful = [obs for obs in observations if obs.meaningful and not b(obs.row.get("eligible"))]
    score_candidates = [obs for obs in observations if obs.score_qualified]
    candidate_rows = [candidate_row(obs) for obs in meaningful]
    # Threshold sensitivity includes both previously rejected candidates and
    # observations that production admitted.  Keep the outcome vector aligned
    # with that same population; the old rejected-only vector silently shifted
    # post-decision labels onto the wrong observations after the first live
    # admission.
    outcomes = outcome_rows(observations, score_candidates)
    rejected_pairs = [
        (obs, outcome) for obs, outcome in zip(score_candidates, outcomes)
        if not b(obs.row.get("eligible"))
    ]
    probe_requests = structure_probe_requests(
        [obs for obs, _ in rejected_pairs],
        [outcome for _, outcome in rejected_pairs],
    )
    runtime = runtime_state(args.audit_dir)
    summary = make_summary(observations, candidate_rows, outcomes, paths, runtime)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    candidate_fields = list(candidate_rows[0]) if candidate_rows else ["schema"]
    outcome_fields = list(outcomes[0]) if outcomes else ["schema"]
    atomic_csv(args.report_dir / "shadow-candidates.csv", candidate_fields, candidate_rows)
    atomic_csv(args.report_dir / "post-decision-outcomes.csv", outcome_fields, outcomes)
    probe_dir = args.audit_dir.parent / "SolTradeFastMultiMarketV220Shadow"
    probe_fields = list(probe_requests[0]) if probe_requests else ["request_id"]
    atomic_csv(probe_dir / "structure-probe-requests.csv", probe_fields, probe_requests)
    atomic_json(args.report_dir / "latest.json", summary)
    atomic_text(args.report_dir / "latest.md", report_markdown(summary, "Fast Multi V2.200 shadow admission audit"))
    freeze_checkpoint(args.report_dir, summary, datetime.now(SAST))
    print(json.dumps({
        "assessment": summary["assessment"],
        "evaluations": summary["evaluations"],
        "score_qualified": summary["score_qualified_count"],
        "live_eligible": summary["live_eligible_count"],
        "report": str(args.report_dir / "latest.md"),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
