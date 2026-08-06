#!/usr/bin/env python3
"""Reconcile V31 trades, apply frozen gates, and audit combined evidence."""
from __future__ import annotations

import csv
import hashlib
import json
import math
import random
import statistics
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
BASE = OUT / "performance-runs"
RUNS = json.loads((OUT / "v31-physical-run-plan.json").read_text())["runs"]
CELLS = json.loads((OUT / "v31-formal-cell-plan.json").read_text())["cells"]
GATES = json.loads((OUT / "v31-gate-manifest.json").read_text())
SEEDS = json.loads((OUT / "v31-profitability-prerun-freeze.json").read_text())["seeds"]
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
FMT = "%Y.%m.%d %H:%M:%S"
START = datetime(2018, 2, 5, 10, 5)
END = datetime(2025, 1, 1)
LEDGER_FIELDS = ("run_id", "dataset", "cost_profile", "execution_layer", "position_identifier", "symbol", "research_symbol", "direction", "entry_time", "exit_time", "entry_price", "exit_price", "volume", "initial_risk_amount", "native_deal_net_before_external_commission", "native_tester_commission", "external_commission_adjustment", "native_trade_net", "spread_cost", "swap_cost", "fee_cost", "adverse_entry_slippage_cost", "adverse_exit_slippage_cost", "native_friction", "supplementary_multiplier", "supplementary_charge", "adjusted_trade_net", "adjusted_net_R", "exit_reason", "holding_seconds", "synthetic_equity_before", "synthetic_cash_flow", "synthetic_equity_after")


def read(path: Path):
    with path.open() as handle:
        return list(csv.DictReader(handle))


def pairs(path: Path):
    return {row["field"]: row["value"] for row in read(path)}


def f(value):
    return float(value or 0)


def dt(value):
    return datetime.strptime(value, FMT)


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value):
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def point_value(symbol: str, price: float) -> float:
    point = 0.001 if symbol == "USDJPY" else 0.00001
    return 100000 * point if symbol.endswith("USD") else 100000 * point / price


def foreign_currency(symbol: str) -> str:
    return symbol[3:] if symbol.startswith("USD") else symbol[:3]


def parse_run(run: dict) -> dict:
    folder = BASE / run["run_id"]
    summary = pairs(folder / "run-summary.csv")
    deals = read(folder / "deals.csv")
    transactions = read(folder / "transactions.csv")
    if summary.get("run_evidence_status") != "PASS" or summary.get("open_positions_at_end") != "0":
        raise RuntimeError(f"invalid physical run {run['run_id']}")
    grouped = defaultdict(list)
    for row in deals:
        grouped[row["position_identifier"]].append(row)
    entry_meta = {row["deal_ticket"]: row for row in transactions if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"}
    exit_meta = {row["deal_ticket"]: row for row in transactions if row["record_type"] == "EXIT_TRANSACTION" and row["fill_confirmed"] == "YES"}
    rows = []
    for position, items in grouped.items():
        entries = [row for row in items if int(row["entry"]) == 0]
        exits = [row for row in items if int(row["entry"]) in (1, 2)]
        if len(entries) != 1 or not exits:
            raise RuntimeError(f"unclosed position {run['run_id']} {position}")
        entry, exit_deal = entries[0], exits[-1]
        meta = entry_meta.get(entry["deal_ticket"])
        if meta is None:
            raise RuntimeError(f"missing entry metadata {run['run_id']} {position}")
        exit_tx = exit_meta.get(exit_deal["deal_ticket"])
        symbol = entry["canonical_symbol"]
        volume = f(entry["volume"])
        direction = "BUY" if int(entry["type"]) == 0 else "SELL"
        native_commission = sum(f(row["commission"]) for row in items)
        native_before_external = sum(f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"]) for row in items)
        external_commission = volume * 6.0
        native_net = native_before_external - external_commission
        price_point = 0.001 if symbol == "USDJPY" else 0.00001
        point_cash = point_value(symbol, f(entry["price"]))
        spread = f(meta["spread_points"]) * point_cash * volume
        requested_entry, actual_entry = f(meta["requested_price"]), f(entry["price"])
        entry_slippage = max(0, (actual_entry - requested_entry) / price_point * point_cash * volume) if direction == "BUY" else max(0, (requested_entry - actual_entry) / price_point * point_cash * volume)
        exit_slippage = 0.0
        if exit_tx:
            requested_exit, actual_exit = f(exit_tx["requested_price"]), f(exit_deal["price"])
            exit_slippage = max(0, (requested_exit - actual_exit) / price_point * point_cash * volume) if direction == "BUY" else max(0, (actual_exit - requested_exit) / price_point * point_cash * volume)
        swap = abs(sum(f(row["swap"]) for row in items))
        fee = abs(sum(f(row["fee"]) for row in items))
        friction = spread + external_commission + swap + fee + entry_slippage + exit_slippage
        rows.append({
            "run_id": run["run_id"], "dataset": run["dataset"], "execution_layer": run["execution_layer"], "position_identifier": int(position),
            "symbol": symbol, "research_symbol": entry["research_symbol"], "direction": direction, "entry_time": entry["time"], "exit_time": exit_deal["time"],
            "entry_price": f(entry["price"]), "exit_price": f(exit_deal["price"]), "volume": volume, "initial_risk_amount": f(meta["initial_risk_amount"]),
            "native_deal_net_before_external_commission": native_before_external, "native_tester_commission": native_commission, "external_commission_adjustment": external_commission,
            "native_trade_net": native_net, "spread_cost": spread, "swap_cost": swap, "fee_cost": fee, "adverse_entry_slippage_cost": entry_slippage,
            "adverse_exit_slippage_cost": exit_slippage, "native_friction": friction, "exit_reason": "STOP_LOSS_EXIT" if int(exit_deal["reason"]) == 4 else "MONTHLY_REBALANCE_EXIT",
            "holding_seconds": (dt(exit_deal["time"]) - dt(entry["time"])).total_seconds(),
        })
    return {"run": run, "summary": summary, "rows": rows}


def grouped_values(rows, key):
    values = defaultdict(float)
    for row in rows:
        values[key(row)] += row["_cash"]
    return dict(sorted(values.items()))


def contribution(rows, key, net):
    if net <= 0:
        return None
    values = grouped_values(rows, key)
    return max(values.values()) / net * 100 if values else None


def longest_negative_period(rows, start):
    equity = peak = 10000.0
    peak_time = start
    longest = 0.0
    for row in rows:
        equity += row["_cash"]
        when = dt(row["exit_time"])
        if equity >= peak:
            peak = equity
            peak_time = when
        else:
            longest = max(longest, (when - peak_time).total_seconds())
    return longest


def metrics(rows, cell_id, dataset, profile, layer, start=START, end=END):
    rows = sorted(rows, key=lambda row: (row["exit_time"], row["symbol"], row.get("position_identifier", 0)))
    equity = peak = 10000.0
    max_drawdown = 0.0
    cash = []
    for row in rows:
        before = equity
        value = equity * 0.005 * row["adjusted_net_R"]
        equity += value
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, (peak - equity) / peak * 100)
        row["_before"], row["_cash"], row["_after"] = before, value, equity
        cash.append(value)
    wins = [value for value in cash if value > 0]
    losses = [value for value in cash if value < 0]
    net = sum(cash)
    seconds = max((end - start).total_seconds(), 1)
    quintiles = [0.0] * 5
    for row in rows:
        index = min(4, max(0, int((dt(row["exit_time"]) - start).total_seconds() / seconds * 5)))
        quintiles[index] += row["_cash"]
    by_week = grouped_values(rows, lambda row: dt(row["exit_time"]).strftime("%G-W%V"))
    by_month = grouped_values(rows, lambda row: dt(row["exit_time"]).strftime("%Y-%m"))
    by_year = grouped_values(rows, lambda row: dt(row["exit_time"]).strftime("%Y"))
    sorted_cash = sorted(cash, reverse=True)
    years = max((end - start).days / 365.0, 1 / 365)
    return {
        "cell_id": cell_id, "dataset": dataset, "cost_profile": profile, "execution_layer": layer, "initial_synthetic_equity": 10000.0,
        "final_synthetic_equity": equity, "adjusted_net_profit": net, "gross_profit": sum(wins), "gross_loss": sum(losses),
        "profit_factor": sum(wins) / abs(sum(losses)) if losses else None, "expectancy_usd": net / len(rows) if rows else None,
        "expectancy_R": statistics.fmean(row["adjusted_net_R"] for row in rows) if rows else None, "naturally_closed_trades": len(rows),
        "winning_trades": len(wins), "losing_trades": len(losses), "win_rate_percent": len(wins) / len(rows) * 100 if rows else None,
        "relative_drawdown_percent": max_drawdown, "annualized_return_percent": ((equity / 10000) ** (1 / years) - 1) * 100,
        "best_trade_contribution_percent": max(cash) / net * 100 if cash and net > 0 else None,
        "largest_five_trade_contribution_percent": sum(sorted_cash[:5]) / net * 100 if cash and net > 0 else None,
        "largest_ten_trade_contribution_percent": sum(sorted_cash[:10]) / net * 100 if cash and net > 0 else None,
        "best_currency_contribution_percent": contribution(rows, lambda row: foreign_currency(row["symbol"]), net),
        "best_symbol_contribution_percent": contribution(rows, lambda row: row["symbol"], net),
        "best_direction_contribution_percent": contribution(rows, lambda row: row["direction"], net),
        "best_registered_subperiod_contribution_percent": max(quintiles) / net * 100 if net > 0 else None,
        "best_week_contribution_percent": max(by_week.values()) / net * 100 if by_week and net > 0 else None,
        "best_month_contribution_percent": max(by_month.values()) / net * 100 if by_month and net > 0 else None,
        "best_year_contribution_percent": max(by_year.values()) / net * 100 if by_year and net > 0 else None,
        "buy_net_profit": sum(row["_cash"] for row in rows if row["direction"] == "BUY"), "sell_net_profit": sum(row["_cash"] for row in rows if row["direction"] == "SELL"),
        "buy_trades": sum(row["direction"] == "BUY" for row in rows), "sell_trades": sum(row["direction"] == "SELL" for row in rows),
        "longest_negative_period_seconds": longest_negative_period(rows, start),
        "by_symbol_net_profit": grouped_values(rows, lambda row: row["symbol"]), "by_foreign_currency_net_profit": grouped_values(rows, lambda row: foreign_currency(row["symbol"])),
        "by_year_net_profit": by_year, "by_month_net_profit": by_month, "by_week_net_profit": by_week,
    }


def apply_cost(rows, cell):
    output = []
    for source in rows:
        row = source.copy()
        row["cost_profile"] = cell["cost_profile"]
        row["supplementary_multiplier"] = cell["supplementary_multiplier"]
        row["supplementary_charge"] = row["native_friction"] * cell["supplementary_multiplier"]
        row["adjusted_trade_net"] = row["native_trade_net"] - row["supplementary_charge"]
        row["adjusted_net_R"] = row["adjusted_trade_net"] / row["initial_risk_amount"]
        output.append(row)
    return output


def ratio_gates(items, scope):
    expectancy = [item["expectancy_R"] for item in items]
    annualized = [item["annualized_return_percent"] for item in items]
    pfs = [item["profit_factor"] for item in items]
    expectancy_ratio = min(expectancy) / max(expectancy) if expectancy and all(value is not None and value > 0 for value in expectancy) else None
    annualized_ratio = min(annualized) / max(annualized) if annualized and all(value is not None and value > 0 for value in annualized) else None
    pf_range = max(pfs) - min(pfs) if pfs and all(value is not None for value in pfs) else None
    return [
        {"scope": scope, "gate": "expectancy_min_div_max", "rule": ">= 0.35", "actual": expectancy_ratio, "status": "PASS" if expectancy_ratio is not None and expectancy_ratio >= 0.35 else "FAIL"},
        {"scope": scope, "gate": "annualized_return_min_div_max", "rule": ">= 0.35", "actual": annualized_ratio, "status": "PASS" if annualized_ratio is not None and annualized_ratio >= 0.35 else "FAIL"},
        {"scope": scope, "gate": "profit_factor_range", "rule": "<= 0.50", "actual": pf_range, "status": "PASS" if pf_range is not None and pf_range <= 0.50 else "FAIL"},
    ]


def period_metrics(rows, profile, layer, start, end, label):
    selected = [row.copy() for row in rows if start <= dt(row["exit_time"]) < end]
    return metrics(selected, label, "ATTRIBUTION", profile, layer, start, end)


def month_ends(start_year, start_month, end_year, end_month):
    year, month = start_year, start_month
    while (year, month) <= (end_year, end_month):
        next_year, next_month = (year + 1, 1) if month == 12 else (year, month + 1)
        yield datetime(next_year, next_month, 1)
        year, month = next_year, next_month


def performance_gates(formal):
    thresholds = {"NORMAL": (1.15, ">", 8, "<"), "HIGH": (1.05, ">=", 10, "<="), "STRESS": (1.0, ">=", 12, "<=")}
    output = []
    for item in formal:
        pf_limit, pf_operator, dd_limit, dd_operator = thresholds[item["cost_profile"]]
        checks = [
            ("profit_factor", f"{pf_operator} {pf_limit}", item["profit_factor"], item["profit_factor"] is not None and (item["profit_factor"] > pf_limit if pf_operator == ">" else item["profit_factor"] >= pf_limit)),
            ("adjusted_net_profit", "> 0", item["adjusted_net_profit"], item["adjusted_net_profit"] > 0),
            ("expectancy_R", "> 0", item["expectancy_R"], item["expectancy_R"] is not None and item["expectancy_R"] > 0),
            ("relative_drawdown_percent", f"{dd_operator} {dd_limit}", item["relative_drawdown_percent"], item["relative_drawdown_percent"] < dd_limit if dd_operator == "<" else item["relative_drawdown_percent"] <= dd_limit),
            ("best_trade_contribution_percent", "<= 15", item["best_trade_contribution_percent"], item["best_trade_contribution_percent"] is not None and item["best_trade_contribution_percent"] <= 15),
            ("best_currency_contribution_percent", "<= 35", item["best_currency_contribution_percent"], item["best_currency_contribution_percent"] is not None and item["best_currency_contribution_percent"] <= 35),
            ("best_registered_subperiod_contribution_percent", "<= 40", item["best_registered_subperiod_contribution_percent"], item["best_registered_subperiod_contribution_percent"] is not None and item["best_registered_subperiod_contribution_percent"] <= 40),
        ]
        output.extend({"cell_id": item["cell_id"], "gate": name, "rule": rule, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, rule, actual, passed in checks)
    return output


def sample_gates(rows, prefix="independent"):
    summary = {"closed": len(rows), "BUY": sum(row["direction"] == "BUY" for row in rows), "SELL": sum(row["direction"] == "SELL" for row in rows), "by_symbol": {symbol: sum(row["symbol"] == symbol for row in rows) for symbol in SYMBOLS}}
    checks = [("continuous_closed >= 100", summary["closed"] >= 100, summary["closed"]), ("BUY_closed >= 20", summary["BUY"] >= 20, summary["BUY"]), ("SELL_closed >= 20", summary["SELL"] >= 20, summary["SELL"])]
    checks.extend((f"{symbol}_closed >= 10", value >= 10, value) for symbol, value in summary["by_symbol"].items())
    return summary, [{"scope": prefix, "gate": name, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, passed, actual in checks]


def quantile(values, probability):
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def uncertainty(values, seed, bootstrap):
    rng = random.Random(seed)
    size = len(values)
    endings, drawdowns, means = [], [], []
    for _ in range(100000):
        path = [values[rng.randrange(size)] for _ in range(size)] if bootstrap else rng.sample(values, size)
        equity = peak = 10000.0
        drawdown = 0.0
        for value in path:
            equity *= 1 + 0.005 * value
            peak = max(peak, equity)
            drawdown = max(drawdown, (peak - equity) / peak * 100)
        endings.append(equity - 10000)
        drawdowns.append(drawdown)
        means.append(statistics.fmean(path))
    return {"paths": 100000, "sample_trades": size, "expectancy_R_95_percent_interval": [quantile(means, 0.025), quantile(means, 0.975)], "ending_net_profit": {"p05": quantile(endings, 0.05), "median": quantile(endings, 0.5), "p95": quantile(endings, 0.95)}, "probability_negative_ending_net_profit": sum(value < 0 for value in endings) / len(endings), "drawdown_percent": {"median": quantile(drawdowns, 0.5), "p90": quantile(drawdowns, 0.9), "p95": quantile(drawdowns, 0.95)}}


def main():
    information = {run["run_id"]: parse_run(run) for run in RUNS}
    formal, ledger, cell_rows = [], [], {}
    for cell in CELLS:
        rows = apply_cost(information[cell["source_run"]]["rows"], cell)
        item = metrics(rows, cell["cell_id"], cell["dataset"], cell["cost_profile"], cell["execution_layer"])
        formal.append(item)
        cell_rows[cell["cell_id"]] = rows
        for row in rows:
            row["synthetic_equity_before"], row["synthetic_cash_flow"], row["synthetic_equity_after"] = row["_before"], row["_cash"], row["_after"]
            ledger.append(row)
    with (OUT / "v31-complete-adjusted-trade-ledger.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=LEDGER_FIELDS, extrasaction="ignore", lineterminator="\n"); writer.writeheader(); writer.writerows(ledger)
    flat_formal = [{key: value for key, value in row.items() if not isinstance(value, dict)} for row in formal]
    with (OUT / "v31-formal-cell-metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(flat_formal[0]), lineterminator="\n"); writer.writeheader(); writer.writerows(flat_formal)
    authoritative = [row for row in ledger if row["cost_profile"] == "NORMAL" and row["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    sample_summary, samples = sample_gates(authoritative)
    performance = performance_gates(formal)
    annual_report, annual_gates, rolling_report, rolling_gates = [], [], [], []
    for cell in CELLS:
        rows = cell_rows[cell["cell_id"]]
        annual = [period_metrics(rows, cell["cost_profile"], cell["execution_layer"], datetime(year, 1, 1), datetime(year + 1, 1, 1), f"{cell['cell_id']}-{year}") for year in range(2018, 2025)]
        annual_report.extend(annual)
        annual_gates.extend(ratio_gates(annual, f"annual:{cell['cell_id']}"))
        losing_years = sum(item["adjusted_net_profit"] <= 0 for item in annual)
        annual_gates.append({"scope": f"annual:{cell['cell_id']}", "gate": "losing_year_count", "rule": "= 0", "actual": losing_years, "status": "PASS" if losing_years == 0 else "FAIL"})
        rolling = []
        for endpoint in month_ends(2019, 1, 2024, 12):
            report_month = endpoint - timedelta(seconds=1)
            rolling.append(period_metrics(rows, cell["cost_profile"], cell["execution_layer"], endpoint - timedelta(days=365), endpoint, f"{cell['cell_id']}-ROLLING-{report_month:%Y-%m}"))
        rolling_report.extend(rolling)
        rolling_gates.extend(ratio_gates(rolling, f"rolling12m:{cell['cell_id']}"))
    latency_gates = []
    for profile in ("NORMAL", "HIGH", "STRESS"):
        latency_gates.extend(ratio_gates([item for item in formal if item["cost_profile"] == profile], f"native_delay:{profile}"))
    independent_gates = samples + performance + annual_gates + rolling_gates + latency_gates
    independent_pass = all(gate["status"] == "PASS" for gate in independent_gates)
    write("v31-formal-cell-inventory.json", {"schema": "SOLTRADE_PHASE6_V31_FORMAL_CELL_INVENTORY_V1", "status": "PASS", "cells": formal})
    write("v31-annual-attribution.json", {"schema": "SOLTRADE_PHASE6_V31_ANNUAL_ATTRIBUTION_V1", "periods": annual_report, "gates": annual_gates})
    write("v31-rolling-12-month-attribution.json", {"schema": "SOLTRADE_PHASE6_V31_ROLLING_ATTRIBUTION_V1", "periods": rolling_report, "gates": rolling_gates})
    write("v31-symbol-currency-direction-attribution.json", {"schema": "SOLTRADE_PHASE6_V31_ATTRIBUTION_V1", "cells": [{"cell_id": item["cell_id"], "buy_net_profit": item["buy_net_profit"], "sell_net_profit": item["sell_net_profit"], "buy_trades": item["buy_trades"], "sell_trades": item["sell_trades"], "by_symbol_net_profit": item["by_symbol_net_profit"], "by_foreign_currency_net_profit": item["by_foreign_currency_net_profit"]} for item in formal]})
    write("v31-concentration-report.json", {"schema": "SOLTRADE_PHASE6_V31_CONCENTRATION_V1", "cells": [{key: item[key] for key in ("cell_id", "best_trade_contribution_percent", "largest_five_trade_contribution_percent", "largest_ten_trade_contribution_percent", "best_currency_contribution_percent", "best_symbol_contribution_percent", "best_direction_contribution_percent", "best_registered_subperiod_contribution_percent", "best_week_contribution_percent", "best_month_contribution_percent", "best_year_contribution_percent")} for item in formal]})
    preserved = read(V28 / "phase6-v28-complete-adjusted-trade-ledger.csv")
    combined_cells, combined_gates, combined_cell_rows = [], [], {}
    for cell in CELLS:
        ext = [row.copy() for row in cell_rows[cell["cell_id"]]]
        old = []
        for source in preserved:
            if source["cost_profile"] != cell["cost_profile"] or source["execution_layer"] != cell["execution_layer"]:
                continue
            old.append({"symbol": source["symbol"], "direction": source["direction"], "entry_time": source["entry_time"], "exit_time": source["exit_time"], "position_identifier": int(source["position_identifier"]), "adjusted_net_R": f(source["adjusted_net_R"])})
        combined = ext + old
        item = metrics(combined, "COMBINED-" + cell["cell_id"], "V31_2018_2024_PLUS_PRESERVED_V28_2025_2026", cell["cost_profile"], cell["execution_layer"], START, datetime(2026, 8, 1))
        combined_cells.append(item)
        combined_cell_rows[item["cell_id"]] = combined
    combined_authoritative = []
    normal_native_id = next(cell["cell_id"] for cell in CELLS if cell["cost_profile"] == "NORMAL" and cell["execution_layer"] == "NATIVE_NORMAL_EXECUTION")
    combined_authoritative.extend(cell_rows[normal_native_id])
    for source in preserved:
        if source["cost_profile"] == "NORMAL" and source["execution_layer"] == "NATIVE_NORMAL_EXECUTION":
            combined_authoritative.append({"symbol": source["symbol"], "direction": source["direction"], "entry_time": source["entry_time"], "exit_time": source["exit_time"], "position_identifier": int(source["position_identifier"]), "adjusted_net_R": f(source["adjusted_net_R"])})
    _, combined_samples = sample_gates(combined_authoritative, "combined")
    combined_gates.extend(combined_samples)
    combined_gates.extend(performance_gates(combined_cells))
    combined_period_report = []
    for item in combined_cells:
        rows = combined_cell_rows[item["cell_id"]]
        periods = [period_metrics(rows, item["cost_profile"], item["execution_layer"], datetime(year, 1, 1), datetime(year + 1, 1, 1), f"{item['cell_id']}-{year}") for year in range(2018, 2026)]
        periods.append(period_metrics(rows, item["cost_profile"], item["execution_layer"], datetime(2026, 1, 1), datetime(2026, 8, 1), f"{item['cell_id']}-2026-PARTIAL"))
        combined_period_report.extend(periods)
        combined_gates.extend(ratio_gates(periods, f"combined_cross_period:{item['cell_id']}"))
        losing_periods = sum(period["adjusted_net_profit"] <= 0 for period in periods)
        combined_gates.append({"scope": f"combined_cross_period:{item['cell_id']}", "gate": "losing_period_count", "rule": "= 0", "actual": losing_periods, "status": "PASS" if losing_periods == 0 else "FAIL"})
        rolling = [period_metrics(rows, item["cost_profile"], item["execution_layer"], endpoint - timedelta(days=365), endpoint, f"{item['cell_id']}-ROLLING-{endpoint - timedelta(seconds=1):%Y-%m}") for endpoint in month_ends(2019, 1, 2026, 7)]
        combined_gates.extend(ratio_gates(rolling, f"combined_rolling12m:{item['cell_id']}"))
    for profile in ("NORMAL", "HIGH", "STRESS"):
        combined_gates.extend(ratio_gates([item for item in combined_cells if item["cost_profile"] == profile], f"combined_native_delay:{profile}"))
    combined_pass = all(gate["status"] == "PASS" for gate in combined_gates)
    write("v31-combined-evidence-audit.json", {"schema": "SOLTRADE_PHASE6_V31_COMBINED_EVIDENCE_AUDIT_V1", "status": "PASS" if combined_pass else "FAIL", "independent_status": "PASS" if independent_pass else "FAIL", "independent_failure_cannot_be_overridden": True, "external_period": "2018-2024", "preserved_periods": ["V28 2025", "V28 January-July 2026"], "reweighting": False, "cells": combined_cells, "period_attribution": combined_period_report, "gates": combined_gates})
    outcome = "V31_EXTERNAL_REPLICATION_FAILED" if not independent_pass else ("V31_COMBINED_GATES_FAILED" if not combined_pass else "V31_EXTERNAL_REPLICATION_AND_COMBINED_GATES_PASSED")
    write("v31-gate-evaluation.json", {"schema": "SOLTRADE_PHASE6_V31_GATE_EVALUATION_V1", "terminal_outcome": outcome, "independent_pass": independent_pass, "combined_pass": combined_pass, "sample_summary": sample_summary, "sample_gates": samples, "performance_gates": performance, "annual_consistency_gates": annual_gates, "rolling_consistency_gates": rolling_gates, "latency_consistency_gates": latency_gates, "failed_independent_gates": [gate for gate in independent_gates if gate["status"] == "FAIL"]})
    values = [row["adjusted_net_R"] for row in sorted(authoritative, key=lambda row: (row["exit_time"], row["symbol"]))]
    bootstrap = uncertainty(values, SEEDS["bootstrap_seed"], True); bootstrap.update({"schema": "SOLTRADE_PHASE6_V31_BOOTSTRAP_V1", "seed": SEEDS["bootstrap_seed"], "reporting_only": True}); write("v31-bootstrap-report.json", bootstrap)
    monte = uncertainty(values, SEEDS["monte_carlo_seed"], False); monte.update({"schema": "SOLTRADE_PHASE6_V31_MONTE_CARLO_V1", "seed": SEEDS["monte_carlo_seed"], "reporting_only": True}); write("v31-monte-carlo-report.json", monte)
    write("v31-evidence-integrity.json", {"schema": "SOLTRADE_PHASE6_V31_EVIDENCE_INTEGRITY_V1", "status": "PASS", "classification": "INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION", "cost_model": "EXTERNAL_PRICE_FEED_WITH_FROZEN_CONTROLLED_COST_MODEL", "physical_runs": 2, "formal_cells": 6, "optimization_or_tuning": False, "external_provider_count": 1, "production_phase1_5_sha256": sha(ROOT / "MQL5/Experts/SolTradeBot.mq5"), "production_phase1_5_unchanged": sha(ROOT / "MQL5/Experts/SolTradeBot.mq5") == "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3", "connected_chart_trades": 0, "demo_trades": 0, "live_trades": 0, "terminal_outcome": outcome})
    normal_native = next(item for item in formal if item["cost_profile"] == "NORMAL" and item["execution_layer"] == "NATIVE_NORMAL_EXECUTION")
    print(json.dumps({"outcome": outcome, "independent_pass": independent_pass, "combined_pass": combined_pass, "sample": sample_summary, "normal_native": {key: normal_native[key] for key in ("adjusted_net_profit", "profit_factor", "expectancy_R", "relative_drawdown_percent")}, "failed_independent_gates": len([gate for gate in independent_gates if gate["status"] == "FAIL"])}, indent=2))


if __name__ == "__main__":
    main()
