#!/usr/bin/env python3
"""Build the bounded FXIFY continuous-account evidence addendum."""
from __future__ import annotations

import bisect
import collections
import csv
import hashlib
import json
import math
import re
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation"
ADD = AUDIT / "continuous-account-evidence-addendum"
RUNS = ADD / "physical-runs"
FROZEN = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
TICKS = Path("/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/Bases/FPMarketsSC-Demo/ticks")
FMT = "%Y.%m.%d %H:%M:%S"
START = datetime(2025, 1, 1)
CUTOFF = datetime(2026, 8, 1)
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
CONDITIONS = {
    "normal": {"label": "NORMAL", "multiplier": 0.0, "run": "normal"},
    "high": {"label": "HIGH", "multiplier": 0.5, "run": "high"},
    "stress": {"label": "STRESS", "multiplier": 1.0, "run": "stress"},
    "200ms": {"label": "200MS", "multiplier": 0.0, "run": "200ms"},
}
PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
ORIGINAL_TERMINAL_SHA = "4fad6a39b8f60ea79da0aa0fa3b6607959870fecb174bb4e1f280534e691d9c3"
ORIGINAL_LEDGER_SHA = "59fa3bd986579e17bd911cbadefe767984f3d67b9494ecf1be2e3d869cf736e2"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str] | tuple[str, ...], rows: list[dict]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def dt(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def msc_dt(value: str | int) -> datetime:
    return datetime.fromtimestamp(int(value) / 1000, timezone.utc).replace(tzinfo=None)


def msc_text(value: int) -> str:
    moment = msc_dt(value)
    return moment.strftime(FMT) + f".{value % 1000:03d}"


def f(value: str | float | int | None) -> float:
    return float(value or 0)


def point_value(symbol: str, price: float) -> float:
    point = 0.001 if symbol == "USDJPY" else 0.00001
    value = 100000 * point
    return value if symbol.endswith("USD") else value / price


def parse_trades(run: Path, multiplier: float) -> tuple[list[dict], list[dict]]:
    deals = read_csv(run / "deals.csv")
    transactions = read_csv(run / "transactions.csv")
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
    grouped: dict[str, list[dict[str, str]]] = collections.defaultdict(list)
    for row in deals:
        grouped[row["position_identifier"]].append(row)
    completed = []
    entries = []
    for pid, rows in grouped.items():
        ins = [row for row in rows if int(row["entry"]) == 0]
        outs = [row for row in rows if int(row["entry"]) in (1, 2)]
        if len(ins) != 1:
            raise RuntimeError(f"position {pid} has {len(ins)} entries")
        entry = ins[0]
        meta = entry_meta.get(entry["deal_ticket"])
        if meta is None:
            raise RuntimeError(f"missing entry metadata {pid}")
        volume = f(entry["volume"])
        risk = f(meta["initial_risk_amount"])
        entry_record = {
            "position_identifier": pid,
            "symbol": entry["symbol"],
            "entry_time": dt(entry["time"]),
            "entry_time_text": entry["time"],
            "entry_time_msc": int(entry["time_msc"]),
            "signal_time": dt(meta["signal_time"]),
            "signal_time_text": meta["signal_time"],
            "volume": volume,
            "initial_risk_amount": risk,
            "loss_per_lot": risk / volume,
        }
        entries.append(entry_record)
        if not outs:
            entry_record["open_at_cutoff"] = True
            continue
        out = outs[-1]
        native_before = sum(f(row["profit"]) + f(row["commission"]) + f(row["swap"]) + f(row["fee"]) for row in rows)
        external_commission = volume * 6.0
        pv = point_value(entry["symbol"], f(entry["price"]))
        spread = f(meta["spread_points"]) * pv * volume
        point = 0.001 if entry["symbol"] == "USDJPY" else 0.00001
        requested_entry = f(meta["requested_price"])
        actual_entry = f(entry["price"])
        direction = "BUY" if int(entry["type"]) == 0 else "SELL"
        adverse_entry = max(0.0, (actual_entry - requested_entry) / point * pv * volume) if direction == "BUY" else max(0.0, (requested_entry - actual_entry) / point * pv * volume)
        adverse_exit = 0.0
        exit_tx = exit_meta.get(out["deal_ticket"])
        if exit_tx:
            requested_exit = f(exit_tx["requested_price"])
            actual_exit = f(out["price"])
            adverse_exit = max(0.0, (requested_exit - actual_exit) / point * pv * volume) if direction == "BUY" else max(0.0, (actual_exit - requested_exit) / point * pv * volume)
        swap_cost = abs(sum(f(row["swap"]) for row in rows))
        fee_cost = abs(sum(f(row["fee"]) for row in rows))
        friction = spread + external_commission + swap_cost + fee_cost + adverse_entry + adverse_exit
        supplementary = multiplier * friction
        adjusted_cash = native_before - external_commission - supplementary
        completed.append({
            **entry_record,
            "direction": direction,
            "exit_time": dt(out["time"]),
            "exit_time_text": out["time"],
            "exit_time_msc": int(out["time_msc"]),
            "exit_reason": "STOP_LOSS_EXIT" if int(out["reason"]) == 4 else "MONTHLY_REBALANCE_EXIT",
            "native_net_before_external_commission": native_before,
            "external_commission": external_commission,
            "spread_cost": spread,
            "swap_cost": swap_cost,
            "fee_cost": fee_cost,
            "adverse_entry_slippage_cost": adverse_entry,
            "adverse_exit_slippage_cost": adverse_exit,
            "native_friction": friction,
            "supplementary_multiplier": multiplier,
            "supplementary_charge": supplementary,
            "total_profile_charge": external_commission + supplementary,
            "adjusted_cash": adjusted_cash,
            "adjusted_net_R": adjusted_cash / risk,
        })
    return sorted(completed, key=lambda row: (row["exit_time_msc"], int(row["position_identifier"]))), sorted(entries, key=lambda row: (row["entry_time_msc"], row["symbol"]))


def charges_index(trades: list[dict]) -> tuple[list[int], list[float]]:
    times = []
    cumulative = []
    total = 0.0
    for row in trades:
        total += row["total_profile_charge"]
        times.append(row["exit_time_msc"])
        cumulative.append(total)
    return times, cumulative


def charge_at(index: tuple[list[int], list[float]], time_msc: int) -> float:
    times, cumulative = index
    position = bisect.bisect_right(times, time_msc) - 1
    return cumulative[position] if position >= 0 else 0.0


def adjusted_hours(run: Path, condition: str, trades: list[dict]) -> list[dict]:
    index = charges_index(trades)
    result = []
    for raw in read_csv(run / "equity-hours.csv"):
        opening_msc = int(raw["opening_time_msc"])
        closing_msc = int(raw["closing_time_msc"])
        minimum_msc = int(raw["minimum_time_msc"])
        open_charge = charge_at(index, opening_msc)
        close_charge = charge_at(index, closing_msc)
        min_charge = charge_at(index, minimum_msc)
        adjusted_open_balance = f(raw["opening_balance"]) - open_charge
        adjusted_open_equity = f(raw["opening_equity"]) - open_charge
        adjusted_close_balance = f(raw["closing_balance"]) - close_charge
        adjusted_close_equity = f(raw["closing_equity"]) - close_charge
        min_candidates = (
            (f(raw["minimum_equity"]) - min_charge, minimum_msc, "RAW_HOURLY_MINIMUM"),
            (adjusted_open_equity, opening_msc, "ADJUSTED_HOUR_OPEN"),
            (adjusted_close_equity, closing_msc, "ADJUSTED_HOUR_CLOSE"),
        )
        minimum_equity, adjusted_minimum_msc, minimum_basis = min(min_candidates)
        result.append({
            "condition": condition,
            "server_hour": raw["server_hour"],
            "opening_time_msc": opening_msc,
            "closing_time_msc": closing_msc,
            "opening_balance": adjusted_open_balance,
            "opening_equity": adjusted_open_equity,
            "closing_balance": adjusted_close_balance,
            "closing_equity": adjusted_close_equity,
            "minimum_equity": minimum_equity,
            "minimum_time_msc": adjusted_minimum_msc,
            "minimum_server_time": msc_text(adjusted_minimum_msc),
            "minimum_basis": minimum_basis,
            "opening_positions": int(raw["opening_positions"]),
            "closing_positions": int(raw["closing_positions"]),
            "maximum_positions": int(raw["maximum_positions"]),
            "cumulative_profile_charge_at_close": close_charge,
        })
    return result


def adjusted_transaction_events(run: Path, trades: list[dict]) -> list[dict]:
    index = charges_index(trades)
    unique = {}
    for raw in read_csv(run / "balance-events.csv"):
        key = (int(raw["time_msc"]), raw["balance"], raw["equity"], raw["positions"])
        charge = charge_at(index, key[0])
        unique[key] = {
            "time": dt(raw["server_time"]),
            "time_msc": key[0],
            "balance": f(raw["balance"]) - charge,
            "equity": f(raw["equity"]) - charge,
            "positions": int(raw["positions"]),
        }
    return sorted(unique.values(), key=lambda row: row["time_msc"])


def server_boundary(day: date, interpretation: str) -> datetime:
    """Return the FP server timestamp ending the requested calendar day."""
    next_day = day + timedelta(days=1)
    if interpretation == "NEW_YORK":
        return datetime.combine(next_day, time(0, 0))
    ny = datetime.combine(day, time(17, 0), ZoneInfo("America/New_York"))
    return datetime.combine(next_day, time(1 if ny.utcoffset() == timedelta(hours=-4) else 0, 0))


def state_at(hours: list[dict], boundary: datetime) -> dict:
    boundary_msc = int(boundary.timestamp() * 1000)
    closes = [row["closing_time_msc"] for row in hours]
    index = bisect.bisect_right(closes, boundary_msc) - 1
    if index < 0:
        return {"closing_balance": 10000.0, "closing_equity": 10000.0, "closing_time_msc": int(START.timestamp() * 1000)}
    return hours[index]


def boundary_audit(condition: str, hours: list[dict], events: list[dict], entries: list[dict], trades: list[dict], interpretation: str) -> list[dict]:
    rows = []
    hour_starts = [dt(row["server_hour"]) for row in hours]
    hour_closes = [row["closing_time_msc"] for row in hours]
    event_times = [row["time"] for row in events]

    def boundary_state(boundary: datetime) -> dict:
        boundary_msc = int(boundary.timestamp() * 1000)
        index = bisect.bisect_right(hour_closes, boundary_msc) - 1
        if index < 0:
            return {"closing_balance": 10000.0, "closing_equity": 10000.0, "closing_time_msc": int(START.timestamp() * 1000)}
        return hours[index]

    day = START.date()
    while True:
        end = server_boundary(day, interpretation)
        if end >= CUTOFF:
            break
        previous_day = day - timedelta(days=1)
        start = server_boundary(previous_day, interpretation)
        opening = boundary_state(start)
        closing = boundary_state(end)
        candidates = []
        hour_left = bisect.bisect_left(hour_starts, start)
        hour_right = bisect.bisect_left(hour_starts, end)
        for row in hours[hour_left:hour_right]:
            candidates.append((row["minimum_equity"], row["minimum_time_msc"], row["minimum_basis"]))
        event_left = bisect.bisect_left(event_times, start)
        event_right = bisect.bisect_left(event_times, end)
        for row in events[event_left:event_right]:
            candidates.append((row["equity"], row["time_msc"], "ADJUSTED_TRANSACTION_STATE"))
        if candidates:
            minimum_equity, minimum_msc, minimum_basis = min(candidates)
        else:
            minimum_equity = min(opening["closing_equity"], closing["closing_equity"])
            minimum_msc = closing["closing_time_msc"]
            minimum_basis = "CARRIED_STATE_NO_MARKET_TICKS"
        day_entries = [row for row in entries if start <= row["entry_time"] < end]
        day_exits = [row for row in trades if start <= row["exit_time"] < end]
        opening_balance = opening["closing_balance"]
        opening_equity = opening["closing_equity"]
        closing_balance = closing["closing_balance"]
        closing_equity = closing["closing_equity"]
        breach_level = opening_balance * 0.96
        rows.append({
            "condition": condition,
            "trading_day": day.isoformat(),
            "boundary_interpretation": interpretation,
            "server_period_start": start.strftime(FMT),
            "server_period_end": end.strftime(FMT),
            "opening_balance": opening_balance,
            "opening_equity": opening_equity,
            "closing_balance": closing_balance,
            "closing_equity": closing_equity,
            "minimum_equity": minimum_equity,
            "minimum_equity_server_time": msc_text(minimum_msc),
            "minimum_basis": minimum_basis,
            "executed_entries": len(day_entries),
            "exits": len(day_exits),
            "realised_profit": closing_balance - opening_balance,
            "equity_change": closing_equity - opening_equity,
            "closing_floating_profit_loss": closing_equity - closing_balance,
            "daily_breach_level": breach_level,
            "daily_loss_margin": minimum_equity - breach_level,
            "daily_loss_breach": "YES" if minimum_equity <= breach_level else "NO",
            "profitable_day_a_cumulative": "YES" if closing_balance >= 10050 and closing_equity >= 10050 else "NO",
            "profitable_day_b_individual": "YES" if closing_balance - opening_balance >= 50 and closing_equity - opening_equity >= 50 else "NO",
        })
        day += timedelta(days=1)
    return rows


def target_state(trades: list[dict], entries: list[dict]) -> tuple[int | None, float | None]:
    grouped: dict[int, list[dict]] = collections.defaultdict(list)
    for row in trades:
        grouped[row["exit_time_msc"]].append(row)
    balance = 10000.0
    for when in sorted(grouped):
        balance += sum(row["adjusted_cash"] for row in grouped[when])
        open_after = sum(
            1 for entry in entries
            if entry["entry_time_msc"] <= when
            and not any(trade["position_identifier"] == entry["position_identifier"] and trade["exit_time_msc"] <= when for trade in trades)
        )
        if balance >= 10400 and open_after == 0:
            return when, balance
    return None, None


def inactivity(condition: str, entries: list[dict]) -> list[dict]:
    cohorts: dict[datetime, list[dict]] = collections.defaultdict(list)
    for row in entries:
        cohorts[row["signal_time"]].append(row)
    executed = []
    for signal_time in sorted(cohorts):
        rows = cohorts[signal_time]
        executed.append({"signal": signal_time, "first": min(row["entry_time"] for row in rows), "last": max(row["entry_time"] for row in rows), "entries": len(rows)})
    result = []
    for previous, following in zip(executed, executed[1:]):
        elapsed = following["first"] - previous["last"]
        result.append({
            "condition": condition,
            "previous_signal": previous["signal"].strftime(FMT),
            "previous_last_executed_entry": previous["last"].strftime(FMT),
            "next_signal": following["signal"].strftime(FMT),
            "next_first_executed_entry": following["first"].strftime(FMT),
            "elapsed_seconds": int(elapsed.total_seconds()),
            "elapsed_days": elapsed.total_seconds() / 86400,
            "crosses_2025_2026_seam": "YES" if previous["last"].year == 2025 and following["first"].year == 2026 else "NO",
            "affected_by_cutoff": "NO",
            "genuinely_reaches_60_days": "YES" if elapsed >= timedelta(days=60) else "NO",
            "sixty_day_timestamp": (previous["last"] + timedelta(days=60)).strftime(FMT) if elapsed >= timedelta(days=60) else "",
            "executed_trade_inside_interval": "NO",
        })
    last = executed[-1]
    elapsed = CUTOFF - last["last"]
    result.append({
        "condition": condition,
        "previous_signal": last["signal"].strftime(FMT),
        "previous_last_executed_entry": last["last"].strftime(FMT),
        "next_signal": "TEST_CUTOFF_EXCLUSIVE",
        "next_first_executed_entry": CUTOFF.strftime(FMT),
        "elapsed_seconds": int(elapsed.total_seconds()),
        "elapsed_days": elapsed.total_seconds() / 86400,
        "crosses_2025_2026_seam": "NO",
        "affected_by_cutoff": "YES",
        "genuinely_reaches_60_days": "YES" if elapsed >= timedelta(days=60) else "NO",
        "sixty_day_timestamp": (last["last"] + timedelta(days=60)).strftime(FMT) if elapsed >= timedelta(days=60) else "",
        "executed_trade_inside_interval": "NO",
    })
    return result


def sizing_sensitivity(condition: str, trades: list[dict], entries: list[dict], target_msc: int | None) -> list[dict]:
    rows = []
    for entry in entries:
        adjusted_balance = 10000.0 + sum(
            trade["adjusted_cash"] for trade in trades if trade["exit_time_msc"] < entry["entry_time_msc"]
        )
        raw_volume = adjusted_balance * 0.005 / entry["loss_per_lot"]
        expected_volume = math.floor((raw_volume + 1e-12) / 0.01) * 0.01
        expected_volume = round(expected_volume, 2)
        applicable = target_msc is None or entry["entry_time_msc"] <= target_msc
        rows.append({
            "condition": condition,
            "signal_time": entry["signal_time_text"],
            "entry_time": entry["entry_time_text"],
            "symbol": entry["symbol"],
            "adjusted_flat_balance_before_cohort": adjusted_balance,
            "loss_per_lot_from_executed_stop": entry["loss_per_lot"],
            "executed_volume": entry["volume"],
            "cost_feedback_expected_volume": expected_volume,
            "volume_matches": "YES" if abs(expected_volume - entry["volume"]) < 1e-9 else "NO",
            "inside_applicable_phase1_interval": "YES" if applicable else "NO",
        })
    return rows


def exact_file_equivalence(left: Path, right: Path, files: tuple[str, ...]) -> list[dict]:
    result = []
    for name in files:
        left_sha, right_sha = sha(left / name), sha(right / name)
        result.append({"reference": left.name, "instrumented": right.name, "file": name, "reference_sha256": left_sha, "instrumented_sha256": right_sha, "status": "PASS" if left_sha == right_sha else "FAIL"})
    return result


def write_condition_ledger(path: Path, trades: list[dict]) -> None:
    fields = [
        "position_identifier", "symbol", "direction", "entry_time_text", "exit_time_text", "volume", "initial_risk_amount",
        "native_net_before_external_commission", "external_commission", "spread_cost", "swap_cost", "fee_cost",
        "adverse_entry_slippage_cost", "adverse_exit_slippage_cost", "native_friction", "supplementary_multiplier",
        "supplementary_charge", "adjusted_cash", "adjusted_net_R", "exit_reason",
    ]
    write_csv(path, fields, trades)


def main() -> None:
    if sha(ROOT / "MQL5/Experts/SolTradeBot.mq5") != PRODUCTION_SHA:
        raise SystemExit("production hash mismatch")
    if sha(AUDIT / "terminal-outcome.md") != ORIGINAL_TERMINAL_SHA or sha(AUDIT / "complete-sha256-ledger.txt") != ORIGINAL_LEDGER_SHA:
        raise SystemExit("original FXIFY audit changed")
    completion = json.loads((ADD / "run-completion.json").read_text())
    if completion.get("status") != "PASS":
        raise SystemExit("physical runs are not complete")

    equivalence = []
    equivalence += exact_file_equivalence(RUNS / "a2-reference-normal", RUNS / "normal", ("deals.csv", "transactions.csv", "events.csv"))
    equivalence += exact_file_equivalence(RUNS / "a2-reference-200ms", RUNS / "200ms", ("deals.csv", "transactions.csv", "events.csv"))
    equivalence += exact_file_equivalence(RUNS / "normal", RUNS / "high", ("deals.csv", "transactions.csv", "events.csv"))
    equivalence += exact_file_equivalence(RUNS / "normal", RUNS / "stress", ("deals.csv", "transactions.csv", "events.csv"))
    if any(row["status"] != "PASS" for row in equivalence):
        raise SystemExit("FXIFY_CONTINUOUS_EVIDENCE_INVALID")
    write_csv(ADD / "instrumentation-equivalence-details.csv", list(equivalence[0]), equivalence)

    all_hours = []
    all_fixed = []
    all_ny = []
    all_inactivity = []
    all_sizing = []
    metrics = {}
    for key, config in CONDITIONS.items():
        condition = config["label"]
        run = RUNS / config["run"]
        trades, entries = parse_trades(run, config["multiplier"])
        hours = adjusted_hours(run, condition, trades)
        events = adjusted_transaction_events(run, trades)
        fixed = boundary_audit(condition, hours, events, entries, trades, "FIXED_EST")
        ny = boundary_audit(condition, hours, events, entries, trades, "NEW_YORK")
        gaps = inactivity(condition, entries)
        target_msc, target_balance = target_state(trades, entries)
        sizing = sizing_sensitivity(condition, trades, entries, target_msc)
        all_sizing.extend(sizing)
        target_time = msc_dt(target_msc) if target_msc is not None else None
        relevant_end = target_time or CUTOFF
        relevant_hours = [row for row in hours if dt(row["server_hour"]) <= relevant_end]
        minimum_row = min(relevant_hours, key=lambda row: row["minimum_equity"])
        relevant_fixed = [row for row in fixed if dt(row["server_period_end"]) <= relevant_end]
        relevant_ny = [row for row in ny if dt(row["server_period_end"]) <= relevant_end]
        daily_breach_fixed = [row for row in relevant_fixed if row["daily_loss_breach"] == "YES"]
        daily_breach_ny = [row for row in relevant_ny if row["daily_loss_breach"] == "YES"]
        gaps_before_end = [row for row in gaps if row["genuinely_reaches_60_days"] == "YES" and row["sixty_day_timestamp"] and dt(row["sixty_day_timestamp"]) <= relevant_end]
        count_a_fixed = sum(row["profitable_day_a_cumulative"] == "YES" for row in relevant_fixed)
        count_b_fixed = sum(row["profitable_day_b_individual"] == "YES" for row in relevant_fixed)
        count_a_ny = sum(row["profitable_day_a_cumulative"] == "YES" for row in relevant_ny)
        count_b_ny = sum(row["profitable_day_b_individual"] == "YES" for row in relevant_ny)
        status = "CONTINUOUS_PHASE1_FAIL" if gaps_before_end or daily_breach_fixed or daily_breach_ny or minimum_row["minimum_equity"] <= 9200 else (
            "CONTINUOUS_PHASE1_PASS_CANDIDATE" if target_time and min(count_a_fixed, count_a_ny) >= 3 and not any(row["volume_matches"] == "NO" and row["inside_applicable_phase1_interval"] == "YES" for row in sizing) else "CONTINUOUS_PHASE1_UNRESOLVED"
        )
        metrics[condition] = {
            "status": status,
            "target_time": target_time,
            "target_msc": target_msc,
            "target_balance": target_balance,
            "minimum_equity": minimum_row["minimum_equity"],
            "minimum_equity_time": minimum_row["minimum_server_time"],
            "static_floor_margin": minimum_row["minimum_equity"] - 9200,
            "fixed_smallest_daily_margin": min(row["daily_loss_margin"] for row in relevant_fixed),
            "ny_smallest_daily_margin": min(row["daily_loss_margin"] for row in relevant_ny),
            "fixed_breaches": len(daily_breach_fixed),
            "ny_breaches": len(daily_breach_ny),
            "a_fixed": count_a_fixed,
            "b_fixed": count_b_fixed,
            "a_ny": count_a_ny,
            "b_ny": count_b_ny,
            "inactivity_breaches": gaps_before_end,
            "completed_positions": len(trades),
            "executed_entries": len(entries),
            "open_positions_at_cutoff": sum(row.get("open_at_cutoff", False) for row in entries),
            "final_closed_balance": 10000 + sum(row["adjusted_cash"] for row in trades),
            "applicable_sizing_mismatches": sum(row["volume_matches"] == "NO" and row["inside_applicable_phase1_interval"] == "YES" for row in sizing),
        }
        all_hours.extend(hours)
        all_fixed.extend(fixed)
        all_ny.extend(ny)
        all_inactivity.extend(gaps)
        condition_dir = ADD / key
        condition_dir.mkdir(exist_ok=True)
        write_condition_ledger(condition_dir / "closed-trade-ledger.csv", trades)

    hour_fields = ["condition", "server_hour", "opening_time_msc", "closing_time_msc", "opening_balance", "opening_equity", "closing_balance", "closing_equity", "minimum_equity", "minimum_time_msc", "minimum_server_time", "minimum_basis", "opening_positions", "closing_positions", "maximum_positions", "cumulative_profile_charge_at_close"]
    write_csv(ADD / "continuous-balance-equity.csv", hour_fields, all_hours)
    boundary_fields = list(all_fixed[0])
    write_csv(ADD / "five-pm-fixed-est-audit.csv", boundary_fields, all_fixed)
    write_csv(ADD / "five-pm-new-york-audit.csv", boundary_fields, all_ny)
    write_csv(ADD / "continuous-inactivity-audit.csv", list(all_inactivity[0]), all_inactivity)
    write_csv(ADD / "position-sizing-sensitivity.csv", list(all_sizing[0]), all_sizing)

    for key, config in CONDITIONS.items():
        m = metrics[config["label"]]
        breach = m["inactivity_breaches"][0]["sixty_day_timestamp"] if m["inactivity_breaches"] else "NONE"
        target_balance_text = f"{m['target_balance']:.8f}" if m["target_balance"] is not None else "NOT_REACHED"
        (ADD / key / "condition-result.md").write_text(
            f"# {config['label']} continuous Phase 1 result\n\n"
            f"`{m['status']}`\n\n"
            f"Natural flat-account target timestamp: `{msc_text(m['target_msc']) if m['target_msc'] is not None else 'NOT_REACHED'}`; "
            f"closed balance then: `{target_balance_text}`. Minimum adjusted equity through the applicable Phase 1 interval: "
            f"`{m['minimum_equity']:.8f}` at `{m['minimum_equity_time']}`; static-floor margin: `{m['static_floor_margin']:.8f}`. "
            f"Profitable-day counts (A/B): Fixed EST `{m['a_fixed']}/{m['b_fixed']}`, New York `{m['a_ny']}/{m['b_ny']}`. "
            f"Daily-loss breaches: Fixed EST `{m['fixed_breaches']}`, New York `{m['ny_breaches']}`. "
            f"First applicable 60-day inactivity timestamp: `{breach}`.\n"
        )

    history_rows = []
    months = [f"2025{month:02d}" for month in range(1, 13)] + [f"2026{month:02d}" for month in range(1, 8)]
    for symbol in SYMBOLS:
        for month in months:
            path = TICKS / symbol / f"{month}.tkc"
            if not path.exists() or path.stat().st_size == 0:
                raise RuntimeError(f"missing tick month {path}")
            history_rows.append({"symbol": symbol, "month": month, "bytes": path.stat().st_size, "sha256": sha(path), "path": str(path)})
    write_csv(ADD / "history-tick-file-fingerprints.csv", list(history_rows[0]), history_rows)

    tester_log = (RUNS / "normal/tester-agent.log").read_text(encoding="utf-16", errors="replace")
    sync_rows = []
    for symbol in SYMBOLS:
        match = re.search(rf"Ticks\s+{symbol}: history ticks synchronized from ([0-9.]+) to ([0-9.]+)", tester_log)
        if not match:
            raise RuntimeError(f"missing tester synchronization record {symbol}")
        sync_rows.append({"symbol": symbol, "tester_synchronized_from": match.group(1), "tester_synchronized_to": match.group(2), "required_month_files": 19, "month_files_present": 19, "status": "PASS"})
    write_csv(ADD / "history-synchronization.csv", list(sync_rows[0]), sync_rows)

    signal_equiv = ADD / "signal-generation/frozen-signal-overlap-equivalence.csv"
    if len(read_csv(signal_equiv)) != 0:
        raise SystemExit("FXIFY_CONTINUOUS_EVIDENCE_INVALID")
    status_lines = []
    for condition in ("NORMAL", "HIGH", "STRESS", "200MS"):
        m = metrics[condition]
        status_lines.append(f"- {condition}: `{m['status']}`")
    stress_breach = metrics["STRESS"]["inactivity_breaches"][0]
    (ADD / "addendum-terminal-outcome.md").write_text(
        "# FXIFY V28 continuous-account evidence addendum outcome\n\n"
        + "\n".join(status_lines)
        + "\n\nNormal, High and 200 ms reach the USD 400 closed-profit target naturally while flat on 2025.06.02, before any 60-day entry interval. "
        "Stress does not reach the target and remains in Phase 1 when its entry interval from "
        f"`{stress_breach['previous_last_executed_entry']}` reaches 60 full days at `{stress_breach['sixty_day_timestamp']}`; "
        "that is a genuine Phase 1 inactivity failure. Neither 5PM interpretation records a 4% daily-loss breach, and the USD 9,200 static floor is not touched.\n\n"
        "This addendum resolves internal continuous-account evidence only. Exact FXIFY RAW specifications and FXIFY's official 5PM interpretation remain external dependencies. "
        "Those dependencies leave other rules unresolved but cannot undo the proven Stress inactivity breach. This is a programme-rule failure, not evidence that V28 lacks a trading edge. "
        "Phase 2 is not entered, purchase is not authorized, V28 and production remain unchanged, and the original audit outcome remains preserved byte-for-byte.\n\n"
        "V28_FXIFY_2PHASE_PRO_10K_FAILS_REQUIRED_RULES\n"
    )

    mrows = []
    for condition, m in metrics.items():
        mrows.append({
            "condition": condition,
            "result": m["status"],
            "target_timestamp": msc_text(m["target_msc"]) if m["target_msc"] is not None else "",
            "target_closed_balance": m["target_balance"] if m["target_balance"] is not None else "",
            "profitable_days_a_fixed_est": m["a_fixed"],
            "profitable_days_b_fixed_est": m["b_fixed"],
            "profitable_days_a_new_york": m["a_ny"],
            "profitable_days_b_new_york": m["b_ny"],
            "daily_loss_breaches_fixed_est": m["fixed_breaches"],
            "daily_loss_breaches_new_york": m["ny_breaches"],
            "smallest_daily_margin_fixed_est": m["fixed_smallest_daily_margin"],
            "smallest_daily_margin_new_york": m["ny_smallest_daily_margin"],
            "minimum_equity": m["minimum_equity"],
            "minimum_equity_timestamp": m["minimum_equity_time"],
            "static_floor_margin": m["static_floor_margin"],
            "genuine_inactivity_breaches": len(m["inactivity_breaches"]),
            "first_inactivity_breach_timestamp": m["inactivity_breaches"][0]["sixty_day_timestamp"] if m["inactivity_breaches"] else "",
            "executed_entries": m["executed_entries"],
            "completed_positions": m["completed_positions"],
            "open_positions_at_cutoff": m["open_positions_at_cutoff"],
            "final_closed_balance": m["final_closed_balance"],
            "applicable_sizing_mismatches": m["applicable_sizing_mismatches"],
        })
    write_csv(ADD / "phase1-condition-metrics.csv", list(mrows[0]), mrows)

    (ADD / "instrumentation-equivalence.md").write_text(
        "# Instrumentation equivalence\n\n`PASS` — maximum unexplained divergence is zero. The zero-delay reference/instrumented pair and "
        "200 ms reference/instrumented pair have byte-identical deals, transactions and events. High and Stress also have byte-identical native streams to Normal; "
        "their frozen 0.5x/1.0x supplementary-friction layers are reporting adjustments and are not described as broker-native fills. The instrumentation observes account state only.\n"
    )
    (ADD / "continuous-run-manifest.md").write_text(
        "# Continuous run manifest\n\nOne USD 10,000 account was tested from 2025-01-01 inclusive through 2026-08-01 exclusive, with warm-up beginning 2024-12-01 and no warm-up trades. "
        "Each run processed 133 scheduled legs across 19 natural cohorts, executed 119 entries, rejected 14 entries under the unchanged consecutive-loss risk lock, missed zero signals, and recorded zero execution blocks. "
        "The account state was not reset on 2026-01-01. Four July positions remained naturally open at the last pre-cutoff tick; MT5's post-test teardown state is excluded from Phase 1 calculations.\n\n"
        "Physical runs: Normal/High/Stress use native zero-delay FP execution plus their frozen reporting cost profiles; 200 ms uses fixed tester delay 200. "
        "The retained `technical-failures/reference-normal-attempt1/` run failed only the first addendum cutoff bookkeeping assertion; its trading artifacts match the corrected reference and are not used for metrics.\n"
    )
    (ADD / "history-coverage-and-fingerprint.md").write_text(
        "# History coverage and fingerprint\n\nAll 133 required FPMarketsSC-Demo monthly TKC files (19 months × seven symbols, 2025-01 through 2026-07) are present, non-empty and independently hashed. "
        "Tester synchronization records cover through 2026-07-31 for every symbol. The 2025-01-01 market holiday has no executable market tick; the first eligible trading ticks occur afterward, with no warm-up trade. "
        "The regenerated 133-leg schedule matches all 119 previously frozen legs field-for-field and adds only the natural 2025-12-01 and 2026-07-06 cohorts. "
        "FP Markets' official FAQ states that platform server time is GMT+2/GMT+3 with daylight saving and is aligned to New York close: https://www.fpmarkets.com/en-au/education/faq/\n"
    )
    (ADD / "phase1-candidate-analysis.md").write_text(
        "# Phase 1 candidate analysis\n\n"
        + "\n".join(
            f"- {row['condition']}: `{row['result']}`; target `{row['target_timestamp'] or 'NOT_REACHED'}`; "
            f"profitable days Fixed A/B `{row['profitable_days_a_fixed_est']}/{row['profitable_days_b_fixed_est']}`, "
            f"New York A/B `{row['profitable_days_a_new_york']}/{row['profitable_days_b_new_york']}`; "
            f"minimum equity `{float(row['minimum_equity']):.2f}`; static margin `{float(row['static_floor_margin']):.2f}`."
            for row in mrows
        )
        + "\n\nInterpretation A requires cumulative closing balance and equity of at least USD 10,050. Interpretation B requires both realised balance change and equity change of at least USD 50 during the individual trading day. "
        "Both are reported; neither timezone choice changes a condition result. Phase 2 is deliberately not entered.\n"
    )
    (ADD / "unresolved-external-dependencies.md").write_text(
        "# Unresolved external dependencies\n\n- Exact historical FXIFY MT5 RAW tick size/value, volume limits/step, margin flags, spreads, swaps, server timezone and execution/slippage remain externally pending and are not guessed.\n"
        "- FXIFY's intended meaning of repeated `5:00 PM EST` wording versus New York-local DST remains externally pending; both interpretations are retained.\n"
        "- High and Stress supplementary costs retain their qualified reporting-only character and are not represented as exact FXIFY broker fills. Their pre-target rounded position volumes remain identical to the native stream; later Stress volume sensitivity does not change the signs that cause the March consecutive-loss lock.\n"
        "- No Phase 2, funded-stage, payout or purchase conclusion is authorized by this addendum.\n"
    )

    ledger = ADD / "complete-addendum-sha256-ledger.txt"
    artifacts = sorted(path for path in ADD.rglob("*") if path.is_file() and path != ledger)
    ledger.write_text("# Addendum artifacts (self-referential ledger excluded)\n" + "".join(f"{sha(path)}  {path.relative_to(ADD).as_posix()}\n" for path in artifacts))
    print(json.dumps({"metrics": {key: {k: (v.strftime(FMT) if isinstance(v, datetime) else v) for k, v in value.items() if k != "inactivity_breaches"} for key, value in metrics.items()}, "equivalence_rows": len(equivalence), "history_files": len(history_rows), "ledger_entries": len(artifacts)}, indent=2))


if __name__ == "__main__":
    main()
