#!/usr/bin/env python3
"""Build strict trade-by-trade and twelve-cell equivalence evidence for SolTradeV28."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import statistics
from collections import defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FROZEN = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
OUT = ROOT / "reports/backtests/soltrade-v28-live-ea-equivalence"
RUN_ROOT = OUT / "runs"
FROZEN_RUN_ROOT = FROZEN / "performance-runs-attempt2"
RUNS = json.loads((FROZEN / "physical-run-plan.json").read_text())["runs"]
CELLS = json.loads((FROZEN / "formal-cell-plan.json").read_text())["cells"]
FMT = "%Y.%m.%d %H:%M:%S"
TOLERANCE = 1e-10
SPANS = {
    "V28_2025_DEVELOPMENT": (datetime(2025, 1, 6), datetime(2026, 1, 1)),
    "V28_2026_PRESEAL_DEVELOPMENT": (datetime(2026, 1, 5), datetime(2026, 8, 1)),
}


def read(path: Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def pairs(path: Path) -> dict[str, str]:
    return {row["field"]: row["value"] for row in read(path)}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def f(value: str | float | int | None) -> float:
    return float(value or 0)


def dt(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def point_value(symbol: str, price: float) -> float:
    point = 0.001 if symbol == "USDJPY" else 0.00001
    return 100000 * point if symbol.endswith("USD") else 100000 * point / price


def compare_rows(
    run_id: str,
    kind: str,
    original: list[dict[str, str]],
    live: list[dict[str, str]],
    mappings: tuple[tuple[str, str], ...],
    divergences: list[dict],
) -> int:
    before = len(divergences)
    if len(original) != len(live):
        divergences.append(
            {
                "run_id": run_id,
                "kind": kind,
                "row": None,
                "field": "row_count",
                "frozen": len(original),
                "live_ea": len(live),
            }
        )
    for index, (left, right) in enumerate(zip(original, live), 1):
        for frozen_field, live_field in mappings:
            if left.get(frozen_field) != right.get(live_field):
                divergences.append(
                    {
                        "run_id": run_id,
                        "kind": kind,
                        "row": index,
                        "field": frozen_field,
                        "frozen": left.get(frozen_field),
                        "live_ea": right.get(live_field),
                    }
                )
    return len(divergences) - before


def parse_trades(run: dict, base: Path, live: bool) -> list[dict]:
    folder = base / run["run_id"]
    summary = pairs(folder / "run-summary.csv")
    if summary.get("run_evidence_status") != "PASS" or summary.get("open_positions_at_end") != "0":
        raise RuntimeError(f"invalid run {folder}")
    deals = read(folder / "deals.csv")
    transactions = read(folder / "transactions.csv")
    symbol_field = "canonical_symbol" if live else "symbol"
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for deal in deals:
        groups[deal["position_identifier"]].append(deal)
    entry_meta = {
        row["deal_ticket"]: row
        for row in transactions
        if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"
    }
    exit_meta = {
        row["deal_ticket"]: row
        for row in transactions
        if row["record_type"] == "EXIT_TRANSACTION" and row["fill_confirmed"] == "YES"
    }
    result = []
    for position, rows in groups.items():
        entries = [row for row in rows if int(row["entry"]) == 0]
        exits = [row for row in rows if int(row["entry"]) in (1, 2)]
        if len(entries) != 1 or not exits:
            raise RuntimeError(f"unclosed position {folder} {position}")
        entry, exit_row = entries[0], exits[-1]
        metadata = entry_meta[entry["deal_ticket"]]
        exit_transaction = exit_meta.get(exit_row["deal_ticket"])
        symbol = entry[symbol_field]
        volume = f(entry["volume"])
        direction = "BUY" if int(entry["type"]) == 0 else "SELL"
        native_before = sum(
            f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"])
            for row in rows
        )
        native_commission = sum(f(row["commission"]) for row in rows)
        external_commission = volume * 6
        native_net = native_before - external_commission
        pv = point_value(symbol, f(entry["price"]))
        point = 0.001 if symbol == "USDJPY" else 0.00001
        spread = f(metadata["spread_points"]) * pv * volume
        requested_entry = f(metadata["requested_price"])
        actual_entry = f(entry["price"])
        entry_slippage = (
            max(0, (actual_entry - requested_entry) / point * pv * volume)
            if direction == "BUY"
            else max(0, (requested_entry - actual_entry) / point * pv * volume)
        )
        exit_slippage = 0.0
        if exit_transaction:
            requested_exit = f(exit_transaction["requested_price"])
            actual_exit = f(exit_row["price"])
            exit_slippage = (
                max(0, (requested_exit - actual_exit) / point * pv * volume)
                if direction == "BUY"
                else max(0, (actual_exit - requested_exit) / point * pv * volume)
            )
        swap = abs(sum(f(row["swap"]) for row in rows))
        fee = abs(sum(f(row["fee"]) for row in rows))
        friction = spread + external_commission + swap + fee + entry_slippage + exit_slippage
        risk = f(metadata["initial_risk_amount"])
        result.append(
            {
                "position_identifier": int(position),
                "symbol": symbol,
                "direction": direction,
                "entry_time": entry["time"],
                "exit_time": exit_row["time"],
                "entry_price": f(entry["price"]),
                "exit_price": f(exit_row["price"]),
                "volume": volume,
                "initial_risk_amount": risk,
                "native_before": native_before,
                "native_commission": native_commission,
                "external_commission": external_commission,
                "native_net": native_net,
                "native_friction": friction,
                "exit_reason": "STOP_LOSS_EXIT" if int(exit_row["reason"]) == 4 else "MONTHLY_REBALANCE_EXIT",
            }
        )
    return result


def contribution(rows: list[dict], key, net: float) -> float | None:
    if net <= 0:
        return None
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        totals[key(row)] += row["_cash"]
    return max(totals.values()) / net * 100 if totals else None


def metrics(rows: list[dict], cell: dict) -> dict:
    start, end = SPANS[cell["dataset"]]
    equity = peak = 10000.0
    maximum_drawdown = 0.0
    cash = []
    for row in rows:
        value = equity * 0.005 * row["adjusted_net_R"]
        equity += value
        peak = max(peak, equity)
        maximum_drawdown = max(maximum_drawdown, (peak - equity) / peak * 100)
        row["_cash"] = value
        cash.append(value)
    wins = [value for value in cash if value > 0]
    losses = [value for value in cash if value < 0]
    net = sum(cash)
    seconds = (end - start).total_seconds()
    bins = [0.0] * 5
    for row in rows:
        index = min(4, max(0, int((dt(row["exit_time"]) - start).total_seconds() / seconds * 5)))
        bins[index] += row["_cash"]
    return {
        "cell_id": cell["cell_id"],
        "dataset": cell["dataset"],
        "cost_profile": cell["cost_profile"],
        "execution_layer": cell["execution_layer"],
        "initial_synthetic_equity": 10000.0,
        "final_synthetic_equity": equity,
        "adjusted_net_profit": net,
        "gross_profit": sum(wins),
        "gross_loss": sum(losses),
        "profit_factor": sum(wins) / abs(sum(losses)) if losses else None,
        "expectancy_usd": net / len(rows) if rows else None,
        "expectancy_R": statistics.fmean(row["adjusted_net_R"] for row in rows) if rows else None,
        "normalized_expectancy_R": statistics.fmean(row["adjusted_net_R"] for row in rows) if rows else None,
        "naturally_closed_trades": len(rows),
        "winning_trades": len(wins),
        "losing_trades": len(losses),
        "win_rate_percent": len(wins) / len(rows) * 100 if rows else None,
        "relative_drawdown_percent": maximum_drawdown,
        "annualized_return_percent": ((equity / 10000) ** (365 / ((end - start).days)) - 1) * 100,
        "best_trade_contribution_percent": max(cash) / net * 100 if cash and net > 0 else None,
        "best_currency_contribution_percent": contribution(rows, lambda row: row["symbol"], net),
        "best_registered_subperiod_contribution_percent": max(bins) / net * 100 if net > 0 else None,
        "buy_trades": sum(row["direction"] == "BUY" for row in rows),
        "sell_trades": sum(row["direction"] == "SELL" for row in rows),
        "stop_loss_exits": sum(row["exit_reason"] == "STOP_LOSS_EXIT" for row in rows),
        "time_exits": sum(row["exit_reason"] == "MONTHLY_REBALANCE_EXIT" for row in rows),
    }


def main() -> None:
    divergences: list[dict] = []
    schedule = read(FROZEN / "signal-feasibility/signal-schedule.csv")
    signal_mapping = (
        ("dataset", "dataset"),
        ("target", "target"),
        ("symbol", "canonical_symbol"),
        ("orientation", "orientation"),
        ("dollar_factor_return", "dollar_factor_return"),
        ("factor_side", "factor_side"),
        ("chart_direction", "direction"),
        ("recent_h1", "recent_h1"),
        ("recent_close", "recent_close"),
        ("anchor_h1", "anchor_h1"),
        ("anchor_close", "anchor_close"),
        ("scheduled_exit", "scheduled_exit"),
    )
    transaction_fields = (
        "time",
        "dataset",
        "execution_layer",
        "symbol",
        "record_type",
        "signal_time",
        "scheduled_exit",
        "direction",
        "requested_price",
        "actual_price",
        "spread_points",
        "slippage_points",
        "volume",
        "initial_risk_amount",
        "stop_loss",
        "order_ticket",
        "deal_ticket",
        "broker_retcode",
        "fill_confirmed",
        "atr_or_exit_reason",
    )
    transaction_mapping = tuple(
        (field, "canonical_symbol" if field == "symbol" else field) for field in transaction_fields
    )
    deal_fields = (
        "deal_ticket",
        "order_ticket",
        "position_identifier",
        "time",
        "time_msc",
        "entry",
        "type",
        "reason",
        "volume",
        "price",
        "profit",
        "commission",
        "swap",
        "fee",
        "magic",
        "symbol",
        "comment",
        "in_research_window",
    )
    deal_mapping = tuple(
        (field, "canonical_symbol" if field == "symbol" else field) for field in deal_fields
    )
    run_results = []
    parsed_live: dict[str, list[dict]] = {}
    for run in RUNS:
        run_id = run["run_id"]
        frozen_folder = FROZEN_RUN_ROOT / run_id
        live_folder = RUN_ROOT / run_id
        before = len(divergences)
        frozen_signals = [row for row in schedule if row["dataset"] == run["dataset"]]
        live_signals = read(live_folder / "signals.csv")
        signal_differences = compare_rows(
            run_id, "signal", frozen_signals, live_signals, signal_mapping, divergences
        )
        transaction_differences = compare_rows(
            run_id,
            "transaction",
            read(frozen_folder / "transactions.csv"),
            read(live_folder / "transactions.csv"),
            transaction_mapping,
            divergences,
        )
        deal_differences = compare_rows(
            run_id,
            "deal",
            read(frozen_folder / "deals.csv"),
            read(live_folder / "deals.csv"),
            deal_mapping,
            divergences,
        )
        frozen_trades = sorted(
            parse_trades(run, FROZEN_RUN_ROOT, False),
            key=lambda row: (row["exit_time"], row["symbol"], row["position_identifier"]),
        )
        live_trades = sorted(
            parse_trades(run, RUN_ROOT, True),
            key=lambda row: (row["exit_time"], row["symbol"], row["position_identifier"]),
        )
        trade_fields = tuple((field, field) for field in frozen_trades[0])
        trade_differences = compare_rows(
            run_id, "reconciled_trade", frozen_trades, live_trades, trade_fields, divergences
        )
        parsed_live[run_id] = live_trades
        run_results.append(
            {
                "run_id": run_id,
                "dataset": run["dataset"],
                "execution_layer": run["execution_layer"],
                "signals_compared": len(frozen_signals),
                "transactions_compared": len(read(frozen_folder / "transactions.csv")),
                "deals_compared": len(read(frozen_folder / "deals.csv")),
                "closed_trades_compared": len(frozen_trades),
                "signal_differences": signal_differences,
                "transaction_differences": transaction_differences,
                "deal_differences": deal_differences,
                "reconciled_trade_differences": trade_differences,
                "total_differences": len(divergences) - before,
                "status": "PASS" if len(divergences) == before else "FAIL",
            }
        )
    live_metrics = []
    for cell in CELLS:
        rows = [row.copy() for row in parsed_live[cell["source_run"]]]
        for row in rows:
            row["supplementary_charge"] = row["native_friction"] * cell["supplementary_multiplier"]
            row["adjusted_trade_net"] = row["native_net"] - row["supplementary_charge"]
            row["adjusted_net_R"] = row["adjusted_trade_net"] / row["initial_risk_amount"]
        live_metrics.append(metrics(rows, cell))
    frozen_metrics = {row["cell_id"]: row for row in read(FROZEN / "phase6-v28-formal-cell-metrics.csv")}
    maximum_metric_delta = 0.0
    for row in live_metrics:
        frozen_row = frozen_metrics[row["cell_id"]]
        for field, value in row.items():
            if field in ("cell_id", "dataset", "cost_profile", "execution_layer"):
                if str(value) != frozen_row[field]:
                    divergences.append(
                        {
                            "run_id": row["cell_id"],
                            "kind": "formal_metric",
                            "row": None,
                            "field": field,
                            "frozen": frozen_row[field],
                            "live_ea": value,
                        }
                    )
                continue
            delta = abs(f(value) - f(frozen_row[field]))
            maximum_metric_delta = max(maximum_metric_delta, delta)
            if not math.isfinite(delta) or delta > TOLERANCE:
                divergences.append(
                    {
                        "run_id": row["cell_id"],
                        "kind": "formal_metric",
                        "row": None,
                        "field": field,
                        "frozen": frozen_row[field],
                        "live_ea": value,
                        "absolute_difference": delta,
                    }
                )
    with (OUT / "live-ea-formal-cell-metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(live_metrics[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(live_metrics)
    (OUT / "divergence-ledger.json").write_text(
        json.dumps(
            {
                "schema": "SOLTRADE_V28_LIVE_EA_DIVERGENCE_LEDGER_V1",
                "numeric_metric_tolerance": TOLERANCE,
                "count": len(divergences),
                "divergences": divergences,
            },
            indent=2,
            allow_nan=False,
        )
        + "\n"
    )
    normal_native = [
        row
        for row in live_metrics
        if row["cost_profile"] == "NORMAL" and row["execution_layer"] == "NATIVE_NORMAL_EXECUTION"
    ]
    result = {
        "schema": "SOLTRADE_V28_LIVE_EA_EQUIVALENCE_PROOF_V1",
        "status": "PASS" if not divergences else "FAIL",
        "source_sha256": sha(ROOT / "MQL5/Experts/SolTradeV28.mq5"),
        "compiled_ex5_sha256": sha(Path("/home/tibule12/.wine-fpmarkets/drive_c/v28-live-ea/SolTradeV28.ex5")),
        "frozen_signal_schedule_sha256": sha(FROZEN / "signal-feasibility/signal-schedule.csv"),
        "physical_runs": 4,
        "formal_cells": 12,
        "real_tick_model": True,
        "optimization": False,
        "rounding_tolerance": {
            "timestamps_seconds": 0,
            "directions": "exact",
            "prices_stops_volumes": "exact serialized MT5 values",
            "aggregate_numeric_absolute": TOLERANCE,
        },
        "trade_count": {
            "frozen_native_total": 105,
            "live_ea_native_total": sum(row["naturally_closed_trades"] for row in normal_native),
            "frozen_2025": 70,
            "live_ea_2025": normal_native[0]["naturally_closed_trades"],
            "frozen_2026": 35,
            "live_ea_2026": normal_native[1]["naturally_closed_trades"],
        },
        "normal_native_metrics": normal_native,
        "maximum_metric_absolute_difference": maximum_metric_delta,
        "unexplained_difference_count": len(divergences),
        "runs": run_results,
    }
    (OUT / "equivalence-proof.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    print(json.dumps(result, indent=2, allow_nan=False))
    if divergences:
        raise SystemExit("SOLTRADE_V28_LIVE_EA_EQUIVALENCE_FAILED")


if __name__ == "__main__":
    main()
