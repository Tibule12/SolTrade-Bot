#!/usr/bin/env python3
"""Freeze the non-trading Phase 6 MT5 history-acquisition evidence.

The tool reads broker cache files and collector CSVs. It never starts MT5,
requests history, launches a tester run, or copies raw tick/bar caches.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
from datetime import datetime, time, timedelta, timezone
from pathlib import Path


START_MONTH = "202401"
END_MONTH_EXCLUSIVE = "202607"
EXPECTED_MONTHS = tuple(
    f"{year:04d}{month:02d}"
    for year in range(2024, 2027)
    for month in range(1, 13)
    if f"{year:04d}{month:02d}" < END_MONTH_EXCLUSIVE
)
ACQUISITION_FILES = (
    "monthly_ticks.csv",
    "daily_ticks.csv",
    "tick_gaps.csv",
    "m1_bars.csv",
    "symbol_specification.csv",
    "trading_sessions.csv",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_timestamp(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S.%f").replace(
        tzinfo=timezone.utc
    )


def parse_log_clock(value: str) -> time:
    return datetime.strptime(value, "%H:%M:%S.%f").time()


def decode_mt5_log(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe"):
        return raw.decode("utf-16")
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        return raw.decode("utf-8")


def next_month(value: str) -> str:
    year = int(value[:4])
    month = int(value[4:])
    month += 1
    if month == 13:
        year += 1
        month = 1
    return f"{year:04d}{month:02d}"


def choose_replacement_range(
    earliest: datetime,
    final: datetime,
    candidate_gaps: list[dict[str, str]],
) -> tuple[str, str]:
    segments: list[tuple[datetime, datetime]] = []
    cursor = earliest
    for gap in candidate_gaps:
        gap_start = parse_timestamp(gap["gap_start"])
        gap_end = parse_timestamp(gap["gap_end"])
        if gap_start > cursor:
            segments.append((cursor, gap_start))
        cursor = max(cursor, gap_end)
    if final > cursor:
        segments.append((cursor, final))
    longest_start, longest_end = max(
        segments, key=lambda segment: segment[1] - segment[0]
    )

    safe_start = longest_start.replace(hour=0, minute=0, second=0, microsecond=0)
    if longest_start != safe_start:
        safe_start += timedelta(days=1)
    safe_end = longest_end.replace(hour=0, minute=0, second=0, microsecond=0)
    if safe_end <= safe_start:
        raise ValueError("no full-day continuous replacement interval exists")
    return safe_start.date().isoformat(), safe_end.date().isoformat()


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=fieldnames, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ticks-dir", type=Path, required=True)
    parser.add_argument("--history-dir", type=Path, required=True)
    parser.add_argument("--acquisition-dir", type=Path, required=True)
    parser.add_argument("--mql-log", type=Path, required=True)
    parser.add_argument("--run-start-clock", required=True)
    parser.add_argument("--run-end-clock", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()

    arguments.output_dir.mkdir(parents=True, exist_ok=True)

    monthly_path = arguments.acquisition_dir / "monthly_ticks.csv"
    with monthly_path.open(newline="", encoding="utf-8") as handle:
        monthly_rows = list(csv.DictReader(handle))
    monthly_by_key = {
        row["month_start"][:7].replace(".", ""): row for row in monthly_rows
    }

    tick_rows: list[dict[str, object]] = []
    identity_entries: list[tuple[str, Path]] = []
    missing_months: list[str] = []
    for month_key in EXPECTED_MONTHS:
        tick_path = arguments.ticks_dir / f"{month_key}.tkc"
        row = monthly_by_key.get(month_key)
        if not tick_path.is_file() or row is None:
            missing_months.append(month_key)
            continue
        tick_rows.append(
            {
                "month": month_key,
                "interval_start_inclusive": row["month_start"],
                "interval_end_exclusive": row["month_end_exclusive"],
                "tick_count": row["tick_count"],
                "earliest_tick": row["earliest_tick"],
                "final_tick": row["final_tick"],
                "weekday_zero_tick_days": row["weekday_zero_tick_days"],
                "copy_failures": row["copy_failures"],
                "tkc_size_bytes": tick_path.stat().st_size,
                "tkc_sha256": sha256(tick_path),
            }
        )
        identity_entries.append((f"canonical-real-ticks/{tick_path.name}", tick_path))

    tick_inventory_path = arguments.output_dir / "tick-inventory.csv"
    write_csv(
        tick_inventory_path,
        [
            "month",
            "interval_start_inclusive",
            "interval_end_exclusive",
            "tick_count",
            "earliest_tick",
            "final_tick",
            "weekday_zero_tick_days",
            "copy_failures",
            "tkc_size_bytes",
            "tkc_sha256",
        ],
        tick_rows,
    )

    bar_rows: list[dict[str, object]] = []
    for relative in ("2024.hcc", "2025.hcc", "2026.hcc", "cache/H1.hc"):
        path = arguments.history_dir / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        logical = f"m1-hcc-bars/{relative}"
        bar_rows.append(
            {
                "logical_name": logical,
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
        identity_entries.append((logical, path))
    bar_inventory_path = arguments.output_dir / "bar-inventory.csv"
    write_csv(
        bar_inventory_path,
        ["logical_name", "size_bytes", "sha256"],
        bar_rows,
    )

    collector_dir = arguments.output_dir / "collector"
    collector_dir.mkdir(parents=True, exist_ok=True)
    for name in ACQUISITION_FILES:
        source = arguments.acquisition_dir / name
        if not source.is_file():
            raise FileNotFoundError(source)
        path = collector_dir / name
        path.write_text(
            "\n".join(source.read_text(encoding="utf-8").splitlines()) + "\n",
            encoding="utf-8",
        )
        identity_entries.append((f"acquisition-artifacts/{name}", source))

    with (arguments.acquisition_dir / "tick_gaps.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        all_gaps = list(csv.DictReader(handle))
    candidate_gaps = [
        row
        for row in all_gaps
        if row["classification"] == "IN_SESSION_CANDIDATE_GAP"
    ]
    candidate_path = arguments.output_dir / "candidate-gaps.csv"
    write_csv(
        candidate_path,
        ["schema", "gap_start", "gap_end", "gap_seconds", "classification"],
        candidate_gaps,
    )

    start_clock = parse_log_clock(arguments.run_start_clock)
    end_clock = parse_log_clock(arguments.run_end_clock)
    messages: list[str] = []
    for line in decode_mt5_log(arguments.mql_log).splitlines():
        fields = line.split("\t")
        if len(fields) < 5:
            continue
        try:
            clock = parse_log_clock(fields[2])
        except ValueError:
            continue
        if not (start_clock <= clock <= end_clock):
            continue
        if "SolTradePhase6HistoryAcquisition" not in fields[3]:
            continue
        if "SOLTRADE_" not in fields[4]:
            continue
        messages.append(
            f"{fields[2]} | {fields[3]} | {fields[4]}"
        )
    messages_path = arguments.output_dir / "broker-download-messages.txt"
    messages_path.write_text("\n".join(messages) + "\n", encoding="utf-8")

    identity_entries.extend(
        (
            ("derived/tick-inventory.csv", tick_inventory_path),
            ("derived/bar-inventory.csv", bar_inventory_path),
            ("derived/candidate-gaps.csv", candidate_path),
            ("derived/broker-download-messages.txt", messages_path),
        )
    )
    inventory_lines = [
        f"{sha256(path)} {path.stat().st_size} {logical}"
        for logical, path in sorted(identity_entries)
    ]
    aggregate_path = arguments.output_dir / "aggregate-history-identity.sha256"
    aggregate_path.write_text("\n".join(inventory_lines) + "\n", encoding="utf-8")
    aggregate_hash = sha256(aggregate_path)

    with (arguments.acquisition_dir / "m1_bars.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        m1_rows = list(csv.DictReader(handle))
    available_m1 = [row for row in m1_rows if int(row["bar_count"]) > 0]
    with (arguments.acquisition_dir / "symbol_specification.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        specification = {
            row["field"]: row["value"] for row in csv.DictReader(handle)
        }

    earliest = parse_timestamp(tick_rows[0]["earliest_tick"])
    final = parse_timestamp(tick_rows[-1]["final_tick"])
    continuous_start, replacement_end = choose_replacement_range(
        earliest, final, candidate_gaps
    )
    replacement_start = (
        datetime.fromisoformat(continuous_start).date() + timedelta(days=14)
    ).isoformat()
    total_ticks = sum(int(row["tick_count"]) for row in tick_rows)
    tick_copy_failures = sum(int(row["copy_failures"]) for row in tick_rows)
    zero_tick_weekdays = sum(
        int(row["weekday_zero_tick_days"]) for row in tick_rows
    )
    proposed_continuous = (
        not missing_months
        and tick_copy_failures == 0
        and zero_tick_weekdays == 0
        and not candidate_gaps
    )
    status = (
        "TICK_HISTORY_CONTINUOUS_FOR_PROPOSED_MATRIX"
        if proposed_continuous
        else "HISTORY_UNAVAILABLE_FOR_PROPOSED_MATRIX"
    )
    result = {
        "schema": "SOLTRADE_PHASE6_IMMUTABLE_HISTORY_IDENTITY_V1",
        "status": status,
        "execution_authorized": False,
        "proposed_interval": {
            "start_inclusive": "2024-01-01T00:00:00Z",
            "end_exclusive": "2026-07-01T00:00:00Z",
            "expected_months": len(EXPECTED_MONTHS),
            "present_months": len(tick_rows),
            "missing_months": missing_months,
            "total_real_ticks": total_ticks,
            "earliest_real_tick": earliest.isoformat().replace("+00:00", "Z"),
            "final_real_tick": final.isoformat().replace("+00:00", "Z"),
            "tick_copy_failures": tick_copy_failures,
            "weekday_zero_tick_days": zero_tick_weekdays,
            "in_session_candidate_gap_count": len(candidate_gaps),
            "continuous": proposed_continuous,
        },
        "m1_hcc": {
            "raw_hcc_and_h1_cache_files": bar_rows,
            "copyrates_access_status": "INCOMPLETE",
            "copyrates_first_available_bar": (
                available_m1[0]["earliest_bar"] if available_m1 else "UNAVAILABLE"
            ),
            "copyrates_final_available_bar": (
                available_m1[-1]["final_bar"] if available_m1 else "UNAVAILABLE"
            ),
            "copyrates_failure_days": sum(
                1 for row in m1_rows if int(row["copy_error"]) != 0
            ),
        },
        "broker_metadata": {
            "server": specification["server"],
            "company": specification["company"],
            "symbol": specification["symbol"],
            "terminal_build": int(specification["terminal_build"]),
            "symbol_specification_sha256": sha256(
                arguments.acquisition_dir / "symbol_specification.csv"
            ),
            "trading_sessions_sha256": sha256(
                arguments.acquisition_dir / "trading_sessions.csv"
            ),
        },
        "aggregate_history_identity": {
            "manifest_file": aggregate_path.name,
            "sha256": aggregate_hash,
            "entry_count": len(identity_entries),
        },
        "replacement_range_proposal": {
            "manifest_id": "PHASE6-PROPOSED-V2",
            "status": "REVIEW_REQUIRED_NOT_AUTHORIZED",
            "basis": (
                "longest full-day interval between recorded in-session "
                "candidate gaps, with a separate deterministic 14-calendar-day "
                "indicator warm-up allowance; no strategy result was viewed"
            ),
            "continuous_cache_start_inclusive": (
                f"{continuous_start}T00:00:00Z"
            ),
            "warmup_start_inclusive": f"{continuous_start}T00:00:00Z",
            "warmup_end_exclusive": f"{replacement_start}T00:00:00Z",
            "start_inclusive": f"{replacement_start}T00:00:00Z",
            "end_exclusive": f"{replacement_end}T00:00:00Z",
        },
        "broker_message_count": len(messages),
    }
    identity_path = arguments.output_dir / "history-identity.json"
    identity_path.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(status)
    print(f"Aggregate history identity: {aggregate_hash}")
    print(
        "Replacement proposal: "
        f"[{replacement_start},{replacement_end})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
