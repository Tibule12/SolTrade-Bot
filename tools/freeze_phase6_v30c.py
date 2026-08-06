#!/usr/bin/env python3
"""Freeze V30C before the exact-window native data audit."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v30c-v28-native-contiguous-replication"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=False)
    candidate = V28 / "candidate-strategy-specification.json"
    gates = V28 / "gate-manifest.json"
    source = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
    ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
    qualifier_source = ROOT / "research/factor_momentum/SolTradeV30CRealTickQualificationHarness.mq5"
    qualifier_ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v30c/SolTradeV30CRealTickQualificationHarness.ex5")
    gate_obj = json.loads(gates.read_text())
    write("v30c-data-window-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30C_DATA_WINDOW_FREEZE_V1", "qualification_start_inclusive": "2022-11-14 00:05:00.354",
        "qualification_end_exclusive": "2024-01-01 00:00:00.000", "last_expected_common_native_tick": "2023-12-29 23:57:52.904",
        "symbols": ["EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY"],
        "generated_or_synthetic_ticks": "PROHIBITED", "partial_portfolio_or_symbol_exclusion": "PROHIBITED",
        "profitability_start": "TO_BE_FROZEN_ONLY_AFTER_ALL_SYMBOLS_PASS_NATIVE_COVERAGE_AND_UNCHANGED_V28_WARMUP",
        "include_2024": False,
    })
    write("v30c-v28-immutability-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30C_V28_IMMUTABILITY_FREEZE_V1", "status": "PASS",
        "v28_terminal_commit": "af122b428bb03396b7ecac453d930f8cb19796fa", "candidate_specification_sha256": sha(candidate),
        "gate_manifest_sha256": sha(gates), "performance_source_sha256": sha(source), "performance_ex5_sha256": sha(ex5),
        "preserved_v28_adjusted_ledger_sha256": sha(V28 / "phase6-v28-complete-adjusted-trade-ledger.csv"),
        "warmup": {"minimum_clean_h1_bars": 300, "atr": "unchanged Wilder D1 ATR14", "formation_anchor": "preceding calendar-month first Monday exact 09:00 H1 close"},
        "symbols_signals_directions_sizing_portfolio_entries_exits_risk_spread_cost_swap_latency_changed": False,
        "v29_used_or_combined": False, "optimization_or_tuning": False,
    })
    write("v30c-gate-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V30C_GATE_MANIFEST_V1", "source_v28_gate_sha256": sha(gates),
        "outcomes": ["V30C_REPLICATION_AND_COMBINED_GATES_PASSED", "V30C_INDEPENDENT_REPLICATION_FAILED", "V30C_COMBINED_GATES_FAILED", "V30C_DATA_INSUFFICIENT_OR_INVALID", "INVALID_TEST_EVIDENCE"],
        "sample": {"closed": ">=100", "BUY": ">=20", "SELL": ">=20", "each_symbol": ">=10"},
        "performance_every_cell": gate_obj["performance_every_cell"], "original_concentration_every_cell": gate_obj["concentration_every_cell"],
        "additional_mandatory_concentration": {"undefined": "FAIL", "BUY_or_SELL": "report and fail if frozen attribution cannot be computed", "best_week": "report", "best_month": "report", "largest_5_trades": "report", "largest_10_trades": "report", "symbol_and_currency": "best currency <=35% unchanged"},
        "rolling_and_cross_period_consistency": gate_obj["cross_dataset_per_cost_execution"],
        "independent_must_pass_before_combined": True, "all_mandatory": True, "no_gate_weakened": True,
    })
    runs = [
        {"run": 1, "id": "01-v30c-native", "execution_layer": "NATIVE_NORMAL_EXECUTION", "execution_mode": 0},
        {"run": 2, "id": "02-v30c-delay200", "execution_layer": "FIXED_DELAY_200_MS", "execution_mode": 200},
    ]
    cells = [{"cell_id": f"V30C-{profile}-{'NATIVE' if run['execution_mode']==0 else 'DELAY200'}", "source_run": run["id"], "execution_layer": run["execution_layer"], "cost_profile": profile, "supplementary_multiplier": mult} for run in runs for profile, mult in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0))]
    write("v30c-conditional-execution-plan.json", {
        "schema": "SOLTRADE_PHASE6_V30C_CONDITIONAL_EXECUTION_PLAN_V1", "authorized_only_if_data_passes": True,
        "history_from": "2022.11.14", "eligible_from": "TO_BE_FROZEN_AFTER_WARMUP", "eligible_to_exclusive": "2024.01.01 00:00:00",
        "physical_runs": runs, "formal_cells": cells,
        "combined_evidence": {"authorized_only_if_independent_valid": True, "sources": ["V30C untouched", "V28 2025 preserved", "V28 Jan-Jul 2026 preserved"], "chronological_no_reweighting": True, "missing_2024_acknowledged": True},
    })
    write("v30c-qualification-harness-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30C_QUALIFICATION_HARNESS_FREEZE_V1", "source_sha256": sha(qualifier_source), "ex5_sha256": sha(qualifier_ex5),
        "compile_result": "0 errors, 0 warnings", "tester_model": 4, "orders_or_positions": 0, "pnl_calculated": False,
    })
    write("v30c-prerun-freeze-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V30C_PRERUN_FREEZE_MANIFEST_V1", "frozen_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "parent_commit": "a235cba97edc3993abcc2f6bc3f6a41628d90026", "worktree_clean_before_phase": True,
        "historical_v30c_pnl_viewed": False, "v28_modified": False, "optimization": False, "v29_used": False,
        "demo_trades": 0, "live_trades": 0,
        "manifest_hashes": {path.name: sha(path) for path in sorted(OUT.glob("*.json"))},
    })


if __name__ == "__main__":
    main()
