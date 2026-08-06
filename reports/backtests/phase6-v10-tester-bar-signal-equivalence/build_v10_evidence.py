#!/usr/bin/env python3
"""Build Phase 6 V10 bar/signal equivalence evidence; never computes P&L."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


STAMP = "%Y.%m.%d %H:%M:%S"
ISO = "%Y-%m-%dT%H:%M:%S"
POINT = Decimal("0.00001")
CUTOFF = datetime(2025, 12, 24)
INDICATOR_TOLERANCE = 1e-12

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SOURCE_A = Path(os.path.expanduser(
    "~/.wine-fpmarkets/drive_c/v8/derived/SolTradePhase6V8DerivedH1.csv"
))
SOURCE_B = Path(os.path.expanduser(
    "~/.wine-fpmarkets/drive_c/users/tibule12/AppData/Roaming/MetaQuotes/"
    "Terminal/Common/Files/SolTrade/Phase6/V10/tester-runtime-h1-bars-v10.csv"
))


SEGMENTS = [
    {
        "id": 1,
        "warmup_start": "2025.01.02 00:00:00",
        "eligible_start": "2025.01.16 00:00:00",
        "end": "2025.02.05 00:00:00",
        "expected_eligible": 336,
    },
    {
        "id": 2,
        "warmup_start": "2025.02.05 01:00:00",
        "eligible_start": "2025.02.17 09:00:00",
        "end": "2025.03.07 23:00:00",
        "expected_eligible": 350,
    },
    {
        "id": 3,
        "warmup_start": "2025.03.10 01:00:00",
        "eligible_start": "2025.03.20 08:00:00",
        "end": "2025.08.06 16:00:00",
        "expected_eligible": 2384,
    },
    {
        "id": 4,
        "warmup_start": "2025.08.06 18:00:00",
        "eligible_start": "2025.08.19 02:00:00",
        "end": "2025.12.24 00:00:00",
        "expected_eligible": 2182,
    },
]


@dataclass(frozen=True)
class Bar:
    time: datetime
    open: float
    high: float
    low: float
    close: float
    tick_volume: int
    spread: float
    runtime_tick_count: int
    first_tick: str
    last_tick: str


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, STAMP)


def iso(value: datetime) -> str:
    return value.strftime(ISO)


def read_source_a() -> dict[datetime, Bar]:
    result = {}
    with SOURCE_A.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            time = parse_time(row["timestamp"])
            result[time] = Bar(
                time, float(row["bid_open"]), float(row["bid_high"]),
                float(row["bid_low"]), float(row["bid_close"]),
                int(row["tick_count"]), float(row["spread_points_close"]),
                int(row["tick_count"]), row["first_tick_timestamp"],
                row["last_tick_timestamp"],
            )
    return result


def read_source_b() -> dict[datetime, Bar]:
    result = {}
    with SOURCE_B.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            time = parse_time(row["timestamp"])
            if time >= CUTOFF:
                raise RuntimeError("post-cutoff bar found in Source B research export")
            result[time] = Bar(
                time, float(row["open"]), float(row["high"]),
                float(row["low"]), float(row["close"]),
                int(row["tick_volume"]), float(row["spread"]),
                int(row["runtime_tick_count"]), row["first_runtime_tick"],
                row["last_runtime_tick"],
            )
    return result


def point_integer(value: float) -> int:
    return int((Decimal(str(value)) / POINT).quantize(
        Decimal("1"), rounding=ROUND_HALF_UP
    ))


def bar_json(bar: Bar, eligible: bool, segment: int | None) -> dict:
    return {
        "timestamp": iso(bar.time),
        "open": bar.open,
        "high": bar.high,
        "low": bar.low,
        "close": bar.close,
        "tick_volume": bar.tick_volume,
        "spread": bar.spread,
        "runtime_tick_count": bar.runtime_tick_count,
        "first_runtime_tick": bar.first_tick,
        "last_runtime_tick": bar.last_tick,
        "eligible": eligible,
        "clean_segment_id": segment,
    }


def eligible_segment(time: datetime) -> int | None:
    for segment in SEGMENTS:
        start = parse_time(segment["eligible_start"])
        end = parse_time(segment["end"])
        if start <= time < end:
            return int(segment["id"])
    return None


def strictly_below(value: float, boundary: float) -> bool:
    scale = max(1.0, abs(value), abs(boundary))
    tolerance = 8.0 * 2.2204460492503131e-16 * scale
    return value < boundary and (boundary - value) > tolerance


def evaluate_completed_bars(window: list[Bar]) -> dict:
    if len(window) != 221:
        raise ValueError("production-equivalent evaluation requires 221 bars")
    ema = sum(bar.close for bar in window[:200]) / 200.0
    alpha = 2.0 / 201.0
    for bar in window[200:]:
        ema = alpha * bar.close + (1.0 - alpha) * ema

    atr = 0.0
    for index, bar in enumerate(window[:14]):
        true_range = bar.high - bar.low
        if index > 0:
            previous_close = window[index - 1].close
            true_range = max(
                true_range,
                abs(bar.high - previous_close),
                abs(bar.low - previous_close),
            )
        atr += true_range
    atr /= 14.0
    for index in range(14, len(window)):
        bar = window[index]
        previous_close = window[index - 1].close
        true_range = max(
            bar.high - bar.low,
            abs(bar.high - previous_close),
            abs(bar.low - previous_close),
        )
        atr = ((atr * 13.0) + true_range) / 14.0

    signal_bar = window[-1]
    entry_high = max(bar.high for bar in window[-21:-1])
    entry_low = min(bar.low for bar in window[-21:-1])
    exit_high = max(bar.high for bar in window[-11:-1])
    exit_low = min(bar.low for bar in window[-11:-1])

    bullish_breakout = signal_bar.close > entry_high
    bearish_breakout = strictly_below(signal_bar.close, entry_low)
    bullish_trend = signal_bar.close > ema
    bearish_trend = signal_bar.close < ema
    if bullish_breakout and bullish_trend:
        entry = "BUY"
    elif bearish_breakout and bearish_trend:
        entry = "SELL"
    else:
        entry = "NONE"
    if strictly_below(signal_bar.close, exit_low):
        exit_signal = "EXIT_LONG"
    elif signal_bar.close > exit_high:
        exit_signal = "EXIT_SHORT"
    else:
        exit_signal = "NONE"
    return {
        "entry": entry,
        "exit": exit_signal,
        "ema_200": ema,
        "atr_14": atr,
        "entry_high": entry_high,
        "entry_low": entry_low,
        "exit_high": exit_high,
        "exit_low": exit_low,
        "initial_stop_distance": 2.0 * atr,
    }


def build_signals(source: dict[datetime, Bar], label: str) -> tuple[dict, dict]:
    events = []
    decisions = {}
    segment_summaries = []
    for segment in SEGMENTS:
        segment_id = int(segment["id"])
        warmup_start = parse_time(segment["warmup_start"])
        eligible_start = parse_time(segment["eligible_start"])
        end = parse_time(segment["end"])
        times = sorted(time for time in source if warmup_start <= time < end)
        state = "FLAT"
        evaluated = 0
        ineligible_history = 0
        events_before = len(events)
        for index, time in enumerate(times):
            if time < eligible_start:
                continue
            evaluation_time = time + timedelta(hours=1)
            if evaluation_time >= CUTOFF:
                continue
            if index < 220:
                ineligible_history += 1
                continue
            calculation = evaluate_completed_bars(
                [source[item] for item in times[index - 220:index + 1]]
            )
            evaluated += 1
            state_before = state
            event_type = None
            signal_type = None
            direction = None
            if state == "FLAT" and calculation["entry"] in {"BUY", "SELL"}:
                signal_type = calculation["entry"]
                direction = "LONG" if signal_type == "BUY" else "SHORT"
                event_type = "ENTRY"
                state = direction
            elif state == "LONG" and calculation["exit"] == "EXIT_LONG":
                signal_type = "EXIT_LONG"
                direction = "LONG"
                event_type = "EXIT"
                state = "FLAT"
            elif state == "SHORT" and calculation["exit"] == "EXIT_SHORT":
                signal_type = "EXIT_SHORT"
                direction = "SHORT"
                event_type = "EXIT"
                state = "FLAT"

            decision_key = iso(time)
            decisions[decision_key] = {
                "segment": segment_id,
                "entry": calculation["entry"],
                "exit": calculation["exit"],
                "state_before": state_before,
                "state_after": state,
                "event": signal_type or "NONE",
                **{key: calculation[key] for key in (
                    "ema_200", "atr_14", "entry_high", "entry_low",
                    "exit_high", "exit_low", "initial_stop_distance"
                )},
            }
            if signal_type is None:
                continue
            entry_level = calculation[
                "entry_high" if direction == "LONG" else "entry_low"
            ]
            exit_level = calculation[
                "exit_low" if direction == "LONG" else "exit_high"
            ]
            events.append({
                "completed_h1_bar_timestamp": iso(time),
                "signal_evaluation_timestamp": iso(evaluation_time),
                "direction": direction,
                "entry_or_exit_type": event_type,
                "signal_type": signal_type,
                "ema_200": calculation["ema_200"],
                "atr_14": calculation["atr_14"],
                "donchian_entry_level": entry_level,
                "donchian_entry_high": calculation["entry_high"],
                "donchian_entry_low": calculation["entry_low"],
                "donchian_exit_level": exit_level,
                "donchian_exit_high": calculation["exit_high"],
                "donchian_exit_low": calculation["exit_low"],
                "calculated_initial_stop_distance":
                    calculation["initial_stop_distance"],
                "clean_segment_identifier": segment_id,
                "state_before": state_before,
                "state_after": state,
            })
        segment_summaries.append({
            "clean_segment_identifier": segment_id,
            "state_at_start": "FLAT",
            "evaluated_bars": evaluated,
            "eligible_bars_without_221_post_reset_bars": ineligible_history,
            "signal_records": len(events) - events_before,
            "state_before_mandatory_reset_or_end": state,
            "state_carried_to_next_segment": False,
        })
    return ({
        "schema": "SOLTRADE_PHASE6_V10_SIGNAL_STREAM_V1",
        "source": label,
        "strategy": "FROZEN_TREND_BREAKOUT_V1_SIGNAL_ONLY",
        "profitability_fields_present": False,
        "signal_count": len(events),
        "decision_evaluation_count": len(decisions),
        "indicator_absolute_tolerance": INDICATOR_TOLERANCE,
        "segment_summaries": segment_summaries,
        "signals": events,
    }, decisions)


def dump(name: str, payload: dict) -> None:
    with (OUT / name).open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2, sort_keys=False, allow_nan=False)
        handle.write("\n")


def main() -> None:
    source_a = read_source_a()
    source_b = read_source_b()
    if len(source_a) != 6097 or len(source_b) != 6097:
        raise RuntimeError("frozen pre-cutoff H1 source count changed")

    eligible_times = sorted(time for time in source_a
                            if eligible_segment(time) is not None)
    missing = [iso(time) for time in eligible_times if time not in source_b]
    eligible_b = {time for time in source_b if eligible_segment(time) is not None}
    extra = sorted(iso(time) for time in eligible_b if time not in source_a)
    mismatches = []
    exact = 0
    for time in eligible_times:
        if time not in source_b:
            continue
        left = source_a[time]
        right = source_b[time]
        fields = {}
        for field in ("open", "high", "low", "close"):
            a_value = getattr(left, field)
            b_value = getattr(right, field)
            if point_integer(a_value) != point_integer(b_value):
                fields[field] = {
                    "source_a": a_value,
                    "source_b": b_value,
                    "source_a_points": point_integer(a_value),
                    "source_b_points": point_integer(b_value),
                }
        if fields:
            mismatches.append({"timestamp": iso(time), "fields": fields})
        else:
            exact += 1

    full_input_mismatch = []
    for time in sorted(set(source_a) | set(source_b)):
        if time not in source_a or time not in source_b:
            full_input_mismatch.append(iso(time))
            continue
        if any(point_integer(getattr(source_a[time], field)) !=
               point_integer(getattr(source_b[time], field))
               for field in ("open", "high", "low", "close")):
            full_input_mismatch.append(iso(time))

    runtime_bars = [
        bar_json(source_b[time], eligible_segment(time) is not None,
                 eligible_segment(time))
        for time in sorted(source_b)
    ]
    dump("tester-runtime-h1-bars-v10.json", {
        "schema": "SOLTRADE_PHASE6_V10_TESTER_RUNTIME_H1_BARS_V1",
        "source": "FPMarketsSC-Demo Strategy Tester CopyRates after guard-tail run",
        "tester_window": "[2025-01-02T00:00:00,2025-12-25T00:00:00)",
        "exported_research_domain": "[2025-01-02T00:00:00,2025-12-24T00:00:00)",
        "guard_tail_bars_included": 0,
        "bar_count": len(runtime_bars),
        "eligible_bar_count": len(eligible_times),
        "first_bar": iso(min(source_b)),
        "final_bar": iso(max(source_b)),
        "source_csv_sha256": sha256(SOURCE_B),
        "bars": runtime_bars,
    })

    dump("tick-derived-versus-tester-h1-comparison-v10.json", {
        "schema": "SOLTRADE_PHASE6_V10_H1_COMPARISON_V1",
        "normalization_point": 0.00001,
        "source_a_sha256": sha256(SOURCE_A),
        "source_b_csv_sha256": sha256(SOURCE_B),
        "eligible_h1_bar_count": len(eligible_times),
        "exact_match_count": exact,
        "mismatched_bar_count": len(mismatches),
        "missing_bar_count": len(missing),
        "extra_bar_count": len(extra),
        "first_mismatch": mismatches[0] if mismatches else None,
        "mismatches": mismatches,
        "missing_timestamps": missing,
        "extra_timestamps": extra,
        "all_6097_indicator_input_bars_point_equal": not full_input_mismatch,
        "all_input_bar_mismatch_timestamps": full_input_mismatch,
        "status": "PASS" if not mismatches and not missing and not extra else "FAIL",
    })

    stream_a, decisions_a = build_signals(source_a, "SOURCE_A_V8_TICK_DERIVED_H1")
    stream_b, decisions_b = build_signals(source_b, "SOURCE_B_TESTER_RUNTIME_H1")
    dump("tick-derived-signal-stream-v10.json", stream_a)
    dump("tester-runtime-signal-stream-v10.json", stream_b)

    all_decision_keys = sorted(set(decisions_a) | set(decisions_b))
    divergences = []
    maximum_deltas = {
        key: 0.0 for key in (
            "ema_200", "atr_14", "entry_high", "entry_low",
            "exit_high", "exit_low", "initial_stop_distance"
        )
    }
    for key in all_decision_keys:
        if key not in decisions_a or key not in decisions_b:
            divergences.append({
                "timestamp": key,
                "reason": "MISSING_DECISION",
                "source_a_present": key in decisions_a,
                "source_b_present": key in decisions_b,
            })
            continue
        left = decisions_a[key]
        right = decisions_b[key]
        exact_fields = ("segment", "entry", "exit", "state_before",
                        "state_after", "event")
        exact_differences = {
            field: {"source_a": left[field], "source_b": right[field]}
            for field in exact_fields if left[field] != right[field]
        }
        indicator_differences = {}
        for field in maximum_deltas:
            delta = abs(float(left[field]) - float(right[field]))
            maximum_deltas[field] = max(maximum_deltas[field], delta)
            if delta > INDICATOR_TOLERANCE:
                indicator_differences[field] = delta
        if exact_differences or indicator_differences:
            divergences.append({
                "timestamp": key,
                "exact_fields": exact_differences,
                "indicator_deltas_over_tolerance": indicator_differences,
            })

    signal_a_keys = [
        (item["completed_h1_bar_timestamp"], item["signal_type"],
         item["direction"], item["clean_segment_identifier"])
        for item in stream_a["signals"]
    ]
    signal_b_keys = [
        (item["completed_h1_bar_timestamp"], item["signal_type"],
         item["direction"], item["clean_segment_identifier"])
        for item in stream_b["signals"]
    ]
    dump("signal-equivalence-report-v10.json", {
        "schema": "SOLTRADE_PHASE6_V10_SIGNAL_EQUIVALENCE_V1",
        "indicator_absolute_tolerance": INDICATOR_TOLERANCE,
        "source_a_signal_count": len(signal_a_keys),
        "source_b_signal_count": len(signal_b_keys),
        "source_a_decision_evaluation_count": len(decisions_a),
        "source_b_decision_evaluation_count": len(decisions_b),
        "signal_key_streams_exact": signal_a_keys == signal_b_keys,
        "complete_signal_divergence_count": len(divergences),
        "maximum_indicator_absolute_deltas": maximum_deltas,
        "divergences": divergences,
        "status": "PASS" if signal_a_keys == signal_b_keys and
                            not divergences else "FAIL",
    })

    segment_counts = {
        str(segment["id"]): sum(
            1 for time in eligible_times
            if eligible_segment(time) == segment["id"]
        ) for segment in SEGMENTS
    }
    dump("quarantine-integrity-v10.json", {
        "schema": "SOLTRADE_PHASE6_V10_QUARANTINE_INTEGRITY_V1",
        "unresolved_gap_count": 3,
        "contaminated_h1_bar_count": 5,
        "post_gap_warmup_per_gap": 200,
        "total_post_gap_warmup_h1_bars": 600,
        "state_reset_after_each_gap": True,
        "state_carried_across_any_gap": False,
        "clean_segment_count": 4,
        "eligible_counts_by_segment": segment_counts,
        "expected_eligible_counts_by_segment": {
            str(segment["id"]): segment["expected_eligible"]
            for segment in SEGMENTS
        },
        "eligible_h1_total": len(eligible_times),
        "development_eligible_h1": 2526,
        "validation_eligible_h1": 1238,
        "out_of_sample_eligible_h1": 1488,
        "boundaries_changed": False,
        "gap_reclassification_performed": False,
        "source_a_segment_summaries": stream_a["segment_summaries"],
        "source_b_segment_summaries": stream_b["segment_summaries"],
        "status": "PASS" if segment_counts == {
            str(segment["id"]): segment["expected_eligible"]
            for segment in SEGMENTS
        } else "FAIL",
    })

    final_bar = source_b[datetime(2025, 12, 23, 23)]
    dump("guard-tail-boundary-report-v10.json", {
        "schema": "SOLTRADE_PHASE6_V10_GUARD_TAIL_BOUNDARY_V1",
        "tester_window": "[2025-01-02T00:00:00,2025-12-25T00:00:00)",
        "research_cutoff_exclusive": "2025-12-24T00:00:00",
        "guard_tail_interval": "[2025-12-24T00:00:00,2025-12-25T00:00:00)",
        "guard_tail_h1_bars_seen_by_tester": 24,
        "guard_tail_h1_bars_exported_as_research": 0,
        "guard_tail_signals_exported_as_research": 0,
        "final_pre_cutoff_h1": bar_json(final_bar, True, 4),
        "final_close_expected": 1.17938,
        "final_close_match": point_integer(final_bar.close) ==
                             point_integer(1.17938),
        "final_bar_signal_evaluation_timestamp": "2025-12-24T00:00:00",
        "final_bar_signal_included": False,
        "post_cutoff_data_influenced_pre_cutoff_signal": False,
        "status": "PASS" if point_integer(final_bar.close) ==
                            point_integer(1.17938) else "FAIL",
    })

    if mismatches or missing or extra or divergences or signal_a_keys != signal_b_keys:
        raise RuntimeError("V10 equivalence gate failed; inspect generated reports")


if __name__ == "__main__":
    main()
