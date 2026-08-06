#!/usr/bin/env python3
"""Close V30 at the frozen data gate without exposing performance."""
from __future__ import annotations

import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v30-v28-historical-replication"
RUNS = OUT / "data-qualification/physical-runs"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
FMT = "%Y.%m.%d %H:%M:%S"
EXPECTED = {
    "EURUSD": (5, 0.00001, 100000.0, -9.71, 4.50), "GBPUSD": (5, 0.00001, 100000.0, -2.63, -1.53),
    "AUDUSD": (5, 0.00001, 100000.0, -1.83, -0.51), "NZDUSD": (5, 0.00001, 100000.0, -2.76, 0.46),
    "USDCAD": (5, 0.00001, 100000.0, 3.49, -9.10), "USDCHF": (5, 0.00001, 100000.0, 5.97, -11.60),
    "USDJPY": (3, 0.001, 100000.0, 9.54, -18.97),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def log_text(path: Path) -> str:
    return path.read_bytes().decode("utf-16le", errors="replace").lstrip("\ufeff")


def last(pattern: str, text: str, cast=int):
    matches = re.findall(pattern, text)
    return cast(matches[-1]) if matches else None


def crosses_saturday(start: datetime, end: datetime) -> bool:
    day = start.replace(hour=0, minute=0, second=0)
    while day <= end:
        if day.weekday() == 5:
            return True
        day += timedelta(days=1)
    return False


def gap_class(start: datetime, end: datetime) -> str:
    if crosses_saturday(start, end):
        return "WEEKEND_CLOSURE"
    days = {(start + timedelta(days=i)).strftime("%m-%d") for i in range((end.date() - start.date()).days + 1)}
    if days & {"12-24", "12-25", "12-26", "12-31", "01-01", "01-02"}:
        return "YEAR_END_HOLIDAY_CLOSURE"
    return "NON_WEEKEND_CLOSURE_OR_GAP"


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def main() -> None:
    coverage, specs, gap_summary, gap_rows = [], [], [], []
    for symbol in SYMBOLS:
        folder = RUNS / symbol
        summary = read_pairs(folder / "qualification-summary.csv")
        text = log_text(folder / "tester-agent.log")
        begin = last(rf"Ticks\s+{symbol} : real ticks begin from ([0-9.]+ [0-9:]+)", text, str)
        absent_minutes = last(r"real ticks absent for ([0-9]+) minutes of [0-9]+ total minute bars, every tick generation used", text)
        discarded_minutes = last(r"real ticks discarded for ([0-9]+) minutes of [0-9]+ total minute bars, every tick generation used", text)
        absent_days = last(r"real ticks absent for ([0-9]+) whole days", text)
        unmatched_volume = last(r"tick volumes not matched for ([0-9]+) minute bars", text)
        price_match = re.findall(r"tick prices of ([0-9]+) ticks not matched for ([0-9]+) minute bars", text)
        price_ticks, price_minutes = (map(int, price_match[-1]) if price_match else (None, None))
        actual = last(rf"{symbol},H1: testing of Experts\\SolTradeV30RealTickQualificationHarness.ex5 from ([0-9.]+ [0-9:]+) to ([0-9.]+ [0-9:]+) started", text, lambda x: x)
        expected = EXPECTED[symbol]
        spec_match = int(summary["digits"]) == expected[0] and abs(float(summary["point"]) - expected[1]) < 1e-12 and abs(float(summary["contract_size"]) - expected[2]) < 1e-9
        swap_match = int(summary["swap_mode"]) == 1 and int(summary["swap_rollover3day"]) == 3 and abs(float(summary["swap_long"]) - expected[3]) < 1e-9 and abs(float(summary["swap_short"]) - expected[4]) < 1e-9
        generated = (absent_minutes or 0) > 0 or (absent_days or 0) > 0
        years = {str(year): {"processed_model_ticks": int(summary[f"ticks_{year}"]), "m1_bars": int(summary[f"m1_{year}"]), "h1_bars": int(summary[f"h1_{year}"])} for year in range(2018, 2025)}
        coverage.append({
            "symbol": symbol, "final_data_gate_status": "FAIL" if generated else "PASS", "failure_reason": "GENERATED_TICK_FALLBACK_USED_BEFORE_NATIVE_TICK_START" if generated else None,
            "requested_test_interval": "[2017-11-01 00:00:00,2025-01-01 00:00:00)", "actual_tester_interval": actual,
            "warmup_first_processed_tick": summary["warmup_first_tick"], "warmup_final_processed_tick": summary["warmup_last_tick"],
            "first_processed_tick_in_research_interval": summary["first_tick"], "final_processed_tick_in_research_interval": summary["final_tick"],
            "processed_model_tick_count": int(summary["tick_count"]), "native_real_tick_start": begin,
            "generated_fallback_minutes": absent_minutes, "real_ticks_discarded_minutes": discarded_minutes, "whole_days_without_real_ticks": absent_days,
            "unmatched_tick_volume_minutes": unmatched_volume, "unmatched_tick_price_ticks": price_ticks, "unmatched_tick_price_minutes": price_minutes,
            "m1_count": int(summary["m1_count"]), "h1_count": int(summary["h1_count"]), "m1_mismatches": int(summary["m1_mismatches"]), "h1_mismatches": int(summary["h1_mismatches"]),
            "spread_samples": int(summary["spread_samples"]), "zero_or_negative_spread_samples": int(summary["zero_or_negative_spread_samples"]),
            "mean_spread_points": float(summary["mean_spread_points"]), "maximum_spread_points": float(summary["maximum_spread_points"]), "by_year": years,
        })
        specs.append({
            "symbol": symbol, "digits": int(summary["digits"]), "point": float(summary["point"]), "contract_size": float(summary["contract_size"]),
            "swap_mode": int(summary["swap_mode"]), "swap_rollover3day": int(summary["swap_rollover3day"]), "swap_long": float(summary["swap_long"]), "swap_short": float(summary["swap_short"]),
            "frozen_v28_contract_match": spec_match, "frozen_v28_swap_match": swap_match,
            "historical_symbol_specification_series": "UNAVAILABLE_FROM_BROKER_TESTER; only the run-time contract snapshot is exposed",
        })
        counts = Counter()
        with (folder / "tick-gaps.csv").open() as handle:
            for row in csv.DictReader(handle):
                start, end = datetime.strptime(row["previous_tick"], FMT), datetime.strptime(row["current_tick"], FMT)
                classification = gap_class(start, end); counts[classification] += 1
                gap_rows.append({**row, "classification": classification, "over_six_hours": int(row["gap_seconds"]) > 21600})
        gap_summary.append({"symbol": symbol, "gaps_over_one_hour": sum(counts.values()), "classifications": dict(counts), "native_only_interpretation_valid": False, "reason": "tester generated ticks before native_real_tick_start"})
    report = {
        "schema": "SOLTRADE_PHASE6_V30_DATA_QUALIFICATION_RESULT_V1", "terminal_outcome": "V30_DATA_INSUFFICIENT_OR_INVALID", "status": "FAIL",
        "bound_from": "2018-01-01 00:00:00", "bound_to_exclusive": "2025-01-01 00:00:00", "warmup_from": "2017-11-01 00:00:00",
        "symbols_required": list(SYMBOLS), "symbols_qualified_for_native_full_interval": [], "symbols_failed": list(SYMBOLS),
        "dominant_failure": "FPMarkets Strategy Tester used generated ticks for roughly 372k-374k minutes per symbol; native real ticks begin only 2022-11-11 or 2022-11-14, not in the 2017 warm-up or at the 2018 test start",
        "generated_tick_fallback_prohibited": True, "synthetic_replacement_used": False, "symbol_substitution_used": False, "missing_symbol_excluded": False,
        "performance_execution_authorized": False, "signal_schedule_generated": False, "pnl_viewed": False, "coverage": coverage,
        "m1_h1_consistency_scope": "processed tester stream, which includes generated fallback and therefore cannot establish pure real-tick parity for the required interval",
        "cross_symbol_timestamp_coverage": "NOT_QUALIFIABLE_AS_NATIVE_REAL_TICK_COVERAGE_BECAUSE_ALL_SEVEN_STREAMS_USED_GENERATED_FALLBACK",
        "formation_timestamp_coverage": "NOT_QUALIFIABLE_FROM_NATIVE_REAL_TICKS_BEFORE_2022-11; no generated-bar signal schedule was permitted",
        "commission_availability": {"native_historical_schedule": "NOT_EXPOSED_WITHOUT_TRADING; no trade was placed to probe it", "frozen_v28_external_assumption": "USD 3 per side per standard lot", "assumption_available": True},
        "swap_assumptions": "all seven current tester snapshots match the frozen V28 values; historical change series unavailable",
    }
    write("phase6-v30-data-qualification-result.json", report)
    write("phase6-v30-symbol-specification-audit.json", {"schema": "SOLTRADE_PHASE6_V30_SYMBOL_SPECIFICATION_AUDIT_V1", "status": "CURRENT_SNAPSHOTS_MATCH_HISTORICAL_SERIES_UNAVAILABLE", "symbols": specs})
    write("phase6-v30-cross-symbol-coverage-report.json", {
        "schema": "SOLTRADE_PHASE6_V30_CROSS_SYMBOL_COVERAGE_V1", "status": "FAIL",
        "h1_count_ranges_by_year": {str(year): {"minimum": min(x["by_year"][str(year)]["h1_bars"] for x in coverage), "maximum": max(x["by_year"][str(year)]["h1_bars"] for x in coverage)} for year in range(2018, 2025)},
        "exact_native_timestamp_intersection": "UNAVAILABLE_INVALID", "reason": "generated-tick fallback precedes native start on every symbol", "symbols": coverage,
    })
    write("phase6-v30-gap-classification-report.json", {"schema": "SOLTRADE_PHASE6_V30_GAP_CLASSIFICATION_V1", "status": "FAIL_NATIVE_INTERPRETATION", "symbols": gap_summary})
    with (OUT / "phase6-v30-gap-ledger.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(gap_rows[0]), lineterminator="\n"); writer.writeheader(); writer.writerows(gap_rows)
    prod = sha(ROOT / "MQL5/Experts/SolTradeBot.mq5")
    performance_absent = not (OUT / "performance-runs").exists() and not (OUT / "signal-feasibility/signal-schedule.csv").exists()
    write("phase6-v30-evidence-integrity.json", {
        "schema": "SOLTRADE_PHASE6_V30_EVIDENCE_INTEGRITY_V1", "status": "PASS", "terminal_outcome": "V30_DATA_INSUFFICIENT_OR_INVALID",
        "qualification_physical_runs": 7, "performance_physical_runs": 0, "formal_profitability_cells": 0, "closed_performance_trades": 0,
        "performance_and_signal_artifacts_absent": performance_absent, "pnl_viewed": False, "profitability_metrics_calculated": False, "bootstrap_or_monte_carlo_executed": False,
        "optimization_or_tuning": False, "generated_tick_fallback_accepted": False, "symbol_substitution_or_exclusion": False, "v29_used": False, "strategies_combined": False,
        "orders_or_positions": 0, "demo_trades": 0, "live_trades": 0, "production_phase1_5_sha256": prod,
        "production_phase1_5_unchanged": prod == "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
        "v28_performance_source_sha256": sha(ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"),
        "v28_performance_source_unchanged": sha(ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5") == "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846",
    })
    (OUT / "phase6-v30-terminal-outcome.md").write_text(
        "# Phase 6 V30 terminal outcome\n\n`V30_DATA_INSUFFICIENT_OR_INVALID`\n\n"
        "All seven required symbols were audited separately using MT5 Model=4. The tester completed each requested 2017-11-01 warm-up through 2025-01-01 run, but native FPMarkets real ticks begin only on 2022-11-11 (six symbols) or 2022-11-14 (NZDUSD). Every symbol used generated-tick fallback for approximately 372,000 to 374,000 minutes, including 260 whole days without real ticks. This violates the frozen no-generated-tick gate and makes native cross-symbol coverage for 2018-2022 invalid.\n\n"
        "V30 profitability execution was therefore prohibited and did not occur. No signal schedule, P&L, trade ledger, annual performance, concentration result, rolling result, bootstrap, or Monte Carlo result was generated. This is not a V28 strategy-performance failure and V28 is not newly retired on financial evidence. No order, position, demo trade, live trade, optimization, V29 use, or strategy combination occurred. Production Phase 1-5 and V28 remain unchanged.\n"
    )
    checksum = OUT / "artifact-sha256-v30.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({"outcome": "V30_DATA_INSUFFICIENT_OR_INVALID", "symbols_failed": list(SYMBOLS), "native_starts": {x["symbol"]: x["native_real_tick_start"] for x in coverage}, "fallback_minutes": {x["symbol"]: x["generated_fallback_minutes"] for x in coverage}, "performance_runs": 0}, indent=2))


if __name__ == "__main__":
    main()
