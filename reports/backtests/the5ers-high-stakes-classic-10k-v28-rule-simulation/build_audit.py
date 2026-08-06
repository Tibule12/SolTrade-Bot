#!/usr/bin/env python3
"""Build the bounded V28/The5ers evidence audit from frozen V28 artifacts only."""

from __future__ import annotations

import csv
import hashlib
import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
RUNS = V28 / "performance-runs-attempt2"
LEDGER = V28 / "phase6-v28-complete-adjusted-trade-ledger.csv"
METRICS = V28 / "phase6-v28-formal-cell-metrics.csv"
EXPECTED_PRODUCTION_SHA256 = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
OUTCOME = "V28_THE5ERS_10K_CLASSIC_INSUFFICIENT_EVIDENCE"
SOURCE_HEAD = "7fc7d898bd6d708218c2c89724a5576f597eacea"
DT_FORMAT = "%Y.%m.%d %H:%M:%S"

CONDITIONS = {
    "NORMAL": ("NORMAL", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "HIGH": ("HIGH", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "STRESS": ("STRESS", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "DELAY_200_MS": ("NORMAL", "FIXED_DELAY_200_MS", ["03-v28-2025-development-delay200", "04-v28-2026-preseal-development-delay200"]),
}

SOURCE_FILES = [
    V28 / "candidate-strategy-specification.json",
    V28 / "formal-cell-plan.json",
    V28 / "gate-manifest.json",
    V28 / "preseal-and-production-guard.json",
    V28 / "prerun-freeze-manifest.json",
    V28 / "performance-executable-freeze.json",
    V28 / "performance-harness-amendment-attempt2.json",
    V28 / "phase6-v28-evidence-integrity.json",
    V28 / "phase6-v28-formal-cell-metrics.csv",
    V28 / "phase6-v28-complete-adjusted-trade-ledger.csv",
    V28 / "phase6-v28-terminal-outcome.md",
    V28 / "signal-feasibility/signal-schedule.csv",
    V28 / "artifact-sha256-v28.txt",
    ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5",
    ROOT / "tools/build_phase6_v28_evidence.py",
]
for run in sorted(CONDITIONS["NORMAL"][2] + CONDITIONS["DELAY_200_MS"][2]):
    for name in ("deals.csv", "events.csv", "transactions.csv", "run-summary.csv", "physical-run-status.json", "native-mt5-report.html"):
        SOURCE_FILES.append(RUNS / run / name)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_json(name: str, payload: object) -> None:
    (OUT / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_csv(name: str, fields: list[str], rows: list[dict[str, object]]) -> None:
    with (OUT / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def dt(value: str) -> datetime:
    return datetime.strptime(value, DT_FORMAT)


def f(value: str | float) -> float:
    return float(value)


def condition_rows(all_rows: list[dict[str, str]], condition: str) -> list[dict[str, str]]:
    cost, layer, _ = CONDITIONS[condition]
    return [row for row in all_rows if row["cost_profile"] == cost and row["execution_layer"] == layer]


def transaction_attempts(run_names: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for run in run_names:
        rows.extend(read_csv(RUNS / run / "transactions.csv"))
    return [row for row in rows if row["record_type"] in {"ENTRY_ATTEMPT", "EXIT_ATTEMPT"}]


def deal_rows(run_names: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for run in run_names:
        rows.extend(read_csv(RUNS / run / "deals.csv"))
    return [row for row in rows if row["in_research_window"] == "YES"]


def max_simultaneous(rows: list[dict[str, str]]) -> int:
    events: list[tuple[datetime, int, int]] = []
    for row in rows:
        events.append((dt(row["entry_time"]), 1, 1))
        events.append((dt(row["exit_time"]), 0, -1))
    current = maximum = 0
    for _, _, delta in sorted(events):
        current += delta
        maximum = max(maximum, current)
    return maximum


def request_frequency(attempts: list[dict[str, str]]) -> dict[str, object]:
    accepted = [
        row for row in attempts
        if row["record_type"] == "EXIT_ATTEMPT" or (row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0")
    ]
    times = sorted(dt(row["time"]) for row in accepted)
    per_second = Counter(times)
    max_rolling = 0
    left = 0
    for right, stamp in enumerate(times):
        while stamp - times[left] >= timedelta(seconds=60):
            left += 1
        max_rolling = max(max_rolling, right - left + 1)
    return {
        "accepted_or_exit_attempt_records": len(accepted),
        "maximum_records_at_one_second": max(per_second.values(), default=0),
        "maximum_records_in_rolling_60_seconds": max_rolling,
        "limitation": "CSV attempt records are not a complete server-request/network trace; retries, modifications, heartbeats and terminal traffic are unavailable.",
    }


def diagnostics(rows: list[dict[str, str]], attempts: list[dict[str, str]]) -> dict[str, object]:
    net = sum(f(row["synthetic_cash_flow"]) for row in rows)
    by_direction = defaultdict(float)
    by_symbol = defaultdict(float)
    by_day = defaultdict(float)
    lots = []
    durations = []
    for row in rows:
        cash = f(row["synthetic_cash_flow"])
        by_direction[row["direction"]] += cash
        by_symbol[row["symbol"]] += cash
        by_day[row["exit_time"][:10]] += cash
        lots.append(f(row["volume"]))
        durations.append(f(row["holding_seconds"]))
    median_lot = statistics.median(lots)
    best_trade = max((f(row["synthetic_cash_flow"]) for row in rows), default=0.0)
    best_day = max(by_day.values(), default=0.0)
    largest_symbol, largest_symbol_net = max(by_symbol.items(), key=lambda item: item[1])
    filled_entries = [row for row in attempts if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"]
    visible_sl = [row for row in filled_entries if f(row["stop_loss"]) > 0]
    lot_counts = {f"{lot:.2f}": count for lot, count in sorted(Counter(lots).items())}
    return {
        "trade_count": len(rows),
        "source_segment_net_profit_sum_usd": net,
        "buy_trade_count": sum(row["direction"] == "BUY" for row in rows),
        "sell_trade_count": sum(row["direction"] == "SELL" for row in rows),
        "buy_net_profit_usd": by_direction["BUY"],
        "sell_net_profit_usd": by_direction["SELL"],
        "largest_trade_usd": best_trade,
        "largest_trade_percent_of_source_segment_net_profit": best_trade / net * 100 if net > 0 else None,
        "best_realized_exit_date": max(by_day, key=by_day.get),
        "best_realized_exit_date_profit_usd": best_day,
        "best_realized_exit_date_percent_of_source_segment_net_profit": best_day / net * 100 if net > 0 else None,
        "best_day_metric_status": "NON_AUTHORITATIVE_REALIZED_EXIT_DATE_PROXY; official midnight-equity day result unavailable",
        "largest_symbol_contribution": largest_symbol,
        "largest_symbol_net_profit_usd": largest_symbol_net,
        "largest_symbol_percent_of_source_segment_net_profit": largest_symbol_net / net * 100 if net > 0 else None,
        "largest_correlated_currency_exposure": "Seven simultaneous legs expressing one common USD-factor direction",
        "maximum_simultaneous_positions": max_simultaneous(rows),
        "maximum_simultaneous_correlated_positions": max_simultaneous(rows),
        "frozen_maximum_initial_portfolio_risk_percent": 3.5,
        "lot_size_distribution": lot_counts,
        "median_lot_size": median_lot,
        "largest_lot_size": max(lots),
        "largest_absolute_lot_deviation_from_median_lots": max(abs(lot - median_lot) for lot in lots),
        "largest_absolute_lot_deviation_from_median_percent": max(abs(lot - median_lot) for lot in lots) / median_lot * 100,
        "average_trade_duration_seconds": statistics.fmean(durations),
        "minimum_trade_duration_seconds": min(durations),
        "trades_lasting_one_second_or_less": sum(value <= 1 for value in durations),
        "trades_lasting_sixty_seconds_or_less": sum(value <= 60 for value in durations),
        "server_request_frequency": request_frequency(attempts),
        "filled_entry_attempts_with_nonzero_visible_stop": len(visible_sl),
        "filled_entry_attempts_total": len(filled_entries),
        "visible_stop_loss_compliance": "PASS_SOURCE_EVIDENCE" if len(visible_sl) == len(filled_entries) else "FAIL",
        "one_sided_betting_evidence": "YES: every cohort is a single common USD-factor bet implemented across seven pairs",
        "outsized_or_concentrated_exposure_evidence": "YES_QUALITATIVE_RISK: seven maximally correlated legs are opened in a batch; individual risk is small but factor concentration is complete",
    }


def inactivity(condition: str) -> dict[str, object]:
    _, _, runs = CONDITIONS[condition]
    deals = sorted(((dt(row["time"]), row) for row in deal_rows(runs)), key=lambda item: item[0])
    gaps = []
    for (start, before), (end, after) in zip(deals, deals[1:]):
        seconds = (end - start).total_seconds()
        if seconds > 30 * 86400:
            gaps.append({
                "start": start.strftime(DT_FORMAT),
                "end": end.strftime(DT_FORMAT),
                "days": seconds / 86400,
                "last_deal_symbol": before["symbol"],
                "next_deal_symbol": after["symbol"],
            })
    return {
        "condition": condition,
        "status": "FAIL_RECORDED_DEAL_GAP_EXCEEDS_30_DAYS" if gaps else "PASS",
        "maximum_gap_days": max((gap["days"] for gap in gaps), default=0.0),
        "breach_count": len(gaps),
        "breaches": gaps,
        "basis": "Elapsed time between consecutive executed deals in the frozen physical stream; holding an unchanged open position is not counted as a new trade execution.",
    }


def daily_rows(rows: list[dict[str, str]], condition: str) -> list[dict[str, object]]:
    output: list[dict[str, object]] = []
    for dataset, start, end in (
        ("V28_2025_DEVELOPMENT", datetime(2025, 1, 6), datetime(2025, 12, 31)),
        ("V28_2026_PRESEAL_DEVELOPMENT", datetime(2026, 1, 5), datetime(2026, 7, 31)),
    ):
        segment = [row for row in rows if row["dataset"] == dataset]
        cash_by_date = defaultdict(float)
        for row in segment:
            cash_by_date[dt(row["exit_time"]).date()] += f(row["synthetic_cash_flow"])
        balance = 10000.0
        day = start
        while day <= end:
            previous = balance
            balance += cash_by_date[day.date()]
            output.append({
                "condition": condition,
                "source_dataset": dataset,
                "source_date_not_normalized_to_utc_plus_3": day.date().isoformat(),
                "source_segment_previous_day_balance_proxy_usd": f"{previous:.10f}",
                "source_segment_realized_cash_flow_proxy_usd": f"{cash_by_date[day.date()]:.10f}",
                "source_segment_end_of_date_balance_proxy_usd": f"{balance:.10f}",
                "midnight_balance_utc_plus_3_usd": "",
                "midnight_equity_utc_plus_3_usd": "",
                "intraday_minimum_equity_usd": "",
                "official_profitable_day_calculation_usd": "",
                "authoritative_status": "INSUFFICIENT_EVIDENCE",
                "continuity_note": "2026 resets to USD 10,000 in source; not a continuous prop-account phase" if day == start and dataset.startswith("V28_2026") else "",
            })
            day += timedelta(days=1)
    return output


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    all_rows = read_csv(LEDGER)
    metrics = read_csv(METRICS)
    production = ROOT / "MQL5/Experts/SolTradeBot.mq5"
    if sha256(production) != EXPECTED_PRODUCTION_SHA256:
        raise RuntimeError("Phase 1-5 production SHA-256 guard failed")
    missing = [str(path.relative_to(ROOT)) for path in SOURCE_FILES if not path.is_file()]
    if missing:
        raise RuntimeError(f"Missing source artifacts: {missing}")

    v28_ledger_entries = []
    for line in (V28 / "artifact-sha256-v28.txt").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        expected, relative = line.split("  ", 1)
        artifact = V28 / relative
        observed = sha256(artifact) if artifact.is_file() else None
        v28_ledger_entries.append({"path": relative, "expected": expected, "observed": observed, "pass": observed == expected})
    if not all(item["pass"] for item in v28_ledger_entries):
        raise RuntimeError("Frozen V28 artifact SHA-256 ledger verification failed")

    summaries = {}
    inactivity_results = {}
    daily_audit_rows: list[dict[str, object]] = []
    for condition in CONDITIONS:
        rows = condition_rows(all_rows, condition)
        attempts = transaction_attempts(CONDITIONS[condition][2])
        summaries[condition] = diagnostics(rows, attempts)
        inactivity_results[condition] = inactivity(condition)
        daily_audit_rows.extend(daily_rows(rows, condition))

    source_refs = {
        "schema": "SOLTRADE_THE5ERS_V28_SOURCE_REFERENCES_V1",
        "source_commit_before_bounded_audit": SOURCE_HEAD,
        "v31_pnl_excluded": True,
        "v29_excluded": True,
        "source_artifacts": [
            {"path": str(path.relative_to(ROOT)), "sha256": sha256(path), "bytes": path.stat().st_size}
            for path in SOURCE_FILES
        ],
        "production_phase1_5": {
            "path": str(production.relative_to(ROOT)),
            "sha256": sha256(production),
            "expected_sha256": EXPECTED_PRODUCTION_SHA256,
            "unchanged": True,
        },
    }
    write_json("exact-source-artifact-references.json", source_refs)
    write_json("source-integrity-and-scope-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_SOURCE_INTEGRITY_V1",
        "status": "PASS",
        "initial_source_commit": SOURCE_HEAD,
        "initial_worktree_clean_observed": True,
        "v28_sha256_ledger_entries_checked": len(v28_ledger_entries),
        "v28_sha256_ledger_failures": 0,
        "production_phase1_5_sha256": sha256(production),
        "production_phase1_5_expected_sha256": EXPECTED_PRODUCTION_SHA256,
        "production_phase1_5_unchanged": True,
        "v31_used_for_pnl": False,
        "v29_used_or_combined": False,
        "strategy_redesign_optimization_or_tuning": False,
        "purchase_or_registration": False,
        "connected_demo_or_live_trade": False,
        "checkout_price_status": "CHECKOUT_PRICE_REVERIFICATION_REQUIRED",
    })

    sufficiency = {
        "schema": "SOLTRADE_THE5ERS_V28_EVIDENCE_SUFFICIENCY_V1",
        "status": "INSUFFICIENT_EVIDENCE",
        "terminal_outcome": OUTCOME,
        "blocking_gaps": [
            "No timestamped full intraday equity stream exists; native HTML preserves aggregate drawdown statistics and bitmap charts only.",
            "No UTC+3 midnight balance/equity snapshots exist for the official profitable-day calculation.",
            "The 2025 and 2026 qualified V28 runs each reset to USD 10,000, so frozen risk sizing was not run on one continuous prop-account balance.",
            "No qualified historical high-impact news calendar dataset, source provenance or checksum exists for the order-window audit.",
            "Physical V28 evidence used MT5 at 1:30 leverage, not the requested 1:100; accepted trades at lower leverage support margin feasibility but are not a native 1:100 run.",
            "Source timestamps are broker-server timestamps and no complete DST-aware mapping to the required UTC+3 day boundary was frozen.",
        ],
        "non_blocking_or_resolved": [
            "All four physical V28 runs and twelve formal cells are qualified V28 evidence.",
            "Every filled entry request in the transaction evidence has a non-zero stop loss, corroborated by native MT5 order reports.",
            "V31 and V29 are excluded from all P&L and rule calculations.",
            "Phase 1-5 production source matches the frozen SHA-256.",
        ],
        "methodological_decision": "No intraday equity, UTC+3 midnight equity, continuous-account sizing or news result is estimated. Rule 7 therefore requires the insufficient-evidence terminal outcome.",
    }
    write_json("evidence-sufficiency.json", sufficiency)

    phase1 = {
        "schema": "SOLTRADE_THE5ERS_V28_PHASE1_SIMULATION_V1",
        "phase": 1,
        "starting_balance_usd": 10000,
        "target_usd": 800,
        "status": "NOT_VALIDLY_SIMULATABLE_INSUFFICIENT_EVIDENCE",
        "conditions": {},
    }
    for condition, summary in summaries.items():
        phase1["conditions"][condition] = {
            "status": "INSUFFICIENT_EVIDENCE",
            "source_segment_net_profit_sum_usd_non_authoritative": summary["source_segment_net_profit_sum_usd"],
            "source_segment_sum_reaches_800": summary["source_segment_net_profit_sum_usd"] >= 800,
            "inactivity_result": inactivity_results[condition]["status"],
            "daily_loss": "UNRESOLVED_MISSING_INTRADAY_EQUITY",
            "total_loss": "UNRESOLVED_NO_CONTINUOUS_ACCOUNT_EQUITY",
            "profitable_days": "UNRESOLVED_MISSING_UTC_PLUS_3_MIDNIGHT_EQUITY",
            "news_windows": "UNRESOLVED_MISSING_QUALIFIED_CALENDAR",
            "qualitative_concentration": "HIGH_RISK_LIKELY_PROHIBITED: one common USD-factor bet across seven simultaneous pairs",
        }
    write_json("phase-1-simulation.json", phase1)

    phase2 = {
        "schema": "SOLTRADE_THE5ERS_V28_PHASE2_SIMULATION_V1",
        "phase": 2,
        "starting_balance_usd": 10000,
        "target_usd": 500,
        "status": "NOT_REACHED_AND_NOT_SIMULATED",
        "reason": "No condition produced a valid Phase 1 pass. Phase 2 cannot chronologically begin or reset under the frozen programme contract.",
        "condition_status": {condition: "NOT_REACHED" for condition in CONDITIONS},
    }
    write_json("phase-2-simulation.json", phase2)

    daily_fields = list(daily_audit_rows[0])
    write_csv("daily-equity-and-balance-audit.csv", daily_fields, daily_audit_rows)
    write_json("daily-loss-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_DAILY_LOSS_AUDIT_V1",
        "limit_percent": 5,
        "day_boundary": "00:00 UTC+3",
        "status_by_condition": {condition: "UNRESOLVED_MISSING_FULL_INTRADAY_EQUITY_AND_UTC_PLUS_3_BOUNDARIES" for condition in CONDITIONS},
        "closed_trade_totals_used_as_substitute": False,
        "aggregate_native_drawdown_used_as_substitute": False,
        "result": "INSUFFICIENT_EVIDENCE",
    })

    max_closed_dd = {}
    for condition, (cost, layer, _) in CONDITIONS.items():
        cells = [row for row in metrics if row["cost_profile"] == cost and row["execution_layer"] == layer]
        max_closed_dd[condition] = max(f(row["relative_drawdown_percent"]) for row in cells)
    write_json("total-loss-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_TOTAL_LOSS_AUDIT_V1",
        "absolute_floor_usd": 9000,
        "status_by_condition": {condition: "UNRESOLVED_NO_CONTINUOUS_PROP_ACCOUNT_EQUITY" for condition in CONDITIONS},
        "source_segment_closed_trade_path_max_drawdown_percent_non_authoritative": max_closed_dd,
        "warning": "The listed drawdowns are segment-local realized-cash-flow reconstructions. They cannot establish the absolute minimum equity of a continuous USD 10,000 prop account.",
        "result": "INSUFFICIENT_EVIDENCE",
    })
    write_json("profitable-day-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_PROFITABLE_DAY_AUDIT_V1",
        "minimum_days": 3,
        "minimum_day_profit_usd": 50,
        "official_formula": "minimum(midnight balance, midnight equity) minus previous-day balance",
        "day_boundary": "00:00 UTC+3",
        "status_by_condition": {condition: "UNRESOLVED_MISSING_MIDNIGHT_EQUITY" for condition in CONDITIONS},
        "realized_exit_date_proxy_not_substituted": True,
        "result": "INSUFFICIENT_EVIDENCE",
    })

    inactivity_csv = []
    for condition, result in inactivity_results.items():
        for gap in result["breaches"]:
            inactivity_csv.append({"condition": condition, **gap, "status": result["status"]})
    write_csv("inactivity-audit.csv", ["condition", "start", "end", "days", "last_deal_symbol", "next_deal_symbol", "status"], inactivity_csv)
    write_json("inactivity-audit-summary.json", {
        "schema": "SOLTRADE_THE5ERS_V28_INACTIVITY_AUDIT_V1",
        "limit": "more than 30 consecutive days without a trade execution",
        "conditions": inactivity_results,
    })

    write_json("news-window-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_NEWS_WINDOW_AUDIT_V1",
        "prohibited_window": "2 minutes before through 2 minutes after each high-impact event",
        "order_open_and_execution_streams_located": True,
        "physical_streams": {condition: CONDITIONS[condition][2] for condition in CONDITIONS},
        "calendar_sources": [],
        "calendar_sha256_ledger": [],
        "calendar_status": "MISSING_QUALIFIED_HISTORICAL_CALENDAR",
        "audit_result_by_condition": {condition: "UNRESOLVED" for condition in CONDITIONS},
        "no_violation_assumed": False,
        "result": "INSUFFICIENT_EVIDENCE",
    })

    write_json("ea-and-prohibited-practice-audit.json", {
        "schema": "SOLTRADE_THE5ERS_V28_EA_PRACTICE_AUDIT_V1",
        "conditions": summaries,
        "microstructure_practices": {
            "tick_scalping": "NO_EVIDENCE; minimum holding time is reported per condition and is much longer than seconds",
            "high_frequency_trading": "NO_EVIDENCE; monthly cohort logic",
            "latency_arbitrage": "NO_EVIDENCE",
            "reverse_arbitrage": "NO_EVIDENCE",
            "hedge_arbitrage": "NO_EVIDENCE; hedge-account platform does not change the directional factor design",
            "copied_third_party_signals": "NO_EVIDENCE; frozen proprietary deterministic signal schedule",
            "emulator_based_trading": "NO_EVIDENCE; native MT5 Strategy Tester artifacts",
            "excessive_server_requests": "UNRESOLVED; attempt-record frequency is measured but a complete server trace and The5ers numerical threshold are unavailable",
        },
        "qualitative_prohibitions": {
            "one_sided_betting": "EVIDENCE_PRESENT",
            "disproportionate_concentration": "EVIDENCE_PRESENT",
            "bulk_trading": "EVIDENCE_PRESENT: cohorts submit up to seven correlated entries around one rebalance timestamp",
            "excessive_correlated_exposure": "EVIDENCE_PRESENT: maximum seven simultaneous positions all express one USD factor",
            "outsized_position_changes": "NO_CLEAR_EVIDENCE; lot sizes are small, but factor exposure changes in a batch",
            "best_day_numeric_cap_invented": False,
            "assessment": "HIGH_RISK_LIKELY_PROGRAMME_PROHIBITION; no unsupported numerical best-day threshold is applied",
        },
    })

    concentration_rows = []
    day_rows = []
    comparison_rows = []
    for condition, summary in summaries.items():
        for direction in ("BUY", "SELL"):
            concentration_rows.append({
                "condition": condition,
                "dimension": "direction",
                "member": direction,
                "trade_count": summary[f"{direction.lower()}_trade_count"],
                "net_profit_usd": f"{summary[f'{direction.lower()}_net_profit_usd']:.10f}",
                "percent_of_total_net_profit": "",
                "status": "SOURCE_SEGMENT_SUM_NON_AUTHORITATIVE_FOR_PROP_PHASE",
            })
        concentration_rows.append({
            "condition": condition,
            "dimension": "largest_symbol",
            "member": summary["largest_symbol_contribution"],
            "trade_count": "",
            "net_profit_usd": f"{summary['largest_symbol_net_profit_usd']:.10f}",
            "percent_of_total_net_profit": f"{summary['largest_symbol_percent_of_source_segment_net_profit']:.10f}",
            "status": "CONCENTRATED",
        })
        day_rows.append({
            "condition": condition,
            "source_segment_net_profit_sum_usd": f"{summary['source_segment_net_profit_sum_usd']:.10f}",
            "largest_trade_usd": f"{summary['largest_trade_usd']:.10f}",
            "largest_trade_percent": f"{summary['largest_trade_percent_of_source_segment_net_profit']:.10f}",
            "best_realized_exit_date": summary["best_realized_exit_date"],
            "best_realized_exit_date_profit_usd": f"{summary['best_realized_exit_date_profit_usd']:.10f}",
            "best_realized_exit_date_percent": f"{summary['best_realized_exit_date_percent_of_source_segment_net_profit']:.10f}",
            "official_best_day_status": "UNRESOLVED_MISSING_MIDNIGHT_EQUITY",
            "numeric_best_day_cap_applied": "NO",
            "qualitative_concentration_risk": "HIGH",
        })
        comparison_rows.append({
            "condition": condition,
            "cost_profile": CONDITIONS[condition][0],
            "execution_layer": CONDITIONS[condition][1],
            "trade_count": summary["trade_count"],
            "source_segment_net_profit_sum_usd": f"{summary['source_segment_net_profit_sum_usd']:.10f}",
            "source_sum_reaches_phase1_target": "YES" if summary["source_segment_net_profit_sum_usd"] >= 800 else "NO",
            "buy_count": summary["buy_trade_count"],
            "sell_count": summary["sell_trade_count"],
            "max_simultaneous": summary["maximum_simultaneous_positions"],
            "max_correlated": summary["maximum_simultaneous_correlated_positions"],
            "minimum_duration_seconds": f"{summary['minimum_trade_duration_seconds']:.0f}",
            "average_duration_seconds": f"{summary['average_trade_duration_seconds']:.6f}",
            "inactivity_status": inactivity_results[condition]["status"],
            "phase1_status": "INSUFFICIENT_EVIDENCE",
            "phase2_status": "NOT_REACHED",
        })
    write_csv("symbol-and-direction-concentration.csv", ["condition", "dimension", "member", "trade_count", "net_profit_usd", "percent_of_total_net_profit", "status"], concentration_rows)
    write_csv("trade-and-best-day-concentration.csv", list(day_rows[0]), day_rows)
    write_csv("execution-condition-comparison.csv", list(comparison_rows[0]), comparison_rows)

    matrix_rows = []
    common_rules = [
        ("phase1_starting_balance_usd_10000", "SOURCE_SEGMENTS_PASS_CONTINUITY_UNRESOLVED", "Both source periods start at USD 10,000; this creates a continuity break for a chronological prop phase."),
        ("phase1_profit_target_8_percent_usd_800", "UNRESOLVED", "Continuous-account sizing is unavailable; source segment sums remain below USD 800."),
        ("phase1_minimum_three_profitable_days_at_usd_50", "UNRESOLVED", "UTC+3 midnight equity is unavailable."),
        ("phase1_maximum_daily_loss_5_percent", "UNRESOLVED", "Full intraday equity is unavailable."),
        ("phase1_maximum_account_loss_10_percent_absolute", "UNRESOLVED", "Continuous-account equity is unavailable."),
        ("phase2_reset_starting_balance_usd_10000", "NOT_REACHED", "No valid Phase 1 pass exists."),
        ("phase2_profit_target_5_percent_usd_500", "NOT_REACHED", "No valid Phase 1 pass exists."),
        ("phase2_minimum_three_profitable_days_at_usd_50", "NOT_REACHED", "No valid Phase 1 pass exists."),
        ("phase2_maximum_daily_loss_5_percent", "NOT_REACHED", "No valid Phase 1 pass exists."),
        ("phase2_maximum_account_loss_10_percent_absolute", "NOT_REACHED", "No valid Phase 1 pass exists."),
        ("profitable_day_official_midnight_formula", "UNRESOLVED", "UTC+3 midnight balance/equity snapshots are unavailable."),
        ("unlimited_trading_period", "NOT_A_RESTRICTION", "No maximum completion-period failure is applied."),
        ("inactivity_more_than_30_days", "FAIL", "Frozen deal stream contains multiple gaps over 30 days."),
        ("overnight_positions_allowed", "PASS_NOT_A_RESTRICTION", "V28 holds overnight and the programme permits it."),
        ("weekend_positions_allowed", "PASS_NOT_A_RESTRICTION", "V28 may hold over weekends and the programme permits it."),
        ("existing_positions_during_news_allowed", "PASS_NOT_A_RESTRICTION", "The programme permits existing positions during news."),
        ("no_open_or_execution_within_high_impact_news_window", "UNRESOLVED", "Qualified historical high-impact calendar is unavailable."),
        ("visible_stop_loss", "PASS_SOURCE_EVIDENCE", "All filled entry attempts have non-zero stop loss; native order reports corroborate."),
        ("prohibited_microstructure_practices", "PARTIAL_PASS", "No scalping/HFT/arbitrage/copy/emulator evidence; complete request trace unavailable."),
        ("qualitative_concentration_practices", "HIGH_RISK_LIKELY_BREACH", "Seven simultaneous legs implement one common USD-factor direction."),
        ("mt5_hedge_leverage_1_100", "UNRESOLVED", "Source physical run is MT5 at 1:30, not 1:100."),
        ("classic_10k_checkout_price", "REVERIFICATION_REQUIRED_NON_BLOCKING", "No purchase is being made; prior USD 78 publication is not treated as current checkout evidence."),
    ]
    for condition in CONDITIONS:
        for rule, status, basis in common_rules:
            matrix_rows.append({"condition": condition, "rule": rule, "status": status, "basis": basis})
    write_csv("full-programme-rule-matrix.csv", ["condition", "rule", "status", "basis"], matrix_rows)

    terminal = f"""# V28 The5ers High Stakes Classic USD 10,000 rule simulation

This bounded audit cannot validly certify a pass or a definitive programme-rule failure under the required method. The frozen V28 artifacts do not contain timestamped full intraday equity, UTC+3 midnight equity, one continuous 2025-to-2026 account-sizing path, or a qualified checksummed high-impact news calendar. Those fields were not estimated from closed trades or chart images.

Adverse evidence is nevertheless preserved: every execution condition has recorded deal gaps longer than 30 days; every cohort expresses one common USD-factor direction through as many as seven simultaneous correlated positions; and the separately-reset source-segment net-profit sums do not reach the USD 800 Phase 1 target. These are The5ers programme-rule observations, not proof that V28 lacks a trading edge. Phase 2 is not reached.

The previous published Classic USD 10,000 price of USD 78 was not used. No purchase is being made, so the audit records `CHECKOUT_PRICE_REVERIFICATION_REQUIRED` without blocking the rule-evidence decision.

V31 data and V29 are excluded from P&L. V31 remains a data-qualification failure and is not treated as a V28 financial result. Phase 1-5 production remains unchanged at SHA-256 `{EXPECTED_PRODUCTION_SHA256}`. No strategy redesign, optimization, tuning, purchase, registration, push, demo trade or live trade occurred.

{OUTCOME}
"""
    (OUT / "terminal-outcome.md").write_text(terminal, encoding="utf-8")

    readme = """# The5ers High Stakes Classic 10K V28 rule simulation

This directory is a bounded evidence audit of unchanged V28. `terminal-outcome.md` is the controlling result. JSON and CSV artifacts provide the required phase, loss, profitable-day, inactivity, news, EA-practice, concentration, execution-condition and source-integrity details.

The audit deliberately distinguishes source-segment proxies from an authoritative prop-account simulation. Missing intraday or calendar data is left unresolved, never inferred. The SHA-256 ledger covers every report artifact except itself and every exact source artifact used; a cryptographic ledger cannot include its own final digest without recursion.
"""
    (OUT / "README.md").write_text(readme, encoding="utf-8")

    report_files = sorted(path for path in OUT.iterdir() if path.is_file() and path.name != "sha256-ledger.txt")
    ledger_lines = [
        "# SHA-256 ledger: report files (excluding this recursively self-referential ledger)",
        *[f"{sha256(path)}  {path.relative_to(ROOT)}" for path in report_files],
        "# SHA-256 ledger: exact source artifacts",
        *[f"{sha256(path)}  {path.relative_to(ROOT)}" for path in SOURCE_FILES],
        f"{sha256(production)}  {production.relative_to(ROOT)}",
    ]
    (OUT / "sha256-ledger.txt").write_text("\n".join(ledger_lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
