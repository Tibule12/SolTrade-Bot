#!/usr/bin/env python3
"""Build the terminal FXIFY RAW lifecycle completion from frozen V28 evidence."""
from __future__ import annotations

import collections
import csv
import hashlib
import math
from datetime import datetime, timedelta
from pathlib import Path

import build_fxify_v28_continuous_addendum as continuous


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation"
ADD = AUDIT / "continuous-account-evidence-addendum"
RUNS = ADD / "physical-runs"
OUT = AUDIT / "final-raw-lifecycle-completion"
CAPTURE = OUT / "raw-specification-capture"
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
FMT = "%Y.%m.%d %H:%M:%S"
PHASE2_START = datetime(2025, 7, 7, 10, 5)
BREACH_NORMAL = datetime(2026, 4, 3, 10, 5, 1)
BREACH_200MS = datetime(2026, 4, 3, 10, 5, 2)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def msc_text(value: int | None) -> str:
    return continuous.msc_text(value) if value is not None else ""


def rollover_weight(entry: datetime, exit_: datetime, triple_day: int) -> int:
    day = entry.date()
    total = 0
    while day < exit_.date():
        if day.weekday() < 5:
            total += 3 if day.weekday() == triple_day - 1 else 1
        day += timedelta(days=1)
    return total


def actual_raw_candidate(normal_trades: list[dict], specs: dict[str, dict[str, str]]) -> list[dict]:
    deals_by_position: dict[str, list[dict[str, str]]] = collections.defaultdict(list)
    for row in read_csv(RUNS / "normal/deals.csv"):
        deals_by_position[row["position_identifier"]].append(row)
    result = []
    for source in normal_trades:
        row = dict(source)
        spec = specs[row["symbol"]]
        signed_source_swap = sum(float(deal["swap"]) for deal in deals_by_position[row["position_identifier"]])
        point = float(spec["point"])
        tick_size = float(spec["tick_size"])
        tick_value_loss = float(spec["tick_value_loss"])
        point_value = tick_value_loss * point / tick_size
        snapshot_spread_cost = float(spec["spread_points"]) * point_value * row["volume"]
        swap_rate = float(spec["swap_long"] if row["direction"] == "BUY" else spec["swap_short"])
        weight = rollover_weight(row["entry_time"], row["exit_time"], int(spec["triple_swap_day"]))
        snapshot_swap_cash = swap_rate * point_value * row["volume"] * weight
        # Remove the source signed swap, replace the source entry-spread diagnostic
        # with the captured FXIFY snapshot, then apply the official $6/lot RT charge.
        candidate_cash = (
            row["native_net_before_external_commission"]
            - signed_source_swap
            + row["spread_cost"]
            - snapshot_spread_cost
            + snapshot_swap_cash
            - row["external_commission"]
        )
        row.update({
            "source_signed_swap": signed_source_swap,
            "fxify_snapshot_spread_points": float(spec["spread_points"]),
            "fxify_snapshot_spread_cost": snapshot_spread_cost,
            "fxify_snapshot_swap_rate": swap_rate,
            "fxify_snapshot_rollover_weight": weight,
            "fxify_snapshot_swap_cash": snapshot_swap_cash,
            "candidate_cash": candidate_cash,
            "adjusted_cash": candidate_cash,
            "adjusted_net_R": candidate_cash / row["initial_risk_amount"],
        })
        result.append(row)
    return result


def replay_stage(trades: list[dict], entries: list[dict], start: datetime, breach: datetime, cash_field: str = "adjusted_cash") -> tuple[dict, list[dict]]:
    trade_by_position = {row["position_identifier"]: row for row in trades}
    cohorts: dict[datetime, list[dict]] = collections.defaultdict(list)
    for entry in entries:
        if entry["position_identifier"] in trade_by_position:
            cohorts[entry["signal_time"]].append(entry)
    balance = 10000.0
    maximum = balance
    minimum = balance
    open_positions: dict[str, float] = {}
    ledger = []

    def close_until(cutoff_msc: int) -> None:
        nonlocal balance, maximum, minimum
        closing = sorted(
            (trade_by_position[pid] for pid in open_positions if trade_by_position[pid]["exit_time_msc"] <= cutoff_msc),
            key=lambda row: (row["exit_time_msc"], int(row["position_identifier"])),
        )
        for trade in closing:
            volume = open_positions.pop(trade["position_identifier"])
            cash = trade[cash_field] / trade["volume"] * volume
            balance += cash
            maximum = max(maximum, balance)
            minimum = min(minimum, balance)
            ledger.append({
                "event": "NATURAL_EXIT",
                "time": msc_text(trade["exit_time_msc"]),
                "position_identifier": trade["position_identifier"],
                "symbol": trade["symbol"],
                "volume": volume,
                "cash": cash,
                "closed_balance": balance,
                "exit_reason": trade["exit_reason"],
            })

    for signal_time, cohort in sorted(cohorts.items()):
        if signal_time < start:
            continue
        entry_msc = min(row["entry_time_msc"] for row in cohort)
        if continuous.msc_dt(entry_msc) > breach:
            break
        close_until(entry_msc)
        for entry in sorted(cohort, key=lambda row: (row["entry_time_msc"], row["symbol"])):
            raw_volume = balance * 0.005 / entry["loss_per_lot"]
            volume = round(math.floor((raw_volume + 1e-12) / 0.01) * 0.01, 2)
            if volume < 0.01:
                continue
            open_positions[entry["position_identifier"]] = volume
            ledger.append({
                "event": "NATURAL_ENTRY",
                "time": msc_text(entry["entry_time_msc"]),
                "position_identifier": entry["position_identifier"],
                "symbol": entry["symbol"],
                "volume": volume,
                "cash": 0.0,
                "closed_balance": balance,
                "exit_reason": "",
            })
    close_until(int(breach.timestamp() * 1000))
    return ({
        "balance_at_breach": balance,
        "maximum_closed_balance": maximum,
        "minimum_closed_balance": minimum,
        "open_positions_at_breach": len(open_positions),
        "target_reached": maximum >= 10800.0,
    }, ledger)


def candidate_phase1_financial_target(trades: list[dict], entries: list[dict]) -> tuple[int | None, float | None]:
    trade_by_position = {row["position_identifier"]: row for row in trades}
    cohorts: dict[datetime, list[dict]] = collections.defaultdict(list)
    for entry in entries:
        if entry["position_identifier"] in trade_by_position:
            cohorts[entry["signal_time"]].append(entry)
    balance = 10000.0
    open_positions: dict[str, float] = {}
    for _, cohort in sorted(cohorts.items()):
        entry_msc = min(row["entry_time_msc"] for row in cohort)
        closing = sorted(
            (trade_by_position[pid] for pid in open_positions if trade_by_position[pid]["exit_time_msc"] <= entry_msc),
            key=lambda row: (row["exit_time_msc"], int(row["position_identifier"])),
        )
        latest_exit = None
        for trade in closing:
            volume = open_positions.pop(trade["position_identifier"])
            balance += trade["candidate_cash"] / trade["volume"] * volume
            latest_exit = trade["exit_time_msc"]
        if not open_positions and balance >= 10400.0:
            return latest_exit or entry_msc, balance
        for entry in cohort:
            raw_volume = balance * 0.005 / entry["loss_per_lot"]
            volume = round(math.floor((raw_volume + 1e-12) / 0.01) * 0.01, 2)
            if volume >= 0.01:
                open_positions[entry["position_identifier"]] = volume
    return None, None


def translated_phase2_support(condition: str, key: str, multiplier: float, trades: list[dict]) -> dict:
    start_balance = 10000.0 + sum(row["adjusted_cash"] for row in trades if row["exit_time"] <= PHASE2_START)
    offset = start_balance - 10000.0
    hours = [
        row for row in read_csv(ADD / "continuous-balance-equity.csv")
        if row["condition"] == condition and "2025.07.07 10:00:00" <= row["server_hour"] <= "2026.04.03 11:00:00"
    ]
    minimum_equity = min(float(row["minimum_equity"]) for row in hours)
    days = [
        row for row in read_csv(ADD / "five-pm-fixed-est-audit.csv")
        if row["condition"] == condition
        and row["server_period_end"] >= "2025.07.07 10:05:00"
        and row["server_period_end"] <= ("2026.04.03 10:05:02" if key == "200ms" else "2026.04.03 10:05:01")
    ]
    minimum_daily_margin = min(float(row["daily_loss_margin"]) for row in days)
    translated_profitable = sum(
        float(row["closing_balance"]) - offset >= 10050.0
        and float(row["closing_equity"]) - offset >= 10050.0
        for row in days
    )
    return {
        "continuous_start_balance": start_balance,
        "reset_translation_offset": offset,
        "static_floor_margin_lower_bound": minimum_equity - offset - 9200.0,
        "daily_loss_margin_lower_bound": minimum_daily_margin - 0.04 * offset,
        "profitable_days_a_translated": translated_profitable,
        "translation_limitation": "RESET_BALANCE_TRANSLATION_WITH_EXACT_CLOSED_CASH_REPLAY;_INTRADAY_PER_SYMBOL_MARK_TO_MARKET_NOT_REBUILT",
    }


def main() -> None:
    if sha(PRODUCTION) != PRODUCTION_SHA:
        raise SystemExit("production hash mismatch")
    specs_rows = read_csv(CAPTURE / "raw-symbol-specifications.csv")
    account_rows = read_csv(CAPTURE / "raw-account-and-server.csv")
    if len(specs_rows) != 7 or any(row["status"] != "PASS" for row in specs_rows):
        raise SystemExit("RAW symbol capture invalid")
    if {row["field"]: row["value"] for row in account_rows}.get("credentials_recorded") != "NO":
        raise SystemExit("credential safety assertion failed")
    specs = {row["canonical_symbol"]: row for row in specs_rows}

    profiles = {
        "NORMAL": ("normal", 0.0),
        "HIGH": ("high", 0.5),
        "200MS": ("200ms", 0.0),
        "STRESS": ("stress", 1.0),
    }
    parsed = {}
    for label, (key, multiplier) in profiles.items():
        parsed[label] = continuous.parse_trades(RUNS / key, multiplier)
    normal_trades, normal_entries = parsed["NORMAL"]
    candidate_trades = actual_raw_candidate(normal_trades, specs)
    candidate_target_msc, candidate_target_balance = candidate_phase1_financial_target(candidate_trades, normal_entries)

    cost_rows = []
    for row in candidate_trades:
        cost_rows.append({
            "position_identifier": row["position_identifier"],
            "symbol": row["symbol"],
            "direction": row["direction"],
            "entry_time": row["entry_time_text"],
            "exit_time": row["exit_time_text"],
            "volume": row["volume"],
            "native_net_before_external_commission": row["native_net_before_external_commission"],
            "source_signed_swap": row["source_signed_swap"],
            "source_entry_spread_cost": row["spread_cost"],
            "fxify_snapshot_spread_points": row["fxify_snapshot_spread_points"],
            "fxify_snapshot_spread_cost": row["fxify_snapshot_spread_cost"],
            "fxify_snapshot_swap_rate": row["fxify_snapshot_swap_rate"],
            "fxify_snapshot_rollover_weight": row["fxify_snapshot_rollover_weight"],
            "fxify_snapshot_swap_cash": row["fxify_snapshot_swap_cash"],
            "fxify_commission_6_per_lot": row["external_commission"],
            "candidate_cash": row["candidate_cash"],
            "historical_spread_swap_status": "STATIC_SNAPSHOT_CANDIDATE_NOT_HISTORICAL_FXIFY_EXECUTION",
        })
    write_csv(OUT / "actual-raw-candidate-cost-ledger.csv", list(cost_rows[0]), cost_rows)

    metrics = {row["condition"]: row for row in read_csv(ADD / "phase1-condition-metrics.csv")}
    gaps = {row["condition"]: row for row in read_csv(ADD / "continuous-inactivity-audit.csv") if row["genuinely_reaches_60_days"] == "YES"}
    lifecycle_rows = []
    stage_ledgers = {}
    support_bounds = {}
    for label in ("NORMAL", "HIGH", "200MS"):
        key, multiplier = profiles[label]
        trades, entries = parsed[label]
        breach = BREACH_200MS if label == "200MS" else BREACH_NORMAL
        replay, ledger = replay_stage(trades, entries, PHASE2_START, breach)
        stage_ledgers[label] = ledger
        bounds = translated_phase2_support(label, key, multiplier, trades)
        support_bounds[label] = bounds
        metric = metrics[label]
        gap = gaps[label]
        lifecycle_rows.append({
            "execution_profile": label,
            "evidence_role": "REQUIRED_SUPPORT",
            "phase1_outcome": "PASS",
            "phase1_pass_timestamp": metric["target_timestamp"],
            "phase1_candidate_financial_target_timestamp": "",
            "phase1_closed_balance": metric["target_closed_balance"],
            "phase1_profitable_days_a": metric["profitable_days_a_fixed_est"],
            "phase1_daily_loss_margin": metric["smallest_daily_margin_fixed_est"],
            "phase1_static_floor_margin": metric["static_floor_margin"],
            "phase2_start_timestamp": PHASE2_START.strftime(FMT),
            "phase2_outcome": "FAIL_INACTIVITY",
            "phase2_outcome_timestamp": gap["sixty_day_timestamp"],
            "phase2_maximum_closed_balance": replay["maximum_closed_balance"],
            "phase2_balance_at_breach": replay["balance_at_breach"],
            "phase2_profitable_days_a": bounds["profitable_days_a_translated"],
            "phase2_daily_loss_margin": bounds["daily_loss_margin_lower_bound"],
            "phase2_static_floor_margin": bounds["static_floor_margin_lower_bound"],
            "active_stage_during_gap": "PHASE_2",
            "previous_executed_entry": gap["previous_last_executed_entry"],
            "next_executed_entry": gap["next_first_executed_entry"],
            "gap_seconds": gap["elapsed_seconds"],
            "gap_duration": "62d 23:59:58" if label == "200MS" else "62d 23:59:59",
            "inactivity_breach_timestamp": gap["sixty_day_timestamp"],
            "executed_entry_inside_gap": gap["executed_trade_inside_interval"],
            "funded_outcome": "NOT_ENTERED",
            "first_payout_eligibility": "NONE",
            "gross_payout": 0.0,
            "trader_share_80_percent": 0.0,
        })

    actual_replay, actual_ledger = replay_stage(candidate_trades, normal_entries, PHASE2_START, BREACH_NORMAL, "candidate_cash")
    stage_ledgers["ACTUAL_RAW_CANDIDATE"] = actual_ledger
    worst_daily = min(value["daily_loss_margin_lower_bound"] for value in support_bounds.values())
    worst_static = min(value["static_floor_margin_lower_bound"] for value in support_bounds.values())
    normal_gap = gaps["NORMAL"]
    lifecycle_rows.insert(0, {
        "execution_profile": "ACTUAL_RAW_CANDIDATE",
        "evidence_role": "STATIC_CAPTURE_CANDIDATE_WITH_SUPPORT_CONSENSUS",
        "phase1_outcome": "PASS_SUPPORTED",
        "phase1_pass_timestamp": metrics["NORMAL"]["target_timestamp"],
        "phase1_candidate_financial_target_timestamp": msc_text(candidate_target_msc),
        "phase1_closed_balance": candidate_target_balance,
        "phase1_profitable_days_a": "56_SUPPORT_CONSENSUS",
        "phase1_daily_loss_margin": f">={min(float(metrics[name]['smallest_daily_margin_fixed_est']) for name in ('NORMAL', 'HIGH', '200MS')):.8f}_SUPPORT_ENVELOPE",
        "phase1_static_floor_margin": f">={min(float(metrics[name]['static_floor_margin']) for name in ('NORMAL', 'HIGH', '200MS')):.8f}_SUPPORT_ENVELOPE",
        "phase2_start_timestamp": PHASE2_START.strftime(FMT),
        "phase2_outcome": "FAIL_INACTIVITY",
        "phase2_outcome_timestamp": normal_gap["sixty_day_timestamp"],
        "phase2_maximum_closed_balance": actual_replay["maximum_closed_balance"],
        "phase2_balance_at_breach": actual_replay["balance_at_breach"],
        "phase2_profitable_days_a": min(value["profitable_days_a_translated"] for value in support_bounds.values()),
        "phase2_daily_loss_margin": f">={worst_daily:.8f}_SUPPORT_ENVELOPE",
        "phase2_static_floor_margin": f">={worst_static:.8f}_SUPPORT_ENVELOPE",
        "active_stage_during_gap": "PHASE_2",
        "previous_executed_entry": normal_gap["previous_last_executed_entry"],
        "next_executed_entry": normal_gap["next_first_executed_entry"],
        "gap_seconds": normal_gap["elapsed_seconds"],
        "gap_duration": "62d 23:59:59",
        "inactivity_breach_timestamp": normal_gap["sixty_day_timestamp"],
        "executed_entry_inside_gap": normal_gap["executed_trade_inside_interval"],
        "funded_outcome": "NOT_ENTERED",
        "first_payout_eligibility": "NONE",
        "gross_payout": 0.0,
        "trader_share_80_percent": 0.0,
    })

    stress_gap = gaps["STRESS"]
    lifecycle_rows.append({
        "execution_profile": "STRESS",
        "evidence_role": "SUPPLEMENTARY_ONLY",
        "phase1_outcome": "FAIL_INACTIVITY",
        "phase1_pass_timestamp": "",
        "phase1_candidate_financial_target_timestamp": "",
        "phase1_closed_balance": "",
        "phase1_profitable_days_a": 251,
        "phase1_daily_loss_margin": 168.64572871776545,
        "phase1_static_floor_margin": 629.7110179166466,
        "phase2_start_timestamp": "",
        "phase2_outcome": "NOT_ENTERED",
        "phase2_outcome_timestamp": "",
        "phase2_maximum_closed_balance": "",
        "phase2_balance_at_breach": "",
        "phase2_profitable_days_a": "",
        "phase2_daily_loss_margin": "",
        "phase2_static_floor_margin": "",
        "active_stage_during_gap": "PHASE_1",
        "previous_executed_entry": stress_gap["previous_last_executed_entry"],
        "next_executed_entry": stress_gap["next_first_executed_entry"],
        "gap_seconds": stress_gap["elapsed_seconds"],
        "gap_duration": "62d 23:59:59",
        "inactivity_breach_timestamp": stress_gap["sixty_day_timestamp"],
        "executed_entry_inside_gap": stress_gap["executed_trade_inside_interval"],
        "funded_outcome": "NOT_ENTERED",
        "first_payout_eligibility": "NONE",
        "gross_payout": 0.0,
        "trader_share_80_percent": 0.0,
    })
    write_csv(OUT / "sequential-lifecycle-results.csv", list(lifecycle_rows[0]), lifecycle_rows)

    ledger_fields = ["execution_profile", "event", "time", "position_identifier", "symbol", "volume", "cash", "closed_balance", "exit_reason"]
    ledger_rows = []
    for label, rows in stage_ledgers.items():
        ledger_rows.extend({"execution_profile": label, **row} for row in rows)
    write_csv(OUT / "phase2-reset-replay-ledger.csv", ledger_fields, ledger_rows)

    inactivity_fields = [
        "execution_profile", "active_stage", "previous_executed_entry", "next_executed_entry", "elapsed_seconds",
        "exact_duration", "executed_entry_inside_interval", "breach_timestamp", "fatal_rule_result",
    ]
    inactivity_rows = [{
        "execution_profile": row["execution_profile"],
        "active_stage": row["active_stage_during_gap"],
        "previous_executed_entry": row["previous_executed_entry"],
        "next_executed_entry": row["next_executed_entry"],
        "elapsed_seconds": row["gap_seconds"],
        "exact_duration": row["gap_duration"],
        "executed_entry_inside_interval": row["executed_entry_inside_gap"],
        "breach_timestamp": row["inactivity_breach_timestamp"],
        "fatal_rule_result": "FAIL_60_CALENDAR_DAY_ENTRY_INACTIVITY",
    } for row in lifecycle_rows]
    write_csv(OUT / "inactivity-stage-audit.csv", inactivity_fields, inactivity_rows)

    spec_summary = []
    for row in specs_rows:
        spec_summary.append({
            **row,
            "official_round_turn_commission_per_lot_usd": 6.0,
            "spread_evidence_type": "LIVE_SNAPSHOT_ONLY_NOT_HISTORICAL",
            "programme_leverage": "1:30_FROZEN_RULE",
            "captured_viewer_account_leverage": "1:100",
        })
    write_csv(OUT / "fxify-raw-static-specification-summary.csv", list(spec_summary[0]), spec_summary)

    (OUT / "cost-model-and-limitations.md").write_text(
        "# FXIFY RAW candidate cost model and limitations\n\n"
        "The read-only capture resolved all seven required symbols with `.r` suffixes, standard 100,000-unit FX contracts, "
        "0.01 minimum/step volume, captured tick values, swaps, execution modes, and live spread snapshots. Official Forex "
        "commission is applied at USD 6 per round-turn lot. The viewer account reported 1:100 while the frozen programme "
        "rule remains 1:30; prior 1:30 margin evidence remains the programme constraint.\n\n"
        "The actual-RAW candidate replaces the source entry-spread diagnostic with the captured FXIFY spread snapshot, "
        "replaces signed source swap with the captured direction-specific swap schedule, and applies USD 6/lot. This is a "
        "static candidate, not reconstructed historical FXIFY spread or swap history. The candidate financial target is "
        f"reached at `{msc_text(candidate_target_msc)}` with closed balance `{candidate_target_balance:.8f}`, but the supported "
        "Phase 1 transition is conservatively held to `2025.06.02 10:05:00.273`, when Normal, High, and 200 ms all support "
        "the same compliant transition. The `2025.06.02 10:05:00` signal predates that supported pass timestamp, so its "
        "later fill is not imported into the reset account; the next new natural signal is `2025.07.07 10:05:00`.\n\n"
        "Phase 2 is replayed from a fresh USD 10,000 balance at the next natural entry opportunity, with broker-step volume "
        "rounding and only natural exits. Intraday per-symbol mark-to-market was not rebuilt after the reset; reported daily "
        "and static margins are conservative support-envelope/translation values. This limitation cannot reverse the fatal "
        "entry-inactivity breach.\n"
    )

    decision_table_lines = [
        "| Profile | Phase 1 outcome / timestamp | P1 profitable days A | P1 daily / static margin (USD) | Phase 2 outcome / timestamp | P2 profitable days A | P2 daily / static margin (USD) | Funded / payout |",
        "|---|---|---:|---|---|---:|---|---|",
    ]
    for row in lifecycle_rows[:4]:
        decision_table_lines.append(
            f"| {row['execution_profile']} | {row['phase1_outcome']} / {row['phase1_pass_timestamp']} | "
            f"{row['phase1_profitable_days_a']} | {row['phase1_daily_loss_margin']} / {row['phase1_static_floor_margin']} | "
            f"{row['phase2_outcome']} / {row['phase2_outcome_timestamp']} | {row['phase2_profitable_days_a']} | "
            f"{row['phase2_daily_loss_margin']} / {row['phase2_static_floor_margin']} | NOT_ENTERED / USD 0 gross, USD 0 trader share |"
        )
    decision_table = "\n".join(decision_table_lines)

    (OUT / "final-decision.md").write_text(
        "# Final FXIFY RAW lifecycle decision\n\n"
        "`PURCHASE_NOT_AUTHORIZED`\n\n"
        "Actual RAW candidate, Normal support, High support, and 200 ms support all pass Phase 1 on the conservative common "
        "evidence transition and remain in Phase 2 during the confirmed no-entry interval. Phase 2 never reaches its USD "
        "10,800 target before the inactivity deadline. The last entry is `2026.02.02 10:05:01` (200 ms: `10:05:02`); the "
        "next is `2026.04.06 10:05:00`. The exact gaps are 62d 23:59:59 and 62d 23:59:58 respectively, with no executed "
        "entry inside. The 60-day hard breach occurs at `2026.04.03 10:05:01` (200 ms: `10:05:02`).\n\n"
        + decision_table + "\n\n"
        "Funded status is never entered. First payout eligibility is none, gross payout is USD 0, and the 80% trader share "
        "is USD 0. Stress is supplementary and fails while still in Phase 1; it is not used as the automatic actual-RAW "
        "programme decision. The pre-tax NEW30 price is USD 90.30, but no checkout total is established and the strategy has "
        "already failed a required programme rule. V28 and production are unchanged; no purchase and no push occurred.\n\n"
        "V28_FXIFY_2PHASE_PRO_10K_FAILS_REQUIRED_RULES\n"
    )

    manifest = (
        "# Final evidence manifest\n\n"
        f"- Production SHA-256: `{sha(PRODUCTION)}`\n"
        f"- RAW account capture SHA-256: `{sha(CAPTURE / 'raw-account-and-server.csv')}`\n"
        f"- RAW symbol capture SHA-256: `{sha(CAPTURE / 'raw-symbol-specifications.csv')}`\n"
        f"- Evidence builder SHA-256: `{sha(Path(__file__))}`\n"
        "- Credentials recorded: `NO`\n"
        "- Orders during capture: `0`\n"
        "- Positions during capture: `0`\n"
        "- Source execution evidence: completed continuous Normal, High, Stress, and 200 ms physical runs.\n"
        "- Official clarifications applied: fixed 17:00 UTC-5 boundary, profitable-day interpretation A, USD 6/lot RAW "
        "Forex commission, USD 129 base and USD 90.30 NEW30 pre-tax.\n"
        "- Historical FXIFY spread/swap reconstruction: unavailable and explicitly bounded by the required support profiles.\n"
    )
    (OUT / "evidence-manifest.md").write_text(manifest)

    ledger_files = sorted(
        [PRODUCTION, Path(__file__)]
        + [path for path in OUT.rglob("*") if path.is_file() and path.name != "complete-final-sha256-ledger.txt"]
    )
    (OUT / "complete-final-sha256-ledger.txt").write_text(
        "".join(f"{sha(path)}  {path.relative_to(ROOT)}\n" for path in ledger_files)
    )


if __name__ == "__main__":
    main()
