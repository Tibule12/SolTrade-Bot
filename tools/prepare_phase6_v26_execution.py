#!/usr/bin/env python3
"""Freeze the four V26 physical executions and twelve formal cells before P&L."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum"
EX5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v26/SolTradeRelativeStrengthPerformanceHarness.ex5")
DATASETS = (
    ("V26_2025_DEVELOPMENT", "2024.12.02", "2025.01.06 10:05:00", "2026.01.01 00:00:00", 204),
    ("V26_2026_PRESEAL_DEVELOPMENT", "2025.12.01", "2026.01.05 10:05:00", "2026.08.01 00:00:00", 116),
)
LAYERS = (("NATIVE_NORMAL_EXECUTION", 0, "NATIVE"), ("FIXED_DELAY_200_MS", 200, "DELAY200"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n")


def main() -> None:
    runs = []
    number = 0
    for layer, mode, suffix in LAYERS:
        for dataset, history, eligible, end, legs in DATASETS:
            number += 1
            run_id = f"{number:02d}-{dataset.lower().replace('_', '-')}-{suffix.lower()}"
            instance = f"V26-{dataset.replace('V26_', '')}-{suffix}"
            core = {"candidate": "FX_CROSS_SECTIONAL_MOMENTUM_3W_1W_TOP2_BOTTOM2_1_0", "dataset": dataset, "history_from": history, "eligible_from": eligible, "eligible_to_exclusive": end, "schedule_legs": legs, "execution_layer": layer, "execution_mode": mode, "model": 4, "optimization": False, "portfolio_initial_equity": 10000, "risk_per_leg_percent": 0.05}
            runs.append({"run_number": number, "run_id": run_id, "execution_instance_id": instance, "dataset": dataset, "history_from": history, "eligible_from": eligible, "eligible_to_exclusive": end, "expected_schedule_legs": legs, "schedule_file": f"SolTrade\\Phase6\\V26Signals\\{dataset}\\signal-schedule.csv", "execution_layer": layer, "execution_mode": mode, "output_subdirectory": f"performance-runs/{run_id}", "complete_run_configuration_sha256": hashlib.sha256(canonical(core)).hexdigest()})
    assert len(runs) == 4
    write("physical-run-plan.json", {"schema": "SOLTRADE_PHASE6_V26_PHYSICAL_RUN_PLAN_V1", "status": "FROZEN_BEFORE_PNL", "physical_run_count": 4, "real_tick_runs": 4, "run_order_locked": True, "runs": runs})
    cells = []
    for dataset, *_ in DATASETS:
        for layer, mode, suffix in LAYERS:
            run = next(x for x in runs if x["dataset"] == dataset and x["execution_layer"] == layer)
            for profile, multiplier in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0)):
                cells.append({"cell_id": f"{dataset}-{profile}-{suffix}", "dataset": dataset, "cost_profile": profile, "supplementary_multiplier": multiplier, "execution_layer": layer, "execution_mode": mode, "source_physical_run": run["run_id"], "synthetic_starting_equity_usd": 10000.0, "risk_per_leg_percent": 0.05, "aggregation_order": "EXIT_TIME_ASCENDING_THEN_SYMBOL_ASCENDING"})
    assert len(cells) == 12
    write("formal-cell-plan.json", {"schema": "SOLTRADE_PHASE6_V26_FORMAL_CELL_PLAN_V1", "status": "FROZEN_BEFORE_PNL", "formal_cell_count": 12, "cells": cells})
    write("performance-executable-freeze.json", {"schema": "SOLTRADE_PHASE6_V26_EXECUTABLE_FREEZE_V1", "status": "FROZEN_BEFORE_PNL", "source": "research/relative_strength/SolTradeRelativeStrengthPerformanceHarness.mq5", "source_sha256": sha(ROOT / "research/relative_strength/SolTradeRelativeStrengthPerformanceHarness.mq5"), "compiled_ex5_sha256": sha(EX5), "compiler_result": "0 errors, 0 warnings", "strategy_specification_sha256": sha(OUT / "candidate-strategy-specification.json"), "gate_manifest_sha256": sha(OUT / "gate-manifest.json"), "physical_run_plan_sha256": sha(OUT / "physical-run-plan.json"), "formal_cell_plan_sha256": sha(OUT / "formal-cell-plan.json"), "pnl_viewed": False, "run_1_started": False})
    print(json.dumps({"runs": 4, "cells": 12, "source_sha256": sha(ROOT / "research/relative_strength/SolTradeRelativeStrengthPerformanceHarness.mq5"), "ex5_sha256": sha(EX5)}, indent=2))


if __name__ == "__main__":
    main()
