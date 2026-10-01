#!/usr/bin/env python3
"""Quote-path tests of predeclared BE floors; explicitly not executable account replay."""

import csv
import json
from collections import defaultdict
from pathlib import Path

try:
    from tools.three_account_first_move import BASE, read_deals, quotes
except ModuleNotFoundError:
    from three_account_first_move import BASE, read_deals, quotes


def quote_exit(quote, side):
    return quote["bid"] if side == 1 else quote["ask"]


def find_floor_hit(path, entry_msc, exit_msc, bank_msc, side, entry_price, risk_price):
    half_armed = False
    half_arm_msc = None
    half_hit = None
    post_bank_hit = None
    for quote in path:
        ms = quote["ms"]
        if ms <= entry_msc or ms > exit_msc:
            continue
        exit_price = quote_exit(quote, side)
        current_r = side * (exit_price - entry_price) / risk_price
        if not half_armed and current_r >= 0.5:
            half_armed = True
            half_arm_msc = ms
        elif half_armed and half_hit is None and current_r <= 0:
            half_hit = (ms, exit_price, current_r)
        if bank_msc is not None and ms > bank_msc and post_bank_hit is None and current_r <= 0:
            post_bank_hit = (ms, exit_price, current_r)
    return half_arm_msc, half_hit, post_bank_hit


def run(deals_path, ticks_dir, scores_path):
    with scores_path.open(newline="") as handle:
        recorded = {r["position_id"]: r for r in csv.DictReader(handle)}
    rows = []
    coverage = defaultdict(int)
    for position, legs in read_deals(deals_path).items():
        openings = [r for r in legs if r["entry"] == "0"]
        closes = [r for r in legs if r["entry"] == "1"]
        tick_path = ticks_dir / f"ticks-fp-life-{position}.csv"
        if len(openings) != 1 or not closes or not tick_path.exists():
            continue
        opening = openings[0]
        side = 1 if opening["type"] == "0" else -1
        entry_price = float(opening["price"])
        initial_stop = float(opening["sl"])
        risk_price = abs(entry_price - initial_stop)
        if risk_price <= 0:
            coverage["NO_INITIAL_STOP_GEOMETRY"] += 1
            continue
        start = int(opening["time_msc"])
        terminal = max(int(c["time_msc"]) for c in closes)
        partial = sorted(closes, key=lambda c: int(c["time_msc"]))[0] if len(closes) > 1 else None
        bank_msc = int(partial["time_msc"]) if partial else None
        quote_path = quotes(tick_path)
        half_arm, half_hit, bank_hit = find_floor_hit(quote_path, start, terminal, bank_msc, side, entry_price, risk_price)
        actual = recorded.get(position, {})
        baseline_cash = sum(float(leg[k]) for leg in legs for k in ("profit", "commission", "swap", "fee"))
        record = {
            "account": "FP 7404213", "position_id": position, "symbol": opening["symbol"],
            "direction": "BUY" if side == 1 else "SELL", "entry_server_msc": start,
            "terminal_server_msc": terminal, "entry_price": entry_price, "initial_stop": initial_stop,
            "initial_price_risk": risk_price, "baseline_broker_net_cash": round(baseline_cash, 2),
            "baseline_r_when_ea_recorded": actual.get("final_r") or None,
            "baseline_bank_confirmed": actual.get("bank1_confirmed") if actual else None,
            "bank_deal_msc": bank_msc,
            "half_r_armed_msc": half_arm,
            "half_r_be_hit_msc": half_hit[0] if half_hit else None,
            "half_r_be_quote_exit": half_hit[1] if half_hit else None,
            "half_r_be_quote_exit_price_r": half_hit[2] if half_hit else None,
            "half_r_be_interrupted_actual_bank": bool(half_hit and bank_msc and half_hit[0] < bank_msc),
            "half_r_be_interrupted_actual_win": bool(half_hit and baseline_cash > 0),
            "bank_runner_be_hit_msc": bank_hit[0] if bank_hit else None,
            "bank_runner_be_quote_exit": bank_hit[1] if bank_hit else None,
            "bank_runner_be_quote_exit_price_r": bank_hit[2] if bank_hit else None,
            "baseline_runner_broker_net_cash": sum(float(c[k]) for c in closes[1:] for k in ("profit", "commission", "swap", "fee")) if partial else None,
            "status": "QUOTE_PATH_DIAGNOSTIC__BROKER_STOP_VALIDITY_AND_ALTERNATE_FILL_UNRESOLVED",
        }
        rows.append(record)
        coverage[record["status"]] += 1
    rows.sort(key=lambda r: (r["entry_server_msc"], r["position_id"]))
    return rows, dict(coverage)


def summarize(rows):
    bank = [r for r in rows if r["bank_deal_msc"] is not None]
    known_r = [r for r in rows if r["baseline_r_when_ea_recorded"] is not None]
    return {
        "positions_with_baseline_tick_path": len(rows),
        "positions_with_actual_partial_bank_deal": len(bank),
        "half_r_quote_threshold_armed": sum(r["half_r_armed_msc"] is not None for r in rows),
        "half_r_quote_be_floor_hit": sum(r["half_r_be_hit_msc"] is not None for r in rows),
        "half_r_floor_would_precede_actual_bank": sum(r["half_r_be_interrupted_actual_bank"] for r in rows),
        "half_r_floor_would_precede_actual_profitable_close": sum(r["half_r_be_interrupted_actual_win"] for r in rows),
        "post_bank_entry_price_floor_hit_before_baseline_exit": sum(r["bank_runner_be_hit_msc"] is not None for r in bank),
        "known_ea_final_r_positions": len(known_r),
        "exact_counterfactual_final_cash_available": False,
        "exact_counterfactual_final_balance_available": False,
        "missing_for_exactness": [
            "historical broker stop/freeze validity and actual modified-stop acceptance",
            "counterfactual broker fills/slippage and closing commission/swap allocation",
            "later account-dependent sizing and concurrent admission response",
        ],
    }


def main():
    rows, coverage = run(BASE / "broker-refresh-fp/deals.csv", BASE / "fp-lifetime-ticks", BASE / "fp-score-trades.csv")
    with (BASE / "fp-management-quote-paths.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    output = {"schema": "FP_BE_QUOTE_PATH_DIAGNOSTIC_V1", "coverage": coverage,
              "frozen_rules": {
                  "HALF_R_TO_BE": "After executable exit-side quote first reaches +0.5 initial price-R, first later quote at or beyond entry price against the trade marks a theoretical BE floor hit.",
                  "BANK1R_RUNNER_BE": "After the actual one-time broker partial close, first later executable exit-side quote at or beyond entry price against the trade marks a theoretical runner BE floor hit.",
              },
              "interpretation": "Observed baseline quote paths only. No new trade was placed and no counterfactual fill is claimed. Opening costs mean entry-price floor is not cash breakeven. This is not M1/M2 broker-valid account-path replay.",
              "summary": summarize(rows)}
    (BASE / "fp-management-quote-summary.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps(output["summary"]))


if __name__ == "__main__":
    main()
