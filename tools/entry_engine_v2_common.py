#!/usr/bin/env python3
"""Shared, deterministic ENTRY_ENGINE_V2 research primitives.

The module contains no broker or order interface.  Future prices are accepted
only by the dataset builder; feature extraction reads completed bars and the
entry-time evidence row.
"""
from __future__ import annotations

import math
import statistics
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable

import numpy as np

FMT = "%Y.%m.%d %H:%M:%S"


def number(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def kv(value: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in (value or "").split(";"):
        if "=" in item:
            key, val = item.split("=", 1)
            result[key] = val
    return result


def epoch(value: str) -> int:
    return int(datetime.strptime(value, FMT).replace(tzinfo=timezone.utc).timestamp())


def direction_state(state: str, direction: int) -> float:
    state = (state or "").upper()
    if "BULL" in state:
        return float(direction)
    if "BEAR" in state:
        return float(-direction)
    return 0.0


def mean(values: Iterable[float]) -> float:
    data = list(values)
    return statistics.fmean(data) if data else 0.0


def aggregate_bars(m1: list[dict[str, float]], minutes: int) -> list[dict[str, float]]:
    result: list[dict[str, float]] = []
    size = minutes * 60
    for bar in m1:
        bucket = int(bar["epoch"]) // size * size
        if not result or int(result[-1]["epoch"]) != bucket:
            result.append({"epoch": float(bucket), "open": bar["open"], "high": bar["high"],
                           "low": bar["low"], "close": bar["close"]})
        else:
            current = result[-1]
            current["high"] = max(current["high"], bar["high"])
            current["low"] = min(current["low"], bar["low"])
            current["close"] = bar["close"]
    return result


def atr14(bars: list[dict[str, float]]) -> float:
    if len(bars) < 15:
        return 0.0
    values = []
    for index in range(len(bars) - 14, len(bars)):
        bar, prior = bars[index], bars[index - 1]
        values.append(max(bar["high"] - bar["low"], abs(bar["high"] - prior["close"]),
                          abs(bar["low"] - prior["close"])))
    return mean(values)


def _prior_close(bars: list[dict[str, float]], seconds: int) -> float:
    target = bars[-1]["epoch"] + 60 - seconds
    earlier = [bar for bar in bars if bar["epoch"] + 60 <= target]
    return earlier[-1]["close"] if earlier else bars[0]["close"]


def bar_features(m1: list[dict[str, float]], at_utc: str, entry: float, direction: int) -> dict[str, float]:
    """Derive causal location/timing features from bars completed before entry."""
    at = epoch(at_utc)
    completed = [bar for bar in m1 if bar["epoch"] + 60 <= at]
    if len(completed) < 120:
        raise ValueError("insufficient completed M1 history")
    completed = completed[-600:]
    # A completed M1 bar may belong to the still-forming M5/M15 bucket.  Higher
    # timeframe features must exclude that partial bucket as well.
    m5 = [bar for bar in aggregate_bars(completed, 5) if bar["epoch"] + 300 <= at]
    m15 = [bar for bar in aggregate_bars(completed, 15) if bar["epoch"] + 900 <= at]
    if len(m5) < 25 or len(m15) < 15:
        raise ValueError("insufficient completed higher-timeframe history")
    a1, a5 = atr14(completed), atr14(m5)
    if a1 <= 0 or a5 <= 0:
        raise ValueError("invalid ATR")

    # Most recent confirmed opposite M5 pivot is the causal impulse origin.
    origin_bar = None
    for index in range(len(m5) - 3, max(1, len(m5) - 60), -1):
        bar = m5[index]
        neighbours = m5[index - 2:index] + m5[index + 1:index + 3]
        pivot = bar["low"] < min(x["low"] for x in neighbours) if direction > 0 else bar["high"] > max(x["high"] for x in neighbours)
        if pivot:
            origin_bar = bar
            break
    if origin_bar is None:
        window = m5[-40:]
        origin_bar = min(window, key=lambda x: x["low"]) if direction > 0 else max(window, key=lambda x: x["high"])
    origin = origin_bar["low"] if direction > 0 else origin_bar["high"]
    leg = [bar for bar in m5 if bar["epoch"] >= origin_bar["epoch"]]
    favorable = max(x["high"] for x in leg) if direction > 0 else min(x["low"] for x in leg)

    recent = m5[-20:]
    high, low = max(x["high"] for x in recent), min(x["low"] for x in recent)
    range_location = ((entry - low) / (high - low) if direction > 0 else (high - entry) / (high - low)) if high > low else 0.5

    last, prior = completed[-1], completed[-2]
    prior_against = direction * (prior["close"] - prior["open"]) < 0
    reclaim = prior["high"] if direction > 0 else prior["low"]
    resumed = prior_against and direction * (last["close"] - last["open"]) > 0 and direction * (last["close"] - reclaim) > 0
    pullback_depth = (prior["high"] - prior["low"]) / a1 if prior_against else 0.0
    streak = 0
    for bar in reversed(completed):
        if direction * (bar["close"] - bar["open"]) <= 0:
            break
        streak += 1
    last_range = max(last["high"] - last["low"], 1e-12)
    opposing_wick = last["high"] - max(last["open"], last["close"]) if direction > 0 else min(last["open"], last["close"]) - last["low"]
    pullback_window = completed[-10:]
    pullback_extreme = min(x["low"] for x in pullback_window) if direction > 0 else max(x["high"] for x in pullback_window)
    pullback_distance = direction * (last["close"] - pullback_extreme) / a1
    last_against = direction * (last["close"] - last["open"]) < 0
    pullback_expanding = last_against and prior_against and (last["high"]-last["low"]) > (prior["high"]-prior["low"])

    ranges_recent = [x["high"] - x["low"] for x in completed[-4:]]
    ranges_prior = [x["high"] - x["low"] for x in completed[-16:-4]]
    volatility = mean(ranges_recent) / max(mean(ranges_prior), 1e-12)
    move5 = direction * (completed[-1]["close"] - _prior_close(completed, 5 * 60)) / a1
    prev_move5 = direction * (_prior_close(completed, 5 * 60) - _prior_close(completed, 10 * 60)) / a1
    move15_m5 = direction * (m5[-1]["close"] - _prior_close(m5, 15 * 60)) / a5
    prev15_m5 = direction * (_prior_close(m5, 15 * 60) - _prior_close(m5, 30 * 60)) / a5

    # Latest completed M5 close beyond the prior 20-bar range is a causal break.
    break_epoch = None
    for index in range(max(20, len(m5) - 60), len(m5)):
        prior_bars = m5[index - 20:index]
        anchor = max(x["high"] for x in prior_bars) if direction > 0 else min(x["low"] for x in prior_bars)
        if direction * (m5[index]["close"] - anchor) > 0:
            break_epoch = int(m5[index]["epoch"] + 300)

    return {
        "impulse_age_minutes": max(0.0, (at - origin_bar["epoch"]) / 60.0),
        "impulse_age_m5_bars": max(0.0, (at - origin_bar["epoch"]) / 300.0),
        "seconds_since_structural_break": float(at - break_epoch) if break_epoch is not None else 8 * 3600.0,
        "impulse_distance_m5_atr": direction * (entry - origin) / a5,
        "range_location": range_location,
        "distance_from_favorable_extreme_m5_atr": direction * (favorable - entry) / a5,
        "m1_displacement_5m_atr": move5,
        "m1_acceleration_atr": move5 - prev_move5,
        "m1_volatility_expansion": volatility,
        "m5_displacement_15m_atr": move15_m5,
        "m5_acceleration_atr": move15_m5 - prev15_m5,
        "pullback_depth_m1_atr": pullback_depth,
        "pullback_resumption": 1.0 if resumed else 0.0,
        "pullback_expanding": 1.0 if pullback_expanding else 0.0,
        "distance_from_pullback_extreme_m1_atr": pullback_distance,
        "m1_directional_close_streak": float(streak),
        "m1_body_fraction": abs(last["close"]-last["open"]) / last_range,
        "m1_opposing_wick_body_ratio": opposing_wick / max(abs(last["close"]-last["open"]), .05*a1),
        "m1_atr": a1,
        "m5_atr": a5,
    }


def evidence_features(row: dict[str, str], bars: list[dict[str, float]], scan_context: dict[str, float] | None = None) -> dict[str, float]:
    direction = 1 if row["direction"] == "BUY" else -1
    entry, stop = number(row["entry"]), number(row["stop"])
    risk = abs(entry - stop)
    proposed = kv(row["buy_case"] if direction > 0 else row["sell_case"])
    opposing = kv(row["sell_case"] if direction > 0 else row["buy_case"])
    no_trade, detail, levels = kv(row["no_trade_case"]), kv(row["detail"]), kv(row["levels"])
    session, previous = kv(row["session"]), kv(row["previous_session"])
    bf = bar_features(bars, row["utc"], entry, direction)

    def favorable_room(data: dict[str, str]) -> float:
        target = number(data.get("high")) if direction > 0 else number(data.get("low"))
        return direction * (target - entry) / max(risk, 1e-12)

    day_target = number(levels.get("previous_day_high")) if direction > 0 else number(levels.get("previous_day_low"))
    mtf = [direction_state(row.get(name, ""), direction) for name in ("m1", "m5", "m15", "h1")]
    result = {
        **bf,
        "proposed_score": number(proposed.get("score")),
        "opposing_score": number(opposing.get("score")),
        "score_dominance": number(proposed.get("score")) - number(opposing.get("score")),
        "no_trade_score": number(no_trade.get("score")),
        "admission_score": number(no_trade.get("admission_score"), number(detail.get("admission_score"))),
        "m1_direction": mtf[0],
        "m5_direction": mtf[1],
        "m15_direction": mtf[2],
        "h1_direction": mtf[3],
        "mtf_alignment_fraction": sum(1 for value in mtf if value > 0) / 4.0,
        "mtf_opposition_fraction": sum(1 for value in mtf if value < 0) / 4.0,
        "regime_range": 1.0 if "RANGE" in row.get("regime", "") else 0.0,
        "regime_transition": 1.0 if "TRANSITION" in row.get("regime", "") else 0.0,
        "remaining_room_r": number(row.get("expected_net_move")) / max(risk, 1e-12),
        "session_room_r": favorable_room(session),
        "previous_session_room_r": favorable_room(previous),
        "previous_day_room_r": direction * (day_target - entry) / max(risk, 1e-12),
        "stop_m5_atr": risk / max(bf["m5_atr"], 1e-12),
        "stop_m1_atr": risk / max(bf["m1_atr"], 1e-12),
        "m5_favorable_room_r": direction * ((number(levels.get("m5_high")) if direction > 0 else number(levels.get("m5_low"))) - entry) / max(risk, 1e-12),
        "m15_favorable_room_r": direction * (number(levels.get("m15_swing")) - entry) / max(risk, 1e-12),
        "confirmation_move_m5_atr": number(detail.get("confirmation_move_m5_atr")),
        "confirmation_consumed": number(detail.get("confirmation_opportunity_consumed")),
        "cost_r": number(row.get("expected_cost_move")) / max(risk + max(0.0, number(row.get("expected_cost_move")) - number(row.get("spread"))), 1e-12),
        "spread_m5_atr_percent": number(no_trade.get("spread_atr")),
        "impulse_extension_m5_atr": number(detail.get("impulse_extension_m5_atr")),
        "breakout_extension_m5_atr": number(detail.get("breakout_extension_m5_atr")),
        "proposed_breakout": 1.0 if proposed.get("breakout", "false").lower() == "true" else 0.0,
        "opposing_breakout": 1.0 if opposing.get("breakout", "false").lower() == "true" else 0.0,
        "stop_inside_m1_noise": 1.0 if risk < bf["m1_atr"] else 0.0,
        "expected_move_consumed_fraction": number(detail.get("confirmation_opportunity_consumed")),
        "broker_execution_cost_room_fraction": number(row.get("expected_cost_move")) / max(number(row.get("available_move")), 1e-12),
        "cost_multiple": number(no_trade.get("cost_multiple"), number(detail.get("net_cost_gate"))),
        "spread_median_ratio": number(detail.get("spread_median_ratio")),
        "persistence_scans": number(detail.get("persistence_scans")),
        "persistence_seconds": number(detail.get("persistence_seconds")),
        "entry_drift_m5_atr": number(detail.get("entry_drift_m5_atr")),
        **(scan_context or {"proposed_score_rate_5m": 0.0, "opposing_score_rate_5m": 0.0}),
    }
    return result


FEATURES = (
    "impulse_age_minutes", "impulse_age_m5_bars", "seconds_since_structural_break", "impulse_distance_m5_atr",
    "range_location", "distance_from_favorable_extreme_m5_atr", "m1_displacement_5m_atr",
    "m1_acceleration_atr", "m1_volatility_expansion", "m5_displacement_15m_atr",
    "m5_acceleration_atr", "pullback_depth_m1_atr", "pullback_resumption",
    "pullback_expanding", "distance_from_pullback_extreme_m1_atr", "m1_directional_close_streak",
    "m1_body_fraction", "m1_opposing_wick_body_ratio",
    "score_dominance", "opposing_score", "m1_direction", "m5_direction", "m15_direction", "h1_direction",
    "mtf_alignment_fraction", "mtf_opposition_fraction",
    "regime_range", "regime_transition", "remaining_room_r", "session_room_r",
    "previous_day_room_r", "m5_favorable_room_r", "m15_favorable_room_r", "stop_m5_atr", "stop_m1_atr",
    "stop_inside_m1_noise", "confirmation_move_m5_atr", "cost_r", "spread_m5_atr_percent",
    "impulse_extension_m5_atr", "breakout_extension_m5_atr", "proposed_breakout", "opposing_breakout",
    "expected_move_consumed_fraction", "broker_execution_cost_room_fraction", "cost_multiple",
    "spread_median_ratio", "persistence_scans", "persistence_seconds", "entry_drift_m5_atr",
    "proposed_score_rate_5m", "opposing_score_rate_5m",
)


@dataclass
class LogisticModel:
    means: np.ndarray
    scales: np.ndarray
    weights: np.ndarray
    l2: float

    def probability(self, features: dict[str, float]) -> float:
        vector = np.asarray([features[name] for name in FEATURES], dtype=float)
        z = self.weights[0] + np.dot(self.weights[1:], (vector - self.means) / self.scales)
        z = max(-35.0, min(35.0, float(z)))
        return 1.0 / (1.0 + math.exp(-z))

    def payload(self) -> dict[str, Any]:
        return {"features": list(FEATURES), "means": dict(zip(FEATURES, self.means.tolist())),
                "scales": dict(zip(FEATURES, self.scales.tolist())), "intercept": float(self.weights[0]),
                "coefficients": dict(zip(FEATURES, self.weights[1:].tolist())), "l2": self.l2}


def fit_logistic(rows: list[dict[str, Any]], l2: float, iterations: int = 3500) -> LogisticModel:
    x = np.asarray([[number(row[name]) for name in FEATURES] for row in rows], dtype=float)
    y = np.asarray([1.0 if row["primary_label"] == "WIN_1R_BEFORE_STOP" else 0.0 for row in rows])
    means, scales = x.mean(axis=0), x.std(axis=0)
    scales[scales < 1e-9] = 1.0
    z = (x - means) / scales
    design = np.column_stack([np.ones(len(z)), z])
    weights = np.zeros(design.shape[1])
    # Deterministic full-batch gradient descent; regularize coefficients only.
    rate = 0.08
    for _ in range(iterations):
        scores = np.clip(design @ weights, -35, 35)
        predictions = 1.0 / (1.0 + np.exp(-scores))
        gradient = design.T @ (predictions - y) / len(y)
        gradient[1:] += l2 * weights[1:] / len(y)
        weights -= rate * gradient
    return LogisticModel(means, scales, weights, l2)
