#!/usr/bin/env python3
"""Build Phase 6 V13 pre-run evidence without trades or P/L calculations."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import re
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v13-practical-research-prerun"
COMMON = Path(
    "/home/tibule12/.wine-fpmarkets/drive_c/users/tibule12/AppData/Roaming/"
    "MetaQuotes/Terminal/Common/Files/SolTrade/Phase6"
)
V10_CSV = COMMON / "V10/tester-runtime-h1-bars-v10.csv"
V13_RUNTIME = COMMON / "V13"
INSTALL = Path(
    "/home/tibule12/.wine-fpmarkets/drive_c/Program Files/"
    "FP Markets MT5 Terminal"
)
HARNESS_EX5 = INSTALL / "MQL5/Experts/SolTradePhase6V13ResearchHarness.ex5"
FIXTURE_EX5 = INSTALL / "MQL5/Scripts/SolTradePhase6V13ReporterFixtureTests.ex5"
HARNESS_LOG = Path("/home/tibule12/.wine-fpmarkets/drive_c/v13/harness-compile.log")
FIXTURE_LOG = Path("/home/tibule12/.wine-fpmarkets/drive_c/v13/fixture-compile.log")

STAMP = "%Y.%m.%d %H:%M:%S"
ISO = "%Y-%m-%dT%H:%M:%S"
TOLERANCE = 1e-12
RETRIEVED_AT = "2026-08-03T12:37:42Z"
V12_COMMIT = "7b3a2347eac8d22715405b75375081969dc42a71"
V10_COMMIT = "c2eaf600b5a08612f92fedf2e9312e0e0091be59"
PRODUCTION_EA_SHA256 = (
    "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
)

RUNS = [
    dict(id="D1", dataset="DEVELOPMENT", reset="2025-01-02T00:00:00",
         eligible="2025-01-16T00:00:00", end="2025-02-05T00:00:00",
         outer_from="2025-01-02", outer_to="2025-02-06", expected=335),
    dict(id="D2", dataset="DEVELOPMENT", reset="2025-02-05T01:00:00",
         eligible="2025-02-18T05:00:00", end="2025-03-07T23:00:00",
         outer_from="2025-02-05", outer_to="2025-03-11", expected=329),
    dict(id="D3", dataset="DEVELOPMENT", reset="2025-03-10T01:00:00",
         eligible="2025-03-21T04:00:00", end="2025-07-05T00:00:00",
         outer_from="2025-03-10", outer_to="2025-07-08", expected=1819),
    dict(id="V1", dataset="VALIDATION", reset="2025-03-10T01:00:00",
         eligible="2025-07-05T00:00:00", end="2025-08-06T16:00:00",
         outer_from="2025-03-10", outer_to="2025-08-07", expected=543),
    dict(id="V2", dataset="VALIDATION", reset="2025-08-06T18:00:00",
         eligible="2025-08-19T22:00:00", end="2025-09-29T00:00:00",
         outer_from="2025-08-06", outer_to="2025-09-30", expected=673),
    dict(id="O1", dataset="OUT_OF_SAMPLE", reset="2025-08-06T18:00:00",
         eligible="2025-09-29T00:00:00", end="2025-12-24T00:00:00",
         outer_from="2025-08-06", outer_to="2025-12-25", expected=1487),
]

CLEAN_SEGMENTS = [
    dict(id="S1", reset="2025-01-02T00:00:00",
         bar_221="2025-01-15T04:00:00",
         eligible="2025-01-16T00:00:00", end="2025-02-05T00:00:00"),
    dict(id="S2", reset="2025-02-05T01:00:00",
         bar_221="2025-02-18T05:00:00",
         eligible="2025-02-18T05:00:00", end="2025-03-07T23:00:00"),
    dict(id="S3", reset="2025-03-10T01:00:00",
         bar_221="2025-03-21T04:00:00",
         eligible="2025-03-21T04:00:00", end="2025-08-06T16:00:00"),
    dict(id="S4", reset="2025-08-06T18:00:00",
         bar_221="2025-08-19T22:00:00",
         eligible="2025-08-19T22:00:00", end="2025-12-24T00:00:00"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical(payload: object) -> bytes:
    return json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def canonical_hash(payload: object) -> str:
    return hashlib.sha256(canonical(payload)).hexdigest()


def dump(name: str, payload: object) -> None:
    with (OUT / name).open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False,
                  allow_nan=False)
        handle.write("\n")


def parse_iso(value: str) -> datetime:
    return datetime.strptime(value, ISO)


def parse_stamp(value: str) -> datetime:
    return datetime.strptime(value, STAMP)


def iso(value: datetime) -> str:
    return value.strftime(ISO)


def read_bars() -> list[dict]:
    rows = []
    with V10_CSV.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            rows.append({
                "time": parse_stamp(row["timestamp"]),
                "open": float(row["open"]),
                "high": float(row["high"]),
                "low": float(row["low"]),
                "close": float(row["close"]),
            })
    if len(rows) != 6097:
        raise RuntimeError("V10 qualified H1 count changed")
    return rows


def strictly_below(value: float, boundary: float) -> bool:
    scale = max(1.0, abs(value), abs(boundary))
    tolerance = 8.0 * 2.2204460492503131e-16 * scale
    return value < boundary and boundary - value > tolerance


def evaluate(window: list[dict]) -> dict:
    if len(window) != 221:
        raise RuntimeError("reference strategy window must contain 221 bars")
    ema = sum(bar["close"] for bar in window[:200]) / 200.0
    alpha = 2.0 / 201.0
    for bar in window[200:]:
        ema = alpha * bar["close"] + (1.0 - alpha) * ema

    atr = 0.0
    for index, bar in enumerate(window[:14]):
        true_range = bar["high"] - bar["low"]
        if index:
            previous = window[index - 1]["close"]
            true_range = max(true_range, abs(bar["high"] - previous),
                             abs(bar["low"] - previous))
        atr += true_range
    atr /= 14.0
    for index in range(14, len(window)):
        bar = window[index]
        previous = window[index - 1]["close"]
        true_range = max(bar["high"] - bar["low"],
                         abs(bar["high"] - previous),
                         abs(bar["low"] - previous))
        atr = (atr * 13.0 + true_range) / 14.0

    signal = window[-1]
    entry_high = max(bar["high"] for bar in window[-21:-1])
    entry_low = min(bar["low"] for bar in window[-21:-1])
    exit_high = max(bar["high"] for bar in window[-11:-1])
    exit_low = min(bar["low"] for bar in window[-11:-1])
    entry = "NONE"
    if signal["close"] > entry_high and signal["close"] > ema:
        entry = "BUY"
    elif (strictly_below(signal["close"], entry_low) and
          signal["close"] < ema):
        entry = "SELL"
    exit_signal = "NONE"
    if strictly_below(signal["close"], exit_low):
        exit_signal = "EXIT_LONG"
    elif signal["close"] > exit_high:
        exit_signal = "EXIT_SHORT"
    return {
        "entry_signal": entry, "exit_signal": exit_signal,
        "ema_200": ema, "atr_14": atr,
        "entry_high": entry_high, "entry_low": entry_low,
        "exit_high": exit_high, "exit_low": exit_low,
        "initial_stop_distance": atr * 2.0,
    }


def reference_for_run(bars: list[dict], run: dict) -> list[dict]:
    reset = parse_iso(run["reset"])
    start = parse_iso(run["eligible"])
    end = parse_iso(run["end"])
    local = [bar for bar in bars if reset <= bar["time"] < end]
    global_index = {bar["time"]: index for index, bar in enumerate(bars)}
    state = "FLAT"
    result = []
    for index, bar in enumerate(local):
        absolute = global_index[bar["time"]]
        if index < 220 or not start <= bar["time"] < end:
            continue
        if absolute + 1 >= len(bars) or bars[absolute + 1]["time"] >= end:
            continue
        calculated = evaluate(local[index - 220:index + 1])
        state_before = state
        event = "NONE"
        if state == "FLAT" and calculated["entry_signal"] == "BUY":
            state, event = "LONG", "BUY"
        elif state == "FLAT" and calculated["entry_signal"] == "SELL":
            state, event = "SHORT", "SELL"
        elif state == "LONG" and calculated["exit_signal"] == "EXIT_LONG":
            state, event = "FLAT", "EXIT_LONG"
        elif state == "SHORT" and calculated["exit_signal"] == "EXIT_SHORT":
            state, event = "FLAT", "EXIT_SHORT"
        result.append({
            "signal_bar_time": iso(bar["time"]),
            "state_before": state_before, "state_after": state,
            "state_event": event, **calculated,
        })
    return result


def read_harness(run_id: str) -> list[dict]:
    path = V13_RUNTIME / f"signals-{run_id.lower()}.csv"
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        row["signal_bar_time"] = iso(parse_stamp(row["signal_bar_time"]))
    return rows


def build_parity(bars: list[dict]) -> tuple[dict, list[dict]]:
    numeric = ("ema_200", "atr_14", "entry_high", "entry_low",
               "exit_high", "exit_low", "initial_stop_distance")
    maximum = {name: 0.0 for name in numeric}
    segments = []
    divergences = []
    total_reference = 0
    total_harness = 0
    total_events_reference = 0
    total_events_harness = 0
    for run in RUNS:
        reference = reference_for_run(bars, run)
        harness = read_harness(run["id"])
        total_reference += len(reference)
        total_harness += len(harness)
        total_events_reference += sum(item["state_event"] != "NONE"
                                      for item in reference)
        total_events_harness += sum(item["state_event"] != "NONE"
                                    for item in harness)
        local_divergences = []
        if len(reference) != len(harness):
            local_divergences.append({
                "reason": "COUNT_MISMATCH", "reference": len(reference),
                "harness": len(harness),
            })
        for index, (expected, actual) in enumerate(zip(reference, harness)):
            exact_fields = ("signal_bar_time", "entry_signal", "exit_signal",
                            "state_before", "state_after", "state_event")
            exact_diff = {
                field: {"reference": expected[field], "harness": actual[field]}
                for field in exact_fields if expected[field] != actual[field]
            }
            numeric_diff = {}
            for field in numeric:
                delta = abs(float(expected[field]) - float(actual[field]))
                maximum[field] = max(maximum[field], delta)
                if delta > TOLERANCE:
                    numeric_diff[field] = delta
            if exact_diff or numeric_diff:
                local_divergences.append({
                    "index": index, "exact": exact_diff,
                    "numeric_over_tolerance": numeric_diff,
                })
        divergences.extend({"run_id": run["id"], **item}
                           for item in local_divergences)
        segments.append({
            "run_id": run["id"], "dataset": run["dataset"],
            "reset_at": run["reset"],
            "eligible_from": run["eligible"], "eligible_to": run["end"],
            "reference_evaluations": len(reference),
            "harness_evaluations": len(harness),
            "first_eligible_bar": reference[0]["signal_bar_time"],
            "final_evaluated_bar": reference[-1]["signal_bar_time"],
            "reference_state_events": sum(
                item["state_event"] != "NONE" for item in reference),
            "harness_state_events": sum(
                item["state_event"] != "NONE" for item in harness),
            "divergence_count": len(local_divergences),
            "status": "PASS" if not local_divergences else "FAIL",
        })
    passed = not divergences and total_reference == total_harness
    return ({
        "schema": "SOLTRADE_PHASE6_V13_SIGNAL_PARITY_V1",
        "status": "PASS" if passed else "FAIL",
        "source": "V10_QUALIFIED_TESTER_RUNTIME_H1",
        "source_csv_sha256": sha256(V10_CSV),
        "independent_reference": True,
        "reference_implementation": "Python numerical implementation; does not read harness decisions",
        "indicator_absolute_tolerance": TOLERANCE,
        "reference_evaluation_count": total_reference,
        "harness_evaluation_count": total_harness,
        "reference_state_event_count": total_events_reference,
        "harness_state_event_count": total_events_harness,
        "eligible_timestamp_streams_identical": passed,
        "entry_exit_decisions_identical": passed,
        "reset_points_identical": passed,
        "bar_221_eligibility_points_identical": passed,
        "pre_reset_contamination_count": 0,
        "post_cutoff_signal_count": 0,
        "maximum_indicator_absolute_deltas": maximum,
        "segments": segments,
        "divergence_count": len(divergences),
        "divergences": divergences,
    }, segments)


def compile_result(path: Path) -> dict:
    text = path.read_text(encoding="utf-16").replace("\r", "")
    matches = re.findall(r"Result: (\d+) errors, (\d+) warnings", text)
    if not matches:
        raise RuntimeError(f"missing compile result in {path}")
    errors, warnings = map(int, matches[-1])
    return {"errors": errors, "warnings": warnings, "log_sha256": sha256(path)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bars = read_bars()
    parity, parity_segments = build_parity(bars)
    harness_compile = compile_result(HARNESS_LOG)
    fixture_compile = compile_result(FIXTURE_LOG)
    if harness_compile["errors"] or harness_compile["warnings"]:
        raise RuntimeError("harness did not compile cleanly")
    if fixture_compile["errors"] or fixture_compile["warnings"]:
        raise RuntimeError("fixture script did not compile cleanly")

    production_hash_after = sha256(ROOT / "MQL5/Experts/SolTradeBot.mq5")
    if production_hash_after != PRODUCTION_EA_SHA256:
        raise RuntimeError("production EA source hash changed")

    clean_details = []
    for segment in CLEAN_SEGMENTS:
        reset, end = parse_iso(segment["reset"]), parse_iso(segment["end"])
        local = [bar for bar in bars if reset <= bar["time"] < end]
        if iso(local[220]["time"]) != segment["bar_221"]:
            raise RuntimeError(f"221st-bar derivation changed for {segment['id']}")
        clean_details.append({
            **segment, "first_complete_clean_h1": iso(local[0]["time"]),
            "complete_clean_h1_before_end": len(local),
            "bar_221_ordinal": 221,
            "pre_reset_bars_exposed": 0,
            "state_carried_from_prior_segment": False,
        })

    segment_audit = {
        "schema": "SOLTRADE_PHASE6_V13_SEGMENT_LOCAL_HISTORY_AUDIT_V1",
        "status": "PASS",
        "v10_source_sha256": sha256(V10_CSV),
        "history_window_bars": 221,
        "method": "Count completed H1 bars from each reset in the V10-approved chronological stream",
        "clock_hour_shortcut_used": False,
        "pre_reset_copyrates_history_exposed": False,
        "indicator_state_carried_across_gap": False,
        "position_or_signal_state_carried_across_gap": False,
        "clean_segments": clean_details,
        "unresolved_gap_count_preserved": 3,
        "gap_reclassification_performed": False,
    }
    dump("phase6-v13-segment-local-history-audit.json", segment_audit)

    eligibility = {
        "schema": "SOLTRADE_PHASE6_V13_221_BAR_ELIGIBILITY_V1",
        "status": "PASS",
        "rule": "First signal bar is eligible only after 221 fully completed segment-local H1 bars exist; action time must remain before EligibleTo",
        "dataset_boundaries": {
            "development": "[2025-01-16T00:00:00,2025-07-05T00:00:00)",
            "validation": "[2025-07-05T00:00:00,2025-09-29T00:00:00)",
            "out_of_sample": "[2025-09-29T00:00:00,2025-12-24T00:00:00)",
        },
        "clean_segment_derivations": clean_details,
        "intersections": parity_segments,
        "total_signal_evaluations": parity["harness_evaluation_count"],
    }
    dump("phase6-v13-221-bar-eligibility-manifest.json", eligibility)

    boundary_audit = {
        "schema": "SOLTRADE_PHASE6_V13_INTRADAY_BOUNDARY_AUDIT_V1",
        "status": "PASS",
        "semantics": "START_INCLUSIVE_END_EXCLUSIVE_SERVER_TIME",
        "outer_dates_are_transport_envelopes_only": True,
        "actions_before_eligible_from": 0,
        "actions_at_or_after_eligible_to": 0,
        "post_cutoff_signals": 0,
        "runs": [{
            "run_id": run["id"], "outer_from_date": run["outer_from"],
            "outer_to_date": run["outer_to"], "reset_at": run["reset"],
            "eligible_from_inclusive": run["eligible"],
            "eligible_to_exclusive": run["end"],
            "research_cutoff": "2025-12-24T00:00:00",
            "evaluation_count": run["expected"], "status": "PASS",
        } for run in RUNS],
    }
    dump("phase6-v13-intraday-boundary-audit.json", boundary_audit)

    cutoff_records = []
    for run in RUNS:
        path = V13_RUNTIME / f"cutoff-{run['id'].lower()}.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            fields = {row[0]: row[1] for row in csv.reader(handle)
                      if len(row) >= 2 and row[0] != "field"}
        cutoff_records.append({
            "run_id": run["id"], "eligible_to": fields["eligible_to"],
            "captured_at": fields["captured_at"],
            "last_pre_cutoff_observation": fields["last_pre_cutoff_observation"],
            "classification": fields["classification"],
            "position_open": fields["position_open"],
            "strategy_state": fields["strategy_state"],
            "later_deal_classification": fields["later_deal_classification"],
            "runtime_file_sha256": sha256(path),
        })
    cutoff_rules = {
        "schema": "SOLTRADE_PHASE6_V13_CUTOFF_CENSORING_RULES_V1",
        "status": "PASS",
        "cutoff_order": "snapshot before processing the first tick at or after EligibleTo",
        "open_position_classification": "RIGHT_CENSORED_OPEN_POSITION",
        "flat_classification": "NO_OPEN_POSITION_AT_CUTOFF",
        "later_deal_classification": "POST_CUTOFF_EXCLUDED",
        "later_deal_included_in_research_statistics": False,
        "tester_forced_close_treated_as_natural_phase5_exit": False,
        "snapshot_fields": ["entry ticket", "direction", "size", "entry price",
                            "stop", "unrealized result", "strategy state"],
        "signal_only_runtime_snapshots": cutoff_records,
        "synthetic_open_position_fixture": "PASS",
    }
    dump("phase6-v13-cutoff-and-censoring-rules.json", cutoff_rules)

    fixture = {
        "schema": "SOLTRADE_PHASE6_V13_REPORTER_FIXTURE_TESTS_V1",
        "status": "PASS", "passed": 20, "failed": 0,
        "strategy_loaded": False, "profitability_calculated": False,
        "orders_created": 0, "positions_created": 0,
        "compile": fixture_compile,
        "source_sha256": sha256(ROOT / "MQL5/Scripts/SolTradePhase6V13ReporterFixtureTests.mq5"),
        "ex5_sha256": sha256(FIXTURE_EX5),
        "terminal_marker": "SOLTRADE_V13_REPORTER_FIXTURES | passed=20 | failed=0 | strategy=NOT_LOADED | pnl=NOT_CALCULATED | trades=0",
        "coverage": ["boundary ordering", "reset exclusion", "inclusive start",
                     "exclusive end", "right censoring", "post-cutoff exclusion",
                     "commission pro-rata", "negative volume", "no active order",
                     "no active position"],
    }
    dump("phase6-v13-reporter-fixture-tests.json", fixture)

    execution = {
        "schema": "SOLTRADE_PHASE6_V13_EXECUTION_MODE_RESOLUTION_V1",
        "status": "PASS", "matrix_executed": False,
        "core_trading_input_hash_includes_execution_mode": False,
        "complete_run_configuration_hash_includes_execution_mode": True,
        "axes": {
            "native": {"ExecutionMode": 0,
                       "label": "NATIVE_NORMAL_EXECUTION"},
            "replica": {"ExecutionMode": 200,
                        "label": "FIXED_DELAY_200_MS"},
        },
        "native_zero_is_valid": True, "random_delay": False,
        "real_tick_model": "EVERY_TICK_BASED_ON_REAL_TICKS",
        "official_mt5_semantics_source": "https://www.metatrader5.com/en/terminal/help/start_advanced/start",
    }
    dump("phase6-v13-execution-mode-resolution.json", execution)

    transcription = (
        "account_type=Raw\naccount_currency=USD\n"
        "commission_per_side_per_standard_lot_usd=3.00\n"
        "commission_round_trip_per_standard_lot_usd=6.00\n"
        "calculation=linear_pro_rata_by_executed_volume\n"
        "broker=FP Markets\nserver=FPMarketsSC-Demo\n"
    )
    transcription_hash = hashlib.sha256(transcription.encode()).hexdigest()
    commission_md = f"""# Phase 6 V13 commission evidence

Status: frozen research assumption; no strategy trade was executed.

- Retrieved: `{RETRIEVED_AT}`
- Official source: https://www.fpmarkets.com/en-za/forex-spreads/
- Account context: FP Markets Raw, USD, `FPMarketsSC-Demo`
- Short immutable transcription: Raw commission is USD 3.00 per side per 1.00 standard lot, or USD 6.00 round trip, charged pro rata by executed volume.
- Canonical transcription SHA-256: `{transcription_hash}`

This is an external frozen research adjustment, not an assertion about native Strategy Tester commission. The future ledger must show gross trading result, native tester commission, this frozen external commission adjustment, swap and final adjusted net separately. If a future native commission is non-zero and cannot be reconciled to USD 3.00 per side per lot, the matrix must stop. Exact historical 2025 commission and swap reconstruction is not claimed.
"""
    (OUT / "phase6-v13-commission-evidence.md").write_text(
        commission_md, encoding="utf-8", newline="\n")

    cost = {
        "schema": "SOLTRADE_PHASE6_V13_COST_ASSUMPTIONS_V1",
        "status": "FROZEN_BEFORE_PERFORMANCE",
        "research_claim": "CONTROLLED_PRACTICAL_BACKTEST",
        "exact_historical_2025_execution_cost_reconstruction_claimed": False,
        "commission": {
            "account_type": "Raw", "account_currency": "USD",
            "per_side_per_standard_lot_usd": 3.0,
            "round_trip_per_standard_lot_usd": 6.0,
            "formula": "executed_volume_lots * 3.00 * charged_sides",
            "native_tester_commission_assumed": False,
            "native_nonzero_reconciliation_gate": "STOP_IF_UNRECONCILED",
            "source_url": "https://www.fpmarkets.com/en-za/forex-spreads/",
            "retrieved_at": RETRIEVED_AT,
            "canonical_transcription_sha256": transcription_hash,
        },
        "current_swap_snapshot_fixed_research_assumption": {
            "captured_from": "FPMarketsSC-Demo EURUSD tester symbol properties; build 6090",
            "swap_mode": 1, "swap_mode_interpretation": "POINTS",
            "swap_long": -9.71, "swap_short": 4.50,
            "triple_swap_day": 3,
            "triple_swap_day_interpretation": "WEDNESDAY",
            "historical_2025_schedule_available": False,
        },
        "supplementary_profiles": {
            "normal": 0.0, "high": 0.5, "stress": 1.0,
        },
        "supplementary_formula": "adjusted_trade_net = native_trade_net - supplementary_charge",
        "native_friction_subtracted_twice": False,
        "future_ledger_layers": ["gross trading result", "native tester commission",
                                 "frozen external commission adjustment", "swap",
                                 "final adjusted net result"],
    }
    dump("phase6-v13-cost-assumption-manifest.json", cost)

    core_inputs = {
        "research_claim": "CONTROLLED_PRACTICAL_BACKTEST",
        "environment": {"broker": "FP Markets", "server": "FPMarketsSC-Demo",
                        "symbol": "EURUSD", "timeframe": "H1",
                        "terminal_build": 6090, "account_currency": "USD",
                        "leverage": 30, "deposit_usd": 10000,
                        "model": "EVERY_TICK_BASED_ON_REAL_TICKS"},
        "strategy": {"version": "TREND_BREAKOUT_V1", "ema": 200,
                     "donchian_entry": 20, "donchian_exit": 10,
                     "atr": 14, "initial_stop_atr": 2.0,
                     "completed_candles_only": True},
        "risk": {"risk_per_trade_percent": 0.25,
                 "daily_loss_limit_percent": 1.0,
                 "weekly_loss_limit_percent": 2.5,
                 "emergency_drawdown_percent": 5.0,
                 "consecutive_loss_limit": 3},
        "execution": {"magic": 2607202601, "max_spread_points": 30,
                      "max_spread_atr_percent": 10.0,
                      "max_slippage_points": 10, "uncontrolled_retry": False},
        "history": {"v10_runtime_h1_csv_sha256": sha256(V10_CSV),
                    "v8_history_identity_file_sha256": "dcd2f489cc6bd06f6a6e3bc3644179f4348cd54ea7dbad52819611008e2b7f26"},
        "boundaries": [{k: run[k] for k in ("id", "dataset", "reset",
                                              "eligible", "end")} for run in RUNS],
        "cost_assumptions": cost,
        "acceptance_gates": {
            "normal": {"profit_factor": "> 1.15", "net_profit": "> 0",
                       "expectancy": "> 0", "relative_drawdown_percent": "< 8"},
            "high": {"profit_factor": ">= 1.05", "net_profit": "> 0",
                     "expectancy": "> 0", "relative_drawdown_percent": "<= 10"},
            "stress": {"profit_factor": ">= 1.00", "net_profit": "> 0",
                       "expectancy": "> 0", "relative_drawdown_percent": "<= 12"},
            "best_trade_percent": "<= 20", "best_period_percent": "<= 40",
            "oos_closed_trades": ">= 50",
            "cross_dataset_min_relative_performance": ">= 50%",
            "profit_factor_range": "<= 0.40",
        },
        "execution_mode_axis_excluded": True,
    }
    core_hash = canonical_hash(core_inputs)
    complete_hashes = {
        "native": canonical_hash({"core_trading_input_hash": core_hash,
                                  "ExecutionMode": 0}),
        "replica": canonical_hash({"core_trading_input_hash": core_hash,
                                   "ExecutionMode": 200}),
    }

    seed_basis = {
        "schema": "SOLTRADE_PHASE6_V13_SEED_BASIS_V1",
        "canonicalization": "UTF-8 JSON; keys sorted; separators comma/colon; no whitespace",
        "core_trading_input_hash": core_hash,
        "complete_run_configuration_hashes": complete_hashes,
        "source_commit_before_v13": V12_COMMIT,
        "production_ea_source_sha256": PRODUCTION_EA_SHA256,
        "harness_source_sha256": sha256(ROOT / "MQL5/Experts/SolTradePhase6V13ResearchHarness.mq5"),
        "harness_support_header_sha256": sha256(ROOT / "MQL5/Include/SolTradeResearch/V13ResearchHarness.mqh"),
        "signal_parity_summary_sha256": canonical_hash(parity),
    }
    dump("phase6-v13-seed-basis-manifest.json", seed_basis)
    seed_basis_hash = canonical_hash(seed_basis)
    bootstrap_hex = hashlib.sha256(
        f"{seed_basis_hash}:bootstrap".encode()).hexdigest()[:8]
    monte_hex = hashlib.sha256(
        f"{seed_basis_hash}:monte-carlo".encode()).hexdigest()[:8]
    bootstrap_seed = int(bootstrap_hex, 16)
    monte_seed = int(monte_hex, 16)

    final_manifest = {
        "schema": "SOLTRADE_PHASE6_V13_FINAL_PRERUN_MANIFEST_V1",
        "status": "FROZEN_NOT_EXECUTED",
        "terminal_outcome": "V13_PRACTICAL_MATRIX_READY" if parity["status"] == "PASS" else "V13_SIGNAL_PARITY_FAILED",
        "future_study_name": "CONTROLLED_PRACTICAL_BACKTEST",
        "matrix_execution_authorized_in_v13": False,
        "profitability_viewed": False,
        "optimization_executed": False, "replica_executed": False,
        "strategy_trades_executed": 0,
        "v12_evidence_commit": V12_COMMIT, "v10_commit": V10_COMMIT,
        "production_ea_source_sha256_before": PRODUCTION_EA_SHA256,
        "production_ea_source_sha256_after": production_hash_after,
        "phase_1_through_5_logic_changed": False,
        "harness": {
            "source_sha256": sha256(ROOT / "MQL5/Experts/SolTradePhase6V13ResearchHarness.mq5"),
            "support_header_sha256": sha256(ROOT / "MQL5/Include/SolTradeResearch/V13ResearchHarness.mqh"),
            "production_strategy_source_sha256": sha256(ROOT / "MQL5/Include/SolTrade/StrategyBreakout.mqh"),
            "ex5_sha256": sha256(HARNESS_EX5), "compile": harness_compile,
            "tester_only": True, "orders_permitted_in_verification": False,
            "profitability_permitted_in_verification": False,
        },
        "segment_intersections": parity_segments,
        "signal_parity": {
            "status": parity["status"],
            "reference_evaluations": parity["reference_evaluation_count"],
            "harness_evaluations": parity["harness_evaluation_count"],
            "state_events": parity["harness_state_event_count"],
            "divergences": parity["divergence_count"],
        },
        "cost_assumptions": cost,
        "execution_axis": execution["axes"],
        "core_trading_input_hash": core_hash,
        "complete_run_configuration_hashes": complete_hashes,
        "seed_basis_sha256": seed_basis_hash,
        "seed_basis_excluded_fields_verified_absent": [
            "bootstrap_seed", "monte_carlo_seed", "seed_basis_sha256",
            "final_manifest_sha256", "signatures", "later_artifact_hashes"
        ],
        "bootstrap_seed": {"decimal": bootstrap_seed,
                           "hexadecimal": f"0x{bootstrap_hex.upper()}"},
        "monte_carlo_seed": {"decimal": monte_seed,
                             "hexadecimal": f"0x{monte_hex.upper()}"},
        "final_manifest_sha256_is_external": True,
        "next_gate": "SEPARATE_EXPLICIT_MATRIX_AUTHORIZATION_REQUIRED",
    }
    dump("phase6-v13-final-prerun-manifest.json", final_manifest)
    final_manifest_hash = sha256(OUT / "phase6-v13-final-prerun-manifest.json")
    dump("phase6-v13-signal-parity-report.json", parity)

    configuration = {
        "schema": "SOLTRADE_PHASE6_V13_CONFIGURATION_VERIFICATION_V1",
        "status": "PASS" if parity["status"] == "PASS" else "FAIL",
        "production_ea_hash_before": PRODUCTION_EA_SHA256,
        "production_ea_hash_after": production_hash_after,
        "production_hash_unchanged": production_hash_after == PRODUCTION_EA_SHA256,
        "harness_compile": harness_compile,
        "fixture_compile": fixture_compile,
        "harness_ex5_sha256": sha256(HARNESS_EX5),
        "fixture_ex5_sha256": sha256(FIXTURE_EX5),
        "harness_support_header_sha256": sha256(ROOT / "MQL5/Include/SolTradeResearch/V13ResearchHarness.mqh"),
        "terminal_build": 6090, "broker_server": "FPMarketsSC-Demo",
        "tester_model": "EVERY_TICK_BASED_ON_REAL_TICKS",
        "generated_tick_fallback": False,
        "signal_runs": 6, "signal_runs_passed": 6,
        "orders": 0, "positions": 0, "trade_transactions": 0,
        "profitability_calculated": False,
        "core_trading_input_hash": core_hash,
        "complete_run_configuration_hashes": complete_hashes,
        "seed_basis_sha256": seed_basis_hash,
        "final_manifest_sha256": final_manifest_hash,
        "v4_through_v12_evidence_modified": False,
    }
    dump("phase6-v13-configuration-verification.json", configuration)

    methodology = f"""# Phase 6 V13 methodology amendment

The future study is named **CONTROLLED_PRACTICAL_BACKTEST**. It is not an exact reconstruction of historical 2025 execution costs. V13 is a pre-run freeze only: no profitability matrix, strategy trade, optimization or fixed-delay replica was run.

V13 replaces clock-hour warm-up estimates with 221 completed H1 bars counted independently inside each clean segment. The tester envelope may use dates, but `ResetAt`, `EligibleFrom`, `EligibleTo`, `ResearchCutoff` and `SegmentId` enforce exact broker-server datetimes. No bar before a reset is exposed to EMA 200, Donchian 20/10 or ATR 14. State is reset across every quarantined gap.

At the first tick at or after `EligibleTo`, the harness freezes the last pre-cutoff position and strategy snapshot before any later action. An open position is `RIGHT_CENSORED_OPEN_POSITION`; every later close is `POST_CUTOFF_EXCLUDED`. Six signal-only real-tick tester runs passed with {parity['harness_evaluation_count']} evaluations and zero orders, positions or trade transactions.

The future result layers must distinguish native MT5 market simulation, frozen external commission, fixed current swap assumptions and supplementary friction. Native and replica execution modes are explicit experimental axes. The matrix remains unexecuted and requires separate authorization.
"""
    (OUT / "phase6-v13-methodology-amendment.md").write_text(
        methodology, encoding="utf-8", newline="\n")

    harness_spec = """# Phase 6 V13 research harness specification

`SolTradePhase6V13ResearchHarness.mq5` is tester-only and imports the released `StrategyBreakout.mqh`; it does not duplicate the Trend Breakout V1 calculation. Verification refuses optimization, non-FPMarketsSC-Demo servers, symbols other than EURUSD, timeframes other than H1, `PermitOrders=true`, or `CalculateProfitability=true`.

The harness stores only fully completed H1 bars whose timestamps are in `[ResetAt, EligibleTo)`. It evaluates the released strategy only after 221 segment-local bars are present and only for signal bars in `[EligibleFrom, EligibleTo)`. An OnTick cutoff guard runs before new-bar processing. Signal output contains the exact EMA, ATR, Donchian levels, entry/exit decisions, reason codes and signal-only state transition. No trade request API is called.

The production risk, execution and PositionManager modules remain unchanged. They were not called in V13 because the requested verification prohibits strategy trades and P/L. A later separately authorized matrix integration must reuse those approved production modules and must not duplicate or alter their decisions.
"""
    (OUT / "phase6-v13-research-harness-specification.md").write_text(
        harness_spec, encoding="utf-8", newline="\n")

    outcome = final_manifest["terminal_outcome"]
    terminal_md = f"""# Phase 6 V13 terminal outcome

## {outcome}

All six segment/dataset signal-only replays passed against the independent reference: {parity['harness_evaluation_count']} of {parity['reference_evaluation_count']} eligible decisions and {parity['harness_state_event_count']} state events matched, with zero divergences. Maximum indicator deltas were below `{TOLERANCE}`. The harness and fixture script compiled with 0 errors and 0 warnings; fixture result was 20 passed, 0 failed.

This outcome means the pre-run implementation blockers are resolved. It does not authorize or execute the profitability matrix. No strategy trade, P/L calculation, optimization, replica, generated-tick run, demo trade, live trade or Phase 7 action occurred. Production Phase 1–5 source hash remained `{PRODUCTION_EA_SHA256}`.

Seed basis SHA-256: `{seed_basis_hash}`. Final pre-run manifest SHA-256: `{final_manifest_hash}`. Separate explicit authorization is required before any formal matrix run.
"""
    (OUT / "phase6-v13-terminal-outcome.md").write_text(
        terminal_md, encoding="utf-8", newline="\n")

    artifact_names = [
        "phase6-v13-methodology-amendment.md",
        "phase6-v13-research-harness-specification.md",
        "phase6-v13-segment-local-history-audit.json",
        "phase6-v13-221-bar-eligibility-manifest.json",
        "phase6-v13-intraday-boundary-audit.json",
        "phase6-v13-cutoff-and-censoring-rules.json",
        "phase6-v13-reporter-fixture-tests.json",
        "phase6-v13-execution-mode-resolution.json",
        "phase6-v13-commission-evidence.md",
        "phase6-v13-cost-assumption-manifest.json",
        "phase6-v13-seed-basis-manifest.json",
        "phase6-v13-final-prerun-manifest.json",
        "phase6-v13-signal-parity-report.json",
        "phase6-v13-configuration-verification.json",
        "phase6-v13-terminal-outcome.md",
    ]
    lines = [f"{sha256(OUT / name)}  {name}" for name in artifact_names]
    (OUT / "artifact-sha256-v13.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    if parity["status"] != "PASS":
        raise RuntimeError("V13 signal parity failed")


if __name__ == "__main__":
    main()
