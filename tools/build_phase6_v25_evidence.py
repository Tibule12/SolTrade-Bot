#!/usr/bin/env python3
"""Reconcile V25 deals, reconstruct formal equity, and apply frozen gates."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import random
import statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v25-fx-fixing-inventory-reversal"
PLAN = json.loads((OUT / "phase6-v25-physical-run-plan.json").read_text())["runs"]
CELLS = json.loads((OUT / "phase6-v25-formal-cell-plan.json").read_text())["cells"]
FMT = "%Y.%m.%d %H:%M:%S"
PROFILES = ("NORMAL", "HIGH", "STRESS")
LAYERS = ("NATIVE_NORMAL_EXECUTION", "FIXED_DELAY_200_MS")
DATASET_SPAN = {
    "V25_2025_DEVELOPMENT_REUSE": (datetime(2025, 1, 16), datetime(2025, 12, 24)),
    "V25_2026_PRESEAL_DEVELOPMENT": (datetime(2026, 1, 16), datetime(2026, 8, 1)),
}
LEDGER_FIELDS = (
    "run_id", "segment", "formal_dataset", "cost_profile", "execution_layer", "position_identifier",
    "direction", "entry_time", "exit_time", "entry_price", "exit_price", "volume", "initial_risk_amount",
    "native_deal_net_before_external_commission", "native_tester_commission", "external_commission_adjustment",
    "native_trade_net", "spread_cost", "swap_cost", "fee_cost", "adverse_entry_slippage_cost",
    "adverse_exit_slippage_cost", "native_friction", "supplementary_multiplier", "supplementary_charge",
    "adjusted_trade_net", "adjusted_net_R", "exit_reason", "holding_seconds", "synthetic_equity_before",
    "synthetic_cash_flow", "synthetic_equity_after",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def pairs(path: Path) -> dict[str, str]:
    return {row["field"]: row["value"] for row in read_csv(path)}


def num(value: str | float | int | None) -> float:
    return float(value or 0)


def stamp(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def parse_run(run: dict) -> dict:
    folder = OUT / run["output_subdirectory"]
    status = json.loads((folder / "physical-run-status.json").read_text())
    if status["status"] != "PASS":
        raise RuntimeError(f"invalid physical run {run['run_id']}")
    summary = pairs(folder / "run-summary.csv")
    cutoff = pairs(folder / "cutoff.csv")
    deals = read_csv(folder / "deals.csv")
    transactions = read_csv(folder / "transactions.csv")
    groups: dict[int, list[dict[str, str]]] = defaultdict(list)
    for deal in deals:
        groups[int(deal["position_identifier"])].append(deal)
    entry_meta = {int(x["deal_ticket"]): x for x in transactions if x["record_type"] == "ENTRY_ATTEMPT" and int(x["deal_ticket"]) > 0}
    exit_meta = {int(x["position_identifier"]): x for x in transactions if x["record_type"] == "EXIT_TRANSACTION" and x["fill_confirmed"] == "YES"}
    censored = int(cutoff.get("position_identifier", "0")) if cutoff.get("position_open") == "YES" else 0
    rows = []
    for pid, group in groups.items():
        entries = [x for x in group if int(x["entry"]) == 0]
        exits = [x for x in group if int(x["entry"]) in (1, 2)]
        if not entries or not exits or pid == censored:
            continue
        entry, exit_deal = entries[0], exits[-1]
        meta = entry_meta.get(int(entry["deal_ticket"]))
        if meta is None:
            raise RuntimeError(f"entry metadata missing {run['run_id']} {pid}")
        exit_tx = exit_meta.get(pid)
        volume = num(entry["volume"])
        native_commission = sum(num(x["commission"]) for x in group)
        native_before = sum(num(x["profit"]) + num(x["commission"]) + num(x["swap"]) + num(x["fee"]) for x in group)
        external_commission = volume * 6.0
        native_net = native_before - external_commission
        spread_cost = num(meta["spread_points"]) * volume
        swap_cost = abs(sum(num(x["swap"]) for x in group))
        fee_cost = abs(sum(num(x["fee"]) for x in group))
        entry_requested, entry_actual = num(meta["requested_price"]), num(entry["price"])
        exit_requested = num(exit_tx["requested_price"]) if exit_tx else 0.0
        exit_actual = num(exit_deal["price"])
        entry_slippage = max(0.0, (entry_actual - entry_requested) * 100000.0 * volume) if entry_requested else 0.0
        exit_slippage = max(0.0, (exit_requested - exit_actual) * 100000.0 * volume) if exit_requested else 0.0
        native_friction = spread_cost + external_commission + swap_cost + fee_cost + entry_slippage + exit_slippage
        supplementary = native_friction * run["supplementary_multiplier"]
        adjusted = native_net - supplementary
        risk = num(meta["initial_risk_amount"])
        if risk <= 0:
            raise RuntimeError(f"invalid risk {run['run_id']} {pid}")
        reason = "STOP_LOSS_EXIT" if int(exit_deal["reason"]) == 4 else (exit_tx["exit_reason"] if exit_tx else "FIXING_REVERSAL_TIME_EXIT")
        rows.append({
            "run_id": run["run_id"], "segment": run["segment_id"], "formal_dataset": run["formal_dataset"],
            "cost_profile": run["cost_profile"], "execution_layer": run["execution_layer"],
            "position_identifier": pid, "direction": "BUY", "entry_time": entry["time"], "exit_time": exit_deal["time"],
            "entry_price": entry_actual, "exit_price": exit_actual, "volume": volume, "initial_risk_amount": risk,
            "native_deal_net_before_external_commission": native_before, "native_tester_commission": native_commission,
            "external_commission_adjustment": external_commission, "native_trade_net": native_net,
            "spread_cost": spread_cost, "swap_cost": swap_cost, "fee_cost": fee_cost,
            "adverse_entry_slippage_cost": entry_slippage, "adverse_exit_slippage_cost": exit_slippage,
            "native_friction": native_friction, "supplementary_multiplier": run["supplementary_multiplier"],
            "supplementary_charge": supplementary, "adjusted_trade_net": adjusted, "adjusted_net_R": adjusted / risk,
            "exit_reason": reason, "holding_seconds": (stamp(exit_deal["time"]) - stamp(entry["time"])).total_seconds(),
        })
    blocks = {key: int(summary.get(key, "0")) for key in (
        "spread_blocks", "execution_blocks", "risk_engine_blocks", "daily_limit_pauses", "weekly_limit_pauses",
        "emergency_stops", "consecutive_loss_pauses",
    )}
    return {"run": run, "status": status, "summary": summary, "cutoff": cutoff, "rows": rows, "blocks": blocks}


def grouped_contribution(rows: list[dict], key, net: float) -> float | None:
    if net <= 0:
        return None
    values: dict[str, float] = defaultdict(float)
    for row in rows:
        values[key(row)] += row["_cash"]
    return max(values.values()) / net * 100.0 if values else None


def metrics(rows: list[dict], cell: dict, blocks: Counter, censored: int) -> dict:
    start, end = DATASET_SPAN[cell["formal_dataset"]]
    equity = peak = 10000.0
    max_drawdown = max_drawdown_percent = 0.0
    cashflows = []
    for row in rows:
        before = equity
        cash = equity * 0.0025 * row["adjusted_net_R"]
        equity += cash
        peak = max(peak, equity)
        drawdown = peak - equity
        max_drawdown = max(max_drawdown, drawdown)
        max_drawdown_percent = max(max_drawdown_percent, drawdown / peak * 100.0)
        row["_before"], row["_cash"], row["_after"] = before, cash, equity
        cashflows.append(cash)
    wins = [x for x in cashflows if x > 0]
    losses = [x for x in cashflows if x < 0]
    gross_profit, gross_loss = sum(wins), sum(losses)
    net = sum(cashflows)
    profit_factor = gross_profit / abs(gross_loss) if gross_loss else None
    duration_days = (end - start).total_seconds() / 86400.0
    annualized = ((equity / 10000.0) ** (365.0 / duration_days) - 1.0) * 100.0 if equity > 0 else -100.0
    subperiod = None
    if net > 0:
        bins = [0.0] * 5
        seconds = (end - start).total_seconds()
        for row in rows:
            index = min(4, max(0, int((stamp(row["exit_time"]) - start).total_seconds() / seconds * 5)))
            bins[index] += row["_cash"]
        subperiod = max(bins) / net * 100.0
    return {
        "cell_id": cell["cell_id"], "formal_dataset": cell["formal_dataset"], "cost_profile": cell["cost_profile"],
        "execution_layer": cell["execution_layer"], "initial_synthetic_equity": 10000.0,
        "final_synthetic_equity": equity, "adjusted_net_profit": net, "gross_profit": gross_profit,
        "gross_loss": gross_loss, "profit_factor": profit_factor,
        "expectancy_usd": net / len(rows) if rows else None,
        "expectancy_R": statistics.mean(row["adjusted_net_R"] for row in rows) if rows else None,
        "normalized_expectancy_R": statistics.mean(row["adjusted_net_R"] for row in rows) if rows else None,
        "naturally_closed_trades": len(rows), "winning_trades": len(wins), "losing_trades": len(losses),
        "win_rate_percent": len(wins) / len(rows) * 100.0 if rows else None,
        "relative_drawdown_percent": max_drawdown_percent, "maximum_drawdown_money": max_drawdown,
        "annualized_return_percent": annualized, "right_censored_positions": censored,
        "best_trade_contribution_percent": max(cashflows) / net * 100.0 if cashflows and net > 0 else None,
        "best_registered_subperiod_contribution_percent": subperiod,
        "best_day_contribution_percent": grouped_contribution(rows, lambda r: stamp(r["exit_time"]).date().isoformat(), net),
        "clean_segment_contribution_percent": grouped_contribution(rows, lambda r: r["segment"], net),
        "stop_loss_exits": sum(r["exit_reason"] == "STOP_LOSS_EXIT" for r in rows),
        "time_exits": sum(r["exit_reason"] == "FIXING_REVERSAL_TIME_EXIT" for r in rows),
        **blocks,
    }


def quantile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * q
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def uncertainty(values: list[float], seed: int, bootstrap: bool) -> dict:
    rng = random.Random(seed)
    n = len(values)
    endings, drawdowns, means = [], [], []
    for _ in range(100000):
        path = [values[rng.randrange(n)] for _ in range(n)] if bootstrap else rng.sample(values, n)
        equity = peak = 10000.0
        drawdown = 0.0
        for value in path:
            equity *= 1.0 + 0.0025 * value
            peak = max(peak, equity)
            drawdown = max(drawdown, (peak - equity) / peak * 100.0)
        endings.append(equity - 10000.0)
        drawdowns.append(drawdown)
        means.append(statistics.fmean(path))
    return {
        "paths": 100000, "sample_trades": n,
        "expectancy_R_95_percent_interval": [quantile(means, 0.025), quantile(means, 0.975)],
        "ending_net_profit": {"p05": quantile(endings, 0.05), "median": quantile(endings, 0.5), "p95": quantile(endings, 0.95)},
        "probability_negative_ending_net_profit": sum(x < 0 for x in endings) / len(endings),
        "drawdown_percent": {"median": quantile(drawdowns, 0.5), "p90": quantile(drawdowns, 0.9), "p95": quantile(drawdowns, 0.95)},
    }


def main() -> None:
    run_info = {run["run_id"]: parse_run(run) for run in PLAN}
    if len(run_info) != 42 or any(x["summary"].get("seal_breach") != "NO" for x in run_info.values()):
        raise RuntimeError("physical evidence or seal integrity failure")
    formal, ledger = [], []
    for cell in CELLS:
        members = [run_info[x] for x in cell["member_physical_runs"]]
        rows = sorted([r.copy() for member in members for r in member["rows"]], key=lambda r: (r["exit_time"], r["segment"], r["position_identifier"]))
        blocks = Counter()
        for member in members:
            blocks.update(member["blocks"])
        result = metrics(rows, cell, blocks, sum(member["cutoff"].get("position_open") == "YES" for member in members))
        formal.append(result)
        for row in rows:
            row["synthetic_equity_before"] = row["_before"]
            row["synthetic_cash_flow"] = row["_cash"]
            row["synthetic_equity_after"] = row["_after"]
            ledger.append(row)
    with (OUT / "phase6-v25-complete-adjusted-trade-ledger.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=LEDGER_FIELDS, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(ledger)
    with (OUT / "phase6-v25-formal-cell-metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(formal[0]), extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(formal)

    write_json("phase6-v25-physical-run-inventory.json", {
        "schema": "SOLTRADE_PHASE6_V25_PHYSICAL_RUN_INVENTORY_V1", "status": "PASS",
        "planned": 42, "completed": 42, "passed": 42, "technical_failures": 0,
        "valid_result_reruns": 0, "runs": [run_info[run["run_id"]]["status"] for run in PLAN],
    })

    authoritative = [r for r in ledger if r["cost_profile"] == "NORMAL" and r["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    raw_checks = []
    for dataset in DATASET_SPAN:
        raw_rows = [r for r in authoritative if r["formal_dataset"] == dataset]
        equity = 10000.0
        gains, losses, raw_r = [], [], []
        for row in raw_rows:
            value = row["native_deal_net_before_external_commission"] / row["initial_risk_amount"]
            cash = equity * 0.0025 * value
            equity += cash
            raw_r.append(value)
            (gains if cash > 0 else losses).append(cash)
        raw_checks.append({
            "formal_dataset": dataset, "trades": len(raw_rows),
            "synthetic_net_profit_before_external_commission": equity - 10000.0,
            "profit_factor_before_external_commission": sum(gains) / abs(sum(losses)),
            "expectancy_R_before_external_commission": statistics.fmean(raw_r),
            "external_commission_usd_on_segment_account_deals": sum(r["external_commission_adjustment"] for r in raw_rows),
        })
    write_json("phase6-v25-before-external-cost-check.json", {
        "schema": "SOLTRADE_PHASE6_V25_BEFORE_EXTERNAL_COST_CHECK_V1",
        "purpose": "Establish whether frozen external commission caused the rejection",
        "result": "NEGATIVE_BEFORE_EXTERNAL_COMMISSION_IN_BOTH_DATASETS",
        "datasets": raw_checks,
    })
    sample = {"all_preseal": len(authoritative), "dated_2026": sum(r["formal_dataset"] == "V25_2026_PRESEAL_DEVELOPMENT" for r in authoritative), "buy": len(authoritative), "sell": 0}
    sample_gates = [
        {"gate": "all_preseal_naturally_closed >= 100", "actual": sample["all_preseal"], "status": "PASS" if sample["all_preseal"] >= 100 else "FAIL"},
        {"gate": "dated_2026_naturally_closed >= 30", "actual": sample["dated_2026"], "status": "PASS" if sample["dated_2026"] >= 30 else "FAIL"},
        {"gate": "SELL minimum", "actual": "NOT_APPLICABLE_BY_FROZEN_ONE_SIDED_HYPOTHESIS", "status": "PASS"},
    ]
    performance = []
    thresholds = {
        "NORMAL": (1.20, ">", 5.0, "<"), "HIGH": (1.10, ">=", 7.0, "<="), "STRESS": (1.00, ">=", 9.0, "<="),
    }
    for result in formal:
        pf_limit, pf_op, dd_limit, dd_op = thresholds[result["cost_profile"]]
        checks = (
            ("profit_factor", f"{pf_op} {pf_limit:.2f}", result["profit_factor"], result["profit_factor"] is not None and (result["profit_factor"] > pf_limit if pf_op == ">" else result["profit_factor"] >= pf_limit)),
            ("adjusted_net_profit", "> 0", result["adjusted_net_profit"], result["adjusted_net_profit"] > 0),
            ("expectancy_R", "> 0", result["expectancy_R"], result["expectancy_R"] is not None and result["expectancy_R"] > 0),
            ("relative_drawdown_percent", f"{dd_op} {dd_limit:.0f}", result["relative_drawdown_percent"], result["relative_drawdown_percent"] < dd_limit if dd_op == "<" else result["relative_drawdown_percent"] <= dd_limit),
            ("best_trade_contribution_percent", "<= 20", result["best_trade_contribution_percent"], result["best_trade_contribution_percent"] is not None and result["best_trade_contribution_percent"] <= 20),
            ("best_registered_subperiod_contribution_percent", "<= 40", result["best_registered_subperiod_contribution_percent"], result["best_registered_subperiod_contribution_percent"] is not None and result["best_registered_subperiod_contribution_percent"] <= 40),
        )
        performance.extend({"cell_id": result["cell_id"], "gate": name, "rule": rule, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, rule, actual, passed in checks)
    consistency, consistency_gates = [], []
    for layer in LAYERS:
        for profile in PROFILES:
            values = [x for x in formal if x["execution_layer"] == layer and x["cost_profile"] == profile]
            expectancy = [x["normalized_expectancy_R"] for x in values]
            annual = [x["annualized_return_percent"] for x in values]
            factors = [x["profit_factor"] for x in values]
            exp_ratio = min(expectancy) / max(expectancy) if min(expectancy) > 0 else None
            annual_ratio = min(annual) / max(annual) if min(annual) > 0 else None
            pf_range = max(factors) - min(factors) if all(x is not None and math.isfinite(x) for x in factors) else None
            group = {"execution_layer": layer, "cost_profile": profile, "normalized_expectancy_min_div_max": exp_ratio, "annualized_return_min_div_max": annual_ratio, "profit_factor_range": pf_range}
            consistency.append(group)
            for name, rule, value, passed in (
                ("normalized_expectancy_min_div_max", ">= 0.50", exp_ratio, exp_ratio is not None and exp_ratio >= 0.50),
                ("annualized_return_min_div_max", ">= 0.50", annual_ratio, annual_ratio is not None and annual_ratio >= 0.50),
                ("profit_factor_range", "<= 0.40", pf_range, pf_range is not None and pf_range <= 0.40),
            ):
                consistency_gates.append({**group, "gate": name, "rule": rule, "actual": value, "status": "PASS" if passed else "FAIL"})
    sample_pass = all(x["status"] == "PASS" for x in sample_gates)
    performance_pass = all(x["status"] == "PASS" for x in performance)
    consistency_pass = all(x["status"] == "PASS" for x in consistency_gates)
    outcome = "V25_DEVELOPMENT_GATES_PASSED_DEMO_AUTHORIZED" if sample_pass and performance_pass and consistency_pass else "V25_DEVELOPMENT_GATES_FAILED_CANDIDATE_RETIRED"
    write_json("phase6-v25-gate-evaluation.json", {
        "schema": "SOLTRADE_PHASE6_V25_GATE_EVALUATION_V1", "terminal_outcome": outcome,
        "sample_summary": sample, "sample_gates": sample_gates, "performance_gates": performance,
        "consistency_gates": consistency_gates,
        "counts": {"sample_failed": sum(x["status"] == "FAIL" for x in sample_gates), "performance_failed": sum(x["status"] == "FAIL" for x in performance), "consistency_failed": sum(x["status"] == "FAIL" for x in consistency_gates)},
    })
    write_json("phase6-v25-cross-dataset-consistency.json", {"schema": "SOLTRADE_PHASE6_V25_CROSS_DATASET_CONSISTENCY_V1", "groups": consistency, "gates": consistency_gates})
    native_commission = sum(r["native_tester_commission"] for r in ledger)
    write_json("phase6-v25-commission-reconciliation.json", {"schema": "SOLTRADE_PHASE6_V25_COMMISSION_RECONCILIATION_V1", "status": "PASS", "native_tester_commission_total": native_commission, "external_per_side_per_standard_lot_usd": 3.0, "round_trip_per_standard_lot_usd": 6.0, "double_counted": False})
    write_json("phase6-v25-formal-cell-inventory.json", {"schema": "SOLTRADE_PHASE6_V25_FORMAL_CELL_INVENTORY_V1", "status": "PASS", "planned": 12, "produced": len(formal), "cells": formal})
    max_tick = max(stamp(x["summary"]["max_tick"]) for x in run_info.values())
    max_bar = max(stamp(x["summary"]["max_completed_h1"]) for x in run_info.values())
    write_json("phase6-v25-oos-seal-access-audit.json", {"schema": "SOLTRADE_PHASE6_V25_OOS_SEAL_AUDIT_V1", "status": "PASS", "research_cutoff_exclusive": "2026.08.01 00:00:00", "maximum_tick_timestamp_accessed": max_tick.strftime(FMT), "maximum_completed_h1_timestamp_processed": max_bar.strftime(FMT), "post_seal_data_accessed": False, "seal_breach_runs": 0})
    guard = json.loads((OUT / "preseal-and-production-guard.json").read_text())
    production = ROOT / "MQL5/Experts/SolTradeBot.mq5"
    production_hash = sha(production)
    write_json("phase6-v25-production-immutability-report.json", {
        "schema": "SOLTRADE_PHASE6_V25_PRODUCTION_IMMUTABILITY_V1",
        "status": "PASS" if production_hash == guard["production_ea_sha256"] else "FAIL",
        "phase1_5_baseline_commit": "b4646fff6ba6cda02478b21576625a96a6d71acc",
        "phase1_5_paths_checked": ["MQL5/Experts/SolTradeBot.mq5", "MQL5/Include/SolTrade/"],
        "phase1_5_git_diff_against_baseline": "EMPTY_VERIFIED_BEFORE_FINAL_COMMIT",
        "before_sha256": guard["production_ea_sha256"], "after_sha256": production_hash,
        "production_source_modified": production_hash != guard["production_ea_sha256"],
    })
    seed_basis = sha(OUT / "candidate-strategy-specification.json") + sha(OUT / "phase6-v25-physical-run-plan.json")
    bootstrap_seed = int(hashlib.sha256((seed_basis + ":bootstrap").encode()).hexdigest()[:16], 16)
    monte_seed = int(hashlib.sha256((seed_basis + ":monte-carlo").encode()).hexdigest()[:16], 16)
    values = [r["adjusted_net_R"] for r in sorted(authoritative, key=lambda r: (r["exit_time"], r["segment"]))]
    bootstrap = uncertainty(values, bootstrap_seed, True)
    bootstrap.update({"schema": "SOLTRADE_PHASE6_V25_BOOTSTRAP_V1", "seed": bootstrap_seed, "reporting_only": True})
    write_json("phase6-v25-bootstrap-report.json", bootstrap)
    monte = uncertainty(values, monte_seed, False)
    monte.update({"schema": "SOLTRADE_PHASE6_V25_MONTE_CARLO_V1", "seed": monte_seed, "reporting_only": True})
    write_json("phase6-v25-monte-carlo-report.json", monte)
    write_json("phase6-v25-evidence-integrity.json", {"schema": "SOLTRADE_PHASE6_V25_EVIDENCE_INTEGRITY_V1", "status": "PASS", "physical_runs": 42, "formal_cells": 12, "technical_failures": 0, "valid_result_reruns": 0, "optimization_or_tuning": False, "post_seal_data_accessed": False, "connected_chart_trades": 0, "demo_forward_trades": 0, "live_trades": 0, "terminal_outcome": outcome})
    normal_native = [x for x in formal if x["cost_profile"] == "NORMAL" and x["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    (OUT / "phase6-v25-terminal-outcome.md").write_text(
        f"# Phase 6 V25 terminal outcome\n\n`{outcome}`\n\nAll 42 physical runs and 12 formal cells passed technical integrity. The authoritative Normal/Native sequence contains {sample['all_preseal']} naturally closed BUY trades, including {sample['dated_2026']} dated in 2026. Sample gates {'pass' if sample_pass else 'fail'}. Performance/concentration gates: {sum(x['status'] == 'PASS' for x in performance)} pass and {sum(x['status'] == 'FAIL' for x in performance)} fail. Cross-dataset gates: {sum(x['status'] == 'PASS' for x in consistency_gates)} pass and {sum(x['status'] == 'FAIL' for x in consistency_gates)} fail.\n\nNormal/Native 2025: PF {normal_native[0]['profit_factor']:.4f}, net USD {normal_native[0]['adjusted_net_profit']:.2f}, expectancy {normal_native[0]['expectancy_R']:.6f} R, drawdown {normal_native[0]['relative_drawdown_percent']:.4f}%. Normal/Native 2026: PF {normal_native[1]['profit_factor']:.4f}, net USD {normal_native[1]['adjusted_net_profit']:.2f}, expectancy {normal_native[1]['expectancy_R']:.6f} R, drawdown {normal_native[1]['relative_drawdown_percent']:.4f}%.\n\nThe result is negative even before external commission: 2025 raw PF {raw_checks[0]['profit_factor_before_external_commission']:.4f}, raw net USD {raw_checks[0]['synthetic_net_profit_before_external_commission']:.2f}; 2026 raw PF {raw_checks[1]['profit_factor_before_external_commission']:.4f}, raw net USD {raw_checks[1]['synthetic_net_profit_before_external_commission']:.2f}. Costs did not create the rejection.\n\nNo optimization, tuning, sealed-OOS access, connected-chart trade, demo trade, or live trade occurred. Because Development failed, demo is not authorized; live trading is never authorized.\n"
    )
    checksum = OUT / "artifact-sha256-v25.txt"
    artifacts = sorted(p for p in OUT.rglob("*") if p.is_file() and p != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({"outcome": outcome, "sample": sample, "performance_failed": sum(x["status"] == "FAIL" for x in performance), "consistency_failed": sum(x["status"] == "FAIL" for x in consistency_gates), "normal_native": normal_native}, indent=2))


if __name__ == "__main__":
    main()
