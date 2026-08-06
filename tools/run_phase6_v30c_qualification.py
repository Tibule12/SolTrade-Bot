#!/usr/bin/env python3
"""Run the frozen V30C exact-window no-trade native-history qualification."""
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
PHASE = ROOT / "reports/backtests/phase6-v30c-v28-native-contiguous-replication"
OUT = PHASE / "data-qualification/physical-runs"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v30c"
REPORTS = TERMINAL / "v30c/reports"
EX5 = WORK / "SolTradeV30CRealTickQualificationHarness.ex5"
FROZEN_EX5_SHA256 = "355dfc759d14c87228c1283431fa428a3d35903b1bf42d1b15cb7ebddbc8a0b6"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def config(symbol: str, port: int) -> str:
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeV30CRealTickQualificationHarness\nSymbol={symbol}\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate=2022.11.14\nToDate=2024.01.01\nVisual=0\nUseCloud=0\nPort={port}\nReport=v30c\\reports\\qualification-{symbol}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nOutputRoot=SolTrade\\Phase6\\V30CQualification\\{symbol}\n"""


def main() -> None:
    if sha(EX5) != FROZEN_EX5_SHA256:
        raise SystemExit("FROZEN_V30C_QUALIFICATION_EXECUTABLE_HASH_MISMATCH")
    if (ROOT / ".git/index.lock").exists():
        raise SystemExit("GIT_INDEX_LOCK_PRESENT")
    OUT.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV30CRealTickQualificationHarness.ex5")
    results = []
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    for index, symbol in enumerate(SYMBOLS, 1):
        destination = OUT / symbol
        runtime = COMMON / "SolTrade/Phase6/V30CQualification" / symbol
        existing = destination / "qualification-run-status.json"
        if existing.exists():
            record = json.loads(existing.read_text())
            results.append(record)
            print(f"V30C_QUALIFY {index}/7 {symbol} RETAINED {record['status']} ticks={record['processed_tick_count']}", flush=True)
            continue
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_INCOMPLETE_EXISTING_QUALIFICATION {symbol}")
        destination.mkdir(parents=True)
        ini = WORK / f"qualification-{symbol}.ini"
        ini.write_text(config(symbol, 3900 + index))
        (destination / "strategy-tester.ini").write_text(ini.read_text())
        for old in REPORTS.glob("qualification-" + symbol + "*"):
            if old.is_file():
                old.unlink()
        started = time.time()
        proc = subprocess.run(
            ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v30c\\qualification-{symbol}.ini", "/portable"],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=7200,
        )
        elapsed = time.time() - started
        (destination / "terminal-stdout.log").write_bytes(proc.stdout)
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        native = []
        report_prefix = "qualification-" + symbol
        for artifact in REPORTS.glob(report_prefix + "*"):
            if artifact.is_file():
                name = "native-mt5-report" + artifact.name[len(report_prefix):]
                shutil.copy2(artifact, destination / name)
                native.append(name)
        agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{3900 + index}"
        logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
        if logs:
            shutil.copy2(logs[-1], destination / "tester-agent.log")
        summary_path = destination / "qualification-summary.csv"
        summary = pairs(summary_path) if summary_path.exists() else {}
        technically_valid = (
            proc.returncode == 0
            and summary.get("orders_or_positions") == "ZERO"
            and summary.get("pnl_calculated") == "NO"
            and bool(native)
            and (destination / "tester-agent.log").exists()
        )
        status = "PASS" if technically_valid and summary.get("local_status") == "PASS" else ("DATA_FAIL" if technically_valid else "TECHNICAL_FAIL")
        record = {
            "schema": "SOLTRADE_PHASE6_V30C_QUALIFICATION_RUN_STATUS_V1",
            "symbol": symbol,
            "model": "EVERY_TICK_BASED_ON_REAL_TICKS",
            "model_code": 4,
            "execution_mode": 0,
            "optimization": False,
            "elapsed_seconds": elapsed,
            "wine_return_code": proc.returncode,
            "processed_tick_count": int(summary.get("processed_tick_count", "0")),
            "first_processed_tick": summary.get("first_processed_tick"),
            "final_processed_tick": summary.get("final_processed_tick"),
            "m1_mismatches": int(summary.get("m1_mismatches", "-1")),
            "h1_mismatches": int(summary.get("h1_mismatches", "-1")),
            "orders_or_positions": summary.get("orders_or_positions"),
            "pnl_calculated": summary.get("pnl_calculated"),
            "native_reports": sorted(native),
            "status": status,
        }
        (destination / "qualification-run-status.json").write_text(json.dumps(record, indent=2) + "\n")
        results.append(record)
        print(f"V30C_QUALIFY {index}/7 {symbol} {status} ticks={record['processed_tick_count']} elapsed={elapsed:.2f}s", flush=True)
    inventory_status = "PASS" if all(record["status"] == "PASS" for record in results) else ("TECHNICAL_FAIL" if any(record["status"] == "TECHNICAL_FAIL" for record in results) else "DATA_FAIL")
    (PHASE / "data-qualification/qualification-physical-run-inventory.json").write_text(json.dumps({
        "schema": "SOLTRADE_PHASE6_V30C_QUALIFICATION_PHYSICAL_INVENTORY_V1",
        "status": inventory_status,
        "runs": results,
        "historical_pnl_viewed": False,
        "orders_or_positions": 0,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
