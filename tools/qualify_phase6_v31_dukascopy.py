#!/usr/bin/env python3
"""Freeze, qualify, and normalize the complete V31 Dukascopy Jetta tick set."""
from __future__ import annotations

import argparse
import calendar
import csv
import gzip
import hashlib
import json
import os
import sqlite3
import struct
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
RAW = Path("/home/tibule12/Datasets/SolTrade/V31/dukascopy-jetta-gzip-raw")
DATASET = Path("/home/tibule12/Datasets/SolTrade/V31")
MANIFESTS = DATASET / "manifests"
NORMALIZED = DATASET / "normalized"
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
EXPECTED_MULTIPLIER = {symbol: (0.001 if symbol == "USDJPY" else 0.00001) for symbol in SYMBOLS}
# UTC acquisition begins two hours before the evaluated server-civil window
# so the UTC+2 winter boundary maps exactly to 2018-01-01 00:00:00.
START = datetime(2017, 12, 31, 22, tzinfo=timezone.utc)
END = datetime(2025, 1, 1, tzinfo=timezone.utc)
SERVER_START_MSC = calendar.timegm((2018, 1, 1, 0, 0, 0)) * 1000
SERVER_END_MSC = calendar.timegm((2025, 1, 1, 0, 0, 0)) * 1000
CALENDAR_HOURS = int((END - START).total_seconds() // 3600)
PARSER_VERSION = "DUKASCOPY_JETTA_DELTA_JSON_V1"
NORMALIZED_VERSION = "SOLTRADE_V31_SERVER_CIVIL_TICK_LE64_I32_I32_V1"
NY = ZoneInfo("America/New_York")
RECORD = struct.Struct("<qii")


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iso_msc(value: int | None) -> str | None:
    if value is None:
        return None
    base = datetime.fromtimestamp(value // 1000, timezone.utc)
    return base.strftime("%Y-%m-%dT%H:%M:%S") + f".{value % 1000:03d}Z"


def civil_msc(value: int | None) -> str | None:
    if value is None:
        return None
    base = datetime.fromtimestamp(value // 1000, timezone.utc)
    return base.strftime("%Y-%m-%d %H:%M:%S") + f".{value % 1000:03d}"


def calendar_hours():
    hour = START
    while hour < END:
        yield hour
        hour += timedelta(hours=1)


def fx_session_open(hour: datetime) -> bool:
    local = hour.astimezone(NY)
    weekday = local.weekday()
    return weekday < 4 or (weekday == 4 and local.hour < 17) or (weekday == 6 and local.hour >= 17)


def expected_hours():
    yield from (hour for hour in calendar_hours() if fx_session_open(hour))


EXPECTED_HOURS = sum(1 for _ in expected_hours())


def path_for(symbol: str, hour: datetime) -> Path:
    return RAW / symbol / f"{hour.year:04d}" / f"{hour.month:02d}" / f"{hour.day:02d}" / f"{hour.hour:02d}h_ticks.json.gz"


def load_ticks(path: Path):
    raw = path.read_bytes()
    decoded = gzip.decompress(raw)
    document = json.loads(decoded)
    keys = ("times", "bids", "asks", "bidVolumes", "askVolumes")
    arrays = [document.get(key) for key in keys]
    if any(not isinstance(array, list) for array in arrays):
        raise ValueError("missing Jetta tick arrays")
    count = len(arrays[0])
    if any(len(array) != count for array in arrays):
        raise ValueError("inconsistent Jetta tick arrays")
    multiplier = float(document["multiplier"])
    scale = round(1.0 / multiplier)
    timestamp = int(document["timestamp"])
    if count:
        if document.get("bid") is None or document.get("ask") is None:
            raise ValueError("missing initial bid or ask")
        bid = round(float(document["bid"]) * scale)
        ask = round(float(document["ask"]) * scale)
    else:
        bid = ask = 0
    ticks = []
    for delta_time, delta_bid, delta_ask in zip(arrays[0], arrays[1], arrays[2]):
        timestamp += int(delta_time)
        bid += int(delta_bid)
        ask += int(delta_ask)
        ticks.append((timestamp, bid, ask))
    return raw, decoded, multiplier, ticks


def journal_database() -> tuple[sqlite3.Connection, int]:
    database = MANIFESTS / "download-journal.sqlite"
    if database.exists():
        database.unlink()
    connection = sqlite3.connect(database)
    connection.execute("create table journal(file text primary key, retrieved text, bytes integer, sha256 text, status text)")
    rows = 0
    journal = RAW / "download-journal.jsonl"
    with journal.open(encoding="utf-8") as handle:
        for line in handle:
            item = json.loads(line)
            if item.get("http_status") != 200:
                continue
            connection.execute(
                "insert or replace into journal values(?,?,?,?,?)",
                (item["file"], item["retrieved_at_utc"], int(item["bytes"]), item["sha256"], "200"),
            )
            rows += 1
    connection.commit()
    return connection, rows


def source_holidays(symbol: str) -> list[tuple[int, int]]:
    code = symbol[:3] + "-" + symbol[3:]
    path = RAW / "_metadata" / f"{code}.json.gz"
    document = json.loads(gzip.decompress(path.read_bytes()))
    return [(int(item["from"]), int(item["till"])) for item in document.get("holidays", [])]


def classify_tick_gap(previous: int, current: int, holidays: list[tuple[int, int]]) -> tuple[str, int]:
    unexplained = 0
    saw_weekend = saw_holiday = False
    cursor = ((previous // 60_000) + 1) * 60_000
    while cursor < current:
        moment = datetime.fromtimestamp(cursor / 1000, timezone.utc)
        if not fx_session_open(moment):
            saw_weekend = True
        elif any(start <= cursor < end for start, end in holidays):
            saw_holiday = True
        else:
            unexplained += 1
        cursor += 60_000
    if unexplained:
        return "UNRESOLVED_OPEN_SESSION_NO_SOURCE_TICKS", unexplained
    if saw_weekend and saw_holiday:
        return "WEEKEND_AND_HOLIDAY_CLOSURE", 0
    if saw_holiday:
        return "SOURCE_METADATA_HOLIDAY_CLOSURE", 0
    return "PREDICTABLE_WEEKEND_CLOSURE", 0


def freeze_raw_manifest() -> dict:
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    manifest = MANIFESTS / "v31-raw-data-manifest.jsonl.gz"
    closure_manifest = MANIFESTS / "v31-predictable-closed-session-hours.jsonl.gz"
    gap_manifest = MANIFESTS / "v31-tick-gap-audit.jsonl.gz"
    summary_path = MANIFESTS / "v31-raw-qualification-summary.json"
    if manifest.exists() or closure_manifest.exists() or gap_manifest.exists() or summary_path.exists():
        raise SystemExit("REFUSE_EXISTING_V31_RAW_MANIFEST")
    run = json.loads((RAW / "download-run.json").read_text())
    if run.get("status") != "COMPLETE" or int(run.get("new_failed", 1)) != 0:
        raise SystemExit("V31_DOWNLOAD_NOT_COMPLETE")
    connection, journal_rows = journal_database()
    symbols = {}
    failures = []
    gap_rows = []
    total_files = total_ticks = total_raw_bytes = total_duplicates = total_closed_without_file = 0
    with closure_manifest.open("wb") as closure_binary:
        with gzip.GzipFile(filename="", mode="wb", fileobj=closure_binary, compresslevel=6, mtime=0) as closed_hours:
            for symbol in SYMBOLS:
                for hour in calendar_hours():
                    path = path_for(symbol, hour)
                    if not fx_session_open(hour) and not path.is_file():
                        closed_hours.write((json.dumps({
                            "schema": "SOLTRADE_PHASE6_V31_PREDICTABLE_CLOSED_SESSION_HOUR_V1",
                            "symbol": symbol,
                            "interval_utc": f"[{hour.isoformat()}, {(hour + timedelta(hours=1)).isoformat()})",
                            "classification": "PREDICTABLE_WEEKEND_CLOSURE",
                            "rule": "Friday 17:00 through Sunday 17:00 America/New_York",
                            "raw_file_requested": False,
                        }, separators=(",", ":"), sort_keys=True) + "\n").encode())
                        total_closed_without_file += 1
    with manifest.open("wb") as binary:
        with gzip.GzipFile(filename="", mode="wb", fileobj=binary, compresslevel=6, mtime=0) as compressed:
            for symbol in SYMBOLS:
                holidays = source_holidays(symbol)
                count = raw_bytes = duplicate_times = crossed = invalid = backward = manifested_files = closed_without_file = 0
                first = final = previous = None
                empty_hours = 0
                multiplier_values = Counter()
                for index, hour in enumerate(calendar_hours(), 1):
                    path = path_for(symbol, hour)
                    if not path.is_file():
                        if fx_session_open(hour):
                            failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": "MISSING_OPEN_SESSION_RAW_FILE"})
                        else:
                            closed_without_file += 1
                        continue
                    file_hash = sha(path)
                    size = path.stat().st_size
                    row = connection.execute("select retrieved,bytes,sha256 from journal where file=?", (str(path),)).fetchone()
                    retrieval = row[0] if row else datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()
                    if row and (int(row[1]) != size or row[2] != file_hash):
                        failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": "DOWNLOAD_JOURNAL_HASH_OR_SIZE_MISMATCH"})
                    try:
                        raw, decoded, multiplier, ticks = load_ticks(path)
                    except Exception as exc:
                        failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": f"PARSE_ERROR:{type(exc).__name__}:{exc}"})
                        continue
                    if not fx_session_open(hour) and ticks:
                        failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": "TICKS_IN_PREDICTABLE_CLOSED_SESSION_HOUR"})
                    multiplier_values[f"{multiplier:.10f}"] += 1
                    if abs(multiplier - EXPECTED_MULTIPLIER[symbol]) > 1e-12:
                        failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": "UNEXPECTED_DECIMAL_MULTIPLIER"})
                    if not ticks:
                        empty_hours += 1
                    hour_start = int(hour.timestamp() * 1000)
                    hour_end = hour_start + 3600 * 1000
                    for timestamp, bid, ask in ticks:
                        if not hour_start <= timestamp < hour_end:
                            failures.append({"symbol": symbol, "hour": hour.isoformat(), "reason": "TICK_OUTSIDE_REQUESTED_HOUR"})
                        if previous is not None:
                            if timestamp < previous:
                                backward += 1
                            elif timestamp == previous:
                                duplicate_times += 1
                            elif timestamp - previous > 3_600_000:
                                classification, unexplained_minutes = classify_tick_gap(previous, timestamp, holidays)
                                gap_rows.append({
                                    "schema": "SOLTRADE_PHASE6_V31_TICK_GAP_AUDIT_V1",
                                    "symbol": symbol,
                                    "previous_tick_utc": iso_msc(previous),
                                    "current_tick_utc": iso_msc(timestamp),
                                    "gap_milliseconds": timestamp - previous,
                                    "classification": classification,
                                    "unexplained_open_session_minutes": unexplained_minutes,
                                    "source_hour_files_complete": True,
                                })
                        previous = timestamp
                        if bid <= 0 or ask <= 0:
                            invalid += 1
                        if bid > ask:
                            crossed += 1
                    if ticks:
                        if first is None:
                            first = ticks[0][0]
                        final = ticks[-1][0]
                    entry = {
                        "schema": "SOLTRADE_PHASE6_V31_RAW_FILE_MANIFEST_V1",
                        "source": "Dukascopy Bank Jetta historical tick service",
                        "retrieval_timestamp_utc": retrieval,
                        "requested_interval_utc": f"[{hour.isoformat()}, {(hour + timedelta(hours=1)).isoformat()})",
                        "symbol": symbol,
                        "relative_file": str(path.relative_to(RAW)),
                        "file_size_bytes": size,
                        "row_count": len(ticks),
                        "first_tick_utc": iso_msc(ticks[0][0]) if ticks else None,
                        "final_tick_utc": iso_msc(ticks[-1][0]) if ticks else None,
                        "sha256": file_hash,
                        "parsing_version": PARSER_VERSION,
                        "detected_timezone": "UTC",
                        "bid_ask_availability": "BOTH" if ticks else "NO_TICKS_IN_SOURCE_HOUR",
                        "content_encoding": "gzip",
                        "decoded_json_bytes": len(decoded),
                    }
                    compressed.write((json.dumps(entry, separators=(",", ":"), sort_keys=True) + "\n").encode())
                    manifested_files += 1
                    count += len(ticks)
                    raw_bytes += size
                    total_files += 1
                    if index % 10000 == 0:
                        print(f"V31_RAW_MANIFEST {symbol} {index}/{CALENDAR_HOURS} ticks={count}", flush=True)
                if crossed or invalid or backward:
                    failures.append({"symbol": symbol, "reason": "INVALID_TICK_VALUES", "crossed": crossed, "zero_or_negative": invalid, "backward": backward})
                symbols[symbol] = {
                    "calendar_hours": CALENDAR_HOURS,
                    "required_open_session_hourly_files": EXPECTED_HOURS,
                    "manifested_raw_files": manifested_files,
                    "predictable_closed_session_hours_without_file": closed_without_file,
                    "tick_count": count,
                    "raw_bytes": raw_bytes,
                    "first_tick_utc": iso_msc(first),
                    "final_tick_utc": iso_msc(final),
                    "empty_source_hours": empty_hours,
                    "duplicate_timestamp_count_retained": duplicate_times,
                    "backward_timestamp_count": backward,
                    "crossed_quote_count": crossed,
                    "zero_or_negative_price_count": invalid,
                    "multiplier_hours": dict(multiplier_values),
                }
                total_ticks += count
                total_raw_bytes += raw_bytes
                total_duplicates += duplicate_times
    connection.close()
    with gap_manifest.open("wb") as gap_binary:
        with gzip.GzipFile(filename="", mode="wb", fileobj=gap_binary, compresslevel=6, mtime=0) as gaps:
            for item in gap_rows:
                gaps.write((json.dumps(item, separators=(",", ":"), sort_keys=True) + "\n").encode())
    manifest_hash = sha(manifest)
    closure_manifest_hash = sha(closure_manifest)
    gap_manifest_hash = sha(gap_manifest)
    gap_classifications = Counter(item["classification"] for item in gap_rows)
    status = "PASS" if total_ticks > 0 and not failures else "FAIL"
    summary = {
        "schema": "SOLTRADE_PHASE6_V31_RAW_QUALIFICATION_SUMMARY_V1",
        "status": status,
        "source": "Dukascopy Bank Jetta historical tick service",
        "requested_interval_utc": f"[{START.isoformat()}, {END.isoformat()})",
        "strategy_evaluation_interval_server_civil": "[2018-01-01 00:00:00, 2025-01-01 00:00:00)",
        "symbols": symbols,
        "required_open_session_hourly_files": EXPECTED_HOURS * len(SYMBOLS),
        "manifested_hourly_files": total_files,
        "calendar_hours_per_symbol": CALENDAR_HOURS,
        "required_open_session_hours_per_symbol": EXPECTED_HOURS,
        "predictable_closed_session_hours_without_file": total_closed_without_file,
        "predictable_closed_session_rule": "Friday 17:00 through Sunday 17:00 America/New_York",
        "total_tick_count": total_ticks,
        "total_raw_bytes": total_raw_bytes,
        "duplicate_timestamp_count_retained": total_duplicates,
        "download_journal_rows_loaded": journal_rows,
        "raw_manifest_path": str(manifest),
        "raw_manifest_sha256": manifest_hash,
        "predictable_closed_session_manifest_path": str(closure_manifest),
        "predictable_closed_session_manifest_sha256": closure_manifest_hash,
        "tick_gap_audit_path": str(gap_manifest),
        "tick_gap_audit_sha256": gap_manifest_hash,
        "tick_gaps_over_one_hour": len(gap_rows),
        "tick_gap_classifications": dict(gap_classifications),
        "unresolved_open_session_gap_count": gap_classifications["UNRESOLVED_OPEN_SESSION_NO_SOURCE_TICKS"],
        "unresolved_open_session_gap_minutes": sum(item["unexplained_open_session_minutes"] for item in gap_rows),
        "unresolved_gap_interpretation": "reported source no-tick intervals, not missing source files; every required open-session hourly response remains mandatory",
        "parsing_version": PARSER_VERSION,
        "failures": failures[:1000],
        "failure_count": len(failures),
        "pnl_viewed": False,
    }
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    os.chmod(manifest, 0o444)
    os.chmod(closure_manifest, 0o444)
    os.chmod(gap_manifest, 0o444)
    os.chmod(summary_path, 0o444)
    print(json.dumps({"status": status, "files": total_files, "ticks": total_ticks, "raw_bytes": total_raw_bytes, "failures": len(failures)}, sort_keys=True), flush=True)
    if status != "PASS":
        raise SystemExit("V31_RAW_DATA_QUALIFICATION_FAILED")
    return summary


def server_time_msc(utc_msc: int) -> int:
    utc = datetime.fromtimestamp(utc_msc // 1000, timezone.utc)
    offset_ms = int((utc.astimezone(NY).utcoffset().total_seconds() + 7 * 3600) * 1000)
    return utc_msc + offset_ms


def normalize(summary: dict) -> dict:
    NORMALIZED.mkdir(parents=True, exist_ok=True)
    manifest_path = MANIFESTS / "v31-normalized-data-manifest.json"
    if manifest_path.exists():
        raise SystemExit("REFUSE_EXISTING_V31_NORMALIZED_MANIFEST")
    results = {}
    for symbol in SYMBOLS:
        output = NORMALIZED / f"{symbol}.v31ticks.gz"
        if output.exists():
            raise SystemExit(f"REFUSE_EXISTING_NORMALIZED_{symbol}")
        count = duplicate_server = backward_server = excluded_before = excluded_after = 0
        first_server = final_server = previous_server = None
        unique_h1 = set()
        with output.open("wb") as binary:
            with gzip.GzipFile(filename="", mode="wb", fileobj=binary, compresslevel=6, mtime=0) as compressed:
                for index, hour in enumerate(calendar_hours(), 1):
                    source_path = path_for(symbol, hour)
                    if not source_path.is_file():
                        if fx_session_open(hour):
                            raise SystemExit(f"V31_NORMALIZATION_MISSING_OPEN_HOUR_{symbol}_{hour.isoformat()}")
                        continue
                    _, _, _, ticks = load_ticks(source_path)
                    for utc_msc, bid, ask in ticks:
                        server_msc = server_time_msc(utc_msc)
                        if server_msc < SERVER_START_MSC:
                            excluded_before += 1
                            continue
                        if server_msc >= SERVER_END_MSC:
                            excluded_after += 1
                            continue
                        if previous_server is not None:
                            if server_msc < previous_server:
                                backward_server += 1
                            elif server_msc == previous_server:
                                duplicate_server += 1
                        previous_server = server_msc
                        if first_server is None:
                            first_server = server_msc
                        final_server = server_msc
                        unique_h1.add(server_msc // 3_600_000)
                        compressed.write(RECORD.pack(server_msc, bid, ask))
                        count += 1
                    if index % 10000 == 0:
                        print(f"V31_NORMALIZE {symbol} {index}/{CALENDAR_HOURS} ticks={count}", flush=True)
        result = {
            "canonical_symbol": symbol,
            "research_symbol": symbol + ".V31",
            "path": str(output),
            "sha256": sha(output),
            "bytes": output.stat().st_size,
            "record_size_bytes": RECORD.size,
            "record_count": count,
            "first_server_civil_tick": civil_msc(first_server),
            "final_server_civil_tick": civil_msc(final_server),
            "duplicate_server_timestamp_count_retained": duplicate_server,
            "backward_server_timestamp_count": backward_server,
            "source_ticks_excluded_before_server_interval": excluded_before,
            "source_ticks_excluded_at_or_after_2025_server_civil_cutoff": excluded_after,
            "tick_derived_h1_bars": len(unique_h1),
            "format": NORMALIZED_VERSION,
            "timezone_conversion": "UTC -> America/New_York civil time -> plus seven civil hours",
        }
        if count + excluded_before + excluded_after != summary["symbols"][symbol]["tick_count"] or backward_server:
            raise SystemExit(f"V31_NORMALIZATION_FAILED_{symbol}")
        results[symbol] = result
        os.chmod(output, 0o444)
        print(f"V31_NORMALIZED {symbol} ticks={count} bytes={result['bytes']} sha256={result['sha256']}", flush=True)
    manifest = {
        "schema": "SOLTRADE_PHASE6_V31_NORMALIZED_DATA_MANIFEST_V1",
        "status": "PASS",
        "raw_manifest_sha256": summary["raw_manifest_sha256"],
        "format": NORMALIZED_VERSION,
        "record_layout": "little-endian signed int64 server civil time milliseconds, signed int32 bid points, signed int32 ask points",
        "normalized_interval_server_civil": "[2018-01-01 00:00:00, 2025-01-01 00:00:00)",
        "duplicate_policy": "retain every source row in source order",
        "symbols": results,
        "pnl_viewed": False,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    os.chmod(manifest_path, 0o444)
    return manifest


def copy_summaries_to_repository() -> None:
    for name in ("v31-raw-qualification-summary.json", "v31-normalized-data-manifest.json"):
        source = MANIFESTS / name
        destination = OUT / name
        destination.write_bytes(source.read_bytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-only", action="store_true")
    args = parser.parse_args()
    source_metadata_path = MANIFESTS / "v31-source-metadata-manifest.json"
    if not source_metadata_path.is_file() or json.loads(source_metadata_path.read_text()).get("status") != "PASS":
        raise SystemExit("V31_SOURCE_METADATA_NOT_FROZEN_OR_INVALID")
    summary = freeze_raw_manifest()
    if not args.manifest_only:
        normalize(summary)
    copy_summaries_to_repository()


if __name__ == "__main__":
    main()
