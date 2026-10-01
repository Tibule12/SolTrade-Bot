#!/usr/bin/env python3
"""Produce exact FP broker-cash path and explicit three-account evidence status."""

import csv
import json
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

try:
    from tools.three_account_replay.engine import read_native_deals, replay_account_path
except ModuleNotFoundError:
    from three_account_replay.engine import read_native_deals, replay_account_path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
UTC_FORMAT = "%Y-%m-%dT%H:%M:%S%z"


def to_utc(ms):
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat()


def at(points, instant):
    eligible = [p for p in points if p.time_msc <= instant]
    if not eligible:
        return None
    point = eligible[-1]
    return {"balance": str(point.balance), "open_position_ids": [p.position_id for p in point.positions],
            "open_position_count": point.position_count, "last_deal_utc": to_utc(point.time_msc)}


def close_positions(deals, risk_by_position):
    groups = defaultdict(list)
    for deal in deals:
        if deal.is_trade:
            groups[deal.position_id].append(deal)
    rows = []
    for position, legs in groups.items():
        opens = [d for d in legs if d.entry == 0]
        closes = [d for d in legs if d.entry == 1]
        if not opens or not closes or sum(d.volume for d in opens) != sum(d.volume for d in closes):
            continue
        first = min(opens, key=lambda d: d.time_msc)
        last = max(closes, key=lambda d: d.time_msc)
        cash = sum((d.cash_delta for d in legs), Decimal("0"))
        risk = risk_by_position.get(position)
        rows.append({
            "account": "FP 7404213", "position_id": position,
            "entry_utc": to_utc(first.time_msc), "exit_utc": to_utc(last.time_msc),
            "symbol": first.symbol, "direction": "BUY" if first.type == 0 else "SELL",
            "entry_price": str(first.price),
            "opening_volume": str(sum(d.volume for d in opens)),
            "close_deal_count": len(closes), "two_close_deals": len(closes) == 2,
            "gross_profit": str(sum((d.profit for d in legs), Decimal("0"))),
            "commission": str(sum((d.commission for d in legs), Decimal("0"))),
            "swap": str(sum((d.swap for d in legs), Decimal("0"))),
            "fee": str(sum((d.fee for d in legs), Decimal("0"))),
            "net_cash": str(cash),
            "initial_risk_when_ea_recorded": str(risk) if risk is not None else "",
            "net_r_when_ea_risk_recorded": str(cash / risk) if risk else "",
        })
    return sorted(rows, key=lambda r: (r["exit_utc"], r["position_id"]))


def main():
    deals_path = BASE / "broker-refresh-fp/deals.csv"
    deals = read_native_deals(deals_path, server_utc_offset_minutes=180)
    risk_by_position = {}
    with (BASE / "fp-score-trades.csv").open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["initial_dollar_risk"]:
                risk_by_position[row["position_id"]] = Decimal(row["initial_dollar_risk"])
    entry_risk = {deal.ticket: risk_by_position[deal.position_id] for deal in deals
                  if deal.is_trade and deal.entry == 0 and deal.position_id in risk_by_position}
    result = replay_account_path(deals, opening_balance=0, opening_flat_confirmed=True,
                                 risk_by_entry_ticket=entry_risk)
    if result.issues:
        raise ValueError(f"Broker baseline has unresolved position reconstruction: {result.issues}")
    with (BASE / "fp-broker-balance-path.csv").open("w", newline="") as handle:
        fields = ["utc", "event", "ticket", "balance", "position_count", "open_position_ids",
                  "gross_to_date", "commission_to_date", "swap_to_date", "fee_to_date", "external_cashflow_to_date",
                  "known_risk", "unknown_risk_positions", "total_risk_if_known"]
        writer = csv.DictWriter(handle, fields)
        writer.writeheader()
        for point in result.points:
            writer.writerow({
                "utc": to_utc(point.time_msc), "event": point.event, "ticket": point.reference,
                "balance": str(point.balance), "position_count": point.position_count,
                "open_position_ids": "|".join(p.position_id for p in point.positions),
                "gross_to_date": str(point.trade_gross_profit), "commission_to_date": str(point.commission),
                "swap_to_date": str(point.swap), "fee_to_date": str(point.fee),
                "external_cashflow_to_date": str(point.nontrade_cashflow),
                "known_risk": str(point.known_risk), "unknown_risk_positions": point.unknown_risk_positions,
                "total_risk_if_known": str(point.total_risk) if point.total_risk is not None else "",
            })
    positions = close_positions(deals, risk_by_position)
    with (BASE / "fp-broker-position-ledger.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(positions[0]))
        writer.writeheader()
        writer.writerows(positions)
    peak = None
    max_balance_dd = Decimal("0")
    for point in result.points:
        if point.nontrade_cashflow < 100000:
            continue
        peak = point.balance if peak is None else max(peak, point.balance)
        max_balance_dd = max(max_balance_dd, peak - point.balance)
    sep30 = int(datetime(2026, 9, 30, 17, 59, tzinfo=timezone.utc).timestamp() * 1000)
    sep13 = int(datetime(2026, 9, 13, 7, 23, 58, tzinfo=timezone.utc).timestamp() * 1000)
    output = {
        "schema": "SOLTRADE_THREE_ACCOUNT_BASELINE_REPLAY_V1",
        "fp": {
            "basis": "FRESH_NATIVE_BROKER_DEALS_AND_ORDERS; CASH_EXACT_FOR_EXPORT",
            "server_utc_offset_minutes": 180,
            "deal_rows": len(deals), "closed_positions": len(positions),
            "wins": sum(Decimal(p["net_cash"]) > 0 for p in positions),
            "losses": sum(Decimal(p["net_cash"]) < 0 for p in positions),
            "two_close_positions": sum(p["two_close_deals"] for p in positions),
            "trade_net_cash_since_deposit": str(sum((Decimal(p["net_cash"]) for p in positions), Decimal("0"))),
            "final_export_balance": str(result.final_balance),
            "final_export_open_positions": [p.position_id for p in result.open_positions],
            "max_observed_realized_balance_drawdown_cash": str(max_balance_dd),
            "max_true_equity_drawdown": None,
            "september_13_baseline": at(result.points, sep13),
            "september_30_visual_anchor": at(result.points, sep30),
            "september_30_expected_visual_balance": "94456.60",
            "september_30_visual_balance_reconciles": Decimal(at(result.points, sep30)["balance"]) == Decimal("94456.60"),
            "risk_annotated_positions": len(risk_by_position),
            "risk_unannotated_positions": len(positions) - len(risk_by_position),
            "ledger_status": result.ledger_status, "position_status": result.position_status,
            "equity_status": result.equity_status, "unresolved_dependencies": result.unresolved_dependencies,
        },
        "fxify_10k": {"basis": "EA_EVENTS_PLUS_TWO_FLAT_BALANCE_ANCHORS", "independent_broker_ledger": False,
                      "baseline_exact_account_path": False, "post_sep13_paused_balance_bridge": "10039.41 - 379.17 = 9660.24"},
        "fxify_100k": {"basis": "EA_EVENTS_PLUS_TWO_FLAT_BALANCE_ANCHORS", "independent_broker_ledger": False,
                       "baseline_exact_account_path": False, "post_sep13_paused_balance_bridge": "100321.36 - 3915.76 = 96405.60"},
    }
    (BASE / "baseline-replay.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({"fp_final": output["fp"]["final_export_balance"],
                      "sep30_reconciles": output["fp"]["september_30_visual_balance_reconciles"],
                      "closed_positions": len(positions)}))


if __name__ == "__main__":
    main()
