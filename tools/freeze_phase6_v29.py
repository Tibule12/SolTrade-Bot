#!/usr/bin/env python3
"""Freeze V29 around the byte-identical, already-retained V26 schedules."""
from __future__ import annotations

import csv
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v29-weekly-cross-sectional-currency-momentum"
SIGNALS = OUT / "frozen-v26-signal-set"
SOURCE = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum/signal-schedules"
EXPECTED = {
    "V26_2025_DEVELOPMENT": (204, "25876a808a49044bfdb2f2b728e0cbd7d097678c377a9b4af8b4d7b0ed8487cf"),
    "V26_2026_PRESEAL_DEVELOPMENT": (116, "feada50576c4c6dd8ff716a2dda94abc053265ec8f545057bbd6e9a92425a11b"),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=False) + "\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    ledger: list[dict[str, object]] = []
    source_inventory = []
    set_hash_material = []
    for dataset, (expected_selected, expected_hash) in EXPECTED.items():
        source = SOURCE / dataset / "signal-schedule.csv"
        frozen = SIGNALS / dataset / "signal-schedule.csv"
        if sha(source) != expected_hash or sha(frozen) != expected_hash or source.read_bytes() != frozen.read_bytes():
            raise SystemExit(f"V26_SCHEDULE_IDENTITY_FAILURE {dataset}")
        raw_lines = frozen.read_bytes().splitlines()
        rows = list(csv.DictReader(line.decode("utf-8") for line in raw_lines))
        selected = 0
        for source_row_number, (raw, row) in enumerate(zip(raw_lines[1:], rows), start=2):
            if row["chart_direction"] not in ("BUY", "SELL"):
                continue
            selected += 1
            row_hash = hashlib.sha256(raw).hexdigest()
            identity = (
                f"{row['dataset']}|{row['target']}|{row['currency']}|{row['symbol']}|"
                f"{row['rank']}|{row['portfolio_side']}|{row['chart_direction']}|{row['scheduled_exit']}"
            )
            identity_hash = hashlib.sha256(identity.encode()).hexdigest()
            ledger.append({
                "ordinal": len(ledger) + 1,
                "source_file": f"{dataset}/signal-schedule.csv",
                "source_row_number": source_row_number,
                "dataset": row["dataset"],
                "target": row["target"],
                "currency": row["currency"],
                "symbol": row["symbol"],
                "orientation": row["orientation"],
                "rank": row["rank"],
                "formation_return": row["formation_return"],
                "portfolio_side": row["portfolio_side"],
                "chart_direction": row["chart_direction"],
                "recent_h1": row["recent_h1"],
                "recent_close": row["recent_close"],
                "anchor_h1": row["anchor_h1"],
                "anchor_close": row["anchor_close"],
                "scheduled_exit": row["scheduled_exit"],
                "identity_sha256": identity_hash,
                "exact_source_row_sha256": row_hash,
            })
            set_hash_material.append(f"{dataset}|{source_row_number}|{row_hash}\n")
        if selected != expected_selected:
            raise SystemExit(f"V26_SELECTED_COUNT_FAILURE {dataset} {selected}")
        source_inventory.append({
            "dataset": dataset,
            "source_path": str(source.relative_to(ROOT)),
            "frozen_copy_path": str(frozen.relative_to(ROOT)),
            "source_and_copy_sha256": expected_hash,
            "selected_signal_count": selected,
            "byte_identical": True,
        })
    if len(ledger) != 320 or len({row["identity_sha256"] for row in ledger}) != 320:
        raise SystemExit("V29_SIGNAL_IDENTITY_CARDINALITY_FAILURE")

    ledger_path = OUT / "v29-frozen-signal-identity-ledger.csv"
    with ledger_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(ledger[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(ledger)
    set_hash = hashlib.sha256("".join(set_hash_material).encode()).hexdigest()
    by_dataset = Counter(row["dataset"] for row in ledger)
    by_side = Counter(row["portfolio_side"] for row in ledger)
    by_direction = Counter(row["chart_direction"] for row in ledger)
    by_currency = Counter(row["currency"] for row in ledger)

    write_json("v29-signal-freeze-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V29_SIGNAL_FREEZE_V1",
        "status": "FROZEN_BYTE_IDENTICAL_BEFORE_V29_PNL",
        "source_candidate": "V26",
        "v26_pnl_previously_viewed": False,
        "source_files": source_inventory,
        "selected_signal_count": len(ledger),
        "selected_signal_identity_set_sha256": set_hash,
        "identity_ledger_sha256": sha(ledger_path),
        "by_dataset": dict(sorted(by_dataset.items())),
        "by_portfolio_side": dict(sorted(by_side.items())),
        "by_chart_direction": dict(sorted(by_direction.items())),
        "by_currency": dict(sorted(by_currency.items())),
        "signal_regeneration_performed": False,
    })

    write_json("candidate-strategy-specification.json", {
        "schema": "SOLTRADE_PHASE6_V29_CANDIDATE_SPECIFICATION_V1",
        "strategy_identifier": "FX_CROSS_SECTIONAL_MOMENTUM_3W_1W_TOP2_BOTTOM2_V29_1_0",
        "source_signal_set": "EXACT_FROZEN_V26_320_SELECTED_LEGS",
        "selected_signal_identity_set_sha256": set_hash,
        "unchanged": [
            "seven-currency universe and broker symbols", "three-week formation return",
            "Monday 10:05 broker-server rebalance", "descending rank with ISO-code tie break",
            "top-two LONG and bottom-two SHORT composition", "one-week holding period",
            "five-minute no-retry entry window", "close-prior-week-before-open-current-week",
            "3.0-times completed-D1 Wilder ATR14 initial stop", "30-point inclusive spread ceiling",
            "no take-profit, trailing, breakeven, or partial close"
        ],
        "only_amendment": {
            "risk_per_leg_current_equity_percent": 0.25,
            "maximum_simultaneous_legs": 4,
            "maximum_total_weekly_initial_portfolio_risk_percent": 1.0,
            "reason": "V26 0.05 percent leg risk was below broker minimum volume for every attempted leg"
        },
        "datasets": {
            "V29_2025_DEVELOPMENT": {"schedule_dataset": "V26_2025_DEVELOPMENT", "history_from": "2024.12.02 00:00:00", "eligible": "[2025.01.06 10:05:00,2026.01.01 00:00:00)"},
            "V29_2026_PRESEAL_DEVELOPMENT": {"schedule_dataset": "V26_2026_PRESEAL_DEVELOPMENT", "history_from": "2025.12.01 00:00:00", "eligible": "[2026.01.05 10:05:00,2026.08.01 00:00:00)"},
            "research_cutoff_exclusive": "2026.08.01 00:00:00",
            "sealed_future_oos": "UNOPENED_UNASSIGNED"
        },
        "prohibited": ["signal regeneration", "symbol removal", "leg removal", "ranking change", "parameter tuning", "portfolio-composition change", "size optimization", "sealed-OOS access", "demo trading", "live trading"]
    })

    write_json("sizing-and-portfolio-risk-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V29_SIZING_RISK_FREEZE_V1",
        "starting_equity_usd": 10000.0,
        "risk_budget_per_leg": "current_account_equity * 0.0025",
        "stop_distance": "3.0 * Wilder ATR14 from last completed D1 bar",
        "raw_volume": "risk_budget_usd / (stop_distance / tick_size * tick_value_loss)",
        "volume_rounding": "floor to broker volume step; never round above risk budget",
        "below_minimum_volume": "POSITION_SIZE_REJECTED; no retry",
        "maximum_simultaneous_legs": 4,
        "maximum_weekly_initial_risk": "current_account_equity * 0.0100",
        "portfolio_gate": "sum of actual fill risk for a rebalance must be <= 1.00 percent of equity immediately before the first leg; otherwise INVALID_TEST_EVIDENCE",
        "unchanged_safety_locks": {"daily_loss_percent": 1.0, "weekly_loss_percent": 2.5, "emergency_drawdown_percent": 5.0, "consecutive_losses": 3}
    })

    write_json("cost-and-friction-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V29_COST_FREEZE_V1",
        "commission_usd_per_side_per_standard_lot": 3.0,
        "native_nonzero_commission": "reconcile and do not double count",
        "swap": "V26 frozen FP Markets point-mode per-symbol values; Wednesday triple",
        "supplementary_friction": {"NORMAL": 0.0, "HIGH": 0.5, "STRESS": 1.0},
        "supplementary_charge": "multiplier * (spread + commission + absolute swap + fee + adverse entry slippage + adverse exit slippage)"
    })

    write_json("gate-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V29_GATE_MANIFEST_V1",
        "all_mandatory": True,
        "sample_normal_native": {"all_closed_legs": ">= 150", "closed_legs_dated_2026": ">= 50", "LONG_closed": ">= 50", "SHORT_closed": ">= 50", "each_currency_closed": ">= 10"},
        "performance_every_cell": {
            "NORMAL": {"profit_factor": "> 1.15", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "< 5"},
            "HIGH": {"profit_factor": ">= 1.05", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "<= 7"},
            "STRESS": {"profit_factor": ">= 1.00", "net_profit": "> 0", "expectancy_R": "> 0", "drawdown_percent": "<= 9"}
        },
        "concentration_every_cell": {"best_individual_leg_percent": "<= 15", "best_currency_percent": "<= 40", "best_direction_percent": "<= 70", "best_week_percent": "<= 20", "best_month_percent": "<= 40", "undefined_on_nonpositive_net": "FAIL"},
        "cross_dataset_per_cost_execution": {"expectancy_min_div_max": ">= 0.35", "annualized_return_min_div_max": ">= 0.35", "profit_factor_range": "<= 0.50"},
        "portfolio_risk": {"simultaneous_legs": "<= 4", "actual_initial_risk_percent_per_rebalance": "<= 1.00", "unexplained_missing_or_unclosed_leg": "INVALID"},
        "correlation": {"method": "Pearson correlation of simultaneous-leg net-R series by deterministic rank slot across complete rebalance cohorts", "numeric_gate": "REPORTING_ONLY"},
        "uncertainty": {"bootstrap_paths": 100000, "monte_carlo_paths": 100000, "reporting_only": True},
        "outcomes": ["V29_INDEPENDENT_DEVELOPMENT_PASSED", "V29_INDEPENDENT_DEVELOPMENT_FAILED", "INCONCLUSIVE_INSUFFICIENT_SAMPLE", "INVALID_TEST_EVIDENCE"]
    })

    runs = []
    for number, year, dataset, schedule_dataset, expected_legs, history_from, eligible_from, eligible_to, layer, mode in [
        (1, "2025", "V29_2025_DEVELOPMENT", "V26_2025_DEVELOPMENT", 204, "2024.12.02", "2025.01.06 10:05:00", "2026.01.01 00:00:00", "NATIVE_NORMAL_EXECUTION", 0),
        (2, "2026-preseal", "V29_2026_PRESEAL_DEVELOPMENT", "V26_2026_PRESEAL_DEVELOPMENT", 116, "2025.12.01", "2026.01.05 10:05:00", "2026.08.01 00:00:00", "NATIVE_NORMAL_EXECUTION", 0),
        (3, "2025", "V29_2025_DEVELOPMENT", "V26_2025_DEVELOPMENT", 204, "2024.12.02", "2025.01.06 10:05:00", "2026.01.01 00:00:00", "FIXED_DELAY_200_MS", 200),
        (4, "2026-preseal", "V29_2026_PRESEAL_DEVELOPMENT", "V26_2026_PRESEAL_DEVELOPMENT", 116, "2025.12.01", "2026.01.05 10:05:00", "2026.08.01 00:00:00", "FIXED_DELAY_200_MS", 200),
    ]:
        runs.append({"run_number": number, "run_id": f"{number:02d}-v29-{year}-{'native' if mode == 0 else 'delay200'}", "dataset": dataset, "schedule_dataset": schedule_dataset, "expected_schedule_legs": expected_legs, "history_from": history_from, "eligible_from": eligible_from, "eligible_to_exclusive": eligible_to, "execution_layer": layer, "execution_mode": mode, "schedule_file": f"SolTrade\\Phase6\\V29Signals\\{schedule_dataset}\\signal-schedule.csv"})
    write_json("physical-run-plan.json", {"schema": "SOLTRADE_PHASE6_V29_PHYSICAL_RUN_PLAN_V1", "frozen_before_pnl": True, "model": "EVERY_TICK_BASED_ON_REAL_TICKS", "optimization": False, "runs": runs})

    cells = []
    for run in runs:
        for profile, multiplier in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0)):
            short_layer = "NATIVE" if run["execution_mode"] == 0 else "DELAY200"
            cells.append({"cell_id": f"{run['dataset']}-{profile}-{short_layer}", "dataset": run["dataset"], "cost_profile": profile, "supplementary_multiplier": multiplier, "execution_layer": run["execution_layer"], "source_run": run["run_id"], "starting_equity_usd": 10000.0, "risk_per_leg_percent": 0.25, "aggregation_order": "EXIT_TIME_ASCENDING_THEN_SYMBOL_ASCENDING"})
    write_json("formal-cell-plan.json", {"schema": "SOLTRADE_PHASE6_V29_FORMAL_CELL_PLAN_V1", "frozen_before_pnl": True, "formal_cell_count": 12, "cells": cells})

    seed_material = set_hash + "|PHASE6_V29_WEEKLY_CROSS_SECTIONAL_MOMENTUM|100000"
    write_json("deterministic-seeds.json", {
        "schema": "SOLTRADE_PHASE6_V29_DETERMINISTIC_SEEDS_V1",
        "material": seed_material,
        "bootstrap_seed": int(hashlib.sha256((seed_material + "|BOOTSTRAP").encode()).hexdigest()[:16], 16),
        "monte_carlo_seed": int(hashlib.sha256((seed_material + "|MONTE_CARLO").encode()).hexdigest()[:16], 16),
        "paths_each": 100000,
    })

    write_json("future-portfolio-combination-manifest.json", {
        "schema": "SOLTRADE_FUTURE_V28_V29_COMBINATION_MANIFEST_V1",
        "status": "IMMUTABLE_PROSPECTIVE_ONLY_NOT_AUTHORIZED_TO_RUN",
        "v28_status": "RETIRED_STANDALONE",
        "eligibility": "Combination may be evaluated only after V29_INDEPENDENT_DEVELOPMENT_PASSED and explicit user approval",
        "weights": {"basis": "capital", "V28_percent": 50.0, "V29_percent": 50.0, "later_optimization": "PROHIBITED"},
        "accounting": "Scale each standalone sleeve cash flow to 50 percent capital, merge chronologically, and maintain no cross-sleeve netting assumption",
        "combined_sample": {"closed_legs_or_trades": ">= 300", "dated_2026": ">= 100"},
        "profitability_every_cell": {"NORMAL": {"profit_factor": "> 1.20", "net_profit": "> 0", "expectancy_R": "> 0"}, "HIGH": {"profit_factor": ">= 1.10", "net_profit": "> 0", "expectancy_R": "> 0"}, "STRESS": {"profit_factor": ">= 1.00", "net_profit": "> 0", "expectancy_R": "> 0"}},
        "drawdown": {"NORMAL": "< 6 percent", "HIGH": "<= 8 percent", "STRESS": "<= 10 percent", "diversification_requirement": "combined drawdown <= 85 percent of the worse contemporaneous standalone drawdown"},
        "concentration_every_cell": {"best_trade_percent": "<= 10", "best_currency_percent": "<= 30", "best_direction_percent": "<= 65", "best_week_percent": "<= 15", "best_month_percent": "<= 30"},
        "correlation": {"V28_V29_weekly_return_absolute_Pearson": "<= 0.50", "minimum_complete_overlapping_weeks": 25},
        "authorization": {"automatic_combined_test": False, "demo_authorized_before_every_combined_gate_passes": False, "live_trading": False}
    })

    write_json("preseal-and-production-guard.json", {
        "schema": "SOLTRADE_PHASE6_V29_GUARD_V1",
        "research_cutoff_exclusive": "2026.08.01 00:00:00",
        "sealed_future_oos_accessed": False,
        "signal_regeneration": False,
        "optimization": False,
        "demo_orders": 0,
        "live_orders": 0,
        "production_ea_expected_sha256": "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
    })

    frozen_names = [
        "v29-frozen-signal-identity-ledger.csv", "v29-signal-freeze-manifest.json",
        "candidate-strategy-specification.json", "sizing-and-portfolio-risk-freeze.json",
        "cost-and-friction-freeze.json", "gate-manifest.json", "physical-run-plan.json",
        "formal-cell-plan.json", "deterministic-seeds.json",
        "future-portfolio-combination-manifest.json", "preseal-and-production-guard.json",
    ]
    write_json("prerun-freeze-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V29_PRERUN_FREEZE_V1",
        "status": "FROZEN_BEFORE_PNL",
        "selected_signal_count": 320,
        "selected_signal_identity_set_sha256": set_hash,
        "artifacts": [{"path": name, "sha256": sha(OUT / name)} for name in frozen_names],
        "pnl_viewed": False,
        "optimization": False,
        "demo_or_live_trades": 0,
    })
    print(json.dumps({"selected": len(ledger), "set_sha256": set_hash, "by_dataset": by_dataset, "by_direction": by_direction, "by_currency": by_currency}, indent=2))


if __name__ == "__main__":
    main()
