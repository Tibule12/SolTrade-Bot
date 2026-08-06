#!/usr/bin/env python3
"""Compare V31A original/adapter runs with a 1e-10 semantic tolerance."""
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
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence"
RUNS = json.loads((ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum/physical-run-plan.json").read_text())["runs"]
RUN_ROOT = OUT / "equivalence-runs"
TOLERANCE = 1e-10
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
MAPPING = {symbol: symbol + ".V31" for symbol in SYMBOLS}
NUMERIC_TX = ("requested_price", "actual_price", "spread_points", "slippage_points", "volume", "initial_risk_amount", "stop_loss", "order_ticket", "deal_ticket")
SEMANTIC_TX = ("time", "dataset", "execution_layer", "record_type", "signal_time", "scheduled_exit", "direction", "broker_retcode", "fill_confirmed", "atr_or_exit_reason")
NUMERIC_DEAL = ("deal_ticket", "order_ticket", "position_identifier", "time_msc", "entry", "type", "reason", "volume", "price", "profit", "commission", "swap", "fee", "magic")
SEMANTIC_DEAL = ("time", "comment", "in_research_window")
FMT = "%Y.%m.%d %H:%M:%S"


def read(path: Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def pairs(path: Path) -> dict[str, str]:
    return {row["field"]: row["value"] for row in read(path)}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def f(value: str | float | int | None) -> float:
    return float(value or 0)


def canonical_tx(row: dict[str, str], side: str) -> dict[str, str]:
    symbol = row["canonical_symbol"] if side == "adapter" else row["symbol"]
    result = {"canonical_symbol": symbol}
    result.update({field: row[field] for field in SEMANTIC_TX})
    result.update({field: row[field] for field in NUMERIC_TX})
    return result


def canonical_deal(row: dict[str, str], side: str) -> dict[str, str]:
    symbol = row["canonical_symbol"] if side == "adapter" else row["symbol"]
    result = {"canonical_symbol": symbol}
    result.update({field: row[field] for field in SEMANTIC_DEAL})
    result.update({field: row[field] for field in NUMERIC_DEAL})
    return result


def canonical_event(row: dict[str, str]) -> dict[str, str]:
    details = row["details"].replace(".V31", "")
    canonical_symbol = row.get("canonical_symbol", "")
    if not canonical_symbol:
        for symbol in SYMBOLS:
            if details == symbol:
                canonical_symbol, details = symbol, ""
                break
            if details.startswith(symbol + ";"):
                canonical_symbol, details = symbol, details[len(symbol) + 1 :]
                break
    return {
        "time": row["time"],
        "dataset": row["dataset"],
        "execution_layer": row["execution_layer"],
        "canonical_symbol": canonical_symbol,
        "event_type": row["event_type"],
        "reason_code": row["reason_code"],
        "details": details,
    }


def compare_rows(kind: str, run_id: str, left: list[dict[str, str]], right: list[dict[str, str]], numeric: tuple[str, ...], divergences: list[dict]) -> dict:
    compared = min(len(left), len(right))
    field_comparisons = 0
    max_abs_difference = 0.0
    if len(left) != len(right):
        divergences.append({"run_id": run_id, "kind": kind, "row": None, "field": "row_count", "original": len(left), "adapter": len(right), "absolute_difference": abs(len(left) - len(right))})
    for index in range(compared):
        fields = sorted(set(left[index]) | set(right[index]))
        for field in fields:
            field_comparisons += 1
            if field in numeric:
                delta = abs(f(left[index].get(field)) - f(right[index].get(field)))
                max_abs_difference = max(max_abs_difference, delta)
                if not math.isfinite(delta) or delta > TOLERANCE:
                    divergences.append({"run_id": run_id, "kind": kind, "row": index + 1, "field": field, "original": left[index].get(field), "adapter": right[index].get(field), "absolute_difference": delta})
            elif left[index].get(field) != right[index].get(field):
                divergences.append({"run_id": run_id, "kind": kind, "row": index + 1, "field": field, "original": left[index].get(field), "adapter": right[index].get(field), "absolute_difference": None})
    return {"rows_original": len(left), "rows_adapter": len(right), "rows_compared": compared, "field_comparisons": field_comparisons, "max_numeric_absolute_difference": max_abs_difference}


def point_value(symbol: str, price: float) -> float:
    point = 0.001 if symbol == "USDJPY" else 0.00001
    return 100000 * point if symbol.endswith("USD") else 100000 * point / price


def adjusted_rows(folder: Path, side: str) -> list[dict]:
    deals = read(folder / "deals.csv")
    tx = read(folder / "transactions.csv")
    symbol_key = "canonical_symbol" if side == "adapter" else "symbol"
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in deals:
        groups[row["position_identifier"]].append(row)
    entry_meta = {row["deal_ticket"]: row for row in tx if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"}
    exit_meta = {row["deal_ticket"]: row for row in tx if row["record_type"] == "EXIT_TRANSACTION" and row["fill_confirmed"] == "YES"}
    result = []
    for position, rows in groups.items():
        entries = [row for row in rows if int(row["entry"]) == 0]
        exits = [row for row in rows if int(row["entry"]) in (1, 2)]
        if len(entries) != 1 or not exits:
            raise RuntimeError(f"unclosed position {side} {folder.name} {position}")
        entry, exit_row = entries[0], exits[-1]
        meta = entry_meta[entry["deal_ticket"]]
        exit_tx = exit_meta.get(exit_row["deal_ticket"])
        symbol = entry[symbol_key]
        volume = f(entry["volume"])
        direction = "BUY" if int(entry["type"]) == 0 else "SELL"
        native_before = sum(f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"]) for row in rows)
        external_commission = volume * 6
        native_net = native_before - external_commission
        pv = point_value(symbol, f(entry["price"]))
        point = 0.001 if symbol == "USDJPY" else 0.00001
        spread = f(meta["spread_points"]) * pv * volume
        requested = f(meta["requested_price"])
        actual = f(entry["price"])
        entry_slippage = max(0, (actual - requested) / point * pv * volume) if direction == "BUY" else max(0, (requested - actual) / point * pv * volume)
        exit_slippage = 0.0
        if exit_tx:
            requested_exit, actual_exit = f(exit_tx["requested_price"]), f(exit_row["price"])
            exit_slippage = max(0, (requested_exit - actual_exit) / point * pv * volume) if direction == "BUY" else max(0, (actual_exit - requested_exit) / point * pv * volume)
        friction = spread + external_commission + abs(sum(f(row["swap"]) for row in rows)) + abs(sum(f(row["fee"]) for row in rows)) + entry_slippage + exit_slippage
        risk = f(meta["initial_risk_amount"])
        result.append({
            "canonical_symbol": symbol,
            "direction": direction,
            "entry_time": entry["time"],
            "exit_time": exit_row["time"],
            "entry_price": f(entry["price"]),
            "exit_price": f(exit_row["price"]),
            "volume": volume,
            "initial_risk_amount": risk,
            "native_net": native_net,
            "native_friction": friction,
            "adjusted_net": native_net,
            "adjusted_R": native_net / risk,
        })
    return sorted(result, key=lambda row: (row["exit_time"], row["canonical_symbol"], row["entry_time"]))


def metrics(rows: list[dict]) -> dict:
    equity = peak = 10000.0
    max_drawdown = 0.0
    cash = []
    for row in rows:
        value = equity * 0.005 * row["adjusted_R"]
        equity += value
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, (peak - equity) / peak * 100)
        cash.append(value)
    wins = [value for value in cash if value > 0]
    losses = [value for value in cash if value < 0]
    return {
        "closed_trades": len(rows),
        "adjusted_net_profit": sum(cash),
        "profit_factor": sum(wins) / abs(sum(losses)) if losses else None,
        "expectancy_R": statistics.fmean(row["adjusted_R"] for row in rows) if rows else None,
        "relative_drawdown_percent": max_drawdown,
        "buy_trades": sum(row["direction"] == "BUY" for row in rows),
        "sell_trades": sum(row["direction"] == "SELL" for row in rows),
    }


def main() -> None:
    divergences: list[dict] = []
    parity_runs = []
    metrics_rows = []
    total_events = total_tx = total_deals = total_fields = 0
    max_delta = 0.0
    for run in RUNS:
        run_id = run["run_id"]
        original = RUN_ROOT / "original" / run_id
        adapter = RUN_ROOT / "adapter" / run_id
        for side, folder in (("original", original), ("adapter", adapter)):
            status = json.loads((folder / "physical-run-status.json").read_text())
            if status["status"] != "PASS":
                raise RuntimeError(f"invalid physical run {side} {run_id}")
        original_tx = [canonical_tx(row, "original") for row in read(original / "transactions.csv")]
        adapter_tx = [canonical_tx(row, "adapter") for row in read(adapter / "transactions.csv")]
        original_deals = [canonical_deal(row, "original") for row in read(original / "deals.csv")]
        adapter_deals = [canonical_deal(row, "adapter") for row in read(adapter / "deals.csv")]
        original_events = [canonical_event(row) for row in read(original / "events.csv")]
        adapter_events = [canonical_event(row) for row in read(adapter / "events.csv")]
        before = len(divergences)
        event_result = compare_rows("event", run_id, original_events, adapter_events, (), divergences)
        tx_result = compare_rows("transaction", run_id, original_tx, adapter_tx, NUMERIC_TX, divergences)
        deal_result = compare_rows("deal", run_id, original_deals, adapter_deals, NUMERIC_DEAL, divergences)
        original_adjusted = adjusted_rows(original, "original")
        adapter_adjusted = adjusted_rows(adapter, "adapter")
        adjusted_numeric = ("entry_price", "exit_price", "volume", "initial_risk_amount", "native_net", "native_friction", "adjusted_net", "adjusted_R")
        adjusted_result = compare_rows("adjusted_trade", run_id, original_adjusted, adapter_adjusted, adjusted_numeric, divergences)
        original_metrics, adapter_metrics = metrics(original_adjusted), metrics(adapter_adjusted)
        metrics_rows.append({"run_id": run_id, "original": original_metrics, "adapter": adapter_metrics})
        for field in original_metrics:
            left, right = original_metrics[field], adapter_metrics[field]
            if left is None or right is None:
                if left != right:
                    divergences.append({"run_id": run_id, "kind": "metric", "row": None, "field": field, "original": left, "adapter": right, "absolute_difference": None})
            else:
                delta = abs(float(left) - float(right))
                max_delta = max(max_delta, delta)
                if delta > TOLERANCE:
                    divergences.append({"run_id": run_id, "kind": "metric", "row": None, "field": field, "original": left, "adapter": right, "absolute_difference": delta})
        summary_a, summary_b = pairs(original / "run-summary.csv"), pairs(adapter / "run-summary.csv")
        summary_fields = ("dataset", "execution_layer", "schedule_signals", "processed_signals", "entry_attempts", "entry_fills", "exit_fills", "missed_signals", "spread_blocks", "risk_blocks", "execution_blocks", "open_positions_at_end", "max_tick", "seal_breach", "run_evidence_status")
        for field in summary_fields:
            if summary_a.get(field) != summary_b.get(field):
                divergences.append({"run_id": run_id, "kind": "run_summary", "row": None, "field": field, "original": summary_a.get(field), "adapter": summary_b.get(field), "absolute_difference": None})
        run_divergences = len(divergences) - before
        parity_runs.append({"run_id": run_id, "dataset": run["dataset"], "execution_layer": run["execution_layer"], "execution_mode": run["execution_mode"], "events": event_result, "transactions": tx_result, "deals": deal_result, "adjusted_trades": adjusted_result, "divergences": run_divergences, "status": "PASS" if run_divergences == 0 else "FAIL"})
        total_events += event_result["rows_compared"]
        total_tx += tx_result["rows_compared"]
        total_deals += deal_result["rows_compared"]
        total_fields += event_result["field_comparisons"] + tx_result["field_comparisons"] + deal_result["field_comparisons"] + adjusted_result["field_comparisons"]
        max_delta = max(max_delta, tx_result["max_numeric_absolute_difference"], deal_result["max_numeric_absolute_difference"], adjusted_result["max_numeric_absolute_difference"])
    outcome = "V28_ADAPTER_EQUIVALENCE_PASSED" if not divergences else "V28_ADAPTER_EQUIVALENCE_FAILED"
    mapping = {"schema": "SOLTRADE_PHASE6_V31A_SYMBOL_MAPPING_V1", "mapping": MAPPING, "reporting": "canonical_and_resolved", "strategy_label_if_passed": "STRATEGY_EQUIVALENT_EXTERNAL_FEED_REPLICATION"}
    (OUT / "v31a-symbol-mapping.json").write_text(json.dumps(mapping, indent=2) + "\n")
    (OUT / "v31a-divergence-ledger.json").write_text(json.dumps({"schema": "SOLTRADE_PHASE6_V31A_DIVERGENCE_LEDGER_V1", "numeric_tolerance": TOLERANCE, "count": len(divergences), "divergences": divergences}, indent=2, allow_nan=False) + "\n")
    (OUT / "v31a-original-adapter-metrics.json").write_text(json.dumps({"schema": "SOLTRADE_PHASE6_V31A_METRICS_V1", "cost_profile": "NORMAL_WITH_FROZEN_EXTERNAL_COMMISSION", "runs": metrics_rows}, indent=2, allow_nan=False) + "\n")
    result = {"schema": "SOLTRADE_PHASE6_V31A_EQUIVALENCE_PROOF_V1", "terminal_outcome": outcome, "numeric_tolerance": TOLERANCE, "physical_runs": 8, "run_pairs": 4, "signal_schedule_sha256": sha(ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum/signal-feasibility/signal-schedule.csv"), "signal_identities_per_side": 119, "physical_signal_evaluations_per_side": 238, "events_compared": total_events, "transactions_compared": total_tx, "deals_compared": total_deals, "semantic_field_comparisons": total_fields, "maximum_numeric_absolute_difference": max_delta, "divergence_count": len(divergences), "runs": parity_runs}
    (OUT / "v31a-equivalence-proof.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    print(json.dumps(result, indent=2), flush=True)


if __name__ == "__main__":
    main()
