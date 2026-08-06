#!/usr/bin/env python3
"""Create the immutable V31 profitability and combined-evidence freeze."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: dict) -> None:
    path = OUT / name
    if path.exists():
        raise SystemExit(f"REFUSE_EXISTING_FREEZE_{name}")
    path.write_text(json.dumps(value, indent=2) + "\n")


def main() -> None:
    signal_status = json.loads((OUT / "signal-generation/signal-generation-status.json").read_text())
    qualification = json.loads((OUT / "data-qualification/qualification-physical-run-inventory.json").read_text())
    raw = json.loads((OUT / "v31-raw-qualification-summary.json").read_text())
    normalized = json.loads((OUT / "v31-normalized-data-manifest.json").read_text())
    source_metadata = json.loads((OUT / "v31-source-metadata-manifest.json").read_text())
    if signal_status.get("status") != "PASS" or signal_status.get("signals") != 574 or qualification.get("status") != "PASS" or raw.get("status") != "PASS" or normalized.get("status") != "PASS" or source_metadata.get("status") != "PASS":
        raise SystemExit("V31_PREPROFITABILITY_EVIDENCE_NOT_PASS")
    gates = {
        "schema": "SOLTRADE_PHASE6_V31_GATE_MANIFEST_V1",
        "source_v28_gate_manifest_sha256": sha(V28 / "gate-manifest.json"),
        "source_v30_gate_manifest_sha256": sha(ROOT / "reports/backtests/phase6-v30-v28-historical-replication/v30-gate-manifest.json"),
        "source_v30c_gate_manifest_sha256": sha(ROOT / "reports/backtests/phase6-v30c-v28-native-contiguous-replication/v30c-gate-manifest.json"),
        "outcomes": ["V31_EXTERNAL_REPLICATION_AND_COMBINED_GATES_PASSED", "V31_EXTERNAL_REPLICATION_FAILED", "V31_COMBINED_GATES_FAILED", "V31_DATA_INSUFFICIENT_OR_INVALID", "INVALID_TEST_EVIDENCE"],
        "sample_normal_native": {"continuous_closed": ">= 100", "BUY_closed": ">= 20", "SELL_closed": ">= 20", "each_symbol_closed": ">= 10"},
        "performance_every_cell": {
            "NORMAL": {"profit_factor": "> 1.15", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "< 8"},
            "HIGH": {"profit_factor": ">= 1.05", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "<= 10"},
            "STRESS": {"profit_factor": ">= 1.00", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "<= 12"},
        },
        "concentration_every_cell": {"best_trade_percent": "<= 15", "best_foreign_currency_percent": "<= 35", "best_of_five_elapsed_time_subperiods_percent": "<= 40", "undefined": "FAIL"},
        "symbol_concentration": "mandatory attribution; no numeric symbol threshold exists in the frozen V28 gate manifest and none is invented",
        "direction_concentration": "BUY and SELL counts and contributions must be computable; sample minima apply; no new directional percentage threshold is invented",
        "annual_cross_period_consistency_per_cost_execution": {"expectancy_min_div_max": ">= 0.35", "annualized_return_min_div_max": ">= 0.35", "profit_factor_range": "<= 0.50", "losing_year_count": "0 through the requirement that the ratios be defined and positive"},
        "rolling_12_month_consistency_per_cost_execution": {"expectancy_min_div_max": ">= 0.35", "annualized_return_min_div_max": ">= 0.35", "profit_factor_range": "<= 0.50", "window": "trailing 365 days at each month-end from 2019-01 through 2024-12"},
        "native_delay_consistency_per_cost": {"expectancy_min_div_max": ">= 0.35", "annualized_return_min_div_max": ">= 0.35", "profit_factor_range": "<= 0.50"},
        "mandatory_reporting_without_new_threshold": ["best_week concentration", "best_month concentration", "best_year concentration", "largest five trades", "largest ten trades", "BUY and SELL contribution", "symbol and currency contribution", "longest negative period"],
        "uncertainty": {"bootstrap_paths": 100000, "monte_carlo_paths": 100000, "reporting_only": True},
        "independent_must_pass": True,
        "all_numeric_frozen_gates_mandatory": True,
        "undefined_ratios_fail_closed": True,
        "no_gate_weakened": True,
    }
    write("v31-gate-manifest.json", gates)
    runs = [
        {"run_number": 1, "run_id": "01-v31-external-2018-2024-native", "dataset": "V31_EXTERNAL_2018_2024", "execution_layer": "NATIVE_NORMAL_EXECUTION", "execution_mode": 0},
        {"run_number": 2, "run_id": "02-v31-external-2018-2024-delay200", "dataset": "V31_EXTERNAL_2018_2024", "execution_layer": "FIXED_DELAY_200_MS", "execution_mode": 200},
    ]
    write("v31-physical-run-plan.json", {"schema": "SOLTRADE_PHASE6_V31_PHYSICAL_RUN_PLAN_V1", "frozen_before_profitability": True, "history_from_server_civil": "2018.01.01", "eligible_from_server_civil": "2018.02.05 10:05:00", "eligible_to_exclusive_server_civil": "2025.01.01 00:00:00", "signals": 574, "runs": runs})
    cells = []
    for run in runs:
        for profile, multiplier in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0)):
            cells.append({"cell_id": f"V31_EXTERNAL_2018_2024-{profile}-{'NATIVE' if run['execution_mode'] == 0 else 'DELAY200'}", "dataset": run["dataset"], "cost_profile": profile, "supplementary_multiplier": multiplier, "execution_layer": run["execution_layer"], "source_run": run["run_id"]})
    write("v31-formal-cell-plan.json", {"schema": "SOLTRADE_PHASE6_V31_FORMAL_CELL_PLAN_V1", "frozen_before_profitability": True, "starting_equity_usd": 10000.0, "risk_per_trade_percent": 0.5, "aggregation_order": "EXIT_TIME_ASCENDING_THEN_SYMBOL_ASCENDING", "cells": cells})
    schedule = OUT / "signal-generation/signal-schedule.csv"
    seed_basis = hashlib.sha256((sha(schedule) + sha(OUT / "v31-gate-manifest.json") + sha(V28 / "candidate-strategy-specification.json")).encode()).hexdigest()
    seeds = {"basis_sha256": seed_basis, "bootstrap_seed": int(hashlib.sha256((seed_basis + ":bootstrap").encode()).hexdigest()[:16], 16), "monte_carlo_seed": int(hashlib.sha256((seed_basis + ":monte-carlo").encode()).hexdigest()[:16], 16)}
    write("v31-profitability-prerun-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V31_PROFITABILITY_PRERUN_FREEZE_V1",
        "classification": "INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION",
        "cost_model": "EXTERNAL_PRICE_FEED_WITH_FROZEN_CONTROLLED_COST_MODEL",
        "signal_schedule_sha256": sha(schedule),
        "signal_count": 574,
        "cohort_count": 82,
        "raw_manifest_sha256": raw["raw_manifest_sha256"],
        "source_metadata_manifest_sha256": sha(OUT / "v31-source-metadata-manifest.json"),
        "normalized_manifest_sha256": sha(OUT / "v31-normalized-data-manifest.json"),
        "qualification_inventory_sha256": sha(OUT / "data-qualification/qualification-physical-run-inventory.json"),
        "v28_candidate_specification_sha256": sha(V28 / "candidate-strategy-specification.json"),
        "v28_gate_manifest_sha256": sha(V28 / "gate-manifest.json"),
        "v31a_adapter_executable_sha256": "92bf94431803c0213b1d796c3a412b581978c680869b20de299bcef90ec8e886",
        "performance_runner_sha256": sha(ROOT / "tools/run_phase6_v31_external_performance.py"),
        "evidence_analyzer_sha256": sha(ROOT / "tools/build_phase6_v31_evidence.py"),
        "terminal_finalizer_sha256": sha(ROOT / "tools/finalize_phase6_v31_external.py"),
        "commission_usd_per_side_per_standard_lot": 3.0,
        "historical_spread": "imported Dukascopy bid/ask",
        "swap": "frozen FP Markets V28 custom-symbol properties",
        "supplementary_friction_multipliers": {"NORMAL": 0.0, "HIGH": 0.5, "STRESS": 1.0},
        "physical_runs": 2,
        "formal_cells": 6,
        "seeds": seeds,
        "combined_evidence": {"external": "V31 2018-2024 unchanged", "preserved": ["V28 2025", "V28 January-July 2026"], "weights": "original 0.5% equity risk per leg and chronological ordering; no reweighting", "independent_failure_cannot_be_overridden": True},
        "tester_end_prevents_post_2024_access": "2025.01.01 server civil exclusive",
        "adapter_research_cutoff_input": "2026.08.01 retained solely to satisfy the already-equivalent V31A executable preflight; tester and EligibleTo both stop at 2025.01.01",
        "profitability_started": False,
        "pnl_viewed": False,
        "optimization": False,
        "demo_or_live_trades": 0,
    })
    print(json.dumps({"status": "FROZEN", "schedule_sha256": sha(schedule), "seeds": seeds}, sort_keys=True))


if __name__ == "__main__":
    main()
