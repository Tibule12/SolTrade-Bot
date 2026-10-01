"""Reconcile a recovered FXIFY broker ledger against recorded EA events."""

from __future__ import annotations

import csv
import json
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

from tools.three_account_replay.engine import read_native_deals, replay_account_path


ROOT = Path(__file__).resolve().parents[2]
PRIOR = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
OUT = ROOT / "reports/fast-multi-market-v2/three-account-replay-completion-20261001"
BROKER = OUT / "fxify-10k-broker-export"


def build() -> dict:
    with (BROKER / "history-status.csv").open(newline="") as stream:
        status = list(csv.DictReader(stream))
    if len(status) != 1 or status[0]["status"] != "COMPLETE" or status[0]["account"] != "7196820":
        raise ValueError("A completed account-specific read-only history receipt is required")
    deals = read_native_deals(BROKER / "deals.csv", server_utc_offset_minutes=180)
    with (BROKER / "orders.csv").open(newline="") as stream:
        orders = list(csv.DictReader(stream))
    replay = replay_account_path(deals, opening_balance=0, opening_flat_confirmed=True)
    if replay.issues or replay.open_positions or replay.final_balance != Decimal("9660.24"):
        raise ValueError("FXIFY broker ledger does not reconcile to the flat pause anchor")
    positions: dict[str, list] = defaultdict(list)
    for deal in deals:
        if deal.is_trade:
            positions[deal.position_id].append(deal)
    with (PRIOR / "fxify-10k-event-trades.csv").open(newline="") as stream:
        observed = list(csv.DictReader(stream))
    if len(positions) != 24 or len(observed) != 22:
        raise ValueError("FXIFY deal or EA event count changed")
    ledger = []
    for pid, legs in positions.items():
        cash = sum((deal.cash_delta for deal in legs), Decimal(0))
        opens = [deal for deal in legs if deal.entry == 0]
        closes = [deal for deal in legs if deal.entry == 1]
        if len(opens) != 1 or len(closes) != 1 or opens[0].volume != closes[0].volume:
            raise ValueError(f"Unresolved broker position path: {pid}")
        ledger.append({"position_id": pid, "entry_utc_msc": opens[0].time_msc,
                       "exit_utc_msc": closes[0].time_msc, "symbol": opens[0].symbol,
                       "direction": "BUY" if opens[0].type == 0 else "SELL",
                       "volume": str(opens[0].volume), "net_cash": str(cash),
                       "entry_deal_ticket": opens[0].ticket, "exit_deal_ticket": closes[0].ticket})
    ledger.sort(key=lambda row: (row["exit_utc_msc"], row["position_id"]))
    cash_by_position = {row["position_id"]: Decimal(row["net_cash"]) for row in ledger}
    september_ids = {row["position_id"] for row in observed}
    august_cash = sum((cash for pid, cash in cash_by_position.items() if pid not in september_ids), Decimal(0))
    mismatches = [{"position_id": row["position_id"], "ea_cash": row["net_usd"],
                   "broker_cash": str(cash_by_position.get(row["position_id"]))}
                  for row in observed if cash_by_position.get(row["position_id"]) != Decimal(row["net_usd"])]
    if mismatches:
        raise ValueError(f"EA-to-broker cash mismatches: {mismatches}")
    peak = None
    drawdown = Decimal(0)
    for point in replay.points:
        if point.nontrade_cashflow < Decimal("10000"):
            continue
        peak = point.balance if peak is None else max(peak, point.balance)
        drawdown = max(drawdown, peak - point.balance)
    with (OUT / "fxify-10k-broker-position-ledger.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=tuple(ledger[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(ledger)
    result = {"schema": "FXIFY_10K_BROKER_CASH_RECONCILIATION_V1",
              "login": 7196820, "server_utc_offset_minutes": 180,
              "broker_deals": len(deals), "broker_orders": len(orders),
              "closed_positions": len(ledger), "broker_open_positions": len(replay.open_positions),
              "september_ea_positions_matched": len(observed), "ea_broker_cash_mismatch_count": 0,
              "august_positions_outside_september_events": sorted(set(cash_by_position) - {r["position_id"] for r in observed}),
              "initial_deposit": "10000.00", "broker_final_balance": str(replay.final_balance),
              "september_opening_balance_after_august_pilot": str(Decimal("10000") + august_cash),
              "broker_net_trade_cash": str(sum(cash_by_position.values(), Decimal(0))),
              "wins": sum(cash > 0 for cash in cash_by_position.values()),
              "losses": sum(cash < 0 for cash in cash_by_position.values()),
              "two_close_positions": 0,
              "max_observed_realized_balance_drawdown_cash": str(drawdown),
              "max_true_equity_drawdown_cash": None,
              "broker_cash_exact": True, "broker_alternative_path_exact": False,
              "research_permission_exception": "Exporter runtime reported MQL_TRADE_ALLOWED=1 despite startup AllowLiveTrading=0; zero order API and no new research deals. Further account probes halted.",
              "broker_export_receipt": "fxify-10k-broker-export/recovery-receipt.json"}
    (OUT / "fxify-10k-broker-reconciliation.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    print(json.dumps(build()))
