#!/usr/bin/env python3
"""Quote-level FP entry-location matrix; outcomes remain right-censored at actual exit."""

import csv
import json
import re
from collections import Counter
from datetime import datetime, timezone

try:
    from tools.three_account_first_move import BASE, read_deals, quotes
except ModuleNotFoundError:
    from three_account_first_move import BASE, read_deals, quotes


EVIDENCE = BASE.parent / "full-live-audit-20260930/evidence/fp-evidence.csv"
DELAYS = (0, 5, 15, 30, 60)
SERVER_OFFSET_MS = 3 * 60 * 60 * 1000


def first_seen_by_position(path):
    result = {}
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["event"] != "ENTRY":
                continue
            match = re.search(r"(?:^|;)signal_first_seen=([^;]+)", row["detail"])
            if match:
                utc = datetime.strptime(match.group(1), "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc)
                result[row["ticket"]] = int(utc.timestamp() * 1000) + SERVER_OFFSET_MS
    return result


def choose_quote(rows, target_msc, max_lag_ms=2000):
    return next((q for q in rows if target_msc <= q["ms"] <= target_msc + max_lag_ms), None)


def run(deals_path, ticks_dir, evidence_path):
    first_seen = first_seen_by_position(evidence_path)
    output = []
    for position, legs in read_deals(deals_path).items():
        openings = [r for r in legs if r["entry"] == "0"]
        closes = [r for r in legs if r["entry"] == "1"]
        tick_path = ticks_dir / f"ticks-fp-life-{position}.csv"
        if len(openings) != 1 or not closes or not tick_path.exists():
            continue
        opening = openings[0]
        side = 1 if opening["type"] == "0" else -1
        actual_entry = float(opening["price"])
        distance = abs(actual_entry - float(opening["sl"]))
        entry_msc = int(opening["time_msc"])
        terminal_msc = max(int(r["time_msc"]) for r in closes)
        path = quotes(tick_path)
        scenarios = [("FIRST_QUALIFICATION", first_seen.get(position))]
        scenarios += [("PRODUCTION_ENTRY" if d == 0 else f"DELAY_{d}S", entry_msc + 1000 * d) for d in DELAYS]
        for arm, target in scenarios:
            quote = choose_quote(path, target) if target is not None else None
            status = "OBSERVED_QUOTE_ONLY"
            if target is None:
                status = "SIGNAL_FIRST_SEEN_UNAVAILABLE"
            elif target >= terminal_msc:
                status = "TARGET_AFTER_BASELINE_EXIT"
            elif quote is None:
                status = "NO_QUOTE_WITHIN_TWO_SECONDS"
            if status != "OBSERVED_QUOTE_ONLY" or distance <= 0:
                output.append({"position_id": position, "symbol": opening["symbol"], "arm": arm,
                               "target_server_msc": target, "status": status if distance > 0 else "NO_INITIAL_STOP_DISTANCE",
                               "sample_server_msc": None, "entry_side_quote": None, "spread": None,
                               "directional_price_change_from_actual_entry": None, "mfe_price_r_to_actual_exit": None,
                               "mae_price_r_to_actual_exit": None, "plus_1r_before_actual_exit": None,
                               "plus_3r_before_actual_exit": None, "plus_5r_before_actual_exit": None,
                               "final_counterfactual_r_known": False})
                continue
            quote_entry = quote["ask"] if side == 1 else quote["bid"]
            subsequent = [q for q in path if quote["ms"] <= q["ms"] <= terminal_msc]
            rs = [side * ((q["bid"] if side == 1 else q["ask"]) - quote_entry) / distance for q in subsequent]
            output.append({"position_id": position, "symbol": opening["symbol"], "arm": arm,
                           "target_server_msc": target, "status": status,
                           "sample_server_msc": quote["ms"], "entry_side_quote": quote_entry,
                           "spread": quote["ask"] - quote["bid"],
                           "directional_price_change_from_actual_entry": side * (quote_entry - actual_entry),
                           "mfe_price_r_to_actual_exit": max(rs) if rs else None,
                           "mae_price_r_to_actual_exit": min(rs) if rs else None,
                           "plus_1r_before_actual_exit": any(r >= 1 for r in rs),
                           "plus_3r_before_actual_exit": any(r >= 3 for r in rs),
                           "plus_5r_before_actual_exit": any(r >= 5 for r in rs),
                           "final_counterfactual_r_known": False})
    return sorted(output, key=lambda r: (r["position_id"], r["arm"]))


def main():
    rows = run(BASE / "broker-refresh-fp/deals.csv", BASE / "fp-lifetime-ticks", EVIDENCE)
    with (BASE / "fp-entry-timing-quote-matrix.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    result = {"schema": "FP_ENTRY_TIMING_QUOTE_MATRIX_V1",
              "rows": len(rows), "status_counts": dict(Counter(r["status"] for r in rows)),
              "arms": ["FIRST_QUALIFICATION", "PRODUCTION_ENTRY", "DELAY_5S", "DELAY_15S", "DELAY_30S", "DELAY_60S"],
              "interpretation": "Original direction and original stop-distance are held only for quote-path MFE/MAE through actual baseline exit. First qualification uses recorded signal_first_seen. Each delayed quote is sampled at/after its target within two seconds. New fills, native structural stops, lot sizing, costs and manager exits remain unknown; no delayed arm has a final account result. Price milestones are not cash Bank1R events."}
    (BASE / "fp-entry-timing-quote-summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
