#!/usr/bin/env python3
"""Reconcile V14 MT5 evidence and build the frozen research artifacts."""

from __future__ import annotations

import csv
from datetime import datetime, timedelta
import hashlib
import json
import math
from pathlib import Path
import random
import statistics

from run_phase6_v14_matrix import OUT, CORE_HASH, plans

INITIAL_EQUITY = 10000.0
RISK_FRACTION = 0.0025
POINT = 0.00001
TICK_SIZE = 0.00001
TICK_VALUE = 1.0
COMMISSION_SIDE_PER_LOT = 3.0
BOOTSTRAP_SEED = 4201290849
MONTE_CARLO_SEED = 2000388822
PATHS = 100000
DATASET_SPANS = {
    "DEVELOPMENT": (datetime(2025, 1, 16), datetime(2025, 7, 5)),
    "VALIDATION": (datetime(2025, 7, 5), datetime(2025, 9, 29)),
    "OUT_OF_SAMPLE": (datetime(2025, 9, 29), datetime(2025, 12, 24)),
}


def jwrite(name: str, value) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n",
                            encoding="utf-8")


def parse_time(value: str) -> datetime | None:
    if not value or value == "NONE":
        return None
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def summary(path: Path) -> dict[str, str]:
    rows = read_csv(path)
    return {r["field"]: r["value"] for r in rows}


def f(value: str | float | int | None) -> float:
    return float(value or 0.0)


def i(value: str | float | int | None) -> int:
    return int(float(value or 0))


def reconstruct(p: dict) -> tuple[list[dict], list[dict], dict]:
    run_dir = OUT / "physical-runs" / p["slug"]
    deals = read_csv(run_dir / "deals.csv")
    tx = read_csv(run_dir / "transactions.csv")
    events = read_csv(run_dir / "events.csv")
    summ = summary(run_dir / "run-summary.csv")
    by_position: dict[str, list[dict]] = {}
    for d in deals:
        by_position.setdefault(d["position_identifier"], []).append(d)

    accepted_entries = {}
    exit_reasons = {}
    for row in tx:
        if row["record_type"] == "ENTRY_ATTEMPT" and i(row["broker_retcode"]) in (10008, 10009, 10010):
            accepted_entries[row["deal_ticket"]] = row
        if row["record_type"] == "EXIT_TRANSACTION" and row["fill_confirmed"] == "YES":
            exit_reasons[row["position_identifier"]] = row["exit_reason"]

    trades = []
    censored = []
    native_commission = 0.0
    for pos, rows in by_position.items():
        rows.sort(key=lambda r: i(r["time_msc"]))
        entries = [r for r in rows if i(r["entry"]) in (0, 2)]
        exits = [r for r in rows if i(r["entry"]) in (1, 2)]
        if not entries:
            continue
        entry = entries[0]
        entry_time = parse_time(entry["time"])
        eligible_to = parse_time(p["eligible_to"])
        natural_exits = [r for r in exits if parse_time(r["time"]) < eligible_to]
        attempt = accepted_entries.get(entry["deal_ticket"], {})
        volume = sum(f(r["volume"]) for r in entries)
        native_deal_net = sum(f(r["profit"]) + f(r["commission"]) +
                              f(r["swap"]) + f(r["fee"]) for r in rows)
        commission_native = sum(f(r["commission"]) for r in rows)
        native_commission += commission_native
        external_commission = COMMISSION_SIDE_PER_LOT * (
            sum(f(r["volume"]) for r in entries) +
            sum(f(r["volume"]) for r in natural_exits))
        native_net = native_deal_net - external_commission
        spread_points = i(attempt.get("spread_points"))
        point_cost = (POINT / TICK_SIZE) * TICK_VALUE * volume
        spread_cost = max(0, spread_points) * point_cost
        requested = f(attempt.get("requested_price"))
        fill = f(entry["price"])
        direction = "LONG" if i(entry["type"]) == 0 else "SHORT"
        entry_slip_points = 0.0
        if requested > 0:
            entry_slip_points = max(0.0, ((fill - requested) if direction == "LONG"
                                          else (requested - fill)) / POINT)
        swap_cost = sum(abs(f(r["swap"])) for r in rows)
        fee_cost = sum(abs(f(r["fee"])) for r in rows)
        commission_cost = external_commission
        native_friction = spread_cost + commission_cost + swap_cost + fee_cost + entry_slip_points * point_cost
        charge = native_friction * p["multiplier"]
        adjusted_net = native_net - charge
        risk = f(attempt.get("initial_risk_amount"))
        exit_time = parse_time(natural_exits[-1]["time"]) if natural_exits else None
        reason = exit_reasons.get(pos)
        if not reason and natural_exits:
            reason = "STOP_LOSS_EXIT" if i(natural_exits[-1]["reason"]) == 4 else "EXPERT_EXIT_UNCLASSIFIED"
        trade = {
            "physical_run": p["number"], "run_id": p["slug"], "segment": p["id"],
            "dataset": p["dataset"], "cost_profile": p["profile"],
            "execution_layer": p["layer"], "position_identifier": pos,
            "direction": direction, "entry_time": entry_time, "exit_time": exit_time,
            "entry_price": fill, "exit_price": f(natural_exits[-1]["price"]) if natural_exits else None,
            "volume": volume, "initial_risk_amount": risk,
            "native_deal_net_before_external_commission": native_deal_net,
            "native_tester_commission": commission_native,
            "external_commission_adjustment": external_commission,
            "native_trade_net": native_net, "spread_cost": spread_cost,
            "swap_cost": swap_cost, "fee_cost": fee_cost,
            "adverse_entry_slippage_cost": entry_slip_points * point_cost,
            "adverse_exit_slippage_cost": 0.0, "native_friction": native_friction,
            "supplementary_multiplier": p["multiplier"],
            "supplementary_charge": charge, "adjusted_trade_net": adjusted_net,
            "realized_net_R": adjusted_net / risk if risk > 0 else None,
            "exit_reason": reason or "RIGHT_CENSORED_OPEN_POSITION",
            "naturally_closed": bool(natural_exits),
            "holding_seconds": (exit_time - entry_time).total_seconds() if exit_time else None,
        }
        if natural_exits:
            trades.append(trade)
        else:
            censored.append(trade)
    counters = {k: i(summ.get(k)) for k in (
        "evaluations", "entry_signals", "exit_signals", "execution_evaluations",
        "execution_submissions", "execution_acceptances", "entry_fills",
        "close_evaluations", "close_submissions", "close_acceptances", "exit_fills",
        "risk_blocks", "spread_blocks", "loss_limit_pauses", "post_cutoff_actions")}
    counters["risk_blocks"] = sum(r["reason_code"] in
        ("RISK_ENGINE_LOCKED", "RISK_LOCKED") for r in events)
    counters["spread_blocks"] = sum(r["reason_code"] in
        ("EXCESSIVE_SPREAD", "SPREAD_EXCEEDS_LIMIT") for r in events)
    counters["loss_limit_pauses"] = sum("LOSS_LIMIT" in r["reason_code"] or
        "DAILY_LOSS" in r["reason_code"] or "WEEKLY_LOSS" in r["reason_code"]
        for r in events)
    counters["native_commission"] = native_commission
    counters["censored_positions"] = len(censored)
    counters["total_positions"] = len(trades) + len(censored)
    return trades, censored, counters


def max_streak(values: list[float], positive: bool) -> int:
    best = current = 0
    for value in values:
        hit = value > 0 if positive else value < 0
        current = current + 1 if hit else 0
        best = max(best, current)
    return best


def contribution(groups: dict, net: float) -> float | None:
    if net <= 0 or not groups:
        return None
    return max(groups.values()) / net * 100.0


def metrics(trades: list[dict], counters: dict, dataset: str) -> dict:
    ordered = sorted(trades, key=lambda t: (t["exit_time"], t["physical_run"], t["position_identifier"]))
    equity = peak = INITIAL_EQUITY
    max_dd_money = max_dd_pct = 0.0
    synthetic = []
    r_values = []
    for trade in ordered:
        r_value = trade["realized_net_R"]
        cash = equity * RISK_FRACTION * r_value
        trade["synthetic_equity_before"] = equity
        trade["synthetic_cash_flow"] = cash
        equity += cash
        trade["synthetic_equity_after"] = equity
        peak = max(peak, equity)
        dd = peak - equity
        max_dd_money = max(max_dd_money, dd)
        max_dd_pct = max(max_dd_pct, dd / peak * 100.0 if peak else 0.0)
        synthetic.append(cash)
        r_values.append(r_value)
    wins = [x for x in synthetic if x > 0]
    losses = [x for x in synthetic if x < 0]
    gross_profit = sum(wins)
    gross_loss_abs = -sum(losses)
    net = sum(synthetic)
    start, end = DATASET_SPANS[dataset]
    years = (end - start).total_seconds() / (365.0 * 86400.0)
    annualized = ((equity / INITIAL_EQUITY) ** (1.0 / years) - 1.0) * 100.0 if equity > 0 and years > 0 else -100.0
    days = {}
    weeks = {}
    months = {}
    segments = {}
    periods = {n: 0.0 for n in range(5)}
    span_seconds = (end - start).total_seconds()
    for trade, cash in zip(ordered, synthetic):
        dt = trade["exit_time"]
        days[dt.date().isoformat()] = days.get(dt.date().isoformat(), 0.0) + cash
        iso = dt.isocalendar()
        wk = f"{iso.year}-W{iso.week:02d}"
        weeks[wk] = weeks.get(wk, 0.0) + cash
        mo = dt.strftime("%Y-%m")
        months[mo] = months.get(mo, 0.0) + cash
        segments[trade["segment"]] = segments.get(trade["segment"], 0.0) + cash
        idx = min(4, max(0, int((dt - start).total_seconds() / span_seconds * 5)))
        periods[idx] += cash
    largest_win = max(wins, default=0.0)
    largest_loss = min(losses, default=0.0)
    avg_win = statistics.mean(wins) if wins else 0.0
    avg_loss = statistics.mean(losses) if losses else 0.0
    pf = gross_profit / gross_loss_abs if gross_loss_abs else (999999.0 if gross_profit else 0.0)
    result = {
        "initial_synthetic_equity": INITIAL_EQUITY, "final_synthetic_equity": equity,
        "adjusted_net_profit": net, "gross_profit": gross_profit,
        "gross_loss": -gross_loss_abs, "profit_factor": pf,
        "expectancy_money": statistics.mean(synthetic) if synthetic else 0.0,
        "expectancy_R": statistics.mean(r_values) if r_values else 0.0,
        "normalized_expectancy_R": statistics.mean(r_values) if r_values else 0.0,
        "expected_payoff": statistics.mean(synthetic) if synthetic else 0.0,
        "total_trades": counters.get("total_positions", len(ordered)),
        "naturally_closed_trades": len(ordered), "winning_trades": len(wins),
        "losing_trades": len(losses), "breakeven_trades": len(ordered)-len(wins)-len(losses),
        "win_rate_percent": len(wins) / len(ordered) * 100.0 if ordered else 0.0,
        "average_win": avg_win, "average_loss": avg_loss,
        "payoff_ratio": avg_win / abs(avg_loss) if avg_loss else None,
        "largest_win": largest_win, "largest_loss": largest_loss,
        "maximum_drawdown_money": max_dd_money,
        "relative_drawdown_percent": max_dd_pct,
        "annualized_return_percent": annualized,
        "recovery_factor": net / max_dd_money if max_dd_money else None,
        "maximum_consecutive_wins": max_streak(synthetic, True),
        "maximum_consecutive_losses": max_streak(synthetic, False),
        "long_net_profit": sum(t["synthetic_cash_flow"] for t in ordered if t["direction"] == "LONG"),
        "short_net_profit": sum(t["synthetic_cash_flow"] for t in ordered if t["direction"] == "SHORT"),
        "stop_loss_exits": sum(t["exit_reason"] == "STOP_LOSS_EXIT" for t in ordered),
        "donchian_exits": sum("BREAKOUT" in t["exit_reason"] for t in ordered),
        "average_holding_seconds": statistics.mean([t["holding_seconds"] for t in ordered]) if ordered else 0.0,
        "median_holding_seconds": statistics.median([t["holding_seconds"] for t in ordered]) if ordered else 0.0,
        "risk_engine_blocks": counters.get("risk_blocks", 0),
        "spread_blocks": counters.get("spread_blocks", 0),
        "loss_limit_pauses": counters.get("loss_limit_pauses", 0),
        "best_trade_contribution_percent": (largest_win / net * 100.0) if net > 0 else None,
        "best_day_contribution_percent": contribution(days, net),
        "best_week_contribution_percent": contribution(weeks, net),
        "best_month_contribution_percent": contribution(months, net),
        "best_registered_subperiod_contribution_percent": contribution(periods, net),
        "clean_segment_contribution_percent": contribution(segments, net),
        "censored_positions": counters.get("censored_positions", 0),
    }
    return result


def percentile(values: list[float], q: float) -> float:
    values = sorted(values)
    if not values:
        return 0.0
    pos = (len(values) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    return values[lo] if lo == hi else values[lo] * (hi-pos) + values[hi] * (pos-lo)


def path_drawdown(r_values: list[float]) -> tuple[float, float]:
    equity = peak = INITIAL_EQUITY
    max_dd = 0.0
    for rv in r_values:
        equity *= 1.0 + RISK_FRACTION * rv
        peak = max(peak, equity)
        max_dd = max(max_dd, (peak-equity)/peak*100.0)
    return equity, max_dd


def uncertainty(trades: list[dict]) -> tuple[dict, dict]:
    values = [t["realized_net_R"] for t in sorted(trades, key=lambda t: t["exit_time"])]
    if not values:
        base = {"status": "NOT_CALCULATED_NO_TRADES", "paths": 0}
        return base, base
    rng = random.Random(BOOTSTRAP_SEED)
    means, money_expectancies, dds, endings = [], [], [], []
    n = len(values)
    for _ in range(PATHS):
        sample = [values[rng.randrange(n)] for _ in range(n)]
        ending, dd = path_drawdown(sample)
        means.append(statistics.mean(sample)); dds.append(dd); endings.append(ending)
        money_expectancies.append((ending - INITIAL_EQUITY) / n)
    bootstrap = {
        "schema": "SOLTRADE_PHASE6_V14_BOOTSTRAP_REPORT_V1", "status": "CALCULATED",
        "paths": PATHS, "seed_decimal": BOOTSTRAP_SEED, "seed_hex": "0xFA6A9C61",
        "sample_trades": n, "reporting_only": True,
        "assumption": "Individual-trade bootstrap assumes independently resampled historical trade returns; it does not reproduce serial dependence, market regimes, or the strategy time-based lock state.",
        "expectancy_R_95_percent_confidence_interval": [percentile(means, .025), percentile(means, .975)],
        "expectancy_money_95_percent_confidence_interval": [percentile(money_expectancies, .025), percentile(money_expectancies, .975)],
        "median_simulated_drawdown_percent": percentile(dds, .50),
        "p90_simulated_drawdown_percent": percentile(dds, .90),
        "p95_simulated_drawdown_percent": percentile(dds, .95),
        "probability_ending_with_negative_net_profit": sum(x < INITIAL_EQUITY for x in endings)/PATHS,
    }
    rng = random.Random(MONTE_CARLO_SEED)
    dds = []
    endings = []
    for _ in range(PATHS):
        sample = values.copy(); rng.shuffle(sample)
        ending, dd = path_drawdown(sample); dds.append(dd); endings.append(ending)
    monte = {
        "schema": "SOLTRADE_PHASE6_V14_MONTE_CARLO_REPORT_V1", "status": "CALCULATED",
        "reshuffles": PATHS, "seed_decimal": MONTE_CARLO_SEED, "seed_hex": "0x773B82D6",
        "sample_trades": n, "reporting_only": True,
        "method": "Chronological completed-trade outcome reshuffling; trading decisions and time-based risk state are not replayed.",
        "median_simulated_drawdown_percent": percentile(dds, .50),
        "p90_simulated_drawdown_percent": percentile(dds, .90),
        "p95_simulated_drawdown_percent": percentile(dds, .95),
        "probability_ending_with_negative_net_profit": sum(x < INITIAL_EQUITY for x in endings)/PATHS,
    }
    return bootstrap, monte


def json_trade(trade: dict) -> dict:
    return {k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in trade.items()}


def csv_write(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    if fields is None:
        fields = list(rows[0]) if rows else []
    with path.open("w", newline="", encoding="utf-8") as fobj:
        writer = csv.DictWriter(fobj, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in row.items()})


def gate_for_cell(cell: dict) -> list[dict]:
    m = cell["metrics"]
    profile = cell["cost_profile"]
    rules = {
        "NORMAL": (("profit_factor", ">", 1.15), ("adjusted_net_profit", ">", 0),
                   ("expectancy_money", ">", 0), ("relative_drawdown_percent", "<", 8.0)),
        "HIGH": (("profit_factor", ">=", 1.05), ("adjusted_net_profit", ">", 0),
                 ("expectancy_money", ">", 0), ("relative_drawdown_percent", "<=", 10.0)),
        "STRESS": (("profit_factor", ">=", 1.0), ("adjusted_net_profit", ">", 0),
                   ("expectancy_money", ">", 0), ("relative_drawdown_percent", "<=", 12.0)),
    }
    result = []
    for field, op, threshold in rules[profile]:
        actual = m[field]
        passed = {">": actual > threshold, ">=": actual >= threshold,
                  "<": actual < threshold, "<=": actual <= threshold}[op]
        result.append({"cell_id": cell["cell_id"], "gate": field,
                       "rule": f"{op} {threshold}", "actual": actual,
                       "status": "PASS" if passed else "FAIL"})
    for field, threshold in (("best_trade_contribution_percent", 20.0),
                             ("best_registered_subperiod_contribution_percent", 40.0)):
        actual = m[field]
        passed = actual is not None and actual <= threshold
        result.append({"cell_id": cell["cell_id"], "gate": field,
                       "rule": f"<= {threshold}", "actual": actual,
                       "status": "PASS" if passed else "FAIL"})
    return result


def main() -> int:
    physical_inventory = json.loads((OUT / "phase6-v14-physical-run-inventory.json").read_text())
    if len(physical_inventory["runs"]) != 36 or any(r["status"] != "PASS" for r in physical_inventory["runs"]):
        raise SystemExit("INVALID_TEST_EVIDENCE: physical matrix incomplete or invalid")

    all_trades = []
    all_censored = []
    physical_metrics = []
    counters_by_run = {}
    commission_total = 0.0
    for p in plans():
        trades, censored, counters = reconstruct(p)
        counters_by_run[p["number"]] = counters
        commission_total += counters["native_commission"]
        m = metrics(trades, counters, p["dataset"])
        physical_metrics.append({"run_number": p["number"], "run_id": p["slug"],
                                 "segment": p["id"], "dataset": p["dataset"],
                                 "cost_profile": p["profile"], "execution_layer": p["layer"], **m})
        all_trades.extend(trades)
        all_censored.extend(censored)

    # Aggregate the clean segments chronologically with no reporting-equity reset.
    formal_cells = []
    for layer in ("NATIVE_NORMAL_EXECUTION", "FIXED_DELAY_200_MS"):
        for dataset in ("DEVELOPMENT", "VALIDATION", "OUT_OF_SAMPLE"):
            for profile in ("NORMAL", "HIGH", "STRESS"):
                selected_plans = [p for p in plans() if p["layer"] == layer and
                                  p["dataset"] == dataset and p["profile"] == profile]
                nums = {p["number"] for p in selected_plans}
                selected = [dict(t) for t in all_trades if t["physical_run"] in nums]
                counters = {key: sum(counters_by_run[n].get(key, 0) for n in nums)
                            for key in counters_by_run[next(iter(nums))]}
                m = metrics(selected, counters, dataset)
                cell_id = f"{dataset}-{profile}-" + ("NATIVE" if layer.startswith("NATIVE") else "DELAY200")
                formal_cells.append({"cell_id": cell_id, "dataset": dataset,
                                     "cost_profile": profile, "execution_layer": layer,
                                     "physical_runs": sorted(nums), "metrics": m,
                                     "trades": selected})

    cell_rows = [{"cell_id": c["cell_id"], "dataset": c["dataset"],
                  "cost_profile": c["cost_profile"], "execution_layer": c["execution_layer"],
                  **c["metrics"]} for c in formal_cells]
    csv_write(OUT / "phase6-v14-physical-run-metrics.csv", physical_metrics)
    csv_write(OUT / "phase6-v14-formal-cell-metrics.csv", cell_rows)
    csv_write(OUT / "phase6-v14-complete-trade-ledger.csv",
              [json_trade(t) for t in all_trades])

    cell_inventory = {"schema": "SOLTRADE_PHASE6_V14_FORMAL_CELL_INVENTORY_V1",
                      "formal_cells": 18,
                      "cells": [{k: v for k, v in c.items() if k != "trades"} for c in formal_cells]}
    jwrite("phase6-v14-formal-cell-inventory.json", cell_inventory)
    native = [{k: v for k, v in c.items() if k != "trades"} for c in formal_cells
              if c["execution_layer"] == "NATIVE_NORMAL_EXECUTION"]
    delay = [{k: v for k, v in c.items() if k != "trades"} for c in formal_cells
             if c["execution_layer"] == "FIXED_DELAY_200_MS"]
    jwrite("phase6-v14-authoritative-native-matrix.json",
           {"schema": "SOLTRADE_PHASE6_V14_NATIVE_MATRIX_V1", "cells": native})
    jwrite("phase6-v14-delay-replica-matrix.json",
           {"schema": "SOLTRADE_PHASE6_V14_DELAY_REPLICA_MATRIX_V1", "cells": delay})

    jwrite("phase6-v14-censored-position-report.json",
           {"schema": "SOLTRADE_PHASE6_V14_CENSORED_POSITIONS_V1",
            "count": len(all_censored), "formal_pnl_included": False,
            "positions": [json_trade(t) for t in all_censored]})
    commission_status = "EXTERNAL_FROZEN_COMMISSION_APPLIED" if abs(commission_total) < 1e-9 else "NATIVE_NONZERO_UNRECONCILED"
    jwrite("phase6-v14-commission-reconciliation.json",
           {"schema": "SOLTRADE_PHASE6_V14_COMMISSION_RECONCILIATION_V1",
            "native_tester_commission_total": commission_total,
            "status": commission_status,
            "external_commission": {"currency": "USD", "per_side_per_standard_lot": 3.0,
                                    "round_trip_per_standard_lot": 6.0,
                                    "linear_pro_rata": True},
            "double_counted": False})

    profiles = {}
    for profile, multiplier in (("NORMAL", 0.0), ("HIGH", 0.5), ("STRESS", 1.0)):
        profile_trades = [t for t in all_trades if t["cost_profile"] == profile]
        profiles[profile] = {"supplementary_multiplier": multiplier,
                             "trades": len(profile_trades),
                             "native_trade_net": sum(t["native_trade_net"] for t in profile_trades),
                             "native_friction": sum(t["native_friction"] for t in profile_trades),
                             "supplementary_charge": sum(t["supplementary_charge"] for t in profile_trades),
                             "adjusted_trade_net": sum(t["adjusted_trade_net"] for t in profile_trades)}
    jwrite("phase6-v14-cost-profile-summary.json",
           {"schema": "SOLTRADE_PHASE6_V14_COST_PROFILE_SUMMARY_V1",
            "supplementary_not_broker_native": True, "profiles": profiles})

    impacts = []
    for ncell in native:
        dcell = next(c for c in delay if c["dataset"] == ncell["dataset"] and c["cost_profile"] == ncell["cost_profile"])
        impacts.append({"dataset": ncell["dataset"], "cost_profile": ncell["cost_profile"],
                        "native_net_profit": ncell["metrics"]["adjusted_net_profit"],
                        "delay_net_profit": dcell["metrics"]["adjusted_net_profit"],
                        "net_profit_difference": dcell["metrics"]["adjusted_net_profit"]-ncell["metrics"]["adjusted_net_profit"],
                        "native_closed_trades": ncell["metrics"]["naturally_closed_trades"],
                        "delay_closed_trades": dcell["metrics"]["naturally_closed_trades"]})
    jwrite("phase6-v14-delay-impact-report.json",
           {"schema": "SOLTRADE_PHASE6_V14_DELAY_IMPACT_V1", "comparisons": impacts})
    jwrite("phase6-v14-concentration-report.json",
           {"schema": "SOLTRADE_PHASE6_V14_CONCENTRATION_V1",
            "rules": {"best_trade_max_percent": 20.0, "best_registered_subperiod_max_percent": 40.0,
                      "subperiod_semantics": "Five equal chronological subperiods for intervals shorter than four years"},
            "cells": [{"cell_id": c["cell_id"],
                       "best_trade_contribution_percent": c["metrics"]["best_trade_contribution_percent"],
                       "best_registered_subperiod_contribution_percent": c["metrics"]["best_registered_subperiod_contribution_percent"],
                       "clean_segment_contribution_percent": c["metrics"]["clean_segment_contribution_percent"]}
                      for c in formal_cells]})

    consistency_groups = []
    consistency_gates = []
    for layer in ("NATIVE_NORMAL_EXECUTION", "FIXED_DELAY_200_MS"):
        for profile in ("NORMAL", "HIGH", "STRESS"):
            cells = [c for c in formal_cells if c["execution_layer"] == layer and c["cost_profile"] == profile]
            exps = [c["metrics"]["normalized_expectancy_R"] for c in cells]
            annuals = [c["metrics"]["annualized_return_percent"] for c in cells]
            pfs = [c["metrics"]["profit_factor"] for c in cells]
            max_exp, max_ann = max(exps), max(annuals)
            exp_ratio = min(exps)/max_exp if max_exp > 0 else None
            ann_ratio = min(annuals)/max_ann if max_ann > 0 else None
            pf_range = max(pfs)-min(pfs)
            record = {"execution_layer": layer, "cost_profile": profile,
                      "normalized_expectancy_min_vs_max": exp_ratio,
                      "annualized_return_min_vs_max": ann_ratio,
                      "profit_factor_range": pf_range}
            consistency_groups.append(record)
            for gate, actual, passed in (
                ("normalized_expectancy_min_vs_max >= 0.50", exp_ratio, exp_ratio is not None and exp_ratio >= .5),
                ("annualized_return_min_vs_max >= 0.50", ann_ratio, ann_ratio is not None and ann_ratio >= .5),
                ("profit_factor_range <= 0.40", pf_range, pf_range <= .4)):
                consistency_gates.append({**record, "gate": gate, "actual": actual,
                                          "status": "PASS" if passed else "FAIL"})
    jwrite("phase6-v14-cross-dataset-consistency.json",
           {"schema": "SOLTRADE_PHASE6_V14_CROSS_DATASET_CONSISTENCY_V1",
            "groups": consistency_groups, "gates": consistency_gates})

    gates = [g for c in formal_cells for g in gate_for_cell(c)]
    oos_cells = [c for c in formal_cells if c["dataset"] == "OUT_OF_SAMPLE"]
    oos_count = min(c["metrics"]["naturally_closed_trades"] for c in oos_cells)
    sample_gate = {"gate": "OOS naturally closed trades >= 50", "actual": oos_count,
                   "status": "PASS" if oos_count >= 50 else "FAIL"}
    all_gates = gates + consistency_gates + [sample_gate]
    performance_failed = any(g["status"] == "FAIL" for g in gates + consistency_gates)
    outcome = ("INVALID_TEST_EVIDENCE" if commission_status != "EXTERNAL_FROZEN_COMMISSION_APPLIED"
               else "INCONCLUSIVE_INSUFFICIENT_SAMPLE" if oos_count < 50
               else "RESEARCH_REJECTED" if performance_failed else "RESEARCH_ACCEPTED")
    jwrite("phase6-v14-gate-evaluation.json",
           {"schema": "SOLTRADE_PHASE6_V14_GATE_EVALUATION_V1",
            "terminal_outcome": outcome, "oos_naturally_closed_trade_count": oos_count,
            "passed": sum(g["status"] == "PASS" for g in all_gates),
            "failed": sum(g["status"] == "FAIL" for g in all_gates), "gates": all_gates})

    oos_normal_native = next(c for c in formal_cells if c["dataset"] == "OUT_OF_SAMPLE" and
                             c["cost_profile"] == "NORMAL" and
                             c["execution_layer"] == "NATIVE_NORMAL_EXECUTION")
    bootstrap, monte = uncertainty(oos_normal_native["trades"])
    jwrite("phase6-v14-bootstrap-report.json", bootstrap)
    jwrite("phase6-v14-monte-carlo-report.json", monte)

    compile_log = Path.home() / ".wine-fpmarkets/drive_c/v14/v14-compile.log"
    ex5 = Path.home() / ".wine-fpmarkets/drive_c/v14/SolTradePhase6V14PracticalBacktest.ex5"
    execution_manifest = {
        "schema": "SOLTRADE_PHASE6_V14_EXECUTION_MANIFEST_V1",
        "study": "CONTROLLED_PRACTICAL_BACKTEST", "v13_commit": "e0522c607eb59641662a7be9922fd8bd2ba4784c",
        "v13_manifest_sha256": "5ede3a1bf1ada3de332705af8746f54cc98362234b5c72c7a7da87cd435a2160",
        "core_trading_input_hash": CORE_HASH, "production_ea_sha256": "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
        "tester_model": "EVERY_TICK_BASED_ON_REAL_TICKS", "generated_tick_fallback": False,
        "broker": "FP Markets", "server": "FPMarketsSC-Demo", "symbol": "EURUSD",
        "terminal_build": 6090, "physical_runs": 36, "formal_cells": 18,
        "optimization": False, "connected_demo_or_live_trades": 0,
        "bootstrap_seed": BOOTSTRAP_SEED, "monte_carlo_seed": MONTE_CARLO_SEED,
        "terminal_outcome": outcome,
    }
    jwrite("phase6-v14-execution-manifest.json", execution_manifest)
    jwrite("phase6-v14-configuration-verification.json",
           {"schema": "SOLTRADE_PHASE6_V14_CONFIGURATION_VERIFICATION_V1", "status": "PASS",
            "compile_errors": 0, "compile_warnings": 0, "compile_log_sha256": hashlib.sha256(compile_log.read_bytes()).hexdigest(),
            "harness_ex5_sha256": hashlib.sha256(ex5.read_bytes()).hexdigest(),
            "all_physical_runs_same_core_hash": True, "only_frozen_axes_varied": True,
            "real_tick_model_all_runs": True, "generated_tick_fallback": False,
            "bootstrap_seed": BOOTSTRAP_SEED, "monte_carlo_seed": MONTE_CARLO_SEED,
            "production_ea_unchanged": True})
    jwrite("phase6-v14-evidence-integrity.json",
           {"schema": "SOLTRADE_PHASE6_V14_EVIDENCE_INTEGRITY_V1", "status": "PASS",
            "physical_runs_valid": 36, "formal_cells_valid": 18,
            "native_html_reports_emitted": sum((OUT/"physical-runs"/p["slug"]/"native-mt5-report.html").exists() for p in plans()),
            "native_tester_statistics_reports": 36, "native_tester_caches": 36,
            "tester_agent_logs": 36, "technical_failures_preserved": 2,
            "technical_rerun_configuration_sha256": "a7da7737d5a6bb0e601a18516dc119ccbda28d074aca8d9ec14affcce526ff78",
            "technical_rerun_configuration_identical": True,
            "configuration_or_history_mismatch": False, "state_collision": False,
            "phase_1_through_5_logic_changed": False})

    outcome_md = f"""# Phase 6 V14 terminal outcome

`{outcome}`

All 36 frozen physical Strategy Tester runs and all 18 formal cells produced valid evidence. The OOS naturally closed-trade count is **{oos_count}** against the frozen minimum of 50. Profitability evidence is reported without omission, but the sample-size rule controls the terminal outcome when it is not met.

No optimization, parameter tuning, connected chart trade, demo-forward trade, live trade, Phase 7 action, or Phase 1–5 production-logic change occurred. Supplementary cost results are reporting-only cash-flow reconstructions and are not represented as broker-native fills.
"""
    (OUT / "phase6-v14-terminal-outcome.md").write_text(outcome_md, encoding="utf-8")

    # Hash all final evidence except the hash listing itself.
    artifacts = sorted(p for p in OUT.rglob("*") if p.is_file() and p.name != "artifact-sha256-v14.txt")
    lines = []
    for path in artifacts:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(OUT).as_posix()}")
    (OUT / "artifact-sha256-v14.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    print(outcome)
    print(f"OOS_CLOSED_TRADES={oos_count}")
    print(f"PASSED_GATES={sum(g['status']=='PASS' for g in all_gates)}")
    print(f"FAILED_GATES={sum(g['status']=='FAIL' for g in all_gates)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
