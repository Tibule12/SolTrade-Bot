"""Join recovered FP 24-hour quote paths to native-stop provenance.

The output is coverage evidence, not an inversion profit backtest. In
particular a mirrored +1R quote crossing is not a cash Bank1R and is never a
terminal opposite-trade outcome. No alternative final R or cash is imputed.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from decimal import Decimal, InvalidOperation
from pathlib import Path


FIELDS = (
    "account", "position_id", "symbol", "actual_direction", "opposite_direction",
    "actual_initial_stop_loss", "actual_final_cash", "actual_final_r",
    "entry_anchor_status", "twentyfour_hour_quote_window_complete", "quote_export_error",
    "mirrored_boundary_status", "mirrored_boundary_time_msc",
    "mirrored_quote_gap_ambiguous", "native_stop_status", "native_stop_exact",
    "native_opposite_stop_price", "native_stop_unresolved_reason",
    "opposite_exact_status", "opposite_exact_final_cash",
    "opposite_exact_final_r", "missing_for_exact_opposite_path",
)


def _rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _native_exact(stop: dict[str, str]) -> bool:
    if stop["native_opposite_status"] != "NATIVE_OPPOSITE_STRUCTURE_RECONSTRUCTED":
        return False
    if stop["historical_broker_floor_available"].lower() != "true":
        return False
    try:
        price = Decimal(stop["exact_native_stop_price"])
    except (InvalidOperation, ValueError):
        return False
    return price.is_finite() and price > 0


def build_coverage(quote_rows: list[dict[str, str]], native_rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], dict]:
    native = {row["position_id"]: row for row in native_rows}
    if len(native) != len(native_rows):
        raise ValueError("Duplicate native-stop position ID")
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    for quote in quote_rows:
        pid = quote["position_id"]
        if pid in seen:
            raise ValueError("Duplicate 24h quote position ID")
        seen.add(pid)
        if pid not in native:
            raise ValueError(f"Native-stop row absent for position {pid}")
        stop = native[pid]
        if (quote["account"], quote["symbol"]) != (stop["account"], stop["symbol"]):
            raise ValueError(f"Account or symbol mismatch at {pid}")
        actual_loss = stop["is_fourteen_stop_loss"].lower() == "true"
        quote_missing = quote["entry_anchor_status"] != "FRESH_QUOTE_WITHIN_2S" or quote["export_error"] != "0"
        native_exact = _native_exact(stop)
        if quote_missing:
            exact_status = "UNRESOLVED_BROKER_HISTORY"
            reason = f"entry_quote_or_export:{quote['entry_anchor_status']};error={quote['export_error']}"
        elif not native_exact:
            exact_status = "UNRESOLVED_NATIVE_STOP"
            reason = stop["unresolved_reason"] or "NATIVE_OPPOSITE_STOP_NOT_RECONCILED"
        elif quote["24h_window_elapsed_at_export"] != "True":
            exact_status = "RIGHT_CENSORED"
            reason = "QUOTE_WINDOW_NOT_YET_24_HOURS"
        else:
            # Even a genuinely reconstructed native initial stop and 24h
            # quotes do not reconstruct cash Bank1R, structure-driven runner
            # modifications, discretionary exits or broker-valid fills.
            exact_status = "UNRESOLVED_MANAGER_AND_EXECUTION"
            reason = "CASH_BANK1R_RUNNER_RESCORING_OWNERSHIP_AND_ALTERNATIVE_FILLS_UNPROVEN"
        out.append({
            "account": quote["account"], "position_id": pid, "symbol": quote["symbol"],
            "actual_direction": quote["actual_direction"],
            "opposite_direction": quote["opposite_direction"],
            "actual_initial_stop_loss": str(actual_loss).lower(),
            "actual_final_cash": quote["actual_final_cash"],
            "actual_final_r": quote["actual_final_r"],
            "entry_anchor_status": quote["entry_anchor_status"],
            "twentyfour_hour_quote_window_complete": quote["24h_window_elapsed_at_export"].lower(),
            "quote_export_error": quote["export_error"],
            "mirrored_boundary_status": quote["opposite_mirrored_status"],
            "mirrored_boundary_time_msc": quote["opposite_mirrored_first_observed_boundary_msc"],
            "mirrored_quote_gap_ambiguous": quote["opposite_mirrored_intervening_gap_over_60s"].lower(),
            "native_stop_status": stop["native_opposite_status"],
            "native_stop_exact": str(native_exact).lower(),
            "native_opposite_stop_price": stop["exact_native_stop_price"] if native_exact else "",
            "native_stop_unresolved_reason": stop["unresolved_reason"],
            "opposite_exact_status": exact_status,
            "opposite_exact_final_cash": "",
            "opposite_exact_final_r": "",
            "missing_for_exact_opposite_path": reason,
        })
    if set(native) != seen:
        raise ValueError("Native-stop rows exist without matching 24h quote rows")
    losses = [row for row in out if row["actual_initial_stop_loss"] == "true"]
    receipt = {
        "schema": "FP_24H_NATIVE_OPPOSITE_EXACT_COVERAGE_V1",
        "all_actual_entries": len(out),
        "initial_stop_loss_entries": len(losses),
        "fresh_entry_quote_count": sum(row["entry_anchor_status"] == "FRESH_QUOTE_WITHIN_2S" for row in out),
        "full_24h_quote_window_count": sum(row["twentyfour_hour_quote_window_complete"] == "true" for row in out),
        "native_stop_exact_count": sum(row["native_stop_exact"] == "true" for row in out),
        "opposite_exact_final_result_count": sum(bool(row["opposite_exact_final_cash"]) for row in out),
        "all_status_counts": dict(sorted(Counter(row["opposite_exact_status"] for row in out).items())),
        "initial_stop_loss_status_counts": dict(sorted(Counter(row["opposite_exact_status"] for row in losses).items())),
        "initial_stop_loss_mirrored_quote_boundary_counts": dict(sorted(Counter(row["mirrored_boundary_status"] for row in losses).items())),
        "note": "Mirrored quote boundaries are diagnostic. No opposite-side cash Bank1R, final R or account balance is imputed.",
    }
    return out, receipt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quotes", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()
    rows, receipt = build_coverage(_rows(args.quotes), _rows(args.native))
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    args.json.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
