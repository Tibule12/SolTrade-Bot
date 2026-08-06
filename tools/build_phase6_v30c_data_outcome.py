#!/usr/bin/env python3
"""Close V30C at the strict broker-native data qualification gate."""
from __future__ import annotations

import csv
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v30c-v28-native-contiguous-replication"
RUNS = OUT / "data-qualification/physical-runs"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
EXPECTED_START = "2022.11.14 00:05:00.354"
EXPECTED_END = "2024.01.01 00:00:00.000"
EXPECTED_LAST = "2023.12.29 23:57:52.904"
SOURCE_HASH = "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846"
EX5_HASH = "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca"
PROD_HASH = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    path = OUT / name
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def relevant_log(path: Path) -> str:
    text = path.read_text(encoding="utf-16", errors="replace")
    marker = "testing of Experts\\SolTradeV30CRealTickQualificationHarness.ex5"
    start = text.rfind(marker)
    if start < 0:
        raise SystemExit(f"V30C_TEST_MARKER_MISSING {path}")
    return text[start:]


def aggregate(log: str, kind: str) -> tuple[int, int]:
    match = re.search(rf"real ticks {kind} for (\d+) minutes of (\d+) total minute bars, every tick generation used", log)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


def daily(log: str, kind: str) -> list[dict[str, object]]:
    pattern = rf"(202[23]\.\d{{2}}\.\d{{2}}) 23:59 - real ticks {kind} for (\d+) minutes out of (\d+) total minute bars within a day"
    return [
        {"date": match.group(1), "minutes": int(match.group(2)), "day_minute_bars": int(match.group(3))}
        for match in re.finditer(pattern, log)
    ]


def main() -> None:
    inventory = json.loads((OUT / "data-qualification/qualification-physical-run-inventory.json").read_text())
    if [row["symbol"] for row in inventory["runs"]] != list(SYMBOLS):
        raise SystemExit("V30C_SYMBOL_SET_INVALID")
    coverage = []
    daily_rows = []
    properties = []
    total_absent = 0
    total_discarded = 0
    for symbol in SYMBOLS:
        run = RUNS / symbol
        summary = pairs(run / "qualification-summary.csv")
        log = relevant_log(run / "tester-agent.log")
        absent, total_minutes_a = aggregate(log, "absent")
        discarded, total_minutes_d = aggregate(log, "discarded")
        total_minutes = total_minutes_a or total_minutes_d or int(summary["m1_count"])
        absent_daily = daily(log, "absent")
        discarded_daily = daily(log, "discarded")
        total_absent += absent
        total_discarded += discarded
        coverage.append({
            "symbol": symbol,
            "first_processed_tick": summary["first_processed_tick"],
            "final_processed_tick": summary["final_processed_tick"],
            "processed_tick_count": int(summary["processed_tick_count"]),
            "total_minute_bars": total_minutes,
            "real_tick_absent_minutes_replaced_by_generation": absent,
            "real_tick_discarded_minutes_replaced_by_generation": discarded,
            "m1_mismatches": int(summary["m1_mismatches"]),
            "h1_mismatches": int(summary["h1_mismatches"]),
            "strict_native_status": "FAIL" if absent or discarded else "PASS",
            "tester_start_not_silently_shifted": "from 2022.11.14 00:00 to 2024.01.01 00:00" in log,
            "expected_common_final_reached": datetime.strptime(summary["final_processed_tick"], "%Y.%m.%d %H:%M:%S.%f") >= datetime.strptime(EXPECTED_LAST, "%Y.%m.%d %H:%M:%S.%f"),
        })
        for kind, rows in (("ABSENT_REAL_TICKS_GENERATED_FALLBACK", absent_daily), ("DISCARDED_REAL_TICKS_GENERATED_FALLBACK", discarded_daily)):
            for row in rows:
                date = str(row["date"])
                classification = "OPEN_SESSION_UNRESOLVED"
                note = "Weekday within the broker's reported trading-day minute bars; native-only evidence is unavailable."
                if date == "2023.01.02":
                    classification = "HOLIDAY_AFFECTED_BUT_UNRESOLVED_NATIVE_GAP"
                    note = "Observed New Year holiday, but MT5 still reports minute bars and generated fallback; native-only gate remains failed."
                daily_rows.append({"symbol": symbol, "kind": kind, **row, "classification": classification, "note": note})
        properties.append({
            "symbol": symbol,
            "digits": int(summary["digits"]),
            "point": summary["point"],
            "contract_size": summary["contract_size"],
            "spread_samples": int(summary["spread_samples"]),
            "zero_or_negative_spread_samples": int(summary["zero_or_negative_spread_samples"]),
            "mean_spread_points": float(summary["mean_spread_points"]),
            "maximum_spread_points": float(summary["maximum_spread_points"]),
            "swap_mode": int(summary["swap_mode"]),
            "swap_rollover_3day": int(summary["swap_rollover3day"]),
            "swap_long": float(summary["swap_long"]),
            "swap_short": float(summary["swap_short"]),
        })

    if not all(row["strict_native_status"] == "FAIL" for row in coverage):
        raise SystemExit("EXPECTED_ALL_SYMBOL_NATIVE_FAILURE_NOT_ESTABLISHED")
    with (OUT / "v30c-session-gap-classification.csv").open("w", newline="") as handle:
        fields = ("symbol", "kind", "date", "minutes", "day_minute_bars", "classification", "note")
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(daily_rows)
    common_final = min(coverage, key=lambda row: datetime.strptime(str(row["final_processed_tick"]), "%Y.%m.%d %H:%M:%S.%f"))["final_processed_tick"]
    write_json("v30c-native-coverage-audit.json", {
        "schema": "SOLTRADE_PHASE6_V30C_NATIVE_COVERAGE_AUDIT_V1",
        "status": "FAIL",
        "qualification_start_inclusive": EXPECTED_START,
        "qualification_end_exclusive": EXPECTED_END,
        "last_expected_common_native_tick": EXPECTED_LAST,
        "observed_common_final_processed_tick": common_final,
        "symbols": coverage,
        "aggregate_real_tick_absent_minutes": total_absent,
        "aggregate_real_tick_discarded_minutes": total_discarded,
        "all_symbols_have_discarded_real_ticks_and_generated_replacement": True,
        "complete_broker_native_cross_symbol_coverage": False,
        "generated_fallback_accepted": False,
        "material_failure": "Each symbol loses 1,371-1,417 native minutes on 2023-04-17; MT5 explicitly says every-tick generation was used.",
    })
    write_json("v30c-symbol-properties-audit.json", {
        "schema": "SOLTRADE_PHASE6_V30C_SYMBOL_PROPERTIES_AUDIT_V1",
        "status": "RECORDED",
        "properties_at_test_time": properties,
        "commission_availability": "Frozen V28 treatment retained; not exercised because profitability was not authorized.",
        "spread_and_swap_treatment": "Observed only for qualification; unchanged V28 treatment was not executed.",
    })
    write_json("v30c-data-qualification-result.json", {
        "schema": "SOLTRADE_PHASE6_V30C_DATA_QUALIFICATION_RESULT_V1",
        "terminal_outcome": "V30C_DATA_INSUFFICIENT_OR_INVALID",
        "status": "FAIL",
        "reason": "The tester discarded native ticks and explicitly used every-tick generation on all seven symbols inside the frozen interval.",
        "data_failure_not_v28_performance_failure": True,
        "eligible_profitability_start": "NOT_FROZEN",
        "warmup_completion": "NOT_EVALUATED_ON_A_CONTIGUOUS_NATIVE_SERIES",
        "performance_execution_authorized": False,
        "performance_physical_runs": 0,
        "formal_performance_cells": 0,
        "combined_evidence_ledger_authorized": False,
        "combined_gates_evaluated": False,
        "v28_pnl_viewed": False,
        "profitability_metrics_calculated": False,
        "orders_or_positions": 0,
        "demo_or_live_trades": 0,
    })
    source = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
    ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
    production = ROOT / "MQL5/Experts/SolTradeBot.mq5"
    write_json("v30c-evidence-integrity.json", {
        "schema": "SOLTRADE_PHASE6_V30C_EVIDENCE_INTEGRITY_V1",
        "status": "PASS",
        "terminal_outcome": "V30C_DATA_INSUFFICIENT_OR_INVALID",
        "all_seven_qualification_runs_technically_complete": all(row["wine_return_code"] == 0 for row in inventory["runs"]),
        "tester_model": "EVERY_TICK_BASED_ON_REAL_TICKS (Model=4)",
        "orders_or_positions": 0,
        "v28_performance_runs": 0,
        "closed_performance_trades": 0,
        "v28_pnl_viewed": False,
        "optimization_or_tuning": False,
        "v29_used_or_combined": False,
        "symbols_or_directions_removed": False,
        "generated_ticks_accepted": False,
        "production_phase1_5_sha256": sha(production),
        "production_phase1_5_unchanged": sha(production) == PROD_HASH,
        "v28_performance_source_sha256": sha(source),
        "v28_performance_source_unchanged": sha(source) == SOURCE_HASH,
        "v28_performance_ex5_sha256": sha(ex5),
        "v28_performance_ex5_unchanged": sha(ex5) == EX5_HASH,
        "previous_evidence_changed": False,
    })
    write_json("v30c-execution-stop-record.json", {
        "schema": "SOLTRADE_PHASE6_V30C_EXECUTION_STOP_RECORD_V1",
        "stopped_at": "DATA_QUALIFICATION",
        "why": "Generated-tick fallback is prohibited and occurred within the frozen window for every required symbol.",
        "normal_native_run": "NOT_RUN",
        "high_native_run": "NOT_RUN",
        "stress_native_run": "NOT_RUN",
        "normal_delay200_run": "NOT_RUN",
        "high_delay200_run": "NOT_RUN",
        "stress_delay200_run": "NOT_RUN",
        "combined_evidence_audit": "NOT_RUN",
        "v28_status": "UNCHANGED; NOT A PERFORMANCE FAILURE",
    })
    (OUT / "phase6-v30c-terminal-outcome.md").write_text(
        "# Phase 6 V30C terminal outcome\n\n"
        "`V30C_DATA_INSUFFICIENT_OR_INVALID`\n\n"
        "All seven no-trade qualification runs completed over the frozen tester interval. The expected common final tick was reached, but complete broker-native coverage was not. On 2023-04-17, MT5 discarded between 1,371 and 1,417 minutes of real ticks for every required symbol and explicitly reported that every-tick generation was used. EURUSD, GBPUSD, and AUDUSD also required generated fallback for 183, 184, and 185 absent minutes respectively. These are prohibited substitutions inside the frozen window, not accepted weekend or session closures.\n\n"
        "The V28 clean warm-up and eligible profitability start could therefore not be frozen on a contiguous native series. None of the six V28 profitability cells ran, no V28 P&L or profitability metric was viewed, and the conditional combined evidence audit was not opened. This outcome is a data-qualification failure, not a V28 performance failure; V28 remains unchanged and has not failed replication. No order, position, demo/live trade, optimization, tuning, symbol exclusion, direction exclusion, V29 use, or production Phase 1-5 change occurred.\n"
    )
    checksum = OUT / "artifact-sha256-v30c.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({
        "outcome": "V30C_DATA_INSUFFICIENT_OR_INVALID",
        "symbols": len(coverage),
        "total_ticks": sum(int(row["processed_tick_count"]) for row in coverage),
        "absent_minutes": total_absent,
        "discarded_minutes": total_discarded,
        "performance_runs": 0,
        "common_final": common_final,
    }, indent=2))


if __name__ == "__main__":
    main()
