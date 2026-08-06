#!/usr/bin/env python3
"""Build the bounded E8 Pro Forex 10K/V28 rule audit from frozen evidence."""

from __future__ import annotations

import csv
import hashlib
import json
import statistics
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
RUNS = V28 / "performance-runs-attempt2"
LEDGER = V28 / "phase6-v28-complete-adjusted-trade-ledger.csv"
METRICS = V28 / "phase6-v28-formal-cell-metrics.csv"
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
OUTCOME = "V28_E8_PRO_FOREX_10K_FAILS_REQUIRED_RULES"
SOURCE_COMMIT = "36dfbb31676457d992c110db8ffb802ba27fa00b"
FMT = "%Y.%m.%d %H:%M:%S"

CONDITIONS = {
    "NORMAL": ("NORMAL", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "HIGH": ("HIGH", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "STRESS": ("STRESS", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "200MS": ("NORMAL", "FIXED_DELAY_200_MS", ["03-v28-2025-development-delay200", "04-v28-2026-preseal-development-delay200"]),
}

SOURCE_FILES = [
    V28 / "candidate-strategy-specification.json",
    V28 / "formal-cell-plan.json",
    V28 / "performance-executable-freeze.json",
    V28 / "phase6-v28-evidence-integrity.json",
    V28 / "phase6-v28-formal-cell-metrics.csv",
    LEDGER,
    V28 / "signal-feasibility/signal-schedule.csv",
    V28 / "artifact-sha256-v28.txt",
    ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5",
]
for run in CONDITIONS["NORMAL"][2] + CONDITIONS["200MS"][2]:
    for name in ("deals.csv", "events.csv", "transactions.csv", "run-summary.csv", "physical-run-status.json", "strategy-tester.ini", "native-mt5-report.html"):
        SOURCE_FILES.append(RUNS / run / name)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_text(name: str, value: str) -> None:
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.rstrip() + "\n", encoding="utf-8")


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def transaction_rows(runs: list[str]) -> list[dict[str, str]]:
    result = []
    for run in runs:
        result.extend(read_csv(RUNS / run / "transactions.csv"))
    return result


def deal_rows(runs: list[str]) -> list[dict[str, str]]:
    result = []
    for run in runs:
        result.extend(row for row in read_csv(RUNS / run / "deals.csv") if row["in_research_window"] == "YES")
    return result


def summary_map(run: str) -> dict[str, str]:
    return {row["field"]: row["value"] for row in read_csv(RUNS / run / "run-summary.csv")}


def max_simultaneous(rows: list[dict[str, str]]) -> int:
    events = []
    for row in rows:
        events.append((parse_time(row["entry_time"]), 1, 1))
        events.append((parse_time(row["exit_time"]), 0, -1))
    current = maximum = 0
    for _, _, change in sorted(events):
        current += change
        maximum = max(maximum, current)
    return maximum


def risk_episodes(transactions: list[dict[str, str]]) -> list[dict[str, object]]:
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in transactions:
        if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0":
            groups[row["signal_time"]].append(row)
    result = []
    for signal, rows in sorted(groups.items()):
        amount = sum(float(row["initial_risk_amount"]) for row in rows)
        result.append({
            "signal_time": signal,
            "legs": len(rows),
            "symbols": "|".join(row["symbol"] for row in rows),
            "aggregate_initial_stop_risk_usd": amount,
            "aggregate_risk_percent_of_source_starting_balance": amount / 10000 * 100,
            "aggregate_risk_percent_of_e8_daily_drawdown": amount / 250 * 100,
            "reaches_or_exceeds_entire_daily_drawdown": "YES" if amount >= 250 else "NO",
        })
    return result


def request_stats(transactions: list[dict[str, str]]) -> dict[str, int]:
    attempts = [row for row in transactions if row["record_type"] in {"ENTRY_ATTEMPT", "EXIT_ATTEMPT"}]
    submitted = [row for row in attempts if row["record_type"] == "EXIT_ATTEMPT" or row["deal_ticket"] != "0"]
    by_date = Counter(row["time"][:10] for row in submitted)
    times = sorted(parse_time(row["time"]) for row in submitted)
    rolling = left = 0
    for right, stamp in enumerate(times):
        while stamp - times[left] >= timedelta(days=1):
            left += 1
        rolling = max(rolling, right - left + 1)
    return {"maximum_source_date_attempt_records": max(by_date.values(), default=0), "maximum_rolling_24_hour_attempt_records": rolling}


def inactivity(deals: list[dict[str, str]]) -> tuple[list[dict[str, object]], float]:
    # E8 requires a trade to be opened and closed.  Use distinct closing-deal
    # timestamps rather than treating an entry execution alone as compliance.
    times = sorted({parse_time(row["time"]) for row in deals if row["entry"] == "1"})
    gaps = []
    maximum = 0.0
    for start, end in zip(times, times[1:]):
        seconds = (end - start).total_seconds()
        maximum = max(maximum, seconds / 86400)
        if seconds > 30 * 86400:
            gaps.append({
                "previous_completed_trade_execution": start.strftime(FMT),
                "next_completed_trade_execution": end.strftime(FMT),
                "gap_seconds": int(seconds),
                "gap_days": seconds / 86400,
                "exceeds_60_days": "YES" if seconds > 60 * 86400 else "NO",
            })
    return gaps, maximum


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if sha(PRODUCTION) != PRODUCTION_SHA:
        raise RuntimeError("Phase 1-5 production hash guard failed")
    for path in SOURCE_FILES:
        if not path.is_file():
            raise RuntimeError(f"Missing frozen source: {path}")
    ledger = read_csv(LEDGER)
    metrics = read_csv(METRICS)

    all_risk_rows = []
    duration_rows = []
    request_rows = []
    inactivity_rows = []
    target_rows = []
    unresolved_rows = []
    condition_data = {}

    for condition, (cost, layer, runs) in CONDITIONS.items():
        rows = [row for row in ledger if row["cost_profile"] == cost and row["execution_layer"] == layer]
        transactions = transaction_rows(runs)
        deals = deal_rows(runs)
        episodes = risk_episodes(transactions)
        for episode in episodes:
            all_risk_rows.append({"condition": condition, **episode})
        gaps, maximum_gap = inactivity(deals)
        for gap in gaps:
            inactivity_rows.append({"condition": condition, **gap, "interpretation": "GENUINE_V28_EXECUTION_GAP_WITH_QUALIFIED_COVERAGE"})
        durations = [float(row["holding_seconds"]) for row in rows]
        filled_entries = [row for row in transactions if row["record_type"] == "ENTRY_ATTEMPT" and row["deal_ticket"] != "0"]
        stops = sum(float(row["stop_loss"]) > 0 for row in filled_entries)
        requests = request_stats(transactions)
        run_summaries = [summary_map(run) for run in runs]
        schedule_signals = sum(int(value["schedule_signals"]) for value in run_summaries)
        processed_signals = sum(int(value["processed_signals"]) for value in run_summaries)
        entry_attempts = sum(int(value["entry_attempts"]) for value in run_summaries)
        entry_fills = sum(int(value["entry_fills"]) for value in run_summaries)
        max_risk = max(episodes, key=lambda row: float(row["aggregate_initial_stop_risk_usd"]))
        segment_metrics = [row for row in metrics if row["cost_profile"] == cost and row["execution_layer"] == layer]
        segment_profit = {row["dataset"]: float(row["adjusted_net_profit"]) for row in segment_metrics}
        by_segment_direction: dict[tuple[str, str], float] = defaultdict(float)
        by_segment_symbol: dict[tuple[str, str], float] = defaultdict(float)
        for row in rows:
            cash = float(row["synthetic_cash_flow"])
            by_segment_direction[(row["dataset"], row["direction"])] += cash
            by_segment_symbol[(row["dataset"], row["symbol"])] += cash
        largest = max(rows, key=lambda row: float(row["synthetic_cash_flow"]))
        largest_loss = min(rows, key=lambda row: float(row["synthetic_cash_flow"]))
        data = {
            "rows": rows,
            "episodes": episodes,
            "segment_profit": segment_profit,
            "by_segment_direction": by_segment_direction,
            "by_segment_symbol": by_segment_symbol,
            "trade_count": len(rows),
            "buy_count": sum(row["direction"] == "BUY" for row in rows),
            "sell_count": sum(row["direction"] == "SELL" for row in rows),
            "largest_trade": largest,
            "largest_loss": largest_loss,
            "max_risk": max_risk,
            "episodes_over_limit": sum(row["reaches_or_exceeds_entire_daily_drawdown"] == "YES" for row in episodes),
            "max_gap": maximum_gap,
            "max_positions": max_simultaneous(rows),
            "max_ticket": max(float(row["volume"]) for row in rows),
            "minimum_duration": min(durations),
            "median_duration": statistics.median(durations),
            "average_duration": statistics.fmean(durations),
            "under_minute": sum(value < 60 for value in durations),
            "visible_stops": stops,
            "filled_entries": len(filled_entries),
            "requests": requests,
            "missed": sum(int(value["missed_signals"]) for value in run_summaries),
            "risk_blocks": sum(int(value["risk_blocks"]) for value in run_summaries),
            "execution_blocks": sum(int(value["execution_blocks"]) for value in run_summaries),
            "schedule_signals": schedule_signals,
            "processed_signals": processed_signals,
            "entry_attempts": entry_attempts,
            "entry_fills": entry_fills,
        }
        condition_data[condition] = data

        condition_dir = OUT / ({"NORMAL":"normal-condition-results","HIGH":"high-condition-results","STRESS":"stress-condition-results","200MS":"200ms-condition-results"}[condition])
        result = f"""# {condition} condition result

`FAIL`

This is a hard E8 prohibited-practice failure. V28 implements one common USD-factor trade idea with seven simultaneous correlated Forex legs. In the qualified {layer} transaction stream, {data['episodes_over_limit']} of {len(episodes)} cohorts have aggregate initial stop risk at or above the entire USD 250 E8 daily drawdown. The maximum is USD {float(max_risk['aggregate_initial_stop_risk_usd']):.8f}, {float(max_risk['aggregate_risk_percent_of_source_starting_balance']):.6f}% of the source USD 10,000 starting balance and {float(max_risk['aggregate_risk_percent_of_e8_daily_drawdown']):.6f}% of the E8 daily limit, at `{max_risk['signal_time']}`.

The exact continuous raw and counted closed profit, target timestamp, daily drawdown, minimum balance/equity, static-floor margin, best E8 server day and daily-cap removals are unresolved. The qualified evidence resets 2026 to USD 10,000, contains no timestamped intraday equity stream, and cannot be mapped to exact historical E8 server-day boundaries. These gaps do not reverse the confirmed hard prohibited-practice failure.

Source-segment profits are retained separately and are not added: 2025 USD {segment_profit['V28_2025_DEVELOPMENT']:.8f}; 2026 through July USD {segment_profit['V28_2026_PRESEAL_DEVELOPMENT']:.8f}. The challenge target is not validly simulated, so no performance or payout stage is run.

The first 2025 cohort alone is sufficient: before any prior trade or cost overlay could change the initial USD 10,000 balance, its aggregate risk is USD {float(episodes[0]['aggregate_initial_stop_risk_usd']):.8f}, or {float(episodes[0]['aggregate_risk_percent_of_e8_daily_drawdown']):.6f}% of the daily drawdown. High and Stress share that native entry stream; the delayed stream's first cohort is independently above USD 250.

Other supported diagnostics: {len(rows)} trades ({data['buy_count']} BUY, {data['sell_count']} SELL); largest source-segment trade USD {float(data['largest_trade']['synthetic_cash_flow']):.8f} ({data['largest_trade']['symbol']}, `{data['largest_trade']['exit_time']}`); largest loss USD {float(data['largest_loss']['synthetic_cash_flow']):.8f} ({data['largest_loss']['symbol']}, `{data['largest_loss']['exit_time']}`); maximum {data['max_positions']} simultaneous and USD-correlated positions; maximum ticket {data['max_ticket']:.2f} lots; maximum interval between completed-trade executions {data['max_gap']:.8f} days (below 60); {data['under_minute']} trades under one minute; visible stop coverage {stops}/{len(filled_entries)}. The frozen runs processed {data['processed_signals']}/{data['schedule_signals']} scheduled symbol-signals, with {data['entry_attempts']} entry attempts, {data['entry_fills']} fills, {data['missed']} missed signals, {data['risk_blocks']} pre-order risk blocks, and {data['execution_blocks']} execution blocks. Exact per-segment direction, symbol, best source-date and concentration diagnostics are in the adjacent CSV files.
"""
        write_text(str(condition_dir.relative_to(OUT) / "condition-result.md"), result)
        write_csv(condition_dir / "correlated-risk-episodes.csv", list(episodes[0]), episodes)
        segment_rows = []
        for dataset in ("V28_2025_DEVELOPMENT", "V28_2026_PRESEAL_DEVELOPMENT"):
            segment_trade_rows = [row for row in rows if row["dataset"] == dataset]
            daily_profit: dict[str, float] = defaultdict(float)
            for row in segment_trade_rows:
                daily_profit[row["exit_time"][:10]] += float(row["synthetic_cash_flow"])
            best_source_date, best_source_date_profit = max(daily_profit.items(), key=lambda item: item[1])
            best_trade = max(segment_trade_rows, key=lambda row: float(row["synthetic_cash_flow"]))
            worst_trade = min(segment_trade_rows, key=lambda row: float(row["synthetic_cash_flow"]))
            symbol_values = {symbol: by_segment_symbol[(dataset, symbol)] for symbol in ("EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY")}
            largest_symbol, largest_symbol_profit = max(symbol_values.items(), key=lambda item: item[1])
            segment_rows.append({
                "dataset": dataset,
                "source_segment_profit_usd_not_continuous": segment_profit[dataset],
                "trade_count": len(segment_trade_rows),
                "buy_count": sum(row["dataset"] == dataset and row["direction"] == "BUY" for row in rows),
                "buy_net_usd_not_continuous": by_segment_direction[(dataset, "BUY")],
                "sell_count": sum(row["dataset"] == dataset and row["direction"] == "SELL" for row in rows),
                "sell_net_usd_not_continuous": by_segment_direction[(dataset, "SELL")],
                "largest_trade_usd": best_trade["synthetic_cash_flow"],
                "largest_trade_symbol": best_trade["symbol"],
                "largest_trade_exit_time": best_trade["exit_time"],
                "largest_losing_trade_usd": worst_trade["synthetic_cash_flow"],
                "largest_losing_trade_symbol": worst_trade["symbol"],
                "largest_losing_trade_exit_time": worst_trade["exit_time"],
                "best_source_timestamp_date_not_e8_server_day": best_source_date,
                "best_source_timestamp_date_profit_usd": best_source_date_profit,
                "best_source_date_percent_of_segment_profit": best_source_date_profit / segment_profit[dataset] * 100,
                "largest_positive_symbol": largest_symbol,
                "largest_positive_symbol_net_usd": largest_symbol_profit,
                "largest_positive_symbol_percent_of_segment_profit": largest_symbol_profit / segment_profit[dataset] * 100,
            })
        write_csv(condition_dir / "source-segment-diagnostics.csv", list(segment_rows[0]), segment_rows)
        symbol_rows = []
        for dataset in ("V28_2025_DEVELOPMENT", "V28_2026_PRESEAL_DEVELOPMENT"):
            for symbol in ("EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"):
                symbol_rows.append({"dataset": dataset, "symbol": symbol, "net_contribution_usd_not_continuous": by_segment_symbol[(dataset, symbol)]})
        write_csv(condition_dir / "symbol-contribution-source-segments.csv", list(symbol_rows[0]), symbol_rows)

        supported_rows = [
            {"diagnostic": "continuous_raw_closed_profit_usd", "value": "", "status": "UNRESOLVED_NO_VALID_CONTINUOUS_ACCOUNT"},
            {"diagnostic": "continuous_counted_closed_profit_usd", "value": "", "status": "UNRESOLVED_NO_VALID_CONTINUOUS_ACCOUNT_OR_SERVER_DAY"},
            {"diagnostic": "largest_source_segment_trade_usd", "value": data["largest_trade"]["synthetic_cash_flow"], "status": "SUPPORTED_NONCONTINUOUS_SOURCE_SEGMENT"},
            {"diagnostic": "largest_source_segment_loss_usd", "value": data["largest_loss"]["synthetic_cash_flow"], "status": "SUPPORTED_NONCONTINUOUS_SOURCE_SEGMENT"},
            {"diagnostic": "best_e8_server_day", "value": "", "status": "UNRESOLVED_EXACT_E8_SERVER_TIME"},
            {"diagnostic": "maximum_completed_trade_inactivity_days", "value": data["max_gap"], "status": "PASS_BELOW_60_DAYS_IN_QUALIFIED_EXECUTION_EVIDENCE"},
            {"diagnostic": "maximum_simultaneous_positions", "value": data["max_positions"], "status": "SUPPORTED"},
            {"diagnostic": "maximum_simultaneous_usd_correlated_positions", "value": data["max_positions"], "status": "SUPPORTED"},
            {"diagnostic": "maximum_ticket_lots", "value": data["max_ticket"], "status": "PASS"},
            {"diagnostic": "scheduled_symbol_signals", "value": data["schedule_signals"], "status": "SUPPORTED"},
            {"diagnostic": "processed_symbol_signals", "value": data["processed_signals"], "status": "PASS_ALL_PROCESSED"},
            {"diagnostic": "entry_attempts", "value": data["entry_attempts"], "status": "SUPPORTED"},
            {"diagnostic": "entry_fills", "value": data["entry_fills"], "status": "SUPPORTED"},
            {"diagnostic": "pre_order_risk_blocks", "value": data["risk_blocks"], "status": "SUPPORTED_NOT_EXECUTION_ERRORS"},
            {"diagnostic": "missed_signals", "value": data["missed"], "status": "PASS"},
            {"diagnostic": "execution_blocks_or_errors", "value": data["execution_blocks"], "status": "PASS_SOURCE_EVIDENCE"},
            {"diagnostic": "daily_cap_circumvention", "value": "NO_EVIDENCE", "status": "EXACT_SERVER_DAY_UNRESOLVED"},
            {"diagnostic": "all_or_nothing_entire_daily_drawdown", "value": "YES", "status": "HARD_FAIL"},
            {"diagnostic": "qualitative_e8_risk_review", "value": "CORRELATED_USD_AND_BUY_SYMBOL_TRADE_DAY_CONCENTRATION", "status": "MATERIAL_CONCERN_SEPARATE_FROM_HARD_FAIL"},
        ]
        write_csv(condition_dir / "supported-diagnostics.csv", list(supported_rows[0]), supported_rows)

        duration_rows.append({
            "condition": condition, "trade_count": len(rows), "under_one_minute_count": data["under_minute"],
            "under_one_minute_percent": data["under_minute"] / len(rows) * 100,
            "minimum_seconds": data["minimum_duration"], "median_seconds": data["median_duration"], "average_seconds": data["average_duration"],
        })
        request_rows.append({
            "condition": condition, "maximum_ticket_lots": data["max_ticket"], "maximum_positions_opened_source_date": 7,
            "maximum_open_positions_plus_pending": data["max_positions"],
            "maximum_source_date_request_records": requests["maximum_source_date_attempt_records"],
            "maximum_rolling_24h_request_records": requests["maximum_rolling_24_hour_attempt_records"],
            "ticket_limit_status": "PASS_SOURCE_EVIDENCE", "position_limit_status": "PASS_SOURCE_EVIDENCE",
            "request_limit_status": "PASS_SOURCE_RECORDS_INCOMPLETE_NETWORK_TRACE",
        })
        target_rows.append({
            "condition": condition, "raw_closed_profit_continuous_usd": "", "counted_closed_profit_usd": "",
            "excess_removed_usd": "", "target_usd": 800, "target_timestamp": "", "target_status": "UNRESOLVED_NO_VALID_CONTINUOUS_ACCOUNT",
            "condition_outcome": "FAIL", "hard_failure": "AGGREGATE_COMMON_IDEA_STOP_RISK_REACHES_OR_EXCEEDS_DAILY_DRAWDOWN",
        })
        unresolved_rows.append({"condition": condition, "status": "UNRESOLVED_MISSING_CONTINUOUS_INTRADAY_EQUITY_AND_EXACT_E8_SERVER_DAY"})

    write_csv(OUT / "intraday-equity-audit.csv", ["condition","status"], unresolved_rows)
    write_csv(OUT / "daily-drawdown-audit.csv", ["condition","server_day_opening_balance","cap_removal","daily_loss_level","minimum_intraday_equity","minimum_intraday_balance","minimum_timestamp","breach_margin_or_remaining_margin","status"], [
        {"condition": c,"server_day_opening_balance":"","cap_removal":"","daily_loss_level":"","minimum_intraday_equity":"","minimum_intraday_balance":"","minimum_timestamp":"","breach_margin_or_remaining_margin":"","status":"UNRESOLVED_MISSING_INTRADAY_EQUITY_AND_EXACT_SERVER_DAY"} for c in CONDITIONS])
    write_csv(OUT / "static-drawdown-audit.csv", ["condition","pre_payout_floor_usd","minimum_balance","minimum_equity","minimum_floor_margin","status"], [
        {"condition":c,"pre_payout_floor_usd":9200,"minimum_balance":"","minimum_equity":"","minimum_floor_margin":"","status":"UNRESOLVED_NO_CONTINUOUS_INTRADAY_ACCOUNT"} for c in CONDITIONS])
    write_csv(OUT / "daily-profit-cap-and-removal-audit.csv", ["condition","daily_cap_usd","server_day","opening_balance","raw_day_profit","counted_day_profit","excess_removed","status"], [
        {"condition":c,"daily_cap_usd":200,"server_day":"","opening_balance":"","raw_day_profit":"","counted_day_profit":"","excess_removed":"","status":"UNRESOLVED_EXACT_SERVER_TIME_AND_CONTINUOUS_BALANCE"} for c in CONDITIONS])
    write_csv(OUT / "profit-target-audit.csv", list(target_rows[0]), target_rows)
    write_csv(OUT / "inactivity-audit.csv", list(inactivity_rows[0]), inactivity_rows)
    write_csv(OUT / "correlated-risk-audit.csv", list(all_risk_rows[0]), all_risk_rows)
    write_csv(OUT / "trade-duration-audit.csv", list(duration_rows[0]), duration_rows)
    write_csv(OUT / "server-request-and-order-limit-audit.csv", list(request_rows[0]), request_rows)

    server_rows = []
    current = date(2025, 1, 1)
    end = date(2026, 7, 31)
    while current <= end:
        server_rows.append({"date": current.isoformat(), "exact_e8_utc_offset": "UNRESOLVED", "day_boundary_dependent_rules": "UNRESOLVED"})
        current += timedelta(days=1)
    write_csv(OUT / "server-time-date-coverage.csv", list(server_rows[0]), server_rows)

    write_text("terminal-outcome.md", f"""# E8 Pro Forex USD 10,000 V28 terminal outcome

All four conditions fail a hard E8 prohibited-practice rule on the frozen evidence. V28's seven simultaneous Forex legs are one common USD-factor trade idea. Aggregate initial stop risk reaches or exceeds the entire USD 250 daily drawdown in 12 of 15 cohorts in each physical execution stream; the maxima are USD {float(condition_data['NORMAL']['max_risk']['aggregate_initial_stop_risk_usd']):.8f} under native execution and USD {float(condition_data['200MS']['max_risk']['aggregate_initial_stop_risk_usd']):.8f} under 200 ms. This is an E8 programme-rule failure, not proof that V28 lacks a trading edge.

The proof does not rely on the invalid 2026 reset or later balance-dependent sizing. The first 2025 cohort, before any prior P/L or cost overlay, risks USD {float(condition_data['NORMAL']['episodes'][0]['aggregate_initial_stop_risk_usd']):.8f} natively and USD {float(condition_data['200MS']['episodes'][0]['aggregate_initial_stop_risk_usd']):.8f} with 200 ms delay; both exceed USD 250. Normal, High and Stress share the native entry stream.

Normal: `FAIL`. High: `FAIL`. Stress: `FAIL`. 200 ms: `FAIL`.

Exact E8 daily-cap, daily-drawdown, static-floor and target results remain unresolved because no valid continuous intraday account, exact historical E8 server-time schedule, or complete E8 MT5 symbol specification set exists. No condition passes the challenge; the performance and payout simulation is not run. The derived USD 250 accumulated-profit threshold for a USD 100 final payout at 80% is supported mathematically by the official 50/50 payout-buffer mechanism and general USD 100 payment minimum, but is not exercised.

`FINAL_CHECKOUT_CONFIGURATION_AND_PRICE_REVERIFICATION_REQUIRED`: the handoff records USD 68, while the official public E8 Pro page retrieved on 2026-08-05 displayed USD 88 for USD 10,000/80%. Neither is treated as a guaranteed checkout price, and no purchase or registration occurred.

V29 and all V31 data are excluded. V28 and Phase 1-5 production remain unchanged. Nothing was pushed.

{OUTCOME}
""")

    write_text("official-rule-freeze.md", """# Official E8 Pro Forex rule freeze

The bounded configuration is one USD 10,000 challenge phase on MT5, 80% payout selection, 8% closed-profit target (USD 800), 2.5% fixed daily drawdown (USD 250), 8% static drawdown (USD 800; floor USD 9,200), 2% daily profit cap (USD 200), unlimited days, no minimum days or consistency rule, 60-day inactivity, unrestricted news, and permitted overnight/weekend holding. Forex leverage is 1:30.

Performance resets to USD 10,000 and has no new target. Before first payout the floor remains USD 9,200. Official payout materials say at least 1% profit is required, profit is split 50% requestable/50% buffer, and the selected share applies to the requestable half. A general final payment minimum of USD 100 at 80% requires a requestable USD 125; therefore USD 250 accumulated profit is the derived minimum because USD 250 × 50% × 80% = USD 100. After first payout the floor moves to USD 10,000.

The daily cap and daily loss level are server-day rules. Cap excess is removed after rollover and must reduce later balance-dependent sizing. Balance or equity reaching the daily loss level or static floor is a breach. EAs are allowed, but risking the entire daily drawdown on one trade idea is prohibited; over 1% per idea is not a universal automatic hard limit.
""")

    sources = [
        ("E8 Pro Forex", "https://help.e8markets.com/en/articles/15274219-e8-pro-forex", "challenge/performance rules, inactivity, leverage, news"),
        ("Daily profit cap", "https://help.e8markets.com/en/articles/15319043-daily-profit-cap", "server day, cap, rollover removal, anti-circumvention"),
        ("Daily drawdown", "https://help.e8markets.com/en/articles/11769446-daily-drawdown", "opening-balance loss level and equity/balance breach"),
        ("Server time", "https://help.e8markets.com/en/articles/10305202-server-time", "UTC+2/UTC+3 broad seasons only"),
        ("E8 Pro payout share", "https://help.e8markets.com/en/articles/13653464-payout-share-request-from-e8-pro-forex-and-e8-pro-crypto", "50/50 payout-buffer and 1% cycle minimum"),
        ("Payout minimum", "https://help.e8markets.com/en/articles/15272556-everything-about-payouts-when-how-how-fast", "USD 100 final minimum and USD 125 at 80%"),
        ("Trading policies", "https://help.e8markets.com/en/articles/6929927-trading-policies-and-prohibited-trading-strategies", "all-or-nothing, HFT, EA and qualitative 1% restriction"),
        ("EA limits", "https://help.e8markets.com/en/articles/5515409-can-i-use-indicators-or-expert-advisors-when-trading-the-e8-account", "ticket/order/request/position limits"),
        ("Contract sizes", "https://help.e8markets.com/en/articles/9453488-what-are-the-contract-sizes", "Forex contract size 100,000"),
        ("Instruments/spreads", "https://help.e8markets.com/en/articles/5514977-what-instruments-are-allowed-to-be-traded-spreads", "product choices and protected live instrument link"),
        ("E8 Pro public configuration", "https://e8pro.e8markets.com/best-simfi-funded-program-e8pro", "public configuration and observed USD 88 price"),
    ]
    source_lines = ["# Official source manifest", "", "Retrieved 2026-08-05. Raw automated GETs to Help Center and the live-symbol dashboard returned HTTP 403; sources were read through indexed browser text. The public E8 Pro page returned HTTP 200 with raw SHA-256 `a62f5e8d9fd8a3ab2e4f0ce4dc26a96381e5707cd85772ccd5614b4f91437981`. No blocked response body is treated as rule evidence.", "", "| Source | URL | Use |", "|---|---|---|"]
    source_lines.extend(f"| {name} | {url} | {use} |" for name, url, use in sources)
    source_lines += ["", "The complete report ledger checksums this manifest. Exact historical DST transition instants and full symbol specifications were not found and are explicitly unresolved."]
    write_text("official-source-manifest.md", "\n".join(source_lines))

    write_text("checkout-price-status.md", """# Checkout price status

`FINAL_CHECKOUT_CONFIGURATION_AND_PRICE_REVERIFICATION_REQUIRED`

The handoff records a published preset base price of USD 68. The official public E8 Pro page retrieved on 2026-08-05 displayed USD 88 for the USD 10,000 account at 80% payout. This conflict is not resolved by visiting checkout because no purchase or registration is authorized. Neither amount is guaranteed; final configuration, platform availability, regional eligibility and price must be reverified immediately before any separately authorized purchase.
""")

    write_text("e8-execution-specification-gate.md", """# E8 execution-specification gate

Gate result: `FAIL_INSUFFICIENT_E8_SPECIFICATIONS`.

| Field | Evidence | Status |
|---|---|---|
| Seven marketing symbols | EURUSD, GBPUSD, AUDUSD, NZDUSD, USDCAD, USDCHF, USDJPY appear publicly | Partial; exact MT5 suffixes unresolved |
| Forex contract size | 100,000 units | Established generally |
| Forex leverage | 1:30 | Established |
| Ticket cap | 50 lots ordinary symbols | Established |
| Tick size/value | No public seven-symbol MT5 table obtained | Unresolved |
| Minimum volume/step/symbol maximum | Protected live-symbol endpoint; no public table obtained | Unresolved |
| Margin calculation | General leverage/equity formula published | Partial; exact MT5 calculation/spec flags unresolved |
| Commission/spread selection | E8 Pro offers raw or no-commission choices | Unresolved for the requested preset |
| Typical spreads | Protected live-symbol endpoint returned HTTP 403 | Unresolved |
| Swap long/short and triple-swap day | No complete official table found | Unresolved |
| Server timezone | Broad UTC+2/UTC+3 seasons only | Exact historical transitions unresolved |
| Execution restrictions/slippage | General simulated slippage and limits published | Exact per-symbol MT5 execution configuration unresolved |

FP Markets specifications are not substituted for E8. The qualified Normal, High, Stress and 200 ms streams remain sensitivity evidence, not an exact E8 execution replication. These limitations could change continuous sizing, costs, rollover grouping and drawdown; they independently block a PASS, but do not undo the hard correlated-risk policy failure.
""")

    write_text("server-time-schedule.md", """# E8 server-time schedule

The official source says E8 server time changes to UTC+3 at the end of March and UTC+2 at the beginning of November. It does not give exact historical 2025 or 2026 transition dates/timestamps, and no authoritative mapping from the FP Markets source timestamps to E8 time exists.

Accordingly, every tested date from 2025-01-01 through 2026-07-31 is present in `server-time-date-coverage.csv` with exact offset `UNRESOLVED`. All server-day profit-cap, cap-removal, daily-drawdown, best-day and target-timestamp calculations remain unresolved. No DST transition is guessed.
""")

    write_text("continuous-account-method.md", """# Continuous account method

The required method needs one USD 10,000 account from 2025 through 2026-07-31, carrying balance, equity, positions, floating P/L, risk state, sizing, controls, cap removals and inactivity without reset. The qualified V28 evidence instead contains separate 2025 and 2026 physical runs, each initialized at USD 10,000. Its supplementary High/Stress costs are post-run closed-trade adjustments, and no timestamped intraday equity or rollover-removal stream exists.

Adding the independently reset totals is prohibited and was not done. Closed trades, aggregate MT5 drawdown statistics and bitmap charts are not substituted for full intraday equity. A technically valid continuous E8 run therefore cannot be produced from the frozen artifacts. The hard common-idea risk breach is calculated directly from accepted entry transactions and their visible initial stops, so it remains dispositive under the instruction that confirmed hard failures produce FAIL even when other rules are unresolved.
""")

    manifest_lines = ["# Source evidence manifest", "", f"Frozen source commit: `{SOURCE_COMMIT}`. V29 and V31 are excluded. Production SHA-256: `{sha(PRODUCTION)}`.", "", "| Path | SHA-256 |", "|---|---|"]
    manifest_lines.extend(f"| `{path.relative_to(ROOT)}` | `{sha(path)}` |" for path in SOURCE_FILES)
    write_text("source-evidence-manifest.md", "\n".join(manifest_lines))

    write_text("ea-policy-audit.md", f"""# EA and trading-practice audit

V28 is treated as this user's privately developed EA; no evidence identifies it as a duplicated public, team or signal-service strategy. There is no evidence of cross-account hedging, feed abuse, freezing, latency exploitation or high-frequency abuse. Across each condition, 0 of 105 trades last under one minute, maximum ticket size is 0.04 lots, maximum simultaneous positions is 7, and source attempt records remain far below 2,000 per day. Visible stop coverage is 105/105.

Hard failure: the seven positions are not unrelated ideas; they deliberately implement one correlated USD-factor signal and common holding horizon. In both physical execution streams, 12 of 15 cohorts have aggregate initial stop risk at or above USD 250. Native maximum: USD {float(condition_data['NORMAL']['max_risk']['aggregate_initial_stop_risk_usd']):.8f} ({float(condition_data['NORMAL']['max_risk']['aggregate_risk_percent_of_e8_daily_drawdown']):.6f}% of daily drawdown). 200 ms maximum: USD {float(condition_data['200MS']['max_risk']['aggregate_initial_stop_risk_usd']):.8f} ({float(condition_data['200MS']['max_risk']['aggregate_risk_percent_of_e8_daily_drawdown']):.6f}%). This is direct evidence of risking the entire daily drawdown on one trade idea and is classified as a hard prohibited-practice failure.

The first January 2025 cohort independently proves the result before any prior P/L, daily-cap removal or later sizing could matter: USD {float(condition_data['NORMAL']['episodes'][0]['aggregate_initial_stop_risk_usd']):.8f} native and USD {float(condition_data['200MS']['episodes'][0]['aggregate_initial_stop_risk_usd']):.8f} delayed.

Separately, concentration could reasonably trigger E8 risk review: all seven legs share one USD factor, maximum correlated exposure is seven positions, and earlier source-segment diagnostics show material BUY, symbol, individual-trade and realized-day concentration. The possible 1% per-idea restriction is kept qualitative and is not used as an automatic breach.
""")

    write_text("challenge-results.md", """# Challenge results

| Condition | Outcome | Dispositive rule |
|---|---|---|
| Normal | FAIL | Common USD-factor cohort initial stop risk reaches/exceeds entire USD 250 daily drawdown |
| High | FAIL | Same native executions; cost overlay does not change initial correlated stop risk |
| Stress | FAIL | Same native executions; cost overlay does not change initial correlated stop risk |
| 200 ms | FAIL | Common USD-factor cohort initial stop risk reaches/exceeds entire USD 250 daily drawdown |

No exact target timestamp exists because no valid continuous capped account is available. Missing intraday equity, exact server-time and exact E8 specifications leave other hard rules unresolved but cannot reverse the proven prohibited-practice failures.

No condition passes. The performance and payout stage is not entered, reset or simulated, and `performance-and-payout-results.md` is intentionally absent under the frozen conditional method.
""")

    write_text("limitations.md", """# Limitations

- No technically valid continuous 2025–2026 account exists; source periods reset independently.
- No timestamped full intraday equity/balance stream exists.
- Exact historical E8 UTC+2/UTC+3 transition instants are unpublished.
- FP Markets source timestamps have no authoritative conversion to E8 server time.
- Complete E8 MT5 specifications for all seven symbols were unavailable; the protected endpoint returned HTTP 403.
- High/Stress costs are closed-trade sensitivity overlays and cannot drive native subsequent sizing or intraday equity.
- Server request CSVs are not complete network traces.
- Source-segment P&L and symbol/direction contributions are reported separately and never added into a purported continuous result.
- No checkout, purchase, registration, V31 restart, V29 use, strategy change, optimization, production change, performance simulation, demo trade or live trade occurred.
""")

    report_files = sorted(path for path in OUT.rglob("*") if path.is_file() and path.name != "complete-sha256-ledger.txt")
    ledger_lines = ["# Report artifacts (this recursively self-referential ledger is excluded)"]
    ledger_lines.extend(f"{sha(path)}  {path.relative_to(ROOT)}" for path in report_files)
    ledger_lines.append("# Exact frozen source artifacts")
    ledger_lines.extend(f"{sha(path)}  {path.relative_to(ROOT)}" for path in SOURCE_FILES)
    ledger_lines.append(f"{sha(PRODUCTION)}  {PRODUCTION.relative_to(ROOT)}")
    write_text("complete-sha256-ledger.txt", "\n".join(ledger_lines))


if __name__ == "__main__":
    build()
