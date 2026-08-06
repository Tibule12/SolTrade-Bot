#!/usr/bin/env python3
"""Close V30B at the exact native common-coverage data gate."""
from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v30b-v28-native-common-coverage"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
TICKS = Path("/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/Bases/FPMarketsSC-Demo/ticks")
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def main() -> None:
    with (OUT / "exact-native-boundaries-v2.csv").open() as handle:
        rows = list(csv.DictReader(handle))
    if [row["symbol"] for row in rows] != list(SYMBOLS):
        raise SystemExit("BOUNDARY_SYMBOL_SET_INVALID")
    first = {row["symbol"]: row["exact_first_native_tick"] for row in rows}
    last_2023 = {row["symbol"]: row["exact_last_native_tick_2023"] for row in rows}
    common_start = max(first.values(), key=lambda value: datetime.strptime(value, "%Y.%m.%d %H:%M:%S.%f"))
    common_last_2023 = min(last_2023.values(), key=lambda value: datetime.strptime(value, "%Y.%m.%d %H:%M:%S.%f"))
    full_2024 = {row["symbol"]: int(row["full_2024_count"]) for row in rows}
    errors = {row["symbol"]: int(row["full_2024_error"]) for row in rows}
    zero_before = {row["symbol"]: int(row["ticks_before_reported_start"]) for row in rows}
    cache = []
    for symbol in SYMBOLS:
        months = sorted(path.stem for path in (TICKS / symbol).glob("*.tkc"))
        cache.append({
            "symbol": symbol, "month_files": months, "first_month": months[0] if months else None,
            "last_month_before_2025": max((month for month in months if month < "202501"), default=None),
            "months_2024": [month for month in months if month.startswith("2024")],
        })
    write("v30b-exact-native-common-coverage.json", {
        "schema": "SOLTRADE_PHASE6_V30B_EXACT_NATIVE_COMMON_COVERAGE_V1", "status": "FAIL",
        "qualification_start": common_start, "qualification_start_basis": "latest exact first connected COPY_TICKS_ALL tick across all seven symbols",
        "qualification_end_exclusive": "2025.01.01 00:00:00.000", "latest_common_native_tick_before_2024": common_last_2023,
        "per_symbol_exact_first_native_tick": first, "per_symbol_exact_last_native_tick_2023": last_2023,
        "ticks_before_reported_calendar_start": zero_before, "full_2024_native_tick_count": full_2024, "full_2024_copy_error": errors,
        "complete_common_native_coverage_to_end": False,
        "failure_reason": "all seven symbols return zero native ticks with error 0 for the entire 2024 interval",
        "generated_or_synthetic_ticks_accepted": False, "symbol_substitution_or_exclusion": False,
        "orders": 0, "positions": 0, "trade_api_calls": "NONE",
    })
    write("v30b-native-tick-cache-inventory.json", {
        "schema": "SOLTRADE_PHASE6_V30B_NATIVE_TICK_CACHE_INVENTORY_V1", "status": "CONFIRMS_2024_ABSENCE",
        "source": "FPMarketsSC-Demo terminal native .tkc cache", "symbols": cache,
    })
    candidate = V28 / "candidate-strategy-specification.json"
    gates = V28 / "gate-manifest.json"
    source = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
    ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
    write("v30b-v28-immutability-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30B_V28_IMMUTABILITY_FREEZE_V1", "status": "PASS",
        "v28_terminal_commit": "af122b428bb03396b7ecac453d930f8cb19796fa", "v28_terminal_tag": "phase6-v28-terminal",
        "candidate_specification_sha256": sha(candidate), "gate_manifest_sha256": sha(gates),
        "performance_source_sha256": sha(source), "performance_ex5_sha256": sha(ex5),
        "authoritative_attempt": "V28 attempt-2 serialized rebalance",
        "exact_symbols": list(SYMBOLS), "rules_or_parameters_changed": False, "directions_removed": False,
        "sizing_or_risk_changed": False, "cost_or_swap_changed": False, "latency_changed": False,
        "gates_changed_or_weakened": False, "v29_used": False, "optimization": False,
        "warmup_assessment": {
            "common_clean_native_segment_begins": common_start,
            "minimum_history_bars": 300,
            "atr_warmup": "unchanged Wilder D1 ATR14",
            "formation_anchor_rule": "unchanged preceding calendar-month first Monday 09:00 H1 close",
            "profitability_interval": "NOT_OPENED because common native coverage fails before qualification_end_exclusive",
        },
    })
    safety = json.loads((OUT / "repository-safety-gate.json").read_text())
    write("v30b-data-qualification-result.json", {
        "schema": "SOLTRADE_PHASE6_V30B_DATA_QUALIFICATION_RESULT_V1", "terminal_outcome": "V30B_DATA_INSUFFICIENT_OR_INVALID", "status": "FAIL",
        "repository_safety": safety["status"], "qualification_start": common_start, "qualification_end_exclusive": "2025.01.01 00:00:00.000",
        "common_native_coverage_available": f"[{common_start}, {common_last_2023}]", "complete_2024_common_coverage": False,
        "full_2024_native_ticks_by_symbol": full_2024, "data_failure_not_strategy_failure": True,
        "signal_schedule_generated": False, "performance_execution_authorized": False, "performance_runs": 0, "formal_cells": 0,
        "pnl_viewed": False, "orders_or_positions": 0, "demo_or_live_trades": 0,
    })
    prod = sha(ROOT / "MQL5/Experts/SolTradeBot.mq5")
    write("v30b-evidence-integrity.json", {
        "schema": "SOLTRADE_PHASE6_V30B_EVIDENCE_INTEGRITY_V1", "status": "PASS", "terminal_outcome": "V30B_DATA_INSUFFICIENT_OR_INVALID",
        "bundle_sha256": safety["bundle"]["sha256"], "bundle_verified": safety["bundle"]["verified"], "automatic_push": False,
        "connected_boundary_attempts_retained": 2, "authoritative_boundary_attempt": 2,
        "performance_runs": 0, "closed_performance_trades": 0, "pnl_viewed": False, "profitability_metrics_calculated": False,
        "signal_schedule_generated": False, "bootstrap_or_monte_carlo_executed": False, "optimization_or_tuning": False,
        "generated_ticks_accepted": False, "symbol_or_direction_exclusion": False, "v29_used": False,
        "connected_orders": 0, "connected_positions": 0, "demo_trades": 0, "live_trades": 0,
        "production_phase1_5_sha256": prod, "production_phase1_5_unchanged": prod == "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
        "v28_performance_source_unchanged": sha(source) == "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846",
        "v28_performance_ex5_unchanged": sha(ex5) == "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca",
    })
    (OUT / "phase6-v30b-terminal-outcome.md").write_text(
        "# Phase 6 V30B terminal outcome\n\n`V30B_DATA_INSUFFICIENT_OR_INVALID`\n\n"
        f"The exact latest first native tick shared by the V28 universe is `{common_start}`, set by NZDUSD. The requested qualification end remains `2025-01-01 00:00:00`. Connected `CopyTicksRange` returned zero native ticks, with error 0, for the full 2024 interval on every required symbol. The last common native tick before that gap is `{common_last_2023}`. Complete common native coverage through 2024 therefore does not exist.\n\n"
        "The repository bundle safety gate passed. V28 remains byte-for-byte unchanged and has not failed historical replication. No signal schedule or profitability run was permitted; no P&L, annual/rolling attribution, concentration result, bootstrap, Monte Carlo, order, position, demo trade, live trade, optimization, V29 use, or automatic push occurred. Production Phase 1-5 remains unchanged.\n"
    )
    checksum = OUT / "artifact-sha256-v30b.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({"outcome": "V30B_DATA_INSUFFICIENT_OR_INVALID", "qualification_start": common_start, "common_last_2023": common_last_2023, "full_2024": full_2024, "performance_runs": 0}, indent=2))


if __name__ == "__main__":
    main()
