"""Build the 14 FP stop-loss evidence rows without inventing opposite P/L."""

from __future__ import annotations

import argparse
import csv
import gzip
import json
from collections import Counter
from decimal import Decimal as D
from pathlib import Path

from .fp_coverage import build_coverage


FIELDS = (
    "account", "position_id", "symbol", "actual_direction", "opposite_direction",
    "actual_result_cash", "actual_result_r", "production_admission_score",
    "production_direction_score", "production_opposite_score", "causal_flow_at_entry",
    "actual_initial_stop_price", "native_opposite_stop_price_exact",
    "native_opposite_stop_status", "native_opposite_stop_diagnostic_only",
    "actual_quote_mfe_price_r_before_first_boundary",
    "actual_quote_mae_price_r_before_first_boundary",
    "opposite_native_initial_boundary_status", "opposite_native_initial_boundary_time_msc",
    "opposite_native_initial_boundary_price_r",
    "opposite_native_quote_mfe_price_r_before_first_boundary",
    "opposite_native_quote_mae_price_r_before_first_boundary",
    "opposite_mirrored_quote_mfe_price_r_before_first_boundary",
    "opposite_mirrored_quote_mae_price_r_before_first_boundary",
    "actual_raw_24h_mfe_price_r", "actual_raw_24h_mae_price_r",
    "opposite_raw_24h_mfe_price_r", "opposite_raw_24h_mae_price_r",
    "raw_24h_quote_count", "raw_24h_window_complete",
    "actual_bank1r_confirmed", "opposite_cash_bank1r_status",
    "opposite_mirrored_first_boundary", "opposite_final_cash_exact",
    "opposite_final_r_exact", "exact_result_status", "missing_for_exact_result",
)


def _read(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def raw_path_extrema(
    ticks: list[tuple[int, D, D]], entry_msc: int, end_msc: int,
    entry_price: D, direction: str, distance: D,
) -> tuple[str, str, int]:
    """Raw quote-only R extrema, including movement after hypothetical stop.

    This is a market path diagnostic. It must never be interpreted as a
    realizable MFE/MAE once any management path has terminated.
    """
    if direction not in ("BUY", "SELL") or distance <= 0:
        raise ValueError("Invalid direction or initial R distance")
    sign = D(1) if direction == "BUY" else D(-1)
    favorable = adverse = D(0)
    count = 0
    for at, bid, ask in ticks:
        if at < entry_msc or at > end_msc:
            continue
        if bid <= 0 or ask < bid:
            raise ValueError("Invalid broker bid/ask quote")
        close_side = bid if direction == "BUY" else ask
        r = sign * (close_side - entry_price) / distance
        favorable = max(favorable, r)
        adverse = min(adverse, r)
        count += 1
    return (str(favorable), str(adverse), count) if count else ("", "", 0)


def read_gzip_ticks(path: Path) -> list[tuple[int, D, D]]:
    rows: list[tuple[int, D, D]] = []
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            rows.append((int(row["time_msc"]), D(row["bid"]), D(row["ask"])))
    if any(a[0] > b[0] for a, b in zip(rows, rows[1:])):
        raise ValueError(f"Decreasing broker tick timestamps: {path}")
    return rows


def native_initial_boundary(
    ticks: list[tuple[int, D, D]], *, entry_msc: int, end_msc: int,
    entry_price: D, stop_price: D, direction: str, window_complete: bool,
    max_continuous_gap_ms: int = 60_000,
) -> tuple[str, str, str, str, str]:
    """First *observed* native-geometry quote boundary; never a trade fill.

    A >60-second market/quote gap before the first crossing makes order
    unknowable even if the next quote lies beyond one level. We continue to
    record raw market extrema separately, but return an ambiguous boundary.
    """
    if direction not in ("BUY", "SELL") or entry_price <= 0 or stop_price <= 0:
        raise ValueError("Native entry, stop and direction required")
    sign = D(1) if direction == "BUY" else D(-1)
    distance = sign * (entry_price - stop_price)
    if distance <= 0:
        raise ValueError("Native stop must be adverse to direction")
    peak = trough = D(0)
    previous = entry_msc
    gap_seen = False
    count = 0
    for at, bid, ask in ticks:
        if at < entry_msc or at > end_msc:
            continue
        if bid <= 0 or ask < bid:
            raise ValueError("Invalid quote")
        if at - previous > max_continuous_gap_ms:
            gap_seen = True
        previous = at
        close_side = bid if direction == "BUY" else ask
        r = sign * (close_side - entry_price) / distance
        peak = max(peak, r)
        trough = min(trough, r)
        count += 1
        if r <= -ONE or r >= ONE:
            if gap_seen:
                return ("BOUNDARY_ORDER_UNRESOLVED_QUOTE_GAP", str(at), str(r), str(peak), str(trough))
            return ("INITIAL_STOP_QUOTE_BOUNDARY" if r <= -ONE else "PLUS_1R_QUOTE_BOUNDARY",
                    str(at), str(r), str(peak), str(trough))
    if not count:
        return "UNRESOLVED_BROKER_HISTORY", "", "", "", ""
    return ("RIGHT_CENSORED_AT_24H" if window_complete else "RIGHT_CENSORED_PENDING_24H",
            "", "", str(peak), str(trough))


ONE = D(1)


def build_loss_table(
    quotes: list[dict[str, str]], native: list[dict[str, str]], tick_dir: Path,
) -> tuple[list[dict[str, str]], dict]:
    coverage, _ = build_coverage(quotes, native)
    by_quote = {row["position_id"]: row for row in quotes}
    by_native = {row["position_id"]: row for row in native}
    losses = [row for row in coverage if row["actual_initial_stop_loss"] == "true"]
    out: list[dict[str, str]] = []
    for covered in losses:
        pid = covered["position_id"]
        q = by_quote[pid]
        n = by_native[pid]
        tick_path = tick_dir / f"ticks-fp24-{pid}.csv.gz"
        if not tick_path.exists():
            raise FileNotFoundError(f"Missing uncompressed or compressed 24h tick shard: {tick_path}")
        ticks = read_gzip_ticks(tick_path)
        entry_msc = int(q["entry_server_msc"])
        end_msc = int(q["requested_24h_end_server_msc"])
        distance = D(q["initial_distance"])
        actual_mfe, actual_mae, count = raw_path_extrema(
            ticks, entry_msc, end_msc, D(q["actual_entry_price"]), q["actual_direction"], distance,
        )
        opposite_mfe = opposite_mae = ""
        if q["opposite_entry_price"]:
            opposite_mfe, opposite_mae, _ = raw_path_extrema(
                ticks, entry_msc, end_msc, D(q["opposite_entry_price"]),
                q["opposite_direction"], distance,
            )
        native_status = native_at = native_r = native_mfe = native_mae = ""
        if n["native_opposite_status"].startswith("NATIVE_STRUCTURE_RECONSTRUCTED"):
            native_status, native_at, native_r, native_mfe, native_mae = native_initial_boundary(
                ticks, entry_msc=entry_msc, end_msc=end_msc,
                entry_price=D(n["native_opposite_entry"]),
                stop_price=D(n["native_opposite_stop"]),
                direction=q["opposite_direction"],
                window_complete=q["24h_window_elapsed_at_export"] == "True",
            )
        out.append({
            "account": q["account"], "position_id": pid, "symbol": q["symbol"],
            "actual_direction": q["actual_direction"], "opposite_direction": q["opposite_direction"],
            "actual_result_cash": q["actual_final_cash"], "actual_result_r": q["actual_final_r"],
            "production_admission_score": q["production_admission_score"],
            "production_direction_score": q["production_direction_score"],
            "production_opposite_score": q["production_opposite_score"],
            "causal_flow_at_entry": q["causal_flow_at_entry"],
            "actual_initial_stop_price": q["actual_initial_stop"],
            "native_opposite_stop_price_exact": covered["native_opposite_stop_price"],
            "native_opposite_stop_status": n["native_opposite_status"],
            "native_opposite_stop_diagnostic_only": n["native_opposite_stop"] if not covered["native_opposite_stop_price"] else "",
            "actual_quote_mfe_price_r_before_first_boundary": q["actual_24h_peak_price_r_before_first_boundary"],
            "actual_quote_mae_price_r_before_first_boundary": q["actual_24h_trough_price_r_before_first_boundary"],
            "opposite_native_initial_boundary_status": native_status,
            "opposite_native_initial_boundary_time_msc": native_at,
            "opposite_native_initial_boundary_price_r": native_r,
            "opposite_native_quote_mfe_price_r_before_first_boundary": native_mfe,
            "opposite_native_quote_mae_price_r_before_first_boundary": native_mae,
            "opposite_mirrored_quote_mfe_price_r_before_first_boundary": q["opposite_mirrored_peak_price_r_before_first_boundary"],
            "opposite_mirrored_quote_mae_price_r_before_first_boundary": q["opposite_mirrored_trough_price_r_before_first_boundary"],
            "actual_raw_24h_mfe_price_r": actual_mfe,
            "actual_raw_24h_mae_price_r": actual_mae,
            "opposite_raw_24h_mfe_price_r": opposite_mfe,
            "opposite_raw_24h_mae_price_r": opposite_mae,
            "raw_24h_quote_count": str(count),
            "raw_24h_window_complete": covered["twentyfour_hour_quote_window_complete"],
            "actual_bank1r_confirmed": q["actual_bank1r_confirmed"],
            "opposite_cash_bank1r_status": "UNRESOLVED_CASH_TRIGGER_AND_BROKER_PARTIAL",
            "opposite_mirrored_first_boundary": q["opposite_mirrored_status"],
            "opposite_final_cash_exact": "", "opposite_final_r_exact": "",
            "exact_result_status": covered["opposite_exact_status"],
            "missing_for_exact_result": covered["missing_for_exact_opposite_path"],
        })
    receipt = {
        "schema": "FP_14_INITIAL_STOP_LOSS_OPPOSITE_EVIDENCE_V1",
        "rows": len(out),
        "raw_24h_tick_rows_used": sum(int(row["raw_24h_quote_count"]) for row in out),
        "exact_opposite_final_results": 0,
        "native_initial_boundary_status_counts": dict(sorted(Counter(
            row["opposite_native_initial_boundary_status"] for row in out
        ).items())),
        "raw_extrema_include_post_stop_quotes": True,
        "mirrored_boundary_is_not_bank1r_or_final_cash": True,
        "native_stop_diagnostic_is_not_execution_stop": True,
    }
    return out, receipt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quotes", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--ticks", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    args = parser.parse_args()
    rows, receipt = build_loss_table(_read(args.quotes), _read(args.native), args.ticks)
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    args.json.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
