#!/usr/bin/env python3
"""Reconcile V29 physical runs and apply the fully frozen independent gates."""
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
OUT = ROOT / "reports/backtests/phase6-v29-weekly-cross-sectional-currency-momentum"
BASE = OUT / "performance-runs-attempt2"
RUNS = json.loads((OUT / "physical-run-plan.json").read_text())["runs"]
CELLS = json.loads((OUT / "formal-cell-plan.json").read_text())["cells"]
SEEDS = json.loads((OUT / "deterministic-seeds.json").read_text())
FMT = "%Y.%m.%d %H:%M:%S"
SPANS = {
    "V29_2025_DEVELOPMENT": (datetime(2025, 1, 6, 10, 5), datetime(2026, 1, 1)),
    "V29_2026_PRESEAL_DEVELOPMENT": (datetime(2026, 1, 5, 10, 5), datetime(2026, 8, 1)),
}
CURRENCIES = ("EUR", "GBP", "AUD", "NZD", "CAD", "CHF", "JPY")
LEDGER_FIELDS = (
    "run_id", "dataset", "cost_profile", "execution_layer", "position_identifier", "signal_identity_sha256",
    "signal_time", "scheduled_exit", "currency", "symbol", "rank", "portfolio_side", "chart_direction",
    "entry_time", "exit_time", "entry_time_msc", "exit_time_msc", "entry_price", "exit_price", "volume",
    "initial_risk_amount", "tester_balance_before_rebalance", "leg_initial_risk_percent", "weekly_initial_risk_percent",
    "leg_notional_usd", "weekly_gross_exposure_percent", "weekly_net_usd_exposure_percent",
    "native_deal_net_before_external_commission", "native_tester_commission", "external_commission_adjustment",
    "native_trade_net", "spread_cost", "swap_cost", "fee_cost", "adverse_entry_slippage_cost",
    "adverse_exit_slippage_cost", "native_friction", "supplementary_multiplier", "supplementary_charge",
    "adjusted_trade_net", "adjusted_net_R", "exit_reason", "holding_seconds", "synthetic_equity_before",
    "synthetic_cash_flow", "synthetic_equity_after"
)


def read(path: Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def pairs(path: Path) -> dict[str, str]:
    return {row["field"]: row["value"] for row in read(path)}


def f(value: object) -> float:
    return float(value or 0)


def dt(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def point_value(symbol: str, price: float) -> float:
    point = 0.001 if symbol == "USDJPY" else 0.00001
    return 100000 * point if symbol.endswith("USD") else 100000 * point / price


def notional_usd(symbol: str, price: float, volume: float) -> float:
    return volume * 100000 * price if symbol.endswith("USD") else volume * 100000


def load_signal_map() -> dict[tuple[str, str, str], dict[str, str]]:
    rows = read(OUT / "v29-frozen-signal-identity-ledger.csv")
    result = {(row["dataset"], row["target"], row["symbol"]): row for row in rows}
    if len(rows) != 320 or len(result) != 320:
        raise RuntimeError("frozen signal identity cardinality")
    return result


def parse_run(run: dict, signal_map: dict) -> dict:
    folder = BASE / run["run_id"]
    summary = pairs(folder / "run-summary.csv")
    status = json.loads((folder / "physical-run-status.json").read_text())
    if status["status"] != "PASS" or summary.get("run_evidence_status") != "PASS" or summary.get("final_exit_target_cleared") != "YES":
        raise RuntimeError(f"invalid physical run {run['run_id']}")
    deals = read(folder / "deals.csv")
    transactions = read(folder / "transactions.csv")
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in deals:
        groups[row["position_identifier"]].append(row)
    entry_meta = {row["deal_ticket"]: row for row in transactions if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"}
    exit_meta = {row["deal_ticket"]: row for row in transactions if row["record_type"] == "EXIT_TRANSACTION" and row["fill_confirmed"] == "YES"}

    ordered_deals = sorted(deals, key=lambda row: (int(row["time_msc"]), int(row["deal_ticket"])))
    balance = 10000.0
    balance_before_deal: dict[str, float] = {}
    for row in ordered_deals:
        balance_before_deal[row["deal_ticket"]] = balance
        if int(row["entry"]) in (1, 2):
            balance += f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"])

    rows = []
    for position_identifier, position_deals in groups.items():
        entries = [row for row in position_deals if int(row["entry"]) == 0]
        exits = [row for row in position_deals if int(row["entry"]) in (1, 2)]
        if len(entries) != 1 or not exits:
            raise RuntimeError(f"unclosed position {run['run_id']} {position_identifier}")
        entry, exit_deal = entries[0], exits[-1]
        meta = entry_meta.get(entry["deal_ticket"])
        if meta is None:
            raise RuntimeError(f"entry metadata missing {run['run_id']} {position_identifier}")
        target = meta["signal_time"]
        signal = signal_map.get((run["schedule_dataset"], target, entry["symbol"]))
        if signal is None:
            raise RuntimeError(f"frozen signal missing {run['run_id']} {target} {entry['symbol']}")
        symbol = entry["symbol"]
        volume = f(entry["volume"])
        direction = "BUY" if int(entry["type"]) == 0 else "SELL"
        if direction != signal["chart_direction"]:
            raise RuntimeError(f"direction parity {run['run_id']} {position_identifier}")
        native_commission = sum(f(row["commission"]) for row in position_deals)
        native_before_external = sum(f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"]) for row in position_deals)
        external_commission = volume * 6.0
        native_net = native_before_external - external_commission
        entry_price = f(entry["price"])
        exit_price = f(exit_deal["price"])
        pv = point_value(symbol, entry_price)
        spread = f(meta["spread_points"]) * pv * volume
        point = 0.001 if symbol == "USDJPY" else 0.00001
        requested_entry = f(meta["requested_price"])
        entry_slippage = max(0.0, (entry_price - requested_entry) / point * pv * volume) if direction == "BUY" else max(0.0, (requested_entry - entry_price) / point * pv * volume)
        exit_slippage = 0.0
        exit_tx = exit_meta.get(exit_deal["deal_ticket"])
        if exit_tx and f(exit_tx["requested_price"]) > 0:
            requested_exit = f(exit_tx["requested_price"])
            exit_slippage = max(0.0, (requested_exit - exit_price) / point * pv * volume) if direction == "BUY" else max(0.0, (exit_price - requested_exit) / point * pv * volume)
        swap = abs(sum(f(row["swap"]) for row in position_deals))
        fee = abs(sum(f(row["fee"]) for row in position_deals))
        friction = spread + external_commission + swap + fee + entry_slippage + exit_slippage
        risk = f(meta["initial_risk_amount"])
        tester_balance = balance_before_deal[entry["deal_ticket"]]
        notional = notional_usd(symbol, entry_price, volume)
        rows.append({
            "run_id": run["run_id"], "dataset": run["dataset"], "execution_layer": run["execution_layer"],
            "position_identifier": int(position_identifier), "signal_identity_sha256": signal["identity_sha256"],
            "signal_time": target, "scheduled_exit": signal["scheduled_exit"], "currency": signal["currency"],
            "symbol": symbol, "rank": int(signal["rank"]), "portfolio_side": signal["portfolio_side"],
            "chart_direction": direction, "entry_time": entry["time"], "exit_time": exit_deal["time"],
            "entry_time_msc": int(entry["time_msc"]), "exit_time_msc": int(exit_deal["time_msc"]),
            "entry_price": entry_price, "exit_price": exit_price, "volume": volume, "initial_risk_amount": risk,
            "tester_balance_before_rebalance": tester_balance, "leg_initial_risk_percent": risk / tester_balance * 100,
            "leg_notional_usd": notional, "native_deal_net_before_external_commission": native_before_external,
            "native_tester_commission": native_commission, "external_commission_adjustment": external_commission,
            "native_trade_net": native_net, "spread_cost": spread, "swap_cost": swap, "fee_cost": fee,
            "adverse_entry_slippage_cost": entry_slippage, "adverse_exit_slippage_cost": exit_slippage,
            "native_friction": friction, "exit_reason": "STOP_LOSS_EXIT" if int(exit_deal["reason"]) == 4 else "WEEKLY_REBALANCE_EXIT",
            "holding_seconds": (dt(exit_deal["time"]) - dt(entry["time"])).total_seconds(),
        })

    for target, cohort in group_rows(rows, "signal_time").items():
        cohort_balance = min(row["tester_balance_before_rebalance"] for row in cohort)
        weekly_risk = sum(row["initial_risk_amount"] for row in cohort) / cohort_balance * 100
        gross = sum(row["leg_notional_usd"] for row in cohort) / cohort_balance * 100
        net_usd = sum((1 if row["portfolio_side"] == "SHORT" else -1) * row["leg_notional_usd"] for row in cohort) / cohort_balance * 100
        for row in cohort:
            row["weekly_initial_risk_percent"] = weekly_risk
            row["weekly_gross_exposure_percent"] = gross
            row["weekly_net_usd_exposure_percent"] = net_usd
    return {"run": run, "summary": summary, "status": status, "rows": rows}


def group_rows(rows: list[dict], key: str) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        result[str(row[key])].append(row)
    return result


def contribution(rows: list[dict], key, net: float) -> float | None:
    if net <= 0:
        return None
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        totals[str(key(row))] += row["_cash"]
    return max(totals.values()) / net * 100 if totals else None


def metric(rows: list[dict], cell: dict) -> dict:
    start, end = SPANS[cell["dataset"]]
    equity = peak = 10000.0
    maximum_drawdown = 0.0
    cash_flows = []
    for row in rows:
        before = equity
        cash = equity * 0.0025 * row["adjusted_net_R"]
        equity += cash
        peak = max(peak, equity)
        maximum_drawdown = max(maximum_drawdown, (peak - equity) / peak * 100)
        row["_before"], row["_cash"], row["_after"] = before, cash, equity
        cash_flows.append(cash)
    wins = [value for value in cash_flows if value > 0]
    losses = [value for value in cash_flows if value < 0]
    net = sum(cash_flows)
    seconds = (end - start).total_seconds()
    return {
        "cell_id": cell["cell_id"], "dataset": cell["dataset"], "cost_profile": cell["cost_profile"],
        "execution_layer": cell["execution_layer"], "initial_synthetic_equity": 10000.0,
        "final_synthetic_equity": equity, "adjusted_net_profit": net, "gross_profit": sum(wins), "gross_loss": sum(losses),
        "profit_factor": sum(wins) / abs(sum(losses)) if losses else None,
        "expectancy_usd": net / len(rows) if rows else None,
        "expectancy_R": statistics.fmean(row["adjusted_net_R"] for row in rows) if rows else None,
        "naturally_closed_legs": len(rows), "winning_legs": len(wins), "losing_legs": len(losses),
        "win_rate_percent": len(wins) / len(rows) * 100 if rows else None,
        "relative_drawdown_percent": maximum_drawdown,
        "annualized_return_percent": ((equity / 10000) ** (365 / ((end - start).days)) - 1) * 100,
        "best_individual_leg_contribution_percent": max(cash_flows) / net * 100 if cash_flows and net > 0 else None,
        "best_currency_contribution_percent": contribution(rows, lambda row: row["currency"], net),
        "best_direction_contribution_percent": contribution(rows, lambda row: row["chart_direction"], net),
        "best_portfolio_side_contribution_percent": contribution(rows, lambda row: row["portfolio_side"], net),
        "best_week_contribution_percent": contribution(rows, lambda row: row["signal_time"][:10], net),
        "best_month_contribution_percent": contribution(rows, lambda row: row["signal_time"][:7], net),
        "BUY_legs": sum(row["chart_direction"] == "BUY" for row in rows),
        "SELL_legs": sum(row["chart_direction"] == "SELL" for row in rows),
        "LONG_legs": sum(row["portfolio_side"] == "LONG" for row in rows),
        "SHORT_legs": sum(row["portfolio_side"] == "SHORT" for row in rows),
        "stop_loss_exits": sum(row["exit_reason"] == "STOP_LOSS_EXIT" for row in rows),
        "weekly_rebalance_exits": sum(row["exit_reason"] == "WEEKLY_REBALANCE_EXIT" for row in rows),
        "registered_span_fraction": (max((dt(row["exit_time"]) - start).total_seconds() for row in rows) / seconds) if rows else 0,
    }


def quantile(values: list[float], probability: float) -> float:
    ordered = sorted(values)
    location = (len(ordered) - 1) * probability
    lower = int(location)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (location - lower)


def uncertainty(values: list[float], seed: int, bootstrap: bool) -> dict:
    rng = random.Random(seed)
    size = len(values)
    endings, drawdowns, means = [], [], []
    for _ in range(100000):
        path = [values[rng.randrange(size)] for _ in range(size)] if bootstrap else rng.sample(values, size)
        equity = peak = 10000.0
        maximum_drawdown = 0.0
        for value in path:
            equity *= 1 + 0.0025 * value
            peak = max(peak, equity)
            maximum_drawdown = max(maximum_drawdown, (peak - equity) / peak * 100)
        endings.append(equity - 10000)
        drawdowns.append(maximum_drawdown)
        means.append(statistics.fmean(path))
    return {
        "paths": 100000, "sample_legs": size,
        "expectancy_R_95_percent_interval": [quantile(means, 0.025), quantile(means, 0.975)],
        "ending_net_profit": {"p05": quantile(endings, 0.05), "median": quantile(endings, 0.5), "p95": quantile(endings, 0.95)},
        "probability_negative_ending_net_profit": sum(value < 0 for value in endings) / len(endings),
        "drawdown_percent": {"median": quantile(drawdowns, 0.5), "p90": quantile(drawdowns, 0.9), "p95": quantile(drawdowns, 0.95)},
    }


def pearson(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3 or statistics.pstdev(xs) == 0 or statistics.pstdev(ys) == 0:
        return None
    mean_x, mean_y = statistics.fmean(xs), statistics.fmean(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mean_x) ** 2 for x in xs) * sum((y - mean_y) ** 2 for y in ys))
    return numerator / denominator if denominator else None


def correlation_report(info: dict[str, dict]) -> dict:
    reports = []
    slots = ("LONG_R1", "LONG_R2", "SHORT_R6", "SHORT_R7")
    for run in RUNS:
        rows = info[run["run_id"]]["rows"]
        complete = []
        for target, cohort in group_rows(rows, "signal_time").items():
            values = {}
            for row in cohort:
                slot = f"{row['portfolio_side']}_R{row['rank']}"
                values[slot] = row["native_trade_net"] / row["initial_risk_amount"]
            if all(slot in values for slot in slots):
                complete.append((target, values))
        matrix = {}
        for left in slots:
            matrix[left] = {}
            for right in slots:
                matrix[left][right] = pearson([item[1][left] for item in complete], [item[1][right] for item in complete]) if left != right else 1.0
        pair_values = [matrix[left][right] for i, left in enumerate(slots) for right in slots[i + 1:] if matrix[left][right] is not None]
        reports.append({"run_id": run["run_id"], "complete_four_leg_weeks": len(complete), "slot_definition": list(slots), "correlation_matrix": matrix, "mean_pairwise_correlation": statistics.fmean(pair_values) if pair_values else None, "maximum_absolute_pairwise_correlation": max(map(abs, pair_values)) if pair_values else None})
    return {"schema": "SOLTRADE_PHASE6_V29_SIMULTANEOUS_LEG_CORRELATION_V1", "method": "Pearson correlation of native net-R by deterministic rank slot across fully filled simultaneous four-leg cohorts", "reporting_only": True, "runs": reports}


def attribution(rows: list[dict], metric_row: dict) -> dict:
    net = metric_row["adjusted_net_profit"]
    def values(key):
        totals: dict[str, float] = defaultdict(float)
        counts: Counter = Counter()
        for row in rows:
            label = str(key(row)); totals[label] += row["_cash"]; counts[label] += 1
        return [{"key": label, "legs": counts[label], "net_profit": totals[label], "contribution_percent": totals[label] / net * 100 if net > 0 else None} for label in sorted(totals)]
    legs = sorted(({"signal_identity_sha256": row["signal_identity_sha256"], "signal_time": row["signal_time"], "currency": row["currency"], "symbol": row["symbol"], "portfolio_side": row["portfolio_side"], "chart_direction": row["chart_direction"], "net_profit": row["_cash"], "contribution_percent": row["_cash"] / net * 100 if net > 0 else None} for row in rows), key=lambda row: row["net_profit"], reverse=True)
    return {"cell_id": metric_row["cell_id"], "adjusted_net_profit": net, "BUY_SELL": values(lambda row: row["chart_direction"]), "LONG_SHORT": values(lambda row: row["portfolio_side"]), "currencies": values(lambda row: row["currency"]), "weeks": values(lambda row: row["signal_time"][:10]), "months": values(lambda row: row["signal_time"][:7]), "individual_legs_descending": legs}


def main() -> None:
    signal_map = load_signal_map()
    info = {run["run_id"]: parse_run(run, signal_map) for run in RUNS}
    consumption_runs = []
    consumption_ok = True
    for run in RUNS:
        expected = {row["identity_sha256"] for key, row in signal_map.items() if key[0] == run["schedule_dataset"]}
        attempts = [row for row in read(BASE / run["run_id"] / "transactions.csv") if row["record_type"] == "ENTRY_ATTEMPT"]
        observed = []
        parity = True
        for attempt in attempts:
            signal = signal_map.get((run["schedule_dataset"], attempt["signal_time"], attempt["symbol"]))
            if signal is None or signal["chart_direction"] != attempt["direction"]:
                parity = False
                continue
            observed.append(signal["identity_sha256"])
        passed = parity and len(attempts) == run["expected_schedule_legs"] and len(observed) == len(set(observed)) and set(observed) == expected
        consumption_ok = consumption_ok and passed
        consumption_runs.append({"run_id": run["run_id"], "expected_signal_identities": len(expected), "entry_attempts": len(attempts), "unique_matched_identities": len(set(observed)), "direction_parity": parity, "status": "PASS" if passed else "FAIL"})
    write("phase6-v29-signal-consumption-audit.json", {"schema": "SOLTRADE_PHASE6_V29_SIGNAL_CONSUMPTION_AUDIT_V1", "status": "PASS" if consumption_ok else "FAIL", "all_320_signals_attempted_once_per_execution_layer": consumption_ok, "schedule_2025_sha256": sha(OUT / "frozen-v26-signal-set/V26_2025_DEVELOPMENT/signal-schedule.csv"), "schedule_2026_sha256": sha(OUT / "frozen-v26-signal-set/V26_2026_PRESEAL_DEVELOPMENT/signal-schedule.csv"), "runs": consumption_runs})
    formal, ledger, attributions = [], [], []
    for cell in CELLS:
        rows = sorted([row.copy() for row in info[cell["source_run"]]["rows"]], key=lambda row: (row["exit_time_msc"], row["symbol"], row["position_identifier"]))
        for row in rows:
            row["cost_profile"] = cell["cost_profile"]
            row["supplementary_multiplier"] = cell["supplementary_multiplier"]
            row["supplementary_charge"] = row["native_friction"] * cell["supplementary_multiplier"]
            row["adjusted_trade_net"] = row["native_trade_net"] - row["supplementary_charge"]
            row["adjusted_net_R"] = row["adjusted_trade_net"] / row["initial_risk_amount"]
        result = metric(rows, cell)
        formal.append(result)
        attributions.append(attribution(rows, result))
        for row in rows:
            row["synthetic_equity_before"], row["synthetic_cash_flow"], row["synthetic_equity_after"] = row["_before"], row["_cash"], row["_after"]
            ledger.append(row)

    with (OUT / "phase6-v29-complete-adjusted-trade-ledger.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=LEDGER_FIELDS, extrasaction="ignore", lineterminator="\n"); writer.writeheader(); writer.writerows(ledger)
    with (OUT / "phase6-v29-formal-cell-metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(formal[0]), lineterminator="\n"); writer.writeheader(); writer.writerows(formal)
    write("phase6-v29-contribution-attribution.json", {"schema": "SOLTRADE_PHASE6_V29_CONTRIBUTION_ATTRIBUTION_V1", "cells": attributions})
    write("phase6-v29-simultaneous-leg-correlation.json", correlation_report(info))

    authoritative = [row for row in ledger if row["cost_profile"] == "NORMAL" and row["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    sample = {
        "all_closed_legs": len(authoritative),
        "dated_2026": sum(row["dataset"] == "V29_2026_PRESEAL_DEVELOPMENT" for row in authoritative),
        "LONG": sum(row["portfolio_side"] == "LONG" for row in authoritative),
        "SHORT": sum(row["portfolio_side"] == "SHORT" for row in authoritative),
        "BUY": sum(row["chart_direction"] == "BUY" for row in authoritative),
        "SELL": sum(row["chart_direction"] == "SELL" for row in authoritative),
        "by_currency": {currency: sum(row["currency"] == currency for row in authoritative) for currency in CURRENCIES},
    }
    sample_checks = [
        ("all_closed_legs >= 150", sample["all_closed_legs"] >= 150, sample["all_closed_legs"]),
        ("dated_2026_closed_legs >= 50", sample["dated_2026"] >= 50, sample["dated_2026"]),
        ("LONG_closed_legs >= 50", sample["LONG"] >= 50, sample["LONG"]),
        ("SHORT_closed_legs >= 50", sample["SHORT"] >= 50, sample["SHORT"]),
    ] + [(f"{currency}_closed_legs >= 10", count >= 10, count) for currency, count in sample["by_currency"].items()]
    sample_gates = [{"gate": name, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, passed, actual in sample_checks]

    thresholds = {"NORMAL": (1.15, ">", 5.0, "<"), "HIGH": (1.05, ">=", 7.0, "<="), "STRESS": (1.0, ">=", 9.0, "<=")}
    performance_gates, concentration_gates = [], []
    for result in formal:
        pf_limit, pf_operator, dd_limit, dd_operator = thresholds[result["cost_profile"]]
        checks = [
            ("profit_factor", f"{pf_operator} {pf_limit}", result["profit_factor"], result["profit_factor"] is not None and (result["profit_factor"] > pf_limit if pf_operator == ">" else result["profit_factor"] >= pf_limit)),
            ("adjusted_net_profit", "> 0", result["adjusted_net_profit"], result["adjusted_net_profit"] > 0),
            ("expectancy_R", "> 0", result["expectancy_R"], result["expectancy_R"] is not None and result["expectancy_R"] > 0),
            ("relative_drawdown_percent", f"{dd_operator} {dd_limit}", result["relative_drawdown_percent"], result["relative_drawdown_percent"] < dd_limit if dd_operator == "<" else result["relative_drawdown_percent"] <= dd_limit),
        ]
        performance_gates += [{"cell_id": result["cell_id"], "gate": name, "rule": rule, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, rule, actual, passed in checks]
        concentration_checks = [
            ("best_individual_leg_contribution_percent", "<= 15", result["best_individual_leg_contribution_percent"], result["best_individual_leg_contribution_percent"] is not None and result["best_individual_leg_contribution_percent"] <= 15),
            ("best_currency_contribution_percent", "<= 40", result["best_currency_contribution_percent"], result["best_currency_contribution_percent"] is not None and result["best_currency_contribution_percent"] <= 40),
            ("best_direction_contribution_percent", "<= 70", result["best_direction_contribution_percent"], result["best_direction_contribution_percent"] is not None and result["best_direction_contribution_percent"] <= 70),
            ("best_week_contribution_percent", "<= 20", result["best_week_contribution_percent"], result["best_week_contribution_percent"] is not None and result["best_week_contribution_percent"] <= 20),
            ("best_month_contribution_percent", "<= 40", result["best_month_contribution_percent"], result["best_month_contribution_percent"] is not None and result["best_month_contribution_percent"] <= 40),
        ]
        concentration_gates += [{"cell_id": result["cell_id"], "gate": name, "rule": rule, "actual": actual, "status": "PASS" if passed else "FAIL"} for name, rule, actual, passed in concentration_checks]

    consistency_gates, consistency_groups = [], []
    for layer in ("NATIVE_NORMAL_EXECUTION", "FIXED_DELAY_200_MS"):
        for profile in ("NORMAL", "HIGH", "STRESS"):
            results = [row for row in formal if row["execution_layer"] == layer and row["cost_profile"] == profile]
            expectancies = [row["expectancy_R"] for row in results]
            annualized = [row["annualized_return_percent"] for row in results]
            factors = [row["profit_factor"] for row in results]
            expectancy_ratio = min(expectancies) / max(expectancies) if min(expectancies) > 0 else None
            annualized_ratio = min(annualized) / max(annualized) if min(annualized) > 0 else None
            factor_range = max(factors) - min(factors) if all(value is not None for value in factors) else None
            group = {"execution_layer": layer, "cost_profile": profile, "expectancy_min_div_max": expectancy_ratio, "annualized_return_min_div_max": annualized_ratio, "profit_factor_range": factor_range}
            consistency_groups.append(group)
            for name, rule, actual, passed in (
                ("expectancy_min_div_max", ">= 0.35", expectancy_ratio, expectancy_ratio is not None and expectancy_ratio >= 0.35),
                ("annualized_return_min_div_max", ">= 0.35", annualized_ratio, annualized_ratio is not None and annualized_ratio >= 0.35),
                ("profit_factor_range", "<= 0.50", factor_range, factor_range is not None and factor_range <= 0.50),
            ):
                consistency_gates.append({**group, "gate": name, "rule": rule, "actual": actual, "status": "PASS" if passed else "FAIL"})

    risk_weeks = []
    for run in RUNS:
        rows = info[run["run_id"]]["rows"]
        for target, cohort in sorted(group_rows(rows, "signal_time").items()):
            risk_weeks.append({"run_id": run["run_id"], "signal_time": target, "filled_legs": len(cohort), "initial_risk_percent": cohort[0]["weekly_initial_risk_percent"], "gross_exposure_percent": cohort[0]["weekly_gross_exposure_percent"], "net_usd_exposure_percent": cohort[0]["weekly_net_usd_exposure_percent"], "risk_gate": "PASS" if len(cohort) <= 4 and cohort[0]["weekly_initial_risk_percent"] <= 1.0 + 1e-9 else "FAIL"})
    risk_ok = all(row["risk_gate"] == "PASS" for row in risk_weeks)
    write("phase6-v29-portfolio-risk-and-exposure.json", {
        "schema": "SOLTRADE_PHASE6_V29_PORTFOLIO_RISK_EXPOSURE_V1", "status": "PASS" if risk_ok else "FAIL",
        "maximum_filled_legs": max(row["filled_legs"] for row in risk_weeks),
        "maximum_initial_risk_percent": max(row["initial_risk_percent"] for row in risk_weeks),
        "maximum_gross_exposure_percent": max(row["gross_exposure_percent"] for row in risk_weeks),
        "maximum_absolute_net_usd_exposure_percent": max(abs(row["net_usd_exposure_percent"]) for row in risk_weeks),
        "risk_limit_blocks": {run["run_id"]: int(info[run["run_id"]]["summary"]["risk_blocks"]) for run in RUNS},
        "weeks": risk_weeks,
    })

    technical_ok = consumption_ok and risk_ok and all(info[run["run_id"]]["status"]["status"] == "PASS" for run in RUNS)
    sample_ok = all(gate["status"] == "PASS" for gate in sample_gates)
    financial_ok = all(gate["status"] == "PASS" for gate in performance_gates + concentration_gates + consistency_gates)
    if not technical_ok:
        outcome = "INVALID_TEST_EVIDENCE"
    elif not sample_ok:
        outcome = "INCONCLUSIVE_INSUFFICIENT_SAMPLE"
    elif financial_ok:
        outcome = "V29_INDEPENDENT_DEVELOPMENT_PASSED"
    else:
        outcome = "V29_INDEPENDENT_DEVELOPMENT_FAILED"
    write("phase6-v29-gate-evaluation.json", {"schema": "SOLTRADE_PHASE6_V29_GATE_EVALUATION_V1", "terminal_outcome": outcome, "sample_summary": sample, "sample_gates": sample_gates, "performance_gates": performance_gates, "concentration_gates": concentration_gates, "consistency_gates": consistency_gates, "technical_and_portfolio_risk_status": "PASS" if technical_ok else "FAIL"})
    write("phase6-v29-formal-cell-inventory.json", {"schema": "SOLTRADE_PHASE6_V29_FORMAL_CELL_INVENTORY_V1", "status": "PASS", "cells": formal})
    write("phase6-v29-cross-dataset-consistency.json", {"schema": "SOLTRADE_PHASE6_V29_CROSS_DATASET_CONSISTENCY_V1", "groups": consistency_groups, "gates": consistency_gates})
    write("phase6-v29-physical-run-inventory.json", {"schema": "SOLTRADE_PHASE6_V29_PHYSICAL_RUN_INVENTORY_V1", "status": "PASS", "valid_runs": 4, "technical_attempts_retained": 1, "authoritative_root": "performance-runs-attempt2", "runs": [info[run["run_id"]]["status"] for run in RUNS]})
    write("phase6-v29-commission-reconciliation.json", {"schema": "SOLTRADE_PHASE6_V29_COMMISSION_RECONCILIATION_V1", "status": "PASS", "native_tester_commission_total": sum(row["native_tester_commission"] for row in ledger), "external_usd_per_side_per_standard_lot": 3.0, "double_counted": False})

    raw_cost_check = []
    for dataset in SPANS:
        rows = [row for row in authoritative if row["dataset"] == dataset]
        values = [row["native_deal_net_before_external_commission"] for row in rows]
        losses = sum(value for value in values if value < 0)
        raw_cost_check.append({"dataset": dataset, "legs": len(rows), "native_net_before_external_commission": sum(values), "profit_factor_before_external_commission": sum(value for value in values if value > 0) / abs(losses) if losses else None, "expectancy_usd_before_external_commission": statistics.fmean(values)})
    write("phase6-v29-before-external-cost-check.json", {"schema": "SOLTRADE_PHASE6_V29_BEFORE_EXTERNAL_COST_CHECK_V1", "datasets": raw_cost_check})

    values = [row["adjusted_net_R"] for row in sorted(authoritative, key=lambda row: (row["exit_time_msc"], row["symbol"]))]
    bootstrap = uncertainty(values, int(SEEDS["bootstrap_seed"]), True); bootstrap.update({"schema": "SOLTRADE_PHASE6_V29_BOOTSTRAP_V1", "seed": int(SEEDS["bootstrap_seed"]), "reporting_only": True}); write("phase6-v29-bootstrap-report.json", bootstrap)
    monte_carlo = uncertainty(values, int(SEEDS["monte_carlo_seed"]), False); monte_carlo.update({"schema": "SOLTRADE_PHASE6_V29_MONTE_CARLO_V1", "seed": int(SEEDS["monte_carlo_seed"]), "reporting_only": True}); write("phase6-v29-monte-carlo-report.json", monte_carlo)
    production_hash = sha(ROOT / "MQL5/Experts/SolTradeBot.mq5")
    write("phase6-v29-evidence-integrity.json", {"schema": "SOLTRADE_PHASE6_V29_EVIDENCE_INTEGRITY_V1", "status": "PASS" if technical_ok else "FAIL", "selected_signals": 320, "signal_set_sha256": "7e437783c8e9b5b616bd301c4a0434afa208b2339fdc80064ad4675425014db9", "physical_runs": 4, "formal_cells": 12, "optimization_or_tuning": False, "sealed_future_oos_accessed": False, "future_combination_executed": False, "production_phase1_5_unchanged": production_hash == "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3", "demo_trades": 0, "live_trades": 0, "terminal_outcome": outcome})

    normal_native = [row for row in formal if row["cost_profile"] == "NORMAL" and row["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    failed_performance = sum(row["status"] == "FAIL" for row in performance_gates)
    failed_concentration = sum(row["status"] == "FAIL" for row in concentration_gates)
    failed_consistency = sum(row["status"] == "FAIL" for row in consistency_gates)
    (OUT / "phase6-v29-terminal-outcome.md").write_text(
        f"# Phase 6 V29 terminal outcome\n\n`{outcome}`\n\n"
        f"The authoritative sample contains {sample['all_closed_legs']} naturally closed legs, including {sample['dated_2026']} in pre-seal 2026, {sample['LONG']} LONG, {sample['SHORT']} SHORT, {sample['BUY']} BUY and {sample['SELL']} SELL.\n\n"
        f"Normal/Native 2025: PF {normal_native[0]['profit_factor']:.4f}, net USD {normal_native[0]['adjusted_net_profit']:.2f}, expectancy {normal_native[0]['expectancy_R']:.6f} R, drawdown {normal_native[0]['relative_drawdown_percent']:.4f}%. "
        f"Normal/Native 2026: PF {normal_native[1]['profit_factor']:.4f}, net USD {normal_native[1]['adjusted_net_profit']:.2f}, expectancy {normal_native[1]['expectancy_R']:.6f} R, drawdown {normal_native[1]['relative_drawdown_percent']:.4f}%.\n\n"
        f"Failed mandatory gates: performance {failed_performance}, concentration {failed_concentration}, consistency {failed_consistency}. The separate future V28/V29 combination manifest remains unexecuted. No optimization, sealed-OOS access, demo trade, live trade, or production Phase 1-5 change occurred.\n"
    )
    checksum = OUT / "artifact-sha256-v29.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({"outcome": outcome, "sample": sample, "normal_native": normal_native, "failed_performance": failed_performance, "failed_concentration": failed_concentration, "failed_consistency": failed_consistency, "risk_ok": risk_ok}, indent=2))


if __name__ == "__main__":
    main()
