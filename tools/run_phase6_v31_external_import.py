#!/usr/bin/env python3
"""Stage normalized V31 ticks, import them, and retain exact MT5 parity evidence."""
from __future__ import annotations

import csv
import gzip
import hashlib
import json
import os
import shutil
import struct
import subprocess
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2/mt5-custom-symbol-import"
MANIFEST = Path("/home/tibule12/Datasets/SolTrade/V31/manifests/v31-normalized-data-manifest.json")
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31-external"
EX5 = WORK / "SolTradeV31ExternalTickImporter.ex5"
EX5_SHA256 = "cb3495eec5cba2b56a90c58834ca83e02feccc5fc2b80fdfa0e5e35cdad19f5c"
IMPORT_ROOT = COMMON / "SolTrade/Phase6/V31ExternalImport"
RUNTIME_ROOT = COMMON / "SolTrade/Phase6/V31ExternalImportEvidence"
RECORD = struct.Struct("<qii")
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def day_name(server_msc: int) -> str:
    return datetime.fromtimestamp(server_msc // 1000, timezone.utc).strftime("%Y-%m-%d")


def stage(symbol: str, normalized: Path) -> tuple[Path, int, int]:
    destination = IMPORT_ROOT / symbol
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    day = datetime(2018, 1, 1, tzinfo=timezone.utc)
    while day < datetime(2025, 1, 1, tzinfo=timezone.utc):
        (destination / (day.strftime("%Y-%m-%d") + ".bin")).touch()
        day += timedelta(days=1)
    count = 0
    current_day = None
    handle = None
    with gzip.open(normalized, "rb") as source:
        while True:
            record = source.read(RECORD.size)
            if not record:
                break
            if len(record) != RECORD.size:
                raise SystemExit(f"TRUNCATED_NORMALIZED_RECORD_{symbol}")
            server_msc, _, _ = RECORD.unpack(record)
            name = day_name(server_msc)
            if name != current_day:
                if handle is not None:
                    handle.close()
                handle = (destination / f"{name}.bin").open("ab")
                current_day = name
            handle.write(record)
            count += 1
    if handle is not None:
        handle.close()
    files = list(destination.glob("*.bin"))
    if len(files) != 2557 or sum(path.stat().st_size for path in files) != count * RECORD.size:
        raise SystemExit(f"V31_IMPORT_STAGING_INVALID_{symbol}")
    return destination, count, len(files)


def run_symbol(symbol: str, expected: int, sequence: int) -> dict:
    destination = OUT / symbol
    runtime = RUNTIME_ROOT / symbol
    if destination.exists() or runtime.exists():
        raise SystemExit(f"REFUSE_EXISTING_V31_IMPORT_OUTPUT_{symbol}")
    destination.mkdir(parents=True)
    relative_import = f"SolTrade\\Phase6\\V31ExternalImport\\{symbol}"
    relative_output = f"SolTrade\\Phase6\\V31ExternalImportEvidence\\{symbol}"
    control = IMPORT_ROOT / "control.csv"
    control.write_text(f"SOLTRADE_PHASE6_V31_IMPORT_CONTROL_V1,{symbol},{relative_import},{relative_output},{expected}\n")
    config = WORK / f"external-import-{symbol}.ini"
    config.write_text("""[Common]
KeepPrivate=1
NewsEnable=0
CertInstall=0

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=0
Account=0
Profile=0

[StartUp]
Symbol=EURUSD
Period=M1
Expert=SolTradeV31ExternalTickImporter
""")
    (destination / "terminal-config.ini").write_text(config.read_text())
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v31-external\\external-import-{symbol}.ini", "/portable"],
        cwd=ROOT,
        env=dict(os.environ, WINEPREFIX=str(PREFIX)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10800,
    )
    elapsed = time.time() - started
    (destination / "terminal-stdout.log").write_bytes(proc.stdout)
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    logs = sorted((TERMINAL / "logs").glob("*.log"), key=lambda path: path.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], destination / "terminal-journal.log")
    summary_path = destination / "import-summary.csv"
    summary = pairs(summary_path) if summary_path.exists() else {}
    valid = (
        proc.returncode == 0
        and summary.get("status") == "PASS"
        and int(summary.get("expected_ticks", 0)) == expected
        and int(summary.get("source_records", 0)) == expected
        and int(summary.get("imported_ticks", 0)) == expected
        and int(summary.get("reloaded_ticks", 0)) == expected
        and int(summary.get("exact_timestamp_bid_ask_mismatches", -1)) == 0
        and int(summary.get("property_or_session_mismatches", -1)) == 0
        and summary.get("orders") == "0"
        and summary.get("positions") == "0"
        and summary.get("trade_api_calls") == "NONE"
        and summary.get("pnl_calculated") == "NO"
    )
    status = {
        "schema": "SOLTRADE_PHASE6_V31_MT5_IMPORT_RUN_STATUS_V1",
        "status": "PASS" if valid else "FAIL",
        "run_sequence": sequence,
        "canonical_symbol": symbol,
        "research_symbol": symbol + ".V31",
        "expected_ticks": expected,
        "imported_ticks": int(summary.get("imported_ticks", 0)),
        "reloaded_ticks": int(summary.get("reloaded_ticks", 0)),
        "exact_timestamp_bid_ask_mismatches": int(summary.get("exact_timestamp_bid_ask_mismatches", -1)),
        "property_or_session_mismatches": int(summary.get("property_or_session_mismatches", -1)),
        "wine_return_code": proc.returncode,
        "elapsed_seconds": elapsed,
        "orders_or_positions": 0,
        "pnl_calculated": False,
    }
    (destination / "run-status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(f"V31_MT5_IMPORT {sequence}/7 {symbol} {status['status']} ticks={status['imported_ticks']} elapsed={elapsed:.1f}s", flush=True)
    if not valid:
        raise SystemExit(f"V31_MT5_IMPORT_FAILED_RETAINED_{symbol}")
    return status


def main() -> None:
    if EX5_SHA256.startswith("TO_BE_") or sha(EX5) != EX5_SHA256:
        raise SystemExit("V31_EXTERNAL_IMPORT_EXECUTABLE_HASH_MISMATCH")
    if OUT.exists():
        raise SystemExit("REFUSE_EXISTING_V31_IMPORT_OUTPUT_ROOT")
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("status") != "PASS":
        raise SystemExit("V31_NORMALIZED_MANIFEST_NOT_PASS")
    OUT.mkdir(parents=True)
    IMPORT_ROOT.mkdir(parents=True, exist_ok=True)
    if RUNTIME_ROOT.exists():
        shutil.rmtree(RUNTIME_ROOT)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV31ExternalTickImporter.ex5")
    statuses = []
    for sequence, symbol in enumerate(SYMBOLS, 1):
        normalized = Path(manifest["symbols"][symbol]["path"])
        expected = int(manifest["symbols"][symbol]["record_count"])
        staged, count, day_files = stage(symbol, normalized)
        stage_status = {"schema": "SOLTRADE_PHASE6_V31_IMPORT_STAGING_V1", "symbol": symbol, "records": count, "day_files": day_files, "status": "PASS" if count == expected else "FAIL"}
        if count != expected:
            raise SystemExit(f"V31_IMPORT_STAGING_COUNT_MISMATCH_{symbol}")
        statuses.append(run_symbol(symbol, expected, sequence))
        (OUT / symbol / "staging-status.json").write_text(json.dumps(stage_status, indent=2) + "\n")
        shutil.rmtree(staged)
    control = IMPORT_ROOT / "control.csv"
    if control.exists():
        control.unlink()
    aggregate = {
        "schema": "SOLTRADE_PHASE6_V31_MT5_IMPORT_AGGREGATE_V1",
        "status": "PASS" if len(statuses) == 7 and all(item["status"] == "PASS" for item in statuses) else "FAIL",
        "symbols": statuses,
        "total_imported_ticks": sum(item["imported_ticks"] for item in statuses),
        "total_reloaded_ticks": sum(item["reloaded_ticks"] for item in statuses),
        "exact_timestamp_bid_ask_mismatches": sum(item["exact_timestamp_bid_ask_mismatches"] for item in statuses),
        "orders_or_positions": 0,
        "pnl_calculated": False,
    }
    (OUT / "aggregate-status.json").write_text(json.dumps(aggregate, indent=2) + "\n")
    print(json.dumps(aggregate, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
