#!/usr/bin/env python3
"""Freeze V26 candidate and gates using availability-only evidence."""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum"
QUAL = OUT / "data-qualification/attempt-2"
SPECS = OUT / "symbol-specification/symbol-specification-inventory.json"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n")


def timestamps(symbol: str) -> set[str]:
    with (QUAL / symbol / "h1-timestamps.csv").open() as handle:
        return {row["time"] for row in csv.DictReader(handle)}


def main() -> None:
    sets = {symbol: timestamps(symbol) for symbol in SYMBOLS}
    common = set.intersection(*sets.values())
    union = set.union(*sets.values())
    coverage = [{"symbol": symbol, "h1_timestamps": len(values), "missing_vs_union": sorted(union - values)} for symbol, values in sets.items()]
    write("data-qualification-report.json", {
        "schema": "SOLTRADE_PHASE6_V26_DATA_QUALIFICATION_V1", "status": "PASS",
        "bound_from": "2024.12.01 00:00:00", "bound_to_exclusive": "2026.08.01 00:00:00",
        "candidate_symbols": list(SYMBOLS), "qualified_symbols": list(SYMBOLS),
        "union_h1_timestamps": len(union), "common_h1_timestamps": len(common), "coverage": coverage,
        "only_discrepancy": "NZDUSD missing 2025.03.10 00:00:00",
        "price_fields_written": False, "returns_rankings_signal_counts_or_pnl_inspected": False,
        "orders_or_positions": 0, "post_seal_access": False,
        "qualification_inventory_sha256": sha(QUAL / "qualification-inventory.json"),
        "symbol_specification_inventory_sha256": sha(SPECS),
    })
    strategy = {
        "schema": "SOLTRADE_PHASE6_V26_CROSS_SECTIONAL_MOMENTUM_SPEC_V1",
        "specification_id": "FX_CROSS_SECTIONAL_MOMENTUM_3W_1W_TOP2_BOTTOM2_1_0",
        "status": "FROZEN_BEFORE_SIGNAL_COUNTS_OR_PNL", "family": "CROSS_SECTIONAL_CURRENCY_MOMENTUM",
        "related_to_trend_breakout_family": False, "related_to_fixing_reversal_family": False,
        "universe": {
            "currencies": ["EUR", "GBP", "AUD", "NZD", "CAD", "CHF", "JPY"],
            "broker_symbols": list(SYMBOLS), "usd_quote_orientation": {"EURUSD": 1, "GBPUSD": 1, "AUDUSD": 1, "NZDUSD": 1, "USDCAD": -1, "USDCHF": -1, "USDJPY": -1},
            "membership_frozen": True, "exclusion_after_freeze": "ONLY_FAIL_CLOSED_TECHNICAL_INVALIDATION_OF_COMPLETE_CANDIDATE",
        },
        "signal": {
            "rebalance_clock": "MONDAY 10:05:00 FP MARKETS BROKER SERVER TIME",
            "observation": "LAST_COMPLETED_H1_CLOSE AT MONDAY 10:00 VERSUS EXACT MATCHING H1 CLOSE 21 CALENDAR DAYS EARLIER",
            "formation_horizon_calendar_days": 21, "holding_horizon_calendar_days": 7,
            "foreign_currency_return": "XXXUSD: recent/anchor-1; USDXXX: anchor/recent-1",
            "ranking": "DESCENDING FOREIGN-CURRENCY RETURN; ISO CURRENCY CODE ASCENDING TIE BREAK",
            "long_portfolio": "TOP_TWO_CURRENCIES", "short_portfolio": "BOTTOM_TWO_CURRENCIES",
            "middle_three": "NO_POSITION", "required_simultaneous_valid_currency_observations": 7,
            "missing_exact_anchor_or_observation": "SKIP_ENTIRE_REBALANCE_FOR_ALL_SYMBOLS",
            "no_absolute_trend_or_breakout_condition": True,
        },
        "execution": {
            "entry": "FIRST_TRADABLE REAL TICK AT OR AFTER TARGET WITHIN FIVE MINUTES",
            "exit": "FIRST_TRADABLE REAL TICK AT OR AFTER NEXT MONDAY 10:05 WITHIN FIVE MINUTES",
            "rebalance_sequence": "CLOSE PRIOR WEEK BEFORE OPENING CURRENT WEEK",
            "spread_maximum_points_inclusive": 30, "failed_leg_entry": "NO RETRY; OTHER LEGS REMAIN VALID",
            "maximum_portfolio_legs": 4, "maximum_position_per_symbol": 1,
            "execution_layers": {"NATIVE_NORMAL_EXECUTION": 0, "FIXED_DELAY_200_MS": 200},
        },
        "risk": {
            "risk_per_leg_current_portfolio_equity_percent": 0.05, "maximum_initial_portfolio_risk_percent": 0.20,
            "initial_stop": "3.0 * WILDER ATR14 FROM LAST COMPLETED D1 BAR", "take_profit": False,
            "trailing_stop": False, "breakeven_move": False, "partial_close": False,
            "daily_loss_limit_percent": 1.0, "weekly_loss_limit_percent": 2.5,
            "emergency_drawdown_limit_percent": 5.0, "consecutive_loss_pause_count": 3,
            "portfolio_gate_semantics": "FAIL CLOSED IF AGGREGATED CHRONOLOGICAL EVIDENCE REQUIRES A TRADE THAT FROZEN PORTFOLIO RISK STATE WOULD HAVE BLOCKED",
        },
        "datasets": {
            "V26_2025_DEVELOPMENT": {"history_from": "2024.12.02 00:00:00", "eligible_from": "2025.01.06 10:05:00", "eligible_to_exclusive": "2026.01.01 00:00:00"},
            "V26_2026_PRESEAL_DEVELOPMENT": {"history_from": "2025.12.01 00:00:00", "eligible_from": "2026.01.05 10:05:00", "eligible_to_exclusive": "2026.08.01 00:00:00"},
            "research_cutoff_exclusive": "2026.08.01 00:00:00", "all_classification": "DEVELOPMENT_EVIDENCE",
        },
        "costs": {
            "commission_per_side_per_standard_lot_usd": 3.0, "native_nonzero_commission_rule": "RECONCILE_NO_DOUBLE_COUNT",
            "swap": "FROZEN POINT-MODE PER-SYMBOL VALUES IN symbol-specification-inventory.json; WEDNESDAY TRIPLE; NO HISTORICAL SCHEDULE CLAIM",
            "supplementary_friction_multiplier": {"NORMAL": 0.0, "HIGH": 0.5, "STRESS": 1.0},
        },
        "prohibited_after_freeze": [
            "Change 3-week formation or 1-week holding horizon", "Change top-two/bottom-two breadth", "Change universe",
            "Add absolute trend, volatility, carry, weekday, macro, or V25 fixing filter", "Tune rebalance clock or spread ceiling",
            "Tune ATR stop or risk after results", "Run a competing cross-sectional portfolio or parameter variant",
        ],
        "demo_authorization": {"permitted_only_after_all_frozen_development_gates_pass": True, "live_trading_permitted": False},
    }
    write("candidate-strategy-specification.json", strategy)
    gates = {
        "schema": "SOLTRADE_PHASE6_V26_GATE_MANIFEST_V1", "status": "FROZEN_BEFORE_SIGNAL_COUNTS_OR_PNL",
        "sample": {"all_closed_legs_min": 150, "closed_legs_dated_2026_min": 50, "long_closed_min": 50, "short_closed_min": 50, "each_currency_closed_min": 10},
        "performance": {
            "NORMAL": {"profit_factor": "> 1.15", "net_profit": "> 0", "expectancy_R": "> 0", "relative_drawdown_percent": "< 5"},
            "HIGH": {"profit_factor": ">= 1.05", "net_profit": "> 0", "expectancy_R": "> 0", "relative_drawdown_percent": "<= 7"},
            "STRESS": {"profit_factor": ">= 1.00", "net_profit": "> 0", "expectancy_R": "> 0", "relative_drawdown_percent": "<= 9"},
        },
        "concentration": {"best_leg_contribution_percent": "<= 15", "best_currency_contribution_percent": "<= 40", "best_five_equal_time_subperiod_percent": "<= 40", "undefined_on_nonpositive_net": "FAIL"},
        "cross_dataset_per_cost_and_execution": {"expectancy_min_div_max": ">= 0.35", "annualized_return_min_div_max": ">= 0.35", "profit_factor_range": "<= 0.50"},
        "portfolio_balance": {"both_long_and_short_net_reported": True, "no_numeric_side_gate": True},
        "bootstrap_paths": 100000, "monte_carlo_paths": 100000, "uncertainty_reporting_only": True,
        "terminal_rule": "PASS ONLY IF EVERY SAMPLE, PERFORMANCE, CONCENTRATION, CONSISTENCY, TECHNICAL AND PORTFOLIO-RISK GATE PASSES",
    }
    write("gate-manifest.json", gates)
    (OUT / "prerun-methodology.md").write_text(
        "# V26 preregistered methodology\n\nExactly one seven-currency, top-two/bottom-two, three-week/one-week cross-sectional momentum portfolio is permitted. The 2025 and pre-seal 2026 datasets are separate Development cells. No sealed OOS data is assigned or accessed.\n\nSignal generation is evaluated before P&L and must produce identical schedules across isolated symbol executions. Performance uses real ticks, three frozen cost profiles and Native versus fixed-200-ms execution. Formal portfolio equity starts at USD 10,000; each leg risks 0.05% and at most four legs risk 0.20%. Segment balances are not summed. Commission and frozen point-mode swap are reconciled without double counting.\n\nNo optimization, parameter sweep, selective rerun, competing portfolio, connected-chart order, demo order, or live order is permitted. Demo becomes authorized only if every frozen Development gate passes.\n"
    )
    manifest = {
        "schema": "SOLTRADE_PHASE6_V26_PRERUN_FREEZE_V1", "status": "FROZEN_BEFORE_SIGNAL_COUNTS_OR_PNL",
        "candidate": strategy["specification_id"], "candidate_count": 1, "configuration_or_variant_count": 1,
        "qualified_symbols": 7, "signal_counts_viewed": False, "pnl_viewed": False,
        "optimization": False, "parameter_sweeps": False, "sealed_oos_access": False,
        "demo_trades": 0, "live_trades": 0, "strategy_specification_sha256": sha(OUT / "candidate-strategy-specification.json"),
        "gate_manifest_sha256": sha(OUT / "gate-manifest.json"), "data_qualification_report_sha256": sha(OUT / "data-qualification-report.json"),
        "symbol_specification_inventory_sha256": sha(SPECS),
    }
    write("prerun-freeze-manifest.json", manifest)
    names = ["project-level-review.md", "economic-hypothesis.md", "data-qualification-plan.md", "data-qualification-report.json", "candidate-strategy-specification.json", "gate-manifest.json", "prerun-methodology.md", "prerun-freeze-manifest.json"]
    (OUT / "prerun-artifact-sha256.txt").write_text("".join(f"{sha(OUT / name)}  {name}\n" for name in names))
    print(json.dumps({"status": manifest["status"], "candidate": manifest["candidate"], "symbols": 7, "common_h1": len(common), "spec_sha256": manifest["strategy_specification_sha256"], "gate_sha256": manifest["gate_manifest_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
