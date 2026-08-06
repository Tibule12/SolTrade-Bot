#!/usr/bin/env python3
"""Materialize the frozen V25 run/cell plans without reading signal or P&L data."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v25-fx-fixing-inventory-reversal"
V23_PARTITIONS = ROOT / "reports/backtests/phase6-v23-v31-development-screen/phase6-v23-data-partition-manifest.json"
SPEC = OUT / "candidate-strategy-specification.json"
PROFILES = (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0))
LAYERS = (("NATIVE_NORMAL_EXECUTION", 0, "NATIVE"), ("FIXED_DELAY_200_MS", 200, "DELAY200"))


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n")


def main() -> None:
    source = json.loads(V23_PARTITIONS.read_text())
    segments = []
    for item in source["segments"]:
        dataset = "V25_2025_DEVELOPMENT_REUSE" if item["segment_id"].startswith("2025") else "V25_2026_PRESEAL_DEVELOPMENT"
        segments.append({
            "segment_id": item["segment_id"],
            "formal_dataset": dataset,
            "classification": "DEVELOPMENT_EVIDENCE",
            "reset_at": item["reset_at"],
            "eligible_from": item["eligible_from"],
            "eligible_to_exclusive": item["eligible_to_exclusive"],
            "minimum_clean_segment_local_bars": 300,
            "segment_local_completed_h1_bars": item["segment_local_completed_h1_bars"],
            "indicator_eligible_h1_bars": item["indicator_eligible_h1_bars"],
            "first_indicator_eligible_h1": item["first_indicator_eligible_h1"],
            "last_indicator_eligible_h1": item["last_indicator_eligible_h1"],
            "state_carried_across_boundary": False,
        })
    write("phase6-v25-data-partition-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V25_DATA_PARTITIONS_V1",
        "status": "FROZEN_BEFORE_RUN_1",
        "source": str(V23_PARTITIONS.relative_to(ROOT)),
        "source_sha256": sha(V23_PARTITIONS),
        "research_cutoff_exclusive": "2026.08.01 00:00:00",
        "post_seal_data_permitted": False,
        "qualified_physical_segments": len(segments),
        "segments": segments,
    })

    runs = []
    number = 0
    for layer, mode, suffix in LAYERS:
        for segment in segments:
            for profile, multiplier in PROFILES:
                number += 1
                stem = segment["segment_id"].lower().replace("_", "-")
                run_id = f"{number:03d}-{stem}-{profile.lower()}-{suffix.lower()}"
                instance = f"V25-{number:03d}-{segment['segment_id']}-{profile}-{suffix}"
                core = {
                    "strategy_id": "LONDON_FIX_USD_INVENTORY_REVERSAL_1_0",
                    "segment_id": segment["segment_id"],
                    "reset_at": segment["reset_at"],
                    "eligible_from": segment["eligible_from"],
                    "eligible_to_exclusive": segment["eligible_to_exclusive"],
                    "research_cutoff": "2026.08.01 00:00:00",
                    "cost_profile": profile,
                    "supplementary_multiplier": multiplier,
                    "execution_layer": layer,
                    "execution_mode": mode,
                    "model": 4,
                    "optimization": False,
                    "deposit_usd": 10000,
                    "leverage": 30,
                    "risk_percent": 0.25,
                }
                runs.append({
                    "run_number": number,
                    "run_id": run_id,
                    "execution_instance_id": instance,
                    "formal_dataset": segment["formal_dataset"],
                    "classification": segment["classification"],
                    "segment_id": segment["segment_id"],
                    "cost_profile": profile,
                    "supplementary_multiplier": multiplier,
                    "execution_layer": layer,
                    "execution_mode": mode,
                    "reset_at": segment["reset_at"],
                    "eligible_from": segment["eligible_from"],
                    "eligible_to_exclusive": segment["eligible_to_exclusive"],
                    "expected_indicator_eligible_h1_bars": segment["indicator_eligible_h1_bars"],
                    "expected_first_indicator_eligible_h1": segment["first_indicator_eligible_h1"],
                    "output_subdirectory": f"physical-runs/{run_id}",
                    "complete_run_configuration_sha256": hashlib.sha256(canonical(core)).hexdigest(),
                })
    assert len(runs) == 42
    write("phase6-v25-physical-run-plan.json", {
        "schema": "SOLTRADE_PHASE6_V25_PHYSICAL_RUN_PLAN_V1",
        "status": "FROZEN_BEFORE_RUN_1",
        "qualified_segments": 7,
        "cost_profiles": 3,
        "execution_layers": 2,
        "physical_run_count": 42,
        "run_order_locked": True,
        "runs": runs,
    })

    cells = []
    for dataset in ("V25_2025_DEVELOPMENT_REUSE", "V25_2026_PRESEAL_DEVELOPMENT"):
        for layer, mode, suffix in LAYERS:
            for profile, _ in PROFILES:
                members = [r["run_id"] for r in runs if r["formal_dataset"] == dataset and r["cost_profile"] == profile and r["execution_layer"] == layer]
                cells.append({
                    "cell_id": f"{dataset}-{profile}-{suffix}",
                    "formal_dataset": dataset,
                    "cost_profile": profile,
                    "execution_layer": layer,
                    "execution_mode": mode,
                    "member_physical_runs": members,
                    "member_count": len(members),
                    "synthetic_starting_equity_usd": 10000.0,
                    "aggregation_order": "NATURALLY_CLOSED_EXIT_TIMESTAMP_ASCENDING_THEN_SEGMENT_ID",
                    "right_censored_pnl_included": False,
                })
    assert len(cells) == 12
    write("phase6-v25-formal-cell-plan.json", {
        "schema": "SOLTRADE_PHASE6_V25_FORMAL_CELL_PLAN_V1",
        "status": "FROZEN_BEFORE_RUN_1",
        "formal_cell_count": 12,
        "cells": cells,
    })

    write("phase6-v25-executable-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V25_EXECUTABLE_FREEZE_V1",
        "status": "FROZEN_BEFORE_RUN_1",
        "source": "research/fixing/SolTradeFixingReversalHarness.mq5",
        "source_sha256": sha(ROOT / "research/fixing/SolTradeFixingReversalHarness.mq5"),
        "compiled_ex5_sha256": sha(Path("/home/tibule12/.wine-fpmarkets/drive_c/v25/SolTradeFixingReversalHarness.ex5")),
        "compiler_result": "0 errors, 0 warnings",
        "strategy_specification_sha256": sha(SPEC),
        "physical_run_plan_sha256": sha(OUT / "phase6-v25-physical-run-plan.json"),
        "formal_cell_plan_sha256": sha(OUT / "phase6-v25-formal-cell-plan.json"),
        "profitability_viewed": False,
        "run_1_started": False,
    })
    print(json.dumps({"segments": 7, "physical_runs": 42, "formal_cells": 12, "source_sha256": sha(ROOT / "research/fixing/SolTradeFixingReversalHarness.mq5")}, indent=2))


if __name__ == "__main__":
    main()
