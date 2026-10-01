#!/usr/bin/env python3
"""Evaluate executable quote-side initial boundaries over recovered 24h FP ticks.

This deliberately does not create counterfactual fills, Bank1R cash outcomes, or
an account balance. Missing quotes and broker execution are explicit censoring.
"""

import csv
import gzip
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRIOR = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
OUT = ROOT / "reports/fast-multi-market-v2/three-account-replay-completion-20261001"
SERVER_FORMAT = "%Y.%m.%d %H:%M:%S"
MAX_FRESH_ENTRY_MS = 2000
GAP_MS = 60000


def server_msc(value):
    return int(datetime.strptime(value, SERVER_FORMAT).replace(tzinfo=timezone.utc).timestamp() * 1000)


def read_rows(path):
    with gzip.open(path, "rt", newline="") as stream:
        for row in csv.DictReader(stream):
            yield int(row["time_msc"]), Decimal(row["bid"]), Decimal(row["ask"])


def evaluate_side(path, entry_msc, side, entry_price, distance, end_msc):
    """Return first initial stop/+1R quote crossing, with gap ambiguity visible."""
    peak = Decimal("0")
    trough = Decimal("0")
    first_event = None
    first_ms = None
    first_r = None
    gap_before_event = False
    prev = entry_msc
    last = None
    counted = 0
    for ms, bid, ask in read_rows(path):
        if ms <= entry_msc or ms > end_msc:
            continue
        if ms - prev > GAP_MS and first_event is None:
            gap_before_event = True
        prev = ms
        last = ms
        counted += 1
        if first_event is not None:
            continue
        exit_price = bid if side == 1 else ask
        r = Decimal(side) * (exit_price - entry_price) / distance
        peak = max(peak, r)
        trough = min(trough, r)
        if r <= -1:
            first_event, first_ms, first_r = "INITIAL_STOP_QUOTE_BOUNDARY", ms, r
        elif r >= 1:
            first_event, first_ms, first_r = "PLUS_1R_QUOTE_BOUNDARY", ms, r
    if first_event and gap_before_event:
        status = "BOUNDARY_ORDER_UNRESOLVED_QUOTE_GAP"
    elif first_event:
        status = first_event
    elif gap_before_event:
        status = "NO_BOUNDARY_OBSERVED_WITH_QUOTE_GAP"
    else:
        status = "NO_INITIAL_BOUNDARY_OBSERVED"
    return {
        "status": status,
        "first_observed_boundary": first_event,
        "first_observed_boundary_msc": first_ms,
        "first_observed_boundary_price_r": str(first_r) if first_r is not None else None,
        "peak_price_r_before_first_boundary": str(peak),
        "trough_price_r_before_first_boundary": str(trough),
        "intervening_gap_over_60s": gap_before_event,
        "post_entry_quote_count": counted,
        "last_post_entry_tick_msc": last,
    }


def actual_deals(path):
    groups = defaultdict(list)
    with path.open(newline="") as stream:
        for row in csv.DictReader(stream):
            if row["position_id"] != "0":
                groups[row["position_id"]].append(row)
    return groups


def indexed(path):
    with path.open(newline="") as stream:
        return {row["position_id"]: row for row in csv.DictReader(stream)}


def run():
    request = {row["case_id"].removeprefix("fp24-"): row
               for row in csv.DictReader((OUT / "fp-24h-requests.csv").open(newline=""))}
    coverage = {row["case_id"].removeprefix("fp24-"): row
                for row in csv.DictReader((OUT / "fp-24h-export/path-coverage-three-account-24h.csv").open(newline=""))}
    scores = indexed(PRIOR / "fp-score-trades.csv")
    flows = indexed(PRIOR / "fp-current-flow-entries.csv")
    positions = indexed(PRIOR / "fp-broker-position-ledger.csv")
    deals = actual_deals(PRIOR / "broker-refresh-fp/deals.csv")
    receipt = json.loads((OUT / "fp-24h-export/export-receipt.json").read_text())
    capture_server = receipt["completed_status"].splitlines()[-1].split(",")[3]
    capture_msc = server_msc(capture_server)
    rows = []
    for position, req in sorted(request.items(), key=lambda item: item[1]["from"]):
        ticks = OUT / "fp-ticks" / f"ticks-fp24-{position}.csv.gz"
        legs = deals.get(position, [])
        opens = [r for r in legs if r["entry"] == "0"]
        if len(opens) != 1 or not ticks.exists():
            continue
        opening = opens[0]
        entry_msc = int(opening["time_msc"])
        end_msc = server_msc(req["to"])
        actual_side = 1 if opening["type"] == "0" else -1
        actual_entry = Decimal(opening["price"])
        actual_stop = Decimal(opening["sl"])
        distance = abs(actual_entry - actual_stop)
        anchor = None
        for ms, bid, ask in read_rows(ticks):
            if ms > entry_msc:
                break
            if ms >= entry_msc - MAX_FRESH_ENTRY_MS:
                anchor = ms, bid, ask
        score = scores.get(position, {})
        flow = flows.get(position, {})
        base = positions.get(position, {})
        row = {
            "account": "FP 7404213", "position_id": position, "symbol": opening["symbol"],
            "actual_direction": "BUY" if actual_side == 1 else "SELL",
            "opposite_direction": "SELL" if actual_side == 1 else "BUY",
            "entry_server_msc": entry_msc, "actual_entry_price": str(actual_entry),
            "actual_initial_stop": str(actual_stop), "initial_distance": str(distance),
            "actual_final_cash": base.get("net_cash") or None,
            "actual_final_r": score.get("final_r") or None,
            "actual_exit_class": score.get("exit_class") or None,
            "actual_bank1r_confirmed": score.get("bank1_confirmed") or None,
            "production_admission_score": score.get("admission_score") or None,
            "production_direction_score": score.get("directional_score") or None,
            "production_opposite_score": score.get("opposite_score") or None,
            "causal_flow_at_entry": flow.get("flow_direction") or None,
            "opposite_native_structural_stop": None,
            "opposite_final_cash": None, "opposite_final_r": None,
            "opposite_bank1r_cash_outcome": None,
            "requested_24h_end_server_msc": end_msc,
            "24h_window_elapsed_at_export": capture_msc >= end_msc,
            "export_tick_count": int(coverage[position]["ticks"]),
            "export_error": int(coverage[position]["error"]),
        }
        if anchor is None or distance <= 0:
            row.update({"entry_anchor_status": "UNRESOLVED_BROKER_HISTORY_OR_STOP", "opposite_mirrored_status": "UNRESOLVED_BROKER_HISTORY_OR_STOP"})
        else:
            anchor_ms, anchor_bid, anchor_ask = anchor
            expected_actual = anchor_ask if actual_side == 1 else anchor_bid
            opposite_side = -actual_side
            opposite_entry = anchor_ask if opposite_side == 1 else anchor_bid
            row.update({"entry_anchor_status": "FRESH_QUOTE_WITHIN_2S",
                        "entry_anchor_msc": anchor_ms,
                        "actual_entry_matches_quote_side": expected_actual == actual_entry,
                        "opposite_entry_price": str(opposite_entry),
                        "opposite_mirrored_stop": str(opposite_entry - Decimal(opposite_side) * distance)})
            normal = evaluate_side(ticks, entry_msc, actual_side, actual_entry, distance, end_msc)
            inverse = evaluate_side(ticks, entry_msc, opposite_side, opposite_entry, distance, end_msc)
            row.update({"actual_24h_" + key: value for key, value in normal.items()})
            row.update({"opposite_mirrored_" + key: value for key, value in inverse.items()})
            if inverse["status"] == "NO_INITIAL_BOUNDARY_OBSERVED":
                row["opposite_mirrored_status"] = "RIGHT_CENSORED_AT_24H" if capture_msc >= end_msc else "RIGHT_CENSORED_AT_CAPTURE"
        rows.append(row)
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with (OUT / "fp-24h-opposite-paths.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "schema": "FP_24H_OPPOSITE_QUOTE_BOUNDARY_RECEIPT_V1",
        "positions": len(rows), "total_exported_ticks": sum(r["export_tick_count"] for r in rows),
        "entry_anchor": dict(Counter(r["entry_anchor_status"] for r in rows)),
        "mirrored_opposite_status": dict(Counter(r["opposite_mirrored_status"] for r in rows)),
        "actual_initial_stop_loss_rows": sum(r.get("actual_exit_class") == "INITIAL_STRUCTURAL_STOP_EXIT" for r in rows),
        "opposite_final_cash_coverage": 0,
        "interpretation": "24h executable quote-side initial boundaries only. Beyond the original exit is included. No opposite manager terminal, native stop, broker-valid fill, or exact counterfactual cash is inferred; quote gaps and unavailable entry anchors remain unresolved.",
    }
    (OUT / "fp-24h-opposite-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


if __name__ == "__main__":
    print(json.dumps(run()))
