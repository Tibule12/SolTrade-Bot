#!/usr/bin/env python3
"""Create the V30 immutable pre-data and pre-profitability contract."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v30-v28-historical-replication"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=False)
    v28_files = {
        "candidate_specification": V28 / "candidate-strategy-specification.json",
        "gate_manifest": V28 / "gate-manifest.json",
        "prerun_freeze": V28 / "prerun-freeze-manifest.json",
        "physical_run_plan": V28 / "physical-run-plan.json",
        "formal_cell_plan": V28 / "formal-cell-plan.json",
        "attempt2_amendment": V28 / "performance-harness-amendment-attempt2.json",
        "performance_source": ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5",
        "v28_signal_source": ROOT / "research/factor_momentum/SolTradeDollarFactorSignalHarness.mq5",
        "production_ea": ROOT / "MQL5/Experts/SolTradeBot.mq5",
    }
    exact = {key: {"path": str(path.relative_to(ROOT)), "sha256": sha(path)} for key, path in v28_files.items()}
    exact["performance_ex5"] = {
        "path": "/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5",
        "sha256": sha(Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")),
    }
    exact["v28_signal_ex5"] = {
        "path": "/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorSignalHarness.ex5",
        "sha256": sha(Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorSignalHarness.ex5")),
    }
    spec = json.loads((V28 / "candidate-strategy-specification.json").read_text())
    gates = json.loads((V28 / "gate-manifest.json").read_text())
    write("v30-v28-immutable-specification.json", {
        "schema": "SOLTRADE_PHASE6_V30_V28_IMMUTABLE_SPECIFICATION_V1",
        "source_phase": "V28",
        "source_terminal_commit": "af122b428bb03396b7ecac453d930f8cb19796fa",
        "source_terminal_tag": "phase6-v28-terminal",
        "strategy_identifier": spec["strategy_identifier"],
        "symbol_universe": spec["universe"],
        "orientation": spec["orientation"],
        "signal_generation": spec["formation"],
        "direction": spec["direction"],
        "rebalance_entry_exit": spec["rebalance"],
        "position_sizing_and_portfolio_risk": spec["risk"],
        "spread_and_execution": spec["execution"],
        "commission_swap_friction": spec["costs"],
        "normal_high_stress": {"NORMAL": 0.0, "HIGH": 0.5, "STRESS": 1.0},
        "execution_modes": {"NATIVE_NORMAL_EXECUTION": 0, "FIXED_DELAY_200_MS": 200},
        "historical_replication_interval": "[2018-01-01 00:00:00,2025-01-01 00:00:00)",
        "warmup_history_from": "2017-11-01 00:00:00",
        "first_required_formation_anchor": "2017-12 first Monday 09:00 broker-server time",
        "last_eligible_target_policy": "target is eligible only when its unchanged next-first-Monday exit is before 2025-01-01",
        "clean_segment_rule": "one continuous broker history segment; missing any seven-symbol exact anchor or recent H1 close skips the whole cohort and invalidates V30 qualification",
        "unchanged": True,
        "optimization": False,
        "v29_used": False,
    })
    write("v30-source-and-configuration-hash-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30_SOURCE_CONFIGURATION_HASH_FREEZE_V1",
        "exact_v28": exact,
        "authoritative_performance_source": "V28 attempt-2 serialized-rebalance source",
        "authoritative_performance_source_sha256": "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846",
        "authoritative_performance_ex5_sha256": "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca",
        "superseded_attempt1_not_eligible": True,
    })
    v30_harnesses = {
        "signal_source": ROOT / "research/factor_momentum/SolTradeV30HistoricalSignalHarness.mq5",
        "qualification_source": ROOT / "research/factor_momentum/SolTradeV30RealTickQualificationHarness.mq5",
        "signal_ex5": Path("/home/tibule12/.wine-fpmarkets/drive_c/v30/SolTradeV30HistoricalSignalHarness.ex5"),
        "qualification_ex5": Path("/home/tibule12/.wine-fpmarkets/drive_c/v30/SolTradeV30RealTickQualificationHarness.ex5"),
    }
    write("v30-harness-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30_HARNESS_FREEZE_V1",
        "purpose": {"signal": "date-bounded signal-only extraction of unchanged V28 rules", "qualification": "no-trade real-tick availability and consistency audit"},
        "artifacts": {key: {"path": str(path), "sha256": sha(path)} for key, path in v30_harnesses.items()},
        "compile_result": {"signal": "0 errors, 0 warnings", "qualification": "0 errors, 0 warnings"},
        "trading_logic_source": "unchanged V28 performance executable in v30-source-and-configuration-hash-freeze.json",
        "pnl_calculation": False,
        "orders_or_positions": 0,
    })
    write("v30-gate-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V30_GATE_MANIFEST_V1",
        "source_v28_gate_manifest_sha256": sha(V28 / "gate-manifest.json"),
        "outcomes": ["V30_HISTORICAL_REPLICATION_PASSED", "V30_HISTORICAL_REPLICATION_FAILED", "V30_DATA_INSUFFICIENT_OR_INVALID", "INVALID_TEST_EVIDENCE"],
        "sample_normal_native": {"continuous_closed": ">= 100", "BUY_closed": ">= 20", "SELL_closed": ">= 20", "each_symbol_closed": ">= 10"},
        "performance_every_cell": gates["performance_every_cell"],
        "concentration_every_cell": gates["concentration_every_cell"],
        "annual_consistency_per_cost_execution": {
            "scope": "fixed calendar-year exit attribution 2018 through 2024 from the continuous run",
            **gates["cross_dataset_per_cost_execution"],
        },
        "uncertainty": gates["uncertainty"],
        "additional_reporting_only": ["best_week", "best_month", "best_year", "top_5_trades", "top_10_trades", "rolling_12_month_profitability", "losing_year_count", "longest_negative_period", "symbol_currency_direction_contribution", "bootstrap", "monte_carlo"],
        "concentration_subperiod_formula": "same V28 elapsed-time quintile formula over the exact continuous interval",
        "all_mandatory": True,
        "no_gate_weakened": True,
        "failure_policy": "permanently retire V28 unchanged as period-specific or insufficiently robust; no rescue, tuning, demo or live",
    })
    runs = [
        {"run_number": 1, "run_id": "01-v30-2018-2024-native", "dataset": "V30_2018_2024_HISTORICAL", "history_from": "2017.11.01", "eligible_from": "2018.01.01 00:00:00", "eligible_to_exclusive": "2025.01.01 00:00:00", "execution_layer": "NATIVE_NORMAL_EXECUTION", "execution_mode": 0},
        {"run_number": 2, "run_id": "02-v30-2018-2024-delay200", "dataset": "V30_2018_2024_HISTORICAL", "history_from": "2017.11.01", "eligible_from": "2018.01.01 00:00:00", "eligible_to_exclusive": "2025.01.01 00:00:00", "execution_layer": "FIXED_DELAY_200_MS", "execution_mode": 200},
    ]
    write("v30-physical-run-plan.json", {"schema": "SOLTRADE_PHASE6_V30_PHYSICAL_RUN_PLAN_V1", "frozen_before_data_qualification": True, "underlying_real_tick_runs": 2, "runs": runs})
    cells = []
    for layer, source in (("NATIVE_NORMAL_EXECUTION", runs[0]["run_id"]), ("FIXED_DELAY_200_MS", runs[1]["run_id"])):
        for profile, multiplier in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0)):
            cells.append({"cell_id": f"V30_2018_2024_HISTORICAL-{profile}-{'NATIVE' if layer.startswith('NATIVE') else 'DELAY200'}", "dataset": "V30_2018_2024_HISTORICAL", "cost_profile": profile, "supplementary_multiplier": multiplier, "execution_layer": layer, "source_run": source})
    write("v30-formal-cell-plan.json", {"schema": "SOLTRADE_PHASE6_V30_FORMAL_CELL_PLAN_V1", "frozen_before_data_qualification": True, "continuous_cells": cells, "annual_attribution_years": list(range(2018, 2025)), "annual_attribution_basis": "exit calendar year; continuous equity and rules are never reset", "aggregation_order": "EXIT_TIME_ASCENDING_THEN_SYMBOL_ASCENDING", "starting_equity_usd": 10000.0, "risk_per_trade_percent": 0.5})
    write("v30-data-qualification-plan.json", {
        "schema": "SOLTRADE_PHASE6_V30_DATA_QUALIFICATION_PLAN_V1",
        "symbols": spec["universe"], "tester_model": 4, "model_name": "EVERY_TICK_BASED_ON_REAL_TICKS", "generated_tick_fallback": "PROHIBITED", "synthetic_or_substitute_data": "PROHIBITED",
        "warmup_from": "2017-11-01 00:00:00", "bound_from": "2018-01-01 00:00:00", "bound_to_exclusive": "2025-01-01 00:00:00",
        "audits": ["first/final tick", "tick count by symbol/year", "all gaps over one hour with deterministic session classification", "weekend and holiday closures", "tick-derived M1 and H1 versus tester series", "current broker symbol specification and year-by-year observed spread availability", "point/digits/contract size", "commission and swap assumption availability", "tester requested versus actual start", "cross-symbol H1 coverage", "every exact V28 formation timestamp", "300 H1-bar warmup"],
        "mandatory_pass": ["every symbol has real ticks in warmup and every year", "no tester log evidence of generated-tick fallback", "M1 and H1 mismatches equal zero", "point/digits/contract size equal frozen symbol contract", "spread samples exist in every year", "all exact seven-symbol V28 formation H1 timestamps exist", "at least 300 H1 bars precede the first entry", "no unexplained open-session gap longer than six hours", "requested and actual tester periods cover the required boundaries"],
        "data_failure_outcome": "V30_DATA_INSUFFICIENT_OR_INVALID", "performance_on_data_failure": "PROHIBITED",
    })
    seed_basis = sha(OUT / "v30-v28-immutable-specification.json") + sha(OUT / "v30-gate-manifest.json") + sha(OUT / "v30-physical-run-plan.json")
    write("v30-deterministic-seed-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V30_DETERMINISTIC_SEED_FREEZE_V1", "basis_sha256": hashlib.sha256(seed_basis.encode()).hexdigest(),
        "bootstrap_seed": int(hashlib.sha256((seed_basis + ":bootstrap").encode()).hexdigest()[:16], 16),
        "monte_carlo_seed": int(hashlib.sha256((seed_basis + ":monte_carlo").encode()).hexdigest()[:16], 16),
        "paths_each": 100000,
    })
    write("v30-prerun-freeze-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V30_PRERUN_FREEZE_MANIFEST_V1", "frozen_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "parent_commit": "439b8b01a33350c471e02d41c300ea4f2392e535", "historical_pnl_viewed": False, "data_qualification_started": False,
        "v28_modified": False, "parameters_tuned": False, "symbols_removed": False, "directions_removed": False, "v29_used": False, "strategies_combined": False, "optimization": False, "demo_trades": 0, "live_trades": 0,
        "manifest_hashes": {p.name: sha(p) for p in sorted(OUT.glob("*.json"))},
    })


if __name__ == "__main__":
    main()
