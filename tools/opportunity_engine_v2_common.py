#!/usr/bin/env python3
"""Causal raw-market primitives for OPPORTUNITY_ENGINE_V2.

No production score or production direction is accepted by this module.
Features use completed bid bars and entry-time executable bid/ask/cost only.
"""
from __future__ import annotations

import math
import statistics
from datetime import datetime, timezone
from typing import Any

FMT = "%Y.%m.%d %H:%M:%S"


def number(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def epoch(value: str) -> int:
    return int(datetime.strptime(value, FMT).replace(tzinfo=timezone.utc).timestamp())


def mean(values: list[float]) -> float:
    return statistics.fmean(values) if values else 0.0


def aggregate(bars: list[dict[str, float]], minutes: int, at: int) -> list[dict[str, float]]:
    size = minutes * 60
    result: list[dict[str, float]] = []
    for bar in bars:
        bucket = int(bar["epoch"]) // size * size
        if bucket + size > at:
            continue
        if not result or int(result[-1]["epoch"]) != bucket:
            result.append({"epoch": float(bucket), "open": bar["open"], "high": bar["high"],
                           "low": bar["low"], "close": bar["close"]})
        else:
            item = result[-1]
            item["high"] = max(item["high"], bar["high"])
            item["low"] = min(item["low"], bar["low"])
            item["close"] = bar["close"]
    return result


def atr(bars: list[dict[str, float]], count: int = 14) -> float:
    if len(bars) < count + 1:
        return 0.0
    values = []
    for index in range(len(bars) - count, len(bars)):
        current, prior = bars[index], bars[index - 1]
        values.append(max(current["high"] - current["low"], abs(current["high"] - prior["close"]),
                          abs(current["low"] - prior["close"])))
    return mean(values)


def efficiency(bars: list[dict[str, float]], count: int) -> float:
    sample = bars[-count:]
    if len(sample) < count:
        return 0.0
    path = sum(abs(sample[i]["close"] - sample[i - 1]["close"]) for i in range(1, len(sample)))
    return abs(sample[-1]["close"] - sample[0]["close"]) / max(path, 1e-12)


def trend(bars: list[dict[str, float]], fast: int, slow: int, scale: float) -> float:
    if len(bars) < slow or scale <= 0:
        return 0.0
    return (mean([x["close"] for x in bars[-fast:]]) - mean([x["close"] for x in bars[-slow:]])) / scale


def nearest_pivot(bars: list[dict[str, float]], entry: float, direction: int, lookback: int) -> float:
    sample = bars[-lookback:]
    candidates = []
    for index in range(1, len(sample) - 1):
        if direction > 0 and sample[index]["high"] >= sample[index - 1]["high"] and sample[index]["high"] >= sample[index + 1]["high"] and sample[index]["high"] > entry:
            candidates.append(sample[index]["high"])
        if direction < 0 and sample[index]["low"] <= sample[index - 1]["low"] and sample[index]["low"] <= sample[index + 1]["low"] and sample[index]["low"] < entry:
            candidates.append(sample[index]["low"])
    if not candidates:
        return 0.0
    return min(candidates) if direction > 0 else max(candidates)


def latest_impulse(bars: list[dict[str, float]], scale: float) -> tuple[int, float, float]:
    """Return direction, causal origin and age of the latest completed M5 impulse."""
    last_epoch = int(bars[-1]["epoch"])
    for bar in reversed(bars[-30:]):
        body = bar["close"] - bar["open"]
        span = bar["high"] - bar["low"]
        if abs(body) >= .70 * scale and span >= .90 * scale:
            direction = 1 if body > 0 else -1
            origin = bar["low"] if direction > 0 else bar["high"]
            age = max(0.0, (last_epoch - int(bar["epoch"])) / 300.0)
            return direction, origin, age
    fallback = bars[-7]
    direction = 1 if bars[-1]["close"] >= fallback["close"] else -1
    origin = fallback["low"] if direction > 0 else fallback["high"]
    return direction, origin, 6.0


def breakout_retest(bars: list[dict[str, float]], scale: float, direction: int) -> tuple[bool, float]:
    """Detect a completed breakout followed by a completed causal retest."""
    current = bars[-1]
    for index in range(len(bars) - 2, max(20, len(bars) - 10), -1):
        prior = bars[index - 20:index]
        if len(prior) < 20:
            continue
        level = max(x["high"] for x in prior) if direction > 0 else min(x["low"] for x in prior)
        breakout = bars[index]["close"] > level if direction > 0 else bars[index]["close"] < level
        held = (current["low"] <= level + .25 * scale and current["close"] >= level) if direction > 0 else (
            current["high"] >= level - .25 * scale and current["close"] <= level)
        if breakout and held:
            return True, level
    return False, 0.0


def structural_stop(entry: float, direction: int, spread: float, m5: list[dict[str, float]],
                    m15: list[dict[str, float]], a5: float, a15: float,
                    volatility_expansion: float) -> tuple[float, float, float]:
    """Mirror production M5/M15 invalidation and volatility floors."""
    if direction > 0:
        m5_swing = min(x["low"] for x in m5[-8:])
        m15_swing = min(x["low"] for x in m15[-6:])
        invalidation = max(m5_swing, m15_swing)
        raw_distance = entry - invalidation
    else:
        m5_swing = max(x["high"] for x in m5[-8:])
        m15_swing = max(x["high"] for x in m15[-6:])
        invalidation = min(m5_swing, m15_swing)
        raw_distance = invalidation - entry
    expansion_buffer = (0.18 + 0.22 * min(1.5, max(0.0, volatility_expansion - 1.0))) * a5 + 2.0 * spread
    distance = max(raw_distance + expansion_buffer, 1.15 * a5, 0.55 * a15)
    stop = entry - direction * distance
    return stop, distance, invalidation


def event_and_features(completed_m1: list[dict[str, float]], at: int, bid: float, ask: float,
                       expected_cost_move: float) -> tuple[str, int, dict[str, float]] | None:
    if len(completed_m1) < 960:
        return None
    m1 = completed_m1[-1800:]
    m5, m15, h1 = aggregate(m1, 5, at), aggregate(m1, 15, at), aggregate(m1, 60, at)
    if len(m5) < 45 or len(m15) < 30 or len(h1) < 16:
        return None
    a1, a5, a15 = atr(m1), atr(m5), atr(m15)
    if min(a1, a5, a15) <= 0:
        return None
    last1, prior1, last5 = m1[-1], m1[-2], m5[-1]
    prior_high, prior_low = max(x["high"] for x in m5[-21:-1]), min(x["low"] for x in m5[-21:-1])
    breakout_up, breakout_down = last5["close"] > prior_high, last5["close"] < prior_low
    failed_up = last5["high"] > prior_high and last5["close"] < prior_high
    failed_down = last5["low"] < prior_low and last5["close"] > prior_low
    body5 = abs(last5["close"] - last5["open"])
    upper5 = last5["high"] - max(last5["open"], last5["close"])
    lower5 = min(last5["open"], last5["close"]) - last5["low"]
    t1, t5, t15, t60 = (trend(m1, 8, 30, a1), trend(m5, 8, 30, a5),
                         trend(m15, 6, 24, a15), trend(h1, 4, 16, atr(h1)))
    vol = mean([x["high"] - x["low"] for x in m5[-4:]]) / max(mean([x["high"] - x["low"] for x in m5[-16:-4]]), 1e-12)
    recent_momentum = (m5[-1]["close"] - m5[-4]["close"]) / a5
    prior_momentum = (m5[-4]["close"] - m5[-7]["close"]) / a5
    acceleration = recent_momentum - prior_momentum
    e5 = efficiency(m5, 18)
    prior_e5 = efficiency(m5[:-1], 18)
    m1_body = last1["close"] - last1["open"]
    m1_range = max(last1["high"] - last1["low"], 1e-12)
    m1_strength = m1_body / a1
    range_now = mean([x["high"] - x["low"] for x in m1[-4:]])
    range_prior = mean([x["high"] - x["low"] for x in m1[-24:-4]])
    compression = range_prior > 0 and range_now / range_prior < 0.72
    fresh_expansion = abs(m1_body) > 0.75 * a1 and m1_range > 1.25 * a1
    rejection_up = lower5 > max(body5, 0.18 * a5) and last5["close"] > last5["open"]
    rejection_down = upper5 > max(body5, 0.18 * a5) and last5["close"] < last5["open"]
    hh = max(x["high"] for x in m5[-5:]) > max(x["high"] for x in m5[-10:-5])
    hl = min(x["low"] for x in m5[-5:]) > min(x["low"] for x in m5[-10:-5])
    lh = max(x["high"] for x in m5[-5:]) < max(x["high"] for x in m5[-10:-5])
    ll = min(x["low"] for x in m5[-5:]) < min(x["low"] for x in m5[-10:-5])
    pullback_up = t5 > .15 and prior1["close"] < prior1["open"] and m1_body > 0 and last1["close"] > prior1["high"]
    pullback_down = t5 < -.15 and prior1["close"] > prior1["open"] and m1_body < 0 and last1["close"] < prior1["low"]
    retest_up, retest_up_level = breakout_retest(m5, a5, 1)
    retest_down, retest_down_level = breakout_retest(m5, a5, -1)
    impulse_direction, impulse_origin, impulse_age = latest_impulse(m5, a5)
    impulse_displacement = (last5["close"] - impulse_origin) / a5
    pressure_m1 = sum(x["close"] - x["open"] for x in m1[-6:]) / a1

    event = None
    if failed_up or failed_down:
        event = ("FAILED_BREAKOUT", -1 if failed_up else 1)
    elif breakout_up or breakout_down:
        event = (("RANGE_TO_DIRECTION" if prior_e5 < .25 else "COMPLETED_BREAKOUT"), 1 if breakout_up else -1)
    elif (rejection_up and t5 < -.15) or (rejection_down and t5 > .15):
        event = ("STRUCTURAL_REVERSAL", 1 if rejection_up else -1)
    elif retest_up or retest_down:
        event = ("BREAKOUT_RETEST", 1 if retest_up else -1)
    elif vol > 1.55 and abs((m5[-1]["close"] - m5[-7]["close"]) / a5) > 2.8 and (upper5 > body5 or lower5 > body5):
        event = ("EXHAUSTION_REJECTION", -1 if upper5 > lower5 else 1)
    elif pullback_up or pullback_down:
        event = ("PULLBACK_CONTINUATION", 1 if pullback_up else -1)
    elif compression and fresh_expansion:
        event = ("COMPRESSION_EXPANSION", 1 if m1_body > 0 else -1)
    elif (hh and hl and m1_body > 0 and t5 > .15) or (lh and ll and m1_body < 0 and t5 < -.15):
        event = ("TREND_RESUMPTION", 1 if m1_body > 0 else -1)
    elif fresh_expansion:
        event = ("FRESH_DIRECTIONAL_EXPANSION", 1 if m1_body > 0 else -1)
    if event is None:
        return None

    spread = max(ask - bid, 0.0)
    nonspread = max(0.0, expected_cost_move - spread)
    long_stop, long_distance, long_invalidation = structural_stop(ask, 1, spread, m5, m15, a5, a15, vol)
    short_stop, short_distance, short_invalidation = structural_stop(bid, -1, spread, m5, m15, a5, a15, vol)
    long_pivots = [nearest_pivot(m5, ask, 1, 34), nearest_pivot(m15, ask, 1, 42), nearest_pivot(h1, ask, 1, 38)]
    short_pivots = [nearest_pivot(m5, bid, -1, 34), nearest_pivot(m15, bid, -1, 42), nearest_pivot(h1, bid, -1, 38)]
    long_rooms = [x - ask for x in long_pivots if x > ask]
    short_rooms = [bid - x for x in short_pivots if 0 < x < bid]
    projected = max(2.20 * a5, 0.75 * a15)
    long_room, short_room = min(long_rooms, default=projected), min(short_rooms, default=projected)
    recent_high, recent_low = max(x["high"] for x in m5[-20:]), min(x["low"] for x in m5[-20:])
    session = [x for x in m1 if int(x["epoch"]) // 86400 == at // 86400]
    previous = [x for x in m1 if int(x["epoch"]) // 86400 == at // 86400 - 1]
    session_high = max((x["high"] for x in session), default=ask)
    session_low = min((x["low"] for x in session), default=bid)
    prev_high = max((x["high"] for x in previous), default=recent_high)
    prev_low = min((x["low"] for x in previous), default=recent_low)
    up_streak = down_streak = 0
    for bar in reversed(m1):
        if bar["close"] > bar["open"] and down_streak == 0: up_streak += 1
        elif bar["close"] < bar["open"] and up_streak == 0: down_streak += 1
        else: break
    latest_range = max(recent_high - recent_low, 1e-12)
    pullback_depth_long = (recent_high - bid) / latest_range
    pullback_depth_short = (ask - recent_low) / latest_range
    micro_high = max(x["high"] for x in m1[-6:])
    micro_low = min(x["low"] for x in m1[-6:])
    micro_range = max(micro_high - micro_low, 1e-12)
    pullback_progress_long = (last1["close"] - micro_low) / micro_range
    pullback_progress_short = (micro_high - last1["close"]) / micro_range
    features = {
        "event_direction": float(event[1]), "trend_m1": t1, "trend_m5": t5, "trend_m15": t15, "trend_h1": t60,
        "path_efficiency_m5": e5, "path_efficiency_change": e5 - prior_e5,
        "impulse_m5_atr": (m5[-1]["close"] - m5[-7]["close"]) / a5,
        "latest_impulse_direction": float(impulse_direction), "impulse_origin": impulse_origin,
        "impulse_age_m5": impulse_age, "impulse_displacement_m5_atr": impulse_displacement,
        "recent_momentum_m5_atr": recent_momentum,
        "acceleration_m5_atr": acceleration, "volatility_expansion_m5": vol,
        "m1_body_atr": m1_strength, "m1_body_fraction": abs(m1_body) / m1_range,
        "m1_upper_wick_body": (last1["high"] - max(last1["open"], last1["close"])) / max(abs(m1_body), .05 * a1),
        "m1_lower_wick_body": (min(last1["open"], last1["close"]) - last1["low"]) / max(abs(m1_body), .05 * a1),
        "up_close_streak": float(up_streak), "down_close_streak": float(down_streak),
        "breakout_up": float(breakout_up), "breakout_down": float(breakout_down),
        "failed_breakout_up": float(failed_up), "failed_breakout_down": float(failed_down),
        "bull_structure": float(hh and hl), "bear_structure": float(lh and ll),
        "pullback_resume_up": float(pullback_up), "pullback_resume_down": float(pullback_down),
        "pullback_depth_long": pullback_depth_long, "pullback_depth_short": pullback_depth_short,
        "pullback_progress_long": pullback_progress_long, "pullback_progress_short": pullback_progress_short,
        "breakout_retest_up": float(retest_up), "breakout_retest_down": float(retest_down),
        "breakout_retest_up_level": retest_up_level, "breakout_retest_down_level": retest_down_level,
        "rejection_up": float(rejection_up), "rejection_down": float(rejection_down),
        "opposing_pressure_signed_m1": pressure_m1,
        "range_location": (bid - recent_low) / latest_range,
        "distance_high_m5_atr": (recent_high - ask) / a5, "distance_low_m5_atr": (bid - recent_low) / a5,
        "session_location": (bid - session_low) / max(session_high - session_low, 1e-12),
        "previous_day_location": (bid - prev_low) / max(prev_high - prev_low, 1e-12),
        "long_room_r": max(0.0, long_room - expected_cost_move) / max(long_distance, 1e-12),
        "short_room_r": max(0.0, short_room - expected_cost_move) / max(short_distance, 1e-12),
        "long_stop_m1_atr": long_distance / a1, "short_stop_m1_atr": short_distance / a1,
        "long_stop_m5_atr": long_distance / a5, "short_stop_m5_atr": short_distance / a5,
        "long_invalidation_distance_m5_atr": (ask - long_invalidation) / a5,
        "short_invalidation_distance_m5_atr": (short_invalidation - bid) / a5,
        "spread_m1_atr": spread / a1, "cost_long_r": expected_cost_move / max(long_distance + nonspread, 1e-12),
        "cost_short_r": expected_cost_move / max(short_distance + nonspread, 1e-12),
        "compression_ratio_m1": range_now / max(range_prior, 1e-12),
    }
    geometry = {"long_entry": ask, "short_entry": bid, "long_stop": long_stop, "short_stop": short_stop,
                "long_invalidation": long_invalidation, "short_invalidation": short_invalidation,
                "long_risk": long_distance + nonspread, "short_risk": short_distance + nonspread,
                "nonspread_cost": nonspread, "spread": spread, "expected_cost_move": expected_cost_move}
    features.update(geometry)
    return event[0], event[1], features


FEATURES = (
    "event_direction", "trend_m1", "trend_m5", "trend_m15", "trend_h1", "path_efficiency_m5",
    "path_efficiency_change", "impulse_m5_atr", "latest_impulse_direction", "impulse_origin",
    "impulse_age_m5", "impulse_displacement_m5_atr", "recent_momentum_m5_atr",
    "acceleration_m5_atr", "volatility_expansion_m5", "m1_body_atr", "m1_body_fraction",
    "m1_upper_wick_body", "m1_lower_wick_body", "up_close_streak", "down_close_streak",
    "breakout_up", "breakout_down", "failed_breakout_up", "failed_breakout_down", "bull_structure",
    "bear_structure", "pullback_resume_up", "pullback_resume_down", "pullback_depth_long",
    "pullback_depth_short", "pullback_progress_long", "pullback_progress_short", "breakout_retest_up",
    "breakout_retest_down", "breakout_retest_up_level", "breakout_retest_down_level",
    "rejection_up", "rejection_down", "opposing_pressure_signed_m1",
    "range_location", "distance_high_m5_atr", "distance_low_m5_atr", "session_location",
    "previous_day_location", "long_room_r", "short_room_r", "long_stop_m1_atr", "short_stop_m1_atr",
    "long_stop_m5_atr", "short_stop_m5_atr", "long_invalidation_distance_m5_atr",
    "short_invalidation_distance_m5_atr", "spread_m1_atr", "cost_long_r", "cost_short_r",
    "compression_ratio_m1",
)
