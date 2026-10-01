#!/usr/bin/env python3
"""Opposite-side initial-boundary replay on actual FP broker ticks, with censoring."""

import csv
import json
from collections import Counter, defaultdict

try:
    from tools.three_account_first_move import BASE, read_deals, quotes
except ModuleNotFoundError:
    from three_account_first_move import BASE, read_deals, quotes


def first_boundary(path, entry_msc, side, entry_price, distance, terminal_msc):
    for quote in path:
        if quote["ms"] <= entry_msc or quote["ms"] > terminal_msc:
            continue
        exit_price = quote["bid"] if side == 1 else quote["ask"]
        r = side * (exit_price - entry_price) / distance
        if r <= -1:
            return "INITIAL_STOP_BOUNDARY", quote["ms"], r
        if r >= 1:
            return "PLUS_1R_BOUNDARY", quote["ms"], r
    return "RIGHT_CENSORED_AT_ACTUAL_EXIT", None, None


def run(deals_path, ticks_dir):
    rows = []
    for position, legs in read_deals(deals_path).items():
        opening = [r for r in legs if r["entry"] == "0"]
        closes = [r for r in legs if r["entry"] == "1"]
        tick_path = ticks_dir / f"ticks-fp-life-{position}.csv"
        if len(opening) != 1 or not closes or not tick_path.exists():
            continue
        first = opening[0]
        entry_msc = int(first["time_msc"])
        terminal_msc = max(int(c["time_msc"]) for c in closes)
        distance = abs(float(first["price"]) - float(first["sl"]))
        quote_path = quotes(tick_path)
        anchors = [q for q in quote_path if entry_msc - 2000 <= q["ms"] <= entry_msc]
        if distance <= 0 or not anchors:
            rows.append({"position_id": position, "symbol": first["symbol"], "entry_server_msc": entry_msc,
                         "normal_direction": "BUY" if first["type"] == "0" else "SELL",
                         "normal_boundary": "UNRESOLVED_ENTRY_QUOTE_OR_STOP", "normal_boundary_msc": None,
                         "normal_boundary_r": None, "inverted_entry_price": None, "inverted_stop": None,
                         "inverted_boundary": "UNRESOLVED_ENTRY_QUOTE_OR_STOP", "inverted_boundary_msc": None,
                         "inverted_boundary_r": None, "actual_baseline_terminal_msc": terminal_msc})
            continue
        side = 1 if first["type"] == "0" else -1
        inverted_side = -side
        anchor = anchors[-1]
        opposite_entry = anchor["bid"] if inverted_side == -1 else anchor["ask"]
        opposite_stop = opposite_entry - inverted_side * distance
        normal_event, normal_ms, normal_r = first_boundary(quote_path, entry_msc, side, float(first["price"]), distance, terminal_msc)
        inverted_event, inverted_ms, inverted_r = first_boundary(quote_path, entry_msc, inverted_side, opposite_entry, distance, terminal_msc)
        rows.append({
            "position_id": position, "symbol": first["symbol"], "entry_server_msc": entry_msc,
            "normal_direction": "BUY" if side == 1 else "SELL", "normal_boundary": normal_event,
            "normal_boundary_msc": normal_ms, "normal_boundary_r": normal_r,
            "inverted_entry_price": opposite_entry, "inverted_stop": opposite_stop,
            "inverted_boundary": inverted_event, "inverted_boundary_msc": inverted_ms,
            "inverted_boundary_r": inverted_r, "actual_baseline_terminal_msc": terminal_msc,
        })
    return sorted(rows, key=lambda r: (r["entry_server_msc"], r["position_id"]))


def main():
    rows = run(BASE / "broker-refresh-fp/deals.csv", BASE / "fp-lifetime-ticks")
    with (BASE / "fp-inversion-initial-boundaries.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "schema": "FP_OPPOSITE_INITIAL_BOUNDARY_DIAGNOSTIC_V1",
        "normal": dict(Counter(r["normal_boundary"] for r in rows)),
        "inverted": dict(Counter(r["inverted_boundary"] for r in rows)),
        "both_boundaries_known": sum(r["normal_boundary"] in ("INITIAL_STOP_BOUNDARY", "PLUS_1R_BOUNDARY") and r["inverted_boundary"] in ("INITIAL_STOP_BOUNDARY", "PLUS_1R_BOUNDARY") for r in rows),
        "exact_inverted_account_path_available": False,
        "native_opposite_structure_available": False,
        "interpretation": "Mirrored initial distance only; actual bid/ask at entry, no synthetic cash negation. A +1R crossing is not final profit. Position path ends at actual baseline exit, so any opposite position still active then is right-censored. Production Bank1R/runner behavior, native opposite stop, costs, and full account path are not reconstructed.",
    }
    (BASE / "fp-inversion-initial-boundaries.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({"n": len(rows), **summary["inverted"]}))


if __name__ == "__main__":
    main()
