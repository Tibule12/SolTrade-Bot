#!/usr/bin/env python3
"""Run no-trade MT5 qualification over the imported V31 custom symbols."""
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
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2/data-qualification/physical-runs"
MANIFEST = Path("/home/tibule12/Datasets/SolTrade/V31/manifests/v31-normalized-data-manifest.json")
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31-external"
REPORTS = TERMINAL / "v31-external/reports"
EX5 = WORK / "SolTradeV31ExternalQualificationHarness.ex5"
EX5_SHA256 = "fd91da3d01a7a9a7762b50fc85ca142e247f73995859fb75903b02e57cd02bd8"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def config(symbol: str, expected: int, port: int) -> str:
    return f"""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0
Account=0
Profile=0

[Tester]
Expert=SolTradeV31ExternalQualificationHarness
Symbol={symbol}.V31
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode=0
Optimization=0
ForwardMode=0
FromDate=2018.01.01
ToDate=2025.01.01
Visual=0
UseCloud=0
Port={port}
Report=v31-external\\reports\\qualification-{symbol}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
DataFrom=2018.01.01 00:00:00
EligibleFrom=2018.02.05 10:05:00
BoundTo=2025.01.01 00:00:00
ExpectedTicks={expected}
CanonicalSymbol={symbol}
OutputRoot=SolTrade\\Phase6\\V31ExternalQualification\\{symbol}
"""


def main() -> None:
    if sha(EX5) != EX5_SHA256:
        raise SystemExit("V31_EXTERNAL_QUALIFICATION_EXECUTABLE_HASH_MISMATCH")
    if OUT.exists():
        raise SystemExit("REFUSE_EXISTING_V31_QUALIFICATION_OUTPUT")
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get("status") != "PASS":
        raise SystemExit("V31_NORMALIZED_MANIFEST_NOT_PASS")
    OUT.mkdir(parents=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV31ExternalQualificationHarness.ex5")
    results = []
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    for index, symbol in enumerate(SYMBOLS, 1):
        expected = int(manifest["symbols"][symbol]["record_count"])
        destination = OUT / symbol
        runtime = COMMON / "SolTrade/Phase6/V31ExternalQualification" / symbol
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_EXISTING_V31_QUALIFICATION_{symbol}")
        destination.mkdir()
        ini = WORK / f"external-qualification-{symbol}.ini"
        ini.write_text(config(symbol, expected, 4300 + index))
        (destination / "strategy-tester.ini").write_text(ini.read_text())
        for old in REPORTS.glob("qualification-" + symbol + "*"):
            if old.is_file():
                old.unlink()
        started = time.time()
        proc = subprocess.run(
            ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v31-external\\external-qualification-{symbol}.ini", "/portable"],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10800,
        )
        elapsed = time.time() - started
        (destination / "terminal-stdout.log").write_bytes(proc.stdout)
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        native = []
        prefix = "qualification-" + symbol
        for artifact in REPORTS.glob(prefix + "*"):
            if artifact.is_file():
                name = "native-mt5-report" + artifact.name[len(prefix):]
                shutil.copy2(artifact, destination / name)
                native.append(name)
        agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{4300 + index}"
        logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
        if logs:
            shutil.copy2(logs[-1], destination / "tester-agent.log")
        summary_path = destination / "qualification-summary.csv"
        summary = pairs(summary_path) if summary_path.exists() else {}
        log_text = (destination / "tester-agent.log").read_text(errors="replace") if (destination / "tester-agent.log").exists() else ""
        lower_log = log_text.lower()
        real_tick_model_confirmed = "generating based on real ticks" in lower_log
        generated_fallback = "real ticks absent" in lower_log or "every tick generation used" in lower_log or "generated tick fallback" in lower_log
        technically_valid = proc.returncode == 0 and summary.get("orders_or_positions") == "ZERO" and summary.get("pnl_calculated") == "NO" and native and (destination / "tester-agent.log").exists()
        status = "PASS" if technically_valid and summary.get("status") == "PASS" and real_tick_model_confirmed and not generated_fallback else ("DATA_FAIL" if technically_valid else "TECHNICAL_FAIL")
        record = {
            "schema": "SOLTRADE_PHASE6_V31_QUALIFICATION_RUN_STATUS_V1",
            "symbol": symbol,
            "research_symbol": symbol + ".V31",
            "model": "EVERY_TICK_BASED_ON_REAL_TICKS",
            "model_code": 4,
            "optimization": False,
            "elapsed_seconds": elapsed,
            "wine_return_code": proc.returncode,
            "expected_tick_count": expected,
            "tick_count": int(summary.get("tick_count", 0)),
            "first_tick": summary.get("first_tick"),
            "final_tick": summary.get("final_tick"),
            "h1_bars_before_eligible": int(summary.get("h1_bars_before_eligible", 0)),
            "m1_mismatches": int(summary.get("m1_mismatches", -1)),
            "h1_mismatches": int(summary.get("h1_mismatches", -1)),
            "generated_tick_fallback_detected": generated_fallback,
            "real_tick_model_confirmed": real_tick_model_confirmed,
            "orders_or_positions": summary.get("orders_or_positions"),
            "pnl_calculated": summary.get("pnl_calculated"),
            "native_reports": native,
            "status": status,
        }
        (destination / "qualification-run-status.json").write_text(json.dumps(record, indent=2) + "\n")
        results.append(record)
        print(f"V31_QUALIFY {index}/7 {symbol} {status} ticks={record['tick_count']} elapsed={elapsed:.1f}s", flush=True)
        if status != "PASS":
            raise SystemExit(f"V31_QUALIFICATION_FAILED_RETAINED_{symbol}")
    inventory = {
        "schema": "SOLTRADE_PHASE6_V31_QUALIFICATION_PHYSICAL_INVENTORY_V1",
        "status": "PASS" if len(results) == 7 and all(record["status"] == "PASS" for record in results) else "FAIL",
        "runs": results,
        "historical_pnl_viewed": False,
        "orders_or_positions": 0,
    }
    (OUT.parent / "qualification-physical-run-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")


if __name__ == "__main__":
    main()
