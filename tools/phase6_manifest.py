#!/usr/bin/env python3
"""Generate the review-only SolTrade Phase 6 run matrix and input hashes.

This tool creates metadata only. It never launches MetaTrader or a Strategy
Tester run. Its canonical field order mirrors
SolTradeBuildTradingInputMaterial() in BacktestResearch.mqh.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import statistics
from datetime import datetime, timezone
from pathlib import Path


SCHEMA = "SOLTRADE_PHASE6_RESEARCH_V1"
MANIFEST_ID = "PHASE6-PROPOSED-V1"
DATASETS = (
    ("DEVELOPMENT", 1, "2024-01-01T00:00:00Z", "2025-04-01T00:00:00Z"),
    ("VALIDATION", 2, "2025-04-01T00:00:00Z", "2025-11-15T00:00:00Z"),
    ("OUT_OF_SAMPLE", 3, "2025-11-15T00:00:00Z", "2026-07-01T00:00:00Z"),
)
COSTS = (
    ("NORMAL", 1, 0.0, 200),
    ("HIGH", 2, 0.50, 400),
    ("STRESS", 3, 1.00, 800),
)


def epoch(timestamp: str) -> int:
    return int(datetime.fromisoformat(timestamp.replace("Z", "+00:00")).timestamp())


def field(name: str, value: object) -> str:
    return f"{name}={value}\n"


def decimal(value: float) -> str:
    return f"{value:.10f}"


def canonical_material(
    dataset_number: int,
    profile_number: int,
    start: str,
    end: str,
    multiplier: float,
    delay_ms: int,
    history_fingerprint: str,
    latency_fingerprint: str,
    build_fingerprint: str,
    source_commit: str,
) -> str:
    values: tuple[tuple[str, object], ...] = (
        ("schema", SCHEMA),
        ("strategy_version", "1.0.0"),
        ("approved_strategy_version", ""),
        ("risk_profile", "CONSERVATIVE_V1"),
        ("approved_risk_profile", ""),
        ("magic_number", "2607202601"),
        ("symbol", "EURUSD"),
        ("timeframe", "16385"),
        ("minimum_history_bars", "222"),
        ("max_tick_age_seconds", "120"),
        ("max_spread_points", "30"),
        ("max_spread_atr_percent", decimal(10.0)),
        ("max_slippage_points", "10"),
        ("risk_per_trade_percent", decimal(0.25)),
        ("daily_loss_limit_percent", decimal(1.0)),
        ("weekly_loss_limit_percent", decimal(2.5)),
        ("emergency_drawdown_percent", decimal(5.0)),
        ("production_baseline_equity", decimal(10000.0)),
        ("consecutive_loss_limit", "3"),
        ("reset_emergency_lock", "0"),
        ("expected_environment", "1"),
        ("enable_demo_execution", "0"),
        ("enable_position_management", "0"),
        ("approved_demo_account", "0"),
        ("allow_live_trading", "0"),
        ("approved_live_account", "0"),
        ("emergency_stop", "0"),
        ("enable_backtest_research", "1"),
        ("enable_backtest_execution", "1"),
        ("enable_backtest_position_management", "1"),
        ("research_manifest_id", MANIFEST_ID),
        ("research_dataset", str(dataset_number)),
        ("research_cost_profile", str(profile_number)),
        ("research_start_inclusive", str(epoch(start))),
        ("research_end_exclusive", str(epoch(end))),
        ("research_history_fingerprint", history_fingerprint),
        ("research_latency_fingerprint", latency_fingerprint),
        ("research_latency_sample_count", "30"),
        ("research_frozen_delay_ms", str(delay_ms)),
        ("tester_tick_model", "EVERY_TICK_BASED_ON_REAL_TICKS"),
        ("tester_execution_delay_mode", "FIXED"),
        ("supplementary_cost_multiplier", decimal(multiplier)),
        ("research_source_commit", source_commit),
        ("research_build_fingerprint", build_fingerprint),
        ("research_expected_terminal_build", "6067"),
        ("research_expected_broker_server", "easyMarkets-Live"),
        ("research_expected_initial_deposit", decimal(10000.0)),
        ("research_expected_deposit_currency", "USD"),
        ("research_expected_leverage", "200"),
        ("enable_csv_journal", "1"),
        ("enable_dashboard", "0"),
        ("dashboard_refresh_seconds", "1"),
        ("ema_period", "200"),
        ("donchian_entry_period", "20"),
        ("donchian_exit_period", "10"),
        ("atr_period", "14"),
        ("initial_stop_atr_multiple", decimal(2.0)),
        ("execution_state_schema", "SOLTRADE_EXECUTION_STATE_V1"),
        ("position_state_schema", "SOLTRADE_POSITION_STATE_V1"),
        ("risk_state_schema", "SOLTRADE_RISK_STATE_V1"),
        ("research_state_schema", "SOLTRADE_PHASE6_STATE_V1"),
    )
    return "".join(field(name, value) for name, value in values)


def load_latency(path: Path) -> dict[str, object]:
    raw = path.read_bytes()
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    measurements = [int(row["round_trip_ms"]) for row in rows]
    if len(measurements) < 30 or any(row["result"] != "SUCCESS" for row in rows):
        raise ValueError("latency evidence requires at least 30 successful samples")
    median = statistics.median(measurements)
    return {
        "fingerprint_sha256": hashlib.sha256(raw).hexdigest(),
        "sample_count": len(measurements),
        "first_timestamp": rows[0]["timestamp_local"],
        "last_timestamp": rows[-1]["timestamp_local"],
        "raw_round_trip_ms": measurements,
        "minimum_ms": min(measurements),
        "maximum_ms": max(measurements),
        "mean_ms": round(statistics.mean(measurements), 2),
        "median_ms": median,
        "rounding_rule": "nearest 50 ms, half upward",
        "frozen_D_ms": 200,
        "sessions": 1,
        "session_note": (
            "Minimum 30-observation gate met in one session; multiple sessions "
            "remain preferable but were not mandatory."
        ),
    }


def generate(arguments: argparse.Namespace) -> None:
    latency = load_latency(arguments.latency)
    history_identity = json.loads(
        arguments.history_identity.read_text(encoding="utf-8")
    )
    safety_evidence = json.loads(
        arguments.safety_evidence.read_text(encoding="utf-8")
    )
    history_fingerprint = str(
        history_identity["aggregate_history_identity"]["sha256"]
    )
    runs: list[dict[str, object]] = []
    matrix_rows: list[dict[str, object]] = []

    for dataset_name, dataset_number, start, end in DATASETS:
        for profile_name, profile_number, multiplier, delay_ms in COSTS:
            material = canonical_material(
                dataset_number,
                profile_number,
                start,
                end,
                multiplier,
                delay_ms,
                history_fingerprint,
                str(latency["fingerprint_sha256"]),
                arguments.build_fingerprint,
                arguments.source_commit,
            )
            digest = hashlib.sha256(material.encode("utf-8")).hexdigest()
            short_dataset = {
                "DEVELOPMENT": "DEV",
                "VALIDATION": "VAL",
                "OUT_OF_SAMPLE": "OOS",
            }[dataset_name]
            base = f"P6-{short_dataset}-{profile_name}"
            run = {
                "dataset": dataset_name,
                "cost_profile": profile_name,
                "start_inclusive": start,
                "end_exclusive": end,
                "supplementary_multiplier": multiplier,
                "fixed_execution_delay_ms": delay_ms,
                "trading_input_hash": digest,
                "authoritative_name": f"{base}-AUTH-01",
                "authoritative_execution_instance_id": f"{base}-AUTH-01",
                "replica_name": f"{base}-REPLICA-01",
                "replica_execution_instance_id": f"{base}-REPLICA-01",
                "authoritative_replica_hash_equal": True,
                "set_file_byte_identity_claimed": False,
            }
            runs.append(run)
            matrix_rows.append(run)
            material_path = arguments.output_dir / "canonical-inputs" / f"{base}.txt"
            material_path.parent.mkdir(parents=True, exist_ok=True)
            material_path.write_text(material, encoding="utf-8")

    matrix_hash_material = "".join(
        f"{run['dataset']}|{run['cost_profile']}|{run['trading_input_hash']}\n"
        for run in runs
    )
    manifest = {
        "schema": "SOLTRADE_PHASE6_PROPOSED_FROZEN_MANIFEST_V1",
        "status": "HISTORY_UNAVAILABLE_FOR_PROPOSED_MATRIX",
        "execution_authorized": False,
        "invalidating_gate": (
            "All 30 proposed TKC months were acquired, but 12 gaps longer than "
            "15 minutes occur inside the broker's weekly sessions, connected M1 "
            "access is incomplete, and the single connected safety run reported "
            "65 passed and 1 failed. No matrix execution is authorized."
        ),
        "manifest_id": MANIFEST_ID,
        "date_semantics": {
            "start": "inclusive",
            "end": "exclusive",
            "full_interval": {
                "start_inclusive": "2024-01-01T00:00:00Z",
                "end_exclusive": "2026-07-01T00:00:00Z",
            },
            "splits": [
                {
                    "name": name,
                    "start_inclusive": start,
                    "end_exclusive": end,
                }
                for name, _, start, end in DATASETS
            ],
            "warmup": (
                "Indicator history is loaded separately before start_inclusive; "
                "orders with signal_bar_time outside [start,end) are rejected and "
                "never enter statistics."
            ),
            "boundary_positions": (
                "Start- and end-boundary flags are emitted per position. Any "
                "unexplained boundary position or cash-flow mismatch invalidates "
                "the run."
            ),
            "replacement_proposal": {
                **history_identity["replacement_range_proposal"],
                "splits": [
                    {
                        "name": "DEVELOPMENT",
                        "start_inclusive": "2024-01-16T00:00:00Z",
                        "end_exclusive": "2024-07-05T00:00:00Z",
                    },
                    {
                        "name": "VALIDATION",
                        "start_inclusive": "2024-07-05T00:00:00Z",
                        "end_exclusive": "2024-09-29T00:00:00Z",
                    },
                    {
                        "name": "OUT_OF_SAMPLE",
                        "start_inclusive": "2024-09-29T00:00:00Z",
                        "end_exclusive": "2024-12-24T00:00:00Z",
                    },
                ],
                "split_rule": (
                    "50/25/25 elapsed-day split after the separate deterministic "
                    "14-calendar-day warm-up allowance; no strategy result viewed"
                ),
            },
        },
        "history": {
            "aggregate_identity_sha256": history_fingerprint,
            "identity_file": arguments.history_identity.name,
            "aggregate_manifest_file": (
                history_identity["aggregate_history_identity"]["manifest_file"]
            ),
            "aggregate_manifest_entry_count": (
                history_identity["aggregate_history_identity"]["entry_count"]
            ),
            "real_tick_coverage_status": history_identity["status"],
            "proposed_interval": history_identity["proposed_interval"],
            "m1_hcc": history_identity["m1_hcc"],
            "symbol_and_session_identity": history_identity["broker_metadata"],
            "broker_download_message_count": (
                history_identity["broker_message_count"]
            ),
            "tester_history_quality_messages": (
                "NON_TRADING_ACQUISITION_MESSAGES_FROZEN; native Strategy Tester "
                "history-quality messages remain absent because no run is authorized"
            ),
            "generated_tick_substitution": False,
            "broker_or_data_source_substitution": False,
            "out_of_interval_202607_tkc_included": False,
            "same_frozen_history_for_all_runs": False,
        },
        "latency": latency,
        "costs": {
            "native_layer": (
                "MT5 real-tick spread, commission, swap, fees and fills remain "
                "broker-native and are never subtracted twice."
            ),
            "supplementary_formula": (
                "adjusted_trade_net = native_trade_net - supplementary_charge"
            ),
            "supplementary_charge": "native_friction * multiplier",
            "normal": {"multiplier": 0.0, "fixed_delay_ms": 200},
            "high": {"multiplier": 0.50, "fixed_delay_ms": 400},
            "stress": {"multiplier": 1.00, "fixed_delay_ms": 800},
            "random_delay": (
                "PROHIBITED for authoritative real-tick runs. Any future random-"
                "delay test must use a compatible generated-tick mode and be "
                "supplementary/non-comparable with seeds and repeats disclosed."
            ),
        },
        "terminal_and_broker": {
            "terminal_build": 6067,
            "broker_company": "Blue Capital Markets Limited",
            "broker_server": "easyMarkets-Live",
            "symbol": "EURUSD",
            "timeframe": "H1",
            "tester_tick_model": "Every tick based on real ticks",
            "tester_initial_deposit": 10000.0,
            "tester_deposit_currency": "USD",
            "tester_leverage": 200,
            "tester_account_parameters_status": "PROPOSED_FOR_REVIEW",
        },
        "source": {
            "release_commit": arguments.source_commit,
            "release_tag": arguments.release_tag,
            "release_commit_frozen": True,
            "ea_source_sha256": arguments.ea_source_hash,
            "ea_ex5_sha256": arguments.ea_ex5_hash,
            "aggregate_trading_source_fingerprint_sha256": (
                arguments.build_fingerprint
            ),
        },
        "connected_safety": {
            "evidence_file": arguments.safety_evidence.name,
            "evidence_sha256": hashlib.sha256(
                arguments.safety_evidence.read_bytes()
            ).hexdigest(),
            "run_count": safety_evidence["run_count"],
            "expected": safety_evidence["expected_before_execution"],
            "actual": safety_evidence["actual_result"],
            "trading_effects": safety_evidence["trading_effects"],
            "markers": safety_evidence["marker_state"],
            "corrected_fixture": safety_evidence["diagnosis"],
            "gate": safety_evidence["gate"],
        },
        "canonical_trading_inputs": {
            "matrix_fingerprint_sha256": hashlib.sha256(
                matrix_hash_material.encode("utf-8")
            ).hexdigest(),
            "execution_instance_id_included": False,
            "state_and_artifact_roots_included": False,
            "reason_for_exclusions": (
                "ExecutionInstanceId and its derived roots isolate state/artifacts "
                "only. Static and MQL fixtures prove they do not reach strategy, "
                "risk, execution-plan, position, or metric calculations."
            ),
            "runs": runs,
        },
        "replication": {
            "authoritative_runs": 9,
            "replicas": 9,
            "fixed_delay_identical_run_required": True,
            "full_set_files_byte_identical_claimed": False,
            "set_file_note": (
                "Authoritative and replica .set files will differ in "
                "ExecutionInstanceId. Their canonical trading-input hash must be "
                "identical within each pair."
            ),
        },
        "acceptance_rules": {
            "best_trade_max_percent_of_positive_net_profit": 20.0,
            "best_calendar_year_or_registered_subperiod_max_percent": 40.0,
            "subperiod_semantics": (
                "For intervals shorter than four years, five equal chronological "
                "subperiods are used; otherwise calendar years are used."
            ),
            "normal": {
                "net_profit": "> 0",
                "expectancy": "> 0",
                "profit_factor": "> 1.15",
                "maximum_equity_drawdown_percent": "< 8.0",
            },
            "high": {
                "net_profit": "> 0",
                "expectancy": "> 0",
                "profit_factor": ">= 1.05",
                "maximum_equity_drawdown_percent": "<= 10.0",
            },
            "stress": {
                "net_profit": "> 0",
                "expectancy": "> 0",
                "profit_factor": ">= 1.00",
                "maximum_equity_drawdown_percent": "<= 12.0",
            },
            "out_of_sample_closed_trade_minimum": 50,
            "below_oos_minimum_label": "INCONCLUSIVE_INSUFFICIENT_SAMPLE",
            "variation": {
                "minimum_normalized_expectancy_vs_max": ">= 50%",
                "minimum_annualized_return_vs_max": ">= 50%",
                "maximum_profit_factor_range": "<= 0.40",
            },
        },
        "uncertainty": {
            "reporting_only": True,
            "bootstrap_paths": 100000,
            "assumption": (
                "Individual-trade bootstrap assumes independently resampled "
                "historical trade returns. It does not reproduce serial dependence, "
                "market regimes, or the strategy time-based lock state."
            ),
        },
        "invalidation_rules": [
            "journal mismatch",
            "missing report",
            "missing metadata",
            "history change",
            "in-session real-tick gap",
            "incomplete relevant M1 access",
            "connected safety result other than exactly 66 passed and 0 failed",
            "state or artifact namespace collision",
            "canonical trading-input hash mismatch",
            "authoritative/replica fixed-delay result mismatch",
        ],
    }

    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = arguments.output_dir / "proposed-frozen-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    matrix_path = arguments.output_dir / "run-matrix.csv"
    with matrix_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=matrix_rows[0].keys(),
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(matrix_rows)
    print(f"Proposed Phase 6 manifest written to {manifest_path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--latency", type=Path, required=True)
    parser.add_argument("--history-identity", type=Path, required=True)
    parser.add_argument("--safety-evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--build-fingerprint", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--ea-source-hash", required=True)
    parser.add_argument("--ea-ex5-hash", required=True)
    arguments = parser.parse_args()
    generate(arguments)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
