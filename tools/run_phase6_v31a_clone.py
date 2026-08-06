#!/usr/bin/env python3
"""Create and exactly audit V31A FP Markets custom-symbol clones without trading."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence/fpmarkets-clone"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31a"
RUNTIME = COMMON / "SolTrade/Phase6/V31AClone"
SOURCE = ROOT / "research/factor_momentum/SolTradeV31AFPTickClone.mq5"
EX5 = WORK / "SolTradeV31AFPTickClone.ex5"
FROZEN_SOURCE_SHA256 = "fd844e469f213aac8f7f64bcc8334ac2850ae86619cfa442c0b140fa09b91a5d"
FROZEN_EX5_SHA256 = "5c61fd0c80120f812f6b0a4b1b293320b31ee4a3a749bff52bb00c3bf0aba36b"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if sha(SOURCE) != FROZEN_SOURCE_SHA256 or sha(EX5) != FROZEN_EX5_SHA256:
        raise SystemExit("V31A_CLONE_EXECUTABLE_HASH_MISMATCH")
    if OUT.exists() or RUNTIME.exists():
        raise SystemExit("REFUSE_EXISTING_V31A_CLONE_OUTPUT")
    OUT.mkdir(parents=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV31AFPTickClone.ex5")
    config = WORK / "clone.ini"
    config.write_text("""[Common]\nKeepPrivate=1\nNewsEnable=0\nCertInstall=0\n\n[Experts]\nAllowLiveTrading=0\nAllowDllImport=0\nEnabled=0\nAccount=0\nProfile=0\n\n[StartUp]\nSymbol=EURUSD\nPeriod=M1\nExpert=SolTradeV31AFPTickClone\n""")
    (OUT / "terminal-config.ini").write_text(config.read_text())
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), "/config:C:\\v31a\\clone.ini", "/portable"],
        cwd=ROOT,
        env=dict(os.environ, WINEPREFIX=str(PREFIX)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=7200,
    )
    elapsed = time.time() - started
    (OUT / "terminal-stdout.log").write_bytes(proc.stdout)
    if RUNTIME.exists():
        for artifact in RUNTIME.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, OUT / artifact.name)
    logs = sorted((TERMINAL / "logs").glob("*.log"), key=lambda path: path.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], OUT / "terminal-journal.log")
    shutil.copy2(WORK / "clone-compile.log", OUT / "clone-compile.log")
    summary_path = OUT / "clone-summary.csv"
    rows = list(csv.DictReader(summary_path.open())) if summary_path.exists() else []
    valid = (
        proc.returncode == 0
        and len(rows) == 7
        and all(row["status"] == "PASS" for row in rows)
        and all(int(row["source_ticks"]) == int(row["imported_ticks"]) == int(row["reloaded_ticks"]) for row in rows)
        and all(int(row["exact_tick_mismatches"]) == 0 for row in rows)
        and all(int(row["property_or_session_mismatches"]) == 0 for row in rows)
        and all(row["trade_api_calls"] == "NONE" and row["pnl_calculated"] == "NO" for row in rows)
    )
    status = {
        "schema": "SOLTRADE_PHASE6_V31A_FP_MARKETS_CLONE_STATUS_V1",
        "status": "PASS" if valid else "FAIL",
        "elapsed_seconds": elapsed,
        "wine_return_code": proc.returncode,
        "symbols": len(rows),
        "source_ticks": sum(int(row["source_ticks"]) for row in rows),
        "imported_ticks": sum(int(row["imported_ticks"]) for row in rows),
        "reloaded_ticks": sum(int(row["reloaded_ticks"]) for row in rows),
        "exact_tick_mismatches": sum(int(row["exact_tick_mismatches"]) for row in rows),
        "property_or_session_mismatches": sum(int(row["property_or_session_mismatches"]) for row in rows),
        "warmup_m1_rates": sum(int(row["warmup_m1_rates"]) for row in rows),
        "orders_or_positions": 0,
        "trade_api_calls": "NONE",
        "pnl_calculated": False,
        "external_data_downloaded": False,
    }
    (OUT / "clone-status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2), flush=True)
    if not valid:
        raise SystemExit("V31A_CLONE_FAILED_RETAINED")


if __name__ == "__main__":
    main()
